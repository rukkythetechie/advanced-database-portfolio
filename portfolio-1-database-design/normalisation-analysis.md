# Corridor Pay Normalisation Analysis

This document reviews the Corridor Pay database structure using candidate keys and functional dependencies. All 12 tables have been created and their structural constraints tested in `corridorpay_p1_check`. Operational routines and access controls remain to be implemented.

## 1. Purpose and method

I reviewed the 12 tables using their business rules, candidate keys and functional dependencies. The aim is to reduce unnecessary duplication and avoid conflicting information when records are updated.

The following terms are used throughout:

- **Candidate key:** a minimal set of fields that uniquely identifies every row. An optional field marked UNIQUE is not a candidate key for the entire table.
- **Functional dependency:** X → Y means that rows with the same value of X must have the same value of Y.
- **1NF:** fields contain individual values, without repeating groups.
- **2NF:** the table meets 1NF, and no non-prime attribute depends on only part of a candidate key.
- **3NF:** for every non-trivial dependency X → A, X is a superkey or A belongs to a candidate key.

A superkey uniquely identifies a row. An attribute belonging to any candidate key is called a prime attribute. These definitions guide the analysis rather than treating every repeated value as a normalisation violation (University of Waterloo, 2026).

Optional references need particular care. A nullable unique field is not a candidate key for the whole table, but its populated values identify at most one row. PostgreSQL normally allows multiple null values in a unique column (PostgreSQL Global Development Group, n.d.).

The analysis uses the declared business rules as well as the implemented constraints. Where a rule still needs operational enforcement, that does not mean it has already been verified by the structural tests.

## 2. Overview of findings

Six tables meet 3NF under the stated assumptions. Payment and FX Conversion deliberately depart from strict 3NF by repeating business ownership information. Ledger Account and Ledger Transaction have no established ordinary 3NF violation under the dependencies reviewed. Payment Status History and Audit Event contain conditional redundancy that needs separate explanation.

| Table | Candidate keys | Assessment |
| :---- | :---- | :---- |
| Business | business_id; (country_code, registration_number) | 3NF |
| Business User | user_id; email compared case-insensitively | 3NF |
| Wallet | wallet_id; (business_id, currency_code) | 3NF within the table; balance is derived from the ledger |
| Beneficiary | beneficiary_id | 3NF under prototype assumptions |
| FX Quote | quote_id | 3NF |
| FX Conversion | conversion_id; quote_id; ledger_transaction_id | 2NF; deliberate ownership-related departure from 3NF |
| Payment | payment_id | 2NF; deliberate ownership-related departure from 3NF |
| Ledger Account | ledger_account_id | No ordinary 3NF violation established; conditional wallet rules apply |
| Ledger Transaction | ledger_transaction_id | No ordinary 3NF violation established; reversal consistency rules apply |
| Ledger Entry | ledger_entry_id | 3NF |
| Payment Status History | history_id | Conditional redundancy in records with ledger references |
| Audit Event | audit_event_id | Conditional ownership redundancy; JSON context assessed separately |

These conclusions depend on the declared business rules. Additional rules could introduce dependencies that require a fresh analysis.

The composite unique constraints containing an existing primary key, such as `UNIQUE(user_id, business_id)`, support foreign-key references. They are superkeys rather than additional candidate keys because they are not minimal.

## 3. Table-by-table analysis

### 3.1 Business

The candidate keys are `business_id` and the combination of `country_code` and `registration_number`.

`business_id → business_name, country_code, registration_number, contact_email, kyb_status, created_at`

The country-and-registration combination also determines the complete record.

The table meets 1NF because each field stores an individual value. It meets 2NF because the non-prime attributes depend on the whole of each candidate key, not just the country or registration number.

Under the stated rules, no non-key determinant introduces a transitive dependency that violates 3NF. Business names and contact emails are not assumed to be unique.

### 3.2 Business User

The candidate keys are `user_id` and email under case-insensitive comparison. The SQL implementation uses a unique index on `LOWER(email)`.

`user_id → business_id, full_name, email, role, is_active, created_at`

The case-insensitive email key also determines the complete user record.

Each user belongs to one business and has one role. The fields contain individual values, meeting 1NF. Neither candidate key has a proper subset on which a non-prime attribute could depend, so the table meets 2NF.

Business details remain in Business instead of being repeated for every employee. No non-key field determines another under the stated rules, so the table meets 3NF.

The composite unique constraint on `(user_id, business_id)` supports ownership foreign keys. It is not another candidate key because `user_id` alone already identifies the row.

### 3.3 Wallet

The candidate keys are `wallet_id` and `(business_id, currency_code)`.

`wallet_id → business_id, currency_code, balance, created_at`

The business-and-currency combination also determines the complete wallet record.

Each row stores one currency and one balance, meeting 1NF. Balance and creation time depend on the whole composite key. Neither the business nor the currency alone identifies these values, so the table meets 2NF.

Under the stated rules, Wallet has no transitive dependencies that violate 3NF.

The stored balance nevertheless duplicates a total calculated from posted ledger entries. This is cross-table redundancy, not automatically a 3NF violation within Wallet. Atomic posting routines and reconciliation are planned to keep it consistent with the ledger; they are not yet implemented.

### 3.4 Beneficiary

The only declared candidate key is `beneficiary_id`.

`beneficiary_id → business_id, beneficiary_name, country_code, currency_code, bank_name, account_reference, routing_reference, created_at`

Each record represents one receiving account with individual field values, meeting 1NF. The single-attribute key has no partial dependencies, so the table meets 2NF.

For this prototype, bank names and routing references are treated as saved destination details. The design does not assume that a routing reference determines a standard bank record. Under these assumptions, no transitive dependencies are asserted, and the table meets 3NF.

Bank-account details are not candidate keys. Different businesses can save the same destination, and duplicates within a business have not been prohibited.

The composite unique constraints containing `beneficiary_id` support ownership and currency references. They are not minimal keys.

If bank-directory rules are introduced later, their dependencies will need to be analysed separately.

### 3.5 FX Quote

The only declared candidate key is `quote_id`.

`quote_id → business_id, source_currency, target_currency, source_amount, exchange_rate, created_at, expires_at`

Each row records one offer using individual values, meeting 1NF. Its single-attribute key has no partial dependencies, so it meets 2NF.

The currency pair does not determine the rate because quotes for the same currencies may offer different rates. Creation time does not determine expiry because a fixed quote duration has not been imposed.

No transitive dependencies are asserted under these rules, so the table meets 3NF.

### 3.6 FX Conversion

The candidate keys are `conversion_id`, `quote_id` and `ledger_transaction_id`. Each is required and unique.

`conversion_id → quote_id, business_id, source_wallet_id, target_wallet_id, initiated_by, target_amount, ledger_transaction_id, completed_at`

Each of the other candidate keys also determines the complete record.

The table meets 1NF. All candidate keys are single attributes, so there are no partial dependencies, and it meets 2NF.

Each source wallet, target wallet and initiating user belongs to one business. Their references therefore determine `business_id`, but they are not superkeys of FX Conversion because they may appear in many conversions.

For example:

`source_wallet_id → business_id`

The determinant is not a superkey, and `business_id` is not prime. The table therefore deliberately departs from strict 3NF by retaining explicit business ownership.

Composite foreign keys enforce agreement between the conversion's business ID and its linked quote, wallets and initiating user.

Under the intended calculation rule, the rounded `target_amount` is determined by the accepted quote. Since `quote_id` is a candidate key, storing that result does not itself violate 3NF. Verification that the stored amount matches the quote calculation still requires additional enforcement.

### 3.7 Payment

The only declared candidate key is `payment_id`.

`payment_id → business_id, wallet_id, beneficiary_id, initiated_by, amount, status, created_at, completed_at`

Each row represents one instruction with individual values, meeting 1NF. Its single-attribute key has no partial dependencies, so it meets 2NF.

The wallet, beneficiary and initiating user each determine the business they belong to. None uniquely identifies a payment because each may appear in many payments.

For example:

`wallet_id → business_id`

Keeping `business_id` therefore creates transitive dependencies and deliberately departs from strict 3NF. Composite foreign keys enforce consistent payment ownership.

Keeping the current status alongside a separate status history also requires coordinated updates. That is an integrity requirement rather than an additional normal-form conclusion. Atomic status and history updates are not yet implemented.

### 3.8 Ledger Account

The only unconditional candidate key is `ledger_account_id`.

`ledger_account_id → account_name, account_type, currency_code, wallet_id, created_at`

Although `wallet_id` is unique when present, platform accounts leave it empty. It is not a candidate key for the whole table.

The ordinary fields hold individual values, and the single unconditional key has no partial dependencies.

For populated wallet references, uniqueness ensures that a wallet identifies at most one ledger-account row. Therefore, the wallet's currency and required liability classification do not, by themselves, establish a non-key dependency across multiple account rows.

No ordinary 3NF violation has been established from the stated dependencies. Conditional integrity rules still apply.

The liability classification for wallet-linked accounts is enforced by a CHECK constraint. Matching wallet currency, protecting the wallet association and ensuring every wallet has an account require additional enforcement.

### 3.9 Ledger Transaction

The only unconditional candidate key is `ledger_transaction_id`.

`ledger_transaction_id → transaction_type, description, status, payment_id, reversal_of_transaction_id, created_at, posted_at`

The optional reversal reference is unique when present, but it does not identify every row.

Each row records one financial event, with entries stored separately, meeting 1NF. The single unconditional key has no partial dependencies.

For a reversal, the intended rule is that the original transaction establishes which payment is being reversed. However, when populated, the original reference is unique, so it identifies at most one reversal row.

No ordinary 3NF violation has been established from that reference. Agreement between the reversal's payment ID and the original transaction's payment ID still requires enforcement.

Checking balanced debits and credits is a separate financial correctness requirement.

### 3.10 Ledger Entry

The only declared candidate key is `ledger_entry_id`.

`ledger_entry_id → ledger_transaction_id, ledger_account_id, entry_type, amount`

Each row records one debit or credit, meeting 1NF. Its single-attribute key has no partial dependencies, so it meets 2NF.

Currency is obtained from Ledger Account, while financial-event details remain in Ledger Transaction. Neither is repeated in each entry.

There are no transitive dependencies between the stored non-key fields under the stated rules, so the table meets 3NF.

The transaction-and-account combination is not assumed unique. A transaction may contain several entries affecting the same account.

### 3.11 Payment Status History

The only declared candidate key is `history_id`.

`history_id → payment_id, from_status, to_status, changed_at, actor_type, changed_by, reason, ledger_transaction_id`

Each row records one status event with individual values. The single-attribute key has no partial dependencies.

Within records containing payout ledger references:

`ledger_transaction_id → payment_id`

Unlike the wallet reference in Ledger Account, this ledger reference is not declared unique. The same posting could therefore appear in multiple history records, repeating the payment it identifies.

The design retains `payment_id` so every event directly identifies its payment, including events without ledger postings. A composite foreign key ensures that a linked ledger transaction belongs to the same payment.

Within user-triggered records, the actor rules also mean:

`changed_by → actor_type`

This applies only to the subset with populated user references. System events have no `changed_by` value.

These conditional dependencies need separate treatment rather than an unqualified strict-3NF claim. The previous and new statuses describe the event; neither status alone determines its timestamp, actor or reason.

### 3.12 Audit Event

The only declared candidate key is `audit_event_id`.

`audit_event_id → business_id, actor_type, actor_user_id, action, entity_type, entity_id, outcome, details, occurred_at`

The ordinary columns store individual event attributes, and the single-attribute key has no partial dependencies.

Within user-triggered events:

`actor_user_id → business_id, actor_type`

One user may trigger many events, so the repeated business ID introduces conditional ownership redundancy. It is retained so both user-triggered and system-triggered events directly identify the business concerned.

A composite foreign key enforces agreement between the audit event's business and its user actor. The actor CHECK constraint requires user references for user actors and no user reference for system actors.

The JSON details field stores flexible event context. Its internal structure is not analysed as a fully normalised set of relational attributes. The use of JSON alone does not establish a 3NF violation.

The audit table therefore receives a qualified assessment that separates ownership redundancy from its structured event context.

## 4. Repeated and calculated data

Some information is retained for practical reasons. Each choice needs an appropriate consistency control.

| Retained information | Tables | Consistency control |
| :---- | :---- | :---- |
| Explicit business_id | Payment and FX Conversion | Implemented composite foreign keys |
| Stored wallet balance | Wallet | Atomic posting and reconciliation; pending |
| Wallet currency and liability classification | Ledger Account | Liability check implemented; wallet currency matching pending |
| Payment reference on reversals | Ledger Transaction | Agreement with the original transaction; pending |
| Payment reference alongside a ledger link | Payment Status History | Implemented composite foreign key |
| Current status and status history | Payment and Payment Status History | Atomic updates; pending |
| Business reference for user actors | Audit Event | Implemented composite foreign key |
| Flexible event context | Audit Event | JSON-object check implemented; sensitive-data restrictions pending |

These items are not all the same kind of normalisation issue. Some are established transitive dependencies, some apply only to particular records, and others are cross-table calculations or integrity rules.

## 5. Limits of this analysis

Normalisation does not establish that a user has permission, a wallet has sufficient funds, a quote is unexpired at execution or a ledger transaction balances.

The full schema has been built successfully, and the structural test results have been reviewed. This does not establish that operational financial rules are enforced. Posting routines, permissions, concurrency control and reconciliation require separate implementation and testing.

The deliberate departures from strict 3NF are documented rather than presented as fully normalised tables. Composite foreign keys protect ownership consistency, but the retained redundancy remains part of the design.

## 6. References

University of Waterloo. *Data Dependencies and Normal Forms*, CS 348, Winter 2026.

https://cs.uwaterloo.ca/~david/cs348/handout-FD.pdf

PostgreSQL Global Development Group. *PostgreSQL Documentation: Constraints*.

https://www.postgresql.org/docs/current/ddl-constraints.html