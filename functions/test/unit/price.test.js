const assert = require("assert");
const H = require("../../price_helpers.js");
const t = (n, f) => { f(); console.log("ok -", n); };
t("parseRupees", () => {
  assert.strictEqual(H.parseRupees("₹1,200"), 1200);
  assert.strictEqual(H.parseRupees("Rs. 500"), 500);
  assert.strictEqual(H.parseRupees("500/-"), 500);
  assert.strictEqual(H.parseRupees(750), 750);
  assert.strictEqual(H.parseRupees("1200.50"), 1200.5);
  assert.strictEqual(H.parseRupees("500-800"), null);
  assert.strictEqual(H.parseRupees(""), null);
  assert.strictEqual(H.parseRupees(null), null);
  assert.strictEqual(H.parseRupees("abc"), null);
});
t("tolerance", () => {
  assert(H.withinTolerance(500, 501)); assert(H.withinTolerance(500, 499));
  assert(!H.withinTolerance(500, 502)); assert(!H.withinTolerance(1, 500));
});
t("platform fee", () => {
  assert.strictEqual(H.platformFeeFor(null, "consultation"), 0);
  assert.strictEqual(H.platformFeeFor({ enabled: false, defaultAmount: 10 }, "x"), 0);
  assert.strictEqual(H.platformFeeFor({ enabled: true, defaultAmount: 10, services: { consultation: 20 } }, "consultation"), 20);
  assert.strictEqual(H.platformFeeFor({ enabled: true, defaultAmount: 10, services: { consultation: 20 } }, "medicine"), 10);
  assert.strictEqual(H.platformFeeFor({ enabled: true, amount: 7 }, "lab_tests"), 7);
  assert.strictEqual(H.platformFeeFor({ enabled: true, services: { caregiver: 15 } }, "caregivers"), 0); // 'caregivers' is not an alias in the app either
  assert.strictEqual(H.platformFeeFor({ enabled: true, services: { caregiver: 15 } }, "nursing"), 15);
  assert.strictEqual(H.platformFeeFor({ enabled: true, services: { diagnostics: 5 } }, "lab_tests"), 5);
});
t("duration fee", () => {
  assert.strictEqual(H.feeForDuration(500, 15), 250);
  assert.strictEqual(H.feeForDuration(500, 60), 1000);
  assert.strictEqual(H.feeForDuration(0, 30), 0);
});
t("sumLines", () => {
  assert.strictEqual(H.sumLines([{ price: 10.9, count: 2 }, { price: 5, count: 3 }]), 35);
  assert.strictEqual(H.sumLines([{ price: 10, count: 0 }]), null);
  assert.strictEqual(H.sumLines([{ price: 10, count: 1.5 }]), null);
});
t("specs", () => {
  assert(H.matchesSpec(520, { type: "exact", value: 520 }));
  assert(!H.matchesSpec(1, { type: "exact", value: 520 }));
  assert(H.matchesSpec(1250, { type: "range", min: 1200, max: 1300 }));
  assert(!H.matchesSpec(1400, { type: "range", min: 1200, max: 1300 }));
  assert(H.matchesSpec(99, { type: "atLeast", value: 99 }));
  assert(!H.matchesSpec(50, { type: "atLeast", value: 99 }));
  assert(H.matchesSpec(3 * 300 + 20, { type: "multiple", unit: 300, maxQty: 100, extra: 20 }));
  assert(!H.matchesSpec(320 + 1 + 150, { type: "multiple", unit: 300, maxQty: 100, extra: 20 }));
  assert(!H.matchesSpec(20, { type: "multiple", unit: 300, extra: 20 })); // qty 0 not allowed
  assert(H.matchesAny(5, [{ type: "exact", value: 1 }, { type: "exact", value: 5 }]));
});
t("sumVerifiedDebits", () => {
  const d = (o) => ({ uid: "u1", type: "debit", walletType: "main", amount: 10, ...o });
  assert.strictEqual(H.sumVerifiedDebits([d({}), d({ walletType: "mednu_money", amount: 5.5 })], "u1"), 15.5);
  assert.strictEqual(H.sumVerifiedDebits([null, null], "u1"), 0);
  assert.strictEqual(H.sumVerifiedDebits([d({ uid: "other" })], "u1"), 0);
  assert.strictEqual(H.sumVerifiedDebits([d({ type: "credit" })], "u1"), 0);
  assert.strictEqual(H.sumVerifiedDebits([d({ walletType: "platform" })], "u1"), 0);
  assert.strictEqual(H.sumVerifiedDebits([d({ amount: -4 }), d({ amount: "x" })], "u1"), 0);
});
t("partner-specific fee", () => {
  const c = { enabled: true, defaultAmount: 10, services: { medicine: 25, consultation: 20 },
    providers: { pharmA: { amount: 5 }, docZ: { amount: 0 }, bare: 7, bad: { amount: -3 } } };
  assert.strictEqual(H.platformFeeFor(c, "medicine", "pharmA"), 5);      // provider wins
  assert.strictEqual(H.platformFeeFor(c, "medicine", "other"), 25);      // unknown provider -> service
  assert.strictEqual(H.platformFeeFor(c, "medicine"), 25);               // no provider -> service
  assert.strictEqual(H.platformFeeFor(c, "consultation", "docZ"), 0);    // explicit 0 override honoured
  assert.strictEqual(H.platformFeeFor(c, "consultation", "bare"), 7);    // bare number tolerated
  assert.strictEqual(H.platformFeeFor(c, "consultation", "bad"), 20);    // invalid entry ignored
  assert.strictEqual(H.platformFeeFor(c, "nutrition", "x"), 10);         // default
  assert.strictEqual(H.platformFeeFor({ ...c, enabled: false }, "medicine", "pharmA"), 0);
  assert.strictEqual(H.platformFeeFor({ enabled: true, defaultAmount: 4 }, "x", "pharmA"), 4); // no providers map
  assert.strictEqual(H.platformFeeFor(c, "medicine", " pharmA "), 5);
  const b = (o) => o;
  assert.strictEqual(H.feeProviderIdFor("medicine", b({ pharmacyId: "pharmA", doctorId: "d" })), "pharmA");
  assert.strictEqual(H.feeProviderIdFor("consultation", b({ doctorId: "docZ" })), "docZ");
  assert.strictEqual(H.feeProviderIdFor("diagnostics", b({ serviceDetails: { sourceLabId: "lab1" } })), "lab1");
  assert.strictEqual(H.feeProviderIdFor("equipment", b({ serviceDetails: { sourceVendorId: "v1" } })), "v1");
  assert.strictEqual(H.feeProviderIdFor("caregiver", b({ serviceDetails: { sourceCaregiverId: "c1" } })), "c1");
  assert.strictEqual(H.feeProviderIdFor("care_assistant", b({ serviceDetails: { assistantId: "a1" } })), "a1");
  assert.strictEqual(H.feeProviderIdFor("ambulance", b({ ambulanceId: "amb" })), null);
  assert.strictEqual(H.feeProviderIdFor("diagnostics", b({ serviceDetails: {} })), null);
  assert.strictEqual(H.feeProviderIdFor("weird", b({ doctorId: "d9" })), "d9");
  assert.strictEqual(H.feeProviderIdFor("consultation", null), null);
});
t("physio video call fee provider + fee", () => {
  const cfg = { enabled: true, defaultAmount: 5, services: { physiotherapy: 15, video_consultation: 30 }, providers: { physio1: { amount: 12 } } };
  const doc = { doctorId: "physio1", providerRole: "physiotherapist" };
  assert.strictEqual(H.feeProviderIdFor("physiotherapy", doc), "physio1");                         // fallback to doctorId
  assert.strictEqual(H.feeProviderIdFor("physiotherapy", { ...doc, physiotherapistId: "physio1" }), "physio1");
  assert.strictEqual(H.feeProviderIdFor("physiotherapy", { doctorId: "d" }), null);                // not a physio doc
  assert.strictEqual(H.feeProviderIdFor("video_consultation", doc), "physio1");                    // old builds
  assert.strictEqual(H.platformFeeFor(cfg, "physiotherapy", "physio2"), 15);
  assert.strictEqual(H.platformFeeFor(cfg, "video_consultation", "physio2"), 30);
  assert.strictEqual(H.platformFeeFor(cfg, "physiotherapy", H.feeProviderIdFor("physiotherapy", doc)), 12);
  // onlineRate 400 + physiotherapy fee 15 = 415
  const pf = H.platformFeeFor(cfg, "physiotherapy", "physio2");
  assert(H.matchesAny(415, [{ type: "exact", value: 400 + pf }]));
  assert(!H.matchesAny(430, [{ type: "exact", value: 400 + pf }]));
});
// ---- verified fee provider (anti-spoof) ----
const docs = {
  "medicines_catalogue/phinv_cheap_1": { sourcePharmacyId: "cheap" },
  "medicines_catalogue/phinv_cheap_2": { sourcePharmacyId: "cheap" },
  "medicines_catalogue/phinv_dear_1": { sourcePharmacyId: "dear" },
  "doctors/d1": {}, "physiotherapists/p1": {}, "counsellors/c1": {}, "caregivers/cg1": {}, "care_assistants/ca1": {},
  "nutritionists/n1": {}, "hospitals/h1": {},
  "lab_tests_catalogue/ltinv_labA_t1": { sourceLabId: "labA" },
  "services/eqi_vendA_i1": { sourceVendorId: "vendA" },
};
const getDoc = async (c, id) => docs[c + "/" + id] || null;
const cfgP = { enabled: true, defaultAmount: 10, services: { medicine: 10, diagnostics: 10, equipment: 10, caregiver: 10 },
  providers: { cheap: 1, labCheap: 1, vendCheap: 1, cgCheap: 1 } };
const feeFor = async (st, col, bd) => { const v = await H.verifiedFeeProviderId(getDoc, st, col, bd); return H.platformFeeFor(cfgP, st, v.id); };
(async () => {
  const ok = (n, c) => { assert(c, n); console.log("ok -", n); };
  // medicine: honest, mixed, spoof
  ok("pharmacy override used when all items from that pharmacy",
    (await feeFor("medicine", "orders", { pharmacyId: "cheap", items: [{ id: "phinv_cheap_1" }, { id: "phinv_cheap_2" }] })) === 1);
  ok("mixed-pharmacy cart => service fee",
    (await feeFor("medicine", "orders", { pharmacyId: "cheap", items: [{ id: "phinv_cheap_1" }, { id: "phinv_dear_1" }] })) === 10);
  ok("spoofed pharmacyId on other pharmacy's items => service fee",
    (await feeFor("medicine", "orders", { pharmacyId: "cheap", items: [{ id: "phinv_dear_1" }] })) === 10);
  ok("unknown medicine item => service fee",
    (await feeFor("medicine", "orders", { pharmacyId: "cheap", items: [{ id: "nope" }] })) === 10);
  // lab
  const lab = (id, sd) => ({ serviceDetails: { sourceLabId: id, sourceTestId: "t1", ...sd } });
  ok("lab spoof (labCheap on labA test) => service fee", (await feeFor("diagnostics", "service_requests", lab("labCheap"))) === 10);
  docs["lab_tests_catalogue/ltinv_labCheap_t1"] = { sourceLabId: "labCheap" };
  ok("lab verified override", (await feeFor("diagnostics", "service_requests", lab("labCheap"))) === 1);
  // equipment
  const eq = (v) => ({ serviceDetails: { sourceVendorId: v, sourceItemId: "i1" } });
  ok("equipment spoof => service fee", (await feeFor("equipment", "service_requests", eq("vendCheap"))) === 10);
  docs["services/eqi_vendCheap_i1"] = { sourceVendorId: "vendCheap" };
  ok("equipment verified override", (await feeFor("equipment", "service_requests", eq("vendCheap"))) === 1);
  // caregiver: id must be an existing caregiver doc
  const cg = (id) => ({ serviceDetails: { sourceCaregiverId: id } });
  ok("caregiver nonexistent id => service fee", (await feeFor("caregiver", "service_requests", cg("cgCheap"))) === 10);
  docs["caregivers/cgCheap"] = {};
  ok("caregiver existing id => override", (await feeFor("caregiver", "service_requests", cg("cgCheap"))) === 1);
  ok("caregivers alias verified", (await H.verifiedFeeProviderId(getDoc, "caregivers", "service_requests", cg("cg1"))).id === "cg1");
  ok("care assistant verified", (await H.verifiedFeeProviderId(getDoc, "care_assistant", "service_requests", { serviceDetails: { assistantId: "ca1" } })).id === "ca1");
  ok("physio / counselling / doctor / nutrition / hospital verified",
    (await H.verifiedFeeProviderId(getDoc, "physiotherapy", "service_requests", { physiotherapistId: "p1" })).id === "p1" &&
    (await H.verifiedFeeProviderId(getDoc, "counselling", "service_requests", { counsellorId: "c1" })).id === "c1" &&
    (await H.verifiedFeeProviderId(getDoc, "consultation", "appointments", { doctorId: "d1" })).id === "d1" &&
    (await H.verifiedFeeProviderId(getDoc, "consultation", "consultations", { doctorId: "p1", providerRole: "physiotherapist" })).id === "p1" &&
    (await H.verifiedFeeProviderId(getDoc, "nutrition", "nutrition_appointments", { nutritionistId: "n1" })).id === "n1" &&
    (await H.verifiedFeeProviderId(getDoc, "hospital_op", "hospital_appointments", { hospitalId: "h1" })).id === "h1");
  // cart physio session (catalogue priced, sessionType set): claimed id is never honoured
  const cartPhysio = { physiotherapistId: "p1", serviceDetails: { sessionType: "Back pain" } };
  ok("cart physio: feeProviderIdFor => null", H.feeProviderIdFor("physiotherapy", cartPhysio) === null);
  ok("cart physio: verified => none (existing physio id spoof)", (await H.verifiedFeeProviderId(getDoc, "physiotherapy", "service_requests", cartPhysio)).id === null);
  ok("physio profile booking unchanged", H.feeProviderIdFor("physiotherapy", { physiotherapistId: "p1", serviceDetails: { title: "x" } }) === "p1");
  ok("nonexistent partner doc => null",(await H.verifiedFeeProviderId(getDoc, "counselling", "service_requests", { counsellorId: "zzz" })).id === null);
  ok("ambulance => null", (await H.verifiedFeeProviderId(getDoc, "ambulance", "service_requests", { providerId: "x" })).id === null);
  console.log("all passed");
})().catch((e) => { console.error(e); process.exit(1); });
