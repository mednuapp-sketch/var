/**
 * Area 9: real-payments switch (app_config/payments.requirePayment).
 *
 * Intended behaviour: when requirePayment == true, a client may not create a
 * booking that skips payment (paymentStatus 'not_required' / 'paid' or any
 * client-written paymentId). When the doc is missing or the flag is false the
 * switch is OFF and the existing no-pay path keeps working.
 *
 * This group is SKIPPED automatically if the rule is not present in
 * ../firestore.rules (detected by a text search for `requirePayment`).
 */
const { test, before, beforeEach, after } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const H = require("./helpers/env");
const { ok, no, doc, U } = H;

const RULE_PRESENT = /requirePayment/.test(fs.readFileSync(path.join(H.ROOT, "firestore.rules"), "utf8"));
const skip = RULE_PRESENT ? false : "SKIPPED: firestore.rules has no app_config/payments.requirePayment rule yet";

let env, A;
before(async () => { env = await H.setup("payments_switch"); A = H.actors(env); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await H.seedBase(env); });

const setSwitch = (state) => H.seed(env, async (db) => {
  if (state === "on") await db.doc("app_config/payments").set({ requirePayment: true });
  else if (state === "off") await db.doc("app_config/payments").set({ requirePayment: false });
  // "missing": no doc at all
});

// collection -> builder of a minimal valid create payload for the patient.
// PRICE is the per-collection price field the switch-ON rule inspects.
const BOOKINGS = {
  appointments: () => ({ patientId: U.patient, doctorId: U.doctor, status: "booked" }),
  hospital_appointments: () => ({ patientId: U.patient, hospitalId: "hosp-1", status: "booked" }),
  consultations: () => ({ patientId: U.patient, doctorId: U.doctor, callerType: "patient", status: "pending" }),
  service_requests: () => ({ patientId: U.patient, type: "diagnostics", status: "pending" }),
  nutrition_appointments: () => ({ userId: U.patient, nutritionistId: "nutritionist-active", status: "pending" }),
  orders: () => ({ patientId: U.patient, status: "pending" }),
};
const PRICE = {
  appointments: "fee", hospital_appointments: "fee", consultations: "fee",
  service_requests: "amount", nutrition_appointments: "fee", orders: "total",
};

for (const [col, build] of Object.entries(BOOKINGS)) {
  const create = (extra = {}) => doc(A.patient, `${col}/new`).set({ ...build(), ...extra });

  test(`[${col}] switch ON: paymentStatus 'not_required' is rejected`, { skip }, async () => {
    await setSwitch("on");
    await no(create({ paymentStatus: "not_required" }));
  });
  test(`[${col}] switch ON: client-asserted paymentStatus 'paid' is rejected`, { skip }, async () => {
    await setSwitch("on");
    await no(create({ paymentStatus: "paid" }));
  });
  test(`[${col}] switch ON: client-written paymentId is rejected`, { skip }, async () => {
    await setSwitch("on");
    await no(create({ paymentId: "pay_forged" }));
  });
  // Free bookings are server-created (createFreeBooking) while ON: rules cannot
  // see the real price, so a client-written fee/amount/total of 0 is NOT trusted.
  test(`[${col}] switch ON: zero price, no paymentStatus is rejected (free bookings go through createFreeBooking)`, { skip }, async () => {
    await setSwitch("on");
    await no(create({ [PRICE[col]]: 0 }));
  });
  test(`[${col}] switch OFF: zero price create works (unchanged)`, { skip }, async () => {
    await setSwitch("off");
    await ok(create({ [PRICE[col]]: 0 }));
  });
  test(`[${col}] switch ON: positive price with paymentStatus OMITTED is rejected (the hole)`, { skip }, async () => {
    await setSwitch("on");
    await no(create({ [PRICE[col]]: 500 }));
  });
  test(`[${col}] switch ON: positive price with paymentStatus 'not_required'/'paid'/paymentId still rejected`, { skip }, async () => {
    await setSwitch("on");
    await no(create({ [PRICE[col]]: 500, paymentStatus: "not_required" }));
    await no(create({ [PRICE[col]]: 500, paymentStatus: "paid" }));
    await no(create({ [PRICE[col]]: 500, paymentId: "pay_forged" }));
  });
  test(`[${col}] switch ON: zero price but secondary amount > 0 is rejected`, { skip }, async () => {
    await setSwitch("on");
    if (col === "service_requests") return; // amount is its price field
    await no(create({ [PRICE[col]]: 0, amount: 500 }));
  });
  test(`[${col}] switch ON: price field absent is rejected`, { skip }, async () => {
    await setSwitch("on");
    await no(create({}));
  });
  test(`[${col}] switch OFF: positive price with no paymentStatus works (unchanged)`, { skip }, async () => {
    await setSwitch("off");
    await ok(create({ [PRICE[col]]: 500 }));
  });
  test(`[${col}] switch OFF (flag false): 'not_required' create works`, { skip }, async () => {
    await setSwitch("off");
    await ok(create({ paymentStatus: "not_required" }));
  });
  test(`[${col}] switch missing (doc absent) behaves as OFF`, { skip }, async () => {
    await setSwitch("missing");
    await ok(create({ paymentStatus: "not_required" }));
  });
}

test("[service_requests] switch ON: ambulance pay_after_trip is allowed, not_required is rejected", { skip }, async () => {
  await setSwitch("on");
  const amb = (s) => doc(A.patient, "service_requests/amb").set({ patientId: U.patient, type: "ambulance", status: "pending", paymentStatus: s });
  await ok(amb("pay_after_trip"));
  await no(doc(A.patient, "service_requests/amb2").set({ patientId: U.patient, type: "ambulance", status: "pending", paymentStatus: "not_required" }));
});

test("[service_requests] switch ON: ambulance pay_after_trip with amount 0 or positive is allowed; non-ambulance pay_after_trip with price is rejected", { skip }, async () => {
  await setSwitch("on");
  const mk = (id, extra) => doc(A.patient, `service_requests/${id}`).set({ patientId: U.patient, status: "pending", ...extra });
  await ok(mk("a1", { type: "ambulance", amount: 0, paymentStatus: "pay_after_trip" }));
  await ok(mk("a2", { type: "ambulance", amount: 900, paymentStatus: "pay_after_trip" }));
  await no(mk("d1", { type: "diagnostics", amount: 900, paymentStatus: "pay_after_trip" }));
});

test("[service_requests] switch ON: SOS emergency_doctor (amount null/absent/0) is allowed; free service types and priced emergency_doctor are rejected", { skip }, async () => {
  await setSwitch("on");
  const mk = (id, extra) => doc(A.patient, `service_requests/${id}`).set({ patientId: U.patient, status: "pending", ...extra });
  await ok(mk("e1", { type: "emergency_doctor", amount: null }));
  await ok(mk("e1b", { type: "emergency_doctor" }));
  await ok(mk("e1c", { type: "emergency_doctor", amount: 0 }));
  await no(mk("e2", { type: "counselling" }));                       // free service: createFreeBooking only
  await no(mk("e3", { type: "counselling", amount: null }));
  await no(mk("e4", { type: "physiotherapy", amount: 0 }));
  await no(mk("e5", { type: "emergency_doctor", amount: 500 }));
  await no(mk("e6", { type: "emergency_doctor", paymentStatus: "not_required" }));
});

test("[service_requests] switch OFF: free ServiceBookingSheet create (amount null) still works", { skip }, async () => {
  await setSwitch("off");
  await ok(doc(A.patient, "service_requests/f1").set({ patientId: U.patient, status: "pending", type: "counselling", amount: null }));
});

test("[consultations] switch ON: provider-created consultation (own uid in doctorId, positive fee) is allowed", { skip }, async () => {
  await setSwitch("on");
  for (const callerType of ["doctor", "physiotherapist", "counsellor", "nutritionist"]) {
    await ok(doc(A.doctor, `consultations/p-${callerType}`).set({ callerType, doctorId: U.doctor, patientId: U.patient, status: "pending", fee: 500 }));
  }
  // ...but not on behalf of another provider's uid.
  await no(doc(A.doctor, "consultations/p-bad").set({ callerType: "doctor", doctorId: U.otherDoctor, patientId: U.patient, status: "pending", fee: 500 }));
});

test("[consultations] switch ON: scheduled call of the patient's OWN existing appointment (no fee) is allowed; others are not", { skip }, async () => {
  await setSwitch("on");
  await H.seed(env, async (db) => {
    await db.doc("appointments/ap1").set({ patientId: U.patient, doctorId: U.doctor, fee: 500, paymentStatus: "paid" });
    await db.doc("appointments/ap2").set({ patientId: U.otherPatient, doctorId: U.doctor, fee: 500, paymentStatus: "paid" });
  });
  const sched = (id, extra) => doc(A.patient, `consultations/${id}`).set({
    callerType: "patient", patientId: U.patient, doctorId: U.doctor, isScheduled: true, status: "scheduled_waiting", ...extra });
  await ok(sched("s1", { appointmentId: "ap1" }));
  await no(sched("s2", { appointmentId: "ap2" }));       // someone else's appointment
  await no(sched("s3", { appointmentId: "missing" }));   // nonexistent appointment
  await no(sched("s4", {}));                              // no appointmentId
  await no(sched("s5", { appointmentId: "ap1", doctorId: U.otherDoctor })); // doctor mismatch
});

test("[hospital_bill_payments] client create: allowed only with switch OFF/missing", { skip }, async () => {
  const mk = () => doc(A.patient, "hospital_bill_payments/b1").set({ patientId: U.patient, hospitalId: "hosp-1", finalAmount: 1000, paymentStatus: "not_required" });
  await setSwitch("on");
  await no(mk());
  await setSwitch("off");
  await ok(mk());
  await env.clearFirestore();
  await ok(mk()); // doc missing == OFF
});

test("switch ON: only a Director can flip app_config/payments", { skip }, async () => {
  await setSwitch("on");
  await no(doc(A.patient, "app_config/payments").update({ requirePayment: false }));
  await no(doc(A.hr, "app_config/payments").update({ requirePayment: false }));
  await ok(doc(A.director, "app_config/payments").update({ requirePayment: false }));
});
