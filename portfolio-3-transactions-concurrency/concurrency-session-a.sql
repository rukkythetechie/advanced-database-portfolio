-- Session A: process the first payment, then pause before commit.
\set ON_ERROR_STOP on
\timing on

SET application_name = 'corridor_p3_A';

BEGIN ISOLATION LEVEL READ COMMITTED;

-- Lock payment A before processing it.
SELECT
    p.payment_id AS test_payment_id,
    p.business_id AS test_business_id,
    p.wallet_id AS test_wallet_id,
    p.initiated_by AS test_user_id,
    t.ledger_transaction_id AS test_transaction_id
FROM payment AS p
JOIN ledger_transaction AS t ON t.payment_id = p.payment_id
WHERE t.description = 'Concurrency test A'
  AND t.status = 'draft'
  AND p.status = 'pending'
FOR UPDATE OF p
\gset

SELECT post_ledger_transaction(:test_transaction_id);

UPDATE payment
SET status = 'processing'
WHERE payment_id = :test_payment_id;

INSERT INTO payment_status_history (
    payment_id, from_status, to_status,
    actor_type, changed_by, reason, ledger_transaction_id
)
VALUES (
    :test_payment_id, 'pending', 'processing',
    'user', :test_user_id, 'Concurrency test A processed',
    :test_transaction_id
);

INSERT INTO audit_event (
    business_id, actor_type, actor_user_id,
    action, entity_type, entity_id, outcome, details
)
VALUES (
    :test_business_id, 'user', :test_user_id,
    'concurrency_payment_processing', 'payment',
    :test_payment_id, 'success',
    '{"test": "A", "currency": "NGN", "amount": 70000.00}'::JSONB
);

-- A sees its own uncommitted changes and still holds the wallet lock.
SELECT
    pg_backend_pid() AS session_a_pid,
    current_setting('transaction_isolation') AS isolation_level,
    balance AS uncommitted_wallet_balance
FROM wallet
WHERE wallet_id = :test_wallet_id;

\prompt 'PAUSED: Do not press Enter until session B is confirmed waiting. ' continue_test

COMMIT;

\echo 'Session A committed.'