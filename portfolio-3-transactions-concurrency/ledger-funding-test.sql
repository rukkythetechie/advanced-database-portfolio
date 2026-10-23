-- Corridor Pay: committed funding demonstration
-- Run once against corridorpay_p3.
\set ON_ERROR_STOP on

BEGIN;

-- Create an approved test business.
INSERT INTO business (
    business_name, country_code, registration_number,
    contact_email, kyb_status
)
VALUES (
    'Ledger Test Business', 'NG', 'P3-LEDGER-001',
    'ledger-business@example.com', 'approved'
)
RETURNING business_id AS test_business_id
\gset

INSERT INTO business_user (
    business_id, full_name, email, role
)
VALUES (
    :test_business_id, 'Ledger Test Admin',
    'ledger-admin@example.com', 'admin'
)
RETURNING user_id AS test_user_id
\gset

-- Create the zero-balance wallet and its liability account together.
INSERT INTO wallet (business_id, currency_code)
VALUES (:test_business_id, 'NGN')
RETURNING wallet_id AS test_wallet_id
\gset

INSERT INTO ledger_account (
    account_name, account_type, currency_code, wallet_id
)
VALUES (
    'Ledger Test NGN Wallet', 'liability', 'NGN', :test_wallet_id
)
RETURNING ledger_account_id AS wallet_account_id
\gset

INSERT INTO ledger_account (
    account_name, account_type, currency_code
)
VALUES (
    'Ledger Test NGN Cash', 'asset', 'NGN'
)
RETURNING ledger_account_id AS cash_account_id
\gset

-- Prepare balanced entries while the transaction is a draft.
INSERT INTO ledger_transaction (
    transaction_type, description
)
VALUES (
    'funding', 'Simulated NGN wallet funding'
)
RETURNING ledger_transaction_id AS funding_transaction_id
\gset

INSERT INTO ledger_entry (
    ledger_transaction_id, ledger_account_id, entry_type, amount
)
VALUES
    (:funding_transaction_id, :cash_account_id, 'debit', 100000.00),
    (:funding_transaction_id, :wallet_account_id, 'credit', 100000.00);

-- Validate the entries, update the wallet and mark the posting.
SELECT post_ledger_transaction(:funding_transaction_id);

-- Save the successful audit event in this same database transaction.
INSERT INTO audit_event (
    business_id, actor_type, actor_user_id, action,
    entity_type, entity_id, outcome, details
)
VALUES (
    :test_business_id, 'user', :test_user_id,
    'simulated_wallet_funding', 'ledger_transaction',
    :funding_transaction_id, 'success',
    '{"currency": "NGN", "amount": 100000.00}'::JSONB
);

COMMIT;

-- Verify the stored wallet balance against posted ledger entries.
SELECT
    w.wallet_id,
    w.currency_code,
    w.balance AS stored_balance,
    SUM(
        CASE e.entry_type
            WHEN 'credit' THEN e.amount
            ELSE -e.amount
        END
    ) AS ledger_balance,
    w.balance = SUM(
        CASE e.entry_type
            WHEN 'credit' THEN e.amount
            ELSE -e.amount
        END
    ) AS balances_match
FROM wallet AS w
JOIN ledger_account AS a ON a.wallet_id = w.wallet_id
JOIN ledger_entry AS e ON e.ledger_account_id = a.ledger_account_id
JOIN ledger_transaction AS t
    ON t.ledger_transaction_id = e.ledger_transaction_id
WHERE w.wallet_id = :test_wallet_id
  AND t.status = 'posted'
GROUP BY w.wallet_id, w.currency_code, w.balance;

-- Verify debit and credit totals within the funding currency.
SELECT
    t.ledger_transaction_id,
    t.status,
    a.currency_code,
    SUM(e.amount) FILTER (WHERE e.entry_type = 'debit') AS debits,
    SUM(e.amount) FILTER (WHERE e.entry_type = 'credit') AS credits
FROM ledger_transaction AS t
JOIN ledger_entry AS e
    ON e.ledger_transaction_id = t.ledger_transaction_id
JOIN ledger_account AS a
    ON a.ledger_account_id = e.ledger_account_id
WHERE t.ledger_transaction_id = :funding_transaction_id
GROUP BY t.ledger_transaction_id, t.status, a.currency_code;