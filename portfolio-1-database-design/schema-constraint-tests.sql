-- Corridor Pay: Schema constraint tests
-- Run using psql against the empty corridorpay_p1_check database.
-- Tests cover table constraints, not operational payment routines.
-- All test records will be rolled back at the end of this script.

\set ON_ERROR_STOP on

BEGIN;

\echo 'SETUP: Create two separate businesses'

INSERT INTO business (
    business_name, country_code,
    registration_number, contact_email
)
VALUES (
    'Schema Test Business A', 'NG',
    'SCHEMA-TEST-A', 'a@example.com'
)
RETURNING business_id AS business_a
\gset

INSERT INTO business (
    business_name, country_code,
    registration_number, contact_email
)
VALUES (
    'Schema Test Business B', 'CA',
    'SCHEMA-TEST-B', 'b@example.com'
)
RETURNING business_id AS business_b
\gset

INSERT INTO business_user (
    business_id, full_name, email, role
)
VALUES (
    :business_a, 'Admin A', 'schema-admin-a@example.com', 'admin'
)
RETURNING user_id AS user_a
\gset

INSERT INTO business_user (
    business_id, full_name, email, role
)
VALUES (
    :business_b, 'Admin B', 'schema-admin-b@example.com', 'admin'
)
RETURNING user_id AS user_b
\gset

INSERT INTO wallet (business_id, currency_code)
VALUES (:business_a, 'NGN')
RETURNING wallet_id AS wallet_a_ngn
\gset

INSERT INTO wallet (business_id, currency_code)
VALUES (:business_a, 'USD')
RETURNING wallet_id AS wallet_a_usd
\gset

INSERT INTO wallet (business_id, currency_code)
VALUES (:business_b, 'NGN')
RETURNING wallet_id AS wallet_b_ngn
\gset

\echo 'TEST 1: Valid beneficiary with optional routing omitted'

INSERT INTO beneficiary (
    business_id, beneficiary_name, country_code,
    currency_code, bank_name, account_reference
)
VALUES (
    :business_a, 'Test Supplier', 'NG',
    'NGN', 'Example Bank', '0012345678'
)
RETURNING beneficiary_id AS beneficiary_a
\gset

SELECT beneficiary_id, account_reference, routing_reference
FROM beneficiary
WHERE beneficiary_id = :beneficiary_a;

\echo 'TEST 2: Another business can save the same supplier destination'

INSERT INTO beneficiary (
    business_id, beneficiary_name, country_code,
    currency_code, bank_name, account_reference
)
VALUES (
    :business_b, 'Test Supplier', 'NG',
    'NGN', 'Example Bank', '0012345678'
)
RETURNING beneficiary_id AS beneficiary_b
\gset

SELECT beneficiary_id, business_id, account_reference
FROM beneficiary
ORDER BY beneficiary_id;

\echo 'TEST 3: Unsupported beneficiary currency must fail'

SAVEPOINT invalid_beneficiary_currency;
\set ON_ERROR_STOP off

INSERT INTO beneficiary (
    business_id, beneficiary_name, country_code,
    currency_code, bank_name, account_reference
)
VALUES (
    :business_a, 'Invalid Currency Supplier', 'NG',
    'EUR', 'Example Bank', 'TEST-003'
);

ROLLBACK TO SAVEPOINT invalid_beneficiary_currency;
\set ON_ERROR_STOP on

\echo 'TEST 4: Unsupported beneficiary country must fail'

SAVEPOINT invalid_beneficiary_country;
\set ON_ERROR_STOP off

INSERT INTO beneficiary (
    business_id, beneficiary_name, country_code,
    currency_code, bank_name, account_reference
)
VALUES (
    :business_a, 'Invalid Country Supplier', 'FR',
    'USD', 'Example Bank', 'TEST-004'
);

ROLLBACK TO SAVEPOINT invalid_beneficiary_country;
\set ON_ERROR_STOP on

\echo 'TEST 5: Missing beneficiary account reference must fail'

SAVEPOINT missing_account_reference;
\set ON_ERROR_STOP off

INSERT INTO beneficiary (
    business_id, beneficiary_name, country_code,
    currency_code, bank_name, account_reference
)
VALUES (
    :business_a, 'Missing Account Supplier', 'NG',
    'NGN', 'Example Bank', NULL
);

ROLLBACK TO SAVEPOINT missing_account_reference;
\set ON_ERROR_STOP on

\echo 'TEST 6: Valid FX quote must succeed'

INSERT INTO fx_quote (
    business_id, source_currency, target_currency,
    source_amount, exchange_rate, expires_at
)
VALUES (
    :business_a, 'NGN', 'USD',
    160000.00, 0.000752154660,
    CURRENT_TIMESTAMP + INTERVAL '1 hour'
)
RETURNING quote_id AS quote_a
\gset

SELECT quote_id, source_currency, target_currency,
       source_amount, exchange_rate,
       ROUND(source_amount * exchange_rate, 2) AS target_amount
FROM fx_quote
WHERE quote_id = :quote_a;

\echo 'TEST 7: Identical source and target currencies must fail'

SAVEPOINT identical_quote_currencies;
\set ON_ERROR_STOP off

INSERT INTO fx_quote (
    business_id, source_currency, target_currency,
    source_amount, exchange_rate, expires_at
)
VALUES (
    :business_a, 'NGN', 'NGN',
    100.00, 1.00,
    CURRENT_TIMESTAMP + INTERVAL '1 hour'
);

ROLLBACK TO SAVEPOINT identical_quote_currencies;
\set ON_ERROR_STOP on

\echo 'TEST 8: Zero source amount must fail'

SAVEPOINT zero_quote_amount;
\set ON_ERROR_STOP off

INSERT INTO fx_quote (
    business_id, source_currency, target_currency,
    source_amount, exchange_rate, expires_at
)
VALUES (
    :business_a, 'NGN', 'USD',
    0.00, 0.000752154660,
    CURRENT_TIMESTAMP + INTERVAL '1 hour'
);

ROLLBACK TO SAVEPOINT zero_quote_amount;
\set ON_ERROR_STOP on

\echo 'TEST 9: Expiry before creation must fail'

SAVEPOINT invalid_quote_expiry;
\set ON_ERROR_STOP off

INSERT INTO fx_quote (
    business_id, source_currency, target_currency,
    source_amount, exchange_rate, expires_at
)
VALUES (
    :business_a, 'NGN', 'USD',
    160000.00, 0.000752154660,
    CURRENT_TIMESTAMP - INTERVAL '1 minute'
);

ROLLBACK TO SAVEPOINT invalid_quote_expiry;
\set ON_ERROR_STOP on

\echo 'TEST 10: Target amount rounding to zero must fail'

SAVEPOINT zero_rounded_target;
\set ON_ERROR_STOP off

INSERT INTO fx_quote (
    business_id, source_currency, target_currency,
    source_amount, exchange_rate, expires_at
)
VALUES (
    :business_a, 'NGN', 'USD',
    0.01, 0.000000000001,
    CURRENT_TIMESTAMP + INTERVAL '1 hour'
);

ROLLBACK TO SAVEPOINT zero_rounded_target;
\set ON_ERROR_STOP on

\echo 'TEST 11: Valid pending payment must succeed'

INSERT INTO payment (
    business_id, wallet_id, beneficiary_id, initiated_by, amount
)
VALUES (
    :business_a, :wallet_a_ngn, :beneficiary_a, :user_a, 50000.00
)
RETURNING payment_id AS payment_a
\gset

SELECT payment_id, business_id, amount, status, completed_at
FROM payment
WHERE payment_id = :payment_a;

\echo 'TEST 12: Another business wallet must fail'

SAVEPOINT payment_wrong_wallet;
\set ON_ERROR_STOP off

INSERT INTO payment (
    business_id, wallet_id, beneficiary_id, initiated_by, amount
)
VALUES (
    :business_a, :wallet_b_ngn, :beneficiary_a, :user_a, 100.00
);

ROLLBACK TO SAVEPOINT payment_wrong_wallet;
\set ON_ERROR_STOP on

\echo 'TEST 13: Another business beneficiary must fail'

SAVEPOINT payment_wrong_beneficiary;
\set ON_ERROR_STOP off

INSERT INTO payment (
    business_id, wallet_id, beneficiary_id, initiated_by, amount
)
VALUES (
    :business_a, :wallet_a_ngn, :beneficiary_b, :user_a, 100.00
);

ROLLBACK TO SAVEPOINT payment_wrong_beneficiary;
\set ON_ERROR_STOP on

\echo 'TEST 14: Another business user must fail'

SAVEPOINT payment_wrong_user;
\set ON_ERROR_STOP off

INSERT INTO payment (
    business_id, wallet_id, beneficiary_id, initiated_by, amount
)
VALUES (
    :business_a, :wallet_a_ngn, :beneficiary_a, :user_b, 100.00
);

ROLLBACK TO SAVEPOINT payment_wrong_user;
\set ON_ERROR_STOP on

\echo 'TEST 15: Negative payment amount must fail'

SAVEPOINT negative_payment_amount;
\set ON_ERROR_STOP off

INSERT INTO payment (
    business_id, wallet_id, beneficiary_id, initiated_by, amount
)
VALUES (
    :business_a, :wallet_a_ngn, :beneficiary_a, :user_a, -1.00
);

ROLLBACK TO SAVEPOINT negative_payment_amount;
\set ON_ERROR_STOP on

\echo 'TEST 16: Unsupported payment status must fail'

SAVEPOINT invalid_payment_status;
\set ON_ERROR_STOP off

INSERT INTO payment (
    business_id, wallet_id, beneficiary_id,
    initiated_by, amount, status
)
VALUES (
    :business_a, :wallet_a_ngn, :beneficiary_a,
    :user_a, 100.00, 'cancelled'
);

ROLLBACK TO SAVEPOINT invalid_payment_status;
\set ON_ERROR_STOP on

\echo 'TEST 17: Completed payment without completion time must fail'

SAVEPOINT missing_completion_time;
\set ON_ERROR_STOP off

INSERT INTO payment (
    business_id, wallet_id, beneficiary_id,
    initiated_by, amount, status
)
VALUES (
    :business_a, :wallet_a_ngn, :beneficiary_a,
    :user_a, 100.00, 'completed'
);

ROLLBACK TO SAVEPOINT missing_completion_time;
\set ON_ERROR_STOP on

\echo 'TEST 18: Valid wallet liability account must succeed'

INSERT INTO ledger_account (
    account_name, account_type, currency_code, wallet_id
)
VALUES (
    'Business A NGN Wallet', 'liability', 'NGN', :wallet_a_ngn
)
RETURNING ledger_account_id AS account_a_ngn
\gset

\echo 'TEST 19: A second account for the same wallet must fail'

SAVEPOINT duplicate_wallet_account;
\set ON_ERROR_STOP off

INSERT INTO ledger_account (
    account_name, account_type, currency_code, wallet_id
)
VALUES (
    'Duplicate NGN Wallet Account', 'liability', 'NGN', :wallet_a_ngn
);

ROLLBACK TO SAVEPOINT duplicate_wallet_account;
\set ON_ERROR_STOP on

\echo 'TEST 20: Wallet-linked asset account must fail'

SAVEPOINT invalid_wallet_account_type;
\set ON_ERROR_STOP off

INSERT INTO ledger_account (
    account_name, account_type, currency_code, wallet_id
)
VALUES (
    'Invalid USD Wallet Account', 'asset', 'USD', :wallet_a_usd
);

ROLLBACK TO SAVEPOINT invalid_wallet_account_type;
\set ON_ERROR_STOP on

\echo 'TEST 21: Platform cash account without wallet must succeed'

INSERT INTO ledger_account (
    account_name, account_type, currency_code
)
VALUES (
    'Platform NGN Cash', 'asset', 'NGN'
)
RETURNING ledger_account_id AS cash_ngn
\gset

\echo 'TEST 22: Draft funding transaction and entries must succeed'

INSERT INTO ledger_transaction (
    transaction_type, description
)
VALUES (
    'funding', 'Draft funding example for schema tests'
)
RETURNING ledger_transaction_id AS funding_transaction
\gset

INSERT INTO ledger_entry (
    ledger_transaction_id, ledger_account_id, entry_type, amount
)
VALUES
    (:funding_transaction, :cash_ngn, 'debit', 100000.00),
    (:funding_transaction, :account_a_ngn, 'credit', 100000.00);

SELECT ledger_transaction_id, status, posted_at
FROM ledger_transaction
WHERE ledger_transaction_id = :funding_transaction;

SELECT entry_type, amount
FROM ledger_entry
WHERE ledger_transaction_id = :funding_transaction
ORDER BY ledger_entry_id;

\echo 'TEST 23: Zero ledger entry amount must fail'

SAVEPOINT zero_entry_amount;
\set ON_ERROR_STOP off

INSERT INTO ledger_entry (
    ledger_transaction_id, ledger_account_id, entry_type, amount
)
VALUES (
    :funding_transaction, :cash_ngn, 'debit', 0.00
);

ROLLBACK TO SAVEPOINT zero_entry_amount;
\set ON_ERROR_STOP on

\echo 'TEST 24: Unsupported ledger entry type must fail'

SAVEPOINT invalid_entry_type;
\set ON_ERROR_STOP off

INSERT INTO ledger_entry (
    ledger_transaction_id, ledger_account_id, entry_type, amount
)
VALUES (
    :funding_transaction, :cash_ngn, 'transfer', 100.00
);

ROLLBACK TO SAVEPOINT invalid_entry_type;
\set ON_ERROR_STOP on

\echo 'TEST 25: Payout transaction without payment reference must fail'

SAVEPOINT missing_payout_payment;
\set ON_ERROR_STOP off

INSERT INTO ledger_transaction (
    transaction_type, description
)
VALUES (
    'payout_processing', 'Invalid posting without payment reference'
);

ROLLBACK TO SAVEPOINT missing_payout_payment;
\set ON_ERROR_STOP on

\echo 'TEST 26: Posted status without posting timestamp must fail'

SAVEPOINT missing_posted_timestamp;
\set ON_ERROR_STOP off

INSERT INTO ledger_transaction (
    transaction_type, description, status
)
VALUES (
    'funding', 'Invalid posted transaction without timestamp', 'posted'
);

ROLLBACK TO SAVEPOINT missing_posted_timestamp;
\set ON_ERROR_STOP on

\echo 'TEST 27: Initial pending history record must succeed'

INSERT INTO payment_status_history (
    payment_id, from_status, to_status,
    actor_type, changed_by, reason
)
VALUES (
    :payment_a, NULL, 'pending',
    'user', :user_a, 'Payment instruction created'
)
RETURNING history_id, from_status, to_status, actor_type;

\echo 'TEST 28: System history actor with a user ID must fail'

SAVEPOINT invalid_history_actor;
\set ON_ERROR_STOP off

INSERT INTO payment_status_history (
    payment_id, from_status, to_status,
    actor_type, changed_by, reason
)
VALUES (
    :payment_a, 'pending', 'failed',
    'system', :user_a, 'Invalid system actor example'
);

ROLLBACK TO SAVEPOINT invalid_history_actor;
\set ON_ERROR_STOP on

\echo 'TEST 29: History cannot link a posting from another payment'

INSERT INTO payment (
    business_id, wallet_id, beneficiary_id, initiated_by, amount
)
VALUES (
    :business_a, :wallet_a_ngn, :beneficiary_a, :user_a, 200.00
)
RETURNING payment_id AS second_payment_a
\gset

INSERT INTO ledger_transaction (
    transaction_type, description, payment_id
)
VALUES (
    'payout_processing', 'Draft posting for second payment',
    :second_payment_a
)
RETURNING ledger_transaction_id AS second_payment_posting
\gset

SAVEPOINT history_wrong_payment_posting;
\set ON_ERROR_STOP off

INSERT INTO payment_status_history (
    payment_id, from_status, to_status,
    actor_type, changed_by, reason, ledger_transaction_id
)
VALUES (
    :payment_a, 'pending', 'processing',
    'user', :user_a, 'Invalid link to another payment',
    :second_payment_posting
);

ROLLBACK TO SAVEPOINT history_wrong_payment_posting;
\set ON_ERROR_STOP on

\echo 'TEST 30: Valid user audit event must succeed'

INSERT INTO audit_event (
    business_id, actor_type, actor_user_id,
    action, entity_type, entity_id, outcome
)
VALUES (
    :business_a, 'user', :user_a,
    'payment_created', 'payment', :payment_a, 'success'
)
RETURNING audit_event_id, outcome, details;

\echo 'TEST 31: Audit actor from another business must fail'

SAVEPOINT audit_wrong_business_user;
\set ON_ERROR_STOP off

INSERT INTO audit_event (
    business_id, actor_type, actor_user_id,
    action, entity_type, outcome
)
VALUES (
    :business_a, 'user', :user_b,
    'test_action', 'payment', 'failure'
);

ROLLBACK TO SAVEPOINT audit_wrong_business_user;
\set ON_ERROR_STOP on

\echo 'TEST 32: Audit details must be a JSON object'

SAVEPOINT audit_invalid_details;
\set ON_ERROR_STOP off

INSERT INTO audit_event (
    business_id, actor_type, action,
    entity_type, outcome, details
)
VALUES (
    :business_a, 'system', 'test_action',
    'payment', 'failure', '[]'::JSONB
);

ROLLBACK TO SAVEPOINT audit_invalid_details;
\set ON_ERROR_STOP on

\echo 'SETUP: FX accounts and balanced entries for conversion tests'

INSERT INTO ledger_account (
    account_name, account_type, currency_code, wallet_id
)
VALUES (
    'Business A USD Wallet', 'liability', 'USD', :wallet_a_usd
)
RETURNING ledger_account_id AS account_a_usd
\gset

INSERT INTO ledger_account (
    account_name, account_type, currency_code
)
VALUES (
    'NGN FX Position', 'asset', 'NGN'
)
RETURNING ledger_account_id AS fx_ngn
\gset

INSERT INTO ledger_account (
    account_name, account_type, currency_code
)
VALUES (
    'USD FX Position', 'asset', 'USD'
)
RETURNING ledger_account_id AS fx_usd
\gset

INSERT INTO ledger_transaction (
    transaction_type, description
)
VALUES (
    'fx_conversion', 'Structural FX example for constraint tests'
)
RETURNING ledger_transaction_id AS fx_transaction
\gset

INSERT INTO ledger_entry (
    ledger_transaction_id, ledger_account_id, entry_type, amount
)
VALUES
    (:fx_transaction, :account_a_ngn, 'debit', 160000.00),
    (:fx_transaction, :fx_ngn, 'credit', 160000.00),
    (:fx_transaction, :fx_usd, 'debit', 120.34),
    (:fx_transaction, :account_a_usd, 'credit', 120.34);

UPDATE ledger_transaction
SET status = 'posted',
    posted_at = CURRENT_TIMESTAMP
WHERE ledger_transaction_id = :fx_transaction;

-- This is a table-constraint fixture, not an operational conversion.
-- Atomic wallet updates and controlled posting are tested later.

\echo 'TEST 33: Conversion with valid references must succeed'

INSERT INTO fx_conversion (
    quote_id, business_id, source_wallet_id, target_wallet_id,
    initiated_by, target_amount, ledger_transaction_id
)
VALUES (
    :quote_a, :business_a, :wallet_a_ngn, :wallet_a_usd,
    :user_a, 120.34, :fx_transaction
)
RETURNING conversion_id, quote_id, target_amount;

\echo 'TEST 34: Reusing the same quote must fail'

SAVEPOINT reused_conversion_quote;
\set ON_ERROR_STOP off

INSERT INTO fx_conversion (
    quote_id, business_id, source_wallet_id, target_wallet_id,
    initiated_by, target_amount, ledger_transaction_id
)
VALUES (
    :quote_a, :business_a, :wallet_a_ngn, :wallet_a_usd,
    :user_a, 120.34, :funding_transaction
);

ROLLBACK TO SAVEPOINT reused_conversion_quote;
\set ON_ERROR_STOP on

\echo 'TEST 35: Conversion source and target wallets cannot be identical'

SAVEPOINT identical_conversion_wallets;
\set ON_ERROR_STOP off

INSERT INTO fx_conversion (
    quote_id, business_id, source_wallet_id, target_wallet_id,
    initiated_by, target_amount, ledger_transaction_id
)
VALUES (
    :quote_a, :business_a, :wallet_a_ngn, :wallet_a_ngn,
    :user_a, 120.34, :funding_transaction
);

ROLLBACK TO SAVEPOINT identical_conversion_wallets;
\set ON_ERROR_STOP on

\echo 'CLEANUP: Roll back all test records'

ROLLBACK;

\echo 'FINAL CHECK: Every table should have zero rows'

SELECT 'business' AS table_name, COUNT(*) AS row_count FROM business
UNION ALL
SELECT 'business_user', COUNT(*) FROM business_user
UNION ALL
SELECT 'wallet', COUNT(*) FROM wallet
UNION ALL
SELECT 'beneficiary', COUNT(*) FROM beneficiary
UNION ALL
SELECT 'fx_quote', COUNT(*) FROM fx_quote
UNION ALL
SELECT 'payment', COUNT(*) FROM payment
UNION ALL
SELECT 'ledger_account', COUNT(*) FROM ledger_account
UNION ALL
SELECT 'ledger_transaction', COUNT(*) FROM ledger_transaction
UNION ALL
SELECT 'ledger_entry', COUNT(*) FROM ledger_entry
UNION ALL
SELECT 'fx_conversion', COUNT(*) FROM fx_conversion
UNION ALL
SELECT 'payment_status_history', COUNT(*) FROM payment_status_history
UNION ALL
SELECT 'audit_event', COUNT(*) FROM audit_event
ORDER BY table_name;