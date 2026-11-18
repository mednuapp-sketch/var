/**
 * Area 6: diagnostic_bookings + pharmacy_orders pool rules, and
 * pharmacy_order_items read access for unclaimed pool orders.
 */
const { test, before, beforeEach, after } = require("node:test");
const H = require("./helpers/env");
const { ok, no, doc, U, arrayUnion, active, pending, other } = H;

let env, A;
before(async () => { env = await H.setup("pool_orders"); A = H.actors(env); });
after(async () => { await env.cleanup(); });

const LAB = active("lab"), PH = active("pharmacy");

const booking = (over = {}) => ({
  sourceRequestId: "s", type: "diagnostics", testName: "CBC", price: 500, amount: 500,
  patientId: U.patient, patientName: "P", patientPhone: "", address: "a",
  preferredDate: "", preferredTime: "", notes: "", labId: null, status: "pending",
  createdAt: new Date(), updatedAt: new Date(), ...over,
});
const order = (over = {}) => ({
  sourceCollection: "orders", sourceId: "o", orderType: "medicine", patientId: U.patient,
  patientName: "P", patientPhone: "", deliveryAddress: "a", itemCount: 1, totalAmount: 300,
  pharmacyId: null, status: "pending", requiresPrescription: false, createdAt: new Date(), ...over,
});

beforeEach(async () => {
  await env.clearFirestore();
  await H.seedBase(env);
  await H.seed(env, async (db) => {
    const d = db.collection("diagnostic_bookings");
    await d.doc("pool").set(booking());
    await d.doc("pool2").set(booking({ declinedBy: ["x"] }));
    await d.doc("owned").set(booking({ labId: LAB, status: "accepted" }));
    const p = db.collection("pharmacy_orders");
    await p.doc("pool").set(order());
    await p.doc("poolRx").set(order({ requiresPrescription: true }));
    await p.doc("verified").set(order({ pharmacyId: PH, status: "verified" }));
    await p.doc("otherOwned").set(order({ pharmacyId: other("pharmacy"), status: "verified" }));
    const i = db.collection("pharmacy_order_items");
    await i.doc("iPool").set({ orderId: "pool", name: "Para" });
    await i.doc("iOwned").set({ orderId: "verified", name: "Para" });
    await i.doc("iOther").set({ orderId: "otherOwned", name: "Para" });
  });
});
const dbk = (ctx, id) => doc(ctx, `diagnostic_bookings/${id}`);
const po = (ctx, id) => doc(ctx, `pharmacy_orders/${id}`);
const lab = () => A.partner("lab");
const ph = () => A.partner("pharmacy");

// ───────────────────────── diagnostic_bookings ─────────────────────────────
test("diag: active lab can read an unclaimed booking; pending lab / stranger cannot", async () => {
  await ok(dbk(lab(), "pool").get());
  await no(dbk(A.partner("lab", "pending"), "pool").get());
  await no(dbk(A.stranger, "pool").get());
  await no(dbk(A.anon, "pool").get());
});
test("diag: pool decline adds own uid to declinedBy (+updatedAt) only", () =>
  ok(dbk(lab(), "pool").update({ declinedBy: arrayUnion(LAB), updatedAt: new Date() })));
test("diag: pool decline keeps status pending; changing status in the same write is rejected", () =>
  no(dbk(lab(), "pool").update({ declinedBy: arrayUnion(LAB), status: "rejected" })));
test("diag: pending lab / stranger / patient cannot decline", async () => {
  await no(dbk(A.partner("lab", "pending"), "pool").update({ declinedBy: arrayUnion(pending("lab")) }));
  await no(dbk(A.stranger, "pool").update({ declinedBy: arrayUnion(U.stranger) }));
  await no(dbk(A.patient, "pool").update({ declinedBy: arrayUnion(U.patient) }));
});
test("diag: declinedBy must contain own uid", () =>
  no(dbk(lab(), "pool").update({ declinedBy: arrayUnion("other-uid") })));
test("diag: cannot drop existing declinedBy entries or add more than one", async () => {
  await no(dbk(lab(), "pool2").update({ declinedBy: [LAB] }));
  await no(dbk(lab(), "pool2").update({ declinedBy: ["x", LAB, "y"] }));
  await ok(dbk(lab(), "pool2").update({ declinedBy: arrayUnion(LAB) }));
});
test("diag: claim sets labId and status 'accepted'", () =>
  ok(dbk(lab(), "pool").update({ labId: LAB, status: "accepted", updatedAt: new Date() })));
for (const s of ["rejected", "cancelled", "completed", "technician_assigned"]) {
  test(`diag: claim-and-'${s}' in one write is no longer allowed`, () =>
    no(dbk(lab(), "pool").update({ labId: LAB, status: s })));
}
test("diag: a second lab cannot claim an owned booking", () =>
  no(dbk(A.partner("lab", "other"), "owned").update({ labId: other("lab"), status: "accepted" })));
test("diag: owning lab follows valid transition, cannot skip or touch price", async () => {
  await ok(dbk(lab(), "owned").update({ status: "technician_assigned" }));
  await no(dbk(lab(), "owned").update({ status: "completed" }));
  await no(dbk(lab(), "owned").update({ amount: 1 }));
});
test("diag: client create/delete denied; admin allowed", async () => {
  await no(dbk(lab(), "n").set(booking()));
  await no(dbk(A.patient, "n").set(booking()));
  await ok(dbk(A.director, "n").set(booking()));
});

// ───────────────────────── pharmacy_orders ─────────────────────────────────
test("pharm: active pharmacy can read pool orders; pending/other roles cannot", async () => {
  await ok(po(ph(), "pool").get());
  await no(po(A.partner("pharmacy", "pending"), "pool").get());
  await no(po(lab(), "pool").get());
  await no(po(A.stranger, "pool").get());
});
test("pharm: pool decline via declinedBy only", () =>
  ok(po(ph(), "pool").update({ declinedBy: arrayUnion(PH), updatedAt: new Date() })));
test("pharm: pool decline with status change is rejected", () =>
  no(po(ph(), "pool").update({ declinedBy: arrayUnion(PH), status: "cancelled" })));
test("pharm: pending pharmacy / patient cannot decline", async () => {
  await no(po(A.partner("pharmacy", "pending"), "pool").update({ declinedBy: arrayUnion(pending("pharmacy")) }));
  await no(po(A.patient, "pool").update({ declinedBy: arrayUnion(U.patient) }));
});
test("pharm: claim to 'verified' (no Rx required) or 'prescription_required' is allowed", async () => {
  await ok(po(ph(), "pool").update({ pharmacyId: PH, status: "verified" }));
  await ok(po(ph(), "poolRx").update({ pharmacyId: PH, status: "prescription_required" }));
});
test("pharm: claim-and-cancel is no longer allowed", () =>
  no(po(ph(), "pool").update({ pharmacyId: PH, status: "cancelled" })));
for (const s of ["packed", "delivered", "out_for_delivery"]) {
  test(`pharm: claim straight to '${s}' is rejected`, () =>
    no(po(ph(), "pool").update({ pharmacyId: PH, status: s })));
}
test("pharm: claim to 'verified' with a required but missing prescription is rejected", () =>
  no(po(ph(), "poolRx").update({ pharmacyId: PH, status: "verified" })));
test("pharm: pending pharmacy cannot claim", () =>
  no(po(A.partner("pharmacy", "pending"), "pool").update({ pharmacyId: pending("pharmacy"), status: "verified" })));
test("pharm: owning pharmacy follows valid transitions only", async () => {
  await ok(po(ph(), "verified").update({ status: "packed" }));
  await no(po(ph(), "verified").update({ status: "delivered" }));
  await no(po(ph(), "verified").update({ totalAmount: 1 }));
});
test("pharm: another pharmacy cannot update a claimed order", () =>
  no(po(A.partner("pharmacy", "other"), "verified").update({ status: "packed" })));
test("pharm: patient cannot update, create or delete", async () => {
  await no(po(A.patient, "pool").update({ status: "cancelled" }));
  await no(po(A.patient, "n").set(order()));
  await no(po(A.patient, "pool").delete());
});

// ───────────────────────── pharmacy_order_items ────────────────────────────
test("items: active pharmacy can read items of an UNCLAIMED pool order", () =>
  ok(doc(ph(), "pharmacy_order_items/iPool").get()));
test("items: pending pharmacy, lab and stranger cannot read pool items", async () => {
  await no(doc(A.partner("pharmacy", "pending"), "pharmacy_order_items/iPool").get());
  await no(doc(lab(), "pharmacy_order_items/iPool").get());
  await no(doc(A.stranger, "pharmacy_order_items/iPool").get());
  await no(doc(A.anon, "pharmacy_order_items/iPool").get());
});
test("items: owning pharmacy and patient can read; another pharmacy cannot read a claimed order's items", async () => {
  await ok(doc(ph(), "pharmacy_order_items/iOwned").get());
  await ok(doc(A.patient, "pharmacy_order_items/iOwned").get());
  await no(doc(ph(), "pharmacy_order_items/iOther").get());
  await no(doc(A.otherPatient, "pharmacy_order_items/iPool").get());
});
test("items: clients cannot write; admin can", async () => {
  await no(doc(ph(), "pharmacy_order_items/iPool").update({ name: "x" }));
  await no(doc(A.patient, "pharmacy_order_items/new").set({ orderId: "pool" }));
  await ok(doc(A.director, "pharmacy_order_items/new").set({ orderId: "pool" }));
});
