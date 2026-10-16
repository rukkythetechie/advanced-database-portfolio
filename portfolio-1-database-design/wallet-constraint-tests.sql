-- Corridor Pay: Wallet constraint tests
-- Run in psql with business and wallet initially empty.
-- Four constraint errors are expected.
-- All test records are rolled back.
-- Generated IDs may differ between runs.

\set ON_ERROR_STOP on

BEGIN;

-- Create the first temporary business and capture its ID.
INSERT INTO business (
    business_name, country_code,
    registration_number, contact_email
)
VALUES (
    'Wallet Test Business', 'NG',
    'TEST-WALLETS-001', 'wallet-test@example.com'
)
RETURNING business_id AS first_business_id
\gset

-- 1. Valid NGN wallet: expect zero balance and a timestamp.
INSERT INTO wallet (business_id, currency_code)
VALUES (:first_business_id, 'NGN')
RETURNING wallet_id, currency_code, balance, created_at;

-- 2. Duplicate currency for the same business: expect rejection.
SAVEPOINT before_duplicate_wallet;

\set ON_ERROR_STOP off

INSERT INTO wallet (business_id, currency_code)
VALUES (:first_business_id, 'NGN');

ROLLBACK TO SAVEPOINT before_duplicate_wallet;

\set ON_ERROR_STOP on

-- 3. Other supported currencies: expect three successful inserts.
INSERT INTO wallet (business_id, currency_code)
VALUES
    (:first_business_id, 'CAD'),
    (:first_business_id, 'GBP'),
    (:first_business_id, 'USD')
RETURNING wallet_id, currency_code, balance;

-- 4. Unsupported currency: expect wallet_currency_check error.
SAVEPOINT before_invalid_currency;

\set ON_ERROR_STOP off

INSERT INTO wallet (business_id, currency_code)
VALUES (:first_business_id, 'EUR');

ROLLBACK TO SAVEPOINT before_invalid_currency;

\set ON_ERROR_STOP on

-- 5. Negative balance: expect wallet_balance_check error.
SAVEPOINT before_negative_balance;

\set ON_ERROR_STOP off

UPDATE wallet
SET balance = -1.00
WHERE business_id = :first_business_id
  AND currency_code = 'NGN';

ROLLBACK TO SAVEPOINT before_negative_balance;

\set ON_ERROR_STOP on

-- 6. Missing business: expect wallet_business_fk error.
SAVEPOINT before_missing_wallet_business;

\set ON_ERROR_STOP off

INSERT INTO wallet (business_id, currency_code)
VALUES (999999, 'NGN');

ROLLBACK TO SAVEPOINT before_missing_wallet_business;

\set ON_ERROR_STOP on

-- Create a second temporary business and capture its ID.
INSERT INTO business (
    business_name, country_code,
    registration_number, contact_email
)
VALUES (
    'Second Wallet Test Business', 'NG',
    'TEST-WALLETS-002', 'second-wallet@example.com'
)
RETURNING business_id AS second_business_id
\gset

-- 7. Same currency for another business: expect success.
INSERT INTO wallet (business_id, currency_code)
VALUES (:second_business_id, 'NGN')
RETURNING wallet_id, business_id, currency_code, balance;

-- 8. Remove all test records; expect both counts to be zero.
ROLLBACK;

SELECT
    (SELECT COUNT(*) FROM business) AS business_count,
    (SELECT COUNT(*) FROM wallet) AS wallet_count;