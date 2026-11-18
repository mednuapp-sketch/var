/**
 * Area 2: consultations. Rules: `match /consultations/{consultationId}`.
 */
const { test, before, beforeEach, after } = require("node:test");
const H = require("./helpers/env");
const { ok, no, doc, U } = H;

let env, A;
before(async () => { env = await H.setup("consultations"); A = H.actors(env); });
after(async () => { await env.cleanup(); });

const base = (over = {}) => ({
  patientId: U.patient, doctorId: U.doctor, callerType: "patient",
  status: "pending", appointmentId: "apptG", createdAt: new Date(), ...over,
});

beforeEach(async () => {
  await env.clearFirestore();
  await H.seedBase(env);
  await H.seed(env, async (db) => {
    const c = db.collection("consultations");
    for (const s of ["pending", "active", "ended", "completed", "cancelled"]) {
      await c.doc(s).set(base({ status: s }));
    }
  });
});
const co = (ctx, id) => doc(ctx, `consultations/${id}`);

// ── create ────────────────────────────────────────────────────────────────
for (const s of ["pending", "scheduled_waiting"]) {
  test(`patient can create a consultation with status '${s}'`, () =>
    ok(co(A.patient, "new").set(base({ status: s }))));
}
test("patient create with no status (defaults to pending) is allowed", () => {
  const d = base(); delete d.status;
  return ok(co(A.patient, "new").set(d));
});
for (const s of ["active", "ongoing", "ended", "completed"]) {
  test(`patient cannot create a consultation already '${s}'`, () =>
    no(co(A.patient, "new").set(base({ status: s }))));
}
test("patient cannot create a consultation for another patientId", () =>
  no(co(A.patient, "new").set(base({ patientId: U.otherPatient }))));
test("doctor can create a doctor-initiated call (doctorId == self)", () =>
  ok(co(A.doctor, "new").set(base({ callerType: "doctor", status: "pending" }))));
test("doctor-initiated call with someone else's doctorId is denied", () =>
  no(co(A.otherDoctor, "new").set(base({ callerType: "doctor" }))));
test("anonymous cannot create", () => no(co(A.anon, "new").set(base())));

// ── read ──────────────────────────────────────────────────────────────────
test("patient, doctor, admin and matching guest can read", async () => {
  await ok(co(A.patient, "pending").get());
  await ok(co(A.doctor, "pending").get());
  await ok(co(A.director, "pending").get());
  await ok(co(A.guestFor("apptG"), "pending").get());
});
test("stranger, anon and wrong-guest cannot read", async () => {
  await no(co(A.stranger, "pending").get());
  await no(co(A.anon, "pending").get());
  await no(co(A.guestFor("other"), "pending").get());
});

// ── patient update ────────────────────────────────────────────────────────
test("patient can cancel a pending consultation", () =>
  ok(co(A.patient, "pending").update({ status: "cancelled", cancelledAt: new Date(), cancelledBy: "patient" })));
test("patient can mark pending as ongoing / missed", async () => {
  await ok(co(A.patient, "pending").update({ status: "ongoing", startedAt: new Date() }));
  await ok(co(A.patient, "pending").update({ status: "missed", missedAt: new Date() }));
});
test("patient may keep status and write patientNotes / patientFcmToken", () =>
  ok(co(A.patient, "active").update({ patientNotes: "hi", patientFcmToken: "t" })));
test("patient cannot write 'completed'", () => no(co(A.patient, "pending").update({ status: "completed" })));
test("patient cannot write 'active'", () => no(co(A.patient, "pending").update({ status: "active" })));
for (const s of ["ended", "completed", "cancelled"]) {
  test(`patient cannot reopen a '${s}' consultation`, () =>
    no(co(A.patient, s).update({ status: "ongoing" })));
}
test("patient cancel stamped cancelledBy 'doctor' is rejected", () =>
  no(co(A.patient, "pending").update({ status: "cancelled", cancelledBy: "doctor" })));
test("patient cannot write doctor-only fields (doctorNotes, prescriptionId)", async () => {
  await no(co(A.patient, "pending").update({ doctorNotes: "x" }));
  await no(co(A.patient, "pending").update({ prescriptionId: "rx" }));
});
test("another patient cannot update", () => no(co(A.otherPatient, "pending").update({ status: "cancelled" })));

// ── doctor update ─────────────────────────────────────────────────────────
test("doctor can set pending -> active", () =>
  ok(co(A.doctor, "pending").update({ status: "active", startedAt: new Date() })));
test("doctor can set active -> ended with endedAt/durationSeconds", () =>
  ok(co(A.doctor, "active").update({ status: "ended", endedAt: new Date(), durationSeconds: 120 })));
for (const [k, v] of [["updatedAt", new Date()], ["prescriptionId", "rx1"], ["prescriptionWritten", true], ["missedReason", "relaunch"]]) {
  test(`doctor may write '${k}'`, () => ok(co(A.doctor, "ended").update({ [k]: v })));
}
test("doctor cannot change patientId / doctorId / callerType", async () => {
  await no(co(A.doctor, "pending").update({ patientId: U.otherPatient }));
  await no(co(A.doctor, "pending").update({ doctorId: U.otherDoctor }));
  await no(co(A.doctor, "pending").update({ callerType: "doctor" }));
});
test("doctor cannot write patient-only fields (patientNotes)", () =>
  no(co(A.doctor, "pending").update({ patientNotes: "x" })));
test("unassigned doctor cannot update", () => no(co(A.otherDoctor, "pending").update({ status: "active" })));

// ── guest / admin ─────────────────────────────────────────────────────────
test("guest can end the call (status/endedAt) but nothing else", async () => {
  const g = A.guestFor("apptG");
  await ok(co(g, "active").update({ status: "ended", endedAt: new Date() }));
  await no(co(g, "pending").update({ doctorNotes: "x" }));
});
test("admin can update and delete", async () => {
  await ok(co(A.director, "pending").update({ anything: 1 }));
  await ok(co(A.director, "pending").delete());
});
test("patient cannot delete", () => no(co(A.patient, "pending").delete()));
