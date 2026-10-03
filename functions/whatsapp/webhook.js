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
const {sendText, sendList, markRead, normalizePhone} = require("./whatsapp");
const {cleanName} = require("./notify");
const {freeSlotsByDay, dayLabel, spread, encodeSlot, decodeSlot} = require("./reschedule");

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
  // A row picked from a list message (the reschedule day/time pickers).
  if (msg.interactive && msg.interactive.list_reply && msg.interactive.list_reply.id) {
    return msg.interactive.list_reply.id;
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
      const [action, refId, ...args] = payload.split(":");
      await _handleAction(db, action, refId, from, args);
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

async function _handleAction(db, action, appointmentId, fromDigits, args = []) {
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
    // Reschedule is a two-step picker inside WhatsApp: the tap opens a 24h
    // service window, so free-form list messages are allowed. RESCHEDULE ->
    // list of days with free slots (RSDAY rows) -> list of that day's free
    // times (RSTIME rows) -> the appointment's date/time is moved.
    case "RESCHEDULE": {
      if (!isPatient) return;
      if (appt.status !== APPOINTMENT_STATUS.booked) {
        await sendText(fromDigits, "This appointment can no longer be rescheduled. Please open the MedNU app for details.");
        return;
      }
      const days = await freeSlotsByDay(appt.doctorId);
      if (!days.size) {
        await sendText(fromDigits,
          `Sorry, Dr. ${cleanName(appt.doctorName) || "your doctor"} has no free slots in the next 10 days. ` +
          "Your current appointment is unchanged.");
        return;
      }
      await sendList(fromDigits, {
        body: `Pick a new day for your appointment with Dr. ${cleanName(appt.doctorName) || "your doctor"}.`,
        button: "Choose a day",
        sectionTitle: "Available days",
        rows: [...days.entries()].slice(0, 10).map(([dateKey, slots]) => ({
          id: `RSDAY:${appointmentId}:${dateKey}`,
          title: dayLabel(dateKey),
          description: `${slots.length} slot${slots.length === 1 ? "" : "s"} free`,
        })),
      });
      break;
    }
    case "RSDAY": {
      if (!isPatient) return;
      if (appt.status !== APPOINTMENT_STATUS.booked) return;
      const dateKey = args[0];
      const slots = (await freeSlotsByDay(appt.doctorId)).get(dateKey) || [];
      if (!slots.length) {
        await sendText(fromDigits, "That day just filled up. Tap Reschedule again to see the latest free days.");
        return;
      }
      await sendList(fromDigits, {
        body: `Free times on ${dayLabel(dateKey)}. Pick one to move your appointment.`,
        button: "Choose a time",
        sectionTitle: dayLabel(dateKey),
        rows: spread(slots, 10).map((slot) => ({
          id: `RSTIME:${appointmentId}:${dateKey}:${encodeSlot(slot)}`,
          title: slot,
        })),
      });
      break;
    }
    case "RSTIME": {
      if (!isPatient) return;
      if (appt.status !== APPOINTMENT_STATUS.booked) return;
      const dateKey = args[0];
      const slot = decodeSlot(args[1]);
      if (!dateKey || !slot) return;
      if (appt.date === dateKey && appt.time === slot) return; // already there
      // Re-check right before writing; onAppointmentWrittenForSlots is still
      // the final arbiter and reverts the move if someone wins the race.
      const stillFree = ((await freeSlotsByDay(appt.doctorId)).get(dateKey) || []).includes(slot);
      if (!stillFree) {
        await sendText(fromDigits, `Sorry, ${slot} on ${dayLabel(dateKey)} was just taken. Tap Reschedule again to pick another time.`);
        return;
      }
      // Same fields the app's reschedule writes (doctor_profile_screen.dart).
      // onAppointmentWritten then sends the booking_confirmed template with
      // the new time, so no extra text is sent here.
      await apptRef.update({
        date: dateKey,
        time: slot,
        status: APPOINTMENT_STATUS.booked,
        rescheduledVia: "whatsapp",
        updatedAt: FieldValue.serverTimestamp(),
      });
      break;
    }
    case "ACCEPT": {
      if (!isDoctor) return;
      if (appt.status !== APPOINTMENT_STATUS.booked) {
        await sendText(fromDigits, "This booking was already cancelled, so there is nothing to accept.");
        return;
      }
      // No separate 'confirmed' status exists on this collection — 'booked'
      // already is the accepted/final state (see triggers.js's comment on
      // why booking_confirmed fires on create), so status stays as is; the
      // acceptance is recorded as its own field instead of a new status
      // value the rest of the app has no concept of.
      if (!appt.doctorAcceptedAt) {
        await apptRef.set({doctorAcceptedAt: FieldValue.serverTimestamp(), doctorAcceptedVia: "whatsapp"}, {merge: true});
      }
      const docName = cleanName(doctorSnap.data().name);
      await sendText(fromDigits,
        `Thanks${docName ? `, Dr. ${docName}` : ""}. The booking from ${cleanName(appt.patientName) || "your patient"} ` +
        `on ${dayLabel(appt.date)} at ${appt.time} is confirmed on your schedule.`);
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
