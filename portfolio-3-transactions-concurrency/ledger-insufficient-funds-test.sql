-- Corridor Pay: insufficient-funds posting test
-- One intentional error is expected.
-- All temporary test records are rolled back.
\set ON_ERROR_STOP on

BEGIN;

SELECT
    b.business_id AS test_business_id,
    u.user_id AS test_user_id,
    w.wallet_id AS test_wallet_id,
    a.ledger_account_id AS wallet_account_id
FROM business AS b
JOIN business_user AS u ON u.business_id = b.business_id
JOIN wallet AS w ON w.business_id = b.business_id
JOIN ledger_account AS a ON a.wallet_id = w.wallet_id
WHERE b.country_code = 'NG'
  AND b.registration_number = 'P3-LEDGER-001'
  AND u.email = 'ledger-admin@example.com'
  AND w.currency_code = 'NGN'
\gset

-- Temporary payout clearing account.
INSERT INTO ledger_account (
    account_name, account_type, currency_code
)
VALUES (
    'Insufficient Funds Test Clearing', 'liability', 'NGN'
)
RETURNING ledger_account_id AS clearing_account_id
\gset

INSERT INTO beneficiary (
    business_id, beneficiary_name, country_code,
    currency_code, bank_name, account_reference
)
VALUES (
    :test_business_id, 'Insufficient Funds Test Supplier',
    'NG', 'NGN', 'Sample Bank', 'TEST-INSUFFICIENT-001'
)
RETURNING beneficiary_id AS test_beneficiary_id
\gset

-- Pending instructions do not deduct funds.
INSERT INTO payment (
    business_id, wallet_id, beneficiary_id, initiated_by, amount
)
VALUES (
    :test_business_id, :test_wallet_id,
    :test_beneficiary_id, :test_user_id, 120000.00
)
RETURNING payment_id AS test_payment_id
\gset

INSERT INTO payment_status_history (
    payment_id, to_status, actor_type, changed_by, reason
)
VALUES (
    :test_payment_id, 'pending', 'user', :test_user_id,
    'Temporary instruction for insufficient-funds test'
);

INSERT INTO ledger_transaction (
    transaction_type, description, payment_id
)
VALUES (
    'payout_processing', 'Intentional insufficient-funds test',
    :test_payment_id
)
RETURNING ledger_transaction_id AS test_transaction_id
\gset

-- The entries balance, but the wallet cannot afford the debit.
INSERT INTO ledger_entry (
    ledger_transaction_id, ledger_account_id, entry_type, amount
)
VALUES
    (:test_transaction_id, :wallet_account_id, 'debit', 120000.00),
    (:test_transaction_id, :clearing_account_id, 'credit', 120000.00);

SAVEPOINT before_insufficient_posting;
\set ON_ERROR_STOP off

SELECT post_ledger_transaction(:test_transaction_id);

\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_insufficient_posting;

-- Expect 100000.00, true, draft and pending.
SELECT
    w.balance,
    w.balance = 100000.00 AS original_balance_preserved,
    t.status AS ledger_status,
    p.status AS payment_status
FROM wallet AS w
JOIN payment AS p ON p.wallet_id = w.wallet_id
JOIN ledger_transaction AS t ON t.payment_id = p.payment_id
WHERE p.payment_id = :test_payment_id
  AND t.ledger_transaction_id = :test_transaction_id;

-- Remove all temporary fixtures.
ROLLBACK;

-- The original funding should be the only remaining posting.
SELECT
    (SELECT COUNT(*) FROM ledger_transaction) AS transaction_count,
    (SELECT COUNT(*) FROM ledger_entry) AS entry_count,
    (SELECT COUNT(*) FROM payment) AS payment_count;