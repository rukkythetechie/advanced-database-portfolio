// Corridor Pay: Portfolio 4 MongoDB demonstration
// Run once against corridorpay_p4.
// Standalone sample events; not a PostgreSQL synchronization.

const p4 = db.getSiblingDB("corridorpay_p4");

function check(condition, message) {
  if (!condition) throw new Error("TEST FAILED: " + message);
  print("PASS: " + message);
}

function show(title, value) {
  print("\n" + title);
  printjson(value);
}

// Stop instead of overwriting an earlier demonstration.
if (p4.getCollectionNames().includes("audit_events")) {
  throw new Error(
    "audit_events already exists. Inspect the existing run before continuing."
  );
}

p4.createCollection("audit_events", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "event_id", "schema_version", "source", "business_id",
        "actor", "action", "entity", "outcome", "occurred_at", "details"
      ],
      properties: {
        event_id: { bsonType: "string", minLength: 1 },
        schema_version: { enum: [1] },
        source: { enum: ["standalone_sample"] },
        business_id: { bsonType: "int" },
        actor: {
          bsonType: "object",
          required: ["type", "user_id"],
          oneOf: [
            {
              properties: {
                type: { enum: ["user"] },
                user_id: { bsonType: "int" }
              }
            },
            {
              properties: {
                type: { enum: ["system"] },
                user_id: { bsonType: "null" }
              }
            }
          ]
        },
        action: { bsonType: "string", minLength: 1 },
        entity: {
          bsonType: "object",
          required: ["type", "id"],
          properties: {
            type: { bsonType: "string", minLength: 1 },
            id: { bsonType: "string", minLength: 1 }
          }
        },
        outcome: { enum: ["success", "failure"] },
        occurred_at: { bsonType: "date" },
        details: { bsonType: "object" }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

const events = p4.audit_events;

events.createIndex(
  { event_id: 1 },
  { unique: true, name: "event_id_unique" }
);
events.createIndex(
  { business_id: 1, occurred_at: -1, event_id: -1 },
  { name: "business_recent_events" }
);
events.createIndex(
  { outcome: 1, occurred_at: -1 },
  { name: "outcome_recent_events" }
);

function event(id, business, action, entityType, entityId,
               outcome, time, details, system = false) {
  return {
    event_id: id,
    schema_version: NumberInt(1),
    source: "standalone_sample",
    business_id: NumberInt(business),
    actor: {
      type: system ? "system" : "user",
      user_id: system ? null : NumberInt(business + 1)
    },
    action: action,
    entity: { type: entityType, id: entityId },
    outcome: outcome,
    occurred_at: ISODate(time),
    details: details
  };
}

const samples = [
  event(
    "P4-001", 1001, "wallet_funding", "wallet", "sample-wallet-ngn",
    "success", "2026-10-26T10:00:00Z",
    { currency: "NGN", amount: NumberDecimal("100000.00") }
  ),
  event(
    "P4-002", 1001, "process_payment", "payment", "sample-payment-a",
    "success", "2026-10-26T10:05:00Z",
    {
      currency: "NGN", amount: NumberDecimal("70000.00"),
      ledger_reference: "sample-posting-a"
    }
  ),
  event(
    "P4-003", 1001, "process_payment", "payment", "sample-payment-b",
    "failure", "2026-10-26T10:06:00Z",
    {
      currency: "NGN", amount: NumberDecimal("70000.00"),
      reason: "insufficient_funds"
    }
  ),
  event(
    "P4-004", 1001, "execute_fx_quote", "fx_conversion", "sample-fx-1",
    "success", "2026-10-26T10:10:00Z",
    {
      source_currency: "NGN", source_amount: NumberDecimal("160000.00"),
      target_currency: "USD", target_amount: NumberDecimal("120.34"),
      quote_reference: "sample-quote-1"
    }
  ),
  event(
    "P4-005", 1001, "execute_fx_quote", "fx_quote", "sample-quote-2",
    "failure", "2026-10-26T10:12:00Z",
    { reason: "quote_expired", retry_allowed_with_new_quote: true },
    true
  ),
  event(
    "P4-006", 2001, "wallet_funding", "wallet", "sample-wallet-cad",
    "success", "2026-10-26T10:15:00Z",
    { currency: "CAD", amount: NumberDecimal("500.00") }
  )
];

events.insertMany(samples);
check(events.countDocuments({}) === 6, "six sample audit events inserted");

show("EXAMPLE EMBEDDED AUDIT DOCUMENT", events.findOne(
  { event_id: "P4-004" },
  { projection: { _id: 0 } }
));

// Query 1: latest three events for one business.
const recent = events.find(
  { business_id: NumberInt(1001) },
  { _id: 0, event_id: 1, action: 1, outcome: 1, occurred_at: 1 }
).sort({ occurred_at: -1, event_id: -1 }).limit(3).toArray();

check(
  recent.map(x => x.event_id).join(",") === "P4-005,P4-004,P4-003",
  "recent business events returned in the expected order"
);
show("QUERY 1: RECENT BUSINESS EVENTS", recent);

// Query 2: failures and their nested reasons.
const failures = events.find(
  { outcome: "failure" },
  { _id: 0, event_id: 1, action: 1, "details.reason": 1 }
).sort({ event_id: 1 }).toArray();

check(failures.length === 2, "two failed events found");
show("QUERY 2: FAILED EVENTS", failures);

// Query 3: aggregate counts by action and outcome.
const summary = events.aggregate([
  {
    $group: {
      _id: { action: "$action", outcome: "$outcome" },
      event_count: { $sum: 1 }
    }
  },
  { $sort: { "_id.action": 1, "_id.outcome": 1 } }
]).toArray();

check(
  summary.reduce((total, row) => total + row.event_count, 0) === 6,
  "aggregation accounts for all six events"
);
show("QUERY 3: COUNTS BY ACTION AND OUTCOME", summary);

// Invalid audit outcome must fail schema validation.
let validationRejected = false;
try {
  events.insertOne({
    ...samples[0],
    event_id: "P4-INVALID",
    outcome: "invalid"
  });
} catch (error) {
  if (error.code !== 121) throw error;
  validationRejected = true;
}
check(validationRejected, "invalid audit outcome rejected");

// Duplicate event identifiers must fail the unique index.
let duplicateRejected = false;
try {
  events.insertOne({ ...samples[0] });
} catch (error) {
  if (error.code !== 11000) throw error;
  duplicateRejected = true;
}
check(duplicateRejected, "duplicate event identifier rejected");

// Demonstrate update and delete on a review note,
// keeping the original audit events unchanged.
const notes = p4.audit_review_notes;

notes.insertOne({
  note_id: "P4-NOTE-TEMP",
  event_id: "P4-003",
  reviewed: false,
  note: "Check the insufficient-funds rejection"
});

const updated = notes.updateOne(
  { note_id: "P4-NOTE-TEMP" },
  { $set: { reviewed: true, note: "Reviewed sample rejection" } }
);
check(updated.modifiedCount === 1, "review note updated");

show("CRUD: UPDATED REVIEW NOTE", notes.findOne(
  { note_id: "P4-NOTE-TEMP" },
  { projection: { _id: 0 } }
));

const removed = notes.deleteOne({ note_id: "P4-NOTE-TEMP" });
check(removed.deletedCount === 1, "temporary review note deleted");
check(events.countDocuments({}) === 6, "audit events retained unchanged");

// Inspect index use without claiming a performance improvement.
const plan = events.find(
  { business_id: NumberInt(1001) }
).sort({ occurred_at: -1, event_id: -1 })
 .limit(3)
 .explain("executionStats");

show("RECENT-EVENT QUERY PLAN", plan.queryPlanner.winningPlan);
show("QUERY EXECUTION COUNTS", {
  returned: plan.executionStats.nReturned,
  documents_examined: plan.executionStats.totalDocsExamined,
  index_keys_examined: plan.executionStats.totalKeysExamined
});

show("FINAL COLLECTION COUNTS", {
  audit_events: events.countDocuments({}),
  review_notes: notes.countDocuments({})
});

show("AUDIT INDEXES", events.getIndexes());
print("\nPortfolio 4 MongoDB demonstration completed.");