-- Corridor Pay: Portfolio 2 sample data
-- Use only with the separate corridorpay_p2 database.
-- Pending payments will demonstrate queries, not money movements.

\set ON_ERROR_STOP on

BEGIN;

-- Prevent accidentally loading the sample data twice.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM business) THEN
        RAISE EXCEPTION 'Load this script into an empty database.';
    END IF;
END;
$$;

-- Create 100 approved businesses across the four countries.
INSERT INTO business (
    business_name,
    country_code,
    registration_number,
    contact_email,
    kyb_status
)
SELECT
    'Sample Business ' || n,
    (ARRAY['NG', 'CA', 'GB', 'US'])[1 + ((n - 1) % 4)],
    'P2-' || LPAD(n::TEXT, 4, '0'),
    'business' || n || '@example.com',
    'approved'
FROM generate_series(1, 100) AS series(n);

-- Create one active admin user per business.
INSERT INTO business_user (
    business_id,
    full_name,
    email,
    role
)
SELECT
    business_id,
    'Sample Admin ' || business_id,
    'admin' || business_id || '@example.com',
    'admin'
FROM business;

-- Create one wallet per currency for each business.
INSERT INTO wallet (
    business_id,
    currency_code
)
SELECT
    b.business_id,
    c.currency_code
FROM business AS b
CROSS JOIN (
    VALUES ('NGN'), ('CAD'), ('GBP'), ('USD')
) AS c(currency_code);

-- Create 400 sample supplier destinations.
INSERT INTO beneficiary (
    business_id,
    beneficiary_name,
    country_code,
    currency_code,
    bank_name,
    account_reference
)
SELECT
    w.business_id,
    'Sample Supplier ' || w.business_id || ' ' || w.currency_code,
    CASE w.currency_code
        WHEN 'NGN' THEN 'NG'
        WHEN 'CAD' THEN 'CA'
        WHEN 'GBP' THEN 'GB'
        WHEN 'USD' THEN 'US'
    END,
    w.currency_code,
    'Sample Bank',
    'TEST-' || w.business_id || '-' || w.currency_code
FROM wallet AS w;

-- Create 100,000 pending payments for query testing.
INSERT INTO payment (
    business_id,
    wallet_id,
    beneficiary_id,
    initiated_by,
    amount,
    created_at
)
SELECT
    w.business_id,
    w.wallet_id,
    ben.beneficiary_id,
    u.user_id,
    (100 + series.n * 10)::NUMERIC(20, 2),
    TIMESTAMPTZ '2026-10-20 12:00:00+00'
        - series.n * INTERVAL '6 hours'
FROM wallet AS w
JOIN beneficiary AS ben
    ON ben.business_id = w.business_id
    AND ben.currency_code = w.currency_code
JOIN business_user AS u
    ON u.business_id = w.business_id
    AND u.role = 'admin'
CROSS JOIN generate_series(1, 250) AS series(n);

-- Record the initial status of every payment.
INSERT INTO payment_status_history (
    payment_id,
    from_status,
    to_status,
    changed_at,
    actor_type,
    changed_by,
    reason
)
SELECT
    payment_id,
    NULL,
    'pending',
    created_at,
    'user',
    initiated_by,
    'Sample payment created for query testing'
FROM payment;

COMMIT;

-- Refresh statistics so PostgreSQL can plan queries.
ANALYZE;

-- Check the sample data totals.
SELECT 'business' AS table_name, COUNT(*) AS row_count
FROM business
UNION ALL
SELECT 'business_user', COUNT(*) FROM business_user
UNION ALL
SELECT 'wallet', COUNT(*) FROM wallet
UNION ALL
SELECT 'beneficiary', COUNT(*) FROM beneficiary
UNION ALL
SELECT 'payment', COUNT(*) FROM payment
UNION ALL
SELECT 'payment_status_history', COUNT(*) FROM payment_status_history
ORDER BY table_name;