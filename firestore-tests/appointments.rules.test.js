/**
 * Area 1: appointments (patient / doctor / guest / admin allow-deny pairs).
 * Rules under test: firestore.rules `match /appointments/{appointmentId}`.
 */
const { test, before, beforeEach, after } = require("node:test");
const H = require("./helpers/env");
const { ok, no, doc, U } = H;

let env, A;
before(async () => { env = await H.setup("appointments"); A = H.actors(env); });
after(async () => { await env.cleanup(); });

const base = (over = {}) => ({
  patientId: U.patient, doctorId: U.doctor, status: "booked",
  fee: 500, amount: 500, paymentId: "pay_1", date: "2026-12-01", time: "10:00 AM",
  consultationType: "video", createdAt: new Date(), ...over,
});

beforeEach(async () => {
  await env.clearFirestore();
  await H.seedBase(env);
  await H.seed(env, async (db) => {
    const c = db.collection("appointments");
    await c.doc("booked").set(base());
    await c.doc("confirmed").set(base({ status: "confirmed" }));
    await c.doc("completed").set(base({ status: "completed" }));
    await c.doc("cancelled").set(base({ status: "cancelled" }));
    await c.doc("ongoing").set(base({ status: "ongoing" }));
  });
});

const ap = (ctx, id) => doc(ctx, `appointments/${id}`);

// ── create ────────────────────────────────────────────────────────────────
test("patient can create an appointment for themselves", () =>
  ok(ap(A.patient, "new").set(base())));
test("patient cannot create an appointment on behalf of another patient", () =>
  no(ap(A.patient, "new").set(base({ patientId: U.otherPatient }))));
test("a doctor cannot book an appointment with themselves", () =>
  no(ap(A.doctor, "new").set(base({ patientId: U.doctor, doctorId: U.doctor }))));
test("unauthenticated user cannot create an appointment", () =>
  no(ap(A.anon, "new").set(base())));

// ── read ──────────────────────────────────────────────────────────────────
test("patient, doctor and admin can read the appointment", async () => {
  await ok(ap(A.patient, "booked").get());
  await ok(ap(A.doctor, "booked").get());
  await ok(ap(A.director, "booked").get());
});
test("stranger and anonymous cannot read the appointment", async () => {
  await no(ap(A.stranger, "booked").get());
  await no(ap(A.anon, "booked").get());
});

// ── patient updates ───────────────────────────────────────────────────────
for (const s of ["completed", "ended", "delivered", "accepted"]) {
  test(`patient cannot set status '${s}'`, () =>
    no(ap(A.patient, "booked").update({ status: s })));
}
test("patient can cancel a booked appointment with cancelledBy 'patient'", () =>
  ok(ap(A.patient, "booked").update({ status: "cancelled", cancelledBy: "patient", cancelReason: "busy", updatedAt: new Date() })));
test("patient can cancel a confirmed appointment (pre-start state)", () =>
  ok(ap(A.patient, "confirmed").update({ status: "cancelled", cancelledBy: "patient" })));
test("patient cancel with cancelledBy 'doctor' is rejected", () =>
  no(ap(A.patient, "booked").update({ status: "cancelled", cancelledBy: "doctor" })));
test("patient cannot cancel an ongoing appointment", () =>
  no(ap(A.patient, "ongoing").update({ status: "cancelled", cancelledBy: "patient" })));
test("patient cannot cancel a completed appointment", () =>
  no(ap(A.patient, "completed").update({ status: "cancelled", cancelledBy: "patient" })));
test("patient can reschedule date/time while booked", () =>
  ok(ap(A.patient, "booked").update({ date: "2026-12-02", time: "11:00 AM" })));
test("patient cannot change fee / amount / paymentId / doctorId", async () => {
  await no(ap(A.patient, "booked").update({ fee: 1 }));
  await no(ap(A.patient, "booked").update({ amount: 1 }));
  await no(ap(A.patient, "booked").update({ paymentId: "x" }));
  await no(ap(A.patient, "booked").update({ doctorId: U.otherDoctor }));
});
test("another patient cannot update the appointment", () =>
  no(ap(A.otherPatient, "booked").update({ status: "cancelled", cancelledBy: "patient" })));
test("patient cannot delete the appointment", () => no(ap(A.patient, "booked").delete()));

// ── doctor updates ────────────────────────────────────────────────────────
test("assigned doctor can complete a booked appointment", () =>
  ok(ap(A.doctor, "booked").update({ status: "completed", completedAt: new Date() })));
test("doctor cannot turn a cancelled appointment into completed", () =>
  no(ap(A.doctor, "cancelled").update({ status: "completed" })));
test("doctor cannot change fee / amount / paymentId / patientId", async () => {
  await no(ap(A.doctor, "booked").update({ fee: 9999 }));
  await no(ap(A.doctor, "booked").update({ amount: 9999 }));
  await no(ap(A.doctor, "booked").update({ paymentId: "forged" }));
  await no(ap(A.doctor, "booked").update({ patientId: U.otherPatient }));
});
test("a doctor not assigned to the appointment cannot update it", () =>
  no(ap(A.otherDoctor, "booked").update({ status: "completed" })));
test("a pending (unapproved) doctor account cannot update it", () =>
  no(ap(A.pendingDoctor, "booked").update({ status: "completed" })));

// ── guest ─────────────────────────────────────────────────────────────────
test("guest can read and complete only their own appointment", async () => {
  const g = A.guestFor("booked");
  await ok(ap(g, "booked").get());
  await ok(ap(g, "booked").update({ status: "completed", completedAt: new Date() }));
});
test("guest cannot cancel, or touch other fields", async () => {
  const g = A.guestFor("booked");
  await no(ap(g, "booked").update({ status: "cancelled" }));
  await no(ap(g, "booked").update({ fee: 0 }));
});
test("guest may set guestDisplayName (<=60 chars) but not longer", async () => {
  const g = A.guestFor("booked");
  await ok(ap(g, "booked").update({ guestDisplayName: "Aunt" }));
  await no(ap(g, "booked").update({ guestDisplayName: "x".repeat(61) }));
});
test("guest token for another appointment is denied", async () => {
  const g = A.guestFor("confirmed");
  await no(ap(g, "booked").get());
  await no(ap(g, "booked").update({ status: "completed" }));
});

// ── admin ─────────────────────────────────────────────────────────────────
test("admin can update and delete any appointment", async () => {
  await ok(ap(A.director, "booked").update({ fee: 600 }));
  await ok(ap(A.director, "booked").delete());
});
