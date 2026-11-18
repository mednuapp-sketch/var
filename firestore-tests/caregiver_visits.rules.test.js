/**
 * Area 5: caregiver_visits (pool claim, decline via declinedBy, provider
 * cancel-after-accept release branch). Rules: `match /caregiver_visits/{visitId}`.
 */
const { test, before, beforeEach, after } = require("node:test");
const H = require("./helpers/env");
const { ok, no, doc, U, arrayUnion, delField, active, pending, other } = H;

let env, A;
before(async () => { env = await H.setup("caregiver_visits"); A = H.actors(env); });
after(async () => { await env.cleanup(); });

const CG = active("caregiver");
const visit = (over = {}) => ({
  patientId: U.patient, patientName: "P", type: "nursing", address: "addr",
  fare: 500, status: "scheduled", caregiverId: null, createdAt: new Date(), ...over,
});

beforeEach(async () => {
  await env.clearFirestore();
  await H.seedBase(env);
  await H.seed(env, async (db) => {
    const c = db.collection("caregiver_visits");
    await c.doc("pool").set(visit());
    await c.doc("pinned").set(visit({ caregiverId: CG }));
    await c.doc("accepted").set(visit({ caregiverId: CG, acceptedAt: new Date(), declinedBy: [] }));
    await c.doc("checkedIn").set(visit({ caregiverId: CG, acceptedAt: new Date(), status: "checkedIn" }));
    await c.doc("others").set(visit({ caregiverId: other("caregiver"), acceptedAt: new Date() }));
    await c.doc("accepted").collection("tasks").doc("t1").set({ title: "Wash", isDone: false });
    await c.doc("accepted").collection("notes").doc("n0").set({ text: "x", authorId: CG });
  });
});
const v = (ctx, id) => doc(ctx, `caregiver_visits/${id}`);
const cg = () => A.partner("caregiver");

// ── read ──────────────────────────────────────────────────────────────────
test("read: patient, assigned caregiver, admin allowed", async () => {
  await ok(v(A.patient, "accepted").get());
  await ok(v(cg(), "accepted").get());
  await ok(v(A.director, "accepted").get());
});
test("read: active caregiver can read an unclaimed pool visit", () => ok(v(cg(), "pool").get()));
test("read: pending caregiver, stranger, other patient, anon cannot read the pool", async () => {
  await no(v(A.partner("caregiver", "pending"), "pool").get());
  await no(v(A.stranger, "pool").get());
  await no(v(A.otherPatient, "pool").get());
  await no(v(A.anon, "pool").get());
});
test("read: a different caregiver cannot read a visit claimed by someone else", () =>
  no(v(cg(), "others").get()));

// ── pool claim ────────────────────────────────────────────────────────────
test("claim: active caregiver can claim an unclaimed scheduled visit (status stays scheduled)", () =>
  ok(v(cg(), "pool").update({ caregiverId: CG, status: "scheduled", acceptedAt: new Date(), updatedAt: new Date() })));
test("claim: pending caregiver cannot claim", () =>
  no(v(A.partner("caregiver", "pending"), "pool").update({ caregiverId: pending("caregiver") })));
test("claim: cannot claim on behalf of another uid", () =>
  no(v(cg(), "pool").update({ caregiverId: other("caregiver") })));
test("claim: claim-and-complete / claim-and-checkIn in one write is rejected", async () => {
  await no(v(cg(), "pool").update({ caregiverId: CG, status: "completed" }));
  await no(v(cg(), "pool").update({ caregiverId: CG, status: "checkedIn" }));
});
test("claim: cannot rewrite immutable fields (fare/patientId) while claiming", async () => {
  await no(v(cg(), "pool").update({ caregiverId: CG, fare: 1 }));
  await no(v(cg(), "pool").update({ caregiverId: CG, patientId: U.otherPatient }));
});
test("claim: a second caregiver cannot take an already-claimed visit", () =>
  no(v(A.partner("caregiver", "other"), "accepted").update({ caregiverId: other("caregiver") })));

// ── pool decline (declinedBy) ─────────────────────────────────────────────
test("decline pool: adds own uid to declinedBy (+updatedAt) only", () =>
  ok(v(cg(), "pool").update({ declinedBy: arrayUnion(CG), updatedAt: new Date() })));
test("decline pool: pending caregiver cannot", () =>
  no(v(A.partner("caregiver", "pending"), "pool").update({ declinedBy: arrayUnion(pending("caregiver")) })));
test("decline pool: declinedBy without own uid is rejected", () =>
  no(v(cg(), "pool").update({ declinedBy: arrayUnion("someone-else") })));
test("decline pool: extra keys (status) in the same write are rejected", () =>
  no(v(cg(), "pool").update({ declinedBy: arrayUnion(CG), status: "cancelled" })));
test("decline pool: patient / stranger cannot decline", async () => {
  await no(v(A.patient, "pool").update({ declinedBy: arrayUnion(U.patient) }));
  await no(v(A.stranger, "pool").update({ declinedBy: arrayUnion(U.stranger) }));
});

// ── pinned release (not yet accepted) ─────────────────────────────────────
test("decline pinned: release back to pool (caregiverId null + declinedBy)", () =>
  ok(v(cg(), "pinned").update({ caregiverId: null, declinedBy: arrayUnion(CG), updatedAt: new Date() })));
test("decline pinned: without adding self to declinedBy is rejected", () =>
  no(v(cg(), "pinned").update({ caregiverId: null, declinedBy: [] })));

// ── provider cancel-after-accept release branch ───────────────────────────
const release = (over = {}) => ({
  caregiverId: null, acceptedAt: delField(), declinedBy: arrayUnion(CG),
  providerCancelReason: "unwell", updatedAt: new Date(), ...over,
});
test("cancel-after-accept: accepted+scheduled visit is released to the pool with a reason", () =>
  ok(v(cg(), "accepted").update(release())));
test("cancel-after-accept: reason longer than 200 chars is rejected", () =>
  no(v(cg(), "accepted").update(release({ providerCancelReason: "r".repeat(201) }))));
test("cancel-after-accept: reason exactly 200 chars is allowed", () =>
  ok(v(cg(), "accepted").update(release({ providerCancelReason: "r".repeat(200) }))));
test("cancel-after-accept: missing or non-string reason is rejected", async () => {
  const d = release(); delete d.providerCancelReason;
  await no(v(cg(), "accepted").update(d));
  await no(v(cg(), "accepted").update(release({ providerCancelReason: 5 })));
});
test("cancel-after-accept: acceptedAt must be cleared", () =>
  no(v(cg(), "accepted").update(release({ acceptedAt: new Date() }))));
test("cancel-after-accept: uid must be added to declinedBy", () =>
  no(v(cg(), "accepted").update(release({ declinedBy: [] }))));
test("cancel-after-accept: not allowed once checked in", () =>
  no(v(cg(), "checkedIn").update(release())));
test("cancel-after-accept: status may not change in the same write", () =>
  no(v(cg(), "accepted").update(release({ status: "cancelled" }))));
test("cancel-after-accept: a different caregiver cannot release someone else's visit", () =>
  no(v(A.partner("caregiver", "other"), "accepted").update(release({ declinedBy: arrayUnion(other("caregiver")) }))));
test("cancel-after-accept: patient cannot use the release branch", () =>
  no(v(A.patient, "accepted").update(release())));

// ── owner workflow ────────────────────────────────────────────────────────
test("owner: scheduled -> checkedIn -> completed is allowed", async () => {
  await ok(v(cg(), "accepted").update({ status: "checkedIn" }));
  await ok(v(cg(), "checkedIn").update({ status: "completed" }));
});
test("owner: cannot jump scheduled -> completed", () => no(v(cg(), "accepted").update({ status: "completed" })));
test("owner: cannot change fare or reassign caregiverId to another uid", async () => {
  await no(v(cg(), "accepted").update({ fare: 1 }));
  await no(v(cg(), "accepted").update({ caregiverId: other("caregiver") }));
});
test("patient and stranger cannot update workflow fields; patient cannot cancel directly", async () => {
  await no(v(A.patient, "accepted").update({ status: "cancelled" }));
  await no(v(A.stranger, "accepted").update({ status: "checkedIn" }));
});
test("create/delete are admin only", async () => {
  await no(v(cg(), "new").set(visit()));
  await no(v(A.patient, "new").set(visit()));
  await ok(v(A.director, "new").set(visit()));
  await no(v(cg(), "accepted").delete());
});

// ── subcollections ────────────────────────────────────────────────────────
test("tasks: assigned caregiver may toggle isDone only", async () => {
  const t = doc(cg(), "caregiver_visits/accepted/tasks/t1");
  await ok(t.update({ isDone: true }));
  await no(t.update({ title: "Rewritten" }));
  await no(doc(A.patient, "caregiver_visits/accepted/tasks/t1").update({ isDone: true }));
});
test("notes: assigned caregiver can append; patient cannot; nobody edits", async () => {
  await ok(doc(cg(), "caregiver_visits/accepted/notes/n1").set({ text: "ok", authorId: CG }));
  await no(doc(A.patient, "caregiver_visits/accepted/notes/n2").set({ text: "x" }));
  await no(doc(cg(), "caregiver_visits/accepted/notes/n0").update({ text: "edited" }));
  await ok(doc(A.patient, "caregiver_visits/accepted/notes/n0").get());
});
