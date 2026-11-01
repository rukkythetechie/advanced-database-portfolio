# Advanced Database Systems Portfolio — MIT 8103

**Student:** Rukayat Yaro
**Student ID:** 301919721
**Case study:** Corridor Pay, a simulated cross-border B2B payments platform

## Case study

Corridor Pay helps small and mid-sized businesses manage
multi-currency balances and pay suppliers across borders.

The prototype covers Nigeria, Canada, the United Kingdom
and the United States, using NGN, CAD, GBP and USD.

The database supports businesses, business users, wallets,
supplier destinations, FX quotes, conversions, payment
instructions, ledger records, payment history and audit events.

Business users have admin, finance or viewer roles.
The controlled financial routines check whether the supplied
acting user is active, belongs to the relevant business and
has an appropriate role.

Business approval is represented by a stored KYB status.
Document collection and compliance review workflows are
outside the prototype.

All business, user and banking details used in testing are
sample data. No real transfers, refunds or external FX trades
are performed.

## Portfolio activities

| Activity | Work and evidence | Guide |
| :--- | :--- | :--- |
| Portfolio 1: Database Design and Modelling | Twelve-table schema, ER diagram, normalisation analysis and constraint tests | [Portfolio 1](portfolio-1-database-design/README.md) |
| Portfolio 2: Query Processing and Optimisation | Sample dataset, SQL queries, execution plans, index comparisons and result checks | [Portfolio 2](portfolio-2-query-optimisation/README.md) |
| Portfolio 3: Transactions and Concurrency | Funding, rollback, competing payments, controlled financial routines and application permissions | [Portfolio 3](portfolio-3-transactions-concurrency/README.md) |
| Portfolio 4: NoSQL and Advanced Data Models | MongoDB audit documents, validation, CRUD, aggregation and index inspection | [Portfolio 4](portfolio-4-nosql/README.md) |
| Portfolio 5: Distributed and Cloud Databases | Proposed architecture, replication and sharding trade-offs, consistency and local deployment inspection | [Portfolio 5](portfolio-5-distributed-cloud/README.md) |

All five activities have committed work. Final assessment review,
individual reflection and submission preparation are in progress.

## Main business rules

- A business can hold one wallet per supported currency.
- Financial records must reference the correct business.
- Payment wallet and beneficiary currencies must match.
- Financial postings must balance within each currency.
- Posted ledger records are preserved; corrections use
  compensating transactions.
- Wallet changes and their financial records must succeed
  or roll back together.
- A quote must be unused and unexpired when executed.
- Competing wallet debits must recheck funds under a lock.

The guides distinguish rules enforced by the implementation
from intended relationships and remaining limitations.

## Repository structure

```text
advanced-database-portfolio/
├── portfolio-1-database-design/
├── portfolio-2-query-optimisation/
├── portfolio-3-transactions-concurrency/
├── portfolio-4-nosql/
├── portfolio-5-distributed-cloud/
├── setup-evidence/
├── docker-compose.yml
└── README.md
```

## Environment and reproduction

The practical exercises use Docker Desktop with:

- PostgreSQL container: corridor-pg.
- MongoDB container: corridor-mongo.

Captured versions were PostgreSQL 16.15 and MongoDB 7.0.43.

### Fresh installation

From the repository folder, copy the example configuration:

    cp .env.example .env

Open .env locally and replace the password placeholder with
your own password. Then create and start the containers:

    docker compose up -d

The .env file is excluded from Git and must not be uploaded.
For an existing database, editing .env alone does not change
the database password.

### Existing containers

Start containers that have already been created:

    docker start corridor-pg corridor-mongo

Follow each portfolio's guide for database names, installation
order, test commands and expected results.

Full-schema exercises use separate databases, including
corridorpay_p1_check, corridorpay_p2 and corridorpay_p3.

MongoDB Portfolio 4 uses corridorpay_p4 and standalone sample
audit events. It is not synchronized with PostgreSQL.

## Evidence and verification

The repository contains SQL and JavaScript scripts, captured
outputs, query plans, selected screenshots and progressive commits.

Portfolio 2 compares query results before and after indexing.

Portfolio 3 includes manual demonstrations and later tests with
assertions. Its two-session test records actual blocking and
the rejection of a competing debit.

Portfolio 4 includes assertions for selected document, query,
validation and CRUD outcomes.

Portfolio 5 follows the discussion route. Its evidence inspects
the current local deployment; its distributed cloud architecture
is proposed and has not been deployed.

A successful command exit alone does not establish correctness.
The guides explain the expected outputs and practical limits.

## Scope and limitations

This is an assessment prototype, not a production payment service.

The implementation does not include real bank integration,
external FX settlement, working authentication, fees, overdrafts,
partial reversals or operational compliance workflows.

The restricted PostgreSQL application role represents a trusted
backend. It does not authenticate customers, and its reads are
not isolated by tenant.

Initial business records, wallet accounts, payment instructions
and quotes are prepared administratively for the demonstrations.

MongoDB audit permissions are not configured to enforce
append-only access.

Cloud failover, sharding, backup restoration and cross-database
event delivery are discussed rather than implemented.

## AI-use declaration

Claude was used for assistance with the initial case-study
selection and README draft.

ChatGPT was used for explanations, implementation guidance,
drafting and revising SQL and JavaScript, test design,
interpretation of outputs, troubleshooting and documentation.

I executed the practical commands and scripts locally, reviewed
the captured results and corrected issues identified during
testing, including evidence image formats and file organisation.

AI assistance does not replace my responsibility for the accuracy,
understanding and explanation of the submitted work.

## References and final documentation

Technical references are listed in the individual portfolio guides.

The final LMS submission will provide the required 2–3 page
summary, repository link, individual reflection and applicable
AI-use declaration.
