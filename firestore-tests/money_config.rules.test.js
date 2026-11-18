/**
 * Area 8: money collections + config.
 * provider_wallets, wallet_ledger, payments, refund_requests, razorpay_*,
 * settlements, users/{uid} balance fields, app_config, settlement_config.
 */
const { test, before, beforeEach, after } = require("node:test");
const H = require("./helpers/env");
const { ok, no, doc, U, active } = H;

let env, A;
before(async () => { env = await H.setup("money_config"); A = H.actors(env); });
after(async () => { await env.cleanup(); });

const LAB = active("lab");
beforeEach(async () => {
  await env.clearFirestore();
  await H.seedBase(env);
  await H.seed(env, async (db) => {
    await db.doc(`provider_wallets/${LAB}`).set({ balance: 100 });
    await db.doc("provider_wallets/hosp-1").set({ balance: 50 });
    await db.doc("wallet_ledger/e1").set({ uid: U.patient, amount: 10 });
    await db.doc("wallet_ledger/eh").set({ uid: "hosp-1", amount: 10 });
    await db.doc("payments/p1").set({ patientId: U.patient, providerId: LAB, amount: 100 });
    await db.doc("refund_requests/r1").set({ patientId: U.patient, status: "pending" });
    await db.doc("razorpay_orders/o1").set({ uid: U.patient, amount: 100 });
    await db.doc("razorpay_refunds/rf1").set({ uid: U.patient });
    await db.doc("razorpay_payments/rp1").set({ uid: U.patient });
    await db.doc("settlements/s1").set({ providerId: LAB, amount: 5 });
    await db.doc(`users/${U.patient}`).set({ name: "P", walletBalance: 100, mednuMoneyBalance: 5, referralPoints: 1, role: "patient" });
    await db.doc("app_config/platform_fee").set({ enabled: true, defaultAmount: 10 });
    await db.doc("settlement_config/main").set({ frequency: "weekly", testCreditEnabled: false });
  });
});

// Every context that must never be able to write a server-owned money doc.
const writers = () => [A.patient, A.partner("lab"), A.doctor, A.hr, A.finance, A.director, A.anon];
const SERVER_ONLY = [
  ["provider_wallets", LAB], ["wallet_ledger", "e1"], ["payments", "p1"], ["refund_requests", "r1"],
  ["razorpay_orders", "o1"], ["razorpay_refunds", "rf1"], ["razorpay_payments", "rp1"], ["settlements", "s1"],
];
for (const [col, id] of SERVER_ONLY) {
  test(`${col}: no client create / update / delete for anyone (incl. directors)`, async () => {
    for (const ctx of writers()) {
      await no(doc(ctx, `${col}/${id}`).update({ amount: 999, balance: 999 }));
      await no(doc(ctx, `${col}/${id}`).delete());
      await no(doc(ctx, `${col}/forged`).set({ uid: U.patient, patientId: U.patient, providerId: LAB, amount: 999 }));
    }
  });
}

// ── reads ─────────────────────────────────────────────────────────────────
test("provider_wallets: owner, admin and matching hospital partner can read; others cannot", async () => {
  await ok(doc(A.partner("lab"), `provider_wallets/${LAB}`).get());
  await ok(doc(A.director, `provider_wallets/${LAB}`).get());
  await ok(doc(A.partner("hospital"), "provider_wallets/hosp-1").get());
  await no(doc(A.partner("hospital", "pending"), "provider_wallets/hosp-1").get());
  await no(doc(A.partner("lab", "other"), `provider_wallets/${LAB}`).get());
  await no(doc(A.patient, `provider_wallets/${LAB}`).get());
  await no(doc(A.anon, `provider_wallets/${LAB}`).get());
});
test("wallet_ledger: owner / admin / hospital partner read; others cannot", async () => {
  await ok(doc(A.patient, "wallet_ledger/e1").get());
  await ok(doc(A.director, "wallet_ledger/e1").get());
  await ok(doc(A.partner("hospital"), "wallet_ledger/eh").get());
  await no(doc(A.otherPatient, "wallet_ledger/e1").get());
  await no(doc(A.anon, "wallet_ledger/e1").get());
});
test("payments: patient, provider and finance/HR admin read; support admin and strangers cannot", async () => {
  await ok(doc(A.patient, "payments/p1").get());
  await ok(doc(A.partner("lab"), "payments/p1").get());
  await ok(doc(A.finance, "payments/p1").get());
  await no(doc(A.support, "payments/p1").get());
  await no(doc(A.otherPatient, "payments/p1").get());
});
test("refund_requests: owner and admin read; other patient cannot", async () => {
  await ok(doc(A.patient, "refund_requests/r1").get());
  await ok(doc(A.support, "refund_requests/r1").get());
  await no(doc(A.otherPatient, "refund_requests/r1").get());
  await no(doc(A.anon, "refund_requests/r1").get());
});
test("razorpay_orders: owner and admin read; others cannot", async () => {
  await ok(doc(A.patient, "razorpay_orders/o1").get());
  await ok(doc(A.director, "razorpay_orders/o1").get());
  await no(doc(A.otherPatient, "razorpay_orders/o1").get());
});
test("razorpay_refunds / razorpay_payments: admin read only", async () => {
  for (const p of ["razorpay_refunds/rf1", "razorpay_payments/rp1"]) {
    await ok(doc(A.director, p).get());
    await no(doc(A.patient, p).get());
    await no(doc(A.partner("lab"), p).get());
    await no(doc(A.anon, p).get());
  }
});

// ── user balance fields ───────────────────────────────────────────────────
test("users: owner cannot write walletBalance / mednuMoneyBalance / referralPoints / role", async () => {
  const r = doc(A.patient, `users/${U.patient}`);
  await no(r.update({ walletBalance: 1e6 }));
  await no(r.update({ mednuMoneyBalance: 1e6 }));
  await no(r.update({ referralPoints: 1e6 }));
  await no(r.update({ role: "admin" }));
  await ok(r.update({ name: "New Name" }));
});
test("users/{uid}/transactions: owner read only; client create denied", async () => {
  await no(doc(A.patient, `users/${U.patient}/transactions/t1`).set({ amount: 1000, type: "credit" }));
  await ok(doc(A.director, `users/${U.patient}/transactions/t1`).set({ amount: 1, type: "credit" }));
  await ok(doc(A.patient, `users/${U.patient}/transactions/t1`).get());
  await no(doc(A.patient, `users/${U.patient}/transactions/t1`).update({ amount: 5 }));
});
test("wallet/{uid} and reward_history/{uid}: owner may seed zero but never update", async () => {
  await ok(doc(env.authenticatedContext("new-u"), "wallet/new-u").set({ balance: 0 }));
  await no(doc(env.authenticatedContext("new-u2"), "wallet/new-u2").set({ balance: 500 }));
  await ok(doc(env.authenticatedContext("new-u"), "reward_history/new-u").set({ totalPoints: 0 }));
  await no(doc(env.authenticatedContext("new-u3"), "reward_history/new-u3").set({ totalPoints: 500 }));
});

// ── app_config ────────────────────────────────────────────────────────────
test("app_config: signed-in read; anonymous cannot", async () => {
  await ok(doc(A.patient, "app_config/platform_fee").get());
  await ok(doc(A.partner("lab"), "app_config/platform_fee").get());
  await no(doc(A.anon, "app_config/platform_fee").get());
});
test("app_config: Director may create / update / delete", async () => {
  await ok(doc(A.director, "app_config/platform_fee").update({ defaultAmount: 20 }));
  await ok(doc(A.director, "app_config/payments").set({ requirePayment: true }));
  await ok(doc(A.director, "app_config/payments").delete());
});
test("app_config: HR / finance / support admins, patients and partners cannot write", async () => {
  for (const ctx of [A.hr, A.finance, A.support, A.patient, A.doctor, A.partner("lab"), A.anon]) {
    await no(doc(ctx, "app_config/platform_fee").update({ defaultAmount: 0 }));
    await no(doc(ctx, "app_config/new").set({ x: 1 }));
    await no(doc(ctx, "app_config/platform_fee").delete());
  }
});

// ── settlement_config (testCreditEnabled) ─────────────────────────────────
const SC = (ctx) => doc(ctx, "settlement_config/main");
test("settlement_config: signed-in read; anon cannot", async () => {
  await ok(SC(A.patient).get());
  await no(SC(A.anon).get());
});
test("settlement_config: Finance and Director can change other keys", async () => {
  await ok(SC(A.finance).update({ frequency: "daily" }));
  await ok(SC(A.director).update({ frequency: "monthly" }));
});
test("settlement_config: HR and Support admins cannot write at all", async () => {
  for (const ctx of [A.hr, A.support]) {
    await no(SC(ctx).update({ frequency: "daily" }));
    await no(doc(ctx, "settlement_config/fresh").set({ frequency: "daily" }));
  }
});
test("settlement_config: Finance cannot flip testCreditEnabled / testCreditEnabledAt / enforcePriceCheck", async () => {
  await no(SC(A.finance).update({ testCreditEnabled: true }));
  await no(SC(A.finance).update({ testCreditEnabledAt: new Date() }));
  await no(SC(A.finance).update({ enforcePriceCheck: false }));
  await no(doc(A.finance, "settlement_config/fresh").set({ frequency: "daily", testCreditEnabled: true }));
  await no(doc(A.finance, "settlement_config/fresh2").set({ frequency: "daily", enforcePriceCheck: false }));
  await no(SC(A.hr).update({ testCreditEnabled: true }));
});
test("settlement_config: Finance may re-write unchanged protected keys alongside allowed ones", () =>
  ok(SC(A.finance).update({ frequency: "weekly", testCreditEnabled: false })));
test("settlement_config: Director can set enforcePriceCheck", () =>
  ok(SC(A.director).update({ enforcePriceCheck: false })));
test("settlement_config: Director can flip testCreditEnabled both ways", async () => {
  await ok(SC(A.director).update({ testCreditEnabled: true }));
  await ok(SC(A.director).update({ testCreditEnabled: false }));
});
test("settlement_config: non-admins cannot write; only Director deletes", async () => {
  await no(SC(A.patient).update({ frequency: "daily" }));
  await no(SC(A.partner("lab")).update({ frequency: "daily" }));
  await no(SC(A.finance).delete());
  await ok(SC(A.director).delete());
});
