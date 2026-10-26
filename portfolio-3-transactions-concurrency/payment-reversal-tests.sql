-- Corridor Pay: full payment reversal tests
-- Requires the committed concurrency demonstration.
-- All changes are rolled back.
\set ON_ERROR_STOP on
BEGIN;

-- Find the existing fixtures without assuming their IDs.
SELECT
    p.payment_id AS payment_a,
    p.initiated_by AS actor_id,
    p.wallet_id AS test_wallet_id
FROM payment p
JOIN ledger_transaction t ON t.payment_id = p.payment_id
WHERE t.description = 'Concurrency test A'
  AND t.status = 'posted'
  AND p.status = 'processing'
\gset

SELECT p.payment_id AS payment_b
FROM payment p
JOIN ledger_transaction t ON t.payment_id = p.payment_id
WHERE t.description = 'Concurrency test B'
  AND p.status = 'failed'
  AND t.status = 'draft'
\gset

SELECT ledger_account_id AS cash_id
FROM ledger_account
WHERE account_name = 'Ledger Test NGN Cash'
  AND account_type = 'asset'
  AND currency_code = 'NGN'
  AND wallet_id IS NULL
\gset


CREATE FUNCTION pg_temp.expect_reversal_rejection(
    p_payment BIGINT,
    p_actor BIGINT,
    p_reason TEXT,
    p_expected TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_rejected BOOLEAN := FALSE;
BEGIN
    BEGIN
        PERFORM public.reverse_payment(
            p_payment, p_actor, p_reason
        );
    EXCEPTION WHEN raise_exception THEN
        IF POSITION(p_expected IN SQLERRM) = 0 THEN
            RAISE;
        END IF;
        v_rejected := TRUE;
        RAISE NOTICE 'PASS: rejected — %', SQLERRM;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'TEST FAILED: expected rejection: %',
            p_expected;
    END IF;
END;
$$;


CREATE FUNCTION pg_temp.check_payment_reversal(
    p_payment BIGINT,
    p_actor BIGINT,
    p_expected_reversals INTEGER,
    p_expected_from TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_before public.payment%ROWTYPE;
    v_reversal BIGINT;
    v_balance NUMERIC;
    v_ledger_balance NUMERIC;
BEGIN
    SELECT *
    INTO STRICT v_before
    FROM public.payment
    WHERE payment_id = p_payment;

    v_reversal := public.reverse_payment(
        p_payment, p_actor, 'Simulated return of payment funds'
    );

    IF NOT EXISTS (
        SELECT 1 FROM public.payment
        WHERE payment_id = p_payment
          AND status = 'reversed'
          AND completed_at IS NOT DISTINCT FROM v_before.completed_at
    ) THEN
        RAISE EXCEPTION
            'TEST FAILED: reversal status or retained completion timestamp';
    END IF;

    SELECT balance INTO v_balance
    FROM public.wallet
    WHERE wallet_id = v_before.wallet_id;

    IF v_balance IS DISTINCT FROM 100000.00::NUMERIC THEN
        RAISE EXCEPTION 'TEST FAILED: full refund balance';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.ledger_transaction
        WHERE payment_id = p_payment
          AND transaction_type = 'reversal'
          AND status = 'posted'
          AND reversal_of_transaction_id IS NOT NULL
    ) <> p_expected_reversals THEN
        RAISE EXCEPTION 'TEST FAILED: linked reversal count';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.ledger_transaction
        WHERE payment_id = p_payment
          AND transaction_type IN (
              'payout_processing', 'payout_settlement'
          )
          AND status = 'posted'
    ) <> p_expected_reversals THEN
        RAISE EXCEPTION 'TEST FAILED: original posted records';
    END IF;

    -- Original payment postings plus their reversals must
    -- have a zero net effect on every affected ledger account.
    IF EXISTS (
        SELECT e.ledger_account_id
        FROM public.ledger_entry e
        JOIN public.ledger_transaction t
          ON t.ledger_transaction_id = e.ledger_transaction_id
        WHERE t.payment_id = p_payment
          AND t.status = 'posted'
        GROUP BY e.ledger_account_id
        HAVING SUM(
            CASE e.entry_type
                WHEN 'debit' THEN e.amount
                ELSE -e.amount
            END
        ) <> 0
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: account movements not fully reversed';
    END IF;

    SELECT SUM(
        CASE e.entry_type
            WHEN 'credit' THEN e.amount
            ELSE -e.amount
        END
    )
    INTO v_ledger_balance
    FROM public.ledger_account a
    JOIN public.ledger_entry e
      ON e.ledger_account_id = a.ledger_account_id
    JOIN public.ledger_transaction t
      ON t.ledger_transaction_id = e.ledger_transaction_id
    WHERE a.wallet_id = v_before.wallet_id
      AND t.status = 'posted';

    IF v_balance IS DISTINCT FROM v_ledger_balance THEN
        RAISE EXCEPTION 'TEST FAILED: wallet reconciliation';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.payment_status_history
        WHERE payment_id = p_payment
          AND from_status = p_expected_from
          AND to_status = 'reversed'
          AND changed_by = p_actor
          AND ledger_transaction_id = v_reversal
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.audit_event
        WHERE action = 'reverse_payment'
          AND entity_type = 'payment'
          AND entity_id = p_payment
          AND business_id = v_before.business_id
          AND outcome = 'success'
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: reversal history or audit';
    END IF;

    IF v_before.status = 'processing' AND NOT EXISTS (
        SELECT 1
        FROM public.payment_status_history
        WHERE payment_id = p_payment
          AND from_status = 'processing'
          AND to_status = 'failed'
          AND changed_by = p_actor
    ) THEN
        RAISE EXCEPTION 'TEST FAILED: processing failure history';
    END IF;

    RAISE NOTICE
        'PASS: % payment refunded; % linked reversal(s); originals retained; balance reconciled',
        v_before.status, p_expected_reversals;
END;
$$;


-- 1. A reason is required.
SELECT pg_temp.expect_reversal_rejection(
    :payment_a, :actor_id, ' ',
    'A reversal reason is required'
);

-- 2. B never deducted money, so it must not receive a refund.
SELECT pg_temp.expect_reversal_rejection(
    :payment_b, :actor_id, 'Attempt refund without deduction',
    'No posted wallet deduction exists'
);


-- 3. Processing payment: fail it and reverse its deduction.
SAVEPOINT processing_case;

SELECT pg_temp.check_payment_reversal(
    :payment_a, :actor_id, 1, 'failed'
);

-- 4. The same payment cannot be refunded twice.
SELECT pg_temp.expect_reversal_rejection(
    :payment_a, :actor_id, 'Duplicate refund attempt',
    'Only a deducted processing, failed or completed payment'
);

ROLLBACK TO SAVEPOINT processing_case;


-- 5. An already-failed payment with a posted deduction
-- can receive its full refund.
SAVEPOINT failed_case;

UPDATE payment
SET status = 'failed'
WHERE payment_id = :payment_a;

INSERT INTO payment_status_history (
    payment_id, from_status, to_status,
    actor_type, changed_by, reason
)
VALUES (
    :payment_a, 'processing', 'failed',
    'user', :actor_id, 'Simulated payout failure before refund'
);

SELECT pg_temp.check_payment_reversal(
    :payment_a, :actor_id, 1, 'failed'
);

ROLLBACK TO SAVEPOINT failed_case;


-- 6. Completed payment: reverse settlement and processing.
SELECT settle_payment(:payment_a, :actor_id, :cash_id);

SELECT pg_temp.check_payment_reversal(
    :payment_a, :actor_id, 2, 'completed'
);

-- 7. A completed-payment refund cannot be repeated.
SELECT pg_temp.expect_reversal_rejection(
    :payment_a, :actor_id, 'Repeat completed-payment refund',
    'Only a deducted processing, failed or completed payment'
);

-- Display the temporary completed-payment reversal result.
SELECT
    p.status AS payment_status,
    p.completed_at IS NOT NULL AS original_completion_retained,
    w.balance AS refunded_wallet_balance,
    (
        SELECT COUNT(*)
        FROM ledger_transaction t
        WHERE t.payment_id = p.payment_id
          AND t.transaction_type = 'reversal'
          AND t.status = 'posted'
    ) AS posted_reversals
FROM payment p
JOIN wallet w ON w.wallet_id = p.wallet_id
WHERE p.payment_id = :payment_a;

ROLLBACK;

-- Expect processing, 30000.00 and zero reversal transactions.
SELECT
    p.status AS restored_payment_status,
    w.balance AS wallet_balance,
    (
        SELECT COUNT(*)
        FROM ledger_transaction t
        WHERE t.payment_id = p.payment_id
          AND t.transaction_type = 'reversal'
    ) AS reversal_transactions_remaining
FROM payment p
JOIN wallet w ON w.wallet_id = p.wallet_id
WHERE p.payment_id = :payment_a;