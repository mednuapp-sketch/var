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
  const keys = Object.prototype.hasOwnProperty.call(_FEE_PROVIDER_KEYS, t) ? _FEE_PROVIDER_KEYS[t] : _FEE_PROVIDER_FALLBACK;
  for (const k of keys) {
    const v = k.startsWith("sd.") ? sd[k.slice(3)] : bd[k];
    if (typeof v === "string" && v.trim() && !v.includes("/") && v.length < 400) return v.trim();
  }
  return null;
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

module.exports = {
  sumVerifiedDebits,
  PRICE_TOLERANCE_RUPEES, parseRupees, withinTolerance, platformFeeFor, normalizeFeeServiceType, feeProviderIdFor,
  feeForDuration, sumLines, matchesSpec, matchesAny,
};
