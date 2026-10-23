-- Corridor Pay: ledger protection tests
-- Requires ledger-funding-test.sql.
-- Four intentional errors are expected.
-- All test changes are rolled back.
\set ON_ERROR_STOP on

BEGIN;

SELECT
    w.wallet_id AS test_wallet_id,
    a.ledger_account_id AS wallet_account_id,
    cash.ledger_account_id AS cash_account_id
FROM wallet AS w
JOIN business AS b ON b.business_id = w.business_id
JOIN ledger_account AS a ON a.wallet_id = w.wallet_id
CROSS JOIN ledger_account AS cash
WHERE b.country_code = 'NG'
  AND b.registration_number = 'P3-LEDGER-001'
  AND w.currency_code = 'NGN'
  AND cash.account_name = 'Ledger Test NGN Cash'
  AND cash.account_type = 'asset'
  AND cash.currency_code = 'NGN'
\gset

SELECT
    t.ledger_transaction_id AS posted_transaction_id,
    e.ledger_entry_id AS posted_entry_id
FROM ledger_transaction AS t
JOIN ledger_entry AS e
    ON e.ledger_transaction_id = t.ledger_transaction_id
WHERE t.status = 'posted'
  AND e.ledger_account_id = :wallet_account_id
ORDER BY t.ledger_transaction_id
LIMIT 1
\gset

-- 1. Posting the same transaction twice must fail.
SAVEPOINT before_duplicate_posting;
\set ON_ERROR_STOP off

SELECT post_ledger_transaction(:posted_transaction_id);

\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_duplicate_posting;

-- 2. Editing a posted entry must fail.
SAVEPOINT before_posted_entry_edit;
\set ON_ERROR_STOP off

UPDATE ledger_entry
SET amount = 1.00
WHERE ledger_entry_id = :posted_entry_id;

\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_posted_entry_edit;

-- 3. Changing a posted account's currency must fail.
SAVEPOINT before_account_currency_edit;
\set ON_ERROR_STOP off

UPDATE ledger_account
SET currency_code = 'USD'
WHERE ledger_account_id = :cash_account_id;

\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_account_currency_edit;

-- 4. An unbalanced draft must not post.
SAVEPOINT before_unbalanced_posting;

INSERT INTO ledger_transaction (
    transaction_type, description
)
VALUES (
    'funding', 'Intentional unbalanced posting test'
)
RETURNING ledger_transaction_id AS unbalanced_transaction_id
\gset

INSERT INTO ledger_entry (
    ledger_transaction_id, ledger_account_id, entry_type, amount
)
VALUES
    (:unbalanced_transaction_id, :cash_account_id, 'debit', 100.00),
    (:unbalanced_transaction_id, :wallet_account_id, 'credit', 90.00);

\set ON_ERROR_STOP off

SELECT post_ledger_transaction(:unbalanced_transaction_id);

\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_unbalanced_posting;

ROLLBACK;

-- The committed funding must remain unchanged.
SELECT
    balance,
    balance = 100000.00 AS original_balance_preserved
FROM wallet
WHERE wallet_id = :test_wallet_id;

SELECT
    (SELECT COUNT(*) FROM ledger_transaction) AS transaction_count,
    (SELECT COUNT(*) FROM ledger_entry) AS entry_count;