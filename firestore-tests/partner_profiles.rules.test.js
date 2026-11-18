/**
 * Area 4: partner profile collections (+ doctors).
 * Rules: lab/pharmacy/equipment/ambulance/caregiver/physiotherapist/
 * counsellor/nutritionist/hospital `*_profiles` and `doctors`.
 *
 * Tests marked `todo` assert the INTENDED (owner-approved) behaviour where the
 * current rules do not enforce it; they are reported as rule/intent mismatches
 * and do not fail the run (see README "Known mismatches").
 */
const { test, before, beforeEach, after } = require("node:test");
const H = require("./helpers/env");
const { ok, no, doc, ROLES, U, active, pending, other } = H;

let env, A;
before(async () => { env = await H.setup("partner_profiles"); A = H.actors(env); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await H.seedBase(env); });

// Required documents per role (activationHasDocs keys in firestore.rules).
const REQ_DOCS = {
  lab: ["lab_license", "maridi_certificate", "lab_technician_details", "pathologist_registration", "gst_certificate"],
  pharmacy: ["pharmacy_license", "pharmacist_registration", "trade_license", "gst_certificate"],
  equipment: ["pharmacy_license", "pharmacist_registration", "trade_license", "gst_certificate"],
  ambulance: ["driver_license", "vehicle_fitness", "vehicle_registration", "vehicle_insurance", "pollution_certificate"],
  caregiver: ["caregiver_id", "certificates"],
  physiotherapist: ["ug_certificate", "renewal_certificate", "registration_state", "registration_national"],
  counsellor: ["counsellor_id", "certificates"],
  nutritionist: ["ug_certificate", "registration_certificate"],
  hospital: ["dmho_license", "fire_certificate", "maridi_certificate", "gvmc_certificate", "pollution_certificate", "trade_license", "gst_certificate"],
};
// Operational (presence / settings) keys an ACTIVE owner may still write.
const OPERATIONAL = {
  lab: { acceptingBookings: false, whatsappOptIn: true },
  pharmacy: { acceptingOrders: false, whatsappOptIn: true },
  equipment: { acceptingOrders: false, whatsappOptIn: true },
  ambulance: { isOnline: true, lastHeartbeat: new Date(), speedKmh: 10, ratePerTrip: 100 },
  caregiver: { isOnDuty: true },
  physiotherapist: { isOnline: true, lastHeartbeat: new Date(), availability: { mon: [] } },
  counsellor: { isOnline: true, lastHeartbeat: new Date(), availability: { mon: [] } },
  nutritionist: { isOnline: true, availability: { mon: [] }, isOnlineAvailable: true, isInPersonAvailable: false },
  hospital: { whatsappOptIn: true, whatsappPhone: "9999999999", language: "en" },
};
const HAS_AVAILABILITY = ["physiotherapist", "counsellor", "nutritionist"];

for (const [role, coll] of Object.entries(ROLES)) {
  const P = (ctx, uid) => doc(ctx, `${coll}/${uid}`);
  const newUid = `${role}-new`;
  const docsMap = Object.fromEntries(REQ_DOCS[role].map((k) => [k, { url: "u" }]));

  // ── create ──────────────────────────────────────────────────────────────
  test(`[${role}] create: owner with status pending + isVerified false is allowed`, () =>
    ok(P(env.authenticatedContext(newUid), newUid).set({ status: "pending", isVerified: false })));
  test(`[${role}] create: status 'active' is rejected`, () =>
    no(P(env.authenticatedContext(newUid), newUid).set({ status: "active", isVerified: false })));
  if (role === "hospital") {
    test(`[${role}] create: isVerified true is rejected`, () =>
      no(P(env.authenticatedContext(newUid), newUid).set({ status: "pending", isVerified: true })));
  } else {
    test(`[${role}] create: isVerified true is rejected`, () =>
      no(P(env.authenticatedContext(newUid), newUid).set({ status: "pending", isVerified: true })));
    test(`[${role}] create: missing isVerified is rejected`, () =>
      no(P(env.authenticatedContext(newUid), newUid).set({ status: "pending" })));
  }
  test(`[${role}] create: cannot create someone else's profile`, () =>
    no(P(A.stranger, newUid).set({ status: "pending", isVerified: false })));
  test(`[${role}] create: anonymous rejected`, () =>
    no(P(A.anon, newUid).set({ status: "pending", isVerified: false })));

  // ── read ────────────────────────────────────────────────────────────────
  test(`[${role}] read: owner, HR and any signed-in (active profile) allowed; anon denied`, async () => {
    await ok(P(A.partner(role), active(role)).get());
    await ok(P(A.stranger, active(role)).get());
    await ok(P(A.hr, pending(role)).get());
    await no(P(A.anon, active(role)).get());
  });
  test(`[${role}] read: a pending profile is hidden from strangers`, () =>
    no(P(A.stranger, pending(role)).get()));
  test(`[${role}] read: pending owner can read own profile`, () =>
    ok(P(A.partner(role, "pending"), pending(role)).get()));

  // ── pending owner ───────────────────────────────────────────────────────
  test(`[${role}] pending owner can write documents, resubmittedAt/Note and staffDetails`, async () => {
    const ref = P(A.partner(role, "pending"), pending(role));
    await ok(ref.update({ documents: { [REQ_DOCS[role][0]]: { url: "u" } } }));
    await ok(ref.update({ resubmittedAt: new Date(), resubmitNote: "fixed" }));
    await ok(ref.update({ staffDetails: [{ name: "A" }] }));
  });
  for (const k of ["status", "documentVerification", "documentsVerified"]) {
    test(`[${role}] pending owner cannot write '${k}'`, () =>
      no(P(A.partner(role, "pending"), pending(role)).update({ [k]: k === "status" ? "active" : {} })));
  }
  if (role === "hospital") {
    test(`[${role}] pending owner cannot self-set isVerified`, () =>
      no(P(A.partner(role, "pending"), pending(role)).update({ isVerified: true })));
  } else {
    test(`[${role}] pending owner cannot self-set isVerified`, () =>
      no(P(A.partner(role, "pending"), pending(role)).update({ isVerified: true })));
  }

  // ── active owner ────────────────────────────────────────────────────────
  test(`[${role}] active owner can write pendingChanges / hasPendingChanges / updatedAt`, () =>
    ok(P(A.partner(role), active(role)).update({ pendingChanges: { name: "New" }, hasPendingChanges: true, updatedAt: new Date() })));
  test(`[${role}] active owner can rotate push token keys`, () =>
    ok(P(A.partner(role), active(role)).update({ fcmToken: "tok", fcmTokenUpdatedAt: new Date(), fcmPlatform: "android" })));
  test(`[${role}] active owner can write presence/settings keys`, () =>
    ok(P(A.partner(role), active(role)).update(OPERATIONAL[role])));
  test(`[${role}] fcmToken >= 4096 chars is rejected`, () =>
    no(P(A.partner(role), active(role)).update({ fcmToken: "x".repeat(4096) })));
  test(`[${role}] fcmToken that is not a string is rejected`, () =>
    no(P(A.partner(role), active(role)).update({ fcmToken: 123 })));
  test(`[${role}] fcmPlatform >= 32 chars is rejected`, () =>
    no(P(A.partner(role), active(role)).update({ fcmPlatform: "p".repeat(32) })));
  for (const [k, v] of [["documents", { x: 1 }], ["status", "suspended"], ["isVerified", false], ["documentVerification", { x: true }], ["documentsVerified", true], ["rating", 5], ["name", "Hacked"]]) {
    test(`[${role}] active owner cannot write '${k}'`, () =>
      no(P(A.partner(role), active(role)).update({ [k]: v })));
  }
  if (HAS_AVAILABILITY.includes(role)) {
    test(`[${role}] active owner can write 'availability'`, () =>
      ok(P(A.partner(role), active(role)).update({ availability: { mon: ["10:00"] } })));
  } else {
    test(`[${role}] active owner cannot write 'availability' (not specified for this role)`, () =>
      no(P(A.partner(role), active(role)).update({ availability: { mon: [] } })));
  }
  test(`[${role}] another partner / stranger cannot update this profile`, async () => {
    await no(P(A.partner(role, "other"), active(role)).update({ updatedAt: new Date() }));
    await no(P(A.stranger, active(role)).update({ updatedAt: new Date() }));
    await no(P(A.anon, active(role)).update({ updatedAt: new Date() }));
  });

  // ── admin-only keys ─────────────────────────────────────────────────────
  test(`[${role}] HR may write documentVerification but cannot change status`, async () => {
    await ok(P(A.hr, pending(role)).update({ documentVerification: { x: true }, documentsVerified: false, updatedAt: new Date(), updatedBy: U.hr }));
    await no(P(A.hr, pending(role)).update({ status: "active", documents: docsMap }));
  });
  test(`[${role}] support / finance admins cannot modify the profile`, async () => {
    await no(P(A.support, pending(role)).update({ documentVerification: { x: true } }));
    await no(P(A.finance, pending(role)).update({ status: "active", documents: docsMap }));
  });
  test(`[${role}] Director can activate only when required documents are on file`, async () => {
    await no(P(A.director, pending(role)).update({ status: "active" }));
    await ok(P(A.director, pending(role)).update({ status: "active", documents: docsMap }));
  });
  test(`[${role}] only Director can delete a profile`, async () => {
    await no(P(A.partner(role), active(role)).delete());
    await no(P(A.hr, active(role)).delete());
    await ok(P(A.director, active(role)).delete());
  });
}

// ── doctors collection ──────────────────────────────────────────────────────
const D = (ctx, uid) => doc(ctx, `doctors/${uid}`);
test("[doctors] create: owner with status pending is allowed", () =>
  ok(D(env.authenticatedContext("doc-new"), "doc-new").set({ status: "pending", roles: ["doctor"], rating: 0 })));
test("[doctors] create: status active is rejected", () =>
  no(D(env.authenticatedContext("doc-new"), "doc-new").set({ status: "active", roles: ["doctor"] })));
test("[doctors] create: roles containing 'admin' is rejected", () =>
  no(D(env.authenticatedContext("doc-new"), "doc-new").set({ status: "pending", roles: ["doctor", "admin"] })));
test("[doctors] create: forged rating is rejected", () =>
  no(D(env.authenticatedContext("doc-new"), "doc-new").set({ status: "pending", rating: 5 })));
test("[doctors] create: for another uid is rejected", () =>
  no(D(A.stranger, "doc-new").set({ status: "pending" })));
test("[doctors] read: signed-in can see active doctors, not pending ones", async () => {
  await ok(D(A.stranger, U.doctor).get());
  await no(D(A.stranger, U.pendingDoctor).get());
  await ok(D(A.pendingDoctor, U.pendingDoctor).get());
  await no(D(A.anon, U.doctor).get());
});
test("[doctors] active owner cannot change status / rating / earnings", async () => {
  await no(D(A.doctor, U.doctor).update({ status: "suspended" }));
  await no(D(A.doctor, U.doctor).update({ rating: 5 }));
  await no(D(A.doctor, U.doctor).update({ earnings: 1e6 }));
  await no(D(A.doctor, U.doctor).update({ totalConsultations: 99 }));
});
test("[doctors] active owner cannot edit patient-visible fields directly", async () => {
  await no(D(A.doctor, U.doctor).update({ name: "X" }));
  await no(D(A.doctor, U.doctor).update({ fee: 1 }));
});
test("[doctors] active owner can write pendingChanges, availability and push token", async () => {
  await ok(D(A.doctor, U.doctor).update({ pendingChanges: { fee: 600 }, hasPendingChanges: true, updatedAt: new Date() }));
  await ok(D(A.doctor, U.doctor).update({ availability: { mon: [] } }));
  await ok(D(A.doctor, U.doctor).update({ fcmToken: "t", fcmTokenUpdatedAt: new Date(), fcmPlatform: "ios" }));
});
test("[doctors] active owner cannot self-promote roles to include 'admin'", () =>
  no(D(A.doctor, U.doctor).update({ roles: ["doctor", "admin"] })));
test("[doctors] active owner cannot write documents", () =>
  no(D(A.doctor, U.doctor).update({ documents: { license: { url: "swap" } } })));
test("[doctors] active owner cannot write isVerified / documentVerification", async () => {
  await no(D(A.doctor, U.doctor).update({ isVerified: true }));
  await no(D(A.doctor, U.doctor).update({ documentVerification: { x: true } }));
});
test("[doctors] active owner cannot write verification/status-style keys", async () => {
  for (const k of ["isVerified", "documentVerification", "documentsVerified", "verificationStatus", "documentLabels", "type"])
    await no(D(A.doctor, U.doctor).update({ [k]: true }));
});
test("[doctors] active owner: legitimate app writes are allowed", async () => {
  await ok(D(A.doctor, U.doctor).update({ isOnline: true, acceptingConsultations: true, lastHeartbeat: new Date() }));
  await ok(D(A.doctor, U.doctor).update({ isOnline: false }));
  await ok(D(A.doctor, U.doctor).update({ location: { latitude: 1, longitude: 2 }, geohash: "abcde12", geohash5: "abcde", lastLocationUpdate: new Date() }));
  await ok(D(A.doctor, U.doctor).update({ "availability.slotDuration": 30, "availability.blockedSlots": {}, "availability.updatedAt": new Date() }));
  await ok(D(A.doctor, U.doctor).update({ "pendingChanges.photoUrl": "u", hasPendingChanges: true, updatedAt: new Date() }));
  await ok(D(A.doctor, U.doctor).update({ whatsappOptIn: true, whatsappPhone: "+91", language: "en", whatsappOptInUpdatedAt: new Date() }));
});
test("[doctors] active owner can append a partner role (role switcher) but not remove/admin", async () => {
  await ok(D(A.doctor, U.doctor).update({ roles: ["doctor", "lab"], termsAccepted: true, termsAcceptedAt: new Date() }));
  await no(D(A.doctor, U.doctor).update({ roles: ["lab"] }));
  await no(D(A.doctor, U.doctor).update({ roles: ["doctor", "admin"] }));
  await no(D(A.doctor, U.doctor).update({ roles: "doctor" }));
});
test("[doctors] pending owner can edit profile + documents but not status", async () => {
  await ok(D(A.pendingDoctor, U.pendingDoctor).update({ name: "Dr P", documents: { license: { url: "u" } } }));
  await no(D(A.pendingDoctor, U.pendingDoctor).update({ status: "active" }));
});
test("[doctors] another doctor / stranger cannot update", async () => {
  await no(D(A.otherDoctor, U.doctor).update({ updatedAt: new Date() }));
  await no(D(A.stranger, U.doctor).update({ updatedAt: new Date() }));
});
test("[doctors] admin can update and delete; owner cannot delete", async () => {
  await no(D(A.doctor, U.doctor).delete());
  await ok(D(A.director, U.doctor).update({ status: "suspended" }));
  await ok(D(A.director, U.doctor).delete());
});
