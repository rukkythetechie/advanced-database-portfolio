# Portfolio 2 — Query Optimisation

## Purpose

This portfolio examines three Corridor Pay queries using
PostgreSQL execution plans, indexes and captured results.

The tests use PostgreSQL 16.15 in the Docker container
`corridor-pg`. They were performed in the separate database
`corridorpay_p2`, using the schema from Portfolio 1.

## Dataset

| Table | Rows |
| :--- | ---: |
| business | 100 |
| business_user | 100 |
| wallet | 400 |
| beneficiary | 400 |
| payment | 100,000 |
| payment_status_history | 100,000 |

Every payment is pending and has one initial history record.
Wallet balances remain zero. These records support query
testing; they do not demonstrate financial operations.

## Queries and findings

| Query | Purpose | Captured finding |
| :--- | :--- | :--- |
| 1 | Latest 20 pending payments for one business | Execution decreased from 19.182 ms to 1.294 ms after indexing |
| 2 | Status history for one payment | Execution decreased from 11.088 ms to 0.588 ms after indexing |
| 3 | Pending payment counts and totals by currency | Sequential scan and aggregation; execution took 34.188 ms |

The complete outputs of Queries 1 and 2 were compared before
and after indexing. Both comparisons reported identical files.

These timings are individual observations, not guaranteed
performance improvements. The analysis discusses caching,
dataset limitations and index maintenance costs.

## Files

| File | Purpose |
| :--- | :--- |
| sample-data.sql | Creates the sample dataset in an empty schema |
| queries.sql | Query 1: recent pending payments |
| query-1-plan.sql | Execution plan for Query 1 |
| query-2.sql | Query 2: payment status history |
| query-2-plan.sql | Execution plan for Query 2 |
| query-3.sql | Currency report and its execution plan |
| indexes.sql | Creates the two additional indexes |
| query-optimisation-analysis.md | Results, plan interpretation and limitations |
| Evidence/ | Actual execution output, result comparisons and PNG screenshots |

The folder name `Evidence` uses a capital E.

## Reproducing the tests

Run the following commands in Mac Terminal from the repository
root. Docker and the `corridor-pg` container must be running.

Use a new database name that is not already in use. The example
below uses `corridorpay_p2_reproduce`. Leave the existing test
databases intact.

### 1. Create an empty database and build the schema

```bash
docker exec corridor-pg createdb -U corridor corridorpay_p2_reproduce
```

```bash
docker exec -i corridor-pg psql -X -v ON_ERROR_STOP=1 --single-transaction -U corridor -d corridorpay_p2_reproduce < portfolio-1-database-design/schema.sql
```

### 2. Load the sample data once

```bash
docker exec -i corridor-pg psql -X -v ON_ERROR_STOP=1 -U corridor -d corridorpay_p2_reproduce < portfolio-2-query-optimisation/sample-data.sql
```

Check that the six row counts match the dataset table above.

### 3. Run the queries before adding the extra indexes

```bash
docker exec -i corridor-pg psql -X -P pager=off -v ON_ERROR_STOP=1 -U corridor -d corridorpay_p2_reproduce < portfolio-2-query-optimisation/queries.sql
```

```bash
docker exec -i corridor-pg psql -X -P pager=off -v ON_ERROR_STOP=1 -U corridor -d corridorpay_p2_reproduce < portfolio-2-query-optimisation/query-2.sql
```

Capture the baseline plans:

```bash
docker exec -i corridor-pg psql -X -P pager=off -v ON_ERROR_STOP=1 -U corridor -d corridorpay_p2_reproduce < portfolio-2-query-optimisation/query-1-plan.sql
```

```bash
docker exec -i corridor-pg psql -X -P pager=off -v ON_ERROR_STOP=1 -U corridor -d corridorpay_p2_reproduce < portfolio-2-query-optimisation/query-2-plan.sql
```

Primary-key and unique-constraint indexes already exist at this
stage. “Before indexing” means before adding the two performance
indexes in `indexes.sql`.

### 4. Add the performance indexes once

```bash
docker exec -i corridor-pg psql -X -v ON_ERROR_STOP=1 --single-transaction -U corridor -d corridorpay_p2_reproduce < portfolio-2-query-optimisation/indexes.sql
```

Repeat the four commands in Step 3 against the same database.
Compare the returned results, scan methods, sorts, buffer usage
and execution times.

In the original tests, results were captured to separate text
files and checked with `diff -s`. Those comparisons are saved
in `Evidence/`.

### 5. Run the currency report

```bash
docker exec -i corridor-pg psql -X -P pager=off -v ON_ERROR_STOP=1 -U corridor -d corridorpay_p2_reproduce < portfolio-2-query-optimisation/query-3.sql
```

Expect four currency groups: CAD, GBP, NGN and USD.
Each group should contain 25,000 payments and a total pending
amount of 33,875,000.00 in its own currency.

## Reading the evidence

Text transcripts preserve the SQL and actual database output.
Screenshots show selected results and execution plans.

The captured comparisons show that targeted lookups benefited
from indexes. The report still used a sequential scan because
all sample payments contributed to its totals.

Execution plans and timings can differ on another computer.
The sample data is evenly distributed, all payments are pending,
and each payment has only one history record. These limitations
are explained in the analysis.