# **Corridor Pay Normalisation Analysis**

This document reviews the proposed Corridor Pay database structure. It explains which tables meet normalisation requirements and where the design keeps repeated or calculated data for practical reasons. Implementation and testing are not yet complete.

## **1\. Purpose and method**

I reviewed the 12 tables using their business rules, candidate keys and functional dependencies. The aim is to reduce unnecessary duplication and avoid conflicting information when records are updated.

The following terms are used throughout:

* **Candidate key:** a minimal set of fields that uniquely identifies every row. An optional field marked UNIQUE is not a candidate key for the entire table.  
* **Functional dependency:** X → Y means that rows with the same value of X must have the same value of Y.  
* **1NF:** fields contain individual values, without repeating groups.  
* **2NF:** the table meets 1NF, and no non-key field depends on only part of a candidate key.  
* **3NF:** for every non-trivial dependency X → A, X is a superkey or A belongs to a candidate key.

A superkey uniquely identifies a row. An attribute belonging to a candidate key is called a prime attribute. These definitions guide the analysis rather than treating every repeated value as a normalisation violation **(University of Waterloo, 2026\)**.

Optional references need particular care. A nullable unique field is not a candidate key for the whole table, but its populated values still identify at most one row. PostgreSQL normally allows multiple null values in a unique column **(PostgreSQL Global Development Group, n.d.)**.

## **2\. Overview of findings**

Six tables meet 3NF under the stated assumptions. Payment and FX Conversion deliberately depart from strict 3NF by repeating business ownership information. Ledger Account and Ledger Transaction have no established ordinary 3NF violation under the dependencies reviewed. Payment Status History and Audit Event contain conditional redundancy that needs separate explanation.

| Business | business\_id; (country\_code, registration\_number) | 3NF |
| :---- | :---- | :---- |
| Business User | user\_id; case-insensitive email | 3NF |
| Wallet | wallet\_id; (business\_id, currency\_code) | 3NF within the table; stored balance is derived from the ledger |
| Beneficiary | beneficiary\_id | 3NF under prototype assumptions |
| FX Quote | quote\_id | 3NF |
| FX Conversion | conversion\_id; quote\_id; ledger\_transaction\_id | 2NF; deliberate ownership-related departure from 3NF |
| Payment | payment\_id | 2NF; deliberate ownership-related departure from 3NF |
| Ledger Account | ledger\_account\_id | No ordinary 3NF violation established; conditional wallet rules apply |
| Ledger Transaction | ledger\_transaction\_id | No ordinary 3NF violation established; reversal consistency rules apply |
| Ledger Entry | ledger\_entry\_id | 3NF |
| Payment Status History | history\_id | Conditional redundancy in records with ledger references |
| Audit Event | audit\_event\_id | Conditional ownership redundancy; JSON context assessed separately |

These conclusions depend on the declared business rules. Additional rules could introduce dependencies that require a fresh analysis.

## **3\. Table-by-table analysis**

### **3.1 Business**

The candidate keys are business\_id and the combination of country\_code and registration\_number.

business\_id → business\_name, country\_code, registration\_number,

             contact\_email, kyb\_status, created\_at

The country-and-registration combination also determines the complete record.

The table meets 1NF because each field stores an individual value. It meets 2NF because the non-key fields depend on the whole of each candidate key, not just the country or registration number.

Under the stated rules, no non-key field determines another non-key field, so the table meets 3NF. Business names and contact emails are not assumed to be unique.

### **3.2 Business User**

The candidate keys are user\_id and email, with email addresses compared case-insensitively.

user\_id → business\_id, full\_name, email, role, is\_active, created\_at

The email key also determines the complete user record.

Each user belongs to one business and has one role. The fields contain individual values, meeting 1NF. Both candidate keys are single attributes, so there are no partial dependencies and the table meets 2NF.

Business details remain in the Business table instead of being repeated for every employee. No non-key field determines another under the stated rules, so the table meets 3NF.

### **3.3 Wallet**

The candidate keys are wallet\_id and (business\_id, currency\_code).

wallet\_id → business\_id, currency\_code, balance, created\_at

The business-and-currency combination also determines the complete wallet record.

Each row stores one currency and one balance, meeting 1NF. Balance and creation time depend on the whole composite key. Neither the business nor the currency alone identifies these values, so the table meets 2NF.

Under the stated rules, Wallet has no transitive dependencies, so it meets 3NF.

The stored balance nevertheless duplicates a total calculated from posted ledger entries. This is cross-table redundancy, not automatically a 3NF violation within Wallet. Atomic posting routines and reconciliation will keep the balance consistent with the ledger.

### **3.4 Beneficiary**

The only declared candidate key is beneficiary\_id.

beneficiary\_id → business\_id, beneficiary\_name, country\_code,

                currency\_code, bank\_name, account\_reference,

                routing\_reference, created\_at

Each record represents one receiving account with individual field values, meeting 1NF. The single-attribute key has no partial dependencies, so the table meets 2NF.

For this prototype, bank names and routing references are treated as saved destination details. The design does not assume that a routing reference determines a standard bank record. Under these assumptions, no transitive dependencies are asserted, and the table meets 3NF.

Bank-account details are not candidate keys. Different businesses can save the same destination, and duplicates within a business have not been prohibited.

If bank-directory rules are introduced later, their dependencies will need to be analysed separately.

### **3.5 FX Quote**

The only declared candidate key is quote\_id.

quote\_id → business\_id, source\_currency, target\_currency,

          source\_amount, exchange\_rate, created\_at, expires\_at

Each row records one offer using individual values, meeting 1NF. Its single-attribute key has no partial dependencies, so it meets 2NF.

The currency pair does not determine the rate because quotes for the same currencies may offer different rates. Creation time does not determine expiry because a fixed quote duration has not been imposed.

No transitive dependencies are asserted under these rules, so the table meets 3NF.

### **3.6 FX Conversion**

The candidate keys are conversion\_id, quote\_id and ledger\_transaction\_id. Each is required and unique.

conversion\_id → quote\_id, business\_id, source\_wallet\_id,

               target\_wallet\_id, initiated\_by, target\_amount,

               ledger\_transaction\_id, completed\_at

Each of the other candidate keys also determines the complete record.

The table meets 1NF. All candidate keys are single attributes, so there are no partial dependencies, and it meets 2NF.

Each source wallet, target wallet and initiating user belongs to one business. Their references therefore determine business\_id, but they are not superkeys of Conversion because they may appear in many conversions.

For example:

source\_wallet\_id → business\_id

The table deliberately departs from strict 3NF by retaining explicit business ownership. Composite foreign keys will prevent the business ID from disagreeing with the linked records.

The rounded target\_amount is determined by the accepted quote. Since quote\_id is a candidate key, storing that result does not itself violate 3NF.

### **3.7 Payment**

The only declared candidate key is payment\_id.

payment\_id → business\_id, wallet\_id, beneficiary\_id, initiated\_by,

            amount, status, created\_at, completed\_at

Each row represents one instruction with individual values, meeting 1NF. Its single-attribute key has no partial dependencies, so it meets 2NF.

The wallet, beneficiary and initiating user each determine the business they belong to. None uniquely identifies a payment because each may appear in many payments.

Keeping business\_id therefore creates transitive dependencies and deliberately departs from strict 3NF. Composite foreign keys will enforce consistent ownership.

Keeping the current status alongside a separate status history also requires coordinated updates. That is an integrity requirement rather than an additional normal-form conclusion.

### **3.8 Ledger Account**

The only unconditional candidate key is ledger\_account\_id.

ledger\_account\_id → account\_name, account\_type, currency\_code,

                   wallet\_id, created\_at

Although wallet\_id is unique when present, platform accounts leave it empty. It is not a candidate key for the whole table.

The ordinary fields hold individual values, and the single unconditional key has no partial dependencies.

For populated wallet references, uniqueness ensures that a wallet identifies at most one ledger-account row. Therefore, the wallet’s currency and required liability classification do not, by themselves, establish a non-key dependency across multiple account rows.

No ordinary 3NF violation has been established from the stated dependencies. Matching wallet currency, requiring a liability account type and protecting the wallet association remain conditional integrity rules that must be enforced.

### **3.9 Ledger Transaction**

The only unconditional candidate key is ledger\_transaction\_id.

ledger\_transaction\_id → transaction\_type, description, status,

                       payment\_id, reversal\_of\_transaction\_id,

                       created\_at, posted\_at

The optional reversal reference is unique when present, but it does not identify every row.

Each row records one financial event, with entries stored separately, meeting 1NF. The single unconditional key has no partial dependencies.

For a reversal, the original transaction establishes which payment is being reversed. However, when populated, the original reference is unique, so it identifies at most one reversal row.

No ordinary 3NF violation has been established from that reference. The reversal’s payment ID must match the original transaction's payment ID.

Checking balanced debits and credits is a separate financial correctness requirement.

### **3.10 Ledger Entry**

The only declared candidate key is ledger\_entry\_id.

ledger\_entry\_id → ledger\_transaction\_id, ledger\_account\_id,

                 entry\_type, amount

Each row records one debit or credit, meeting 1NF. Its single-attribute key has no partial dependencies, so it meets 2NF.

Currency is obtained from Ledger Account, while financial-event details remain in Ledger Transaction. Neither is repeated in each entry.

There are no transitive dependencies between the stored non-key fields under the stated rules, so the table meets 3NF.

The transaction-and-account combination is not assumed unique. A transaction may contain several entries affecting the same account.

### **3.11 Payment Status History**

The only declared candidate key is history\_id.

history\_id → payment\_id, from\_status, to\_status, changed\_at,

            actor\_type, changed\_by, reason, ledger\_transaction\_id

Each row records one status event with individual values. The single-attribute key has no partial dependencies.

Within records containing payout ledger references:

ledger\_transaction\_id → payment\_id

Unlike the wallet reference in Ledger Account, this ledger reference is not declared unique. The same posting could therefore appear in multiple history records, repeating the payment it identifies.

The design retains payment\_id so every event directly identifies its payment, including events without ledger postings. This conditional redundancy requires consistency checks and is not presented as an unqualified strict-3NF result.

The previous and new statuses describe the event. Neither status alone determines its timestamp, actor or reason.

### **3.12 Audit Event**

The only declared candidate key is audit\_event\_id.

audit\_event\_id → business\_id, actor\_type, actor\_user\_id, action,

                entity\_type, entity\_id, outcome, details, occurred\_at

The ordinary columns store individual event attributes, and the single-attribute key has no partial dependencies.

Within user-triggered events:

actor\_user\_id → business\_id

One user may trigger many events, so the repeated business ID introduces conditional ownership redundancy. It is retained so both user-triggered and system-triggered events directly identify the business concerned. Ownership checks will enforce agreement.

The JSON details field stores flexible event context. Its internal structure is not analysed as a fully normalised set of relational attributes. The use of JSON alone does not establish a 3NF violation.

The audit table therefore receives a qualified assessment that separates ownership redundancy from its structured event context.

## **4\. Repeated and calculated data**

Some information is retained for practical reasons. Each choice needs an appropriate consistency control.

| Explicit business\_id | Payment and FX Conversion | Composite foreign keys and ownership checks |
| :---- | :---- | :---- |
| Stored wallet balance | Wallet | Atomic posting and reconciliation |
| Wallet currency and liability classification | Ledger Account | Checks against the linked wallet |
| Payment reference on reversals | Ledger Transaction | Agreement with the original transaction |
| Payment reference alongside a ledger link | Payment Status History | Agreement with the linked posting |
| Current status and status history | Payment and Payment Status History | Updates saved together |
| Business reference for user actors | Audit Event | Ownership checks |
| Flexible event context | Audit Event | JSON validation and sensitive-data restrictions |

These items are not all the same kind of normalisation issue. Some are established transitive dependencies, some apply only to particular records, and others are cross-table calculations or integrity rules.

## **5\. Limits of this analysis**

Normalisation does not establish that a user has permission, a wallet has sufficient funds, a quote is valid or a ledger transaction balances.

Those requirements need separate constraints, routines and tests. This analysis concerns the proposed design and does not claim that the database has already been implemented successfully.

## **6\. References**

University of Waterloo. *Data Dependencies and Normal Forms*, CS 348, Winter 2026\.

[https\://cs.uwaterloo.ca/\~david/cs348/handout-FD.pdf](https://cs.uwaterloo.ca/~david/cs348/handout-FD.pdf)

PostgreSQL Global Development Group. *PostgreSQL Documentation: Constraints*.

[https\://www\.postgresql.org/docs/current/ddl-constraints.html](https://www.postgresql.org/docs/current/ddl-constraints.html)