-- Corridor Pay: database schema
-- First table: registered businesses

CREATE TABLE business (
    business_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    business_name TEXT NOT NULL,
    country_code TEXT NOT NULL,
    registration_number TEXT NOT NULL,
    contact_email TEXT NOT NULL,
    kyb_status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT business_country_check
        CHECK (country_code IN ('NG', 'CA', 'GB', 'US')),

    CONSTRAINT business_kyb_status_check
        CHECK (kyb_status IN ('pending', 'approved', 'rejected')),

    CONSTRAINT business_registration_unique
        UNIQUE (country_code, registration_number)
);