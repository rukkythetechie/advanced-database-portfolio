# Corridor Pay Database Design

## 1. Purpose and scope

Corridor Pay is a fintech company used as a simulated case study.
It provides cross-border payment services to small and mid-sized
businesses in Nigeria, Canada, the United Kingdom and the
United States.

The project demonstrates relational modelling, SQL implementation,
double-entry accounting, atomic financial operations and
concurrency management.

Supported currencies are NGN, CAD, GBP and USD. Each business may
have one wallet per currency. Separate spending-purpose wallets
are outside scope.

Overdrafts, payment fees, partial reversals, real bank integration,
working customer authentication and external FX settlement are
not implemented. Each business user belongs to one business.
Internal compliance and operations workflows are also outside scope.

All business, user and banking details used in testing are sample data.

### Implementation checkpoints

Portfolio 1 contains the base schema and structural tests completed
on 19–20 October 2026.

Financial routines, transaction tests and restricted application
permissions were subsequently added in
[Portfolio 3](../portfolio-3-transactions-concurrency/README.md).

The dictionary and business rules below describe the intended model.
Section 9 distinguishes implemented protections from remaining limits.

## 2. Core business rules

1. Each wallet belongs to one business and holds one currency.
   `UNIQUE(business_id, currency_code)` prevents duplicate wallets
   for the same business and currency.

2. Payment processing and currency conversion require an approved
   business and an active admin or finance user from that business.
   Viewer users cannot initiate these financial operations.

3. A payment's wallet, beneficiary and initiating user must belong
   to the same business. The wallet and beneficiary currencies
   must match.

4. A conversion's wallets and initiating user must belong to the
   business receiving the quote. Wallet currencies must match
   the quote, and source and target currencies must differ.

5. A quote can be executed once and must remain unexpired when
   executed. Its terms are fixed after issue. Amounts and rates
   must be positive, and the target amount must remain positive
   after rounding to two decimal places.

6. Every posted ledger transaction must have equal total debits
   and credits within each currency. Posted entries are immutable.
   Corrections use compensating transactions.

7. The ledger is the financial source of truth. A wallet's balance
   must equal posted credits minus posted debits on its liability
   account.

8. Wallets begin at zero. Funding is recorded through the ledger,
   rather than entered as an arbitrary opening balance.

9. Related financial records, wallet updates and successful audit
   events must commit together or roll back together. Failed-attempt
   audits require a separate transaction after rollback.

10. Payment status changes and their history records must be atomic.
    Transitions involving financial postings include those postings
    in the same database transaction.

## 3. Table dictionary

PK means primary key: a unique, non-null identifier.

FK means foreign key: a reference to an existing record.

Fields are required unless marked optional. The business-user table
is named `business_user` to distinguish it from SQL's `USER` keyword.

### 3.1 business

| Field | Meaning or rule |
| :--- | :--- |
| business_id | PK |
| business_name | Registered company name |
| country_code | NG, CA, GB or US |
| registration_number | Registration reference stored as text |
| contact_email | Business contact address |
| kyb_status | pending, approved or rejected; default pending |
| created_at | Registration timestamp |

The combination of country and registration number is unique,
because registration numbers may overlap across countries.

A foreign key checks that a business exists. Approval checks
require additional logic in the financial routines.

### 3.2 business_user

| Field | Meaning or rule |
| :--- | :--- |
| user_id | PK |
| business_id | FK to business |
| full_name | Person's name |
| email | Unique across the prototype, compared case-insensitively |
| role | admin, finance or viewer |
| is_active | Whether access is enabled |
| created_at | Creation timestamp |

The intended roles allow admins to manage users and beneficiaries,
and finance users to manage beneficiaries. Both may initiate
financial operations. Viewers have read-only access.

The implemented financial routines check the supplied user's
business, role and active status. User-management and beneficiary-
management application workflows are outside the prototype.

Storing a role does not enforce permissions by itself.
Password storage and working customer authentication are outside scope.

### 3.3 wallet

| Field | Meaning or rule |
| :--- | :--- |
| wallet_id | PK |
| business_id | FK to business |
| currency_code | NGN, CAD, GBP or USD |
| balance | Exact decimal, non-negative, initially zero |
| created_at | Creation timestamp |

`UNIQUE(business_id, currency_code)` enforces one wallet per
currency per business.

The intended model creates a wallet and its matching liability
account together. The demonstrations perform this administrative
setup within a database transaction.

Portfolio 3 restricts application writes so financial wallet
updates pass through controlled routines.

### 3.4 beneficiary

| Field | Meaning or rule |
| :--- | :--- |
| beneficiary_id | PK |
| business_id | FK to business that saved it |
| beneficiary_name | Supplier name |
| country_code | NG, CA, GB or US |
| currency_code | Receiving currency |
| bank_name | Destination bank |
| account_reference | Text preserving letters and leading zeros |
| routing_reference | Optional routing details |
| created_at | Creation timestamp |

Each beneficiary represents one supplier receiving account.
Two businesses may independently save the same supplier.

Real banking-detail validation is outside scope.

The intended model preserves destinations used by earlier payments.
Changed bank details should create a new beneficiary record.
A dedicated trigger preventing edits to used beneficiaries has
not been implemented; the restricted application role has no
direct write access to this table.

### 3.5 fx_quote

| Field | Meaning or rule |
| :--- | :--- |
| quote_id | PK |
| business_id | FK to business receiving the offer |
| source_currency | Currency surrendered |
| target_currency | Currency received; different from source |
| source_amount | Positive exact amount |
| exchange_rate | Positive target-currency units per source unit |
| created_at | Offer timestamp |
| expires_at | Later than created_at |

Portfolio 3 protects issued quotes against changes and deletion.

An illustrative sample rate of NGN 1,329.5138 per USD converts
NGN 160,000 to USD 120.34 after rounding. This is a demonstration
value, not a verified market-rate observation.

The test routine uses the rounded inverse sample rate of
0.000752154660 USD per NGN.

Rates use more decimal places than monetary amounts. The conversion
routine checks expiry after acquiring the required locks, preventing
execution of a quote that expires while waiting.

### 3.6 fx_conversion

| Field | Meaning or rule |
| :--- | :--- |
| conversion_id | PK |
| quote_id | UNIQUE FK to fx_quote |
| business_id | FK to business |
| source_wallet_id | FK to wallet |
| target_wallet_id | FK to wallet; different from source |
| initiated_by | FK to business_user |
| target_amount | Positive source amount multiplied by rate, rounded to two decimal places |
| ledger_transaction_id | UNIQUE FK to ledger_transaction |
| completed_at | Completion timestamp |

This table records successful conversions.

The source amount and exchange rate come from the linked quote.
The controlled conversion routine calculates the target amount
and saves the conversion, ledger entries, wallet updates and
success audit atomically.

The linked ledger transaction must be posted and have type
`fx_conversion`. These operational checks belong to Portfolio 3.

Failed attempts require caller-managed audit logging after rollback.

### 3.7 payment

| Field | Meaning or rule |
| :--- | :--- |
| payment_id | PK |
| business_id | FK to business |
| wallet_id | FK to source wallet |
| beneficiary_id | FK to destination |
| initiated_by | FK to business_user |
| amount | Positive exact amount; no fees |
| status | pending, processing, completed, failed or reversed |
| created_at | Request timestamp |
| completed_at | Optional; time settlement succeeded |

Creating a pending payment does not reserve or deduct funds.

Processing locks the relevant records and checks sufficient funds
before posting the wallet debit.

If a completed payment is reversed, `completed_at` retains its
original completion time. History records both events.

The intended model keeps the amount, business, source wallet and
beneficiary unchanged after creation. Retrying a failed payment
creates a new payment record.

A dedicated immutable-payment trigger has not been implemented.
The restricted application role cannot directly update payment
records; controlled routines manage their status changes.

### 3.8 ledger_account

| Field | Meaning or rule |
| :--- | :--- |
| ledger_account_id | PK |
| account_name | Readable label |
| account_type | asset, liability, equity, income or expense |
| currency_code | One supported currency |
| wallet_id | Optional UNIQUE FK to wallet |
| created_at | Creation timestamp |

A wallet-linked account must be a liability account in the same
currency as its wallet.

Platform accounts have no wallet reference. Cash accounts are
assets, while payout clearing accounts are liabilities.

For this prototype, platform FX position accounts are classified
as assets. They may carry debit or credit balances and represent
the platform's side of internal conversions. Customers cannot
spend these account balances.

External FX settlement, valuation and profit or loss accounting
are outside scope.

Portfolio 3 protects account properties after posting and prevents
changes to wallet associations. Foreign keys prevent deletion
of accounts referenced by entries.

### 3.9 ledger_transaction

| Field | Meaning or rule |
| :--- | :--- |
| ledger_transaction_id | PK |
| transaction_type | funding, fx_conversion, payout_processing, payout_settlement or reversal |
| description | Explanation |
| status | draft or posted |
| payment_id | Optional FK; required for payout-related postings |
| reversal_of_transaction_id | Optional UNIQUE self-FK; required for reversal |
| created_at | Creation timestamp |
| posted_at | Optional until posted |

Posting requires at least two entries and equal total debits
and credits within each currency.

Posted transactions and their entries cannot be edited or deleted
through the protected implementation.

A full reversal references an original posted transaction and swaps
its debit and credit entries. It cannot reference itself, and each
original transaction can have one full reversal.

A payment may have processing, settlement and reversal transactions.
Portfolio 3 combines payment locks, checks and uniqueness rules
to prevent duplicate processing and settlement.

### 3.10 ledger_entry

| Field | Meaning or rule |
| :--- | :--- |
| ledger_entry_id | PK |
| ledger_transaction_id | FK to ledger_transaction |
| ledger_account_id | FK to ledger_account |
| entry_type | debit or credit |
| amount | Positive exact decimal |

Each entry uses its ledger account's currency.

Entries may be added, edited or removed only while their transaction
is a draft. Before posting, aggregate debits and credits must balance
within each currency.

Checking individual entry amounts alone cannot establish that
a transaction balances.

### 3.11 payment_status_history

| Field | Meaning or rule |
| :--- | :--- |
| history_id | PK; secondary ordering for equal timestamps |
| payment_id | FK to payment |
| from_status | Optional only for the initial pending record |
| to_status | New status |
| changed_at | Transition timestamp |
| actor_type | user or system |
| changed_by | Optional FK; required for user actors |
| reason | Explanation; required for failure or reversal |
| ledger_transaction_id | Optional FK to the related posting |

The intended model records initial pending history when a payment
is created. The demonstrations prepare that initial history
administratively.

Controlled routines lock the payment, check its current state
and save transition history with the related financial operation.

Linked ledger transactions must belong to the same payment.
For system actors, `changed_by` remains empty.

Reversing a completed payment requires two ledger transactions.
The reversal history links to the transaction restoring the wallet;
both transactions remain associated with the payment.

The restricted application role cannot directly insert, edit
or delete history records. Controlled routines insert history.

### 3.12 audit_event

| Field | Meaning or rule |
| :--- | :--- |
| audit_event_id | PK |
| business_id | FK to the business concerned |
| actor_type | user or system |
| actor_user_id | Optional FK; required for user actors |
| action | Event name |
| entity_type | Kind of record concerned |
| entity_id | Optional record identifier |
| outcome | success or failure |
| details | JSON object; default empty object |
| occurred_at | Event timestamp |

A user actor must belong to the business recorded in the event.
For system actors, `actor_user_id` remains empty.

Audit details should exclude passwords, credentials and full bank
account details.

Because `entity_id` can refer to different tables, one standard
foreign key cannot validate every reference. Specific financial
relationships retain their own foreign keys.

The restricted application role cannot directly insert, edit
or delete audit records. Controlled routines save success audits.

Portfolio 4 separately demonstrates MongoDB audit documents using
standalone sample events. Synchronisation between PostgreSQL
and MongoDB is not implemented.

## 4. Payout transitions and ledger treatment

| Transition | Financial effect |
| :--- | :--- |
| Initial → pending | No funds deducted |
| pending → processing | Debit wallet liability; credit payout clearing liability |
| pending → failed | No deduction and no reversal |
| processing → completed | Debit payout clearing liability; credit platform cash asset |
| processing → failed | Record failure; deducted funds remain in clearing pending return |
| failed → reversed | Return previously deducted funds by reversing processing |
| completed → reversed | Simulate returned funds by reversing settlement and processing |

These transitions describe the intended lifecycle. The controlled
routines implement the processing, settlement and reversal paths
documented in Portfolio 3.

A payment that fails before deduction has no funds to reverse.
A payment with deducted funds is marked reversed only after its
refund postings succeed.

Reversing a completed payment requires two compensating transactions:

1. Debit cash and credit clearing to represent returned settled funds.
2. Debit clearing and credit the wallet liability to restore the balance.

Both postings, the status update, history and success audit must
succeed together.

The history record links to the wallet-restoring transaction.
Both transactions remain associated with the payment.

`reversed` is a final status in this prototype.

Settlement and fund returns are simulated. Database atomicity
covers its own records and does not establish atomicity with
external bank transfers.

## 5. Worked ledger examples

### Wallet funding: NGN 200,000

| Account | Debit | Credit |
| :--- | ---: | ---: |
| NGN platform cash asset | 200,000 | |
| Business NGN wallet liability | | 200,000 |

The wallet balance increases by NGN 200,000.

### Processing a payout: NGN 50,000

| Account | Debit | Credit |
| :--- | ---: | ---: |
| Business NGN wallet liability | 50,000 | |
| NGN payout clearing liability | | 50,000 |

Processing reduces the wallet balance by NGN 50,000.

Settlement debits clearing and credits platform cash. If processing
is reversed before settlement, the compensating entries debit
clearing and credit the wallet liability.

### Internal FX conversion: NGN 160,000 to USD 120.34

| Account | Currency | Debit | Credit |
| :--- | :--- | ---: | ---: |
| Business NGN wallet liability | NGN | 160,000 | |
| NGN platform FX position account | NGN | | 160,000 |
| USD platform FX position account | USD | 120.34 | |
| Business USD wallet liability | USD | | 120.34 |

At the illustrative sample rate of NGN 1,329.5138 per USD,
NGN 160,000 converts to approximately USD 120.3447.

The USD wallet receives USD 120.34 after rounding to two decimal
places. Converting that rounded amount back would not reproduce
exactly NGN 160,000.

All four entries belong to one ledger transaction.
NGN debits equal NGN credits, and USD debits equal USD credits.
Each currency is checked separately.

These entries represent an internal conversion.
External FX settlement is outside scope.

## 6. Relationships and cardinalities

The distinction below is between the intended operational model
and the Portfolio 1 base schema.

| Parent → child | Cardinality |
| :--- | :--- |
| Business → users, wallets, beneficiaries, quotes, payments, conversions and audit events | One to zero or many |
| Quote → conversion | One to zero or one |
| Wallet → wallet liability account | Intended: exactly one; base schema permits zero or one |
| Wallet → payments | One to zero or many |
| Beneficiary → payments | One to zero or many |
| User → initiated payments or conversions | One to zero or many |
| Conversion → ledger transaction | Exactly one reference; posted status and FX type require operational checks |
| Payment → ledger transactions | One to zero or many |
| Payment → status history | Intended: one or many; base schema permits zero |
| Ledger transaction → entries | Draft: zero or many; Portfolio 3 posting requires at least two |
| Ledger account → entries | One to zero or many |
| Original ledger transaction → full reversal | One to zero or one |

Each conversion references a source wallet and a target wallet.
Composite foreign keys require its wallets, quote and initiating
user to belong to the conversion's business.

History and audit records reference user actors where applicable.
System actors have no user reference.

Audit user ownership is enforced by a composite foreign key.
History actor ownership requires operational checks beyond its
simple user reference.

Platform ledger accounts may have no wallet.
Pending payments may have no ledger transactions because creating
an instruction does not move funds.

## 7. Enforcement and consistency plan

- Use generated integer identifiers, `NUMERIC(20,2)` monetary amounts,
  `NUMERIC(24,12)` rates, `TIMESTAMPTZ` timestamps and `JSONB` audit
  details. Round conversion results explicitly.

- Use primary keys, foreign keys, uniqueness, required fields and
  checks for record existence, allowed values and row-level rules.

- Use composite ownership foreign keys with parent
  `UNIQUE(id, business_id)` keys where appropriate.

- Use financial routines for aggregate balance, approval, role,
  currency agreement, quote expiry and reversal correctness.
  Ordinary row checks cannot enforce all cross-row rules.

- Restrict direct application writes. Use triggers to protect
  posted records, quote terms and account properties.

- Lock payment or quote records and affected wallets. Acquire
  wallet locks in consistent identifier order and recheck funds
  and quote expiry after waiting.

- Prevent quote reuse and duplicate financial operations through
  uniqueness rules and checks under locks.

- Reconcile stored wallet balances with posted credits minus
  debits, including zero-balance wallets without entries.

- Commit successful financial events and audits atomically.
  Record failed attempts separately after rollback.

- Preserve financial history and avoid deletion cascades that
  erase financial records.

These protections apply within the documented implementation
boundary. Privileged administrators can perform actions unavailable
to the restricted application role.

## 8. Normalisation rationale

Business details are separated from users and wallets.
Supplier destinations are separated from payments.
Quote terms are separated from successful conversions.
Ledger transaction details are separated from individual entries.

The normalisation analysis examines candidate keys, functional
dependencies and deliberate redundancy.

`wallet.balance` is derived data retained for efficient spending
checks. Its correctness requires atomic updates and reconciliation.

Repeated business identifiers support ownership enforcement through
composite foreign keys. Their normalisation trade-offs are explained
in the separate analysis.

Generic audit references have a documented integrity limitation:
one foreign key cannot validate identifiers referring to several
different entity tables.

## 9. Review outcome and implementation checkpoints

### Portfolio 1 structural checkpoint

All 12 tables were created in `corridorpay_p1_check`.
The base schema ran against an empty database in one transaction
with stop-on-error enabled.

Its 35 numbered tests produced the reviewed expected outcomes,
including 25 intentional constraint errors.
The final rollback left all 12 tables empty.

The base schema enforces:

- Primary and foreign keys.
- Required fields and supported values.
- Business ownership references.
- One wallet per business and currency.
- Case-insensitive user email uniqueness.
- Other documented row-level checks.

The schema-and-test checkpoint was pushed as commit `0f113a4`.
The Portfolio 1 guide, ER diagram and normalisation analysis
are included in the repository.

### Later Portfolio 3 implementation

Portfolio 3 subsequently added and tested:

- Balanced ledger posting and atomic wallet updates.
- Protection of posted records and wallet identity fields.
- Locked sufficient-funds checks and competing-payment handling.
- Controlled payment processing, simulated settlement and full reversals.
- Actor, approval, ownership and currency checks in financial routines.
- Immutable FX quotes and execution-time expiry checks.
- Calculated conversion amounts and atomic conversion records.
- Successful financial history and audit records.
- Duplicate processing and settlement protections.
- Restricted backend access through controlled financial entry points.

Portfolio 1's conversion records remain structural test examples.
They do not demonstrate actual conversion or balance movement.
Operational evidence belongs to Portfolio 3.

### Remaining boundaries

The dictionary and enforcement plan describe the intended model.
They do not establish global protection against every privileged write.

The restricted backend cannot directly edit payment instructions,
beneficiaries, history or audits. Dedicated immutable-payment
and used-beneficiary triggers have not been implemented.

Wallet/account creation and initial payment history are prepared
administratively. Application creation routines do not enforce
these initial relationships.

The generic ledger posting engine checks accounting balance and
wallet effects. It does not independently enforce every business
meaning associated with each transaction type. Controlled financial
routines provide additional operation-specific checks.

Row-level security, tenant-isolated reads and customer authentication
are not implemented.

Failure auditing after rollback is demonstrated by concurrency
session B. Other failed routine calls require caller-managed
failure logging.

See the Portfolio 3 guide for exact routine coverage, tests
and limitations.

## 10. References

PostgreSQL Global Development Group.
*PostgreSQL 16: Numeric Types.*

https://www.postgresql.org/docs/16/datatype-numeric.html

The exchange-rate figures in the worked examples are illustrative
sample values.