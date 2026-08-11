/**
 * Firestore Rules Unit Tests — Lab & Diagnostics module.
 *
 * Requires the Firestore emulator (Java + firebase-tools). Run from this
 * directory:
 *   npm install
 *   npm test
 *
 * These tests load the SAME `firestore.rules` file every app/emulator uses
 * (../firestore.rules) — there is no separate copy to drift out of sync.
 */
const { test, before, beforeEach, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

let testEnv;

const LAB_A = "lab-a-uid";
const LAB_B = "lab-b-uid";
const PATIENT = "patient-uid";
const OTHER_PATIENT = "other-patient-uid";

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
  // Seed fixtures with security rules disabled — mirrors what the Cloud
  // Function mirror (Admin SDK) would have already written before any
  // client ever touches these documents.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection("lab_profiles").doc(LAB_A).set({ status: "active", isVerified: true });
    await db.collection("lab_profiles").doc(LAB_B).set({ status: "active", isVerified: true });

    await db.collection("diagnostic_bookings").doc("unclaimed-1").set({
      sourceRequestId: "unclaimed-1",
      type: "diagnostics",
      testName: "Blood Test",
      price: 500,
      amount: 500,
      patientId: PATIENT,
      patientName: "Patient",
      patientPhone: "",
      address: "",
      preferredDate: "",
      preferredTime: "",
      notes: "",
      labId: null,
      status: "pending",
      technicianId: null,
      technicianName: null,
      collectionTime: null,
      reportUrl: null,
      reportUploadedAt: null,
      reportVersion: 0,
      latestReportId: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    await db.collection("diagnostic_bookings").doc("claimed-by-a").set({
      sourceRequestId: "claimed-by-a",
      type: "diagnostics",
      testName: "X-Ray",
      price: 800,
      amount: 800,
      patientId: PATIENT,
      patientName: "Patient",
      patientPhone: "",
      address: "",
      preferredDate: "",
      preferredTime: "",
      notes: "",
      labId: LAB_A,
      status: "accepted",
      technicianId: null,
      technicianName: null,
      collectionTime: null,
      reportUrl: null,
      reportUploadedAt: null,
      reportVersion: 0,
      latestReportId: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });
});

test("a lab partner can claim (accept) an unclaimed pending booking", async () => {
  const labCtx = testEnv.authenticatedContext(LAB_A);
  const ref = labCtx.firestore().collection("diagnostic_bookings").doc("unclaimed-1");
  await assertSucceeds(ref.update({ labId: LAB_A, status: "accepted", updatedAt: new Date() }));
});

test("a second lab cannot claim a booking already owned by another lab (prevents double acceptance)", async () => {
  const labBCtx = testEnv.authenticatedContext(LAB_B);
  const ref = labBCtx.firestore().collection("diagnostic_bookings").doc("claimed-by-a");
  await assertFails(ref.update({ labId: LAB_B, status: "accepted", updatedAt: new Date() }));
});

test("claiming a booking cannot jump straight to a non-accept/reject status", async () => {
  const labCtx = testEnv.authenticatedContext(LAB_A);
  const ref = labCtx.firestore().collection("diagnostic_bookings").doc("unclaimed-1");
  await assertFails(ref.update({ labId: LAB_A, status: "completed", updatedAt: new Date() }));
});

test("a random authenticated user (no lab_profiles doc) cannot claim an unclaimed booking", async () => {
  const strangerCtx = testEnv.authenticatedContext("stranger-uid");
  const ref = strangerCtx.firestore().collection("diagnostic_bookings").doc("unclaimed-1");
  await assertFails(ref.update({ labId: "stranger-uid", status: "accepted", updatedAt: new Date() }));
});

test("the owning lab can advance a booking along a valid status transition", async () => {
  const labCtx = testEnv.authenticatedContext(LAB_A);
  const ref = labCtx.firestore().collection("diagnostic_bookings").doc("claimed-by-a");
  await assertSucceeds(ref.update({
    status: "technician_assigned",
    technicianName: "Ravi",
    collectionTime: new Date(),
    updatedAt: new Date(),
  }));
});

test("the owning lab cannot skip a status transition (accepted -> completed)", async () => {
  const labCtx = testEnv.authenticatedContext(LAB_A);
  const ref = labCtx.firestore().collection("diagnostic_bookings").doc("claimed-by-a");
  await assertFails(ref.update({ status: "completed", updatedAt: new Date() }));
});

test("the owning lab cannot rewrite immutable core booking fields", async () => {
  const labCtx = testEnv.authenticatedContext(LAB_A);
  const ref = labCtx.firestore().collection("diagnostic_bookings").doc("claimed-by-a");
  await assertFails(ref.update({
    amount: 999999,
    patientId: "someone-else",
    updatedAt: new Date(),
  }));
});

test("a lab not assigned to a booking cannot update it at all", async () => {
  const labBCtx = testEnv.authenticatedContext(LAB_B);
  const ref = labBCtx.firestore().collection("diagnostic_bookings").doc("claimed-by-a");
  await assertFails(ref.update({ status: "technician_assigned", updatedAt: new Date() }));
});

test("the owning patient can read their own booking", async () => {
  const patientCtx = testEnv.authenticatedContext(PATIENT);
  const ref = patientCtx.firestore().collection("diagnostic_bookings").doc("claimed-by-a");
  await assertSucceeds(ref.get());
});

test("a different patient cannot read someone else's claimed booking", async () => {
  const otherPatientCtx = testEnv.authenticatedContext(OTHER_PATIENT);
  const ref = otherPatientCtx.firestore().collection("diagnostic_bookings").doc("claimed-by-a");
  await assertFails(ref.get());
});

test("clients can never write lab_transactions directly (Cloud Function only)", async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("lab_transactions").doc("claimed-by-a").set({
      labId: LAB_A, bookingId: "claimed-by-a", amount: 800, type: "earning", status: "credited",
    });
  });
  const labCtx = testEnv.authenticatedContext(LAB_A);
  const ref = labCtx.firestore().collection("lab_transactions").doc("claimed-by-a");
  await assertFails(ref.set({ labId: LAB_A, bookingId: "claimed-by-a", amount: 999999 }));
  await assertSucceeds(ref.get()); // owner can still read it
});

test("diagnostic_reports create requires the uploader to actually own the referenced booking", async () => {
  const labBCtx = testEnv.authenticatedContext(LAB_B);
  // LAB_B does not own "claimed-by-a" (LAB_A does) — must be rejected even
  // though LAB_B correctly asserts its own uid as labId on the report.
  const ref = labBCtx.firestore().collection("diagnostic_reports").doc();
  await assertFails(ref.set({
    bookingId: "claimed-by-a",
    patientId: PATIENT,
    labId: LAB_B,
    testName: "X-Ray",
    fileUrl: "https://example.com/report.pdf",
    fileName: "report.pdf",
    fileType: "pdf",
    version: 1,
    uploadedAt: new Date(),
  }));
});

test("diagnostic_reports create succeeds when the uploader owns the referenced booking", async () => {
  const labACtx = testEnv.authenticatedContext(LAB_A);
  const ref = labACtx.firestore().collection("diagnostic_reports").doc();
  await assertSucceeds(ref.set({
    bookingId: "claimed-by-a",
    patientId: PATIENT,
    labId: LAB_A,
    testName: "X-Ray",
    fileUrl: "https://example.com/report.pdf",
    fileName: "report.pdf",
    fileType: "pdf",
    version: 1,
    uploadedAt: new Date(),
  }));
});

test("diagnostic_reports are append-only — a lab cannot update or delete an existing version", async () => {
  let reportId;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const ref = await ctx.firestore().collection("diagnostic_reports").add({
      bookingId: "claimed-by-a", patientId: PATIENT, labId: LAB_A, version: 1,
    });
    reportId = ref.id;
  });
  const labCtx = testEnv.authenticatedContext(LAB_A);
  const ref = labCtx.firestore().collection("diagnostic_reports").doc(reportId);
  await assertFails(ref.update({ version: 2 }));
  await assertFails(ref.delete());
});

test("a lab cannot self-verify or inflate its own rating on lab_profiles", async () => {
  const labCtx = testEnv.authenticatedContext(LAB_A);
  const ref = labCtx.firestore().collection("lab_profiles").doc(LAB_A);
  await assertFails(ref.update({ isVerified: true, status: "active" }));
  await assertFails(ref.update({ rating: 5, totalReviews: 999 }));
  await assertSucceeds(ref.update({ address: "New address" }));
});
