# Portfolio 1 | Database Design and Modelling

## Scope

This portfolio documents the base schema and structural tests
completed on 19–20 October 2026.

Financial routines, transaction tests and application access
controls were subsequently added in
[Portfolio 3](../portfolio-3-transactions-concurrency/README.md).

The base `schema.sql` is kept separate from those additions.

## Case study

Corridor Pay is a fintech company used as a simulated case study.
It helps small and mid-sized businesses pay suppliers across borders.

The prototype covers Nigeria, Canada, the United Kingdom and
the United States, using NGN, CAD, GBP and USD.

Business users have admin, finance or viewer roles. The intended
operations include managing supplier destinations, funding wallets,
converting currencies and tracking supplier payments.

Each business can hold only one wallet per currency. The design
includes a double-entry ledger, payment status history and audit events.

All businesses, users and banking details used in testing are sample data.

## Files

| File | Purpose |
| :--- | :--- |
| corridor-pay-database-design.md | Scope, business rules, table dictionary, accounting examples and enforcement plan |
| er-diagram.md | Mermaid ER diagram, cardinalities and implementation notes |
| normalisation-analysis.md | Candidate keys, functional dependencies and normalisation trade-offs |
| schema.sql | PostgreSQL definitions for all 12 tables |
| business-constraint-tests.sql | Tests for the business table |
| business-user-constraint-tests.sql | Tests for business users |
| wallet-constraint-tests.sql | Tests for wallets |
| schema-constraint-tests.sql | 35 numbered tests covering the wider schema |
| evidence/ | Captured execution output, table structures and selected screenshots |

## Implementation and results

The schema was built successfully in the separate PostgreSQL database
`corridorpay_p1_check`, using PostgreSQL 16.15 in the Docker container
`corridor-pg`.

The build ran in a single transaction with stop-on-error enabled.
All 12 tables were created.

The wider schema test script produced the reviewed expected outcomes
for its 35 numbered tests, including 25 intentional constraint errors.

Successful examples included saved supplier destinations, a quote,
a pending payment, ledger records, payment history, an audit event
and a conversion record.

After the final rollback, all 12 tables contained zero rows.

At the initial checkpoint, the original `corridorpay` database
contained the first three tables: business, business_user and wallet.
The full-schema build and wider tests were performed separately
in `corridorpay_p1_check`.

## Reproducing the build

Run these commands in the Mac Terminal from the repository root.
Docker must be running and the `corridor-pg` container must be available.

Create a new empty database using a name that is not already in use:

```bash
docker exec corridor-pg createdb -U corridor corridorpay_p1_reproduce
```

Build the schema:

```bash
docker exec -i corridor-pg psql -X -v ON_ERROR_STOP=1 --single-transaction -U corridor -d corridorpay_p1_reproduce < portfolio-1-database-design/schema.sql
```

List the tables:

```bash
docker exec corridor-pg psql -X -U corridor -d corridorpay_p1_reproduce -c '\dt'
```

The expected result is 12 tables. The schema script is intended for
an empty database; do not rerun it against an existing schema.

## Reproducing the structural tests

Run the wider schema tests and capture both SQL commands and output:

```bash
docker exec -i corridor-pg psql -X -a -U corridor -d corridorpay_p1_reproduce < portfolio-1-database-design/schema-constraint-tests.sql > portfolio-1-database-design/evidence/schema-constraint-test-run-reproduce.txt 2>&1
```

Inspect the complete transcript:

```bash
cat portfolio-1-database-design/evidence/schema-constraint-test-run-reproduce.txt
```

Expected results:

- Valid test records are accepted.
- The 25 intentionally invalid statements produce the intended errors.
- Savepoints allow the script to recover from those errors.
- The final rollback removes all test records.
- The final count query reports zero rows in all 12 tables.

The script is not an automated assertion-based test suite.
Its expected errors and successful results must be inspected.
A zero process exit code alone does not establish that every test
behaved correctly.

Generated IDs may differ between runs because PostgreSQL identity
sequence values are not restored by rollback.

The three earlier table-specific scripts can also be run individually
against an empty schema. Each rolls back its test records.

## Evidence

The evidence folder includes:

- Earlier manual-test summaries and table-structure output.
- Full rerun transcripts dated 18 October 2026 for the first three tables.
- Selected screenshots from those reruns.
- The full-schema build transcript dated 19 October 2026.
- A table-list transcript and screenshot showing all 12 tables.
- The wider constraint-test transcript dated 19 October 2026.
- A screenshot of the final zero-row counts.

The full-schema test run started on 19 October. Document review
continued after midnight on 20 October.

Text transcripts preserve the complete captured output.
Screenshots show selected results and support the transcripts.

## Design decisions and limits

The base schema enforces keys, required fields, allowed values,
uniqueness, business ownership references and other row-level
constraints.

Payment and FX Conversion deliberately retain repeated business
ownership information. Their departures from strict 3NF and the
reasons for retaining that information are explained in the
normalisation analysis.

Some intended relationships require more than foreign keys.
For example, the base schema permits a wallet without a ledger
account and a payment without history.

Creating a wallet with its matching liability account and recording
initial payment history are handled administratively in the
demonstrations.

The Portfolio 1 structural tests do not demonstrate balanced
financial posting, controlled wallet updates or atomic currency
conversion. Their conversion records test table constraints only.

Portfolio 3 subsequently adds and tests ledger posting protections,
controlled payment workflows, FX conversion, rollback, competing
wallet debits and restricted application permissions.

Working customer authentication and row-level security are not
implemented. The application role represents a trusted backend.

Section 9 of the design document records the implementation
boundaries. See the Portfolio 3 guide for operational coverage.

Real bank integration, external FX settlement, fees, overdrafts
and partial reversals are outside the prototype's scope.

## Assessment coverage

| Portfolio 1 area | Supporting file |
| :--- | :--- |
| Case study and business rules | corridor-pay-database-design.md |
| ER diagram and relationships | er-diagram.md |
| Relational schema, keys and constraints | schema.sql |
| Functional dependencies and normalisation | normalisation-analysis.md |
| Implementation evidence | Test scripts and evidence/ |

References are included in the design and normalisation documents.