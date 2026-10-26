-- Corridor Pay: controlled payment processing
-- Install after ledger-routines.sql.
-- Functions participate in the caller's database transaction.
-- Database access restrictions are installed separately.

-- A payment may have only one original processing posting.
-- Corrections must use linked reversal transactions.
CREATE UNIQUE INDEX payment_processing_posting_unique
ON ledger_transaction (payment_id)
WHERE transaction_type = 'payout_processing';


CREATE OR REPLACE FUNCTION process_payment(
    p_payment_id BIGINT,
    p_actor_user_id BIGINT,
    p_clearing_account_id BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_payment public.payment%ROWTYPE;
    v_user public.business_user%ROWTYPE;
    v_business public.business%ROWTYPE;
    v_beneficiary public.beneficiary%ROWTYPE;
    v_clearing public.ledger_account%ROWTYPE;
    v_wallet_currency TEXT;
    v_wallet_account_id BIGINT;
    v_transaction_id BIGINT;
BEGIN
    -- Serialize attempts to process this same payment.
    SELECT *
    INTO v_payment
    FROM public.payment
    WHERE payment_id = p_payment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment does not exist';
    END IF;

    IF v_payment.status <> 'pending' THEN
        RAISE EXCEPTION 'Only a pending payment can be processed';
    END IF;

    -- Keep the actor's role and active status stable until commit.
    SELECT *
    INTO v_user
    FROM public.business_user
    WHERE user_id = p_actor_user_id
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Acting user does not exist';
    END IF;

    IF v_user.business_id <> v_payment.business_id
       OR NOT v_user.is_active
       OR v_user.role NOT IN ('admin', 'finance') THEN
        RAISE EXCEPTION
            'An active admin or finance user from the payment business is required';
    END IF;

    -- Keep approval status stable until commit.
    SELECT *
    INTO v_business
    FROM public.business
    WHERE business_id = v_payment.business_id
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment business does not exist';
    END IF;

    IF v_business.kyb_status <> 'approved' THEN
        RAISE EXCEPTION 'The payment business must be approved';
    END IF;

    SELECT currency_code
    INTO v_wallet_currency
    FROM public.wallet
    WHERE wallet_id = v_payment.wallet_id
      AND business_id = v_payment.business_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment wallet ownership is invalid';
    END IF;

    -- Prevent destination changes during this operation.
    SELECT *
    INTO v_beneficiary
    FROM public.beneficiary
    WHERE beneficiary_id = v_payment.beneficiary_id
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment beneficiary does not exist';
    END IF;

    IF v_beneficiary.business_id <> v_payment.business_id
       OR v_beneficiary.currency_code <> v_wallet_currency THEN
        RAISE EXCEPTION
            'Beneficiary ownership or currency does not match the wallet';
    END IF;

    SELECT ledger_account_id
    INTO v_wallet_account_id
    FROM public.ledger_account
    WHERE wallet_id = v_payment.wallet_id
      AND account_type = 'liability'
      AND currency_code = v_wallet_currency;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'The wallet needs a matching liability ledger account';
    END IF;

    SELECT *
    INTO v_clearing
    FROM public.ledger_account
    WHERE ledger_account_id = p_clearing_account_id
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Clearing account does not exist';
    END IF;

    IF v_clearing.wallet_id IS NOT NULL
       OR v_clearing.account_type <> 'liability'
       OR v_clearing.currency_code <> v_wallet_currency THEN
        RAISE EXCEPTION
            'Clearing requires a platform liability account in the wallet currency';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.ledger_transaction
        WHERE payment_id = p_payment_id
          AND transaction_type = 'payout_processing'
    ) THEN
        RAISE EXCEPTION
            'This payment already has a processing ledger transaction';
    END IF;

    INSERT INTO public.ledger_transaction (
        transaction_type, description, payment_id
    )
    VALUES (
        'payout_processing',
        'Controlled payment processing',
        p_payment_id
    )
    RETURNING ledger_transaction_id INTO v_transaction_id;

    INSERT INTO public.ledger_entry (
        ledger_transaction_id, ledger_account_id,
        entry_type, amount
    )
    VALUES
        (v_transaction_id, v_wallet_account_id,
         'debit', v_payment.amount),
        (v_transaction_id, p_clearing_account_id,
         'credit', v_payment.amount);

    -- The existing posting engine locks the wallet,
    -- rechecks available funds and applies the balance change.
    PERFORM public.post_ledger_transaction(v_transaction_id);

    UPDATE public.payment
    SET status = 'processing'
    WHERE payment_id = p_payment_id;

    INSERT INTO public.payment_status_history (
        payment_id, from_status, to_status,
        actor_type, changed_by, reason, ledger_transaction_id
    )
    VALUES (
        p_payment_id, 'pending', 'processing',
        'user', p_actor_user_id,
        'Payment processed through the controlled routine',
        v_transaction_id
    );

    INSERT INTO public.audit_event (
        business_id, actor_type, actor_user_id,
        action, entity_type, entity_id, outcome, details
    )
    VALUES (
        v_payment.business_id, 'user', p_actor_user_id,
        'process_payment', 'payment', p_payment_id, 'success',
        jsonb_build_object(
            'amount', v_payment.amount,
            'currency', v_wallet_currency,
            'ledger_transaction_id', v_transaction_id
        )
    );

    RETURN v_transaction_id;
END;
$$;