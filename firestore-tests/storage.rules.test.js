/**
 * Area 10: storage.rules — partner `{role}_documents/{uid}/...` and
 * `doctors/{uid}/...`.
 *
 * Needs BOTH the Firestore and Storage emulators (storage rules call
 * firestore.get()/exists() on the profile docs and admins/{uid}).
 */
const { test, before, beforeEach, after } = require("node:test");
const H = require("./helpers/env");
const { ok, no, ROLES, U, active, pending } = H;

let env, A;
before(async () => { env = await H.setup("storage", { storage: true }); A = H.actors(env); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await H.seedBase(env);
  await H.seed(env, async (db) => {
    await db.doc("lab_profiles/lab-suspended").set({ status: "suspended", isVerified: true });
  });
});

const MB = 1024 * 1024;
const bytes = (n = 16) => new Uint8Array(n);
const put = (ctx, p, contentType, size = 16) => ctx.storage().ref(p).put(bytes(size), { contentType });
const get = (ctx, p) => ctx.storage().ref(p).getMetadata();
const del = (ctx, p) => ctx.storage().ref(p).delete();
const seedFile = (p, contentType = "application/pdf") =>
  env.withSecurityRulesDisabled(async (ctx) => { await ctx.storage().ref(p).put(bytes(), { contentType }); });

for (const role of Object.keys(ROLES)) {
  const base = (uid) => `${role}_documents/${uid}`;
  const owner = () => A.partner(role);
  const pendingOwner = () => A.partner(role, "pending");

  test(`[${role}] owner with NO profile doc yet can upload any file (registration)`, async () => {
    const uid = `${role}-noprofile`;
    const c = env.authenticatedContext(uid);
    await ok(put(c, `${base(uid)}/anything.pdf`, "application/pdf"));
    await ok(put(c, `${base(uid)}/id_card.jpg`, "image/jpeg"));
  });
  test(`[${role}] pending owner can write any document type (jpg and pdf)`, async () => {
    await ok(put(pendingOwner(), `${base(pending(role))}/license.pdf`, "application/pdf"));
    await ok(put(pendingOwner(), `${base(pending(role))}/license.jpg`, "image/jpeg"));
    await ok(put(pendingOwner(), `${base(pending(role))}/other_doc_1.pdf`, "application/pdf"));
  });
  test(`[${role}] active owner can only write other_doc_[1-5].(jpg|pdf)`, async () => {
    const b = base(active(role));
    for (const n of [1, 2, 3, 4, 5]) {
      await ok(put(owner(), `${b}/other_doc_${n}.pdf`, "application/pdf"));
      await ok(put(owner(), `${b}/other_doc_${n}.jpg`, "image/jpeg"));
    }
  });
  test(`[${role}] active owner cannot overwrite verified fixed documents`, async () => {
    const b = base(active(role));
    await no(put(owner(), `${b}/license.pdf`, "application/pdf"));
    await no(put(owner(), `${b}/gst_certificate.jpg`, "image/jpeg"));
  });
  test(`[${role}] active owner cannot write out-of-range / odd other_doc names`, async () => {
    const b = base(active(role));
    await no(put(owner(), `${b}/other_doc_0.pdf`, "application/pdf"));
    await no(put(owner(), `${b}/other_doc_6.pdf`, "application/pdf"));
    await no(put(owner(), `${b}/other_doc_1.png`, "image/png"));
    await no(put(owner(), `${b}/other_doc_10.pdf`, "application/pdf"));
    await no(put(owner(), `${b}/sub/other_doc_1.pdf`, "application/pdf"));
  });
  test(`[${role}] content type and size limits apply (<20MB, image/pdf only)`, async () => {
    const b = base(pending(role));
    await no(put(pendingOwner(), `${b}/x.pdf`, "text/plain"));
    await no(put(pendingOwner(), `${b}/x.pdf`, "application/zip"));
    await no(put(pendingOwner(), `${b}/big.pdf`, "application/pdf", 20 * MB));
    await ok(put(pendingOwner(), `${b}/just_under.pdf`, "application/pdf", 20 * MB - 1));
  });
  test(`[${role}] active owner other_doc still obeys the content-type check`, () =>
    no(put(owner(), `${base(active(role))}/other_doc_1.pdf`, "text/html")));
  test(`[${role}] read: owner and admin only`, async () => {
    const p = `${base(active(role))}/license.pdf`;
    await seedFile(p);
    await ok(get(owner(), p));
    await ok(get(A.director, p));
    await no(get(A.stranger, p));
    await no(get(A.partner(role, "other"), p));
    await no(get(A.patient, p));
    await no(get(A.anon, p));
  });
  test(`[${role}] others cannot write into the owner's folder (incl. admin)`, async () => {
    const p = `${base(pending(role))}/license.pdf`;
    await no(put(A.stranger, p, "application/pdf"));
    await no(put(A.partner(role, "other"), p, "application/pdf"));
    await no(put(A.director, p, "application/pdf"));
    await no(put(A.anon, p, "application/pdf"));
  });
  test(`[${role}] delete: admin may delete; owner (active or pending) and others may not`, async () => {
    const pa = `${base(active(role))}/other_doc_1.pdf`;
    const pp = `${base(pending(role))}/other_doc_1.pdf`;
    await seedFile(pa);
    await seedFile(pp);
    await no(del(owner(), pa));
    await no(del(A.stranger, pa));
    await no(del(A.anon, pa));
    await ok(del(A.director, pa));
    await ok(del(A.hr, pp));
  });
}

test("[lab] a suspended profile is not 'active': owner may write any file", () =>
  ok(put(env.authenticatedContext("lab-suspended"), "lab_documents/lab-suspended/lab_license.pdf", "application/pdf")));

// ── doctors/{uid} ──────────────────────────────────────────────────────────
test("[doctors] docs: owner and admin can read; others cannot", async () => {
  const p = `doctors/${U.doctor}/docs/license.pdf`;
  await seedFile(p);
  await ok(get(A.doctor, p));
  await ok(get(A.director, p));
  await no(get(A.stranger, p));
  await no(get(A.patient, p));
  await no(get(A.otherDoctor, p));
  await no(get(A.anon, p));
});
test("[doctors] docs: owner can upload pdf/image; others cannot write", async () => {
  const p = `doctors/${U.doctor}/docs/license.pdf`;
  await ok(put(A.doctor, p, "application/pdf"));
  await ok(put(A.doctor, `doctors/${U.doctor}/docs/scan.jpg`, "image/jpeg"));
  await no(put(A.otherDoctor, p, "application/pdf"));
  await no(put(A.stranger, p, "application/pdf"));
  await no(put(A.director, p, "application/pdf"));
  await no(put(A.anon, p, "application/pdf"));
});
test("[doctors] docs: content type and size limits (<10MB, image/pdf only)", async () => {
  const p = `doctors/${U.doctor}/docs/license.pdf`;
  await no(put(A.doctor, p, "text/plain"));
  await no(put(A.doctor, p, "application/pdf", 10 * MB));
  await ok(put(A.doctor, p, "application/pdf", 10 * MB - 1));
});
test("[doctors] profile.jpg is public to read; only the owner writes", async () => {
  const p = `doctors/${U.doctor}/profile.jpg`;
  await ok(put(A.doctor, p, "image/jpeg"));
  await ok(get(A.anon, p));
  await ok(get(A.stranger, p));
  await no(put(A.stranger, p, "image/jpeg"));
});
test("[doctors] profile.jpg write is limited to images < 5MB", async () => {
  const p = `doctors/${U.doctor}/profile.jpg`;
  await no(put(A.doctor, p, "application/pdf"));
  await no(put(A.doctor, p, "image/jpeg", 5 * MB));
});
test("[doctors] legit upload paths stay allowed; stray paths are not", async () => {
  await ok(put(A.doctor, `doctors/${U.doctor}/docs/other_doc_1.jpg`, "image/jpeg"));
  await ok(put(A.doctor, `doctors/${U.doctor}/signature.png`, "image/png"));
  await no(put(A.doctor, `doctors/${U.doctor}/signature.png`, "application/pdf"));
  await no(put(A.doctor, `doctors/${U.doctor}/stray.pdf`, "application/pdf"));
  await no(put(A.stranger, `doctors/${U.doctor}/docs/x.jpg`, "image/jpeg"));
});
test("[doctors] signature.png is readable by any signed-in user but not anonymous", async () => {
  const p = `doctors/${U.doctor}/signature.png`;
  await seedFile(p, "image/png");
  await ok(get(A.patient, p));
  await ok(get(A.stranger, p));
  await no(get(A.anon, p));
  await no(put(A.stranger, p, "image/png"));
});
