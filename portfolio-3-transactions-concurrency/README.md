# Portfolio 3 — Transactions and Concurrency

## Current checkpoint: 26 October 2026

This portfolio uses Corridor Pay, a simulated cross-border
payments case study, to demonstrate atomic transactions,
ledger protections, wallet locking and controlled financial routines.

Implemented demonstrations cover:

- Committed wallet funding.
- Rollback after a later failure.
- Protection of posted ledger records.
- Insufficient-funds rejection.
- Two payments competing for the same wallet.
- Controlled payment processing and simulated settlement.
- Full payment reversals through compensating ledger transactions.
- Internal currency conversion using a saved quote.
- Restricted backend application access.
- Reconciliation of stored balances against posted ledger entries.

All business, user and banking details are sample data.
No real bank transfer, refund or external FX settlement occurs.

## Environment

- PostgreSQL 16.15.
- Docker container: `corridor-pg`.
- Evidence database: `corridorpay_p3`.
- Base schema: Portfolio 1's 12-table `schema.sql`.

## Files

| File | Purpose |
| :--- | :--- |
| ledger-routines.sql | Posting engine and ledger protections |
| ledger-funding-test.sql | Commits simulated funding and verifies accounting results |
| ledger-rollback-test.sql | Rolls back a posting after a later failure |
| ledger-protection-tests.sql | Tests four invalid ledger operations |
| ledger-insufficient-funds-test.sql | Tests spending beyond the wallet balance |
| concurrency-setup.sql | Creates two competing payment instructions |
| concurrency-session-a.sql | Posts A and pauses before commit |
| concurrency-session-b.sql | Attempts B and records its failure after rollback |
| payment-routines.sql | Controlled pending-to-processing operation |
| payment-processing-tests.sql | Successful processing and seven rejection cases |
| payment-settlement.sql | Simulated processing-to-completed operation |
| payment-settlement-tests.sql | Settlement, audit, history and duplicate checks |
| payment-reversal.sql | Full linked reversals of deducted payments |
| payment-reversal-tests.sql | Seven reversal cases |
| fx-routines.sql | Quote protection and controlled internal conversion |
| fx-tests.sql | Successful conversion and rejection checks |
| application-permissions.sql | Restricted backend role and routine ownership |
| application-permission-tests.sql | Denied direct writes and permitted routine calls |
| evidence/ | Installation output, test transcripts and selected screenshots |

## Ledger implementation

Ledger transactions begin as drafts. Posting requires at least
two entries and equal debits and credits within each currency.

Posting updates affected wallet balances and marks the ledger
transaction as posted within the surrounding database transaction.
The posting function does not independently commit.

Entry changes lock their parent ledger transaction. Posting locks
that transaction, stabilizes affected ledger accounts and locks
affected wallets in wallet-ID order.

Wallet liability credits increase the wallet balance; debits
decrease it. A posting cannot produce a negative wallet balance.

Posted transactions and their entries cannot be changed or deleted.
Account type, currency and wallet linkage cannot change once an
account has posted entries.

Wallets start at zero. Their identity, ownership and currency
remain fixed, and NaN balances are explicitly rejected.

## Results: funding, rollback and protections

### Committed funding

A funding transaction debited a platform cash asset and credited
the wallet liability by NGN 100,000.00.

The successful audit was saved in the same database transaction.

After commit, the stored wallet balance and posted ledger balance
were both NGN 100,000.00. Debit and credit totals also matched.

### Rollback after a later failure

A temporary NGN 10,000.00 funding posting increased the wallet
to NGN 110,000.00 inside an open transaction.

A later invalid audit outcome caused a constraint error.
Explicit rollback removed the temporary posting, entries and
success audit, restoring the wallet to NGN 100,000.00.

### Ledger protections

The tests rejected:

- Posting the same ledger transaction twice.
- Editing a posted entry.
- Changing the currency of an account with posted entries.
- Posting unequal debit and credit totals.

Savepoints recovered from the expected errors. Final rollback
preserved the original funding.

### Insufficient funds

A balanced NGN 120,000.00 posting was rejected against a wallet
holding NGN 100,000.00.

The wallet remained unchanged, the ledger transaction remained
draft and the payment remained pending. Final rollback removed
the temporary fixtures.

## Results: competing payments

Two sessions attempted NGN 70,000.00 payments from a wallet
holding NGN 100,000.00. Both used READ COMMITTED isolation.

A posted within an open transaction and paused before commit.
B then attempted its posting.

A third session used `pg_stat_activity` and `pg_blocking_pids()`
to confirm that B was waiting on a lock held by A.
The reported wait event was `transactionid`.

After A committed, B continued, rechecked the remaining funds
and was rejected.

B's failed posting was rolled back. Its failed payment status,
history and failure audit were saved in a separate transaction.

| Payment | Amount | Payment status | Ledger status |
| :--- | ---: | :--- | :--- |
| A | NGN 70,000.00 | processing | posted |
| B | NGN 70,000.00 | failed | draft |

The remaining wallet balance was NGN 30,000.00 and matched
the posted ledger balance.

The recorded waiting time includes a deliberate manual pause.
It is not a performance benchmark.

This concurrency demonstration exercised the posting engine
through session scripts. The later financial entry points were
tested separately; they were not subjected to another two-session run.

## Results: controlled payment operations

### Processing

`process_payment()` checks:

- The payment is pending.
- The supplied actor is active, belongs to the business and
  has an admin or finance role.
- The business is approved.
- Wallet and beneficiary ownership and currencies match.
- Wallet and clearing ledger accounts are suitable.
- No original processing posting already exists.

The routine posts the deduction, changes the status to processing,
adds history and records a success audit in one transaction.

Tests confirmed valid processing and rejection of duplicate
processing, a viewer, another business's user, an inactive user,
an unapproved business, mismatched currency and insufficient funds.

### Simulated settlement

`settle_payment()` validates the actor, payment state, original
processing entries and cash account.

It debits payout clearing and credits platform cash.
It marks the payment completed, records the completion timestamp
and saves history and an audit.

The test confirmed that settlement did not debit the wallet again.
An invalid cash account and duplicate settlement were rejected.

### Linked reversals

`reverse_payment()` creates new entries with the original debits
and credits exchanged.

An unsettled deducted payment requires one reversal.
A completed payment requires two: settlement first, then processing.

Processing payments pass through failed before reversed.
A failed payment without a posted deduction cannot receive a refund.

Tests confirmed:

- Processing-payment and failed-payment refunds.
- Completed-payment refunds with two linked reversals.
- Preservation of original posted records and completion timestamps.
- Reconciliation after refunds.
- Rejection of duplicate refunds and a missing reason.
- Rejection of a refund where no deduction occurred.

Completed-payment reversal represents a confirmed simulated
return of funds. It does not initiate a real bank refund.

All processing, settlement and reversal test changes were rolled
back. The committed concurrency wallet remained at NGN 30,000.00.

## Results: internal currency conversion

`execute_fx_quote()` validates the actor, business, wallet ownership,
currencies and platform asset accounts.

It locks the quote and both wallets, checks expiry after lock
acquisition and calculates the target amount rounded to two decimals.

Four entries balance independently within the two currencies.
The wallet changes, posted transaction, conversion record and
success audit belong to one database transaction.

The test used a sample rate of 0.000752154660 USD per NGN.

| Currency | Starting balance | After conversion | Posted ledger balance |
| :--- | ---: | ---: | ---: |
| NGN | 200,000.00 | 40,000.00 | 40,000.00 |
| USD | 0.00 | 120.34 | 120.34 |

NGN 160,000.00 converted to USD 120.34.

The tests rejected quote reuse, a viewer, identical wallets,
swapped wallet currencies, an expired quote, an invalid FX account,
insufficient funds and editing a saved quote.

Rejected attempts left no partial conversion or wallet movement.
Final rollback removed the temporary business and wallets.

Saved quotes are protected against updates and deletes by a trigger.
Quote deletion and concurrent quote acceptance were not separately
tested in this checkpoint.

## Results: application permissions

The `corridor_p3_app` role represents a trusted backend,
not an individual customer.

It can read existing tables and execute these entry points:

- process_payment()
- settle_payment()
- reverse_payment()
- execute_fx_quote()

It cannot directly write financial tables, call the raw posting
function or create objects in the public schema.

The four entry points use SECURITY DEFINER and belong to
`corridor_p3_routine_owner`, a non-login, non-superuser role.
Their search paths place the temporary schema last.

Tests switched to the restricted application role and confirmed
eight denied operations:

- Direct wallet update.
- Direct payment status update.
- Direct ledger transaction insertion.
- Audit deletion.
- Payment history deletion.
- Direct quote update.
- Calling the raw posting routine.
- Creating a table in the public schema.

All four permitted routines then executed successfully as the
restricted role.

Rollback restored the NGN 30,000.00 wallet and removed the
temporary USD wallet.

## Reproduction order

Use a fresh database to reproduce the complete sequence.
The scripts are not all intended for repeated installation.

1. Build Portfolio 1's schema.
2. Install ledger-routines.sql.
3. Run ledger-funding-test.sql once.
4. Run ledger-rollback-test.sql.
5. Run ledger-protection-tests.sql.
6. Run ledger-insufficient-funds-test.sql.
7. Run concurrency-setup.sql once.
8. Run sessions A and B with the blocking inspection described below.
9. Install payment-routines.sql.
10. Install payment-settlement.sql.
11. Install payment-reversal.sql.
12. Install fx-routines.sql.
13. Run the payment processing, settlement, reversal and FX tests.
14. Install application-permissions.sql.
15. Run application-permission-tests.sql.

Steps before the concurrency demonstration expect NGN 100,000.00.
Later fixture-dependent tests expect the committed NGN 30,000.00
balance and payment A in processing.

### Build and run commands

Run from the repository root with Docker running.

Create a new database using a name not already in use:

```bash
docker exec corridor-pg createdb -U corridor corridorpay_p3_reproduce
```

Build the base schema:

```bash
docker exec -i corridor-pg psql -X -v ON_ERROR_STOP=1 --single-transaction -U corridor -d corridorpay_p3_reproduce < portfolio-1-database-design/schema.sql
```

For each installation file in the order above, use this pattern,
replacing `FILE.sql` with the listed filename:

```bash
docker exec -i corridor-pg psql -X -v ON_ERROR_STOP=1 --single-transaction -U corridor -d corridorpay_p3_reproduce < portfolio-3-transactions-concurrency/FILE.sql
```

For each non-interactive test or setup file, use:

```bash
docker exec -i corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce < portfolio-3-transactions-concurrency/FILE.sql
```

Replace `FILE.sql` before running these commands.
Test scripts manage their own transactions.

### Interactive concurrency sequence

Copy the two session scripts into Docker:

```bash
docker cp portfolio-3-transactions-concurrency/concurrency-session-a.sql corridor-pg:/tmp/concurrency-session-a.sql
docker cp portfolio-3-transactions-concurrency/concurrency-session-b.sql corridor-pg:/tmp/concurrency-session-b.sql
```

Run A in one Terminal tab and leave it at the PAUSED prompt:

```bash
docker exec -it corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce -f /tmp/concurrency-session-a.sql
```

Run B in a second Terminal tab:

```bash
docker exec -it corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce -f /tmp/concurrency-session-b.sql
```

While B waits, inspect blocking from a third tab:

```bash
docker exec corridor-pg psql -X -P pager=off -U corridor -d corridorpay_p3_reproduce -c "SELECT blocked.application_name AS waiting_session, blocked.wait_event_type, blocked.wait_event, blocker.application_name AS blocking_session FROM pg_stat_activity AS blocked JOIN pg_stat_activity AS blocker ON blocker.pid = ANY(pg_blocking_pids(blocked.pid)) WHERE blocked.application_name = 'corridor_p3_B';"
```

After confirming B is waiting on A, return to A and press Enter.
Inspect A's commit and B's rejection before continuing.

The `-f` option allows A's interactive prompt to read Terminal input.

## Evidence and validation

The evidence folder contains installation output, complete test
transcripts and selected PNG screenshots dated 23, 25 and
26 October 2026.

The initial ledger tests use expected errors and manual inspection.
The later payment, reversal, FX and permission tests include
assertions that raise an exception when an expected result fails.

A zero process exit code alone is not sufficient evidence.
Review the transcript, PASS notices and final verification results.

Session transcripts contain echoed conditional branches.
Echoed commands do not establish that those branches executed.

Generated identity values may differ between runs because
sequence values are not restored by rollback.

## Transaction observations

- Atomicity: rollback removed related wallet, ledger and audit changes.
- Consistency: selected balance, ownership, currency and state rules
  were enforced through constraints and controlled routines.
- Isolation: explicit wallet locking serialized competing debits
  under READ COMMITTED.
- Committed results: later queries confirmed persisted funding
  and concurrency outcomes.

Crash recovery, other isolation levels, deadlock scenarios and
broader concurrent workloads were not tested.

## Scope and limitations

The application role trusts a backend to supply the authenticated
business user ID. Passing a user ID is not authentication.

Application reads span businesses. Row-level security and
tenant-specific read filtering are not implemented.

The administrator can prepare fixtures and perform privileged
writes. The access restrictions are demonstrated for the
restricted backend role.

Business onboarding, wallet/account creation, quote issuance
and initial payment instructions are prepared administratively.
They do not yet have application entry points.

The controlled routines enforce their own workflows.
They do not make every possible privileged table change valid.

Failure auditing after rollback is demonstrated in concurrency
session B. Other rejected calls raise errors; a caller must
separately record a failure after rollback if required.

Exactly one ledger account per wallet and automatic initial
payment history are not enforced globally.

Real bank integration, authentication, external FX settlement,
fees, overdrafts and partial reversals are outside scope.
Database atomicity does not make an external bank operation atomic.

Final assessment review and individual reflection remain to
be completed.

## References

PostgreSQL 16 documentation:

- [Transactions](https://www.postgresql.org/docs/16/tutorial-transactions.html)
- [Explicit Locking](https://www.postgresql.org/docs/16/explicit-locking.html)
- [Transaction Isolation](https://www.postgresql.org/docs/16/transaction-iso.html)
- [Privileges](https://www.postgresql.org/docs/16/ddl-priv.html)
- [CREATE FUNCTION](https://www.postgresql.org/docs/16/sql-createfunction.html)
- [psql](https://www.postgresql.org/docs/16/app-psql.html)