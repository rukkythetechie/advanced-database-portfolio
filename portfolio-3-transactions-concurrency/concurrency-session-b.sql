-- Session B: compete for the wallet used by session A.
\set ON_ERROR_STOP on
\timing on

SET application_name = 'corridor_p3_B';

BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT
    p.payment_id AS test_payment_id,
    p.business_id AS test_business_id,
    p.wallet_id AS test_wallet_id,
    p.initiated_by AS test_user_id,
    p.amount AS requested_amount,
    t.ledger_transaction_id AS test_transaction_id
FROM payment AS p
JOIN ledger_transaction AS t ON t.payment_id = p.payment_id
WHERE t.description = 'Concurrency test B'
  AND t.status = 'draft'
  AND p.status = 'pending'
FOR UPDATE OF p
\gset

-- This call should wait while A holds the wallet lock.
-- After A commits, B should see the remaining 30000.00.
\set ON_ERROR_STOP off

SELECT post_ledger_transaction(:test_transaction_id);

\set posting_failed :ERROR
\set posting_sqlstate :SQLSTATE
\set ON_ERROR_STOP on

\if :posting_failed

    ROLLBACK;

    -- Record the failed attempt after rollback.
    BEGIN ISOLATION LEVEL READ COMMITTED;

    SELECT payment_id
    FROM payment
    WHERE payment_id = :test_payment_id
      AND status = 'pending'
    FOR UPDATE
    \gset

    -- Check the expected state before classifying the failure.
    SELECT
        balance AS remaining_balance,
        (
            balance = 30000.00
            AND balance < :requested_amount
            AND :'posting_sqlstate' = 'P0001'
            AND EXISTS (
                SELECT 1
                FROM ledger_transaction
                WHERE description = 'Concurrency test A'
                  AND status = 'posted'
            )
        ) AS expected_funds_failure
    FROM wallet
    WHERE wallet_id = :test_wallet_id
    FOR NO KEY UPDATE
    \gset

    \if :expected_funds_failure

        UPDATE payment
        SET status = 'failed'
        WHERE payment_id = :test_payment_id;

        INSERT INTO payment_status_history (
            payment_id, from_status, to_status,
            actor_type, reason
        )
        VALUES (
            :test_payment_id, 'pending', 'failed', 'system',
            'Insufficient funds after concurrency test A committed'
        );

        INSERT INTO audit_event (
            business_id, actor_type, actor_user_id,
            action, entity_type, entity_id, outcome, details
        )
        VALUES (
            :test_business_id, 'user', :test_user_id,
            'concurrency_payment_processing', 'payment',
            :test_payment_id, 'failure',
            '{"test": "B", "currency": "NGN", "amount": 70000.00,
              "reason": "insufficient_funds"}'::JSONB
        );

        COMMIT;

        SELECT
            p.status AS payment_status,
            t.status AS ledger_status,
            w.balance AS remaining_wallet_balance
        FROM payment AS p
        JOIN ledger_transaction AS t ON t.payment_id = p.payment_id
        JOIN wallet AS w ON w.wallet_id = p.wallet_id
        WHERE t.ledger_transaction_id = :test_transaction_id;

    \else

        ROLLBACK;
        \echo 'Unexpected failure state: investigate before continuing.'

    \endif

\else

    ROLLBACK;
    \echo 'Unexpected success: B was rolled back; investigate the test.'

\endif