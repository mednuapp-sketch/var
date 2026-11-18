"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const H = require("./harness");
const { T, state } = H;
const { Timestamp } = H;

const silence = () => { const l = console.log, e = console.error, w = console.warn; console.log = console.error = console.warn = () => {}; return () => { console.log = l; console.error = e; console.warn = w; }; };
let restore;
test.beforeEach(() => { H.reset(); restore = silence(); });
test.afterEach(() => restore());

const ledgerBy = (db, pred) => db.list("wallet_ledger").filter(pred);
const rejects = async (fn, code) => {
  await assert.rejects(fn, (e) => { assert.equal(e.code, code, `expected ${code}, got ${e.code}: ${e.message}`); return true; });
};

function payment(over = {}) {
  return {
    paymentId: "pay1", patientId: "u1", providerId: "p1", serviceType: "ambulance",
    paidAmount: 500, walletPortionAmount: 0, paymentMethod: "razorpay", razorpayPaymentId: "rzp_1",
    platformFee: 50, commission: 0, providerAmount: 450, status: "completed", settlementStatus: "pending",
    ...over,
  };
}

// ── _refundPayment ────────────────────────────────────────────────────────────
test("refund: razorpay-only goes to gateway, idempotent on second call", async () => {
  const db = H.db;
  db.seed("payments/pay1", payment());
  const r = await T._refundPayment(db, "pay1", "test", "admin1");
  assert.equal(r.status, "completed");
  assert.deepEqual(state.razorpayCalls.map((c) => [c.fn, c.body.amount]), [["refund", 50000]]);
  const p = db.peek("payments/pay1");
  assert.equal(p.status, "refunded"); assert.equal(p.refundGatewayDone, true);
  assert.equal(db.list("refunds").length, 1);
  assert.equal(db.peek("users/u1"), undefined, "no wallet credit for gateway-only");
  assert.ok(ledgerBy(db, (l) => l.uid === "platform" && l.category === "refund").length === 1);
  await rejects(() => T._refundPayment(db, "pay1", "again", "admin1"), "failed-precondition");
  assert.equal(state.razorpayCalls.length, 1);
  assert.equal(db.list("refunds").length, 1);
});

test("refund: wallet-only credits main wallet once", async () => {
  const db = H.db;
  db.seed("users/u1", { walletBalance: 100 });
  db.seed("payments/pay1", payment({ paymentMethod: "wallet", razorpayPaymentId: null, paidAmount: 300 }));
  await T._refundPayment(db, "pay1", "t", "admin1");
  assert.equal(db.peek("users/u1").walletBalance, 400);
  assert.equal(state.razorpayCalls.length, 0);
  assert.ok(db.peek("wallet_ledger/refund:pay1:wallet"));
  await rejects(() => T._refundPayment(db, "pay1", "t", "admin1"), "failed-precondition");
  assert.equal(db.peek("users/u1").walletBalance, 400);
});

test("refund: split payment with walletLegs refunds each leg to its own source", async () => {
  const db = H.db;
  db.seed("users/u1", { walletBalance: 10, mednuMoneyBalance: 20 });
  db.seed("payments/pay1", payment({
    paidAmount: 1000, walletPortionAmount: 400, walletLegs: { main: 100, mednuMoney: 300 }, providerAmount: 950, platformFee: 50,
  }));
  await T._refundPayment(db, "pay1", "t", "admin1");
  assert.equal(state.razorpayCalls[0].body.amount, 60000);
  const u = db.peek("users/u1");
  assert.equal(u.walletBalance, 110); assert.equal(u.mednuMoneyBalance, 320);
  assert.ok(db.peek("wallet_ledger/refund:pay1:wallet-main"));
  assert.ok(db.peek("wallet_ledger/refund:pay1:wallet-mednu"));
});

test("refund: gateway failure leaves payment untouched", async () => {
  const db = H.db;
  db.seed("payments/pay1", payment());
  state.razorpayRefundImpl = async () => { throw { error: { description: "boom" } }; };
  await rejects(() => T._refundPayment(db, "pay1", "t", "admin1"), "internal");
  assert.equal(db.peek("payments/pay1").status, "completed");
  assert.equal(db.list("refunds").length, 0);
});

test("refund: gateway 'already refunded' error is treated as done", async () => {
  const db = H.db;
  db.seed("payments/pay1", payment());
  state.razorpayRefundImpl = async () => { throw { error: { description: "The payment has been fully refunded already" } }; };
  await T._refundPayment(db, "pay1", "t", "admin1");
  assert.equal(db.peek("payments/pay1").status, "refunded");
});

test("refund: eligible provider earnings are reversed from pendingEarnings", async () => {
  const db = H.db;
  db.seed("provider_wallets/p1", { pendingEarnings: 450 });
  db.seed("payments/pay1", payment({ settlementStatus: "eligible" }));
  await T._refundPayment(db, "pay1", "t", "admin1");
  assert.equal(db.peek("provider_wallets/p1").pendingEarnings, 0);
  assert.equal(db.peek("provider_wallets/p1").recoverableDebt, undefined);
  assert.equal(ledgerBy(db, (l) => l.category === "settlement_reversal").length, 1);
});

test("refund: pending_review payment is refused", async () => {
  const db = H.db;
  db.seed("payments/pay1", payment({ settlementStatus: "pending_review", settlementId: "s1" }));
  await rejects(() => T._refundPayment(db, "pay1", "t", "admin1"), "failed-precondition");
  assert.equal(state.razorpayCalls.length, 0);
});

test("refund: already-paid provider payment becomes recoverableDebt (once)", async () => {
  const db = H.db;
  db.seed("provider_wallets/p1", { pendingEarnings: 0, paidThisMonth: 450, recoverableDebt: 100 });
  db.seed("payments/pay1", payment({ settlementStatus: "paid" }));
  const r = await T._refundPayment(db, "pay1", "t", "admin1");
  assert.equal(r.status, "recovery_pending");
  assert.equal(db.peek("provider_wallets/p1").recoverableDebt, 550);
  assert.equal(db.peek("payments/pay1").recoveryRecorded, true);
  const led = db.peek("wallet_ledger/plan_recovery:pay1");
  assert.equal(led.category, "recovery_due"); assert.equal(led.type, "debit"); assert.equal(led.amount, 450);
  assert.equal(led.title, "Recovery of refunded service");
  await rejects(() => T._refundPayment(db, "pay1", "t", "admin1"), "failed-precondition");
  assert.equal(db.peek("provider_wallets/p1").recoverableDebt, 550);
  await new Promise((r) => setImmediate(r));
  assert.ok(db.list("admin_alerts").some((a) => a.type === "refund_recovery_pending"));
});

function seedPlan(db, { childStates }) {
  db.seed("payments/planpay", payment({
    paymentId: "planpay", paidAmount: 3050, providerAmount: 3000, platformFee: 50, planSubscriptionId: "sub1", planMonths: 3,
    serviceType: "nutrition", settlementStatus: "plan_hold", razorpayPaymentId: "rzp_plan",
  }));
  childStates.forEach((st, i) => {
    if (!st) return;
    db.seed(`payments/planshare:sub1:${i + 1}`, {
      paymentId: `planshare:sub1:${i + 1}`, providerId: "d1", providerAmount: 1000, status: "completed", settlementStatus: st,
    });
  });
}

test("refund: plan payment reverses eligible shares and records settled shares as recoverableDebt", async () => {
  const db = H.db;
  db.seed("provider_wallets/d1", { pendingEarnings: 1000 });
  seedPlan(db, { childStates: ["eligible", "paid", null] });
  // share 2 (paid) + a pending_review share 3 to cover both skip reasons
  db.seed("payments/planshare:sub1:3", { providerId: "d1", providerAmount: 1000, status: "completed", settlementStatus: "pending_review" });
  await T._refundPayment(db, "planpay", "t", "admin1");
  const w = db.peek("provider_wallets/d1");
  assert.equal(w.pendingEarnings, 0, "eligible share reversed");
  assert.equal(w.recoverableDebt, 2000, "paid + pending_review shares recorded as debt");
  assert.equal(db.peek("payments/planshare:sub1:1").shareReversed, true);
  assert.equal(db.peek("payments/planshare:sub1:2").recoveryRecorded, true);
  assert.equal(db.peek("payments/planshare:sub1:3").recoveryRecorded, true);
  assert.equal(db.peek("wallet_ledger/plan_recovery:planshare:sub1:2").category, "recovery_due");
  assert.equal(db.peek("payments/planpay").planShareReversal.skipped, 2);
  await new Promise((r) => setImmediate(r));
  assert.ok(db.list("admin_alerts").some((a) => a.type === "plan_refund_reversal_skipped"));
  await rejects(() => T._refundPayment(db, "planpay", "t", "admin1"), "failed-precondition");
  assert.equal(db.peek("provider_wallets/d1").recoverableDebt, 2000);
});

test("refund: partial refund never records recovery", async () => {
  const db = H.db;
  db.seed("provider_wallets/p1", {});
  db.seed("payments/pay1", payment({ settlementStatus: "paid" }));
  await T._refundPayment(db, "pay1", "t", "admin1", { refundAmount: 200, nonRefundableFee: 50 });
  assert.equal(db.peek("provider_wallets/p1").recoverableDebt, undefined);
});

// ── settlement netting ───────────────────────────────────────────────────────
async function eligiblePayments(db, amounts, providerId = "p1") {
  amounts.forEach((a, i) => db.seed(`payments/e${i}`, { providerId, providerAmount: a, settlementStatus: "eligible", status: "completed" }));
}

test("settlement: debt Rs999 netted off Rs3000 -> payout Rs2001, debt cleared, pending accounting stays right", async () => {
  const db = H.db;
  db.seed("provider_wallets/p1", { pendingEarnings: 3000, recoverableDebt: 999, paidThisMonth: 0 });
  db.seed("admins/a1", { role: "finance" });
  await eligiblePayments(db, [1000, 2000]);
  const created = await T._runSettlementQueueOnce(db);
  assert.equal(created.length, 1);
  const s = db.list("settlements")[0];
  assert.equal(s.totalAmount, 2001); assert.equal(s.grossAmount, 3000); assert.equal(s.recoveryApplied, 999);
  assert.equal(db.peek("provider_wallets/p1").recoverableDebt, 0);
  assert.ok(db.peek(`wallet_ledger/recovery_applied:${s.id}`));
  db.seed(`settlements/${s.id}`, { ...db.peek(`settlements/${s.id}`), status: "approved" });
  await H.index.markSettlementPaid.run({ auth: { uid: "a1" }, data: { settlementId: s.id, payoutReference: "UTR1" } });
  const w = db.peek("provider_wallets/p1");
  assert.equal(w.pendingEarnings, 0, "gross leaves pending");
  assert.equal(w.paidThisMonth, 2001, "net is what was paid");
  assert.equal(ledgerBy(db, (l) => l.category === "provider_settlement")[0].amount, 2001);
  // second call is a no-op
  await H.index.markSettlementPaid.run({ auth: { uid: "a1" }, data: { settlementId: s.id } });
  assert.equal(db.peek("provider_wallets/p1").paidThisMonth, 2001);
});

test("settlement: debt larger than total -> payout 0, remainder stays as debt", async () => {
  const db = H.db;
  db.seed("provider_wallets/p1", { pendingEarnings: 500, recoverableDebt: 800 });
  await eligiblePayments(db, [500]);
  await T._runSettlementQueueOnce(db);
  const s = db.list("settlements")[0];
  assert.equal(s.totalAmount, 0); assert.equal(s.recoveryApplied, 500);
  assert.equal(db.peek("provider_wallets/p1").recoverableDebt, 300);
});

test("settlement: no debt -> unchanged behaviour, no recovery ledger", async () => {
  const db = H.db;
  db.seed("provider_wallets/p1", { pendingEarnings: 700 });
  await eligiblePayments(db, [700]);
  await T._runSettlementQueueOnce(db);
  const s = db.list("settlements")[0];
  assert.equal(s.totalAmount, 700); assert.equal(s.recoveryApplied, 0);
  assert.equal(ledgerBy(db, (l) => l.category === "recovery_applied").length, 0);
});

test("settlement: legacy settlement (no grossAmount) pays as before", async () => {
  const db = H.db;
  db.seed("admins/a1", { role: "director" });
  db.seed("provider_wallets/p1", { pendingEarnings: 400, paidThisMonth: 10 });
  db.seed("settlements/legacy", { providerId: "p1", paymentIds: [], totalAmount: 400, status: "approved" });
  await H.index.markSettlementPaid.run({ auth: { uid: "a1" }, data: { settlementId: "legacy" } });
  const w = db.peek("provider_wallets/p1");
  assert.equal(w.pendingEarnings, 0); assert.equal(w.paidThisMonth, 410);
});

// ── _creditTestEarningsTx ────────────────────────────────────────────────────
const cfgOn = (db, over = {}) => db.seed("settlement_config/global", { testCreditEnabled: true, testCreditEnabledAt: Timestamp.now(), ...over });
const credit = (db, src, extra = {}) => db.runTransaction((tx) => T._creditTestEarningsTx(db, tx, {
  sourceSnap: { data: () => src }, sourceCollection: "appointments", sourceId: "a1", providerId: "p1", serviceType: "consultation", ...extra,
}));

test("test credit: flag off / missing config -> no credit", async () => {
  const db = H.db;
  assert.equal(await credit(db, { fee: 300 }), false);
  db.seed("settlement_config/global", { testCreditEnabled: false, testCreditEnabledAt: Timestamp.now() });
  assert.equal(await credit(db, { fee: 300 }), false);
  assert.equal(db.peek("provider_wallets/p1"), undefined);
});

test("test credit: expired (>7d) or no timestamp -> no credit", async () => {
  const db = H.db;
  cfgOn(db, { testCreditEnabledAt: Timestamp.fromMillis(Date.now() - 8 * 86400000) });
  assert.equal(await credit(db, { fee: 300 }), false);
  db.seed("settlement_config/global", { testCreditEnabled: true });
  assert.equal(await credit(db, { fee: 300 }), false);
});

test("test credit: requirePayment on -> no credit", async () => {
  const db = H.db;
  cfgOn(db); db.seed("app_config/payments", { requirePayment: true });
  assert.equal(await credit(db, { fee: 300 }), false);
});

test("test credit: amount extraction, ambulance fareFinal, no amount, idempotent", async () => {
  const db = H.db;
  cfgOn(db);
  assert.equal(await credit(db, { fee: 300, amount: 250 }), true, "amount wins over fee");
  assert.equal(db.peek("provider_wallets/p1").pendingEarnings, 250);
  const led = db.peek("wallet_ledger/test:appointments:a1");
  assert.equal(led.isTest, true); assert.equal(led.amount, 250);
  assert.equal(await credit(db, { amount: 250 }), false, "idempotent");
  assert.equal(db.peek("provider_wallets/p1").pendingEarnings, 250);
  assert.equal(await credit(db, { amount: 600, fareFinal: 450 }, { sourceId: "r1", serviceType: "ambulance" }), true);
  assert.equal(db.peek("wallet_ledger/test:appointments:r1").amount, 450);
  assert.equal(await credit(db, { nothing: 1 }, { sourceId: "z" }), false);
  assert.equal(db.peek("wallet_ledger/test:appointments:z"), undefined);
});

// ── _transitionPaymentToEligible ─────────────────────────────────────────────
test("transitionToEligible: pending payment -> eligible, wallet credited once", async () => {
  const db = H.db;
  db.seed("appointments/a1", { paymentId: "pay1" });
  db.seed("payments/pay1", payment({ settlementStatus: "pending" }));
  const args = { sourceCollection: "appointments", sourceId: "a1", providerId: "p1", serviceType: "consultation" };
  await T._transitionPaymentToEligible(db, args);
  assert.equal(db.peek("payments/pay1").settlementStatus, "eligible");
  assert.equal(db.peek("provider_wallets/p1").pendingEarnings, 450);
  await T._transitionPaymentToEligible(db, args);
  assert.equal(db.peek("provider_wallets/p1").pendingEarnings, 450, "second run is a no-op");
  assert.equal(ledgerBy(db, (l) => l.source === "payment:pay1:eligible").length, 1);
});

test("transitionToEligible: legacy payment (no platformFee) re-split fee-only", async () => {
  const db = H.db;
  db.seed("app_config/platform_fee", { enabled: true, defaultAmount: 40 });
  db.seed("appointments/a1", { paymentId: "pay1" });
  const p = payment({ settlementStatus: "pending", commissionBase: 500, originalAmount: 500, providerAmount: 400 });
  delete p.platformFee;
  db.seed("payments/pay1", p);
  await T._transitionPaymentToEligible(db, { sourceCollection: "appointments", sourceId: "a1", providerId: "p1", serviceType: "consultation" });
  assert.equal(db.peek("payments/pay1").providerAmount, 460);
  assert.equal(db.peek("provider_wallets/p1").pendingEarnings, 460);
});

test("transitionToEligible: not_required booking uses test credit; missing ids no-op", async () => {
  const db = H.db;
  cfgOn(db);
  db.seed("appointments/a1", { paymentStatus: "not_required", fee: 200 });
  await T._transitionPaymentToEligible(db, { sourceCollection: "appointments", sourceId: "a1", providerId: "p1", serviceType: "consultation" });
  assert.equal(db.peek("provider_wallets/p1").pendingEarnings, 200);
  await T._transitionPaymentToEligible(db, { sourceCollection: "appointments", sourceId: "a1" });
});

// ── _computeProviderSplit ────────────────────────────────────────────────────
test("computeProviderSplit: fee-only, capped, provider override", async () => {
  const snap = (d) => ({ exists: !!d, data: () => d });
  assert.deepEqual(T._computeProviderSplit(snap(null), "x", 500, 500, "p"), { commission: 0, platformFee: 0, providerAmount: 500, baseAmount: 500 });
  const cfg = snap({ enabled: true, defaultAmount: 40, services: { ambulance: 60 }, providers: { pX: 10 } });
  assert.equal(T._computeProviderSplit(cfg, "ambulance", 500, 500, "p").platformFee, 60);
  assert.equal(T._computeProviderSplit(cfg, "ambulance", 500, 500, "pX").platformFee, 10);
  const r = T._computeProviderSplit(cfg, "other", 20, 20, "p");
  assert.equal(r.platformFee, 20); assert.equal(r.providerAmount, 0);
  const rr = T._computeProviderSplit(cfg, "other", 500, 1000, "p");
  assert.equal(rr.providerAmount, 460); assert.equal(rr.baseAmount, 960);
});

// ── markTripWrittenOff ───────────────────────────────────────────────────────
test("markTripWrittenOff: credits driver, platform expense, idempotent, non-director refused", async () => {
  const db = H.db;
  db.seed("admins/dir", { role: "director" }); db.seed("admins/fin", { role: "finance" });
  db.seed("service_requests/r1", { type: "ambulance", paymentStatus: "payment_due", assignedTo: "drv1", fareFinal: 750, patientId: "u1" });
  await rejects(() => H.index.markTripWrittenOff.run({ auth: { uid: "fin" }, data: { requestId: "r1" } }), "permission-denied");
  await H.index.markTripWrittenOff.run({ auth: { uid: "dir" }, data: { requestId: "r1", reason: "unreachable" } });
  const sr = db.peek("service_requests/r1");
  assert.equal(sr.paymentStatus, "written_off");
  const pid = sr.writeOffPaymentId;
  const p = db.peek(`payments/${pid}`);
  assert.equal(p.isWriteOff, true); assert.equal(p.settlementStatus, "eligible"); assert.equal(p.providerAmount, 750);
  assert.equal(db.peek("provider_wallets/drv1").pendingEarnings, 750);
  assert.equal(ledgerBy(db, (l) => l.category === "writeoff_expense" && l.uid === "platform" && l.amount === 750).length, 1);
  assert.equal(ledgerBy(db, (l) => l.uid === "drv1" && l.category === "settlement_pending").length, 1);
  assert.ok(db.peek("ambulance_transactions/r1"));
  // replay: trip no longer payment_due -> refused, nothing doubled
  await rejects(() => H.index.markTripWrittenOff.run({ auth: { uid: "dir" }, data: { requestId: "r1" } }), "failed-precondition");
  assert.equal(db.peek("provider_wallets/drv1").pendingEarnings, 750);
  // a write-off payment can't be refunded
  await rejects(() => T._refundPayment(db, pid, "t", "dir"), "failed-precondition");
});

test("markTripWrittenOff: crash-replay with existing write-off payment does not double credit", async () => {
  const db = H.db;
  db.seed("admins/dir", { role: "director" });
  db.seed("service_requests/r2", { type: "ambulance", paymentStatus: "payment_due", assignedTo: "drv1", fareFinal: 300 });
  db.seed("payments/writeoff:r2", { providerAmount: 300, isWriteOff: true, settlementStatus: "eligible" });
  db.seed("provider_wallets/drv1", { pendingEarnings: 300 });
  await H.index.markTripWrittenOff.run({ auth: { uid: "dir" }, data: { requestId: "r2" } });
  assert.equal(db.peek("provider_wallets/drv1").pendingEarnings, 300);
  assert.equal(ledgerBy(db, (l) => l.category === "writeoff_expense").length, 0);
});

// ── plan payout ──────────────────────────────────────────────────────────────
function planSetup(db, { months = 3, providerAmount = 1000, refunded = false } = {}) {
  db.seed("payments/pp", { patientId: "u1", providerAmount, status: refunded ? "refunded" : "completed" });
  const consultations = [];
  for (let i = 1; i <= months; i++) consultations.push({ index: i, status: i === 1 ? "booked" : "available", ...(i === 1 ? { appointmentId: "ap1" } : {}) });
  db.seed("nutrition_subscriptions/sub1", { nutritionistId: "d1", paymentId: "pp", months, status: "active", consultations });
}

test("plan completion: equal split with remainder on last share, exactly once", async () => {
  const db = H.db;
  planSetup(db);
  await T._completePlanConsultation(db, "ap1", { subscriptionId: "sub1", planIndex: 1, nutritionistId: "d1" });
  const c1 = db.peek("payments/planshare:sub1:1");
  assert.equal(c1.providerAmount, 333.33); assert.equal(c1.settlementStatus, "eligible");
  assert.equal(db.peek("provider_wallets/d1").pendingEarnings, 333.33);
  // replay
  await T._completePlanConsultation(db, "ap1", { subscriptionId: "sub1", planIndex: 1, nutritionistId: "d1" });
  assert.equal(db.peek("provider_wallets/d1").pendingEarnings, 333.33);
  // complete the rest
  const subDoc = db.peek("nutrition_subscriptions/sub1");
  subDoc.consultations[1].appointmentId = "ap2"; subDoc.consultations[2].appointmentId = "ap3";
  db.seed("nutrition_subscriptions/sub1", subDoc);
  await T._completePlanConsultation(db, "ap2", { subscriptionId: "sub1", planIndex: 2, nutritionistId: "d1" });
  await T._completePlanConsultation(db, "ap3", { subscriptionId: "sub1", planIndex: 3, nutritionistId: "d1" });
  assert.equal(db.peek("payments/planshare:sub1:3").providerAmount, 333.34);
  assert.equal(db.peek("provider_wallets/d1").pendingEarnings, 1000);
  assert.equal(db.peek("nutrition_subscriptions/sub1").status, "completed");
});

test("plan completion: refunded parent payment releases nothing", async () => {
  const db = H.db;
  planSetup(db, { refunded: true });
  await T._completePlanConsultation(db, "ap1", { subscriptionId: "sub1", planIndex: 1, nutritionistId: "d1" });
  assert.equal(db.peek("payments/planshare:sub1:1"), undefined);
  assert.equal(db.peek("provider_wallets/d1"), undefined);
});

test("plan completion: unpaid (test mode) uses test credit gating", async () => {
  const db = H.db;
  db.seed("nutrition_subscriptions/sub2", {
    nutritionistId: "d1", paymentId: null, months: 2, baseTotal: 999, status: "active",
    consultations: [{ index: 1, status: "booked", appointmentId: "ap1" }, { index: 2, status: "available" }],
  });
  await T._completePlanConsultation(db, "ap1", { subscriptionId: "sub2", planIndex: 1, nutritionistId: "d1" });
  assert.equal(db.peek("provider_wallets/d1"), undefined, "flag off -> no credit");
});

// ── fake sanity: read-after-write is rejected ────────────────────────────────
test("fake firestore enforces read-before-write in transactions", async () => {
  const db = H.db;
  await assert.rejects(db.runTransaction(async (tx) => { tx.set(db.collection("a").doc("x"), { v: 1 }); await tx.get(db.collection("a").doc("x")); }), /all reads/);
  assert.equal(db.peek("a/x"), undefined);
});
