/**
 * Partner payouts: payout_accounts/{providerId} + provider read of settlements.
 */
const { test, before, beforeEach, after } = require("node:test");
const H = require("./helpers/env");
const { ok, no, doc, U, active } = H;

let env, A;
before(async () => { env = await H.setup("payouts"); A = H.actors(env); });
after(async () => { await env.cleanup(); });

const LAB = active("lab");
const DESK = active("hospital"); // billing-desk login, hospitalId 'hosp-1'

const acct = (uid, over = {}) => ({
  providerId: uid, ownerUid: uid, role: "lab", holderName: "Test Lab", accountNumber: "123456781234",
  ifsc: "HDFC0001234", bankName: "HDFC Bank", upiId: "lab@upi",
  submittedAt: H.serverTs(), updatedAt: H.serverTs(), status: "pending", ...over,
});

beforeEach(async () => {
  await env.clearFirestore();
  await H.seedBase(env);
  await H.seed(env, async (db) => {
    await db.doc(`settlements/s1`).set({ providerId: LAB, totalAmount: 100, status: "pending" });
    await db.doc(`settlements/s2`).set({ providerId: "hosp-1", totalAmount: 100, status: "pending" });
  });
});

const seedVerified = (id, uid, role = "lab") => H.seed(env, async (db) => {
  await db.doc(`payout_accounts/${id}`).set({
    ...acct(uid, { role }), providerId: id, status: "verified", verifiedBy: U.finance, verifiedAt: new Date(),
  });
});

test("owner can create a pending account (with and without UPI)", async () => {
  await ok(doc(A.partner("lab"), `payout_accounts/${LAB}`).set(acct(LAB)));
  const { upiId, ...noUpi } = acct(LAB);
  await ok(doc(A.partner("lab"), `payout_accounts/${LAB}`).set(noUpi));
});

test("forged status / wrong owner / wrong provider id / extra keys / bad fields are denied", async () => {
  const ref = () => doc(A.partner("lab"), `payout_accounts/${LAB}`);
  await no(ref().set(acct(LAB, { status: "verified" })));
  await no(ref().set(acct(LAB, { ownerUid: "someone" })));
  await no(ref().set(acct(LAB, { providerId: "other" })));
  await no(ref().set({ ...acct(LAB), verifiedBy: U.finance }));
  await no(ref().set({ ...acct(LAB), rejectReason: "x" }));
  await no(ref().set(acct(LAB, { holderName: "A" })));
  await no(ref().set(acct(LAB, { accountNumber: "12345" })));
  await no(ref().set(acct(LAB, { accountNumber: "12ab5678" })));
  await no(ref().set(acct(LAB, { ifsc: "hdfc0001234" })));
  await no(ref().set(acct(LAB, { ifsc: "HDFC1001234" })));
  await no(ref().set(acct(LAB, { upiId: "no-at-sign" })));
  await no(ref().set(acct(LAB, { upiId: "a@" + "b".repeat(90) })));
});

test("other users cannot create or update someone else's account", async () => {
  await no(doc(A.partner("lab", "other"), `payout_accounts/${LAB}`).set(acct(LAB)));
  await no(doc(A.patient, `payout_accounts/${LAB}`).set(acct(LAB)));
  await no(doc(A.anon, `payout_accounts/${LAB}`).set(acct(LAB)));
  await seedVerified(LAB, LAB);
  await no(doc(A.partner("lab", "other"), `payout_accounts/${LAB}`).set(acct(LAB, { bankName: "Evil" })));
});

test("verified account: owner edit must reset to pending (full set); staying verified is denied", async () => {
  await seedVerified(LAB, LAB);
  const ref = doc(A.partner("lab"), `payout_accounts/${LAB}`);
  await no(ref.set(acct(LAB, { status: "verified", bankName: "Changed" })));
  await ok(ref.set(acct(LAB, { bankName: "Changed" }))); // full replace drops verifiedAt/verifiedBy
});

test("finance and director can verify / reject, but not edit bank fields", async () => {
  await H.seed(env, async (db) => { await db.doc(`payout_accounts/${LAB}`).set({ ...acct(LAB) , submittedAt: new Date(), updatedAt: new Date() }); });
  await ok(doc(A.finance, `payout_accounts/${LAB}`).update({ status: "verified", verifiedBy: U.finance, verifiedAt: H.serverTs() }));
  await ok(doc(A.director, `payout_accounts/${LAB}`).update({ status: "rejected", rejectReason: "IFSC mismatch" }));
  await no(doc(A.finance, `payout_accounts/${LAB}`).update({ accountNumber: "99999999" }));
  await no(doc(A.finance, `payout_accounts/${LAB}`).update({ status: "approved" }));
  await no(doc(A.hr, `payout_accounts/${LAB}`).update({ status: "verified" }));
  await no(doc(A.support, `payout_accounts/${LAB}`).update({ status: "verified" }));
});

test("read: owner + finance + director only; hr/support/other owner/patient/anon denied", async () => {
  await seedVerified(LAB, LAB);
  await ok(doc(A.partner("lab"), `payout_accounts/${LAB}`).get());
  await ok(doc(A.finance, `payout_accounts/${LAB}`).get());
  await ok(doc(A.director, `payout_accounts/${LAB}`).get());
  await no(doc(A.hr, `payout_accounts/${LAB}`).get());
  await no(doc(A.support, `payout_accounts/${LAB}`).get());
  await no(doc(A.partner("lab", "other"), `payout_accounts/${LAB}`).get());
  await no(doc(A.patient, `payout_accounts/${LAB}`).get());
  await no(doc(A.anon, `payout_accounts/${LAB}`).get());
});

test("no delete for anyone", async () => {
  await seedVerified(LAB, LAB);
  for (const ctx of [A.partner("lab"), A.finance, A.director, A.hr]) {
    await no(doc(ctx, `payout_accounts/${LAB}`).delete());
  }
});

test("hospital: billing-desk login writes/reads the hospitalId-keyed account; wrong/pending desk denied", async () => {
  const mk = (over = {}) => acct(DESK, { role: "hospital", providerId: "hosp-1", ...over });
  await ok(doc(A.partner("hospital"), "payout_accounts/hosp-1").set(mk()));
  await ok(doc(A.partner("hospital"), "payout_accounts/hosp-1").get());
  await no(doc(A.partner("hospital", "pending"), "payout_accounts/hosp-1").set(mk({ ownerUid: "hospital-pending" })));
  await no(doc(A.partner("hospital", "pending"), "payout_accounts/hosp-1").get());
  await no(doc(A.partner("lab"), "payout_accounts/hosp-1").set(mk({ ownerUid: LAB })));
  await no(doc(A.partner("hospital"), "payout_accounts/hosp-9").set(mk({ providerId: "hosp-9" })));
});

test("settlements: provider (and hospital partner) can read own, not others; no client writes", async () => {
  await ok(doc(A.partner("lab"), "settlements/s1").get());
  await no(doc(A.partner("lab", "other"), "settlements/s1").get());
  await no(doc(A.patient, "settlements/s1").get());
  await ok(doc(A.director, "settlements/s1").get());
  await ok(doc(A.partner("hospital"), "settlements/s2").get());
  await no(doc(A.partner("hospital", "pending"), "settlements/s2").get());
  await no(doc(A.partner("lab"), "settlements/s2").get());
  await no(doc(A.partner("lab"), "settlements/s1").update({ status: "approved" }));
  await no(doc(A.partner("lab"), "settlements/new").set({ providerId: LAB, status: "pending" }));
});

test("app_config/payouts: signed-in read, director-only write", async () => {
  await ok(doc(A.director, "app_config/payouts").set({ enabled: true, minAmount: 500 }));
  await ok(doc(A.partner("lab"), "app_config/payouts").get());
  await no(doc(A.finance, "app_config/payouts").set({ enabled: false }));
  await no(doc(A.partner("lab"), "app_config/payouts").set({ enabled: false }));
});
