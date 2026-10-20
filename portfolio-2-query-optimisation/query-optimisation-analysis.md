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

The overall performance comparison for Portfolio 2 is still
in progress.