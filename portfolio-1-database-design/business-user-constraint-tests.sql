-- Corridor Pay: Business user constraint tests
-- Run in psql with business and business_user initially empty.
-- Four errors are expected. All test records are rolled back.
-- Generated IDs may differ between runs.

\set ON_ERROR_STOP on

BEGIN;

-- Create a temporary business and capture its ID.
INSERT INTO business (
    business_name, country_code,
    registration_number, contact_email
)
VALUES (
    'User Test Business', 'NG',
    'TEST-USERS-001', 'business@example.com'
)
RETURNING business_id AS test_business_id
\gset

-- 1. Valid admin: expect success, active = true and a timestamp.
INSERT INTO business_user (
    business_id, full_name, email, role
)
VALUES (
    :test_business_id, 'Test Admin', 'admin@example.com', 'admin'
)
RETURNING user_id, role, is_active, created_at;

-- Continue after the intentional constraint errors below.
\set ON_ERROR_STOP off

-- 2. Invalid role: expect business_user_role_check error.
SAVEPOINT before_invalid_role;

INSERT INTO business_user (
    business_id, full_name, email, role
)
VALUES (
    :test_business_id, 'Invalid Role Test',
    'invalidrole@example.com', 'manager'
);

ROLLBACK TO SAVEPOINT before_invalid_role;

-- 3. Case-insensitive duplicate: expect email uniqueness error.
SAVEPOINT before_duplicate_email;

INSERT INTO business_user (
    business_id, full_name, email, role
)
VALUES (
    :test_business_id, 'Duplicate Email Test',
    'ADMIN@EXAMPLE.COM', 'finance'
);

ROLLBACK TO SAVEPOINT before_duplicate_email;

-- 4. Missing business: expect business_user_business_fk error.
SAVEPOINT before_missing_business;

INSERT INTO business_user (
    business_id, full_name, email, role
)
VALUES (
    999999, 'Missing Business Test',
    'missingbusiness@example.com', 'viewer'
);

ROLLBACK TO SAVEPOINT before_missing_business;

-- 5. Missing name: expect full_name NOT NULL error.
SAVEPOINT before_missing_user_name;

INSERT INTO business_user (
    business_id, full_name, email, role
)
VALUES (
    :test_business_id, NULL, 'missingname@example.com', 'viewer'
);

ROLLBACK TO SAVEPOINT before_missing_user_name;

\set ON_ERROR_STOP on

-- 6. Finance and viewer: expect both inserts to succeed.
INSERT INTO business_user (
    business_id, full_name, email, role
)
VALUES
    (:test_business_id, 'Test Finance', 'finance@example.com', 'finance'),
    (:test_business_id, 'Test Viewer', 'viewer@example.com', 'viewer')
RETURNING user_id, role, is_active;

-- 7. Remove all test records; expect both counts to be zero.
ROLLBACK;

SELECT
    (SELECT COUNT(*) FROM business) AS business_count,
    (SELECT COUNT(*) FROM business_user) AS user_count;