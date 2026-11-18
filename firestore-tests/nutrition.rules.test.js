/**
 * Area 7: nutrition_appointments (+ _validNutritionReschedule) and the
 * read-only slot index collections.
 */
const { test, before, beforeEach, after } = require("node:test");
const H = require("./helpers/env");
const { ok, no, doc, U, serverTs, active, other } = H;

let env, A;
before(async () => { env = await H.setup("nutrition"); A = H.actors(env); });
after(async () => { await env.cleanup(); });

const NU = active("nutritionist");
const appt = (over = {}) => ({
  userId: U.patient, nutritionistId: NU, status: "pending",
  date: "2026-12-01", timeSlot: "10:00 AM", createdAt: new Date(), ...over,
});

beforeEach(async () => {
  await env.clearFirestore();
  await H.seedBase(env);
  await H.seed(env, async (db) => {
    const c = db.collection("nutrition_appointments");
    for (const s of ["pending", "confirmed", "in_progress", "completed", "cancelled"]) {
      await c.doc(s).set(appt({ status: s }));
    }
    for (const col of ["nutrition_slots", "physio_slots", "counselling_slots", "appointment_slots"]) {
      await db.collection(col).doc("s1").set({ date: "2026-12-01", time: "10:00 AM" });
    }
  });
});
const na = (ctx, id) => doc(ctx, `nutrition_appointments/${id}`);
const nu = () => A.partner("nutritionist");

// ── create/read ───────────────────────────────────────────────────────────
test("create: patient can book for themselves, not for others", async () => {
  await ok(na(A.patient, "n1").set(appt()));
  await no(na(A.patient, "n2").set(appt({ userId: U.otherPatient })));
  await no(na(A.anon, "n3").set(appt()));
});
test("read: patient, nutritionist, admin; not strangers", async () => {
  await ok(na(A.patient, "pending").get());
  await ok(na(nu(), "pending").get());
  await ok(na(A.director, "pending").get());
  await no(na(A.stranger, "pending").get());
  await no(na(A.anon, "pending").get());
});

// ── patient cancel / status ───────────────────────────────────────────────
test("patient can cancel pending and confirmed appointments", async () => {
  await ok(na(A.patient, "pending").update({ status: "cancelled", cancelledBy: "patient", updatedAt: new Date() }));
  await ok(na(A.patient, "confirmed").update({ status: "cancelled", cancelledBy: "patient" }));
});
test("patient cannot cancel once in_progress, or revive a completed one", async () => {
  await no(na(A.patient, "in_progress").update({ status: "cancelled" }));
  await no(na(A.patient, "completed").update({ status: "cancelled" }));
});
test("patient cannot set confirmed / in_progress / completed", async () => {
  for (const s of ["confirmed", "in_progress", "completed"]) await no(na(A.patient, "pending").update({ status: s }));
});
test("patient cancel stamped cancelledBy 'provider' is rejected", () =>
  no(na(A.patient, "pending").update({ status: "cancelled", cancelledBy: "provider" })));
test("another patient cannot touch the appointment", () =>
  no(na(A.otherPatient, "pending").update({ status: "cancelled" })));

// ── patient reschedule ────────────────────────────────────────────────────
const resched = (by = "patient", over = {}) => ({
  date: "2026-12-02", timeSlot: "11:30 AM", rescheduledAt: serverTs(), rescheduledBy: by, updatedAt: serverTs(), ...over,
});
test("patient reschedule: pending and confirmed allowed", async () => {
  await ok(na(A.patient, "pending").update(resched()));
  await ok(na(A.patient, "confirmed").update(resched()));
});
test("patient reschedule: only date or only timeSlot is enough", async () => {
  await ok(na(A.patient, "pending").update({ date: "2026-12-03", rescheduledAt: serverTs(), rescheduledBy: "patient" }));
  await ok(na(A.patient, "confirmed").update({ timeSlot: "01:00 PM", rescheduledAt: serverTs(), rescheduledBy: "patient" }));
});
test("patient reschedule: not allowed once in_progress / completed / cancelled", async () => {
  for (const s of ["in_progress", "completed", "cancelled"]) await no(na(A.patient, s).update(resched()));
});
test("patient reschedule: rescheduledBy must be 'patient'", () =>
  no(na(A.patient, "pending").update(resched("provider"))));
test("patient reschedule: rescheduledAt must be the server time (not a client date)", () =>
  no(na(A.patient, "pending").update(resched("patient", { rescheduledAt: new Date("2020-01-01") }))));
test("patient reschedule: stamp keys are mandatory", async () => {
  await no(na(A.patient, "pending").update({ date: "2026-12-02" }));
  await no(na(A.patient, "pending").update({ date: "2026-12-02", rescheduledBy: "patient" }));
});
test("patient reschedule: must change date or timeSlot", () =>
  no(na(A.patient, "pending").update({ rescheduledAt: serverTs(), rescheduledBy: "patient" })));
test("patient reschedule: malformed date / timeSlot are rejected", async () => {
  await no(na(A.patient, "pending").update(resched("patient", { date: "02-12-2026" })));
  await no(na(A.patient, "pending").update(resched("patient", { date: 20261202 })));
  await no(na(A.patient, "pending").update(resched("patient", { timeSlot: "11:30" })));
  await no(na(A.patient, "pending").update(resched("patient", { timeSlot: "11:30 am" })));
});
test("patient reschedule: cannot piggy-back status / nutritionistId changes", async () => {
  await no(na(A.patient, "pending").update(resched("patient", { status: "confirmed" })));
  await no(na(A.patient, "pending").update(resched("patient", { nutritionistId: other("nutritionist") })));
});
test("stranger / other patient cannot reschedule", async () => {
  await no(na(A.otherPatient, "pending").update(resched()));
  await no(na(A.stranger, "pending").update(resched()));
});

// ── provider ──────────────────────────────────────────────────────────────
test("provider reschedule: stamped 'provider' allowed; stamped 'patient' rejected", async () => {
  await ok(na(nu(), "confirmed").update(resched("provider")));
  await no(na(nu(), "pending").update(resched("patient")));
});
test("provider: other nutritionist cannot reschedule", () =>
  no(na(A.partner("nutritionist", "other"), "pending").update(resched("provider"))));
test("provider: pipeline pending -> confirmed -> in_progress -> completed", async () => {
  await ok(na(nu(), "pending").update({ status: "confirmed", updatedAt: new Date() }));
  await ok(na(nu(), "confirmed").update({ status: "in_progress" }));
  await ok(na(nu(), "in_progress").update({ status: "completed", providerNotes: "done" }));
});
test("provider: cannot jump pending -> completed or reopen completed", async () => {
  await no(na(nu(), "pending").update({ status: "completed" }));
  await no(na(nu(), "completed").update({ status: "pending" }));
});
test("provider: cannot stamp cancelledBy 'patient'", () =>
  no(na(nu(), "pending").update({ status: "cancelled", cancelledBy: "patient" })));
test("provider: cannot change userId or date outside the reschedule shape", async () => {
  await no(na(nu(), "pending").update({ userId: U.otherPatient }));
  await no(na(nu(), "pending").update({ status: "confirmed", date: "2027-01-01" }));
});
test("delete: admin only", async () => {
  await no(na(A.patient, "pending").delete());
  await no(na(nu(), "pending").delete());
  await ok(na(A.director, "pending").delete());
});

// ── slot index collections ────────────────────────────────────────────────
for (const col of ["nutrition_slots", "physio_slots", "counselling_slots", "appointment_slots"]) {
  test(`${col}: any signed-in user can read; anonymous cannot`, async () => {
    await ok(doc(A.patient, `${col}/s1`).get());
    await ok(doc(nu(), `${col}/s1`).get());
    await no(doc(A.anon, `${col}/s1`).get());
  });
  test(`${col}: no client write (create / update / delete), not even admin or the booking patient`, async () => {
    for (const ctx of [A.patient, nu(), A.doctor, A.director]) {
      await no(doc(ctx, `${col}/new`).set({ date: "2026-12-01", time: "10:00 AM" }));
      await no(doc(ctx, `${col}/s1`).update({ time: "x" }));
      await no(doc(ctx, `${col}/s1`).delete());
    }
  });
}

// ── prepaid weight-loss plan: nutrition_subscriptions + server-set plan fields ──
const sub = (over = {}) => ({
  patientId: U.patient, nutritionistId: NU, planType: "weight_loss", months: 2, status: "active",
  consultations: [{ index: 1, status: "booked" }, { index: 2, status: "available" }], ...over,
});
const ns = (ctx, id = "sub1") => doc(ctx, `nutrition_subscriptions/${id}`);
test("nutrition_subscriptions: patient and assigned dietician read their own; strangers cannot", async () => {
  await H.seed(env, (db) => db.collection("nutrition_subscriptions").doc("sub1").set(sub()));
  await ok(ns(A.patient).get());
  await ok(ns(nu()).get());
  await ok(ns(A.director).get());
  await no(ns(A.otherPatient).get());
  await no(ns(A.stranger).get());
  await no(ns(A.partner("nutritionist", "other")).get());
  await no(ns(A.anon).get());
});
test("nutrition_subscriptions: no client write at all (create / update / delete)", async () => {
  await H.seed(env, (db) => db.collection("nutrition_subscriptions").doc("sub1").set(sub()));
  for (const ctx of [A.patient, nu(), A.director]) {
    await no(ns(ctx, "new").set(sub()));
    await no(ns(ctx).update({ status: "completed" }));
    await no(ns(ctx).update({ consultations: [] }));
    await no(ns(ctx).delete());
  }
});
test("create: client cannot set plan links or a prepaid paymentStatus on a nutrition appointment", async () => {
  await no(na(A.patient, "p1").set(appt({ subscriptionId: "sub1", planIndex: 2 })));
  await no(na(A.patient, "p2").set(appt({ paymentStatus: "plan_prepaid" })));
  await no(na(A.patient, "p3").set(appt({ planIndex: 1 })));
  await ok(na(A.patient, "p4").set(appt({ paymentStatus: "not_required", planType: "weight_loss", planMonths: 2 })));
});
test("update: patient / dietician cannot add or change subscriptionId / planIndex / paymentStatus", async () => {
  for (const ctx of [A.patient, nu()]) {
    await no(na(ctx, "pending").update({ subscriptionId: "sub1" }));
    await no(na(ctx, "pending").update({ planIndex: 3 }));
    await no(na(ctx, "pending").update({ paymentStatus: "plan_prepaid" }));
  }
});
