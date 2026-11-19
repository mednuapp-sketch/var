/**
 * Shared helper layer for the MedNu rules test suite.
 *
 * - setup(name, {storage}) boots a rules-unit-testing environment against the
 *   CURRENT ../firestore.rules (and ../storage.rules) read from disk at call
 *   time. Every test file uses its own projectId so files never clobber each
 *   other's data on a shared emulator.
 * - Emulator hosts come from FIRESTORE_EMULATOR_HOST / FIREBASE_STORAGE_EMULATOR_HOST
 *   (set by `firebase emulators:exec`), falling back to 127.0.0.1:8080 / :9199.
 * - seed()/seedBase() write fixtures with security rules disabled.
 */
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

const ROOT = path.resolve(__dirname, "..", "..");
const readRules = (f) => fs.readFileSync(path.join(ROOT, f), "utf8");

function hostPort(envName, defHost, defPort) {
  const v = process.env[envName];
  if (v && v.includes(":")) {
    const i = v.lastIndexOf(":");
    return { host: v.slice(0, i), port: Number(v.slice(i + 1)) };
  }
  return { host: defHost, port: defPort };
}

async function setup(name, { storage = false } = {}) {
  // Storage rules call firestore.get()/exists(), which the Storage emulator
  // resolves against the emulator suite's own project (--project), so storage
  // tests must run under that project id or the cross-service lookups miss.
  const projectId = storage
    ? (process.env.GCLOUD_PROJECT || "mednu-rules-test")
    : `mednu-rules-${String(name).toLowerCase().replace(/[^a-z0-9-]/g, "-")}`;
  const cfg = {
    projectId,
    firestore: { rules: readRules("firestore.rules"), ...hostPort("FIRESTORE_EMULATOR_HOST", "127.0.0.1", 8080) },
  };
  if (storage) {
    cfg.storage = { rules: readRules("storage.rules"), ...hostPort("FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1", 9199) };
  }
  return initializeTestEnvironment(cfg);
}

// Partner roles: profile collection + the uid prefix used for fixtures.
const ROLES = {
  lab: "lab_profiles",
  pharmacy: "pharmacy_profiles",
  equipment: "equipment_profiles",
  ambulance: "ambulance_profiles",
  caregiver: "caregiver_profiles",
  physiotherapist: "physiotherapist_profiles",
  counsellor: "counsellor_profiles",
  nutritionist: "nutritionist_profiles",
  hospital: "hospital_profiles",
};

// Fixed uids.
const U = {
  patient: "patient-1",
  otherPatient: "patient-2",
  doctor: "doctor-1",
  otherDoctor: "doctor-2",
  pendingDoctor: "doctor-pending",
  director: "admin-director",
  hr: "admin-hr",
  support: "admin-support",
  finance: "admin-finance",
  guest: "guest-1",
  stranger: "stranger-1",
};
const active = (role) => `${role}-active`;
const pending = (role) => `${role}-pending`;
const other = (role) => `${role}-active-2`;

/** Run a seeding callback with security rules disabled (compat Firestore db). */
async function seed(env, fn) {
  await env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
}

/** Admins, doctors and one active + one pending profile for every partner role. */
async function seedBase(env) {
  await seed(env, async (db) => {
    await db.collection("admins").doc(U.director).set({ role: "director" });
    await db.collection("admins").doc(U.hr).set({ role: "hr" });
    await db.collection("admins").doc(U.support).set({ role: "support" });
    await db.collection("admins").doc(U.finance).set({ role: "finance" });
    await db.collection("doctors").doc(U.doctor).set({ status: "active", roles: ["doctor"], name: "Dr A", fee: 500 });
    await db.collection("doctors").doc(U.otherDoctor).set({ status: "active", roles: ["doctor"] });
    await db.collection("doctors").doc(U.pendingDoctor).set({ status: "pending", roles: ["doctor"] });
    for (const [role, coll] of Object.entries(ROLES)) {
      const extra = role === "hospital" ? { hospitalId: "hosp-1" } : {};
      await db.collection(coll).doc(active(role)).set({ status: "active", isVerified: true, documents: {}, ...extra });
      await db.collection(coll).doc(other(role)).set({ status: "active", isVerified: true, documents: {}, ...extra });
      await db.collection(coll).doc(pending(role)).set({ status: "pending", isVerified: false, documents: {}, ...extra });
    }
    // The doctor-role partner identity docs that every partner app signup writes.
  });
}

/** Named auth contexts. */
function memo(ctx) {
  // ctx.firestore() re-applies useEmulator() on every call, which throws once
  // Firestore has started; cache the instances per context.
  let f, s;
  const ff = ctx.firestore.bind(ctx);
  ctx.firestore = (...args) => (f = f || ff(...args));
  if (ctx.storage) { const sf = ctx.storage.bind(ctx); ctx.storage = (...args) => (s = s || sf(...args)); }
  return ctx;
}
function actors(env) {
  const a = (uid, claims) => memo(env.authenticatedContext(uid, claims));
  return {
    anon: memo(env.unauthenticatedContext()),
    patient: a(U.patient),
    otherPatient: a(U.otherPatient),
    doctor: a(U.doctor),
    otherDoctor: a(U.otherDoctor),
    pendingDoctor: a(U.pendingDoctor),
    director: a(U.director),
    hr: a(U.hr),
    support: a(U.support),
    finance: a(U.finance),
    stranger: a(U.stranger),
    guestFor: (apptId) => a(U.guest, { guestAppointmentId: apptId }),
    partner: (role, which = "active") => a(which === "pending" ? pending(role) : which === "other" ? other(role) : active(role)),
  };
}

const db = (ctx) => ctx.firestore();
const doc = (ctx, p) => ctx.firestore().doc(p);

// Server timestamp sentinel (compat SDK) for rules comparing against request.time.
function serverTs() {
  const app = require("firebase/compat/app").default;
  require("firebase/compat/firestore");
  return app.firestore.FieldValue.serverTimestamp();
}
function delField() {
  const app = require("firebase/compat/app").default;
  require("firebase/compat/firestore");
  return app.firestore.FieldValue.delete();
}
function arrayUnion(...v) {
  const app = require("firebase/compat/app").default;
  require("firebase/compat/firestore");
  return app.firestore.FieldValue.arrayUnion(...v);
}

const ok = (p) => assertSucceeds(p);
const no = (p) => assertFails(p);

module.exports = {
  setup, seed, seedBase, actors, db, doc, ok, no, serverTs, delField, arrayUnion,
  ROLES, U, active, pending, other, readRules, ROOT,
};
