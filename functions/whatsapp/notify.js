/**
 * Recipient resolution + the dedupe-safe send wrapper every trigger uses.
 */

const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {COLLECTIONS, WHATSAPP_DEFAULT_LANG} = require("./config");
const {normalizePhone, sendTemplate} = require("./whatsapp");

/**
 * Tidies a stored name for use inside a template: trims and collapses
 * spaces, drops a leading "Dr"/"Dr." (the doctor templates already say
 * "Dr. {{n}}", so a stored "Dr. Navya" would otherwise read "Dr. Dr. Navya"),
 * and title-cases names typed in all-lower or all-upper case
 * ("ravi kumar" / "RAVI KUMAR" -> "Ravi Kumar"). Returns "" if nothing usable.
 */
function cleanName(raw) {
  let s = String(raw || "").replace(/\s+/g, " ").trim();
  s = s.replace(/^dr(\.\s*|\s+)/i, "").trim();
  if (!s) return "";
  if (s === s.toLowerCase() || s === s.toUpperCase()) {
    s = s.toLowerCase().replace(/(^|[\s'-])(\p{L})/gu, (m, sep, ch) => sep + ch.toUpperCase());
  }
  return s;
}

/**
 * Resolves whether `uid`'s profile doc in `collection` is opted in to
 * WhatsApp and, if so, returns what to send to. Returns null when opted out,
 * missing, or has no usable phone — callers should just skip sending.
 * @param {string} collection e.g. COLLECTIONS.users or COLLECTIONS.doctors.
 * @param {string} uid
 * @param {string} [fallbackName] Name to use if the profile has none, e.g.
 *   the `patientName` stored on the booking itself.
 */
async function getRecipient(collection, uid, fallbackName) {
  if (!uid) return null;
  const snap = await getFirestore().collection(collection).doc(uid).get();
  if (!snap.exists) return null;
  const d = snap.data() || {};
  if (d.whatsappOptIn !== true) return null;

  const rawPhone = d.whatsappPhone || d.phone;
  const phone = normalizePhone(rawPhone);
  if (!phone) return null;

  // Profiles don't all use the same field (ambulance profiles store
  // `driverName`), so take the first one that has a usable value.
  const fullName = cleanName(
    d.name || d.fullName || d.displayName || d.driverName || d.ownerName || fallbackName,
  );
  const firstName = fullName ? fullName.split(" ")[0] : "there";

  // Only "en" has real copy today (all 13 templates were created in en);
  // any other stored language value falls back to the configured default
  // rather than requesting a template variant that doesn't exist.
  const lang = d.language === "en" ? "en" : WHATSAPP_DEFAULT_LANG.value();

  return {phone, firstName, fullName, lang};
}

/**
 * Sends `templateKey` to `recipient` exactly once, ever, for `dedupeKey`.
 * Uses `.create()` on whatsapp_logs/{dedupeKey} as the idempotency lock —
 * a concurrent/retried invocation racing for the same key gets an
 * ALREADY_EXISTS error and simply returns without sending again.
 *
 * Throws on a retryable send failure so the caller's onDocumentWritten
 * (registered with retry: true) gets retried by Cloud Functions; a
 * non-retryable failure (e.g. bad template params) is logged and swallowed.
 *
 * @param {string} dedupeKey Firestore-doc-id-safe unique key for this send.
 * @param {{phone:string, firstName:string, lang:string}} recipient
 * @param {string} templateKey
 * @param {string[]} params Ordered body params matching templates.js.
 * @param {string} refId Used to build quick-reply payloads.
 */
async function notifyOnce(dedupeKey, recipient, templateKey, params, refId) {
  const db = getFirestore();
  const logRef = db.collection(COLLECTIONS.whatsappLogs).doc(dedupeKey);

  try {
    await logRef.create({
      templateKey,
      to: recipient.phone,
      refId,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    if (e?.code === 6 || e?.code === "already-exists") {
      // Another invocation already owns this dedupe key — nothing to do.
      return {ok: true, deduped: true};
    }
    throw e;
  }

  const result = await sendTemplate(recipient.phone, templateKey, params, recipient.lang, refId);

  if (result.ok) {
    await logRef.set(
      {status: "sent", messageId: result.messageId, sentAt: FieldValue.serverTimestamp()},
      {merge: true},
    );
    return result;
  }

  await logRef.set(
    {
      status: "failed",
      error: result.error ? JSON.stringify(result.error).slice(0, 1000) : "unknown",
      retryable: !!result.retryable,
      failedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  if (result.retryable) {
    throw new Error(`WhatsApp send failed (retryable): ${templateKey} -> ${dedupeKey}`);
  }
  return result;
}

/** "25 Sep, 5:30 pm" in Asia/Kolkata, from a Firestore Timestamp or Date. */
function formatWhen(dateLike) {
  const date = dateLike?.toDate ? dateLike.toDate() : dateLike instanceof Date ? dateLike : null;
  if (!date) return "";
  const datePart = new Intl.DateTimeFormat("en-IN", {
    timeZone: "Asia/Kolkata",
    day: "2-digit",
    month: "short",
  }).format(date);
  const timePart = new Intl.DateTimeFormat("en-IN", {
    timeZone: "Asia/Kolkata",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  }).format(date).toLowerCase();
  return `${datePart}, ${timePart}`;
}

/** Just the time part, e.g. "5:30 pm" — for same-day reminder copy. */
function formatTime(dateLike) {
  const date = dateLike?.toDate ? dateLike.toDate() : dateLike instanceof Date ? dateLike : null;
  if (!date) return "";
  return new Intl.DateTimeFormat("en-IN", {
    timeZone: "Asia/Kolkata",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  }).format(date).toLowerCase();
}

/**
 * Parses `appointments`' separate `date` ("yyyy-MM-dd") + `time`
 * ("hh:mm AM/PM") string fields into a Date — mirrors
 * `mednu/lib/core/services/booking_reminder_service.dart`'s
 * `_parseBookingTime` exactly, since there is no Timestamp field on this
 * collection to read instead. Returns null if either string is missing or
 * unparseable, so callers can fall back gracefully.
 */
function parseApptDateTime(dateStr, timeStr) {
  try {
    if (!dateStr || !timeStr) return null;
    const [y, mo, d] = dateStr.split("-").map(Number);
    const parts = timeStr.trim().split(" ");
    const [hStr, mStr] = parts[0].split(":");
    let h = Number(hStr);
    const m = Number(mStr);
    if (parts.length > 1) {
      const period = parts[1].toUpperCase();
      if (period === "PM" && h !== 12) h += 12;
      if (period === "AM" && h === 12) h = 0;
    }
    // The strings are IST wall-clock time, but Cloud Functions run in UTC —
    // build the instant explicitly as IST (UTC+5:30) so formatWhen() (which
    // renders in Asia/Kolkata) prints the same time the patient booked.
    const date = new Date(Date.UTC(y, mo - 1, d, h, m) - 330 * 60 * 1000);
    return Number.isNaN(date.getTime()) ? null : date;
  } catch (_) {
    return null;
  }
}

/** "BK-A1B2C3" fallback when no human-readable booking number exists. */
function shortId(docId, prefix = "BK") {
  const tail = (docId || "").replace(/[^a-zA-Z0-9]/g, "").slice(-6).toUpperCase();
  return `${prefix}-${tail || "000000"}`;
}

module.exports = {getRecipient, notifyOnce, formatWhen, formatTime, shortId, parseApptDateTime, cleanName};
