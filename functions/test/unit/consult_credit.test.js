const assert = require("assert");
const H = require("../../price_helpers.js");
const ts = (ms) => ({ toMillis: () => ms });
const D = "doc1", P = "pat1";
const c = (b, a) => H.consultationCreditDecision(b, { doctorId: D, patientId: P, ...a }).credit;
const T0 = 1_000_000;
// doctor 'active' ok
assert.strictEqual(c({ status: "active" }, { status: "ended" }), true);
assert.strictEqual(c({ status: "ongoing" }, { status: "ended", doctorJoinedAt: ts(1) }), true);
// 'active' write failed, doctor ends after 10 min -> credited
assert.strictEqual(c({ status: "ongoing" }, { status: "ended", endedBy: D, ringingAt: ts(T0), endedAt: ts(T0 + 600000) }), true);
// patient ends alone -> not credited
assert.strictEqual(c({ status: "ongoing" }, { status: "ended", ringingAt: ts(T0), endedAt: ts(T0 + 600000) }), false);
assert.strictEqual(c({ status: "ongoing" }, { status: "ended", endedBy: P, ringingAt: ts(T0), endedAt: ts(T0 + 600000) }), false);
// doctor ended too quickly
assert.strictEqual(c({ status: "ongoing" }, { status: "ended", endedBy: D, ringingAt: ts(T0), endedAt: ts(T0 + 10000) }), false);
assert.strictEqual(c({ status: "ongoing" }, { status: "ended", endedBy: D, ringingAt: ts(T0), endedAt: ts(T0 + 30000) }), true);
// no usable timestamps -> doctor-ended only
assert.strictEqual(c({ status: "ongoing" }, { status: "ended", endedBy: D }), true);
// acceptedAt fallback
assert.strictEqual(c({ status: "ongoing" }, { status: "ended", endedBy: D, acceptedAt: ts(T0), endedAt: ts(T0 + 5000) }), false);
// pending -> ended by doctor does not count (never accepted)
assert.strictEqual(c({ status: "pending" }, { status: "ended", endedBy: D }), false);
// missing doctorId / endedBy undefined can't match
assert.strictEqual(H.consultationCreditDecision({ status: "ongoing" }, { status: "ended" }).credit, false);
assert.strictEqual(H.consultationCreditDecision({ status: "ongoing" }, { status: "ended", endedBy: undefined }).credit, false);
// Date / seconds forms
assert.strictEqual(c({ status: "ongoing" }, { status: "ended", endedBy: D, ringingAt: new Date(T0), endedAt: new Date(T0 + 1000) }), false);
console.log("consult_credit_test passed");
