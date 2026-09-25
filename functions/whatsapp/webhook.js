/**
 * Inbound WhatsApp webhook: verification handshake (GET) + delivery
 * statuses / inbound messages (POST).
 */

const crypto = require("crypto");
const {onRequest} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {
  REGION,
  COLLECTIONS,
  PROVIDER_ROLES,
  APPOINTMENT_STATUS,
  WHATSAPP_TOKEN,
  WHATSAPP_APP_SECRET,
  WHATSAPP_VERIFY_TOKEN,
} = require("./config");
const {sendText, markRead, normalizePhone} = require("./whatsapp");

// ── Signature verification ──────────────────────────────────────────────
function _isValidSignature(req) {
  const header = req.get("x-hub-signature-256") || "";
  const expectedPrefix = "sha256=";
  if (!header.startsWith(expectedPrefix)) return false;

  const appSecret = WHATSAPP_APP_SECRET.value();
  const hmac = crypto.createHmac("sha256", appSecret);
  hmac.update(req.rawBody || Buffer.alloc(0));
  const digest = hmac.digest("hex");

  const given = Buffer.from(header.slice(expectedPrefix.length), "hex");
  const expected = Buffer.from(digest, "hex");
  if (given.length !== expected.length) return false;
  return crypto.timingSafeEqual(given, expected);
}

// ── Opt-out/opt-in via free text ────────────────────────────────────────
async function _setOptInForPhone(fromDigits, value) {
  const db = getFirestore();
  // Sender's number arrives from Meta as bare digits with country code (no
  // '+'); stored phone fields in this app are usually E.164 ('+91...') but
  // not guaranteed everywhere (see config.js's doctor-phone-format note) —
  // match both shapes so a legacy bare-digit record still gets caught.
  const candidates = [`+${fromDigits}`, fromDigits];
  const collections = [COLLECTIONS.users, ...PROVIDER_ROLES.map((r) => r.collection)];

  const updates = [];
  for (const col of collections) {
    for (const field of ["phone", "whatsappPhone"]) {
      for (const candidate of candidates) {
        updates.push(
          db
            .collection(col)
            .where(field, "==", candidate)
            .limit(5)
            .get()
            .then((snap) => Promise.all(snap.docs.map((d) => d.ref.set(
              {whatsappOptIn: value, whatsappOptInUpdatedAt: FieldValue.serverTimestamp()},
              {merge: true},
            )))),
        );
      }
    }
  }
  await Promise.all(updates).catch(() => {});
}

// ── Statuses (delivery receipts) ────────────────────────────────────────
async function _handleStatuses(statuses) {
  const db = getFirestore();
  await Promise.all(
    statuses.map(async (s) => {
      const messageId = s.id;
      if (!messageId) return;
      const snap = await db
        .collection(COLLECTIONS.whatsappLogs)
        .where("messageId", "==", messageId)
        .limit(1)
        .get();
      if (snap.empty) return;
      await snap.docs[0].ref.set(
        {deliveryStatus: s.status || "unknown", deliveryUpdatedAt: FieldValue.serverTimestamp()},
        {merge: true},
      );
    }),
  );
}

// ── Inbound messages (quick-reply button taps + free text) ─────────────
function _extractPayload(msg) {
  if (msg.button && msg.button.payload) return msg.button.payload;
  if (msg.interactive && msg.interactive.button_reply && msg.interactive.button_reply.id) {
    return msg.interactive.button_reply.id;
  }
  return null;
}

function _extractText(msg) {
  return msg.text && msg.text.body ? msg.text.body.trim() : null;
}

async function _handleMessages(messages) {
  const db = getFirestore();

  for (const msg of messages) {
    const from = msg.from; // bare digits, e.g. "919876543210"
    if (msg.id) await markRead(msg.id);

    const payload = _extractPayload(msg);
    if (payload) {
      const [action, refId] = payload.split(":");
      await _handleAction(db, action, refId, from);
      continue;
    }

    const text = (_extractText(msg) || "").toUpperCase();
    if (text === "STOP") {
      await _setOptInForPhone(from, false);
      await sendText(from, "You have been unsubscribed from MedNU WhatsApp updates. Reply START to opt back in.");
    } else if (text === "START") {
      await _setOptInForPhone(from, true);
      await sendText(from, "You are now subscribed to MedNU WhatsApp updates.");
    }
  }
}

async function _handleAction(db, action, appointmentId, fromDigits) {
  if (!action || !appointmentId) return;
  const apptRef = db.collection(COLLECTIONS.appointments).doc(appointmentId);
  const apptSnap = await apptRef.get();
  if (!apptSnap.exists) return;
  const appt = apptSnap.data();

  const senderDigits = normalizePhone(fromDigits);

  const patientSnap = appt.patientId ? await db.collection(COLLECTIONS.users).doc(appt.patientId).get() : null;
  const patientPhone = normalizePhone(patientSnap?.exists ? patientSnap.data().whatsappPhone || patientSnap.data().phone : null);

  const doctorSnap = appt.doctorId ? await db.collection(COLLECTIONS.doctors).doc(appt.doctorId).get() : null;
  const doctorPhone = normalizePhone(doctorSnap?.exists ? doctorSnap.data().whatsappPhone || doctorSnap.data().phone : null);

  const isPatient = senderDigits && patientPhone && senderDigits === patientPhone;
  const isDoctor = senderDigits && doctorPhone && senderDigits === doctorPhone;

  switch (action) {
    case "CANCEL": {
      if (!isPatient) return; // only the booking's own patient may cancel via WhatsApp.
      if (appt.status !== APPOINTMENT_STATUS.booked) return; // already cancelled/completed.
      await apptRef.update({
        status: APPOINTMENT_STATUS.cancelled,
        cancelledBy: "patient",
        updatedAt: FieldValue.serverTimestamp(),
      });
      // onAppointmentWritten (triggers.js) sends the booking_cancelled /
      // doctor_booking_cancelled templates off the back of this write.
      break;
    }
    case "CONFIRM": {
      if (!isPatient) return;
      await apptRef.set(
        {patientConfirmedAt: FieldValue.serverTimestamp()},
        {merge: true},
      );
      await sendText(fromDigits, "Thank you for confirming — we'll see you at your appointment. MedNU - Always With You");
      break;
    }
    case "RESCHEDULE": {
      if (!isPatient) return;
      await sendText(fromDigits, "To reschedule your appointment, please visit https://mednu.in or open the MedNU app.");
      break;
    }
    case "ACCEPT": {
      if (!isDoctor) return;
      if (appt.status !== APPOINTMENT_STATUS.booked) return;
      // No separate 'confirmed' status exists on this collection — 'booked'
      // already is the accepted/final state (see triggers.js's comment on
      // why booking_confirmed fires on create), so accepting is
      // acknowledgement-only and doesn't write a new status value the rest
      // of the app has no concept of.
      await sendText(fromDigits, "Thanks — this booking is confirmed on your schedule.");
      break;
    }
    case "DECLINE": {
      if (!isDoctor) return;
      if (appt.status !== APPOINTMENT_STATUS.booked) return;
      await apptRef.update({
        status: APPOINTMENT_STATUS.cancelled,
        cancelledBy: "doctor",
        updatedAt: FieldValue.serverTimestamp(),
      });
      await sendText(fromDigits, "You've declined this booking. The patient has been notified.");
      break;
    }
    default:
      break;
  }
}

// ── HTTP entry point ─────────────────────────────────────────────────────
const waWebhook = onRequest(
  {
    region: REGION,
    secrets: [WHATSAPP_TOKEN, WHATSAPP_APP_SECRET, WHATSAPP_VERIFY_TOKEN],
  },
  async (req, res) => {
    if (req.method === "GET") {
      const mode = req.query["hub.mode"];
      const token = req.query["hub.verify_token"];
      const challenge = req.query["hub.challenge"];
      if (mode === "subscribe" && token === WHATSAPP_VERIFY_TOKEN.value()) {
        res.status(200).send(challenge);
      } else {
        res.sendStatus(403);
      }
      return;
    }

    if (req.method !== "POST") {
      res.sendStatus(405);
      return;
    }

    if (!_isValidSignature(req)) {
      res.sendStatus(403);
      return;
    }

    try {
      const entries = req.body?.entry || [];
      for (const entry of entries) {
        for (const change of entry.changes || []) {
          const value = change.value || {};
          if (value.statuses) await _handleStatuses(value.statuses);
          if (value.messages) await _handleMessages(value.messages);
        }
      }
    } catch (e) {
      console.error("waWebhook: error processing payload", e);
    }

    // Always 200 once signature-verified and processing has been attempted —
    // Meta disables the webhook after repeated non-200 responses.
    res.sendStatus(200);
  },
);

module.exports = {waWebhook};
