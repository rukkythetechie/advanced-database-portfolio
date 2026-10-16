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
-- Business users and their roles
CREATE TABLE business_user (
    user_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    business_id BIGINT NOT NULL,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    role TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT business_user_business_fk
        FOREIGN KEY (business_id)
        REFERENCES business (business_id),

    CONSTRAINT business_user_role_check
        CHECK (role IN ('admin', 'finance', 'viewer')),

    CONSTRAINT business_user_ownership_unique
        UNIQUE (user_id, business_id)
);

-- Prevent duplicate emails, regardless of letter case
CREATE UNIQUE INDEX business_user_email_unique
    ON business_user (LOWER(email));
    
    -- One wallet per currency per business
CREATE TABLE wallet (
    wallet_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    business_id BIGINT NOT NULL,
    currency_code TEXT NOT NULL,
    balance NUMERIC(20, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT wallet_business_fk
        FOREIGN KEY (business_id)
        REFERENCES business (business_id),

    CONSTRAINT wallet_currency_check
        CHECK (currency_code IN ('NGN', 'CAD', 'GBP', 'USD')),

    CONSTRAINT wallet_balance_check
        CHECK (balance >= 0),

    CONSTRAINT wallet_business_currency_unique
        UNIQUE (business_id, currency_code),

    CONSTRAINT wallet_ownership_unique
        UNIQUE (wallet_id, business_id)
);