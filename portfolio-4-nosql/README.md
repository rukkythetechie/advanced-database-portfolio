# Portfolio 4 — NoSQL Document Modelling

## Case study and purpose

This portfolio models Corridor Pay audit events using MongoDB.

Different actions need different details. A funding event records
a currency and amount; a failed payment records a reason; an FX
conversion records source and target currencies, amounts and
a quote reference.

The demonstration uses standalone sample events. It does not
export or synchronize records from the PostgreSQL portfolios.

## Environment and files

- Docker image: mongo:7.
- Container: corridor-mongo.
- Database: corridorpay_p4.
- Main collection: audit_events.
- Supporting collection: audit_review_notes.

| File | Purpose |
| :--- | :--- |
| mongodb-demo.js | Collection validation, indexes, sample data, queries and tests |
| evidence/mongodb-demo.txt | Complete captured execution output |
| evidence/mongodb-version.txt | Server version used |
| evidence/ | Selected PNG screenshots |

## Document model

Each audit event contains a consistent envelope and an
action-specific details object.

| Field | Purpose |
| :--- | :--- |
| _id | MongoDB-generated document identifier |
| event_id | Unique application event identifier |
| schema_version | Identifies this document format |
| source | Marks these events as standalone samples |
| business_id | Identifies the sample business |
| actor | Embedded actor type and user identifier |
| action | Operation being recorded |
| entity | Embedded entity type and identifier |
| outcome | success or failure |
| occurred_at | BSON date for the event |
| details | Fields relevant to the particular action |

Actor and entity information are embedded because they are read
with the event. These objects contain references rather than
complete copies of business or user records.

Monetary values use BSON Decimal128. Currency codes remain
explicit, and amounts in different currencies are not added
together.

The identifiers in these sample documents are illustrative.
They are not foreign keys to the PostgreSQL database.

## Validation

The collection uses strict validation with validationAction
set to error.

The validator requires the main event fields and checks their
types. Outcomes must be success or failure. A user actor requires
an integer user identifier; a system actor requires a null
user identifier.

The details field must be an object, but its internal fields
can vary by action. Action-specific monetary and business rules
are not comprehensively validated.

The test confirmed that an invalid outcome was rejected.
Other validator rules were defined but not individually tested.

## Indexes

| Index | Definition and purpose |
| :--- | :--- |
| _id_ | MongoDB's default identifier index |
| event_id_unique | Prevents duplicate application event identifiers |
| business_recent_events | business_id ascending, occurred_at descending, event_id descending |
| outcome_recent_events | outcome ascending, occurred_at descending |

The business index matches the business filter and requested
event order. event_id provides a tie-breaker when timestamps match.

The outcome index is available for filtering events by outcome
and ordering them by time. Its use was not separately measured.

Indexes require storage and maintenance during writes.

## Sample events

Six events were inserted across two sample businesses:

- Two successful wallet funding events.
- One successful payment processing event.
- One failed payment processing event.
- One successful FX conversion event.
- One failed FX quote execution event.

These events demonstrate document shapes and queries.
They are not a complete chronological wallet ledger.

## Queries and captured results

### Recent business events

The query filters business 1001, sorts newest first and
returns three records.

The expected event order was:

1. P4-005.
2. P4-004.
3. P4-003.

The assertion passed.

### Failed events

The query returned two failures and their nested reasons:

| Event | Reason |
| :--- | :--- |
| P4-003 | insufficient_funds |
| P4-005 | quote_expired |

### Counts by action and outcome

The aggregation grouped events by action and outcome:

| Action | Outcome | Count |
| :--- | :--- | ---: |
| execute_fx_quote | failure | 1 |
| execute_fx_quote | success | 1 |
| process_payment | failure | 1 |
| process_payment | success | 1 |
| wallet_funding | success | 2 |

The grouped counts accounted for all six events.

## CRUD demonstration

Audit events were inserted and queried.

Update and delete operations were demonstrated on a separate
review note associated with the failed payment event:

1. Insert a temporary note with reviewed set to false.
2. Update it to reviewed and change its text.
3. Retrieve the updated note.
4. Delete the temporary note.

This separates editable review information from the original
event records.

The final counts were:

| Collection | Documents |
| :--- | ---: |
| audit_events | 6 |
| audit_review_notes | 0 |

The demonstration leaves the audit events unchanged.
It does not enforce append-only access through MongoDB roles.

## Validation and index results

The script confirmed:

- Six sample audit events were inserted.
- Recent events appeared in the expected order.
- Two failed events were returned.
- Aggregation accounted for all events.
- An invalid audit outcome was rejected.
- A duplicate event identifier was rejected.
- The review note was updated and deleted.
- Six audit events remained.

An explain run for the recent-business lookup used:

LIMIT → FETCH → IXSCAN

The selected index was business_recent_events.

| Measure | Captured result |
| :--- | ---: |
| Documents returned | 3 |
| Documents examined | 3 |
| Index keys examined | 3 |

The explain run retrieved complete documents; the displayed
recent-events query used a smaller projection.

This demonstrates index selection on a six-document dataset.
It is not a before-and-after performance benchmark and does
not establish production-scale performance.

## Suitability and trade-offs

The document model groups each event with its actor, entity
and action-specific details. This supports reading an event
without assembling those nested objects from separate tables.

The details object accommodates different event shapes while
validation maintains a consistent envelope.

PostgreSQL remains suitable for the financial records and
relational constraints demonstrated in earlier portfolios.
Its existing audit_event table also supports JSONB details;
MongoDB is an alternative document implementation, rather than
a requirement for storing flexible event data.

A separate MongoDB service introduces deployment, monitoring,
access-control and synchronization responsibilities.

Business and user references are not enforced as relational
foreign keys. Any integration would need explicit handling of
event delivery, retries, duplicate identifiers and reconciliation.

No cross-database atomicity is demonstrated.

## Reproducing the demonstration

Start the existing MongoDB container:

```bash
docker start corridor-mongo
```

Check connectivity:

```bash
docker exec corridor-mongo mongosh --quiet --eval 'db.runCommand({ping: 1})'
```

From the repository root, copy the script:

```bash
docker cp portfolio-4-nosql/mongodb-demo.js corridor-mongo:/tmp/mongodb-demo.js
```

Execute it and capture the output:

```bash
docker exec corridor-mongo mongosh --quiet --file /tmp/mongodb-demo.js 2>&1 | tee portfolio-4-nosql/evidence/mongodb-demo.txt
```

Run against a database without the audit_events collection.
The script deliberately stops if that collection already exists.

For a separate reproduction, make a copy of the script and
change the database name in getSiblingDB() to a new unused name.
Preserve the original evidence database.

Unlike the PostgreSQL rollback demonstrations, this script
retains its six sample audit events.

## Evidence and limitations

Text output preserves the complete demonstration. Screenshots
show an embedded audit document and the execution/final counts.

The script contains assertions for selected expected outcomes.
If interrupted, earlier successful writes may remain; the whole
script is not wrapped in one transaction.

The demonstration does not implement:

- PostgreSQL-to-MongoDB synchronization.
- Customer authentication or tenant isolation.
- Enforced append-only audit permissions.
- A retention or archival policy.
- Replica-set failover or sharding.
- Production workload testing.

These limits distinguish the demonstrated document model
from a deployed audit service.

## References

MongoDB documentation:

- [Schema Validation](https://www.mongodb.com/docs/manual/core/schema-validation/)
- [JSON Schema Validation Tips, version 7.0](https://www.mongodb.com/docs/v7.0/core/schema-validation/specify-json-schema/json-schema-tips/)
- [Compound Indexes](https://www.mongodb.com/docs/manual/core/indexes/index-types/index-compound/create-compound-index/)
## Final review corrections

The demonstration script was corrected to use mongosh's direct
projection argument when excluding the internal `_id` field.

The duplicate-event test now supplies a fresh `_id` and checks
that rejection comes from the `event_id_unique` index.

A focused verification against the existing sample collection
confirmed that:

- All six original audit events were present.
- The projection excluded `_id`.
- The duplicate-test fixture existed.
- The event identifier index rejected a duplicate with a fresh `_id`.
- All six original audit events remained afterwards.

The verification output is saved in
`evidence/mongodb-review-check.txt`.

The original demonstration transcript and screenshots are retained
as evidence of the earlier run. The focused verification records
the subsequent corrections without rerunning the full demonstration.
