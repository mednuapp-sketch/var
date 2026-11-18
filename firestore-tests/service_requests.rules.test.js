/**
 * Area 3: service_requests. Rules: `match /service_requests/{requestId}`.
 */
const { test, before, beforeEach, after } = require("node:test");
const H = require("./helpers/env");
const { ok, no, doc, U } = H;

let env, A;
before(async () => { env = await H.setup("service_requests"); A = H.actors(env); });
after(async () => { await env.cleanup(); });

const base = (over = {}) => {
  const d = {
    patientId: U.patient, type: "diagnostics", status: "pending",
    amount: 500, fee: 500, price: 500, total: 500, totalAmount: 500,
    paymentId: "pay_1", paymentStatus: "paid",
    preferredDate: "2026-12-01", preferredTime: "10:00 AM", createdAt: new Date(), ...over,
  };
  // The Firestore SDK rejects `undefined` values client-side; drop them.
  for (const k of Object.keys(d)) if (d[k] === undefined) delete d[k];
  return d;
};

beforeEach(async () => {
  await env.clearFirestore();
  await H.seedBase(env);
  await H.seed(env, async (db) => {
    const c = db.collection("service_requests");
    await c.doc("diag").set(base());
    await c.doc("accepted").set(base({ status: "accepted" }));
    await c.doc("inprog").set(base({ status: "in_progress" }));
    await c.doc("completed").set(base({ status: "completed" }));
    await c.doc("physioPending").set(base({ type: "physiotherapy" }));
    await c.doc("physioAccepted").set(base({ type: "physiotherapy", status: "accepted" }));
    await c.doc("physioInProg").set(base({ type: "physiotherapy", status: "in_progress" }));
    await c.doc("counsAccepted").set(base({ type: "counselling", status: "accepted" }));
  });
});
const sr = (ctx, id) => doc(ctx, `service_requests/${id}`);

// ── create ────────────────────────────────────────────────────────────────
test("patient can create a diagnostics request for themselves", () =>
  ok(sr(A.patient, "new").set(base())));
test("patient cannot create a request for another patient", () =>
  no(sr(A.patient, "new").set(base({ patientId: U.otherPatient }))));
test("anonymous cannot create", () => no(sr(A.anon, "new").set(base())));
test("ambulance pay_after_trip create is allowed", () =>
  ok(sr(A.patient, "new").set(base({ type: "ambulance", paymentStatus: "pay_after_trip", paymentId: undefined }))));
test("ambulance not_required create is allowed", () =>
  ok(sr(A.patient, "new").set(base({ type: "ambulance", paymentStatus: "not_required", paymentId: undefined }))));
test("ambulance create with paymentStatus 'paid' is blocked", () =>
  no(sr(A.patient, "new").set(base({ type: "ambulance", paymentStatus: "paid", paymentId: undefined }))));
for (const k of ["amountDue", "fareFinal", "paymentId", "paidAt", "platformFee"]) {
  test(`ambulance create with client-written '${k}' is blocked`, () => {
    const d = base({ type: "ambulance", paymentStatus: "pay_after_trip" });
    delete d.paymentId;
    d[k] = 100;
    return no(sr(A.patient, "new").set(d));
  });
}

// ── read ──────────────────────────────────────────────────────────────────
test("owner, active doctor and admin can read; stranger/anon cannot", async () => {
  await ok(sr(A.patient, "diag").get());
  await ok(sr(A.doctor, "diag").get());
  await ok(sr(A.director, "diag").get());
  await no(sr(A.otherPatient, "diag").get());
  await no(sr(A.pendingDoctor, "diag").get());
  await no(sr(A.anon, "diag").get());
});

// ── patient update: cancel only ───────────────────────────────────────────
test("patient can cancel a pending request (cancelledBy patient)", () =>
  ok(sr(A.patient, "diag").update({ status: "cancelled", cancelledBy: "patient", cancelReason: "x", updatedAt: new Date() })));
test("patient can cancel an accepted request (refund flow is server-side)", () =>
  ok(sr(A.patient, "accepted").update({ status: "cancelled", cancelledBy: "patient" })));
test("patient cancel with cancelledBy 'provider' is rejected", () =>
  no(sr(A.patient, "diag").update({ status: "cancelled", cancelledBy: "provider" })));
test("patient cannot cancel an in_progress or completed request", async () => {
  await no(sr(A.patient, "inprog").update({ status: "cancelled" }));
  await no(sr(A.patient, "completed").update({ status: "cancelled" }));
});
for (const s of ["completed", "delivered", "in_progress", "accepted"]) {
  test(`patient cannot set status '${s}'`, () => no(sr(A.patient, "diag").update({ status: s })));
}
test("patient cannot touch price / paymentStatus", async () => {
  await no(sr(A.patient, "diag").update({ amount: 1 }));
  await no(sr(A.patient, "diag").update({ price: 1 }));
  await no(sr(A.patient, "diag").update({ paymentStatus: "refunded" }));
});
test("another patient cannot cancel", () =>
  no(sr(A.otherPatient, "diag").update({ status: "cancelled", cancelledBy: "patient" })));

// ── patient reschedule (physio / counselling) ─────────────────────────────
const resched = { preferredDate: "2026-12-05", preferredTime: "04:00 PM", rescheduledAt: new Date(), rescheduledBy: "patient", updatedAt: new Date() };
test("patient can reschedule a pending physiotherapy request", () => ok(sr(A.patient, "physioPending").update(resched)));
test("patient can reschedule an accepted physiotherapy request", () => ok(sr(A.patient, "physioAccepted").update(resched)));
test("patient can reschedule an accepted counselling request", () => ok(sr(A.patient, "counsAccepted").update(resched)));
test("patient cannot reschedule an in_progress physiotherapy request", () => no(sr(A.patient, "physioInProg").update(resched)));
test("patient cannot reschedule a diagnostics request through the reschedule branch", () =>
  no(sr(A.patient, "diag").update(resched)));
test("reschedule stamped rescheduledBy 'provider' by the patient is rejected", () =>
  no(sr(A.patient, "physioPending").update({ ...resched, rescheduledBy: "provider" })));
test("reschedule combined with a price change is rejected", () =>
  no(sr(A.patient, "physioPending").update({ ...resched, amount: 1 })));
test("another patient cannot reschedule", () => no(sr(A.otherPatient, "physioPending").update(resched)));

// ── provider (doctor) update: status ok, price fields never ───────────────
test("active doctor can update status", () => ok(sr(A.doctor, "diag").update({ status: "accepted" })));
for (const k of ["amount", "fee", "total", "totalAmount", "price", "patientId", "paymentId", "paymentStatus"]) {
  test(`provider cannot touch '${k}'`, () => no(sr(A.doctor, "diag").update({ [k]: k === "patientId" ? U.otherPatient : 1 })));
}
test("pending doctor and non-doctor partner cannot update", async () => {
  await no(sr(A.pendingDoctor, "diag").update({ status: "accepted" }));
  await no(sr(A.partner("lab"), "diag").update({ status: "accepted" }));
});
test("admin can update and delete; patient cannot delete", async () => {
  await no(sr(A.patient, "diag").delete());
  await ok(sr(A.director, "diag").update({ amount: 1 }));
  await ok(sr(A.director, "diag").delete());
});
