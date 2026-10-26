-- Corridor Pay: simulated payment settlement
-- Install after payment-routines.sql.
-- No real bank transfer is performed.

CREATE UNIQUE INDEX payment_settlement_posting_unique
ON ledger_transaction (payment_id)
WHERE transaction_type = 'payout_settlement';


CREATE OR REPLACE FUNCTION settle_payment(
    p_payment_id BIGINT,
    p_actor_user_id BIGINT,
    p_cash_account_id BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_payment public.payment%ROWTYPE;
    v_processing_id BIGINT;
    v_wallet_account_id BIGINT;
    v_clearing_account_id BIGINT;
    v_currency TEXT;
    v_settlement_id BIGINT;
BEGIN
    SELECT *
    INTO v_payment
    FROM public.payment
    WHERE payment_id = p_payment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment does not exist';
    END IF;

    IF v_payment.status <> 'processing' THEN
        RAISE EXCEPTION
            'Only a processing payment can be settled';
    END IF;

    -- Validate the actor and keep permission data stable.
    PERFORM u.user_id
    FROM public.business_user u
    JOIN public.business b ON b.business_id = u.business_id
    WHERE u.user_id = p_actor_user_id
      AND u.business_id = v_payment.business_id
      AND u.is_active
      AND u.role IN ('admin', 'finance')
      AND b.kyb_status = 'approved'
    FOR SHARE OF u, b;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Settlement requires an active admin or finance user from the approved business';
    END IF;

    SELECT a.ledger_account_id, w.currency_code
    INTO v_wallet_account_id, v_currency
    FROM public.wallet w
    JOIN public.ledger_account a ON a.wallet_id = w.wallet_id
    WHERE w.wallet_id = v_payment.wallet_id
      AND w.business_id = v_payment.business_id
      AND a.account_type = 'liability'
      AND a.currency_code = w.currency_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Matching wallet account was not found';
    END IF;

    SELECT ledger_transaction_id
    INTO v_processing_id
    FROM public.ledger_transaction
    WHERE payment_id = p_payment_id
      AND transaction_type = 'payout_processing'
      AND status = 'posted'
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'A posted processing transaction is required';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.ledger_transaction
        WHERE reversal_of_transaction_id = v_processing_id
    ) THEN
        RAISE EXCEPTION 'The processing transaction has a reversal';
    END IF;

    -- Identify the clearing account from the original posting.
    SELECT a.ledger_account_id
    INTO v_clearing_account_id
    FROM public.ledger_entry e
    JOIN public.ledger_account a
      ON a.ledger_account_id = e.ledger_account_id
    WHERE e.ledger_transaction_id = v_processing_id
      AND e.entry_type = 'credit'
      AND e.amount = v_payment.amount
      AND a.wallet_id IS NULL
      AND a.account_type = 'liability'
      AND a.currency_code = v_currency;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Matching processing clearing entry was not found';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.ledger_entry
        WHERE ledger_transaction_id = v_processing_id
    ) <> 2 OR NOT EXISTS (
        SELECT 1
        FROM public.ledger_entry
        WHERE ledger_transaction_id = v_processing_id
          AND ledger_account_id = v_wallet_account_id
          AND entry_type = 'debit'
          AND amount = v_payment.amount
    ) THEN
        RAISE EXCEPTION 'Processing entries do not match this payment';
    END IF;

    PERFORM ledger_account_id
    FROM public.ledger_account
    WHERE ledger_account_id = p_cash_account_id
      AND wallet_id IS NULL
      AND account_type = 'asset'
      AND currency_code = v_currency
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Settlement requires a platform cash asset account in the payment currency';
    END IF;

    INSERT INTO public.ledger_transaction (
        transaction_type, description, payment_id
    )
    VALUES (
        'payout_settlement',
        'Simulated supplier payment settlement',
        p_payment_id
    )
    RETURNING ledger_transaction_id INTO v_settlement_id;

    -- Clear the payout liability and reduce platform cash.
    -- The customer wallet was already debited during processing.
    INSERT INTO public.ledger_entry (
        ledger_transaction_id, ledger_account_id,
        entry_type, amount
    )
    VALUES
        (v_settlement_id, v_clearing_account_id,
         'debit', v_payment.amount),
        (v_settlement_id, p_cash_account_id,
         'credit', v_payment.amount);

    PERFORM public.post_ledger_transaction(v_settlement_id);

    UPDATE public.payment
    SET status = 'completed',
        completed_at = clock_timestamp()
    WHERE payment_id = p_payment_id;

    INSERT INTO public.payment_status_history (
        payment_id, from_status, to_status,
        actor_type, changed_by, reason, ledger_transaction_id
    )
    VALUES (
        p_payment_id, 'processing', 'completed',
        'user', p_actor_user_id,
        'Simulated settlement recorded',
        v_settlement_id
    );

    INSERT INTO public.audit_event (
        business_id, actor_type, actor_user_id,
        action, entity_type, entity_id, outcome, details
    )
    VALUES (
        v_payment.business_id, 'user', p_actor_user_id,
        'settle_payment', 'payment', p_payment_id, 'success',
        jsonb_build_object(
            'amount', v_payment.amount,
            'currency', v_currency,
            'ledger_transaction_id', v_settlement_id,
            'simulated', TRUE
        )
    );

    RETURN v_settlement_id;
END;
$$;