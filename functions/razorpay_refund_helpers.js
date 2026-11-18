"use strict";

// Pure helpers for the automatic Razorpay refund flow (no Firebase / network),
// kept in their own module so they can be unit-tested in isolation.
// Used by functions/index.js: _refundRazorpayPayment, the capture* wrapper and
// the reconcileRazorpayPayments scheduler.

// Rupees (or any decimal amount) -> integer paise. Returns 0 for anything
// non-finite / non-positive so callers can treat 0 as "nothing to refund".
function toPaise(amount) {
  const n = Number(amount);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.round(n * 100);
}

// Error classes that must NEVER trigger a refund: the payment is not proven
// (signature) or does not belong to the caller (another user's order).
const NO_REFUND_CODES = new Set(["unauthenticated", "permission-denied"]);

// Decide whether a capture* rejection should be followed by a gateway refund.
// Signature validity and order ownership are checked separately by the caller;
// this only classifies the error that was thrown.
function classifyCaptureError(err) {
  const code = err && err.code ? String(err.code).replace(/^functions\//, "") : "";
  if (NO_REFUND_CODES.has(code)) return { refund: false, reason: `code:${code}` };
  if (!code) return { refund: true, reason: "internal_error" };
  return { refund: true, reason: `capture_rejected:${code}` };
}

const REQUESTED_STALE_MS = 30 * 60 * 1000;
const MAX_ATTEMPTS = 5;

// Idempotency decision for razorpay_refunds/{paymentId}. `existing` is the
// doc data (or null). Returns "claim" (go on to call the gateway) or "skip".
//  - none                          -> claim
//  - succeeded / not_refundable    -> skip (terminal)
//  - requested                     -> skip, unless allowRetry && stale (a crash
//                                     mid-call; the gateway fetch step then
//                                     re-checks what was actually refunded)
//  - failed                        -> skip, unless allowRetry && attempts < max
function decideRefundClaim(existing, nowMs, opts = {}) {
  const allowRetry = !!opts.allowRetry;
  if (!existing) return "claim";
  const status = existing.status;
  if (status === "succeeded" || status === "not_refundable") return "skip";
  if (!allowRetry) return "skip";
  const attempts = Number(existing.attempts) || 1;
  if (attempts >= MAX_ATTEMPTS) return "skip";
  if (status === "failed") return "claim";
  if (status === "requested") {
    const at = existing.requestedAtMs;
    return typeof at === "number" && nowMs - at > REQUESTED_STALE_MS ? "claim" : "skip";
  }
  return "skip";
}

// How much to ask the gateway to refund, given what the order was for and what
// the gateway says about the payment. Never exceeds what is still refundable.
// Returns { amount, alreadyDone }.
function computeRefundAmount({ orderAmountPaise, paymentAmountPaise, alreadyRefundedPaise }) {
  const wanted = Math.round(Number(orderAmountPaise) || 0);
  const pay = Math.round(Number(paymentAmountPaise) || 0);
  const done = Math.round(Number(alreadyRefundedPaise) || 0);
  const target = wanted > 0 ? Math.min(wanted, pay) : pay;
  const remaining = Math.max(0, target - done);
  return { amount: remaining, alreadyDone: target > 0 && remaining === 0 };
}

// Splits a refund between the Razorpay gateway and the in-app (main) wallet.
//  - 'wallet' / 'already_settled' payments: the whole refund goes to the wallet.
//  - 'razorpay': the payment was `paidAmount` = walletPortionAmount (already
//    debited from the wallet) + gateway portion (charged at Razorpay). A full
//    refund returns each portion to where it came from. A partial refund is
//    PRORATED: gateway = refund * gatewayPortion / paid (rounded to paise), the
//    wallet gets the remainder, so the two legs always sum to the refund and the
//    gateway leg never exceeds what Razorpay actually captured.
//  - any other method: nothing is moved here (legacy behaviour).
// All results are integer paise. `refundAmount` (rupees) defaults to paidAmount.
//
// Optional `walletLegs` ({ main, mednuMoney }, recorded at capture): when present
// and summing exactly to the wallet portion, the result also carries
// `walletMainPaise` + `walletMednuPaise` (always summing to walletPaise; a full
// refund returns each leg exactly, a partial one is prorated, MedNU Money rounded
// to paise and the remainder to main). Without valid legs the result is unchanged
// (legacy: the whole wallet portion goes to the main wallet).
function computeRefundSplit({ paidAmount, walletPortionAmount, paymentMethod, refundAmount, walletLegs }) {
  const paidPaise = toPaise(paidAmount);
  const wanted = refundAmount === undefined || refundAmount === null ? paidPaise : toPaise(refundAmount);
  const refundPaise = Math.min(wanted, paidPaise);
  if (refundPaise <= 0) return { refundPaise: 0, gatewayPaise: 0, walletPaise: 0 };
  let out;
  let walletPortionPaise;
  if (paymentMethod === "wallet" || paymentMethod === "already_settled") {
    out = { refundPaise, gatewayPaise: 0, walletPaise: refundPaise };
    walletPortionPaise = paidPaise;
  } else if (paymentMethod !== "razorpay") {
    return { refundPaise, gatewayPaise: 0, walletPaise: 0 };
  } else {
    walletPortionPaise = Math.min(toPaise(walletPortionAmount), paidPaise);
    const gatewayPortionPaise = paidPaise - walletPortionPaise;
    const gatewayPaise = Math.min(Math.round((refundPaise * gatewayPortionPaise) / paidPaise), gatewayPortionPaise);
    out = { refundPaise, gatewayPaise, walletPaise: refundPaise - gatewayPaise };
  }
  if (walletLegs && out.walletPaise > 0) {
    const mmLeg = toPaise(walletLegs.mednuMoney);
    const mainLeg = toPaise(walletLegs.main);
    if (mmLeg + mainLeg === walletPortionPaise && walletPortionPaise > 0) {
      const mm = Math.min(out.walletPaise, mmLeg, Math.round((out.walletPaise * mmLeg) / walletPortionPaise));
      out.walletMednuPaise = mm;
      out.walletMainPaise = out.walletPaise - mm;
    }
  }
  return out;
}

// Orders the reconciler should look at (docs are read newest-first within a
// window; the status filter is applied in memory to avoid a composite index).
const RECONCILE_MIN_AGE_MS = 20 * 60 * 1000;
const RECONCILE_MAX_AGE_MS = 36 * 60 * 60 * 1000;
const RECONCILE_MAX_CHECKS = 3;
function isReconcileCandidate(order, nowMs) {
  if (!order || order.status !== "created") return false;
  if (order.refundState) return false;
  if ((Number(order.reconcileChecks) || 0) >= RECONCILE_MAX_CHECKS) return false;
  const t = order.createdAtMs;
  if (typeof t !== "number") return false;
  const age = nowMs - t;
  return age >= RECONCILE_MIN_AGE_MS && age <= RECONCILE_MAX_AGE_MS;
}

module.exports = {
  toPaise, classifyCaptureError, decideRefundClaim, computeRefundAmount, isReconcileCandidate, computeRefundSplit,
  REQUESTED_STALE_MS, MAX_ATTEMPTS, RECONCILE_MIN_AGE_MS, RECONCILE_MAX_AGE_MS, RECONCILE_MAX_CHECKS,
};
