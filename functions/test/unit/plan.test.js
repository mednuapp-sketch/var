const assert = require("assert");
const P = require("../../plan_helpers.js");
const eq = assert.deepStrictEqual;
// month-end windows
eq(P.addMonthsKey("2026-01-31", 1), "2026-02-28");
eq(P.addMonthsKey("2028-01-31", 1), "2028-02-29");
eq(P.addMonthsKey("2026-01-31", 2), "2026-03-31");
eq(P.addMonthsKey("2026-11-30", 3), "2027-02-28");
eq(P.addMonthsKey("2026-12-15", 2), "2027-02-15");
const w = P.buildWindows("2026-01-31", 4);
eq(w.map((x) => [x.windowStart, x.windowEnd]), [
  ["2026-01-31", "2026-02-27"], ["2026-02-28", "2026-03-30"], ["2026-03-31", "2026-04-29"], ["2026-04-30", "2026-05-30"]]);
// contiguous, no gap/overlap
for (let i = 1; i < w.length; i++) eq(P.addDaysKey(w[i - 1].windowEnd, 1), w[i].windowStart);
eq(P.buildWindows("2026-03-10", 2).length, 2);
eq(P.addDaysKey("2026-12-31", 1), "2027-01-01");
assert.strictEqual(P.parseKey("2026-02-30"), null);
// IST date: 20:00 UTC Dec 31 is already Jan 1 in IST
eq(P.istDateKey(new Date("2026-12-31T20:00:00Z")), "2027-01-01");
// price = monthly x months + fee
eq(P.planTotal(999, 6, 30), 6024);
eq(P.planTotal(999, 2, 0), 1998);
eq(P.monthlyFromPrice("₹999/month"), 999);
eq(P.monthlyFromPrice("₹1,200/month"), 1200);
eq(P.monthlyFromPrice("free"), null);
eq(P.monthlyFromPrice(0), null);
// payout split with remainder on the last
eq(P.splitPayout(5994, 6), [999, 999, 999, 999, 999, 999]);
eq(P.splitPayout(1000, 3), [333.33, 333.33, 333.34]);
eq(P.splitPayout(100, 6).reduce((a, b) => Math.round((a + b) * 100) / 100, 0), 100);
eq(P.splitPayout(0.05, 2), [0.02, 0.03]);
for (const m of [2, 4, 6]) for (const t of [1, 99.99, 5994, 7777.77]) {
  const s = P.splitPayout(t, m); assert.strictEqual(Math.round(s.reduce((a, b) => a + Math.round(b * 100), 0)), Math.round(t * 100));
}
// credit pick
const cr = [{ index: 1, status: "booked", windowStart: "2026-01-01", windowEnd: "2026-01-31" },
  { index: 2, status: "available", windowStart: "2026-02-01", windowEnd: "2026-02-28" },
  { index: 3, status: "available", windowStart: "2026-03-01", windowEnd: "2026-03-31" }];
eq(P.pickCredit(cr, "2026-02-10").index, 2);
eq(P.pickCredit(cr, "2026-01-10"), null);       // month 1 already booked
eq(P.pickCredit(cr, "2026-04-10"), null);
eq(P.pickCredit(cr, "2026-03-05", 2), null);    // pinned credit window mismatch
eq(P.pickCredit(cr, "2026-03-05", 3).index, 3);
// refund: base only, fee non-refundable
eq(P.planRefundAmount({ baseTotal: 5994, platformFee: 30, paidAmount: 6024 }), 5994);
eq(P.planRefundAmount({ baseTotal: 5994, platformFee: 30, paidAmount: 5000 }), 4970); // coupon: never more than paid-fee
eq(P.planRefundAmount({ baseTotal: 100, platformFee: 30, paidAmount: 20 }), 0);
eq(P.unusedShare([999, 999, 999], cr, ["available"]), 1998);
// contract constants
eq(P.PLAN_MONTHS, [2, 4, 6]);
console.log("plan_test OK");

// manual full refund: share reversal decision
{
  const d = P.planShareReversalDecision([
    { id: "a", exists: true, status: "completed", settlementStatus: "eligible", providerId: "d1", providerAmount: 999 },
    { id: "b", exists: true, status: "completed", settlementStatus: "paid", providerId: "d1", providerAmount: 999 },
    { id: "c", exists: true, status: "completed", settlementStatus: "pending_review", providerId: "d1", providerAmount: 999 },
    { id: "d", exists: false },
    { id: "e", exists: true, status: "refunded", settlementStatus: "failed", providerId: "d1", providerAmount: 999 },
    { id: "f", exists: true, status: "completed", settlementStatus: "eligible", shareReversed: true, providerId: "d1", providerAmount: 999 },
    { id: "g", exists: true, status: "completed", settlementStatus: "eligible", providerId: "d1", providerAmount: 0 },
  ]);
  eq(d.reverse, [{ id: "a", providerId: "d1", amount: 999 }]);
  eq(d.skipped.map((x) => [x.id, x.reason]), [["b", "paid"], ["c", "pending_review"]]);
  eq(P.planShareReversalDecision(null), { reverse: [], skipped: [] });
  // 2 of 6 completed, both still eligible -> both reversed
  const two = P.planShareReversalDecision([1, 2].map((i) => ({ id: "s" + i, exists: true, status: "completed", settlementStatus: "eligible", providerId: "d1", providerAmount: 999 })));
  eq(two.reverse.length, 2); eq(two.skipped.length, 0);
}
console.log("plan reversal OK");
