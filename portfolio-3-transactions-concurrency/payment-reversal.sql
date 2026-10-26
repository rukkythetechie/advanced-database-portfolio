-- Corridor Pay: full simulated payment reversals
-- Requires payment-routines.sql and payment-settlement.sql.
-- No real bank refund is performed.
-- A completed-payment reversal represents a confirmed
-- simulated return of funds.

CREATE OR REPLACE FUNCTION reverse_payment(
    p_payment_id BIGINT,
    p_actor_user_id BIGINT,
    p_reason TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_payment public.payment%ROWTYPE;
    v_processing_id BIGINT;
    v_settlement_id BIGINT;
    v_wallet_account_id BIGINT;
    v_clearing_id BIGINT;
    v_currency TEXT;
    v_original RECORD;
    v_reversal_id BIGINT;
    v_processing_reversal_id BIGINT;
    v_reversal_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_from_status TEXT;
BEGIN
    IF p_reason IS NULL OR LENGTH(BTRIM(p_reason)) = 0 THEN
        RAISE EXCEPTION 'A reversal reason is required';
    END IF;

    SELECT *
    INTO v_payment
    FROM public.payment
    WHERE payment_id = p_payment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment does not exist';
    END IF;

    IF v_payment.status NOT IN (
        'processing', 'failed', 'completed'
    ) THEN
        RAISE EXCEPTION
            'Only a deducted processing, failed or completed payment can be reversed';
    END IF;

    -- Refunds require an active authorized user.
    -- Business approval is not required to return deducted funds.
    PERFORM user_id
    FROM public.business_user
    WHERE user_id = p_actor_user_id
      AND business_id = v_payment.business_id
      AND is_active
      AND role IN ('admin', 'finance')
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Reversal requires an active admin or finance user from the payment business';
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
        RAISE EXCEPTION
            'No posted wallet deduction exists for this payment';
    END IF;

    SELECT a.ledger_account_id
    INTO v_clearing_id
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

    IF v_payment.status = 'completed' THEN
        SELECT ledger_transaction_id
        INTO v_settlement_id
        FROM public.ledger_transaction
        WHERE payment_id = p_payment_id
          AND transaction_type = 'payout_settlement'
          AND status = 'posted'
        FOR SHARE;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Completed payment requires a posted settlement';
        END IF;

        IF (
            SELECT COUNT(*)
            FROM public.ledger_entry
            WHERE ledger_transaction_id = v_settlement_id
        ) <> 2 OR NOT EXISTS (
            SELECT 1
            FROM public.ledger_entry
            WHERE ledger_transaction_id = v_settlement_id
              AND ledger_account_id = v_clearing_id
              AND entry_type = 'debit'
              AND amount = v_payment.amount
        ) OR NOT EXISTS (
            SELECT 1
            FROM public.ledger_entry e
            JOIN public.ledger_account a
              ON a.ledger_account_id = e.ledger_account_id
            WHERE e.ledger_transaction_id = v_settlement_id
              AND e.entry_type = 'credit'
              AND e.amount = v_payment.amount
              AND a.wallet_id IS NULL
              AND a.account_type = 'asset'
              AND a.currency_code = v_currency
        ) THEN
            RAISE EXCEPTION 'Settlement entries do not match this payment';
        END IF;
    ELSE
        IF EXISTS (
            SELECT 1
            FROM public.ledger_transaction
            WHERE payment_id = p_payment_id
              AND transaction_type = 'payout_settlement'
        ) THEN
            RAISE EXCEPTION
                'Unexpected settlement exists for an uncompleted payment';
        END IF;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.ledger_transaction
        WHERE reversal_of_transaction_id IN (
            v_processing_id, v_settlement_id
        )
    ) THEN
        RAISE EXCEPTION
            'An original posting already has a reversal';
    END IF;

    v_from_status := v_payment.status;

    -- Record processing failure before refunding its deduction.
    IF v_payment.status = 'processing' THEN
        UPDATE public.payment
        SET status = 'failed'
        WHERE payment_id = p_payment_id;

        INSERT INTO public.payment_status_history (
            payment_id, from_status, to_status,
            actor_type, changed_by, reason
        )
        VALUES (
            p_payment_id, 'processing', 'failed',
            'user', p_actor_user_id, BTRIM(p_reason)
        );

        v_from_status := 'failed';
    END IF;

    -- Completed payments require two compensating postings:
    -- first undo settlement, then undo the wallet deduction.
    -- An unsettled deducted payment needs only the second.
    FOR v_original IN
        SELECT ledger_transaction_id, transaction_type
        FROM public.ledger_transaction
        WHERE ledger_transaction_id IN (
            v_processing_id, v_settlement_id
        )
        ORDER BY CASE transaction_type
            WHEN 'payout_settlement' THEN 0
            ELSE 1
        END
    LOOP
        INSERT INTO public.ledger_transaction (
            transaction_type, description, payment_id,
            reversal_of_transaction_id
        )
        VALUES (
            'reversal', 'Full simulated payment reversal',
            p_payment_id, v_original.ledger_transaction_id
        )
        RETURNING ledger_transaction_id INTO v_reversal_id;

        INSERT INTO public.ledger_entry (
            ledger_transaction_id, ledger_account_id,
            entry_type, amount
        )
        SELECT
            v_reversal_id,
            ledger_account_id,
            CASE entry_type
                WHEN 'debit' THEN 'credit'
                ELSE 'debit'
            END,
            amount
        FROM public.ledger_entry
        WHERE ledger_transaction_id =
              v_original.ledger_transaction_id;

        PERFORM public.post_ledger_transaction(v_reversal_id);

        v_reversal_ids := array_append(
            v_reversal_ids, v_reversal_id
        );

        IF v_original.transaction_type = 'payout_processing' THEN
            v_processing_reversal_id := v_reversal_id;
        END IF;
    END LOOP;

    -- Preserve any original completion timestamp.
    UPDATE public.payment
    SET status = 'reversed'
    WHERE payment_id = p_payment_id;

    INSERT INTO public.payment_status_history (
        payment_id, from_status, to_status,
        actor_type, changed_by, reason, ledger_transaction_id
    )
    VALUES (
        p_payment_id, v_from_status, 'reversed',
        'user', p_actor_user_id, BTRIM(p_reason),
        v_processing_reversal_id
    );

    INSERT INTO public.audit_event (
        business_id, actor_type, actor_user_id,
        action, entity_type, entity_id, outcome, details
    )
    VALUES (
        v_payment.business_id, 'user', p_actor_user_id,
        'reverse_payment', 'payment', p_payment_id, 'success',
        jsonb_build_object(
            'amount', v_payment.amount,
            'currency', v_currency,
            'original_payment_status', v_payment.status,
            'reversal_transaction_ids', v_reversal_ids,
            'reason', BTRIM(p_reason),
            'simulated', TRUE
        )
    );

    RETURN v_processing_reversal_id;
END;
$$;