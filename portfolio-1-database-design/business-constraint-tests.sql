-- Corridor Pay: Business table constraint tests
-- Run using psql against the empty Business table.
-- Four errors are expected. All test rows are rolled back.

-- Allow psql to continue after intentional constraint errors.
\set ON_ERROR_STOP off

BEGIN;

-- 1. Valid insert: expect an ID, pending status and timestamp.
INSERT INTO business (
    business_name, country_code,
    registration_number, contact_email
)
VALUES (
    'Rooks Trading Ltd', 'NG',
    'TEST-NG-001', 'contact@rookstrading.example'
)
RETURNING business_id, kyb_status, created_at;

-- 2. Unsupported country: expect business_country_check error.
SAVEPOINT before_invalid_country;

INSERT INTO business (
    business_name, country_code,
    registration_number, contact_email
)
VALUES (
    'Unsupported Country Test', 'FR',
    'TEST-FR-001', 'test@example.com'
);

ROLLBACK TO SAVEPOINT before_invalid_country;

-- 3. Duplicate country and registration: expect unique error.
SAVEPOINT before_duplicate_registration;

INSERT INTO business (
    business_name, country_code,
    registration_number, contact_email
)
VALUES (
    'Duplicate Registration Test', 'NG',
    'TEST-NG-001', 'duplicate@example.com'
);

ROLLBACK TO SAVEPOINT before_duplicate_registration;

-- 4. Same registration in another country: expect success.
INSERT INTO business (
    business_name, country_code,
    registration_number, contact_email
)
VALUES (
    'Canada Registration Test', 'CA',
    'TEST-NG-001', 'canada@example.com'
)
RETURNING business_id, country_code, registration_number;

-- 5. Invalid status: expect business_kyb_status_check error.
SAVEPOINT before_invalid_status;

INSERT INTO business (
    business_name, country_code,
    registration_number, contact_email, kyb_status
)
VALUES (
    'Invalid Status Test', 'NG',
    'TEST-NG-002', 'status@example.com', 'verified'
);

ROLLBACK TO SAVEPOINT before_invalid_status;

-- 6. Missing name: expect not-null error.
SAVEPOINT before_missing_name;

INSERT INTO business (
    business_name, country_code,
    registration_number, contact_email
)
VALUES (
    NULL, 'NG',
    'TEST-NG-003', 'missingname@example.com'
);

ROLLBACK TO SAVEPOINT before_missing_name;

-- 7. Remove test rows and verify the empty table.
ROLLBACK;

SELECT COUNT(*) AS business_count FROM business;

-- Restore stop-on-error behaviour for subsequent scripts.
\set ON_ERROR_STOP on