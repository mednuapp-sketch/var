/**
 * Firestore Rules Unit Tests — Patient "Join Now" call-initiation flow
 * (`appointments.consultationId` stamp + `consultations` create).
 *
 * Reproduces the exact batch write from
 * mednu/lib/features/services/appointment/appointment_screen.dart _joinCall():
 *   1. create consultations/{new}  (callerType: 'patient', patientId: uid)
 *   2. update appointments/{id}    ({ consultationId: <new id> })
 * as a single atomic batch, matching what the client actually sends.
 *
 * Requires the Firestore emulator. Run from this directory:
 *   npm test -- appointments_join_call.rules.test.js
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
const OTHER_PATIENT = "other-patient-uid";
const DOCTOR = "doctor-uid";
const APPT_ID = "appt-1";

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
      status: "confirmed",
      consultationType: "Video",
      consultationId: null,
    });
  });
});

test("patient joining a scheduled call: batch(create consultation + stamp consultationId) succeeds", async () => {
  const patientCtx = testEnv.authenticatedContext(PATIENT);
  const db = patientCtx.firestore();
  const consultRef = db.collection("consultations").doc();
  const batch = db.batch();
  batch.set(consultRef, {
    appointmentId: APPT_ID,
    channelName: APPT_ID,
    doctorId: DOCTOR,
    patientId: PATIENT,
    consultationType: "Video",
    callerType: "patient",
    isScheduled: true,
    status: "scheduled_waiting",
  });
  batch.update(db.collection("appointments").doc(APPT_ID), {
    consultationId: consultRef.id,
  });
  await assertSucceeds(batch.commit());
});

test("a different patient cannot stamp consultationId onto someone else's appointment", async () => {
  const otherCtx = testEnv.authenticatedContext(OTHER_PATIENT);
  const ref = otherCtx.firestore().collection("appointments").doc(APPT_ID);
  await assertFails(ref.update({ consultationId: "hijacked-consultation" }));
});

test("owning patient still cannot smuggle other fields alongside consultationId", async () => {
  const patientCtx = testEnv.authenticatedContext(PATIENT);
  const ref = patientCtx.firestore().collection("appointments").doc(APPT_ID);
  await assertFails(ref.update({ consultationId: "c1", amount: 0 }));
});

test("owning patient can still cancel (status/cancelReason/updatedAt only)", async () => {
  const patientCtx = testEnv.authenticatedContext(PATIENT);
  const ref = patientCtx.firestore().collection("appointments").doc(APPT_ID);
  await assertSucceeds(ref.update({ status: "cancelled", cancelReason: "changed my mind" }));
});
