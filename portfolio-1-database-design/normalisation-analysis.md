# Corridor Pay Normalisation Analysis

## Scope

This document analyses the 12-table base schema tested in
`corridorpay_p1_check` during Portfolio 1.

Operational routines, transaction tests and restricted application
permissions were subsequently added in
[Portfolio 3](../portfolio-3-transactions-concurrency/README.md).

Normalisation conclusions are distinguished from operational
checks and implementation evidence.

## 1. Purpose and method

The analysis uses business rules, candidate keys and functional
dependencies to identify unnecessary duplication and possible
update inconsistencies.

The following terms are used:

- **Candidate key:** a minimal set of attributes identifying every row.
- **Superkey:** a set of attributes identifying every row, which
  need not be minimal.
- **Prime attribute:** an attribute belonging to a candidate key.
- **Functional dependency:** X → Y means rows agreeing on X
  must agree on Y.
- **1NF:** individual field values without repeating groups.
- **2NF:** 1NF, with no non-prime attribute depending on only
  part of a candidate key.
- **3NF:** for every non-trivial dependency X → A, either X
  is a superkey or A is a prime attribute.

These definitions distinguish actual dependencies from values
that merely happen to repeat.

Nullable unique fields require care. They do not identify every
row and are not candidate keys for the entire table.
PostgreSQL's default unique constraints permit multiple nulls.

The analysis considers declared business rules as well as
implemented constraints. A stated operational rule does not imply
that Portfolio 1's structural tests verified its enforcement.

## 2. Overview of findings

Six tables meet 3NF under the stated assumptions.
Payment and FX Conversion deliberately retain ownership information
that departs from strict 3NF.

Nullable references and conditional dependencies receive qualified
assessments rather than an unqualified claim that every table
is fully normalised.

| Table | Candidate keys | Assessment |
| :--- | :--- | :--- |
| Business | business_id; (country_code, registration_number) | 3NF |
| Business User | user_id; email under case-insensitive comparison | 3NF |
| Wallet | wallet_id; (business_id, currency_code) | 3NF within the table; balance is derived from ledger records |
| Beneficiary | beneficiary_id | 3NF under prototype assumptions |
| FX Quote | quote_id | 3NF |
| FX Conversion | conversion_id; quote_id; ledger_transaction_id | 2NF; deliberate ownership-related departure from 3NF |
| Payment | payment_id | 2NF; deliberate ownership-related departure from 3NF |
| Ledger Account | ledger_account_id | No ordinary 3NF violation established; conditional wallet rules apply |
| Ledger Transaction | ledger_transaction_id | No ordinary 3NF violation established; reversal consistency rules apply |
| Ledger Entry | ledger_entry_id | 3NF |
| Payment Status History | history_id | Conditional redundancy in records with ledger or user references |
| Audit Event | audit_event_id | Conditional ownership redundancy; JSON context assessed separately |

These conclusions depend on the stated assumptions.
Additional business rules may introduce further dependencies.

Composite unique constraints containing an existing primary key,
such as `UNIQUE(user_id, business_id)`, support ownership foreign
keys. They are superkeys rather than additional candidate keys,
because they are not minimal.

## 3. Table-by-table analysis

### 3.1 Business

Candidate keys:

- `business_id`
- `(country_code, registration_number)`

Dependency:

`business_id → business_name, country_code, registration_number,
contact_email, kyb_status, created_at`

The country-and-registration combination also determines the
complete record.

Each field contains an individual value. Non-prime attributes
depend on the whole composite candidate key, rather than country
or registration number alone.

Business names and contact emails are not assumed unique.
No further non-key determinant is asserted.

The table meets 3NF under these rules.

### 3.2 Business User

Candidate keys:

- `user_id`
- Email under case-insensitive comparison, implemented through
  a unique index on `LOWER(email)`.

Dependency:

`user_id → business_id, full_name, email, role, is_active, created_at`

The case-insensitive email key also identifies the complete record.

Each user belongs to one business and has one role.
The candidate keys have no partial dependencies.
Business details remain in Business.

No non-key field determines another under the stated assumptions.
The table meets 3NF.

`UNIQUE(user_id, business_id)` supports ownership foreign keys.
It is not minimal because `user_id` already identifies the row.

### 3.3 Wallet

Candidate keys:

- `wallet_id`
- `(business_id, currency_code)`

Dependency:

`wallet_id → business_id, currency_code, balance, created_at`

The business-and-currency combination also identifies the record.

Balance and creation time depend on the whole composite key.
Neither business nor currency alone determines them.

No transitive dependency violating 3NF is asserted within Wallet.

The stored balance nevertheless duplicates a total calculated from
posted ledger entries. This is cross-table derived information,
rather than automatically a 3NF violation within Wallet.

Portfolio 3 implements atomic posting and demonstrates reconciliation
between stored balances and posted ledger totals.

### 3.4 Beneficiary

Candidate key:

- `beneficiary_id`

Dependency:

`beneficiary_id → business_id, beneficiary_name, country_code,
currency_code, bank_name, account_reference, routing_reference,
created_at`

Each row represents one receiving account. Its single-attribute
candidate key has no partial dependencies.

Bank names and routing details are treated as saved destination
information. The prototype does not assume a routing reference
determines a standard bank-directory record.

Under these assumptions, the table meets 3NF.

Bank details are not candidate keys. Different businesses may
save the same destination, and duplicates within a business
have not been prohibited.

Composite unique constraints containing `beneficiary_id` support
foreign keys but are not minimal keys.

Introducing a bank directory would require a fresh dependency analysis.

### 3.5 FX Quote

Candidate key:

- `quote_id`

Dependency:

`quote_id → business_id, source_currency, target_currency,
source_amount, exchange_rate, created_at, expires_at`

The single-attribute key has no partial dependencies.

A currency pair does not determine its rate because different
quotes may offer different rates. Creation time does not determine
expiry because a fixed quote duration is not imposed.

No further transitive dependencies are asserted.
The table meets 3NF.

### 3.6 FX Conversion

Candidate keys:

- `conversion_id`
- `quote_id`
- `ledger_transaction_id`

All three are required and unique.

Dependency:

`conversion_id → quote_id, business_id, source_wallet_id,
target_wallet_id, initiated_by, target_amount,
ledger_transaction_id, completed_at`

Each other candidate key also identifies the complete record.

All candidate keys are single attributes, so the table has
no partial dependencies and meets 2NF.

Each wallet and initiating user belongs to one business.
For example:

`source_wallet_id → business_id`

A source wallet may appear in many conversions, so it is not
a superkey of FX Conversion. `business_id` is not prime.

Retaining explicit business ownership therefore deliberately
departs from strict 3NF.

Composite foreign keys ensure agreement between the conversion's
business and its quote, wallets and initiating user.

Under the calculation rule, the accepted quote determines the
rounded target amount. Because `quote_id` is a candidate key,
storing that result does not itself violate 3NF.

Portfolio 3's conversion routine calculates the amount and
enforces the operational checks.

### 3.7 Payment

Candidate key:

- `payment_id`

Dependency:

`payment_id → business_id, wallet_id, beneficiary_id,
initiated_by, amount, status, created_at, completed_at`

The single-attribute key has no partial dependencies.
The table meets 2NF.

Its wallet, beneficiary and initiating user each determine
their business. For example:

`wallet_id → business_id`

A wallet may appear in many payments and is not a superkey.
The repeated `business_id` therefore creates a deliberate
departure from strict 3NF.

Composite foreign keys enforce consistent ownership.

Keeping current status alongside status history requires coordinated
updates. This is a cross-table integrity requirement.
Portfolio 3 implements atomic updates for its controlled
payment routines.

### 3.8 Ledger Account

Unconditional candidate key:

- `ledger_account_id`

Dependency:

`ledger_account_id → account_name, account_type,
currency_code, wallet_id, created_at`

Although `wallet_id` is unique when present, platform accounts
leave it empty. It is not a candidate key for the whole table.

The single unconditional candidate key has no partial dependencies.

A populated wallet reference identifies at most one account row.
The wallet's currency and liability classification do not, by
themselves, establish a non-key dependency across multiple
account rows.

No ordinary 3NF violation is established from the reviewed
dependencies. Conditional integrity rules still apply.

The base schema requires wallet-linked accounts to be liabilities.
Portfolio 3 adds wallet currency matching and association protections.

Ensuring every wallet is created with an account remains an
administrative setup responsibility in the demonstrations.

### 3.9 Ledger Transaction

Unconditional candidate key:

- `ledger_transaction_id`

Dependency:

`ledger_transaction_id → transaction_type, description,
status, payment_id, reversal_of_transaction_id,
created_at, posted_at`

The optional reversal reference is unique when populated but
does not identify every row.

Entries are stored separately, avoiding repeating entry groups.
The single unconditional key has no partial dependencies.

For a reversal, the original transaction establishes the related
payment. However, the populated original reference identifies
at most one reversal row because it is unique.

No ordinary 3NF violation is established from that reference.
Agreement between the original and reversal payment references
remains an integrity requirement.

Balanced posting and correct reversal entries are financial
correctness requirements, separate from normalisation.
Portfolio 3 addresses these through posting protections
and controlled reversal logic.

### 3.10 Ledger Entry

Candidate key:

- `ledger_entry_id`

Dependency:

`ledger_entry_id → ledger_transaction_id,
ledger_account_id, entry_type, amount`

Each row records one debit or credit.
Its single-attribute key has no partial dependencies.

Currency is obtained from Ledger Account. Financial-event details
remain in Ledger Transaction.

No transitive dependencies between stored non-key fields are
asserted. The table meets 3NF.

The transaction-and-account combination is not assumed unique:
a transaction may contain several entries affecting one account.

### 3.11 Payment Status History

Candidate key:

- `history_id`

Dependency:

`history_id → payment_id, from_status, to_status,
changed_at, actor_type, changed_by, reason,
ledger_transaction_id`

Each row represents one event. Its single-attribute candidate
key has no partial dependencies.

Within records containing payout ledger references:

`ledger_transaction_id → payment_id`

The ledger reference is not unique within history. Multiple
history rows could repeat the payment identified by one posting.

The table retains `payment_id` so every event directly identifies
its payment, including events without postings.
A composite foreign key ensures a linked transaction belongs
to that same payment.

Within user-triggered records:

`changed_by → actor_type`

This dependency applies to the subset containing user references.
System events have no `changed_by` value.

These conditional dependencies warrant a qualified assessment,
rather than an unqualified strict-3NF claim.

Neither previous nor new status alone determines the event's
timestamp, actor or reason.

### 3.12 Audit Event

Candidate key:

- `audit_event_id`

Dependency:

`audit_event_id → business_id, actor_type, actor_user_id,
action, entity_type, entity_id, outcome, details, occurred_at`

The ordinary columns describe one event.
The single-attribute candidate key has no partial dependencies.

Within user-triggered events:

`actor_user_id → business_id, actor_type`

A user may trigger many events. Repeating their business therefore
introduces conditional ownership redundancy.

The business reference is retained so both user and system events
directly identify the business concerned.

A composite foreign key enforces agreement between the business
and user actor. Checks require a user reference for user actors
and no user reference for system actors.

JSON details hold flexible event context. Their internal structure
is not analysed as a fully normalised set of relational attributes.
Using JSON does not, by itself, establish a 3NF violation.

The assessment therefore distinguishes conditional ownership
redundancy from structured event context.

## 4. Repeated and calculated data

Each retained duplication or calculated value needs an appropriate
consistency control.

| Retained information | Tables | Consistency control and status |
| :--- | :--- | :--- |
| Explicit business_id | Payment and FX Conversion | Composite foreign keys in the base schema |
| Stored wallet balance | Wallet | Atomic posting and reconciliation demonstrated in Portfolio 3 |
| Wallet currency and liability classification | Ledger Account | Base liability check; Portfolio 3 currency and association protections |
| Payment reference on reversals | Ledger Transaction | Controlled reversal checks in Portfolio 3 |
| Payment reference alongside ledger link | Payment Status History | Composite foreign key in the base schema |
| Current status and status history | Payment and Payment Status History | Atomic changes in Portfolio 3 controlled routines |
| Business reference for user actors | Audit Event | Composite foreign key in the base schema |
| Flexible event context | Audit Event | Base JSON-object check; no general sensitive-content filtering implemented |

These are different kinds of design concern.
Some are transitive dependencies, some apply only to subsets
of records, and others are cross-table calculations or integrity
requirements.

Operational routines and permissions do not remove the underlying
redundancy. They help keep the retained information consistent.

## 5. Limits of this analysis

Normalisation does not establish that:

- A user has permission to perform an operation.
- A wallet has sufficient funds.
- A quote remains unexpired when executed.
- A ledger transaction balances.
- Concurrent transactions cannot overspend a wallet.

Portfolio 1's evidence establishes captured structural behaviour.
Portfolio 3 provides separate evidence for financial routines,
rollback, access restrictions and concurrent wallet operations.

The deliberate departures from strict 3NF are documented.
Composite foreign keys protect ownership consistency, but the
retained redundancy remains part of the design.

The conclusions are limited to the stated dependencies and
prototype assumptions.

## 6. References

University of Waterloo.
*Data Dependencies and Normal Forms*, CS 348, Winter 2026.

https://cs.uwaterloo.ca/~david/cs348/handout-FD.pdf

PostgreSQL Global Development Group.
*PostgreSQL 16 Documentation: Constraints.*

https://www.postgresql.org/docs/16/ddl-constraints.html