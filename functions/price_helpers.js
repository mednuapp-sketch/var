// Pure (no Firebase) helpers for server-authoritative price checks. Kept in
// their own module so they can be unit tested without the Functions runtime.
"use strict";

const PRICE_TOLERANCE_RUPEES = 1;

// '₹1,200', 'Rs. 500', '500/-', 1200, '1200.50' -> number. Ranges ('500-800'),
// empty and non-numeric values -> null (caller must then skip, never guess).
function parseRupees(v) {
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (typeof v !== "string") return null;
  let s = v.trim().toLowerCase();
  if (!s) return null;
  s = s.replace(/₹|rs\.?|inr/g, "").replace(/\/-\s*$/, "").replace(/,/g, "").replace(/\s+/g, "");
  if (!/^\d+(\.\d+)?$/.test(s)) return null;
  return Number(s);
}

function withinTolerance(actual, expected, tol = PRICE_TOLERANCE_RUPEES) {
  return Number.isFinite(actual) && Number.isFinite(expected) && Math.abs(actual - expected) <= tol + 1e-9;
}

// Mirrors normalizeFeeServiceType in the patient app (platform_fee_provider.dart).
function normalizeFeeServiceType(raw) {
  if (typeof raw !== "string") return null;
  const t = raw.trim().toLowerCase().replace(/-/g, "_").replace(/ /g, "_");
  switch (t) {
    case "lab_tests": case "lab_test": case "labtest": case "diagnostic": case "diagnostics": return "diagnostics";
    case "nursing": case "home_care": case "homecare": case "caregiver": return "caregiver";
    case "medicine": case "medicines": case "pharmacy": return "medicine";
    case "physio": case "physiotherapy": return "physiotherapy";
    case "counseling": case "counselling": return "counselling";
    case "video": case "video_consultation": return "video_consultation";
    default: return t;
  }
}

// Platform fee for one booking, mirroring the patient app exactly:
// fee = enabled === true
//   ? (providers[providerId] ?? services[type] ?? defaultAmount ?? legacy amount ?? 0)
//   : 0
// (cfg = app_config/platform_fee data). Missing doc => 0. providerId is optional
// (unknown / pool jobs => service/default fee). Entries are {amount, label?} or a bare number.
function platformFeeFor(cfg, serviceType, providerId) {
  if (!cfg || typeof cfg !== "object" || cfg.enabled !== true) return 0;
  const asFee = (x) => {
    const n = parseRupees(x);
    return n === null || n < 0 ? null : Math.round(n);
  };
  if (typeof providerId === "string" && providerId.trim() && cfg.providers && typeof cfg.providers === "object") {
    const e = cfg.providers[providerId.trim()];
    const f = asFee(e && typeof e === "object" ? e.amount : e);
    if (f !== null) return f;
  }
  const key = normalizeFeeServiceType(serviceType);
  let fromServices = null;
  if (key && cfg.services && typeof cfg.services === "object") {
    for (const [k, v] of Object.entries(cfg.services)) {
      if (normalizeFeeServiceType(k) === key) {
        const f = asFee(v);
        if (f !== null) fromServices = f;
      }
    }
  }
  const dflt = asFee(cfg.defaultAmount ?? cfg.amount) ?? 0;
  return fromServices ?? dflt;
}

// Provider id used for the partner-specific fee. MUST stay identical to
// feeProviderIdFor in the patient app (platform_fee_provider.dart): the app and
// the server both derive the fee from the same booking data, so any drift
// would make the server reject honest payments.
const _FEE_PROVIDER_KEYS = {
  consultation: ["doctorId"], video_consultation: ["doctorId"],
  diagnostics: ["sd.sourceLabId", "labId"], lab_tests: ["sd.sourceLabId", "labId"],
  medicine: ["pharmacyId"], pharmacy: ["pharmacyId"],
  equipment: ["sd.sourceVendorId", "vendorId"], equipment_hiring: ["sd.sourceVendorId", "vendorId"],
  caregiver: ["sd.sourceCaregiverId", "caregiverId"], caregivers: ["sd.sourceCaregiverId", "caregiverId"],
  nursing: ["sd.sourceCaregiverId", "caregiverId"], home_care: ["sd.sourceCaregiverId", "caregiverId"],
  care_assistant: ["sd.assistantId", "assistantId"],
  physiotherapy: ["physiotherapistId"], counselling: ["counsellorId"], nutrition: ["nutritionistId"],
  hospital_bill: ["hospitalId"], hospital_op: ["hospitalId"],
  ambulance: [],
};
const _FEE_PROVIDER_FALLBACK = ["doctorId", "nutritionistId", "physiotherapistId", "counsellorId", "pharmacyId", "hospitalId", "providerId"];

function feeProviderIdFor(serviceType, bookingData) {
  const bd = bookingData && typeof bookingData === "object" ? bookingData : {};
  const sd = bd.serviceDetails && typeof bd.serviceDetails === "object" ? bd.serviceDetails : {};
  const t = typeof serviceType === "string" ? serviceType.trim().toLowerCase() : "";
  // Physio sessions added from the cart are priced from the admin `services`
  // catalogue by NAME (sd.sessionType); that catalogue has no partner binding,
  // so there is no partner id to verify => service/default fee (never the
  // client's physiotherapistId). The physio PROFILE booking (no sessionType)
  // keeps its id (verified by physiotherapists/{id}).
  if (t === "physiotherapy" && sd.sessionType) return null;
  const keys = Object.prototype.hasOwnProperty.call(_FEE_PROVIDER_KEYS, t) ? _FEE_PROVIDER_KEYS[t] : _FEE_PROVIDER_FALLBACK;
  for (const k of keys) {
    const v = k.startsWith("sd.") ? sd[k.slice(3)] : bd[k];
    if (typeof v === "string" && v.trim() && !v.includes("/") && v.length < 400) return v.trim();
  }
  // A physiotherapist video call lives in `consultations` where the physio's
  // uid is stored as `doctorId` (providerRole 'physiotherapist').
  if (t === "physiotherapy" && bd.providerRole === "physiotherapist") {
    const v = bd.doctorId;
    if (typeof v === "string" && v.trim() && !v.includes("/") && v.length < 400) return v.trim();
  }
  return null;
}

// Server-verified partner id for the fee override. The client-supplied id
// (feeProviderIdFor) is NEVER trusted on its own: it is checked against the
// same trusted catalogue/profile docs the price check reads, otherwise a
// customer could stamp a discounted partner's id on another partner's booking.
// `getDoc(collection, id)` -> data | null (injected so this stays Firebase-free).
// Returns {id: string|null, reason?: string}. id null => service/default fee.
//  - orders (medicines): every item's catalogue doc must carry the SAME
//    sourcePharmacyId (the doc's value is used, not the client's).
//  - lab / equipment: sourceLabId / sourceVendorId of the catalogue doc
//    (ltinv_{lab}_{test}, eqi_{vendor}_{item}) must equal the claimed id.
//  - caregiver / care assistant / physio / counselling / nutrition / doctor /
//    hospital: the catalogue/profile doc id IS the partner uid, verified by
//    existence of that doc.
async function verifiedFeeProviderId(getDoc, serviceType, bookingCollection, bookingData) {
  const bd = bookingData && typeof bookingData === "object" ? bookingData : {};
  const sd = bd.serviceDetails && typeof bd.serviceDetails === "object" ? bd.serviceDetails : {};
  const safeId = (v) => (typeof v === "string" && v.trim() && !v.includes("/") && v.length < 400 ? v.trim() : null);
  const none = (reason) => ({ id: null, reason });
  const claimed = feeProviderIdFor(serviceType, bd);

  if (bookingCollection === "orders") {
    const items = Array.isArray(bd.items) ? bd.items : [];
    if (!items.length || items.length > 50) return none("bad_items");
    const ids = [...new Set(items.map((i) => safeId(i && i.id)))];
    if (ids.some((x) => !x)) return none("item_missing_id");
    let pharmacy = null;
    for (const id of ids) {
      const d = await getDoc("medicines_catalogue", id);
      const p = d ? safeId(d.sourcePharmacyId) : null;
      if (!p) return none("item_without_pharmacy");
      if (pharmacy !== null && p !== pharmacy) return none("mixed_pharmacies");
      pharmacy = p;
    }
    return { id: pharmacy };
  }
  if (!claimed) return { id: null };
  const exists = async (col, id) => (id && (await getDoc(col, id))) ? { id } : none("partner_doc_not_found");

  if (bookingCollection === "appointments") {
    return safeId(bd.doctorId) === claimed ? exists("doctors", claimed) : none("id_not_doctor_field");
  }
  if (bookingCollection === "consultations") {
    if (safeId(bd.doctorId) !== claimed) return none("id_not_doctor_field");
    return exists(bd.providerRole === "physiotherapist" ? "physiotherapists" : "doctors", claimed);
  }
  if (bookingCollection === "nutrition_appointments") {
    if (safeId(bd.nutritionistId) !== claimed) return none("id_not_nutritionist_field");
    const r = await exists("nutritionists", claimed);
    return r.id ? r : exists("nutritionist_profiles", claimed);
  }
  if (bookingCollection === "hospital_appointments" || bookingCollection === "hospital_bill_payments") {
    return safeId(bd.hospitalId) === claimed ? exists("hospitals", claimed) : none("id_not_hospital_field");
  }
  if (bookingCollection === "service_requests") {
    const t = normalizeFeeServiceType(serviceType);
    if (t === "diagnostics") {
      const lab = safeId(sd.sourceLabId), test = safeId(sd.sourceTestId);
      if (!lab || !test || lab !== claimed) return none("no_lab_catalogue_binding");
      const d = await getDoc("lab_tests_catalogue", `ltinv_${lab}_${test}`);
      return d && safeId(d.sourceLabId) === lab ? { id: lab } : none("lab_doc_mismatch");
    }
    if (t === "equipment" || serviceType === "equipment_hiring") {
      const v = safeId(sd.sourceVendorId), it = safeId(sd.sourceItemId);
      if (!v || !it || v !== claimed) return none("no_equipment_catalogue_binding");
      const d = await getDoc("services", `eqi_${v}_${it}`);
      return d && safeId(d.sourceVendorId) === v ? { id: v } : none("equipment_doc_mismatch");
    }
    if (t === "caregiver" || t === "caregivers") {
      return safeId(sd.sourceCaregiverId) === claimed ? exists("caregivers", claimed) : none("id_not_caregiver_field");
    }
    if (t === "care_assistant") {
      return safeId(sd.assistantId) === claimed ? exists("care_assistants", claimed) : none("id_not_assistant_field");
    }
    if (t === "counselling") {
      return safeId(bd.counsellorId) === claimed ? exists("counsellors", claimed) : none("id_not_counsellor_field");
    }
    if (t === "physiotherapy") {
      // Catalogue-priced cart session: no partner binding exists => no override.
      if (sd.sessionType) return none("physio_catalogue_no_partner_binding");
      return safeId(bd.physiotherapistId) === claimed ? exists("physiotherapists", claimed) : none("id_not_physio_field");
    }
  }
  return none("unsupported");
}

// Doctor fees scale linearly off the 30-minute rate (mirrors the patient app).
function feeForDuration(baseFee, minutes) {
  return baseFee <= 0 ? 0 : Math.round((baseFee * minutes) / 30);
}

// sum(trunc(price) * count) — the app prices medicines with int truncation.
function sumLines(lines) {
  let total = 0;
  for (const { price, count } of lines) {
    const p = Math.trunc(Number(price));
    const c = Number(count);
    if (!Number.isFinite(p) || !Number.isInteger(c) || c < 1 || c > 1000) return null;
    total += p * c;
  }
  return total;
}

// A spec describes one acceptable price:
//   {type:'exact', value}                     value (+/- tolerance)
//   {type:'range', min, max}                  min-1 .. max+1
//   {type:'atLeast', value}                   >= value-1
//   {type:'multiple', unit, maxQty, extra}    k*unit + extra, integer k in 1..maxQty
function matchesSpec(amount, spec) {
  switch (spec.type) {
    case "exact": return withinTolerance(amount, spec.value);
    case "range": return amount >= spec.min - PRICE_TOLERANCE_RUPEES && amount <= spec.max + PRICE_TOLERANCE_RUPEES;
    case "atLeast": return amount >= spec.value - PRICE_TOLERANCE_RUPEES;
    case "multiple": {
      if (!(spec.unit > 0)) return false;
      const extra = spec.extra || 0;
      const maxQty = spec.maxQty || 100;
      for (let k = 1; k <= maxQty; k++) {
        if (withinTolerance(amount, k * spec.unit + extra)) return true;
      }
      return false;
    }
    default: return false;
  }
}

function matchesAny(amount, specs) {
  return specs.some((s) => matchesSpec(amount, s));
}

// Sum of wallet_ledger debit docs (already fetched; null for missing) that
// belong to `uid`. Used to prove a claimed walletPortionAmount was really debited.
function sumVerifiedDebits(docs, uid) {
  let sum = 0;
  for (const d of docs || []) {
    if (!d || d.uid !== uid || d.type !== "debit") continue;
    if (d.walletType !== "main" && d.walletType !== "mednu_money") continue;
    const a = Number(d.amount);
    if (Number.isFinite(a) && a > 0) sum += a;
  }
  return Math.round(sum * 100) / 100;
}

// Per-wallet breakdown of the same verified debits: { main, mednuMoney } (rupees,
// 2 dp). Same acceptance rules as sumVerifiedDebits (uid match, type 'debit',
// known walletType), so main + mednuMoney === sumVerifiedDebits(docs, uid).
function verifiedDebitLegs(docs, uid) {
  let main = 0;
  let mm = 0;
  for (const d of docs || []) {
    if (!d || d.uid !== uid || d.type !== "debit") continue;
    const a = Number(d.amount);
    if (!Number.isFinite(a) || !(a > 0)) continue;
    if (d.walletType === "main") main += a;
    else if (d.walletType === "mednu_money") mm += a;
  }
  return { main: Math.round(main * 100) / 100, mednuMoney: Math.round(mm * 100) / 100 };
}

// Legs to record on a payment doc for a `claimed` wallet portion. Returns
// { main, mednuMoney } summing EXACTLY to `claimed` (MedNU Money is taken first,
// the remainder is main wallet), or null when the ledger does not back the claim
// (then the payment keeps the legacy behaviour: wallet refunds go to main).
function fitWalletLegs(legs, claimed) {
  const c = Math.round((Number(claimed) || 0) * 100);
  if (!legs || !(c > 0)) return null;
  const mmP = Math.round((Number(legs.mednuMoney) || 0) * 100);
  const mainP = Math.round((Number(legs.main) || 0) * 100);
  if (mmP + mainP + 1 < c) return null; // ledger covers less than claimed (1 paise tolerance)
  const mm = Math.min(mmP, c);
  return { main: (c - mm) / 100, mednuMoney: mm / 100 };
}

// Cart: one item's share (`itemWallet`) of the order's legs. `allocatedMm` is the
// MedNU Money already given to earlier items. The last item takes the remainder,
// so per-item legs sum to the order legs exactly. Returns { main, mednuMoney }.
function itemWalletLegs(legs, walletTotal, itemWallet, allocatedMm, isLast) {
  const it = Math.round((Number(itemWallet) || 0) * 100);
  const tot = Math.round((Number(walletTotal) || 0) * 100);
  const mmTot = Math.round((Number(legs && legs.mednuMoney) || 0) * 100);
  if (!(it > 0) || !(tot > 0)) return { main: 0, mednuMoney: 0 };
  const left = Math.max(0, mmTot - Math.round((Number(allocatedMm) || 0) * 100));
  const mm = Math.min(it, isLast ? left : Math.min(left, Math.round((mmTot * it) / tot)));
  return { main: (it - mm) / 100, mednuMoney: mm / 100 };
}

// ── Quick-connect consultation credit decision ────────────────────────────
// Pure decision for onConsultationSettlement (consultations without
// appointmentId that just moved to 'ended'/'completed'). A PATIENT can end
// their own consultation, so a payout needs proof the doctor really joined:
//  1. before.status === 'active' (doctor app wrote it after joining Agora;
//     patients cannot write 'active') or doctorJoinedAt was stamped; or
//  2. fallback for a lost/failed 'active' write: the doctor accepted
//     (before.status === 'ongoing'), the DOCTOR ended it in this very update
//     (after.endedBy === after.doctorId; patients cannot write `endedBy`, it
//     is not in their rules allowlist) and the call lasted >= minSeconds,
//     measured endedAt - (ringingAt | acceptedAt). If either timestamp is
//     missing/unreadable only the doctor-ended condition is required.
const CONSULT_MIN_DOCTOR_ENDED_SECONDS = 30;
function _tsMillis(v) {
  if (v === null || v === undefined) return null;
  if (typeof v.toMillis === "function") { const n = v.toMillis(); return Number.isFinite(n) ? n : null; }
  if (v instanceof Date) { const n = v.getTime(); return Number.isFinite(n) ? n : null; }
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "object" && typeof v.seconds === "number") return v.seconds * 1000;
  return null;
}
function consultationCreditDecision(before, after, minSeconds = CONSULT_MIN_DOCTOR_ENDED_SECONDS) {
  const b = before || {}, a = after || {};
  if (b.status === "active" || a.doctorJoinedAt) return { credit: true, reason: "doctor_active" };
  const doctorId = typeof a.doctorId === "string" ? a.doctorId : "";
  if (b.status === "ongoing" && doctorId && a.endedBy === doctorId) {
    const start = _tsMillis(a.ringingAt) ?? _tsMillis(a.acceptedAt);
    const end = _tsMillis(a.endedAt);
    if (start !== null && end !== null && end - start < minSeconds * 1000) {
      return { credit: false, reason: "doctor_ended_too_short" };
    }
    return { credit: true, reason: "doctor_ended_ongoing" };
  }
  return { credit: false, reason: "doctor_not_joined" };
}

// ── Booking-doc sanitiser ─────────────────────────────────────────────────
// capturePayment / captureCartPayment / createFreeBooking copy the client's
// bookingData into a new booking doc. Fields that only the server / provider /
// triggers may write are stripped, and `status` is forced to the collection's
// initial value (what the patient app writes at creation). Everything else is
// kept verbatim. Pure: returns a new object, never mutates the input.
const BOOKING_CLIENT_FORBIDDEN_FIELDS = [
  "status", "paymentId", "paymentStatus", "settlementStatus", "amountDue", "fareFinal",
  "lockedFare", "lockedRate", "providerReleasedAt", "rescheduledAt", "rescheduledBy",
  "cancelledBy", "cancelReason", "completedAt", "completedBy", "acceptedAt", "declinedBy",
  "assignedTo", "assignedToName", "doctorJoinedAt", "settlementDeferredUntil",
  // Prepaid weight-loss plan links are server-set (capturePayment / bookPlanConsultation).
  "subscriptionId", "planIndex",
];
// null = the patient app sends no status for that collection (field omitted).
const BOOKING_INITIAL_STATUS = {
  appointments: "booked",
  hospital_appointments: "booked",
  consultations: "pending",
  service_requests: "pending",
  orders: "pending",
  nutrition_appointments: "pending",
  hospital_bill_payments: null,
};
function sanitizeBookingData(bookingCollection, bookingData) {
  const out = {};
  if (!bookingData || typeof bookingData !== "object" || Array.isArray(bookingData)) return out;
  for (const k of Object.keys(bookingData)) {
    if (BOOKING_CLIENT_FORBIDDEN_FIELDS.includes(k)) continue;
    out[k] = bookingData[k];
  }
  const initial = BOOKING_INITIAL_STATUS[bookingCollection];
  if (initial) out.status = initial;
  if (bookingCollection === "service_requests") out.assignedTo = null;
  return out;
}

module.exports = {
  sumVerifiedDebits, verifiedDebitLegs, fitWalletLegs, itemWalletLegs,
  PRICE_TOLERANCE_RUPEES, parseRupees, withinTolerance, platformFeeFor, normalizeFeeServiceType, feeProviderIdFor, verifiedFeeProviderId,
  feeForDuration, sumLines, matchesSpec, matchesAny,
  sanitizeBookingData, BOOKING_CLIENT_FORBIDDEN_FIELDS, BOOKING_INITIAL_STATUS,
  consultationCreditDecision, CONSULT_MIN_DOCTOR_ENDED_SECONDS,
};
