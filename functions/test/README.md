# Server-logic test harness

Run: `node functions/test/run_all.js` (from repo root; no extra dependencies, Node 20+).

How it works: `harness.js` sets `MEDNU_TEST=1`, intercepts `require` of
`firebase-admin/{firestore,messaging,auth,app}` and `razorpay` (via `Module._load`)
and loads the real `functions/index.js`. `fake_firestore.js` is an in-memory
Firestore (get/set/merge/update with dotted paths/create/delete/batch, `FieldValue`,
`Timestamp`, simple `where/orderBy/limit`, `runTransaction` that throws if a read
follows a write). Internal helpers come from `index.js` `__testing` (only when
`MEDNU_TEST=1`).

Covered: `_refundPayment` (razorpay / wallet / split with walletLegs, gateway
failure + already-refunded, idempotency, eligible reversal, paid -> recoverableDebt,
plan reversal + recoverableDebt, partial), settlement netting (`_createSettlementForProvider`,
`_runSettlementQueueOnce`, `markSettlementPaid`), `_creditTestEarningsTx`,
`_transitionPaymentToEligible`, `_computeProviderSplit`, `markTripWrittenOff`,
`_completePlanConsultation`.

Not covered: `captureTripPayment` refusal after write-off and the other onCall
capture paths (need signed Razorpay payloads + App Check wiring), Firestore
rules, query indexes, real concurrency/contention retries (the fake runs
transactions serially without retry), push delivery.
