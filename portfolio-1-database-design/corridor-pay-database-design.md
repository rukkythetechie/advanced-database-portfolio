# **Corridor Pay Database Design**

## **1\. Purpose and scope**

Corridor Pay is a fintech company used as a simulated case study. It provides cross-border payment services to small and mid-sized businesses in Nigeria, Canada, the United Kingdom and the United States. This prototype will demonstrate relational modelling, SQL implementation, a double-entry ledger architecture, atomic money movements and concurrency management.

The currencies that are supported are NGN, CAD, GBP, and USD; each business may have only one wallet for each currency. Spending-purpose wallets are not included in this prototype. Overdrafts, payment fees, partial reversals, integration with a real bank, authentication, and external foreign exchange trading are not implemented. Each business user is linked to a single business, and this project also excludes internal compliance and operations workflows.

All business, user and banking details used in testing are sample data.

## **2\. Core business rules**

1\. Each wallet is linked to one business and contains one currency, and the UNIQUE(business\_id, currency\_code) constraint prevents duplicates from being created.

2\. Only approved businesses and active admin or finance users are authorized to initiate payments or currency conversions. Users who have only viewer permissions are not allowed to initiate any money movements.

3\. For each payment, the associated wallet, beneficiary, and initiating user must all belong to the same business, and the wallet and beneficiary must use the same currency.

4\. For currency conversions, both wallets and the initiating user must be associated with the business specified in the quote. Wallet currencies must match those in the quote, and the source and target currencies must differ.

5\. A quote can only be accepted once and must be accepted before it expires; after it has been issued, its financial terms become fixed. All the amounts and rates must be positive, and the target amount must remain positive after rounding to two decimal places.

6\. Every posted ledger transaction must have equal total debits and credits within each currency. Posted entries are immutable, so corrections must use compensating transactions.

7\. The ledger is the definitive source of truth, and the wallet's balance is the total amount obtained by subtracting the posted debits from the posted credits on its liability account.

8\. Wallets begin at zero, and funding is recorded on the ledger rather than being entered as arbitrary opening balances.

9\. Wallet updates, postings, business records, and successful audit events are all committed as part of a single database transaction; if an operation fails, all the changes are rolled back, and the audit events relating to the failed attempt are recorded separately afterwards.

10\. The processing of changes to payout status and of the history records takes place atomically, and where transitions involve the movement of money the relevant ledger postings are included within the same database transaction.

## **3\. Proposed table dictionary**

PK \= primary key: a unique, non-null identifier.

FK \= foreign key: a reference to an existing record.

Fields are required unless marked optional. The names below are proposed SQL table and column names. The business-user table is named business\_user to distinguish it from SQL’s USER keyword.

### **1\. business**

| Field | Meaning / rule |
| :---- | :---- |
| business\_id | PK |
| business\_name | Registered company name |
| country\_code | NG, CA, GB or US |
| registration\_number | Registration reference stored as text |
| contact\_email | Business contact address; separate from employee login email |
| kyb\_status | pending, approved or rejected; default pending |
| created\_at | Registration timestamp |

The combination of country\_code and registration\_number must be unique, because registration numbers may overlap across countries. Payment and conversion routines must check that the business is approved; a foreign key only checks that the referenced business exists.

### **2\. business\_user**

| Field | Meaning / rule |
| :---- | :---- |
| user\_id | PK |
| business\_id | FK to business |
| full\_name | Person’s name |
| email | Unique across the prototype; compare case-insensitively |
| role | admin, finance or viewer |
| is\_active | Whether access is enabled |
| created\_at | Creation timestamp |

Admin users can manage business users and beneficiaries and initiate money movements. Finance users can manage beneficiaries and initiate money movements. Viewers have read-only access.

Storing a user’s role does not automatically enforce permissions. The relevant routines must check the user’s role and active status before allowing an action. Password storage and working authentication are out of scope for the prototype.

### **3\. wallet**

| Field | Meaning / rule |
| :---- | :---- |
| wallet\_id | PK |
| business\_id | FK to business |
| currency\_code | NGN, CAD, GBP or USD |
| balance | Exact decimal, non-negative, initially zero |
| created\_at | Creation timestamp |

The combination of business\_id and currency\_code must be unique, ensuring one wallet per currency per business. Each wallet and its corresponding liability ledger account will be created in the same database transaction, so both are created successfully, or neither is created. Wallet balances can only be changed through controlled ledger-posting routines.

### **4\. beneficiary**

| Field | Meaning / rule |
| :---- | :---- |
| beneficiary\_id | PK |
| business\_id | FK to business that saved it |
| beneficiary\_name | Supplier name |
| country\_code | NG, CA, GB or US |
| currency\_code | Receiving currency |
| bank\_name | Destination bank |
| account\_reference | Text preserving letters and leading zeros |
| routing\_reference | Optional text; routing details where needed |
| created\_at | Creation timestamp |

Each beneficiary record represents one supplier’s receiving bank account. Two businesses may independently save the same supplier. Real banking-detail validation is outside scope.

Once a beneficiary record has been referenced by a payment, it cannot be edited or deleted. Changed bank details require a new beneficiary record, preserving the destination recorded for earlier payments.

### **5\. fx\_quote**

| Field | Meaning / rule |
| :---- | :---- |
| quote\_id | PK |
| business\_id | FK to business receiving the offer |
| source\_currency | Currency surrendered |
| target\_currency | Currency received; different from source |
| source\_amount | Positive exact amount |
| exchange\_rate | Positive target-currency units per source unit |
| created\_at | Offer timestamp |
| expires\_at | Later than created\_at |

Once issued, a quote’s financial terms cannot be changed. For example, using the CBN reference rate of ₦1,329.5138 per US dollar on 25 September 2026, ₦160,000 would convert to \$120.34 after rounding. This historical rate is used for demonstration.

Exchange rates are stored with more decimal places than monetary amounts to preserve precision. The conversion routine checks expiry after acquiring the required locks, preventing use of a quote that expires while waiting.

### **6\. fx\_conversion**

| Field | Meaning / rule |
| :---- | :---- |
| conversion\_id | PK |
| quote\_id | FK to fx\_quote; UNIQUE |
| business\_id | FK to business |
| source\_wallet\_id | FK to wallet |
| target\_wallet\_id | FK to wallet; different from source |
| initiated\_by | FK to business\_user |
| target\_amount | Positive source\_amount × exchange\_rate, rounded to two decimal places |
| ledger\_transaction\_id | FK to ledger\_transaction; UNIQUE |
| completed\_at | Completion timestamp |

This table records successful conversions only; failed attempts are recorded as audit events. The source amount and exchange rate come from the linked quote, whose financial terms cannot be changed.

The conversion record, ledger entries, and both wallet balance updates are saved in a single database transaction, so all changes succeed together, or none take effect. The linked ledger transaction must have a status of posted and a transaction type of fx\_conversion.

### **7\. payment**

| Field | Meaning / rule |
| :---- | :---- |
| payment\_id | PK |
| business\_id | FK to business |
| wallet\_id | FK to source wallet |
| beneficiary\_id | FK to destination |
| initiated\_by | FK to business\_user |
| amount | Positive exact amount; no fees |
| status | pending, processing, completed, failed or reversed |
| created\_at | Request timestamp |
| completed\_at | Optional; time settlement succeeded |

If a completed payment is later reversed, completed\_at retains the original completion time, while the status history records both events. The payment’s amount, business, source wallet and beneficiary cannot be changed after creation. Retrying a failed payment creates a new payment record.

During processing, the system locks the source wallet and checks for sufficient funds before deducting money. Creating a pending payment does not reserve or deduct funds.

### **8\. ledger\_account**

| Field | Meaning / rule |
| :---- | :---- |
| ledger\_account\_id | PK |
| account\_name | Readable label |
| account\_type | asset, liability, equity, income or expense |
| currency\_code | One supported currency |
| wallet\_id | Optional UNIQUE FK to wallet; set only for wallet liability accounts |
| created\_at | Creation timestamp |

Each wallet’s ledger account must be a liability account in the same currency as the wallet. Platform accounts have no wallet\_id: cash accounts are assets, while payout clearing accounts are liabilities.

For this prototype, each currency has an FX position account classified as an asset. These accounts may carry debit or credit balances and record the platform’s side of internal conversions; customers cannot spend their balances. External FX settlement, valuation and profit or loss accounting are outside scope.

Once an account has posted entries, you cannot change its currency or accounting type. Accounts referenced by ledger entries cannot be deleted.

Once created, you cannot change a wallet-linked account’s wallet association. This preserves the connection between the wallet and its financial history.

### **9\. ledger\_transaction**

| Field | Meaning / rule |
| :---- | :---- |
| ledger\_transaction\_id | PK |
| transaction\_type | funding, fx\_conversion, payout\_processing, payout\_settlement or reversal |
| description | Explanation |
| status | draft or posted |
| payment\_id | Optional FK to payment; required for payout-related postings |
| reversal\_of\_transaction\_id | Optional UNIQUE self-FK; required for a full reversal |
| created\_at | Creation timestamp |
| posted\_at | Optional until posted |

A ledger transaction can be posted only if it has at least two entries and total debits equal total credits within each currency. Posted transactions and their entries cannot be edited or deleted.

A full reversal must reference an original posted transaction and swap its debit and credit entries. It cannot reference itself, and each original transaction can have only one full reversal.

A payment may have several ledger transactions covering processing, settlement and reversal. The system must prevent duplicate processing or settlement postings through uniqueness rules and checks performed while the payment record is locked.

### **10\. ledger\_entry**

| Field | Meaning / rule |
| :---- | :---- |
| ledger\_entry\_id | PK |
| ledger\_transaction\_id | FK to ledger\_transaction |
| ledger\_account\_id | FK to ledger\_account |
| entry\_type | debit or credit |
| amount | Positive exact decimal |

Each entry uses the currency of its linked ledger account. Entries can only be added, edited or removed while their ledger transaction is in draft status.

Before posting, the system checks that total debits equal total credits within each currency. Checking individual entry amounts alone cannot establish that the transaction balances.

### **11\. payment\_status\_history**

| Field | Meaning / rule |
| :---- | :---- |
| history\_id | PK; deterministic secondary order for equal timestamps |
| payment\_id | FK to payment |
| from\_status | Optional only for initial pending record |
| to\_status | New status |
| changed\_at | Transition timestamp |
| actor\_type | user or system |
| changed\_by | Optional FK to business\_user; required for user actors |
| reason | Explanation; required for failure/reversal |
| ledger\_transaction\_id | Optional FK; required when this transition posts money movements |

The application can add status-history records but cannot edit or delete existing ones. Each payment receives an initial pending history record when created. Any linked ledger transaction must relate to the same payment.

Before changing a status, the system locks the payment record and checks that from\_status matches its current status. For changes triggered by the system, changed\_by remains empty.

Reversing a completed payout requires two ledger transactions. The history record links to the transaction restoring the wallet balance; both transactions remain linked to the payment through payment\_id.

### **12\. audit\_event**

| Field | Meaning / rule |
| :---- | :---- |
| audit\_event\_id | PK |
| business\_id | FK to business concerned |
| actor\_type | user or system |
| actor\_user\_id | Optional FK; required for user actors |
| action | Event name, such as beneficiary\_created |
| entity\_type | Kind of record concerned |
| entity\_id | Optional record ID |
| outcome | success or failure |
| details | Structured JSON context; default empty object |
| occurred\_at | Event timestamp |

The application can add audit events but cannot edit or delete existing records. When a user triggers an event, that user must belong to the business recorded in the event. For system events, actor\_user\_id remains empty. The details field must exclude passwords, credentials and full bank account details.

Because entity\_id may refer to different tables, one standard foreign key cannot validate every reference. Specific financial relationships will retain their own foreign keys.

MongoDB will later demonstrate a document-based model for audit data. Transferring or synchronising events between databases will require a separate design decision.

## **4\. Payout transitions and ledger treatment**

| Payout transitions | Transition Financial effect |
| :---- | :---- |
| Initial → pending | No funds deducted |
| pending → processing | Debit wallet liability; credit payout clearing liability |
| pending → failed | No deduction; no reversal |
| processing → completed | Debit payout clearing liability; credit platform cash asset |
| processing → failed | Record failure; deducted funds remain in clearing pending return |
| failed → reversed | Allowed only if previously deducted funds are returned; reverse the processing posting |
| completed → reversed | Allowed only after actual return of settled funds; reverse settlement and processing postings |

Any transition not listed above is rejected. A payout that fails before funds are deducted remains failed. If funds were deducted, the payout is only marked reversed after the refund has been successfully posted.

Reversing a completed payout requires two compensating ledger transactions. The first debits cash and credits the payout clearing account to record the returned funds. The second debits clearing and credits the wallet liability account to restore the business’s balance. Both transactions must be saved together with the status update and history record in one database transaction.

The history record links to the transaction that restores the wallet balance. Both ledger transactions remain linked to the payout through payment\_id.

reversed is a final status in this prototype, with no further transitions permitted. Settlement and fund returns are simulated; the database’s atomicity applies only to its own records, not to external bank transfers.

## **5\. Worked ledger examples**

### **Wallet funding: NGN 200,000**

| Account | Debit | Credit |
| :---- | :---- | :---- |
| NGN platform cash asset | 200,000 | — |
| Business NGN wallet liability | — | 200,000 |

Wallet balance increases by 200,000.

### **Processing a payout: NGN 50,000**

| Account | Debit | Credit |
| :---- | :---- | :---- |
| Business NGN wallet liability | 50,000 | — |
| NGN payout clearing liability | — | 50,000 |

Processing the payout reduces the wallet balance by ₦50,000. When the payout settles, the ledger debits the payout clearing liability account and credits the cash asset account. If the payout fails before settlement and the funds are returned, the system reverses the processing entries to restore the wallet balance.

### **Internal FX conversion: NGN 160,000 to USD 120.34**

| Account | Currency | Debit | Credit |
| :---- | :---- | :---- | :---- |
| Business NGN wallet liability | NGN | 160,000 | — |
| NGN platform FX position account | NGN | — | 160,000 |
| USD platform FX position account | USD | 120.34 | — |
| Business USD wallet liability | USD | — | 120.34 |

At the reference rate of ₦1,329.5138 per US dollar, ₦160,000 converts to approximately \$120.344745575. The USD wallet receives \$120.34 after rounding to two decimal places. Converting that rounded amount back would not produce exactly ₦160,000.

The four ledger entries form one transaction. Total NGN debits equal total NGN credits at ₦160,000, while total USD debits equal total USD credits at \$120.34. Each currency is checked separately. These entries record an internal conversion; the prototype excludes external FX settlement.

## **6\. Relationships and cardinalities**

These describe the intended model. Minimum requirements that need
routines or triggers are distinguished from the current schema below.

| Parent → child | Cardinality |
| :---- | :---- |
| Business → users, wallets, beneficiaries, quotes, payments, conversions and audit events | One to zero or many |
| Quote → conversion | One to zero or one |
| Wallet → wallet liability ledger account | Intended: exactly one; current schema: zero or one |
| Wallet → payments | One to zero or many |
| Beneficiary → payments | One to zero or many |
| User → initiated payments or conversions | One to zero or many |
| Conversion → ledger transaction | Exactly one; posted status and FX type require additional enforcement |
| Payment → ledger transactions | One to zero or many |
| Payment → status-history records | Intended: one or many; current schema permits zero |
| Ledger transaction → entries | Draft: zero or many; posting must eventually require at least two |
| Ledger account → entries | One to zero or many |
| Original ledger transaction → full reversal | One to zero or one |

Each conversion references a source wallet and a target wallet.
Composite foreign keys require both wallets, the quote and the
initiating user to belong to the conversion's business.

Payment status history and audit events reference user actors when
applicable. System actors have no user reference. Audit user ownership
is enforced by a composite foreign key; history user ownership still
requires additional enforcement.

Platform ledger accounts may have no wallet. A pending payment may
have no ledger transactions because creating it does not move money.

## **7\. Enforcement and consistency plan**

* Use generated integer IDs; monetary amounts NUMERIC(20,2), rates NUMERIC(24,12), timestamps TIMESTAMPTZ and audit details JSONB. Explicitly round conversion results before storing.  
* PKs, FKs, UNIQUE, NOT NULL and CHECK constraints enforce record existence, allowed values, positive amounts and simple uniqueness.  
* Composite ownership FKs use parent UNIQUE(id, business\_id) keys where appropriate, so payments/conversions cannot reference another business's records.  
* Posting and transition routines enforce aggregate balance, approval, role, currency agreement, immutable terms, quote expiry and reversal correctness. Cross-row checks cannot be delegated to ordinary row CHECK constraints.  
* Restricted application privileges prevent direct writes around these routines. Triggers additionally guard posted records and immutable account properties. Superuser access is outside the application's protection boundary.  
* Lock payment/quote and affected wallet records. Acquire wallet locks in a consistent wallet-ID order. Recheck sufficient funds and quote expiry after locks. UNIQUE quote\_id prevents reuse; repeated calls must not post duplicate money movements.  
* Reconcile each wallet.balance with posted credits minus debits; expect zero differences. Include zero-balance wallets with no entries.  
* Successful financial events and audits are atomic. Failed-attempt audits are written after rollback; losing a failure log must not falsely claim the financial operation succeeded.  
* No direct negative balance adjustments, edits to posted history or deletion cascades that erase financial records.

## **8\. Normalisation rationale**

Business details are separated from wallets/users; supplier destinations are separated from payments; quote terms are separated from executed conversions; ledger event details are separated from individual entries. This separation reduces duplication. The normalisation analysis will examine candidate keys and functional dependencies and explain deliberate redundancy, including stored wallet balances and repeated business identifiers.

Wallet.balance is deliberately derived data for efficient spending checks. It requires atomic updates and reconciliation. Some business\_id fields are repeated to enforce ownership efficiently; their consistency must be protected by composite relationships. Generic audit references have an explicitly documented integrity limitation.

## **9\. Review outcome and current implementation**

The design review clarified platform account types, successful-conversion records, payout-to-ledger relationships, completed-payment reversals, beneficiary protection, completion timestamps and failure auditing.

All 12 tables have now been created successfully in the separate PostgreSQL database `corridorpay_p1_check`. The original `corridorpay` database currently contains the business, business_user and wallet tables.

The full schema was executed against an empty database in one transaction with stop-on-error enabled. A script containing 35 numbered constraint tests was then run. Its successful examples and 25 expected constraint errors were reviewed. The final rollback left all 12 tables empty. SQL scripts, execution transcripts and selected screenshots are saved in the repository.

Currently enforced by the schema:
- Primary keys, required fields and foreign-key references.
- Supported currencies, countries, roles and status values.
- One wallet per currency per business.
- Case-insensitive user email uniqueness.
- Business ownership of payment and conversion references.
- Positive payment, quote, conversion and ledger-entry amounts.
- Quote expiry later than creation and a positive rounded target amount.
- Unique quote and ledger references for conversion records.
- Wallet-linked ledger accounts classified as liabilities.
- Payment-history ledger references belonging to the same payment.
- Audit user ownership, actor rules and JSON-object details.

Still awaiting routines, triggers or access controls:
- Business approval and user permission checks.
- Payment currency agreement and immutable payment instructions.
- Protection against editing beneficiary destinations already used.
- Immutable quotes and expiry checks when accepting a quote.
- Conversion currency matching, calculated amount verification and
  validation of the linked ledger transaction's type and posted status.
- Atomic creation of wallets and matching liability accounts.
- Ledger-controlled balance updates and reconciliation.
- Balanced posting per currency, posted-record protection and
  correct compensating reversals.
- Payout transition enforcement, automatic history creation and
  prevention of duplicate processing or settlement postings.
- Append-only history and audit records, history actor ownership,
  restricted application privileges and row-level security.

The FX records in the schema tests are structural examples. They do
not demonstrate an operational conversion, sufficient-funds checks
or atomic wallet balance updates.

Portfolio 1 still requires final document alignment and an organised
README. Operational financial routines and concurrency demonstrations
will be developed and tested during Portfolio 3.

The schema and constraint-test checkpoint was pushed as commit
`0f113a4`. Portfolio 1 is not yet marked complete.

## **10\. References**

Central Bank of Nigeria. NFEM Exchange Rates. Entry dated 25 September 2026: ₦1,329.5138 per US dollar.

https\://www\.cbn.gov.ng/rates/ExchRateByCurrency.html

