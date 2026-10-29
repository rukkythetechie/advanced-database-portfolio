# Corridor Pay | ER Diagram

## Scope

This diagram represents the 12-table base schema tested in
`corridorpay_p1_check` during Portfolio 1.

Financial routines, triggers and restricted application permissions
were subsequently added in
[Portfolio 3](../portfolio-3-transactions-concurrency/README.md).

The diagram shows structural relationships. It does not, by itself,
demonstrate enforcement of financial posting rules or application
permissions.

Uppercase entity labels correspond to lowercase SQL table names.

```mermaid
erDiagram
    BUSINESS ||--o{ BUSINESS_USER : has
    BUSINESS ||--o{ WALLET : owns
    BUSINESS ||--o{ BENEFICIARY : saves
    BUSINESS ||--o{ FX_QUOTE : receives
    BUSINESS ||--o{ FX_CONVERSION : performs
    BUSINESS ||--o{ PAYMENT : requests
    BUSINESS ||--o{ AUDIT_EVENT : concerns

    WALLET ||--o{ PAYMENT : funds
    BENEFICIARY ||--o{ PAYMENT : receives
    BUSINESS_USER ||--o{ PAYMENT : initiates

    FX_QUOTE ||--o| FX_CONVERSION : accepted_for
    WALLET ||--o{ FX_CONVERSION : source_wallet
    WALLET ||--o{ FX_CONVERSION : target_wallet
    BUSINESS_USER ||--o{ FX_CONVERSION : initiates

    WALLET |o--o| LEDGER_ACCOUNT : links_wallet_liability
    LEDGER_TRANSACTION ||--o| FX_CONVERSION : records_exchange
    PAYMENT |o--o{ LEDGER_TRANSACTION : has_postings
    LEDGER_TRANSACTION ||--o{ LEDGER_ENTRY : groups
    LEDGER_ACCOUNT ||--o{ LEDGER_ENTRY : receives_entries
    LEDGER_TRANSACTION |o--o| LEDGER_TRANSACTION : reversed_by

    PAYMENT ||--o{ PAYMENT_STATUS_HISTORY : has_history
    BUSINESS_USER |o--o{ PAYMENT_STATUS_HISTORY : triggers
    LEDGER_TRANSACTION |o--o{ PAYMENT_STATUS_HISTORY : supports
    BUSINESS_USER |o--o{ AUDIT_EVENT : triggers

    BUSINESS {
        bigint business_id PK
        text business_name
        text country_code
        text registration_number
        text contact_email
        text kyb_status
        timestamptz created_at
    }

    BUSINESS_USER {
        bigint user_id PK
        bigint business_id FK
        text full_name
        text email "Unique through LOWER(email)"
        text role
        boolean is_active
        timestamptz created_at
    }

    WALLET {
        bigint wallet_id PK
        bigint business_id FK
        text currency_code
        numeric balance
        timestamptz created_at
    }

    BENEFICIARY {
        bigint beneficiary_id PK
        bigint business_id FK
        text beneficiary_name
        text country_code
        text currency_code
        text bank_name
        text account_reference
        text routing_reference "Optional"
        timestamptz created_at
    }

    FX_QUOTE {
        bigint quote_id PK
        bigint business_id FK
        text source_currency
        text target_currency
        numeric source_amount
        numeric exchange_rate
        timestamptz created_at
        timestamptz expires_at
    }

    FX_CONVERSION {
        bigint conversion_id PK
        bigint quote_id FK, UK
        bigint business_id FK
        bigint source_wallet_id FK
        bigint target_wallet_id FK
        bigint initiated_by FK
        numeric target_amount
        bigint ledger_transaction_id FK, UK
        timestamptz completed_at
    }

    PAYMENT {
        bigint payment_id PK
        bigint business_id FK
        bigint wallet_id FK
        bigint beneficiary_id FK
        bigint initiated_by FK
        numeric amount
        text status
        timestamptz created_at
        timestamptz completed_at "Optional"
    }

    LEDGER_ACCOUNT {
        bigint ledger_account_id PK
        text account_name
        text account_type
        text currency_code
        bigint wallet_id FK, UK "Optional; wallet liability only"
        timestamptz created_at
    }

    LEDGER_TRANSACTION {
        bigint ledger_transaction_id PK
        text transaction_type
        text description
        text status
        bigint payment_id FK "Optional; required for processing and settlement"
        bigint reversal_of_transaction_id FK, UK "Optional; required for reversal type"
        timestamptz created_at
        timestamptz posted_at "Required when posted"
    }

    LEDGER_ENTRY {
        bigint ledger_entry_id PK
        bigint ledger_transaction_id FK
        bigint ledger_account_id FK
        text entry_type
        numeric amount
    }

    PAYMENT_STATUS_HISTORY {
        bigint history_id PK
        bigint payment_id FK
        text from_status "Optional for initial pending record"
        text to_status
        timestamptz changed_at
        text actor_type
        bigint changed_by FK "Optional; required for user actors"
        text reason
        bigint ledger_transaction_id FK "Optional; must match payment"
    }

    AUDIT_EVENT {
        bigint audit_event_id PK
        bigint business_id FK
        text actor_type
        bigint actor_user_id FK "Optional; required for user actors"
        text action
        text entity_type
        bigint entity_id "Optional; generic reference"
        text outcome
        jsonb details
        timestamptz occurred_at
    }
```

## Reading the diagram

- PK means primary key.
- FK means foreign key.
- UK marks an individual column with a uniqueness constraint.
- Nullable unique references are not candidate keys for the whole table.
- `||` means exactly one.
- `|o` or `o|` means zero or one.
- `o{` means zero or many.
- The symbol beside an entity describes how many of that entity
  may relate to one record at the other end.

Each conversion references two wallets: a source and a target.
It also references exactly one ledger transaction.
A ledger transaction can be referenced by zero or one conversion.

A payment may have zero or many ledger transactions.
Creating a pending payment does not require a financial posting.

An original ledger transaction may have zero or one full reversal.
Transactions of type `reversal` must reference an original transaction.

User references in history and audit events are empty for system actions.

## Structural minimums and operational requirements

The base schema permits a wallet to have zero or one linked account.
The intended model requires one matching liability account.
The demonstrations create the wallet and account together
administratively. Platform accounts have no wallet.

The base schema permits a payment to have zero or more history
records. Initial pending history is prepared administratively
in the demonstrations; automatic creation is not implemented.

The base schema permits a ledger transaction to have zero or more
entries. Portfolio 3 adds posting logic requiring at least two
entries and equal debits and credits within each currency.

## Keys and constraints enforced by the base schema

### Businesses, users and wallets

- Supported countries are NG, CA, GB and US.
- Supported currencies are NGN, CAD, GBP and USD.
- `UNIQUE(country_code, registration_number)` prevents duplicate
  registration references within a country.
- A unique index on `LOWER(email)` prevents duplicate user emails
  regardless of letter case.
- User roles are limited to admin, finance and viewer.
- `UNIQUE(business_id, currency_code)` permits one wallet per
  currency per business.
- Wallet balances default to zero and have a non-negative check.
- Composite foreign keys enforce payment ownership of its wallet,
  beneficiary and initiating user.
- Composite foreign keys enforce conversion ownership of its quote,
  both wallets and initiating user.

### Beneficiaries and FX quotes

- Beneficiaries reference an existing business and use supported
  country and currency codes.
- Account references are text, preserving letters and leading zeros.
- Routing references are optional.
- Separate businesses may save the same supplier destination.
- Quote source and target currencies must differ.
- Quote amounts and rates must be positive and exclude numeric NaN.
- The calculated quote target must remain positive after rounding
  to two decimal places.
- Quote expiry must be later than creation.
- Conversion quote references are unique.
- Conversion source and target wallet identifiers must differ.
- Conversion target amounts must be positive and exclude numeric NaN.
- A conversion's ledger transaction cannot be shared by another
  conversion.

### Payments and ledger records

- Payment amounts must be positive and exclude numeric NaN.
- Payment status is pending, processing, completed, failed or reversed.
- A completed payment requires `completed_at`.
- A populated completion timestamp cannot precede payment creation.
- A wallet can link to at most one ledger account.
- A wallet-linked account must be a liability.
- Account types and currencies are restricted to supported values.
- Ledger entries reference existing accounts and transactions.
- Entry types are debit or credit; amounts are positive and exclude
  numeric NaN.
- Ledger transaction status is draft or posted.
- Draft transactions have no posting timestamp.
- Posted transactions require a posting timestamp no earlier
  than creation.
- Processing and settlement transactions require a payment reference.
- Funding and FX transactions have no payment reference.
- Reversal transactions require an original-transaction reference;
  other transaction types cannot have one.
- A transaction cannot reverse itself.
- Each original transaction can have at most one full reversal.

### History and audit records

- History references an existing payment.
- A linked history ledger transaction must belong to that payment.
- A null `from_status` is permitted only for an initial pending record.
- A populated `from_status` cannot equal `to_status`.
- History reasons are required and cannot be blank.
- User actors require a user reference; system actors have none.
- Audit user actors must belong to the event's business.
- Audit outcomes are success or failure.
- Audit details must be a JSON object and default to `{}`.
- Audit action and entity type cannot be blank.
- Generic audit `entity_id` has no foreign key because it can
  refer to different tables.

Composite uniqueness constraints supporting ownership foreign keys
are defined in `schema.sql`. They are not shown as individual-column
unique keys in this diagram.

## Protections added in Portfolio 3

Portfolio 3 adds operational checks and protections beyond the
structural relationships shown above:

- Active-user, role, business-approval and ownership checks
  in controlled financial routines.
- Wallet and beneficiary currency matching during processing.
- Quote currency, calculation, expiry and reuse checks.
- Protection of quote terms against changes.
- Zero opening wallet balances and protected wallet identity fields.
- Balanced ledger posting and atomic wallet updates.
- Protection of posted transactions, entries and account properties.
- Locked sufficient-funds checks for competing debits.
- Controlled processing, settlement and full reversal routines.
- Duplicate processing and settlement protections.
- Financial status, history and success-audit changes saved together.
- Restricted backend permissions preventing direct application writes.

These protections have specific boundaries. Their exact behaviour
and evidence are documented in the Portfolio 3 guide.

## Remaining limitations

- Customer authentication and row-level security are not implemented.
- Reads through the application role are not isolated by tenant.
- Wallet/account creation and initial payment history are prepared
  administratively.
- Dedicated immutable-payment and used-beneficiary triggers
  are not implemented.
- Restricted application permissions do not prevent privileged
  administrators from making direct changes.
- Failed-attempt auditing requires a separate transaction after
  rollback. Concurrency session B demonstrates that approach.
- Generic audit references cannot enforce every entity relationship
  through a single foreign key.

## Implementation evidence

The full schema was built in `corridorpay_p1_check`.

Its 35 numbered structural tests produced the reviewed expected
outcomes, including 25 intentional constraint errors.
The final rollback left all 12 tables empty.

Scripts, execution transcripts and selected screenshots are stored
in this portfolio folder. The normalisation analysis is maintained
separately.

These structural tests establish the captured schema behaviour.
Financial operations and concurrency demonstrations are evidenced
separately in Portfolio 3.

Real banking, external FX settlement, working customer authentication,
fees, overdrafts and partial reversals are outside the prototype's scope.