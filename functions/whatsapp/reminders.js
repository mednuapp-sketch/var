/**
 * Every 10 minutes: WhatsApp reminders for doctor appointments starting
 * within the next hour.
 *
 * `appointments` has no Timestamp field to range-query (only separate
 * `date`/`time` strings — see config.js's comment on APPOINTMENT_STATUS).
 * Rather than adding one, this reads the `scheduled_reminders` queue that
 * `mednu/lib/core/services/booking_reminder_service.dart` already populates
 * with a precomputed `fireAt` Timestamp for every active booking (of every
 * type, not just doctor appointments) — a decision made explicitly with the
 * project owner to avoid touching booking-creation code in the Flutter app.
 *
 * Range query is on `fireAt` alone (server-side); `role`, and whether the
 * underlying booking is actually a still-active doctor appointment, are
 * filtered in code, matching the "range query only, filter in code" pattern
 * the project owner specified.
 */

const {onSchedule} = require("firebase-functions/v2/scheduler");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {
  REGION,
  COLLECTIONS,
  APPOINTMENT_STATUS,
  WHATSAPP_TOKEN,
  WHATSAPP_APP_SECRET,
  WHATSAPP_VERIFY_TOKEN,
  WHATSAPP_PHONE_NUMBER_ID,
} = require("./config");
const {getRecipient, notifyOnce, formatTime, shortId, cleanName, parseApptDateTime} = require("./notify");
const {istDateKey} = require("./reschedule");

const _LOOKAHEAD_MINUTES = 60;

const sendAppointmentReminders = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "Asia/Kolkata",
    region: REGION,
    secrets: [WHATSAPP_TOKEN, WHATSAPP_APP_SECRET, WHATSAPP_VERIFY_TOKEN],
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const until = new Date(now.getTime() + _LOOKAHEAD_MINUTES * 60 * 1000);

    const dueSnap = await db
      .collection(COLLECTIONS.scheduledReminders)
      .where("fireAt", ">=", Timestamp.fromDate(now))
      .where("fireAt", "<=", Timestamp.fromDate(until))
      .get();

    if (dueSnap.empty) return;

    await Promise.all(
      dueSnap.docs.map(async (doc) => {
        const r = doc.data();
        if (r.role !== "patient") return; // patient-facing reminder docs only.
        const bookingId = r.data && r.data.bookingId;
        if (!bookingId) return;

        const apptSnap = await db.collection(COLLECTIONS.appointments).doc(bookingId).get();
        if (!apptSnap.exists) return; // this reminder is for a non-appointment booking type.
        const appt = apptSnap.data();
        if (appt.status !== APPOINTMENT_STATUS.booked) return; // cancelled/completed since queued.

        // The template says "today at {{3}}", so show the APPOINTMENT's time,
        // not the reminder's fireAt (which is N minutes earlier). Skip
        // reminders that no longer fit the appointment — e.g. one queued for
        // the old time of a booking rescheduled over WhatsApp, before the
        // patient app has re-synced its reminders.
        const apptAt = parseApptDateTime(appt.date, appt.time);
        const fireAt = r.fireAt && r.fireAt.toDate ? r.fireAt.toDate() : null;
        if (!apptAt || apptAt <= now) return;
        if (istDateKey(apptAt) !== istDateKey(now)) return; // "today" in the copy
        if (fireAt && (fireAt > apptAt || apptAt - fireAt > 24 * 60 * 60 * 1000)) return;
        const time = formatTime(apptAt);
        const shortBookingId = appt.bookingNumber || appt.rxId || shortId(bookingId);
        // Dedupe key includes date+time so a reschedule (new date/time on the
        // same appointment doc) is treated as a fresh reminder rather than
        // silently suppressed by the original booking's dedupe record.
        const dedupeSuffix = `${appt.date || ""}:${appt.time || ""}`;

        const patient = await getRecipient(COLLECTIONS.users, appt.patientId, appt.patientName);
        if (patient) {
          await notifyOnce(
            `appointment_reminder:${bookingId}:${dedupeSuffix}`,
            patient,
            "mednu_appointment_reminder",
            [patient.firstName, cleanName(appt.doctorName) || "your doctor", time, shortBookingId],
            bookingId,
          );
        }

        const doctor = await getRecipient(COLLECTIONS.doctors, appt.doctorId, appt.doctorName);
        if (doctor) {
          await notifyOnce(
            `doctor_appointment_reminder:${bookingId}:${dedupeSuffix}`,
            doctor,
            "mednu_doctor_appointment_reminder",
            [doctor.firstName, cleanName(appt.patientName) || "a patient", time, shortBookingId],
            bookingId,
          );
        }
      }),
    );
  },
);

module.exports = {sendAppointmentReminders};
