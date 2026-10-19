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

-- Supplier bank destinations saved by each business
CREATE TABLE beneficiary (
    beneficiary_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    business_id BIGINT NOT NULL,
    beneficiary_name TEXT NOT NULL,
    country_code TEXT NOT NULL,
    currency_code TEXT NOT NULL,
    bank_name TEXT NOT NULL,
    account_reference TEXT NOT NULL,
    routing_reference TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT beneficiary_business_fk
        FOREIGN KEY (business_id)
        REFERENCES business (business_id),

    CONSTRAINT beneficiary_country_check
        CHECK (country_code IN ('NG', 'CA', 'GB', 'US')),

    CONSTRAINT beneficiary_currency_check
        CHECK (currency_code IN ('NGN', 'CAD', 'GBP', 'USD')),

    CONSTRAINT beneficiary_ownership_currency_unique
        UNIQUE (beneficiary_id, business_id, currency_code)
);

-- Fixed exchange offers issued to businesses
CREATE TABLE fx_quote (
    quote_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    business_id BIGINT NOT NULL,
    source_currency TEXT NOT NULL,
    target_currency TEXT NOT NULL,
    source_amount NUMERIC(20, 2) NOT NULL,
    exchange_rate NUMERIC(24, 12) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT fx_quote_business_fk
        FOREIGN KEY (business_id)
        REFERENCES business (business_id),

    CONSTRAINT fx_quote_source_currency_check
        CHECK (source_currency IN ('NGN', 'CAD', 'GBP', 'USD')),

    CONSTRAINT fx_quote_target_currency_check
        CHECK (target_currency IN ('NGN', 'CAD', 'GBP', 'USD')),

    CONSTRAINT fx_quote_different_currencies_check
        CHECK (source_currency <> target_currency),

    CONSTRAINT fx_quote_source_amount_check
        CHECK (source_amount > 0 AND source_amount <> 'NaN'::NUMERIC),

    CONSTRAINT fx_quote_exchange_rate_check
        CHECK (exchange_rate > 0 AND exchange_rate <> 'NaN'::NUMERIC),

    CONSTRAINT fx_quote_target_amount_check
        CHECK (ROUND(source_amount * exchange_rate, 2) > 0),

    CONSTRAINT fx_quote_expiry_check
        CHECK (expires_at > created_at),

    CONSTRAINT fx_quote_ownership_unique
        UNIQUE (quote_id, business_id)
);

-- Support payment references that enforce beneficiary ownership
ALTER TABLE beneficiary
    ADD CONSTRAINT beneficiary_ownership_unique
    UNIQUE (beneficiary_id, business_id);

-- Instructions to pay saved supplier destinations
CREATE TABLE payment (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    business_id BIGINT NOT NULL,
    wallet_id BIGINT NOT NULL,
    beneficiary_id BIGINT NOT NULL,
    initiated_by BIGINT NOT NULL,
    amount NUMERIC(20, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,

    CONSTRAINT payment_business_fk
        FOREIGN KEY (business_id)
        REFERENCES business (business_id),

    CONSTRAINT payment_wallet_ownership_fk
        FOREIGN KEY (wallet_id, business_id)
        REFERENCES wallet (wallet_id, business_id),

    CONSTRAINT payment_beneficiary_ownership_fk
        FOREIGN KEY (beneficiary_id, business_id)
        REFERENCES beneficiary (beneficiary_id, business_id),

    CONSTRAINT payment_user_ownership_fk
        FOREIGN KEY (initiated_by, business_id)
        REFERENCES business_user (user_id, business_id),

    CONSTRAINT payment_amount_check
        CHECK (amount > 0 AND amount <> 'NaN'::NUMERIC),

    CONSTRAINT payment_status_check
        CHECK (status IN (
            'pending', 'processing', 'completed', 'failed', 'reversed'
        )),

    CONSTRAINT payment_completion_time_check
        CHECK (
            completed_at IS NULL
            OR completed_at >= created_at
        ),

    CONSTRAINT payment_completed_timestamp_check
        CHECK (status <> 'completed' OR completed_at IS NOT NULL),

    CONSTRAINT payment_ownership_unique
        UNIQUE (payment_id, business_id)
);

-- Accounts used to record each side of a money movement
CREATE TABLE ledger_account (
    ledger_account_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_name TEXT NOT NULL,
    account_type TEXT NOT NULL,
    currency_code TEXT NOT NULL,
    wallet_id BIGINT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ledger_account_wallet_fk
        FOREIGN KEY (wallet_id)
        REFERENCES wallet (wallet_id),

    CONSTRAINT ledger_account_type_check
        CHECK (account_type IN (
            'asset', 'liability', 'equity', 'income', 'expense'
        )),

    CONSTRAINT ledger_account_currency_check
        CHECK (currency_code IN ('NGN', 'CAD', 'GBP', 'USD')),

    CONSTRAINT ledger_account_wallet_liability_check
        CHECK (wallet_id IS NULL OR account_type = 'liability')
);

-- Groups the entries belonging to one accounting event
CREATE TABLE ledger_transaction (
    ledger_transaction_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_type TEXT NOT NULL,
    description TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft',
    payment_id BIGINT,
    reversal_of_transaction_id BIGINT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    posted_at TIMESTAMPTZ,

    CONSTRAINT ledger_transaction_payment_fk
        FOREIGN KEY (payment_id)
        REFERENCES payment (payment_id),

    CONSTRAINT ledger_transaction_reversal_fk
        FOREIGN KEY (reversal_of_transaction_id)
        REFERENCES ledger_transaction (ledger_transaction_id),

    CONSTRAINT ledger_transaction_type_check
        CHECK (transaction_type IN (
            'funding', 'fx_conversion', 'payout_processing',
            'payout_settlement', 'reversal'
        )),

    CONSTRAINT ledger_transaction_status_check
        CHECK (status IN ('draft', 'posted')),

    CONSTRAINT ledger_transaction_posted_at_check
        CHECK (
            (status = 'draft' AND posted_at IS NULL)
            OR
            (status = 'posted' AND posted_at IS NOT NULL
                AND posted_at >= created_at)
        ),

    CONSTRAINT ledger_transaction_payout_payment_check
        CHECK (
            transaction_type NOT IN (
                'payout_processing', 'payout_settlement'
            )
            OR payment_id IS NOT NULL
        ),

    CONSTRAINT ledger_transaction_nonpayout_payment_check
        CHECK (
            transaction_type NOT IN ('funding', 'fx_conversion')
            OR payment_id IS NULL
        ),

    CONSTRAINT ledger_transaction_reversal_reference_check
        CHECK (
            (transaction_type = 'reversal'
                AND reversal_of_transaction_id IS NOT NULL)
            OR
            (transaction_type <> 'reversal'
                AND reversal_of_transaction_id IS NULL)
        ),

    CONSTRAINT ledger_transaction_no_self_reversal_check
        CHECK (
            reversal_of_transaction_id IS NULL
            OR reversal_of_transaction_id <> ledger_transaction_id
        ),

    CONSTRAINT ledger_transaction_payment_link_unique
        UNIQUE (ledger_transaction_id, payment_id)
);

-- Individual debits and credits within a ledger transaction
CREATE TABLE ledger_entry (
    ledger_entry_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ledger_transaction_id BIGINT NOT NULL,
    ledger_account_id BIGINT NOT NULL,
    entry_type TEXT NOT NULL,
    amount NUMERIC(20, 2) NOT NULL,

    CONSTRAINT ledger_entry_transaction_fk
        FOREIGN KEY (ledger_transaction_id)
        REFERENCES ledger_transaction (ledger_transaction_id),

    CONSTRAINT ledger_entry_account_fk
        FOREIGN KEY (ledger_account_id)
        REFERENCES ledger_account (ledger_account_id),

    CONSTRAINT ledger_entry_type_check
        CHECK (entry_type IN ('debit', 'credit')),

    CONSTRAINT ledger_entry_amount_check
        CHECK (amount > 0 AND amount <> 'NaN'::NUMERIC)
);

-- Records completed internal currency conversions
CREATE TABLE fx_conversion (
    conversion_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    quote_id BIGINT NOT NULL UNIQUE,
    business_id BIGINT NOT NULL,
    source_wallet_id BIGINT NOT NULL,
    target_wallet_id BIGINT NOT NULL,
    initiated_by BIGINT NOT NULL,
    target_amount NUMERIC(20, 2) NOT NULL,
    ledger_transaction_id BIGINT NOT NULL UNIQUE,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fx_conversion_business_fk
        FOREIGN KEY (business_id)
        REFERENCES business (business_id),

    CONSTRAINT fx_conversion_quote_ownership_fk
        FOREIGN KEY (quote_id, business_id)
        REFERENCES fx_quote (quote_id, business_id),

    CONSTRAINT fx_conversion_source_wallet_fk
        FOREIGN KEY (source_wallet_id, business_id)
        REFERENCES wallet (wallet_id, business_id),

    CONSTRAINT fx_conversion_target_wallet_fk
        FOREIGN KEY (target_wallet_id, business_id)
        REFERENCES wallet (wallet_id, business_id),

    CONSTRAINT fx_conversion_user_ownership_fk
        FOREIGN KEY (initiated_by, business_id)
        REFERENCES business_user (user_id, business_id),

    CONSTRAINT fx_conversion_ledger_transaction_fk
        FOREIGN KEY (ledger_transaction_id)
        REFERENCES ledger_transaction (ledger_transaction_id),

    CONSTRAINT fx_conversion_different_wallets_check
        CHECK (source_wallet_id <> target_wallet_id),

    CONSTRAINT fx_conversion_target_amount_check
        CHECK (
            target_amount > 0
            AND target_amount <> 'NaN'::NUMERIC
        )
);

-- Records the initial status and later payment status changes
CREATE TABLE payment_status_history (
    history_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_id BIGINT NOT NULL,
    from_status TEXT,
    to_status TEXT NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actor_type TEXT NOT NULL,
    changed_by BIGINT,
    reason TEXT NOT NULL,
    ledger_transaction_id BIGINT,

    CONSTRAINT payment_history_payment_fk
        FOREIGN KEY (payment_id)
        REFERENCES payment (payment_id),

    CONSTRAINT payment_history_user_fk
        FOREIGN KEY (changed_by)
        REFERENCES business_user (user_id),

    CONSTRAINT payment_history_ledger_payment_fk
        FOREIGN KEY (ledger_transaction_id, payment_id)
        REFERENCES ledger_transaction (
            ledger_transaction_id, payment_id
        ),

    CONSTRAINT payment_history_from_status_check
        CHECK (from_status IN (
            'pending', 'processing', 'completed', 'failed', 'reversed'
        )),

    CONSTRAINT payment_history_to_status_check
        CHECK (to_status IN (
            'pending', 'processing', 'completed', 'failed', 'reversed'
        )),

    CONSTRAINT payment_history_initial_status_check
        CHECK (from_status IS NOT NULL OR to_status = 'pending'),

    CONSTRAINT payment_history_status_change_check
        CHECK (from_status IS NULL OR from_status <> to_status),

    CONSTRAINT payment_history_actor_check
        CHECK (
            (actor_type = 'user' AND changed_by IS NOT NULL)
            OR
            (actor_type = 'system' AND changed_by IS NULL)
        ),

    CONSTRAINT payment_history_reason_check
        CHECK (LENGTH(BTRIM(reason)) > 0)
);

-- Records actions and their outcomes
CREATE TABLE audit_event (
    audit_event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    business_id BIGINT NOT NULL,
    actor_type TEXT NOT NULL,
    actor_user_id BIGINT,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id BIGINT,
    outcome TEXT NOT NULL,
    details JSONB NOT NULL DEFAULT '{}'::JSONB,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT audit_event_business_fk
        FOREIGN KEY (business_id)
        REFERENCES business (business_id),

    CONSTRAINT audit_event_user_ownership_fk
        FOREIGN KEY (actor_user_id, business_id)
        REFERENCES business_user (user_id, business_id),

    CONSTRAINT audit_event_actor_check
        CHECK (
            (actor_type = 'user' AND actor_user_id IS NOT NULL)
            OR
            (actor_type = 'system' AND actor_user_id IS NULL)
        ),

    CONSTRAINT audit_event_outcome_check
        CHECK (outcome IN ('success', 'failure')),

    CONSTRAINT audit_event_details_object_check
        CHECK (jsonb_typeof(details) = 'object'),

    CONSTRAINT audit_event_action_check
        CHECK (LENGTH(BTRIM(action)) > 0),

    CONSTRAINT audit_event_entity_type_check
        CHECK (LENGTH(BTRIM(entity_type)) > 0)
);
