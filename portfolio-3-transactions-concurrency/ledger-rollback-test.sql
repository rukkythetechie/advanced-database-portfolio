-- Corridor Pay: rollback after a successful posting
-- Requires the committed funding test.
-- One intentional audit constraint error is expected.
\set ON_ERROR_STOP on

BEGIN;

-- Find the existing test records without assuming their IDs.
SELECT
    b.business_id AS test_business_id,
    u.user_id AS test_user_id,
    w.wallet_id AS test_wallet_id,
    a.ledger_account_id AS wallet_account_id,
    cash.ledger_account_id AS cash_account_id
FROM business AS b
JOIN business_user AS u ON u.business_id = b.business_id
JOIN wallet AS w ON w.business_id = b.business_id
JOIN ledger_account AS a ON a.wallet_id = w.wallet_id
CROSS JOIN ledger_account AS cash
WHERE b.country_code = 'NG'
  AND b.registration_number = 'P3-LEDGER-001'
  AND u.email = 'ledger-admin@example.com'
  AND w.currency_code = 'NGN'
  AND cash.account_name = 'Ledger Test NGN Cash'
  AND cash.account_type = 'asset'
  AND cash.currency_code = 'NGN'
\gset

INSERT INTO ledger_transaction (
    transaction_type, description
)
VALUES (
    'funding', 'Temporary funding for rollback test'
)
RETURNING ledger_transaction_id AS rollback_transaction_id
\gset

INSERT INTO ledger_entry (
    ledger_transaction_id, ledger_account_id, entry_type, amount
)
VALUES
    (:rollback_transaction_id, :cash_account_id, 'debit', 10000.00),
    (:rollback_transaction_id, :wallet_account_id, 'credit', 10000.00);

SELECT post_ledger_transaction(:rollback_transaction_id);

INSERT INTO audit_event (
    business_id, actor_type, actor_user_id, action,
    entity_type, entity_id, outcome
)
VALUES (
    :test_business_id, 'user', :test_user_id,
    'temporary_funding_test', 'ledger_transaction',
    :rollback_transaction_id, 'success'
);

-- Changes are visible inside this transaction but not committed.
SELECT
    w.balance AS balance_before_rollback,
    t.status AS temporary_posting_status
FROM wallet AS w
CROSS JOIN ledger_transaction AS t
WHERE w.wallet_id = :test_wallet_id
  AND t.ledger_transaction_id = :rollback_transaction_id;

-- Deliberately fail a later step: "invalid" is not an allowed outcome.
\set ON_ERROR_STOP off

INSERT INTO audit_event (
    business_id, actor_type, action, entity_type, outcome
)
VALUES (
    :test_business_id, 'system',
    'intentional_rollback_error', 'wallet', 'invalid'
);

\set ON_ERROR_STOP on

-- Undo everything since BEGIN, including the posting and audit.
ROLLBACK;

SELECT
    balance AS balance_after_rollback,
    balance = 100000.00 AS original_balance_restored
FROM wallet
WHERE wallet_id = :test_wallet_id;

SELECT
    (
        SELECT COUNT(*)
        FROM ledger_transaction
        WHERE ledger_transaction_id = :rollback_transaction_id
    ) AS temporary_transactions,
    (
        SELECT COUNT(*)
        FROM ledger_entry
        WHERE ledger_transaction_id = :rollback_transaction_id
    ) AS temporary_entries,
    (
        SELECT COUNT(*)
        FROM audit_event
        WHERE action = 'temporary_funding_test'
          AND entity_id = :rollback_transaction_id
    ) AS temporary_success_audits;