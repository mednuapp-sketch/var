/**
 * Read restrictions: coupons, commission_rules, app_config allow-list,
 * Storage users/{uid}/** (only profile.jpg public).
 */
const { test, before, beforeEach, after } = require("node:test");
const H = require("./helpers/env");
const { ok, no, doc, U } = H;

let env, A;
before(async () => { env = await H.setup("read_restrictions", { storage: true }); A = H.actors(env); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await H.seedBase(env);
  await H.seed(env, async (db) => {
    await db.doc("coupons/SAVE10").set({ code: "SAVE10", discount: 10 });
    await db.doc("commission_rules/lab").set({ percent: 10 });
    for (const d of ["payments", "platform_fee", "payouts", "app_version", "ambulance_rates", "ambulance_settings", "referral", "nutrition_plans", "other"])
      await db.doc(`app_config/${d}`).set({ x: 1 });
    await db.doc("settlement_config/global").set({ frequency: "weekly" });
  });
});

const everyone = () => [["patient", A.patient], ["partner", A.partner("lab")], ["doctor", A.doctor], ["support", A.support], ["anon", A.anon]];

test("coupons: only director/finance/hr/marketing admins can read; list too", async () => {
  for (const a of [A.director, A.finance, A.hr]) await ok(doc(a, "coupons/SAVE10").get());
  for (const [, c] of [["patient", A.patient], ["partner", A.partner("lab")], ["doctor", A.doctor], ["support", A.support], ["anon", A.anon]])
    await no(doc(c, "coupons/SAVE10").get());
  await no(A.patient.firestore().collection("coupons").get());
});

test("commission_rules: admin finance/hr/director only", async () => {
  for (const a of [A.director, A.finance, A.hr]) await ok(doc(a, "commission_rules/lab").get());
  for (const [, c] of everyone()) await no(doc(c, "commission_rules/lab").get());
});

test("app_config: used docs readable by signed-in; internal docs admin only", async () => {
  for (const d of ["payments", "platform_fee", "payouts", "app_version", "ambulance_rates", "ambulance_settings", "referral"]) {
    await ok(doc(A.patient, `app_config/${d}`).get());
    await ok(doc(A.partner("lab"), `app_config/${d}`).get());
    await no(doc(A.anon, `app_config/${d}`).get());
  }
  for (const d of ["nutrition_plans", "other"]) {
    await no(doc(A.patient, `app_config/${d}`).get());
    await no(doc(A.partner("lab"), `app_config/${d}`).get());
    await ok(doc(A.director, `app_config/${d}`).get());
    await ok(doc(A.support, `app_config/${d}`).get());
  }
});

test("settlement_config/global stays readable by signed-in partner (payout frequency)", async () => {
  await ok(doc(A.partner("lab"), "settlement_config/global").get());
  await no(doc(A.anon, "settlement_config/global").get());
});

const put = (c, p) => c.storage().ref(p).put(new Uint8Array(16), { contentType: "image/jpeg" });
const meta = (c, p) => c.storage().ref(p).getMetadata();
test("storage users/{uid}: profile.jpg public; other files owner/admin only; owner writes still work", async () => {
  await ok(put(A.patient, `users/${U.patient}/profile.jpg`));
  await ok(put(A.patient, `users/${U.patient}/scan.jpg`));
  await ok(meta(A.anon, `users/${U.patient}/profile.jpg`));
  await ok(meta(A.doctor, `users/${U.patient}/profile.jpg`));
  await ok(meta(A.patient, `users/${U.patient}/scan.jpg`));
  await ok(meta(A.director, `users/${U.patient}/scan.jpg`));
  await no(meta(A.anon, `users/${U.patient}/scan.jpg`));
  await no(meta(A.doctor, `users/${U.patient}/scan.jpg`));
  await no(put(A.doctor, `users/${U.patient}/profile.jpg`));
});
