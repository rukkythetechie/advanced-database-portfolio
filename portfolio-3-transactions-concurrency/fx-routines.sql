-- Corridor Pay: controlled internal currency conversion
-- Install after ledger-routines.sql.
-- Rates are supplied through saved quotes.
-- No external FX trade or bank settlement is performed.

-- Saved quote terms cannot be edited or deleted.
CREATE OR REPLACE FUNCTION guard_fx_quote()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'Saved FX quotes cannot be changed or deleted';
END;
$$;

CREATE TRIGGER fx_quote_guard
BEFORE UPDATE OR DELETE ON fx_quote
FOR EACH ROW
EXECUTE FUNCTION guard_fx_quote();


CREATE OR REPLACE FUNCTION execute_fx_quote(
    p_quote_id BIGINT,
    p_source_wallet_id BIGINT,
    p_target_wallet_id BIGINT,
    p_actor_user_id BIGINT,
    p_source_fx_account_id BIGINT,
    p_target_fx_account_id BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_quote public.fx_quote%ROWTYPE;
    v_source public.wallet%ROWTYPE;
    v_target public.wallet%ROWTYPE;
    v_source_wallet_account BIGINT;
    v_target_wallet_account BIGINT;
    v_target_amount NUMERIC(20, 2);
    v_transaction_id BIGINT;
    v_conversion_id BIGINT;
BEGIN
    -- Serialize attempts to accept the same quote.
    SELECT *
    INTO v_quote
    FROM public.fx_quote
    WHERE quote_id = p_quote_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'FX quote does not exist';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.fx_conversion
        WHERE quote_id = p_quote_id
    ) THEN
        RAISE EXCEPTION 'FX quote has already been used';
    END IF;

    PERFORM u.user_id
    FROM public.business_user u
    JOIN public.business b ON b.business_id = u.business_id
    WHERE u.user_id = p_actor_user_id
      AND u.business_id = v_quote.business_id
      AND u.is_active
      AND u.role IN ('admin', 'finance')
      AND b.kyb_status = 'approved'
    FOR SHARE OF u, b;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Conversion requires an active admin or finance user from the approved quote business';
    END IF;

    IF p_source_wallet_id = p_target_wallet_id THEN
        RAISE EXCEPTION 'Conversion requires two different wallets';
    END IF;

    SELECT *
    INTO v_source
    FROM public.wallet
    WHERE wallet_id = p_source_wallet_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source wallet does not exist';
    END IF;

    SELECT *
    INTO v_target
    FROM public.wallet
    WHERE wallet_id = p_target_wallet_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target wallet does not exist';
    END IF;

    IF v_source.business_id <> v_quote.business_id
       OR v_target.business_id <> v_quote.business_id THEN
        RAISE EXCEPTION
            'Both wallets must belong to the quote business';
    END IF;

    IF v_source.currency_code <> v_quote.source_currency
       OR v_target.currency_code <> v_quote.target_currency THEN
        RAISE EXCEPTION 'Wallet currencies must match the FX quote';
    END IF;

    SELECT ledger_account_id
    INTO v_source_wallet_account
    FROM public.ledger_account
    WHERE wallet_id = p_source_wallet_id
      AND account_type = 'liability'
      AND currency_code = v_quote.source_currency;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Source wallet needs a matching liability account';
    END IF;

    SELECT ledger_account_id
    INTO v_target_wallet_account
    FROM public.ledger_account
    WHERE wallet_id = p_target_wallet_id
      AND account_type = 'liability'
      AND currency_code = v_quote.target_currency;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Target wallet needs a matching liability account';
    END IF;

    -- Stabilize all four accounts in a consistent order.
    PERFORM ledger_account_id
    FROM public.ledger_account
    WHERE ledger_account_id IN (
        v_source_wallet_account,
        v_target_wallet_account,
        p_source_fx_account_id,
        p_target_fx_account_id
    )
    ORDER BY ledger_account_id
    FOR SHARE;

    IF NOT EXISTS (
        SELECT 1
        FROM public.ledger_account
        WHERE ledger_account_id = p_source_fx_account_id
          AND wallet_id IS NULL
          AND account_type = 'asset'
          AND currency_code = v_quote.source_currency
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.ledger_account
        WHERE ledger_account_id = p_target_fx_account_id
          AND wallet_id IS NULL
          AND account_type = 'asset'
          AND currency_code = v_quote.target_currency
    ) THEN
        RAISE EXCEPTION
            'FX accounts must be platform assets matching the quote currencies';
    END IF;

    -- Lock both wallets in ascending ID order.
    PERFORM wallet_id
    FROM public.wallet
    WHERE wallet_id IN (
        p_source_wallet_id, p_target_wallet_id
    )
    ORDER BY wallet_id
    FOR NO KEY UPDATE;

    -- Check real elapsed time after any lock wait.
    IF clock_timestamp() >= v_quote.expires_at THEN
        RAISE EXCEPTION 'FX quote has expired';
    END IF;

    v_target_amount := ROUND(
        v_quote.source_amount * v_quote.exchange_rate, 2
    );

    IF v_target_amount <= 0 THEN
        RAISE EXCEPTION 'Rounded target amount must be positive';
    END IF;

    INSERT INTO public.ledger_transaction (
        transaction_type, description
    )
    VALUES (
        'fx_conversion', 'Simulated internal currency conversion'
    )
    RETURNING ledger_transaction_id INTO v_transaction_id;

    -- Each currency balances independently.
    INSERT INTO public.ledger_entry (
        ledger_transaction_id, ledger_account_id,
        entry_type, amount
    )
    VALUES
        (v_transaction_id, v_source_wallet_account,
         'debit', v_quote.source_amount),
        (v_transaction_id, p_source_fx_account_id,
         'credit', v_quote.source_amount),
        (v_transaction_id, p_target_fx_account_id,
         'debit', v_target_amount),
        (v_transaction_id, v_target_wallet_account,
         'credit', v_target_amount);

    -- Rechecks funds and applies both wallet changes atomically.
    PERFORM public.post_ledger_transaction(v_transaction_id);

    INSERT INTO public.fx_conversion (
        quote_id, business_id, source_wallet_id,
        target_wallet_id, initiated_by, target_amount,
        ledger_transaction_id, completed_at
    )
    VALUES (
        p_quote_id, v_quote.business_id,
        p_source_wallet_id, p_target_wallet_id,
        p_actor_user_id, v_target_amount,
        v_transaction_id, clock_timestamp()
    )
    RETURNING conversion_id INTO v_conversion_id;

    INSERT INTO public.audit_event (
        business_id, actor_type, actor_user_id,
        action, entity_type, entity_id, outcome, details
    )
    VALUES (
        v_quote.business_id, 'user', p_actor_user_id,
        'execute_fx_quote', 'fx_conversion',
        v_conversion_id, 'success',
        jsonb_build_object(
            'quote_id', p_quote_id,
            'source_currency', v_quote.source_currency,
            'source_amount', v_quote.source_amount,
            'target_currency', v_quote.target_currency,
            'target_amount', v_target_amount,
            'exchange_rate', v_quote.exchange_rate,
            'ledger_transaction_id', v_transaction_id,
            'simulated', TRUE
        )
    );

    RETURN v_conversion_id;
END;
$$;