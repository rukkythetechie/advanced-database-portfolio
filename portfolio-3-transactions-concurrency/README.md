# Portfolio 3 — Transactions and Concurrency

## Current checkpoint: 25 October 2026

This portfolio uses Corridor Pay, a simulated cross-border
payments case study, to demonstrate database transactions
and concurrency controls.

The implementation currently demonstrates:

- Committed wallet funding with balanced ledger entries.
- Rollback after a later operation fails.
- Protection of posted ledger records.
- Rejection of insufficient-funds postings.
- Two payments competing for the same wallet.
- Reconciliation of wallet balances against posted ledger entries.

Financial workflows and application access controls remain
in progress.

## Environment

- PostgreSQL 16.15.
- Docker container: `corridor-pg`.
- Test database: `corridorpay_p3`.
- Base schema: Portfolio 1's 12-table `schema.sql`.
- All business, user and banking details are sample data.
- No real bank transfers or external settlement.

## Files

| File | Purpose |
| :--- | :--- |
| ledger-routines.sql | Posting routine and ledger protection triggers |
| ledger-funding-test.sql | Creates fixtures and commits simulated funding |
| ledger-rollback-test.sql | Demonstrates rollback after a temporary posting |
| ledger-protection-tests.sql | Tests four invalid ledger operations |
| ledger-insufficient-funds-test.sql | Tests rejection when funds are insufficient |
| concurrency-setup.sql | Creates two competing pending payments |
| concurrency-session-a.sql | Posts payment A and pauses before commit |
| concurrency-session-b.sql | Attempts payment B and records its failure after rollback |
| evidence/ | Captured execution output and supporting screenshots |

## Ledger implementation

New ledger transactions must begin as drafts.

Posting requires at least two entries and equal total debits
and credits within each currency. Wallet liability accounts
must match their wallet's currency.

The posting operation updates affected wallet balances and
marks the ledger transaction as posted within the same database
transaction. It rejects a resulting negative wallet balance.

Entry changes lock their parent ledger transaction. Posting
also locks that transaction, holds shared locks on affected
accounts and locks affected wallets in wallet-ID order.

Posted ledger transactions cannot be updated or deleted.
Entries belonging to posted transactions cannot be changed.
Account type, currency and wallet linkage cannot change
once an account has posted entries.

Wallet identity, business ownership and currency cannot change
after creation. Wallets must start at zero, and NaN balances
are explicitly rejected.

The posting routine does not independently commit. Its changes
remain part of the surrounding database transaction.

These tests cover selected behaviours, rather than every
possible operation or concurrent interaction.

## Test results

### 1. Committed funding

The funding test created an approved business, an admin user,
an NGN wallet, a wallet liability account and a cash asset account.

The funding transaction contained:

- Debit cash: NGN 100,000.00.
- Credit wallet liability: NGN 100,000.00.

A successful audit event was inserted in the same database
transaction. COMMIT saved the changes.

Verification showed:

- Stored wallet balance: NGN 100,000.00.
- Posted ledger balance: NGN 100,000.00.
- Balance comparison: true.
- Total debits and credits: NGN 100,000.00 each.

### 2. Rollback after a later failure

A second database transaction temporarily posted another
NGN 10,000.00 and inserted a success audit event.

Within that transaction, the wallet showed NGN 110,000.00
and the temporary ledger transaction showed posted.

A deliberately invalid audit outcome then violated
`audit_event_outcome_check`. Explicit ROLLBACK undid the
temporary posting, wallet change and success audit.

Verification showed:

- Wallet balance restored to NGN 100,000.00.
- Zero temporary ledger transactions.
- Zero temporary ledger entries.
- Zero temporary success audits.

This demonstrates that a posting remains reversible through
rollback until its surrounding database transaction commits.

### 3. Ledger protection tests

Four intentional operations were rejected:

1. Posting an already-posted transaction.
2. Editing a posted ledger entry.
3. Changing the currency of an account with posted entries.
4. Posting NGN 100.00 of debits against NGN 90.00 of credits.

Savepoints allowed recovery from the expected errors.
The final rollback left the original funding unchanged:

- Wallet balance: NGN 100,000.00.
- Ledger transactions: one.
- Ledger entries: two.

### 4. Insufficient funds

The test attempted a balanced posting of NGN 120,000.00
against a wallet holding NGN 100,000.00.

The posting routine rejected the attempt because the wallet
could not cover the debit.

After recovery to the savepoint:

- The wallet still held NGN 100,000.00.
- The ledger transaction remained draft.
- The payment remained pending.

The final rollback removed all temporary fixtures.
The original funding remained, with one ledger transaction,
two ledger entries and no payments.

### 5. Two competing payments

Two separate PostgreSQL sessions attempted payments of
NGN 70,000.00 each from the same wallet, initially holding
NGN 100,000.00.

Both sessions used READ COMMITTED isolation.

Session A posted its payment within an open transaction,
then paused before committing. It saw its own uncommitted
wallet balance of NGN 30,000.00 and held the wallet row lock.

Session B attempted its posting while A remained open.

A third session inspected `pg_stat_activity` and
`pg_blocking_pids()`. The result confirmed:

- Waiting session: `corridor_p3_B`.
- Wait type: `Lock`.
- Wait event: `transactionid`.
- Blocking session: `corridor_p3_A`.

After A committed, B continued. Its posting was rejected
because the remaining NGN 30,000.00 could not cover its
NGN 70,000.00 payment.

B's failed posting attempt was rolled back. Its failed payment
status, history record and failure audit were then saved in
a separate database transaction.

| Test | Payment amount | Payment status | Ledger status |
| :--- | ---: | :--- | :--- |
| A | NGN 70,000.00 | processing | posted |
| B | NGN 70,000.00 | failed | draft |

Only A's debit was applied. B's draft entries were excluded
from the posted ledger balance.

Final reconciliation showed:

| Measure | Result |
| :--- | ---: |
| Stored wallet balance | NGN 30,000.00 |
| Posted ledger balance | NGN 30,000.00 |
| Balances match | true |

This demonstrates that wallet locking and the balance recheck
prevented both competing debits from succeeding in this test.

Payment A remains processing. Supplier settlement was not
demonstrated.

B's recorded waiting time includes the deliberate manual pause.
It is not a database performance benchmark.

## Transaction and isolation observations

### Atomicity

The rollback demonstration showed that wallet changes, ledger
records and a success audit could be undone together after
a later operation failed before commit.

### Consistency

The posting routine rejected unbalanced entries and attempted
spending beyond the wallet balance.

Reconciliation confirmed that the stored wallet balance matched
the posted ledger balance after the concurrency test.

### Isolation

The concurrency demonstration used READ COMMITTED isolation
with explicit wallet row locking.

B waited while A held the lock. After A committed, B's balance
check used the remaining funds and rejected the second debit.

Other isolation levels and broader concurrent interactions
have not been tested.

### Committed results

Queries after commit confirmed the saved funding and final
payment outcomes. Recovery after a database or host crash
was not tested.

## Reproducing the initial tests

Run these commands in Mac Terminal from the repository root,
with Docker running.

Use a new database name that is not already in use:

```bash
docker exec corridor-pg createdb -U corridor corridorpay_p3_reproduce
```

Build the base schema:

```bash
docker exec -i corridor-pg psql -X -v ON_ERROR_STOP=1 --single-transaction -U corridor -d corridorpay_p3_reproduce < portfolio-1-database-design/schema.sql
```

Install the routines once:

```bash
docker exec -i corridor-pg psql -X -v ON_ERROR_STOP=1 --single-transaction -U corridor -d corridorpay_p3_reproduce < portfolio-3-transactions-concurrency/ledger-routines.sql
```

Run the funding demonstration once:

```bash
docker exec -i corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce < portfolio-3-transactions-concurrency/ledger-funding-test.sql
```

Run the rollback demonstration:

```bash
docker exec -i corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce < portfolio-3-transactions-concurrency/ledger-rollback-test.sql
```

Run the protection tests:

```bash
docker exec -i corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce < portfolio-3-transactions-concurrency/ledger-protection-tests.sql
```

Run the insufficient-funds test:

```bash
docker exec -i corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce < portfolio-3-transactions-concurrency/ledger-insufficient-funds-test.sql
```

Expected intentional errors:

- One audit constraint error in the rollback demonstration.
- Four rejection errors in the protection tests.
- One insufficient-funds error in the insufficient-funds test.

Other errors require investigation.

After these tests, the wallet should still hold NGN 100,000.00,
with one ledger transaction and two entries.

## Reproducing the concurrency demonstration

Continue in the reproduction database after the initial tests.

Create the competing-payment fixtures once:

```bash
docker exec -i corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce < portfolio-3-transactions-concurrency/concurrency-setup.sql
```

Copy both session scripts into the container:

```bash
docker cp portfolio-3-transactions-concurrency/concurrency-session-a.sql corridor-pg:/tmp/concurrency-session-a.sql
docker cp portfolio-3-transactions-concurrency/concurrency-session-b.sql corridor-pg:/tmp/concurrency-session-b.sql
```

Start Session A in one Terminal tab:

```bash
docker exec -it corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce -f /tmp/concurrency-session-a.sql
```

Leave A at its PAUSED prompt. Do not press Enter yet.

Start Session B in a second Terminal tab:

```bash
docker exec -it corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce -f /tmp/concurrency-session-b.sql
```

B should wait at its posting call.

In a third Terminal tab, inspect the blocking relationship:

```bash
docker exec corridor-pg psql -X -P pager=off -U corridor -d corridorpay_p3_reproduce -c "SELECT blocked.application_name AS waiting_session, blocked.wait_event_type, blocked.wait_event, blocker.application_name AS blocking_session FROM pg_stat_activity AS blocked JOIN pg_stat_activity AS blocker ON blocker.pid = ANY(pg_blocking_pids(blocked.pid)) WHERE blocked.application_name = 'corridor_p3_B';"
```

Expect B to be waiting for a lock held by A.

Return to A and press Enter once to commit.
B should then reject its posting and record the failed attempt.

Verify both outcomes:

```bash
docker exec corridor-pg psql -X -P pager=off -U corridor -d corridorpay_p3_reproduce -c "SELECT t.description AS test, p.amount, p.status AS payment_status, t.status AS ledger_status, w.balance AS wallet_balance FROM ledger_transaction AS t JOIN payment AS p ON p.payment_id = t.payment_id JOIN wallet AS w ON w.wallet_id = p.wallet_id WHERE t.description IN ('Concurrency test A', 'Concurrency test B') ORDER BY t.description;"
```

Expect A to be processing with a posted ledger transaction,
B to be failed with a draft ledger transaction, and the wallet
to hold NGN 30,000.00.

Reconcile the wallet against posted ledger entries:

```bash
docker exec corridor-pg psql -X -P pager=off -U corridor -d corridorpay_p3_reproduce -c "SELECT w.wallet_id, w.currency_code, w.balance AS stored_balance, SUM(CASE e.entry_type WHEN 'credit' THEN e.amount ELSE -e.amount END) AS ledger_balance, w.balance = SUM(CASE e.entry_type WHEN 'credit' THEN e.amount ELSE -e.amount END) AS balances_match FROM wallet AS w JOIN business AS b ON b.business_id = w.business_id JOIN ledger_account AS a ON a.wallet_id = w.wallet_id JOIN ledger_entry AS e ON e.ledger_account_id = a.ledger_account_id JOIN ledger_transaction AS t ON t.ledger_transaction_id = e.ledger_transaction_id WHERE b.registration_number = 'P3-LEDGER-001' AND b.country_code = 'NG' AND w.currency_code = 'NGN' AND t.status = 'posted' GROUP BY w.wallet_id, w.currency_code, w.balance;"
```

Expect both balances to be NGN 30,000.00 and
`balances_match` to be true.

Use psql's `-f` option for the session scripts so that A can
accept input at its interactive prompt.

The concurrency demonstration changes committed data.
Earlier tests that expect NGN 100,000.00 must run before it
or in a fresh test database.

Generated IDs may differ between runs because sequence values
are not restored by rollback.

## Evidence

### Initial ledger tests — 23 October 2026

- schema-build.txt
- ledger-routines-install.txt
- ledger-funding-test.txt
- ledger-rollback-test.txt
- ledger-protection-tests.txt
- Five supporting PNG screenshots dated 23 October 2026.

### Insufficient funds and concurrency — 25 October 2026

- ledger-insufficient-funds-test.txt
- concurrency-setup.txt
- concurrency-session-a.txt
- concurrency-session-b.txt
- concurrency-blocking.txt
- concurrency-final-results.txt
- concurrency-wallet-reconciliation.txt
- Four supporting PNG screenshots dated 25 October 2026.

The captured runs used `corridorpay_p3`. The reproduction
commands use a separate database to preserve those results.

The scripts are demonstrations with manual result inspection,
not a complete automated assertion-based test suite.
A zero process exit code alone does not prove that every
expected outcome occurred.

Session transcripts include echoed SQL and psql conditional
branches. Echoed commands alone do not establish execution;
returned results and verification queries show the outcomes.

## Remaining work and limits

- Extend coverage of additional ledger cases.
- Implement controlled financial operations and business-role checks.
- Restrict application access to direct balance and financial-table writes.
- Implement controlled payment transitions and linked reversals.
- Implement quote execution and currency-conversion checks.
- Extend failed-attempt auditing beyond the demonstrated concurrency case.
- Extend reconciliation and complete the technical reflection.

The test admin's role and business approval status are stored
data at this checkpoint. These tests do not demonstrate
permission enforcement.

The generic posting engine checks accounting balance.
It does not yet validate the complete business meaning of
every funding, payout, conversion or reversal.

Payment status changes, history records and audits in the
concurrency demonstration are coordinated by the test scripts.
They are not yet enforced through a complete payment workflow.

Database atomicity does not establish atomicity with an
external bank or payment partner.

## References

PostgreSQL 16 documentation:

- [Explicit Locking](https://www.postgresql.org/docs/16/explicit-locking.html)
- [Transaction Isolation](https://www.postgresql.org/docs/16/transaction-iso.html)
- [psql](https://www.postgresql.org/docs/16/app-psql.html)