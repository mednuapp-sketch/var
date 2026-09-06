/**
 * Firestore Rules Unit Tests — Guest join (family member joining a
 * scheduled consultation via a signed link, with no MedNU account of their
 * own).
 *
 * The guest's session is a Firebase custom-token sign-in carrying a
 * `guestAppointmentId` claim (minted by redeemGuestJoinLink in
 * functions/index.js), NOT a normal patientId/doctorId match. These tests
 * simulate that claim directly via testEnv.authenticatedContext(uid, {
 * guestAppointmentId }) rather than actually calling the Cloud Function.
 *
 * Requires the Firestore emulator. Run from this directory:
 *   npm test -- guest_join.rules.test.js
 * (or add to the "test" script in package.json)
 */
const { test, before, beforeEach, after } = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

let testEnv;

const PATIENT = "patient-uid";
const DOCTOR = "doctor-uid";
const APPT_ID = "appt-guest-1";
const OTHER_APPT_ID = "appt-guest-2";
const CONSULT_ID = "consult-guest-1";
const QUICK_CONNECT_CONSULT_ID = "consult-quickconnect-1"; // no appointmentId field
const GUEST_UID = `guest_${APPT_ID}`;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "mednu-rules-test",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "..", "firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection("appointments").doc(APPT_ID).set({
      patientId: PATIENT,
      doctorId: DOCTOR,
      status: "booked",
      guestPhone: "9876543210",
      consultationId: CONSULT_ID,
    });
    await db.collection("appointments").doc(OTHER_APPT_ID).set({
      patientId: PATIENT,
      doctorId: DOCTOR,
      status: "booked",
      // No guestPhone — not guest-enabled.
    });
    await db.collection("consultations").doc(CONSULT_ID).set({
      appointmentId: APPT_ID,
      patientId: PATIENT,
      doctorId: DOCTOR,
      status: "pending",
      callerType: "doctor",
    });
    // A walk-in/quick-connect consultation — no appointmentId field at all,
    // the case the `!= null` short-circuit guard in the rules is protecting.
    await db.collection("consultations").doc(QUICK_CONNECT_CONSULT_ID).set({
      patientId: PATIENT,
      doctorId: DOCTOR,
      status: "pending",
      callerType: "patient",
    });
  });
});

function guestCtx(appointmentId = APPT_ID) {
  return testEnv.authenticatedContext(`guest_${appointmentId}`, {
    guestAppointmentId: appointmentId,
  });
}

// ── appointments ─────────────────────────────────────────────────────────

test("guest can read the one appointment their claim is scoped to", async () => {
  const ref = guestCtx().firestore().collection("appointments").doc(APPT_ID);
  await assertSucceeds(ref.get());
});

test("guest cannot read a different appointment", async () => {
  const ref = guestCtx().firestore().collection("appointments").doc(OTHER_APPT_ID);
  await assertFails(ref.get());
});

test("guest cannot write to the appointment", async () => {
  const ref = guestCtx().firestore().collection("appointments").doc(APPT_ID);
  await assertFails(ref.update({ status: "cancelled" }));
});

test("regular authenticated user without the claim still cannot read someone else's appointment", async () => {
  const ref = testEnv.authenticatedContext("random-uid").firestore()
    .collection("appointments").doc(APPT_ID);
  await assertFails(ref.get());
});

// ── consultations ────────────────────────────────────────────────────────

test("guest can read the consultation whose appointmentId matches their claim", async () => {
  const ref = guestCtx().firestore().collection("consultations").doc(CONSULT_ID);
  await assertSucceeds(ref.get());
});

test("guest cannot read an unrelated (quick-connect) consultation with no appointmentId", async () => {
  const ref = guestCtx().firestore().collection("consultations").doc(QUICK_CONNECT_CONSULT_ID);
  await assertFails(ref.get());
});

test("patient/doctor reads of the quick-connect consultation are unaffected by the guest clause", async () => {
  const asPatient = testEnv.authenticatedContext(PATIENT).firestore()
    .collection("consultations").doc(QUICK_CONNECT_CONSULT_ID);
  await assertSucceeds(asPatient.get());
});

test("guest can end the call (status + endedAt only)", async () => {
  const ref = guestCtx().firestore().collection("consultations").doc(CONSULT_ID);
  await assertSucceeds(ref.update({ status: "ended", endedAt: new Date() }));
});

test("guest cannot modify any other consultation field", async () => {
  const ref = guestCtx().firestore().collection("consultations").doc(CONSULT_ID);
  await assertFails(ref.update({ status: "ended", doctorNotes: "hijacked" }));
});

test("guest with a stale/mismatched claim cannot touch this consultation", async () => {
  const ref = guestCtx(OTHER_APPT_ID).firestore().collection("consultations").doc(CONSULT_ID);
  await assertFails(ref.get());
});

// ── messages subcollection ──────────────────────────────────────────────

test("guest can send a chat message on their own consultation", async () => {
  const ref = guestCtx().firestore()
    .collection("consultations").doc(CONSULT_ID).collection("messages").doc();
  await assertSucceeds(ref.set({
    text: "hello",
    senderId: GUEST_UID,
    senderRole: "patient",
    timestamp: new Date(),
  }));
});

test("guest cannot send a chat message impersonating another sender", async () => {
  const ref = guestCtx().firestore()
    .collection("consultations").doc(CONSULT_ID).collection("messages").doc();
  await assertFails(ref.set({
    text: "hello",
    senderId: PATIENT,
    senderRole: "patient",
    timestamp: new Date(),
  }));
});

test("guest cannot read or send messages on an unrelated consultation", async () => {
  const col = guestCtx().firestore()
    .collection("consultations").doc(QUICK_CONNECT_CONSULT_ID).collection("messages");
  await assertFails(col.doc().set({
    text: "hello",
    senderId: GUEST_UID,
    senderRole: "patient",
    timestamp: new Date(),
  }));
});
