"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const H = require("./harness");

const silence = () => { const l = console.log, e = console.error, w = console.warn; console.log = console.error = console.warn = () => {}; return () => { console.log = l; console.error = e; console.warn = w; }; };
let restore;
test.beforeEach(() => { H.reset(); restore = silence(); });
test.afterEach(() => restore());

const rejects = async (fn, code) => {
  await assert.rejects(fn, (e) => { assert.equal(e.code, code, `expected ${code}, got ${e.code}: ${e.message}`); return true; });
};
const call = (name, uid, data = {}) => H.index[name].run({ auth: { uid }, data });

function seedPartner(db, uid = "p1", over = {}) {
  db.seed(`doctors/${uid}`, { roles: ["lab"], name: "Test Lab", ...over });
  db.seed(`payout_accounts/${uid}`, {
    providerId: uid, ownerUid: uid, role: "lab", holderName: "Test Lab", accountNumber: "123456781234",
    ifsc: "HDFC0001234", bankName: "HDFC Bank", upiId: "lab@upi", status: "verified",
  });
}
function eligible(db, amounts, providerId = "p1", prefix = "e") {
  amounts.forEach((a, i) => db.seed(`payments/${prefix}${i}`, { providerId, providerAmount: a, settlementStatus: "eligible", status: "completed" }));
}

test("requestPayout: needs a partner role and a verified account", async () => {
  const db = H.db;
  eligible(db, [1000]);
  await rejects(() => call("requestPayout", "nobody"), "permission-denied");
  db.seed("doctors/p1", { roles: ["lab"] });
  await rejects(() => call("requestPayout", "p1"), "failed-precondition");
  db.seed("payout_accounts/p1", { providerId: "p1", ownerUid: "p1", accountNumber: "123456", status: "pending" });
  await rejects(() => call("requestPayout", "p1"), "failed-precondition");
  db.seed("payout_accounts/p1", { providerId: "p1", ownerUid: "someone-else", accountNumber: "123456", status: "verified" });
  await rejects(() => call("requestPayout", "p1"), "failed-precondition");
  assert.equal(db.list("settlements").length, 0);
});

test("requestPayout: minimum amount (default 500, configurable) and enabled flag", async () => {
  const db = H.db; seedPartner(db);
  eligible(db, [200, 250]);
  await rejects(() => call("requestPayout", "p1"), "failed-precondition");
  db.seed("app_config/payouts", { minAmount: 400 });
  const r = await call("requestPayout", "p1");
  assert.equal(r.amount, 450);

  H.reset(); seedPartner(H.db); eligible(H.db, [900]);
  H.db.seed("app_config/payouts", { enabled: false });
  await rejects(() => call("requestPayout", "p1"), "failed-precondition");
  assert.equal(H.db.list("settlements").length, 0);
});

test("requestPayout: Rs3000 eligible, Rs999 debt -> settlement Rs2001, masked snapshot, payments flagged", async () => {
  const db = H.db; seedPartner(db);
  db.seed("provider_wallets/p1", { pendingEarnings: 3000, recoverableDebt: 999 });
  eligible(db, [1000, 2000]);
  const r = await call("requestPayout", "p1");
  assert.equal(r.amount, 2001);
  const s = db.peek(`settlements/${r.settlementId}`);
  assert.equal(s.totalAmount, 2001); assert.equal(s.grossAmount, 3000); assert.equal(s.recoveryApplied, 999);
  assert.equal(s.status, "pending"); assert.equal(s.requestedByPartner, true); assert.equal(s.requestedBy, "p1");
  assert.ok(s.requestedAt);
  assert.deepEqual(s.payoutAccountSnapshot, {
    holderName: "Test Lab", bankName: "HDFC Bank", ifsc: "HDFC0001234", accountNumberMasked: "XXXXXX1234", upiId: "lab@upi",
  });
  assert.ok(!JSON.stringify(s).includes("123456781234"), "full number never stored on the settlement");
  assert.equal(db.peek("provider_wallets/p1").recoverableDebt, 0);
  assert.equal(db.peek("payments/e0").settlementStatus, "pending_review");
  assert.equal(db.peek("payments/e1").settlementId, r.settlementId);
  assert.ok(db.list("admin_alerts").some((a) => a.type === "payout_requested"));
  assert.ok(db.list("audit_logs").some((a) => a.action === "requestPayout"));
});

test("requestPayout: second request refused while one is open; allowed after paid", async () => {
  const db = H.db; seedPartner(db); db.seed("admins/a1", { role: "finance" });
  eligible(db, [1000]);
  const r = await call("requestPayout", "p1");
  db.seed("payments/new", { providerId: "p1", providerAmount: 800, settlementStatus: "eligible", status: "completed" });
  await rejects(() => call("requestPayout", "p1"), "already-exists");
  await call("approveSettlement", "a1", { settlementId: r.settlementId });
  await rejects(() => call("requestPayout", "p1"), "already-exists");
  const paid = await call("markSettlementPaid", "a1", { settlementId: r.settlementId, payoutReference: "U1" });
  assert.equal(paid.destination.accountNumberMasked, "XXXXXX1234");
  const r2 = await call("requestPayout", "p1");
  assert.equal(r2.amount, 800);
});

test("requestPayout: debt fully offsetting earnings is refused and nothing changes", async () => {
  const db = H.db; seedPartner(db);
  db.seed("provider_wallets/p1", { recoverableDebt: 5000 });
  eligible(db, [600]);
  await rejects(() => call("requestPayout", "p1"), "failed-precondition");
  assert.equal(db.peek("provider_wallets/p1").recoverableDebt, 5000);
  assert.equal(db.peek("payments/e0").settlementStatus, "eligible");
});

test("requestPayout: hospital login resolves to the hospitalId wallet", async () => {
  const db = H.db;
  db.seed("hospital_profiles/desk1", { status: "active", hospitalId: "hosp-1", name: "City Hospital" });
  db.seed("payout_accounts/hosp-1", { providerId: "hosp-1", ownerUid: "desk1", role: "hospital", accountNumber: "99887766", holderName: "City", bankName: "SBI", ifsc: "SBIN0000001", status: "verified" });
  eligible(db, [1500], "hosp-1");
  eligible(db, [700], "desk1", "x"); // the uid is NOT the wallet id: must not be touched
  const r = await call("requestPayout", "desk1");
  const s = db.peek(`settlements/${r.settlementId}`);
  assert.equal(s.providerId, "hosp-1"); assert.equal(s.totalAmount, 1500);
  assert.equal(s.payoutAccountSnapshot.accountNumberMasked, "XXXXXX7766");
  assert.equal(db.peek("payments/x0").settlementStatus, "eligible");
  await rejects(() => call("requestPayout", "desk-unknown"), "permission-denied");
});

test("cancelPayoutRequest: releases payments, restores debt, only while pending, only own", async () => {
  const db = H.db; seedPartner(db); seedPartner(db, "p2"); db.seed("admins/a1", { role: "finance" });
  db.seed("provider_wallets/p1", { pendingEarnings: 3000, recoverableDebt: 999 });
  eligible(db, [1000, 2000]);
  const r = await call("requestPayout", "p1");
  await rejects(() => call("cancelPayoutRequest", "p2", { settlementId: r.settlementId }), "permission-denied");
  await call("cancelPayoutRequest", "p1", { settlementId: r.settlementId });
  assert.equal(db.peek(`settlements/${r.settlementId}`).status, "cancelled");
  assert.equal(db.peek("payments/e0").settlementStatus, "eligible");
  assert.equal(db.peek("payments/e0").settlementId, undefined);
  assert.equal(db.peek("provider_wallets/p1").recoverableDebt, 999);
  await rejects(() => call("cancelPayoutRequest", "p1", { settlementId: r.settlementId }), "failed-precondition");
  await rejects(() => call("approveSettlement", "a1", { settlementId: r.settlementId }), "failed-precondition");
  await rejects(() => call("holdSettlement", "a1", { settlementId: r.settlementId }), "failed-precondition");
  // request again; once approved it can no longer be cancelled
  const r2 = await call("requestPayout", "p1");
  assert.equal(r2.amount, 2001);
  await call("approveSettlement", "a1", { settlementId: r2.settlementId });
  await rejects(() => call("cancelPayoutRequest", "p1"), "not-found");
  await rejects(() => call("cancelPayoutRequest", "p1", { settlementId: r2.settlementId }), "failed-precondition");
});

test("cancelPayoutRequest: finds the open request when no id is given", async () => {
  const db = H.db; seedPartner(db); eligible(db, [900]);
  const r = await call("requestPayout", "p1");
  const c = await call("cancelPayoutRequest", "p1");
  assert.equal(c.settlementId, r.settlementId);
});
