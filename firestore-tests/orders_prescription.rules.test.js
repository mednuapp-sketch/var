/**
 * Firestore Rules Unit Tests — Patient Prescription Upload (`orders`
 * collection additive fields).
 *
 * Requires the Firestore emulator (Java + firebase-tools). Run from this
 * directory:
 *   npm install
 *   npm test
 *
 * Loads the SAME `firestore.rules` file every app/emulator uses
 * (../firestore.rules) — this is also, as of the deploy-target fix, the
 * file both mednu/firebase.json and mednu_doctor/firebase.json point at.
 */
const { test, before, beforeEach, after } = require("node:test");
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
const PHARMACY = "pharmacy-uid";
const OTHER_PHARMACY = "other-pharmacy-uid";

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
    await db.collection("orders").doc("order-1").set({
      orderId: "order-1",
      patientId: PATIENT,
      items: [{ id: "med-1", name: "Paracetamol", brand: "Crocin", price: 30, count: 2 }],
      total: 60,
      status: "confirmed",
      deliveryAddress: "123 Main St",
      deliveryName: "Patient",
      deliveryPhone: "9999999999",
      prescriptionUrl: null,
      prescriptionFileType: null,
      prescriptionUploadedAt: null,
      prescriptionVerified: null,
      prescriptionRejectedReason: null,
    });
    await db.collection("pharmacy_profiles").doc(PHARMACY).set({ status: "active", isVerified: true });
    await db.collection("pharmacy_orders").doc("order-1").set({
      sourceCollection: "orders",
      sourceId: "order-1",
      orderType: "medicine",
      pharmacyId: PHARMACY,
      status: "prescription_required",
      patientId: PATIENT,
    });
  });
});

test("the owning patient can upload a prescription (url/fileType/uploadedAt only)", async () => {
  const patientCtx = testEnv.authenticatedContext(PATIENT);
  const ref = patientCtx.firestore().collection("orders").doc("order-1");
  await assertSucceeds(ref.update({
    prescriptionUrl: "https://example.com/rx.jpg",
    prescriptionFileType: "image",
    prescriptionUploadedAt: new Date(),
  }));
});

test("a different patient cannot upload onto someone else's order", async () => {
  const otherCtx = testEnv.authenticatedContext(OTHER_PATIENT);
  const ref = otherCtx.firestore().collection("orders").doc("order-1");
  await assertFails(ref.update({
    prescriptionUrl: "https://example.com/rx.jpg",
    prescriptionFileType: "image",
    prescriptionUploadedAt: new Date(),
  }));
});

test("the owning patient can remove a prescription (set fields back to null)", async () => {
  const patientCtx = testEnv.authenticatedContext(PATIENT);
  const ref = patientCtx.firestore().collection("orders").doc("order-1");
  await assertSucceeds(ref.update({
    prescriptionUrl: null,
    prescriptionFileType: null,
    prescriptionUploadedAt: null,
  }));
});

test("a patient can never set prescriptionVerified themselves", async () => {
  const patientCtx = testEnv.authenticatedContext(PATIENT);
  const ref = patientCtx.firestore().collection("orders").doc("order-1");
  await assertFails(ref.update({ prescriptionVerified: true }));
});

test("a patient can never set prescriptionRejectedReason themselves", async () => {
  const patientCtx = testEnv.authenticatedContext(PATIENT);
  const ref = patientCtx.firestore().collection("orders").doc("order-1");
  await assertFails(ref.update({ prescriptionRejectedReason: "self-approved, trust me" }));
});

test("a patient cannot smuggle a verification field into an otherwise-valid upload write", async () => {
  const patientCtx = testEnv.authenticatedContext(PATIENT);
  const ref = patientCtx.firestore().collection("orders").doc("order-1");
  await assertFails(ref.update({
    prescriptionUrl: "https://example.com/rx.jpg",
    prescriptionFileType: "image",
    prescriptionUploadedAt: new Date(),
    prescriptionVerified: true, // the one extra field that should sink the whole write
  }));
});

test("a patient cannot rewrite order total/items via the same update", async () => {
  const patientCtx = testEnv.authenticatedContext(PATIENT);
  const ref = patientCtx.firestore().collection("orders").doc("order-1");
  await assertFails(ref.update({
    prescriptionUrl: "https://example.com/rx.jpg",
    total: 1,
  }));
});

// ── Storage: order_prescriptions/{orderId}/... ─────────────────────────────
// Rules-unit-testing for Storage requires a separate emulator/harness
// (@firebase/rules-unit-testing's storage helpers); documented here as the
// scenarios that harness should cover once wired up, since this file only
// exercises Firestore rules:
//   - the owning patient (order(orderId).patientId == uid) can write
//   - a stranger cannot write
//   - the owning patient AND the assigned pharmacy (pharmacyOrder(orderId)
//     .pharmacyId == uid) can read; a stranger cannot
//   - a file over 20 MB is rejected
