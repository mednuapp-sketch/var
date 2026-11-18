// Pure (no Firebase) helpers for the prepaid weight-loss plan (nutrition
// subscription). Unit-testable without the Functions runtime.
"use strict";

const PLAN_MONTHS = [2, 4, 6];
const PLAN_TYPE = "weight_loss";
const PLAN_CONTRACT = 2; // `planContract` sent by builds that know the prepaid-plan flow
const IST_OFFSET_MS = 330 * 60 * 1000;

const pad2 = (n) => String(n).padStart(2, "0");

// 'yyyy-MM-dd' of an instant in India time (the app's calendar).
function istDateKey(d = new Date()) {
  const t = new Date((d instanceof Date ? d.getTime() : Number(d)) + IST_OFFSET_MS);
  return `${t.getUTCFullYear()}-${pad2(t.getUTCMonth() + 1)}-${pad2(t.getUTCDate())}`;
}

function parseKey(key) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ""));
  if (!m) return null;
  const y = +m[1], mo = +m[2], d = +m[3];
  const dt = new Date(Date.UTC(y, mo - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d) return null;
  return { y, mo, d };
}

// start + n calendar months, day clamped to the target month's length
// (Jan 31 + 1 month = Feb 28/29). Always computed from the ORIGINAL start so
// windows stay contiguous (no cumulative clamping drift).
function addMonthsKey(key, n) {
  const p = parseKey(key);
  if (!p) return null;
  const total = p.mo - 1 + n;
  const y = p.y + Math.floor(total / 12);
  const mo = ((total % 12) + 12) % 12;
  const last = new Date(Date.UTC(y, mo + 1, 0)).getUTCDate();
  return `${y}-${pad2(mo + 1)}-${pad2(Math.min(p.d, last))}`;
}

function addDaysKey(key, n) {
  const p = parseKey(key);
  if (!p) return null;
  const t = new Date(Date.UTC(p.y, p.mo - 1, p.d + n));
  return `${t.getUTCFullYear()}-${pad2(t.getUTCMonth() + 1)}-${pad2(t.getUTCDate())}`;
}

// Consultation k (1-based) window = [start+(k-1) months, start+k months - 1 day].
function buildWindows(startKey, months) {
  const out = [];
  for (let k = 1; k <= months; k++) {
    out.push({
      index: k,
      windowStart: addMonthsKey(startKey, k - 1),
      windowEnd: addDaysKey(addMonthsKey(startKey, k), -1),
    });
  }
  return out;
}

// '₹999/month', '₹1,200/month', 999 -> 999 (integer rupees) | null.
// Mirrors monthlyAmountFromPrice in the patient app (first digit run).
function monthlyFromPrice(v) {
  if (typeof v === "number") return Number.isFinite(v) && v > 0 ? Math.trunc(v) : null;
  if (typeof v !== "string") return null;
  const m = /[\d,]+/.exec(v);
  if (!m) return null;
  const n = parseInt(m[0].replace(/,/g, ""), 10);
  return Number.isFinite(n) && n > 0 ? n : null;
}

// Expected TOTAL the customer pays: monthly x months + the platform fee (once).
function planTotal(monthly, months, platformFee) {
  return monthly * months + (platformFee || 0);
}

// Splits a rupee total (2 dp) into `months` integer-paise shares; remainder
// paise go on the LAST share. Returns rupees (2 dp) per consultation.
function splitPayout(totalRupees, months) {
  const paise = Math.round((Number(totalRupees) || 0) * 100);
  if (!(months >= 1)) return [];
  const each = Math.floor(paise / months);
  const out = [];
  for (let i = 1; i <= months; i++) out.push(i === months ? paise - each * (months - 1) : each);
  return out.map((p) => p / 100);
}

// Whole months in a plan -> is it a valid weight-loss plan request.
function isPlanBooking(bd) {
  return !!bd && typeof bd === "object" && bd.planType === PLAN_TYPE;
}

// Is `dateKey` inside the credit's window (inclusive, string compare is safe for yyyy-MM-dd).
function inWindow(credit, dateKey) {
  return !!credit && parseKey(dateKey) !== null && dateKey >= credit.windowStart && dateKey <= credit.windowEnd;
}

// Credit choice for a booking date. `wanted` (optional 1-based index) pins the credit.
// Returns the credit or null.
function pickCredit(credits, dateKey, wanted) {
  const avail = (credits || []).filter((c) => c.status === "available" && inWindow(c, dateKey));
  if (wanted) return avail.find((c) => c.index === wanted) || null;
  avail.sort((a, b) => a.index - b.index);
  return avail[0] || null;
}

// Cancel-plan refund (client decision 5a): before any consultation is
// completed the customer gets the plan BASE back; the platform fee is
// non-refundable. Returns rupees (2 dp), capped at what was paid.
function planRefundAmount({ baseTotal, platformFee, paidAmount }) {
  const base = Math.max(0, Number(baseTotal) || 0);
  const paid = Math.max(0, Number(paidAmount) || 0);
  const fee = Math.max(0, Number(platformFee) || 0);
  // With a coupon the customer paid less than base+fee: never refund more than paid - fee.
  return Math.round(Math.max(0, Math.min(base, paid - fee)) * 100) / 100;
}

// Unused, not-booked credits' share (refundUnused / lapsePolicy 'refund_to_wallet').
function unusedShare(shares, credits, statuses = ["available"]) {
  let paise = 0;
  for (const c of credits || []) {
    if (statuses.includes(c.status)) paise += Math.round((shares[c.index - 1] || 0) * 100);
  }
  return paise / 100;
}

// Manual FULL refund of a plan payment after some consultations were completed:
// decides, per child share payment (`planshare:<sub>:<i>`), whether the earnings
// already credited to the dietician can be taken back.
//  - missing doc / already refunded / already reversed -> ignored (idempotent)
//  - settlementStatus 'eligible' (credited to pendingEarnings, in no settlement)
//    -> reverse
//  - anything else (pending_review, approved, paid, ...) -> skipped, never clawed
//    back; the caller records `reversalSkipped` and raises an admin alert.
// Input: [{ id, exists, status, settlementStatus, shareReversed, providerId, providerAmount }]
// Output: { reverse: [{ id, providerId, amount }], skipped: [{ id, providerId, amount, reason }] }
function planShareReversalDecision(children) {
  const reverse = [];
  const skipped = [];
  for (const c of children || []) {
    if (!c || c.exists === false) continue;
    if (c.status === "refunded" || c.shareReversed === true) continue;
    const amount = Math.round((Number(c.providerAmount) || 0) * 100) / 100;
    if (!(amount > 0) || !c.providerId) continue;
    if (c.settlementStatus === "eligible") {
      reverse.push({ id: c.id, providerId: c.providerId, amount });
    } else {
      skipped.push({ id: c.id, providerId: c.providerId, amount, reason: String(c.settlementStatus || "unknown") });
    }
  }
  return { reverse, skipped };
}

// Carry-forward recovery of earnings that were already settled (or sitting in a
// settlement) when their payment was fully refunded. The amount becomes
// provider_wallets.recoverableDebt and is netted off the provider's NEXT settlement.
// Input: skipped shares [{ id, providerId, amount }] -> [{ providerId, amount, ids }] grouped.
function recoveryByProvider(skipped) {
  const m = new Map();
  for (const c of skipped || []) {
    const amt = Math.round((Number(c.amount) || 0) * 100) / 100;
    if (!c || !c.providerId || !(amt > 0)) continue;
    if (!m.has(c.providerId)) m.set(c.providerId, { providerId: c.providerId, amount: 0, ids: [] });
    const g = m.get(c.providerId);
    g.amount = Math.round((g.amount + amt) * 100) / 100;
    g.ids.push(c.id);
  }
  return [...m.values()];
}

// Nets a provider's recoverableDebt against a settlement gross total.
// applied = min(debt, gross); payout = gross - applied; remaining debt stays.
// All in integer paise to avoid float drift.
function netRecovery(grossTotal, recoverableDebt) {
  const g = Math.max(0, Math.round((Number(grossTotal) || 0) * 100));
  const d = Math.max(0, Math.round((Number(recoverableDebt) || 0) * 100));
  const applied = Math.min(g, d);
  return { recoveryApplied: applied / 100, netTotal: (g - applied) / 100, debtAfter: (d - applied) / 100 };
}

module.exports = {
  recoveryByProvider, netRecovery,
  planShareReversalDecision,
  PLAN_MONTHS, PLAN_TYPE, PLAN_CONTRACT,
  istDateKey, parseKey, addMonthsKey, addDaysKey, buildWindows, monthlyFromPrice,
  planTotal, splitPayout, isPlanBooking, inWindow, pickCredit, planRefundAmount, unusedShare,
};
