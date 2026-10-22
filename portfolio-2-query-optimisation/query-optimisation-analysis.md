# Query Optimisation Analysis

## Test setup

These tests use PostgreSQL 16.15 in the Docker container
`corridor-pg`, with the separate database `corridorpay_p2`.

The sample dataset contains 100 businesses, 100 business users,
400 wallets, 400 supplier destinations, 100,000 pending payments
and 100,000 initial payment-history records.

These are sample instructions for query testing. They do not
represent completed payments or demonstrate money movements.

## Query 1: Recent pending payments

This query returns a business’s 20 most recent pending payments,
including the supplier, currency, amount and request timestamp.

Payments are ordered by request timestamp, then payment ID,
both descending. The payment ID gives a consistent order when
timestamps match.

### Before indexing

PostgreSQL scanned all 100,000 payment rows. The joins narrowed
these to 1,000 payments belonging to the selected business.
A top-N heapsort selected the first 20 results.

The captured execution time was 19.182 ms.

### Index added

The index contains these columns, in order:

- business_id
- status
- created_at DESC
- payment_id DESC

The first two columns support the business and status filters.
The remaining columns match the requested payment order, although
this captured plan still uses a separate sort.

### After indexing

PostgreSQL used `payment_business_status_recent_idx` through a
Bitmap Index Scan, followed by a Bitmap Heap Scan.

The payment scan returned 1,000 matching rows and accessed
13 heap blocks. PostgreSQL joined those records to the supplier
and wallet tables, then sorted them to return 20 rows.

The captured execution time was 1.294 ms.

### Comparison

| Measure | Before index | After index |
| :--- | ---: | ---: |
| Execution time | 19.182 ms | 1.294 ms |
| Rows returned by the payment scan | 100,000 | 1,000 |
| Overall execution buffers | 1,252 shared hits | 30 shared hits and 9 shared reads |
| Payment access method | Sequential scan | Bitmap index and heap scans |
| Separate sort | Yes | Yes |

In these two runs, execution was about 15 times faster.
The main improvement was finding the relevant payments without
scanning the full payment table.

### Limits and trade-offs

These timings come from one captured run before indexing and
one afterwards. They demonstrate an improvement on this dataset,
rather than a guaranteed speed increase for every workload.
Caching and other activity can affect execution times.

All sample payments are pending, so the test does not establish
how selective the status column would be with mixed statuses.

The index uses additional storage and must be maintained when
payments are inserted or indexed values change.

The measurements above exclude planning time. The full plans
record planning and execution times separately.

### Evidence

- `Evidence/query-results.txt`
- `Evidence/index-creation.txt`
- `Evidence/query-1-plan-before.txt`
- `Evidence/query-1-plan-after.txt`
- Selected before-and-after screenshots in `Evidence/`

## Query 2: Payment status history

This query retrieves the history of payment 1, ordered by event
timestamp and history ID. It returned the expected initial
pending record.

### Before indexing

PostgreSQL scanned all 100,000 history records, discarded
99,999 non-matching rows and sorted the remaining result.

The captured execution time was 11.088 ms.
Execution used 1,646 shared buffer hits.

### Index added

The index `payment_history_payment_time_idx` contains
payment_id, changed_at and history_id, in that order.

The first column supports finding a payment's history.
The remaining columns match the requested event order.

### After indexing

PostgreSQL used an Index Scan with payment_id = 1 as the
index condition. The separate sort was no longer needed.

The captured execution time was 0.588 ms.
Execution used 4 shared buffer hits and 3 shared buffer reads.

### Comparison

| Measure | Before index | After index |
| :--- | ---: | ---: |
| Execution time | 11.088 ms | 0.588 ms |
| Access method | Sequential scan | Index scan |
| Rows removed by filter | 99,999 | No filter removals reported |
| Separate sort | Yes | No |
| Execution buffers | 1,646 shared hits | 4 shared hits and 3 shared reads |

Execution was about 19 times faster in these captured runs.

### Limits and trade-offs

Each sample payment has only one history record. This test
demonstrates finding one record within a large history table.
It does not test sorting a long history for one payment.

The timings represent individual runs and may vary with caching
and system activity. The index also requires storage and
maintenance when history records are inserted.

### Evidence

- `query-2.sql`
- `query-2-plan.sql`
- `Evidence/query-2-results.txt`
- `Evidence/query-2-index-creation.txt`
- `Evidence/query-2-plan-before.txt`
- `Evidence/query-2-plan-after.txt`
- `Evidence/query-2-plan-before-2026-10-21.png`
- `Evidence/query-2-plan-after-2026-10-21.png`

## Query 3: Pending payment totals by currency

This report counts pending payments and totals their amounts
separately for each currency. It joins payments to wallets to
obtain the currency.

Each currency returned 25,000 payments with a total pending
amount of 33,875,000.00. These totals match the sample data:
each currency has 100 wallets, with 250 payments per wallet.
Each wallet's payment amounts run from 110.00 to 2,600.00,
in increments of 10.00.

The totals represent pending instructions, not settled payments
or wallet balances. Amounts in different currencies are not
combined.

### Execution plan

PostgreSQL used sequential scans on the payment and wallet
tables, followed by a hash join and a hash aggregate.
It then sorted the four currency groups.

The captured execution time was 34.188 ms, with 1,238 shared
buffer hits during execution.

All 100,000 payments contribute to this report because every
sample payment is pending. Reading the full payment table is
therefore reasonable. The existing indexes were available,
but PostgreSQL chose sequential scans for this query.

No additional index was created for this report. This example
shows that a sequential scan alone is not evidence of a
performance problem. A different data distribution or a more
selective report could produce a different plan.

### Evidence

- `query-3.sql`
- `Evidence/query-3-report-and-plan.txt`
- `Evidence/query-3-currency-totals-2026-10-22.png`

## Result checks

Queries 1 and 2 were rerun after indexing. Their complete
captured outputs were compared with the original outputs
using `diff -s`.

Both comparisons reported identical files. For these tested
queries and this dataset, the indexes preserved the returned
values and ordering.

The comparison evidence is saved in:

- `Evidence/query-1-results-after.txt`
- `Evidence/query-1-result-comparison.txt`
- `Evidence/query-2-results-after.txt`
- `Evidence/query-2-result-comparison.txt`

## Findings

The two targeted lookups benefited from indexes. Query 1
avoided scanning the full payment table, while Query 2 used
an index scan and no longer needed a separate sort.

The currency report needed every payment, so PostgreSQL
continued to use a sequential scan.

These are individual captured measurements on sample data.
They demonstrate the observed plans and timings rather than
a controlled benchmark or guaranteed production performance.