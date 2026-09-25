/**
 * Firestore-write-driven WhatsApp notifications. Every export here is an
 * `onDocumentWritten` trigger with `retry: true` — `notify.notifyOnce`
 * throws on a retryable send failure specifically so Cloud Functions'
 * built-in retry mechanism re-invokes this handler, rather than this module
 * implementing its own retry loop.
 */

const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {getFirestore} = require("firebase-admin/firestore");
const {
  REGION,
  COLLECTIONS,
  PROVIDER_ROLES,
  APPOINTMENT_STATUS,
  ORDER_STATUS_LABEL,
  LAB_SERVICE_REQUEST_TYPES,
  LAB_STATUS_LABEL,
  LAB_REPORT_READY_STATUS,
  PAYMENT_STATUS,
  SETTLEMENT_STATUS,
  WHATSAPP_TOKEN,
  WHATSAPP_APP_SECRET,
  WHATSAPP_VERIFY_TOKEN,
  WHATSAPP_PHONE_NUMBER_ID,
} = require("./config");
const {getRecipient, notifyOnce, formatWhen, shortId, parseApptDateTime} = require("./notify");

// Every trigger needs at least the send secrets/params (notifyOnce ->
// sendTemplate reads them); listed once here and spread into each trigger's
// options so a secret rotation only needs updating in config.js.
const _SEND_SECRETS = [WHATSAPP_TOKEN, WHATSAPP_APP_SECRET, WHATSAPP_VERIFY_TOKEN];
const _SEND_PARAMS = [WHATSAPP_PHONE_NUMBER_ID];

// ── Bookings (appointments/{id}) ────────────────────────────────────────────
//
// Real status values are only 'booked' | 'cancelled' | 'completed' — there is
// no approval workflow (payment capture writes 'booked' directly), so
// booking_received + booking_confirmed both fire on create rather than
// waiting for a 'confirmed' transition that never happens (confirmed with
// the project owner). `doctor_on_the_way`/etaAt are deliberately NOT wired
// here — that's an ambulance/home-visit concept with no equivalent for
// regular doctor appointments; the template stays defined in templates.js,
// unused, for a future module that does have it.
const onAppointmentWritten = onDocumentWritten(
  {
    document: `${COLLECTIONS.appointments}/{appointmentId}`,
    region: REGION,
    retry: true,
    secrets: _SEND_SECRETS,
  },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return; // deleted — nothing to notify.

    const appointmentId = event.params.appointmentId;
    const bookingId = after.bookingNumber || after.rxId || shortId(appointmentId);
    const when = formatWhen(parseApptDateTime(after.date, after.time)) || `${after.date || ""} ${after.time || ""}`.trim();

    const isNew = !before;
    const statusChanged = before && before.status !== after.status;

    if (isNew) {
      const patient = await getRecipient(COLLECTIONS.users, after.patientId);
      if (patient) {
        await notifyOnce(
          `booking_received:${appointmentId}`,
          patient,
          "mednu_booking_received",
          [patient.firstName, after.doctorName || "your doctor", when, bookingId],
          appointmentId,
        );
        // No real 'pending -> confirmed' transition exists for this
        // collection — 'booked' already is the final state, so the
        // confirmation message is sent right alongside the received one.
        await notifyOnce(
          `booking_confirmed:${appointmentId}:${after.date || ""}:${after.time || ""}`,
          patient,
          "mednu_booking_confirmed",
          [patient.firstName, after.doctorName || "your doctor", when, bookingId],
          appointmentId,
        );
      }

      const doctor = await getRecipient(COLLECTIONS.doctors, after.doctorId);
      if (doctor) {
        await notifyOnce(
          `doctor_new_booking:${appointmentId}`,
          doctor,
          "mednu_doctor_new_booking",
          [doctor.firstName, after.consultationType || "appointment", after.patientName || "a patient", when],
          appointmentId,
        );
      }
      return;
    }

    if (statusChanged && after.status === APPOINTMENT_STATUS.cancelled) {
      const patient = await getRecipient(COLLECTIONS.users, after.patientId);
      if (patient) {
        await notifyOnce(
          `booking_cancelled:${appointmentId}`,
          patient,
          "mednu_booking_cancelled",
          [patient.firstName, after.doctorName || "your doctor", when, bookingId],
          appointmentId,
        );
      }

      // cancelledBy is written by both cancel call-sites (patient's
      // appointment_screen.dart and the doctor dashboard's cancel action) —
      // only notify the doctor when the PATIENT was the one who cancelled;
      // a doctor doesn't need a WhatsApp message about their own action.
      if (after.cancelledBy !== "doctor") {
        const doctor = await getRecipient(COLLECTIONS.doctors, after.doctorId);
        if (doctor) {
          await notifyOnce(
            `doctor_booking_cancelled:${appointmentId}`,
            doctor,
            "mednu_doctor_booking_cancelled",
            [doctor.firstName, after.patientName || "a patient", when, bookingId],
            appointmentId,
          );
        }
      }
    }
  },
);

// ── Medicine orders (orders/{id}) ───────────────────────────────────────────
const onOrderWritten = onDocumentWritten(
  {
    document: `${COLLECTIONS.orders}/{orderId}`,
    region: REGION,
    retry: true,
    secrets: _SEND_SECRETS,
  },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after || !before) return; // only react to status changes, not creation/deletion.
    if (before.status === after.status) return;

    const orderId = event.params.orderId;
    const label = ORDER_STATUS_LABEL[after.status];
    if (!label) return; // unmapped status (e.g. an internal-only value) — nothing user-facing to say.

    const patient = await getRecipient(COLLECTIONS.users, after.patientId);
    if (!patient) return;

    await notifyOnce(
      `order_update:${orderId}:${after.status}`,
      patient,
      "mednu_order_update",
      [patient.firstName, "medicine", shortId(orderId, "OD"), label],
      orderId,
    );
  },
);

// ── Lab / diagnostics (service_requests/{id} where type is diagnostics) ───
const onLabServiceRequestWritten = onDocumentWritten(
  {
    document: `${COLLECTIONS.serviceRequests}/{requestId}`,
    region: REGION,
    retry: true,
    secrets: _SEND_SECRETS,
  },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after || !before) return;
    if (!LAB_SERVICE_REQUEST_TYPES.includes((after.type || "").toLowerCase())) return;
    if (before.status === after.status) return;

    const requestId = event.params.requestId;
    const patient = await getRecipient(COLLECTIONS.users, after.patientId);
    if (!patient) return;
    const orderId = shortId(requestId, "OD");

    if (after.status === LAB_REPORT_READY_STATUS) {
      await notifyOnce(
        `report_ready:${requestId}`,
        patient,
        "mednu_report_ready",
        [patient.firstName, orderId],
        requestId,
      );
      return;
    }

    const label = LAB_STATUS_LABEL[after.status];
    if (!label) return;
    await notifyOnce(
      `order_update:${requestId}:${after.status}`,
      patient,
      "mednu_order_update",
      [patient.firstName, "lab test", orderId, label],
      requestId,
    );
  },
);

// ── Payments (payments/{id}) ────────────────────────────────────────────────
// Payment docs are created already at status:"completed" (no separate
// capture-then-complete transition on this collection) — react on create,
// and defensively also on an update that newly reaches "completed", using
// the same dedupe key either way so a double-fire is harmless.
const onPaymentWritten = onDocumentWritten(
  {
    document: `${COLLECTIONS.payments}/{paymentId}`,
    region: REGION,
    retry: true,
    secrets: _SEND_SECRETS,
  },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return;
    if (after.status !== PAYMENT_STATUS.completed) return;
    if (before && before.status === PAYMENT_STATUS.completed) return; // already handled.

    const paymentId = event.params.paymentId;
    const patient = await getRecipient(COLLECTIONS.users, after.patientId);
    if (!patient) return;

    const bookingId = shortId((after.bookingRef && after.bookingRef.id) || paymentId);
    const amount = Math.round(Number(after.paidAmount) || 0);

    await notifyOnce(
      `payment_received:${paymentId}`,
      patient,
      "mednu_payment_received",
      [patient.firstName, String(amount), bookingId],
      paymentId,
    );
  },
);

// ── Payouts (settlements/{id}) — shared across all 8 partner roles ─────────
async function _resolveProvider(providerId) {
  const db = getFirestore();
  for (const role of PROVIDER_ROLES) {
    const snap = await db.collection(role.collection).doc(providerId).get();
    if (snap.exists) return {role, doc: snap};
  }
  return null;
}

const onSettlementWritten = onDocumentWritten(
  {
    document: `${COLLECTIONS.settlements}/{settlementId}`,
    region: REGION,
    retry: true,
    secrets: _SEND_SECRETS,
  },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return;
    if (after.status !== SETTLEMENT_STATUS.paid) return;
    if (before && before.status === SETTLEMENT_STATUS.paid) return;

    const settlementId = event.params.settlementId;
    const providerId = after.providerId;
    if (!providerId) return;

    const resolved = await _resolveProvider(providerId);
    if (!resolved) return; // provider profile not found in any known role collection.

    const recipient = await getRecipient(resolved.role.collection, providerId);
    if (!recipient) return;

    const amount = Math.round(Number(after.totalAmount) || 0);
    const reference = after.payoutReference || shortId(settlementId, "PAY");

    await notifyOnce(
      `payout:${settlementId}`,
      recipient,
      resolved.role.payoutTemplate,
      [recipient.firstName, String(amount), reference],
      settlementId,
    );
  },
);

module.exports = {
  onAppointmentWritten,
  onOrderWritten,
  onLabServiceRequestWritten,
  onPaymentWritten,
  onSettlementWritten,
};
