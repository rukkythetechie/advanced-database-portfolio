# Portfolio 3 — Transactions and Concurrency

## Current checkpoint: 23 October 2026

This portfolio uses Corridor Pay to demonstrate database
transactions and concurrency controls.

The current checkpoint implements ledger posting protections
and demonstrates committed funding, rollback after a later
failure, and rejection of invalid ledger changes.

Multi-session concurrency tests and the remaining financial
operations have not been completed.

## Environment

- PostgreSQL 16.15 in the Docker container `corridor-pg`.
- Separate database: `corridorpay_p3`.
- Base schema: Portfolio 1's 12-table `schema.sql`.
- No real bank transfers or external settlement.

## Files

| File | Purpose |
| :--- | :--- |
| ledger-routines.sql | Posting routine, validation triggers and wallet/account protections |
| ledger-funding-test.sql | Creates fixtures and commits simulated NGN funding |
| ledger-rollback-test.sql | Demonstrates rollback after a successful temporary posting |
| ledger-protection-tests.sql | Exercises four rejection cases |
| evidence/ | Installation output, test transcripts and five PNG screenshots |

## Implementation

New ledger transactions must begin as drafts.

Posting requires at least two entries and equal total debits
and credits within each currency. Wallet liability accounts
must match their wallet's currency.

Posting updates affected wallet balances and marks the ledger
transaction as posted within the same database transaction.
The posting logic rejects a resulting negative wallet balance.

Entry changes lock their parent ledger transaction. Posting
also locks that transaction, holds shared locks on affected
accounts, and locks affected wallets in wallet-ID order.

Posted transactions cannot be updated or deleted. Entries
belonging to posted transactions cannot be changed. Account
type, currency and wallet linkage cannot change once the account
has posted entries.

Wallet identity, ownership and currency cannot change after
creation. Wallets must start at zero, and NaN balances are
explicitly rejected.

The tests below verify selected behaviours. They do not
establish that every protection or concurrent interaction
has been tested.

## Test results

### Committed funding

The funding test created an approved business, an admin user,
an NGN wallet, a wallet liability account and a cash asset account.

It posted:

- Debit cash: NGN 100,000.00.
- Credit wallet liability: NGN 100,000.00.

A successful audit event was inserted in the same transaction,
then COMMIT saved the changes.

After commit, the stored wallet balance and posted ledger
balance were both 100,000.00. The comparison returned true,
and the posting's debit and credit totals were equal.

### Rollback after a later failure

A second database transaction temporarily posted another
NGN 10,000.00 and inserted a success audit event.

Within that transaction, the wallet showed 110,000.00 and
the temporary ledger transaction showed posted.

A deliberately invalid audit outcome then violated
`audit_event_outcome_check`. Explicit ROLLBACK undid the
temporary funding and its audit event.

The wallet returned to 100,000.00. Queries found zero temporary
ledger transactions, zero temporary entries and zero temporary
success audits.

The posting routine does not independently commit. Its changes
remain part of the surrounding database transaction.

### Ledger protection tests

Four intentional operations were rejected:

1. Posting an already-posted transaction.
2. Editing a posted entry.
3. Changing the currency of an account with posted entries.
4. Posting NGN 100.00 of debits against NGN 90.00 of credits.

Savepoints recovered from the expected errors. Final rollback
left the original balance at 100,000.00, with one ledger
transaction and two entries.

The expected errors and final results were reviewed in the
captured transcripts. These scripts are demonstrations with
manual result inspection, not a complete automated test suite.

## Reproducing this checkpoint

Run commands from the repository root with Docker running.
Use a new database name that is not already in use.

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

Run the funding test once:

```bash
docker exec -i corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce < portfolio-3-transactions-concurrency/ledger-funding-test.sql
```

Run the rollback and protection tests:

```bash
docker exec -i corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce < portfolio-3-transactions-concurrency/ledger-rollback-test.sql
```

```bash
docker exec -i corridor-pg psql -X -a -v ON_ERROR_STOP=1 -P pager=off -U corridor -d corridorpay_p3_reproduce < portfolio-3-transactions-concurrency/ledger-protection-tests.sql
```

Expect one intentional constraint error in the rollback test
and four intentional rejection errors in the protection tests.
Other errors require investigation.

The final wallet balance should be 100,000.00, with one ledger
transaction and two entries. Generated IDs may differ because
sequence values are not restored by rollback.

## Remaining work and limits

- Test insufficient-funds rejection and additional ledger cases.
- Demonstrate isolation and competing operations in separate sessions.
- Implement controlled financial operations and business-role checks.
- Restrict application access to direct balance and financial-table writes.
- Implement payment transitions, history and linked reversals.
- Implement quote execution and currency-conversion checks.
- Record failed-attempt audit events separately after rollback.
- Extend reconciliation and complete the technical reflection.

The test admin's role and the business approval status are stored
data at this checkpoint; these tests do not demonstrate permission
enforcement.

The generic posting engine checks accounting balance. It does
not yet validate the complete business meaning of every funding,
payout, conversion or reversal.

Locks are implemented, but their concurrent behaviour still
requires multi-session demonstrations.

## Reference

PostgreSQL 16 documentation: Explicit Locking.
https://www.postgresql.org/docs/16/explicit-locking.html