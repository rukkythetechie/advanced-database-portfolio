-- Corridor Pay: controlled payment processing tests
-- All fixtures and changes are rolled back.
\set ON_ERROR_STOP on
BEGIN;

-- A test helper: fail the test unless the expected rejection occurs.
CREATE FUNCTION pg_temp.expect_payment_rejection(
    p_payment_id BIGINT,
    p_actor_id BIGINT,
    p_clearing_id BIGINT,
    p_expected_message TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_rejected BOOLEAN := FALSE;
BEGIN
    BEGIN
        PERFORM public.process_payment(
            p_payment_id, p_actor_id, p_clearing_id
        );
    EXCEPTION WHEN raise_exception THEN
        IF POSITION(p_expected_message IN SQLERRM) = 0 THEN
            RAISE;
        END IF;

        v_rejected := TRUE;
        RAISE NOTICE 'PASS: rejected — %', SQLERRM;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'TEST FAILED: expected rejection: %',
            p_expected_message;
    END IF;
END;
$$;

DO $$
DECLARE
    v_business BIGINT;
    v_other_business BIGINT;
    v_admin BIGINT;
    v_viewer BIGINT;
    v_other_user BIGINT;
    v_wallet BIGINT;
    v_wallet_account BIGINT;
    v_cash BIGINT;
    v_clearing BIGINT;
    v_supplier BIGINT;
    v_usd_supplier BIGINT;
    v_funding BIGINT;
    v_payment BIGINT;
    v_pending BIGINT;
    v_posting BIGINT;
BEGIN
    INSERT INTO business (
        business_name, country_code, registration_number,
        contact_email, kyb_status
    )
    VALUES (
        'Payment Routine Test', 'NG', 'P3-PROCESS-001',
        'process-business@example.com', 'approved'
    )
    RETURNING business_id INTO v_business;

    INSERT INTO business (
        business_name, country_code, registration_number,
        contact_email, kyb_status
    )
    VALUES (
        'Other Payment Test Business', 'NG', 'P3-PROCESS-002',
        'other-process-business@example.com', 'approved'
    )
    RETURNING business_id INTO v_other_business;

    INSERT INTO business_user (
        business_id, full_name, email, role
    )
    VALUES (
        v_business, 'Process Admin',
        'process-admin@example.com', 'admin'
    )
    RETURNING user_id INTO v_admin;

    INSERT INTO business_user (
        business_id, full_name, email, role
    )
    VALUES (
        v_business, 'Process Viewer',
        'process-viewer@example.com', 'viewer'
    )
    RETURNING user_id INTO v_viewer;

    INSERT INTO business_user (
        business_id, full_name, email, role
    )
    VALUES (
        v_other_business, 'Other Process Admin',
        'other-process-admin@example.com', 'admin'
    )
    RETURNING user_id INTO v_other_user;

    INSERT INTO wallet (business_id, currency_code)
    VALUES (v_business, 'NGN')
    RETURNING wallet_id INTO v_wallet;

    INSERT INTO ledger_account (
        account_name, account_type, currency_code, wallet_id
    )
    VALUES (
        'Process Test Wallet', 'liability', 'NGN', v_wallet
    )
    RETURNING ledger_account_id INTO v_wallet_account;

    INSERT INTO ledger_account (
        account_name, account_type, currency_code
    )
    VALUES ('Process Test Cash', 'asset', 'NGN')
    RETURNING ledger_account_id INTO v_cash;

    INSERT INTO ledger_account (
        account_name, account_type, currency_code
    )
    VALUES ('Process Test Clearing', 'liability', 'NGN')
    RETURNING ledger_account_id INTO v_clearing;

    INSERT INTO beneficiary (
        business_id, beneficiary_name, country_code,
        currency_code, bank_name, account_reference
    )
    VALUES (
        v_business, 'Process NGN Supplier', 'NG',
        'NGN', 'Sample Bank', 'PROCESS-NGN-001'
    )
    RETURNING beneficiary_id INTO v_supplier;

    INSERT INTO beneficiary (
        business_id, beneficiary_name, country_code,
        currency_code, bank_name, account_reference
    )
    VALUES (
        v_business, 'Process USD Supplier', 'US',
        'USD', 'Sample Bank', 'PROCESS-USD-001'
    )
    RETURNING beneficiary_id INTO v_usd_supplier;

    -- Fund the temporary wallet through the ledger.
    INSERT INTO ledger_transaction (
        transaction_type, description
    )
    VALUES ('funding', 'Payment routine test funding')
    RETURNING ledger_transaction_id INTO v_funding;

    INSERT INTO ledger_entry (
        ledger_transaction_id, ledger_account_id,
        entry_type, amount
    )
    VALUES
        (v_funding, v_cash, 'debit', 100000.00),
        (v_funding, v_wallet_account, 'credit', 100000.00);

    PERFORM post_ledger_transaction(v_funding);

    INSERT INTO payment (
        business_id, wallet_id, beneficiary_id,
        initiated_by, amount
    )
    VALUES (
        v_business, v_wallet, v_supplier, v_admin, 10000.00
    )
    RETURNING payment_id INTO v_payment;

    INSERT INTO payment_status_history (
        payment_id, to_status, actor_type, changed_by, reason
    )
    VALUES (
        v_payment, 'pending', 'user', v_admin,
        'Temporary payment created for routine testing'
    );

    -- 1. Valid processing.
    v_posting := process_payment(
        v_payment, v_admin, v_clearing
    );

    IF NOT EXISTS (
        SELECT 1
        FROM payment p
        JOIN wallet w ON w.wallet_id = p.wallet_id
        JOIN ledger_transaction t ON t.payment_id = p.payment_id
        WHERE p.payment_id = v_payment
          AND p.status = 'processing'
          AND w.balance = 90000.00
          AND t.ledger_transaction_id = v_posting
          AND t.status = 'posted'
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: valid processing result';
    END IF;

    IF (
        SELECT COUNT(*) FROM payment_status_history
        WHERE payment_id = v_payment
          AND from_status = 'pending'
          AND to_status = 'processing'
          AND ledger_transaction_id = v_posting
    ) <> 1 OR (
        SELECT COUNT(*) FROM audit_event
        WHERE business_id = v_business
          AND action = 'process_payment'
          AND entity_id = v_payment
          AND outcome = 'success'
    ) <> 1 THEN
        RAISE EXCEPTION 'TEST FAILED: history or success audit';
    END IF;

    RAISE NOTICE 'PASS: processing, wallet debit, history and audit';

    -- 2. The same payment cannot be processed twice.
    PERFORM pg_temp.expect_payment_rejection(
        v_payment, v_admin, v_clearing,
        'Only a pending payment'
    );

    -- A second pending instruction supports the rejection tests.
    INSERT INTO payment (
        business_id, wallet_id, beneficiary_id,
        initiated_by, amount
    )
    VALUES (
        v_business, v_wallet, v_supplier, v_admin, 1000.00
    )
    RETURNING payment_id INTO v_pending;

    INSERT INTO payment_status_history (
        payment_id, to_status, actor_type, changed_by, reason
    )
    VALUES (
        v_pending, 'pending', 'user', v_admin,
        'Temporary instruction for rejection tests'
    );

    -- 3. Viewer cannot process.
    PERFORM pg_temp.expect_payment_rejection(
        v_pending, v_viewer, v_clearing,
        'An active admin or finance user'
    );

    -- 4. A user from another business cannot process.
    PERFORM pg_temp.expect_payment_rejection(
        v_pending, v_other_user, v_clearing,
        'An active admin or finance user'
    );

    -- 5. Inactive admin cannot process.
    UPDATE business_user SET is_active = FALSE
    WHERE user_id = v_admin;

    PERFORM pg_temp.expect_payment_rejection(
        v_pending, v_admin, v_clearing,
        'An active admin or finance user'
    );

    UPDATE business_user SET is_active = TRUE
    WHERE user_id = v_admin;

    -- 6. Unapproved business cannot process.
    UPDATE business SET kyb_status = 'pending'
    WHERE business_id = v_business;

    PERFORM pg_temp.expect_payment_rejection(
        v_pending, v_admin, v_clearing,
        'The payment business must be approved'
    );

    UPDATE business SET kyb_status = 'approved'
    WHERE business_id = v_business;

    -- 7. Destination currency must match the wallet.
    UPDATE payment SET beneficiary_id = v_usd_supplier
    WHERE payment_id = v_pending;

    PERFORM pg_temp.expect_payment_rejection(
        v_pending, v_admin, v_clearing,
        'Beneficiary ownership or currency'
    );

    UPDATE payment SET beneficiary_id = v_supplier
    WHERE payment_id = v_pending;

    -- 8. Insufficient funds must leave no partial processing.
    UPDATE payment SET amount = 120000.00
    WHERE payment_id = v_pending;

    PERFORM pg_temp.expect_payment_rejection(
        v_pending, v_admin, v_clearing,
        'invalid or insufficient balance'
    );

    IF EXISTS (
        SELECT 1 FROM ledger_transaction
        WHERE payment_id = v_pending
    ) OR EXISTS (
        SELECT 1 FROM audit_event
        WHERE business_id = v_business
          AND action = 'process_payment'
          AND entity_id = v_pending
    ) OR (
        SELECT status FROM payment
        WHERE payment_id = v_pending
    ) <> 'pending' OR (
        SELECT balance FROM wallet
        WHERE wallet_id = v_wallet
    ) <> 90000.00 THEN
        RAISE EXCEPTION 'TEST FAILED: rejected attempt left changes';
    END IF;

    RAISE NOTICE 'PASS: rejected attempts left no partial posting or debit';
END;
$$;

-- Display the successful processing result before rollback.
SELECT
    p.status AS payment_status,
    t.status AS ledger_status,
    p.amount,
    w.balance AS wallet_balance
FROM payment p
JOIN business b ON b.business_id = p.business_id
JOIN wallet w ON w.wallet_id = p.wallet_id
JOIN ledger_transaction t ON t.payment_id = p.payment_id
WHERE b.registration_number = 'P3-PROCESS-001'
  AND b.country_code = 'NG';

ROLLBACK;

-- Expect zero temporary businesses.
SELECT COUNT(*) AS temporary_businesses_remaining
FROM business
WHERE country_code = 'NG'
  AND registration_number IN ('P3-PROCESS-001', 'P3-PROCESS-002');

-- The existing concurrency-test wallet must remain unchanged.
SELECT w.wallet_id, w.currency_code, w.balance
FROM wallet w
JOIN business b ON b.business_id = w.business_id
WHERE b.country_code = 'NG'
  AND b.registration_number = 'P3-LEDGER-001'
  AND w.currency_code = 'NGN';