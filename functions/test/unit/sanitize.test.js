const assert = require("assert");
const P = require("../../price_helpers.js");
const evil = { status: "completed", paymentId: "x", paymentStatus: "paid", settlementStatus: "paid", amountDue: 1, fareFinal: 1,
  lockedFare: 1, lockedRate: 1, providerReleasedAt: 1, rescheduledAt: 1, rescheduledBy: 1, cancelledBy: 1, cancelReason: 1,
  completedAt: 1, completedBy: 1, acceptedAt: 1, declinedBy: 1, assignedTo: "u", assignedToName: "n", doctorJoinedAt: 1,
  settlementDeferredUntil: 1, doctorId: "d1", date: "2026-01-01", patientName: "P", planType: "x", physiotherapistId: "p", items: [1], fee: 5 };
const keep = ["doctorId","date","patientName","planType","physiotherapistId","items","fee"];
for (const [col, st] of Object.entries(P.BOOKING_INITIAL_STATUS)) {
  const o = P.sanitizeBookingData(col, evil);
  for (const f of P.BOOKING_CLIENT_FORBIDDEN_FIELDS) {
    if (f === "status") assert.strictEqual(o.status, st === null ? undefined : st, col);
    else if (f === "assignedTo" && col === "service_requests") assert.strictEqual(o.assignedTo, null);
    else assert.ok(!(f in o), col + " " + f);
  }
  for (const k of keep) assert.deepStrictEqual(o[k], evil[k]);
}
assert.strictEqual(evil.status, "completed"); // no mutation
assert.deepStrictEqual(P.sanitizeBookingData("orders", null), {});
console.log("sanitize_test OK");
