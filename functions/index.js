/* eslint-disable max-len */
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");
const Razorpay = require("razorpay");
const crypto = require("crypto");
const { RtcTokenBuilder, RtcRole } = require("agora-token");

initializeApp();

// ── Incoming Consultation Alert ──────────────────────────────────────────────
//
// Fires when a patient creates a new consultation document.
// Reads the assigned doctor's FCM token and sends a high-priority call
// notification so the doctor is alerted even when the app is killed.
// Doctor-initiated calls (dashboard_screen.dart's "Start Consultation" for a
// *scheduled* appointment — see `callerType: 'doctor'` written there) need to
// ring the PATIENT, not the doctor who just tapped the button. The patient
// app (mednu/lib/main.dart) already fully handles `type:'incoming_doctor_call'`
// in its background handler, notification-tap router, and foreground
// listener — it was just never actually sent. Deliberately data-only, no
// `notification` payload at any level: the client calls
// CallNotificationService.showIncomingCall() itself for this type in every
// app state, so a notification payload here would make the OS additionally
// auto-display a generic system notification alongside it.
// Provider-initiated call types that ring the PATIENT rather than the
// provider — originally just 'doctor' (dashboard_screen.dart's "Start
// Consultation"); Physiotherapist/Counsellor sessions reuse the exact same
// `consultations` doc shape and push path (see PhysioOutgoingCallScreen /
// CounsellingOutgoingCallScreen in mednu_doctor), just with `doctorId`/
// `doctorName`/etc. holding the provider's own identity instead of a
// doctor's — kept in those literal field names rather than renamed to
// `providerId` so every existing consumer (generateAgoraToken's auth check,
// the patient app's push handler/live listener/IncomingCallScreen) needs
// zero changes to already work for the new roles.
const _PROVIDER_INITIATED_CALLER_TYPES = ["doctor", "physiotherapist", "counsellor"];

function _providerRoleLabel(callerType) {
  switch (callerType) {
    case "physiotherapist": return "Physiotherapist";
    case "counsellor": return "Counsellor";
    default: return "Doctor";
  }
}

async function _pushIncomingDoctorCallToPatient(data, consultationId) {
  const patientId = data.patientId;
  if (!patientId) return;

  let fcmToken = null;
  try {
    const userDoc = await getFirestore().collection("users").doc(patientId).get();
    if (userDoc.exists) fcmToken = userDoc.data()?.fcmToken || null;
  } catch (_) {}
  if (!fcmToken) {
    console.log(`Patient ${patientId} has no FCM token — incoming doctor call push skipped.`);
    return;
  }

  const message = {
    token: fcmToken,
    data: {
      type: "incoming_doctor_call",
      consultationId,
      doctorId: data.doctorId || "",
      doctorName: data.doctorName || "Doctor",
      doctorSpecialty: data.doctorSpecialty || "",
      doctorPhotoUrl: data.doctorPhotoUrl || "",
      providerRole: data.callerType || "doctor",
    },
    android: { priority: "high" },
    apns: {
      headers: { "apns-priority": "10", "apns-push-type": "background" },
      payload: { aps: { "content-available": 1 } },
    },
  };

  try {
    const response = await getMessaging().send(message);
    console.log(`Incoming-doctor-call FCM sent to patient ${patientId}: ${response}`);
  } catch (err) {
    console.error(`Incoming-doctor-call FCM failed for patient ${patientId}:`, err);
  }
}

exports.onNewConsultation = onDocumentCreated(
  "consultations/{consultationId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (data.status !== "pending") return;

    const consultationId = event.params.consultationId;
    if (_PROVIDER_INITIATED_CALLER_TYPES.includes(data.callerType)) {
      await _pushIncomingDoctorCallToPatient(data, consultationId);
      return;
    }

    const doctorId = data.doctorId;
    if (!doctorId) return;

    // Fetch the doctor's FCM token from Firestore.
    const doctorDoc = await getFirestore()
      .collection("doctors")
      .doc(doctorId)
      .get();

    if (!doctorDoc.exists) return;

    const fcmToken = doctorDoc.data().fcmToken;
    if (!fcmToken) {
      console.log(`Doctor ${doctorId} has no FCM token — skipping push.`);
      return;
    }

    const patientName = data.patientName || "Patient";
    const complaint = data.chiefComplaint || "";
    const consultationType = data.consultationType || "Video";

    const message = {
      token: fcmToken,

      // Data payload: Flutter app receives this in foreground & background.
      data: {
        type: "incoming_consultation",
        consultationId,
        patientName,
        complaint,
        consultationType,
        doctorId,
      },

      // Android: high-priority delivery wakes up killed apps.
      android: {
        priority: "high",
        notification: {
          channelId: "incoming_call",
          priority: "max",
          sound: "default",
          defaultVibrateTimings: false,
          vibrateTimingsMillis: ["0", "800", "200", "800", "200", "800", "200", "800"],
          title: `📞 Incoming from ${patientName}`,
          body: complaint || "Patient is requesting a consultation",
        },
      },

      // APNs: critical alert bypasses silent mode on iOS.
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
        payload: {
          aps: {
            alert: {
              title: `📞 Incoming from ${patientName}`,
              body: complaint || "Patient is requesting a consultation",
            },
            sound: "default",
            badge: 1,
            "content-available": 1,
            "interruption-level": "critical",
          },
        },
      },
    };

    try {
      const response = await getMessaging().send(message);
      console.log(`FCM sent to doctor ${doctorId}: ${response}`);
    } catch (err) {
      console.error(`FCM failed for doctor ${doctorId}:`, err);
    }
  }
);

// ── Doctor Rating Aggregation (server-authoritative) ────────────────────────
//
// `doctors/{id}.rating`, `doctors/{id}.totalReviews` and the whole
// `doctor_rating_summary/{id}` document are Cloud-Function-only: firestore.rules
// denies every client write to them (admin-only), exactly like the *_transactions
// ledgers. This helper is the single place that folds one new star rating into
// both aggregates, so the two can never disagree.
//
// NOTE: a Firestore transaction requires every read to happen before every
// write — the mirror onto `doctors/{id}` therefore reuses the value computed
// here instead of re-reading the summary after writing it.
async function _applyDoctorRating(db, doctorId, rating) {
  const summaryRef = db.collection("doctor_rating_summary").doc(doctorId);
  const doctorRef = db.collection("doctors").doc(doctorId);

  await db.runTransaction(async (tx) => {
    const summarySnap = await tx.get(summaryRef);
    const doctorSnap = await tx.get(doctorRef);

    const data = summarySnap.exists ? summarySnap.data() : {};
    const oldTotal = data.totalReviews || 0;
    const oldAvg = data.averageRating || 0;
    const newTotal = oldTotal + 1;
    const newAvg = parseFloat(((oldAvg * oldTotal + rating) / newTotal).toFixed(2));

    const dist = data.ratingDistribution || { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
    const bucket = String(Math.min(5, Math.max(1, Math.round(rating))));
    dist[bucket] = (dist[bucket] || 0) + 1;

    tx.set(
      summaryRef,
      {
        doctorId,
        averageRating: newAvg,
        totalReviews: newTotal,
        ratingDistribution: dist,
        lastUpdated: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // Mirror onto the doctors document for query-time sorting/listing. The doc
    // may legitimately not exist (deleted doctor) — skip rather than fail the
    // whole transaction, since this function is now the only writer.
    if (doctorSnap.exists) {
      tx.update(doctorRef, { rating: newAvg, totalReviews: newTotal });
    }
  });

  console.log(`Rating aggregate updated for doctor ${doctorId}`);
}

// ── Review Created: Aggregate Rating ────────────────────────────────────────
//
// Fires when a patient submits a new review. Updates the doctor_rating_summary
// document atomically so ratings are always consistent and realtime.
exports.onReviewCreated = onDocumentCreated(
  "doctor_reviews/{reviewId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const review = snap.data();
    const doctorId = review.doctorId;
    const rating = review.rating;

    if (!doctorId || typeof rating !== "number" || !isFinite(rating) || rating <= 0) return;
    if (doctorId === review.patientId) return;

    await _applyDoctorRating(getFirestore(), doctorId, rating);
  }
);

// ── Post-consultation Feedback Created: Aggregate Rating ────────────────────
//
// The post-consultation feedback screen writes a `feedbacks` document (a
// separate entry point from `doctor_reviews`) carrying a star rating. It used
// to fold that star into the aggregates client-side; now that the aggregates
// are Cloud-Function-only, that fold happens here instead. Feedback rows
// without a usable rating/doctorId are ignored.
exports.onFeedbackCreated = onDocumentCreated(
  "feedbacks/{feedbackId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const fb = snap.data();
    const doctorId = fb.doctorId;
    const rating = fb.rating;

    if (!doctorId || typeof rating !== "number" || !isFinite(rating) || rating <= 0) return;
    if (doctorId === fb.patientId) return;

    await _applyDoctorRating(getFirestore(), doctorId, rating);
  }
);

// ── Appointment Completed: Prompt Patient to Review ──────────────────────────
//
// When an appointment is marked completed, send the patient a push notification
// inviting them to rate their doctor. Only fires on status → completed transitions.
exports.onAppointmentCompleted = onDocumentUpdated(
  "appointments/{appointmentId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    if (before.status === after.status) return;
    if (after.status !== "completed") return;

    const patientId = after.patientId;
    const doctorName = after.doctorName || "your doctor";
    const appointmentId = event.params.appointmentId;

    if (!patientId) return;

    // Check if patient already reviewed this appointment.
    const db = getFirestore();
    const existingReview = await db
      .collection("appointment_reviews")
      .doc(appointmentId)
      .get();

    if (existingReview.exists && existingReview.data().reviewed) return;

    // Was FCM-only (no in-app record) — switched to the shared helper so
    // the prompt also shows up in the patient's notification bell, not just
    // as a push that's easy to miss/dismiss.
    await _sendPatientNotification(db, getMessaging(), patientId, {
      title: `How was your visit with ${doctorName}?`,
      body: "Share your experience to help other patients.",
      type: "review_prompt",
      bookingId: appointmentId,
      doctorId: after.doctorId || "",
      extraData: { doctorName },
    });
  }
);

// ── Serious Issue Alert to Admin ─────────────────────────────────────────────
//
// Fires ONLY for genuine patient safety issues or abuse reports — not for
// routine low ratings. Writes to admin_alerts so the admin panel surfaces it.
exports.onSeriousComplaint = onDocumentCreated(
  "serious_complaints/{complaintId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const db = getFirestore();

    await db.collection("admin_alerts").add({
      type: "serious_complaint",
      severity: data.severity || "high",
      patientId: data.patientId || "",
      doctorId: data.doctorId || "",
      patientName: data.patientName || "Unknown Patient",
      doctorName: data.doctorName || "Unknown Doctor",
      reason: data.reason || "",
      complaintId: event.params.complaintId,
      createdAt: FieldValue.serverTimestamp(),
      isRead: false,
    });

    // This write-only-no-push was the gap: every other admin_alerts producer
    // goes through _sendAdminAlert (which pushes too); this one and
    // onEmergencyDoctorRequest built their own structured doc directly and
    // never pushed. See _pushToAllAdmins' comment above.
    await _pushToAllAdmins(db, getMessaging(), {
      title: "🚨 Serious Complaint",
      body: `${data.patientName || "A patient"} reported an issue with Dr. ${data.doctorName || "Unknown"}.`,
      type: "serious_complaint",
    });

    console.log(`Serious complaint alert created for complaint ${event.params.complaintId}`);
  }
);

// ── Weekly Consultation Quality Report ───────────────────────────────────────
//
// Runs every Monday at 08:00 IST. Aggregates the past 7 days of feedback,
// reviews, and appointments into a structured quality report stored in
// weekly_quality_reports. Normal poor ratings go here — not as realtime alerts.
exports.generateWeeklyQualityReport = onSchedule(
  { schedule: "0 8 * * 1", timeZone: "Asia/Kolkata" },
  async () => {
    const db = getFirestore();
    const now = new Date();

    const weekEnd = new Date(now);
    const weekStart = new Date(now);
    weekStart.setDate(weekStart.getDate() - 7);
    weekStart.setHours(0, 0, 0, 0);
    weekEnd.setHours(23, 59, 59, 999);

    const weekStartTs = Timestamp.fromDate(weekStart);
    const weekEndTs = Timestamp.fromDate(weekEnd);

    // ── Collect feedback for the week ────────────────────────────────────────
    const feedbackSnap = await db.collection("feedbacks")
      .where("createdAt", ">=", weekStartTs)
      .where("createdAt", "<=", weekEndTs)
      .get();

    // ── Collect doctor reviews for the week ──────────────────────────────────
    const reviewsSnap = await db.collection("doctor_reviews")
      .where("createdAt", ">=", weekStartTs)
      .where("createdAt", "<=", weekEndTs)
      .get();

    // ── Collect appointments for the week ────────────────────────────────────
    const appointmentsSnap = await db.collection("appointments")
      .where("createdAt", ">=", weekStartTs)
      .where("createdAt", "<=", weekEndTs)
      .get();

    // ── Aggregate per-doctor stats ───────────────────────────────────────────
    const doctorMap = {};

    const ensureDoctor = (id, name, specialty) => {
      if (!doctorMap[id]) {
        doctorMap[id] = {
          doctorId: id,
          doctorName: name || "Unknown Doctor",
          specialty: specialty || "",
          feedbackCount: 0,
          ratingSum: 0,
          poorCount: 0,
          satisfiedCount: 0,
          totalAppointments: 0,
          cancelledAppointments: 0,
          missedAppointments: 0,
        };
      }
    };

    feedbackSnap.forEach(doc => {
      const d = doc.data();
      if (!d.doctorId) return;
      ensureDoctor(d.doctorId, d.doctorName, d.specialty);
      const entry = doctorMap[d.doctorId];
      if (typeof d.rating === "number") {
        entry.feedbackCount++;
        entry.ratingSum += d.rating;
        if (d.rating <= 2) entry.poorCount++;
        if (d.rating >= 4) entry.satisfiedCount++;
      }
    });

    reviewsSnap.forEach(doc => {
      const d = doc.data();
      if (!d.doctorId) return;
      ensureDoctor(d.doctorId, d.doctorName, d.specialty);
      const entry = doctorMap[d.doctorId];
      if (typeof d.rating === "number") {
        entry.feedbackCount++;
        entry.ratingSum += d.rating;
        if (d.rating <= 2) entry.poorCount++;
        if (d.rating >= 4) entry.satisfiedCount++;
      }
    });

    appointmentsSnap.forEach(doc => {
      const d = doc.data();
      if (!d.doctorId) return;
      ensureDoctor(d.doctorId, d.doctorName || d.doctor, "");
      const entry = doctorMap[d.doctorId];
      entry.totalAppointments++;
      if (d.status === "cancelled") entry.cancelledAppointments++;
      if (d.status === "no_show") entry.missedAppointments++;
    });

    // ── Compute derived metrics per doctor ───────────────────────────────────
    const ratingDistribution = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
    let platformRatingSum = 0;
    let platformFeedbackCount = 0;
    let platformPoorCount = 0;
    let platformSatisfiedCount = 0;
    let platformCancelled = 0;
    let platformMissed = 0;
    let platformTotal = 0;

    feedbackSnap.forEach(doc => {
      const r = doc.data().rating;
      if (typeof r === "number") {
        const bucket = Math.round(r).toString();
        if (ratingDistribution[bucket] !== undefined) ratingDistribution[bucket]++;
      }
    });

    const doctorStats = {};
    const topPerformers = [];
    const lowPerformers = [];

    Object.values(doctorMap).forEach(entry => {
      const avgRating = entry.feedbackCount > 0
        ? parseFloat((entry.ratingSum / entry.feedbackCount).toFixed(2))
        : null;

      const satisfactionPercent = entry.feedbackCount > 0
        ? Math.round((entry.satisfiedCount / entry.feedbackCount) * 100)
        : null;

      const poorPercent = entry.feedbackCount > 0
        ? Math.round((entry.poorCount / entry.feedbackCount) * 100)
        : 0;

      const cancellationPercent = entry.totalAppointments > 0
        ? Math.round((entry.cancelledAppointments / entry.totalAppointments) * 100)
        : 0;

      const flagReasons = [];
      if (avgRating !== null && avgRating < 3.0) flagReasons.push("Low average rating");
      if (satisfactionPercent !== null && satisfactionPercent < 50) flagReasons.push("Low patient satisfaction");
      if (poorPercent > 30) flagReasons.push("High poor-rating ratio");
      if (cancellationPercent > 40) flagReasons.push("High cancellation rate");
      if (entry.missedAppointments > 3) flagReasons.push("Frequent missed appointments");

      const isFlagged = flagReasons.length > 0;

      const stat = {
        doctorId: entry.doctorId,
        doctorName: entry.doctorName,
        specialty: entry.specialty,
        feedbackCount: entry.feedbackCount,
        avgRating,
        poorCount: entry.poorCount,
        satisfactionPercent,
        poorPercent,
        totalAppointments: entry.totalAppointments,
        cancelledAppointments: entry.cancelledAppointments,
        cancellationPercent,
        missedAppointments: entry.missedAppointments,
        isFlagged,
        flagReasons,
      };

      doctorStats[entry.doctorId] = stat;

      platformFeedbackCount += entry.feedbackCount;
      platformRatingSum += entry.ratingSum;
      platformPoorCount += entry.poorCount;
      platformSatisfiedCount += entry.satisfiedCount;
      platformCancelled += entry.cancelledAppointments;
      platformMissed += entry.missedAppointments;
      platformTotal += entry.totalAppointments;

      if (avgRating !== null && avgRating >= 4.5 && entry.feedbackCount >= 3) {
        topPerformers.push({ doctorId: entry.doctorId, doctorName: entry.doctorName, avgRating, satisfactionPercent });
      }
      if (isFlagged) {
        lowPerformers.push({ doctorId: entry.doctorId, doctorName: entry.doctorName, specialty: entry.specialty, avgRating, satisfactionPercent, flagReasons });
      }
    });

    topPerformers.sort((a, b) => (b.avgRating || 0) - (a.avgRating || 0));
    lowPerformers.sort((a, b) => (a.avgRating || 99) - (b.avgRating || 99));

    const platformAvgRating = platformFeedbackCount > 0
      ? parseFloat((platformRatingSum / platformFeedbackCount).toFixed(2))
      : null;

    const platformSatisfactionPercent = platformFeedbackCount > 0
      ? Math.round((platformSatisfiedCount / platformFeedbackCount) * 100)
      : null;

    const platformPoorPercent = platformFeedbackCount > 0
      ? Math.round((platformPoorCount / platformFeedbackCount) * 100)
      : 0;

    // ── Compute ISO week label (e.g. "2026-W21") ────────────────────────────
    const startYear = weekStart.getFullYear();
    const startDay = weekStart.getDay() || 7;
    const thursday = new Date(weekStart);
    thursday.setDate(weekStart.getDate() + (4 - startDay));
    const yearStart = new Date(thursday.getFullYear(), 0, 1);
    const weekNum = Math.ceil(((thursday - yearStart) / 86400000 + 1) / 7);
    const reportId = `${startYear}-W${String(weekNum).padStart(2, "0")}`;

    await db.collection("weekly_quality_reports").doc(reportId).set({
      reportId,
      weekStart: weekStartTs,
      weekEnd: weekEndTs,
      generatedAt: FieldValue.serverTimestamp(),
      generatedBy: "scheduled",
      platformStats: {
        totalFeedback: platformFeedbackCount,
        avgRating: platformAvgRating,
        satisfactionPercent: platformSatisfactionPercent,
        poorConsultationPercent: platformPoorPercent,
        totalAppointments: platformTotal,
        totalCancelled: platformCancelled,
        totalMissed: platformMissed,
        flaggedDoctorsCount: lowPerformers.length,
      },
      ratingDistribution,
      doctorStats,
      topPerformers: topPerformers.slice(0, 10),
      lowPerformers: lowPerformers.slice(0, 10),
    });

    console.log(`Weekly quality report ${reportId} generated successfully.`);
  }
);

// ── Manual Report Trigger ────────────────────────────────────────────────────
//
// Admin can write to report_triggers collection to generate a report on demand.
exports.onManualReportTrigger = onDocumentCreated(
  "report_triggers/{triggerId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (data.type !== "weekly_quality") return;

    const db = getFirestore();
    const now = new Date();

    const weekEnd = new Date(now);
    weekEnd.setHours(23, 59, 59, 999);
    const weekStart = new Date(now);
    weekStart.setDate(weekStart.getDate() - 7);
    weekStart.setHours(0, 0, 0, 0);

    const weekStartTs = Timestamp.fromDate(weekStart);
    const weekEndTs = Timestamp.fromDate(weekEnd);

    const feedbackSnap = await db.collection("feedbacks")
      .where("createdAt", ">=", weekStartTs)
      .where("createdAt", "<=", weekEndTs)
      .get();

    const reviewsSnap = await db.collection("doctor_reviews")
      .where("createdAt", ">=", weekStartTs)
      .where("createdAt", "<=", weekEndTs)
      .get();

    const appointmentsSnap = await db.collection("appointments")
      .where("createdAt", ">=", weekStartTs)
      .where("createdAt", "<=", weekEndTs)
      .get();

    const doctorMap = {};
    const ensureDoctor = (id, name, specialty) => {
      if (!doctorMap[id]) {
        doctorMap[id] = {
          doctorId: id, doctorName: name || "Unknown Doctor", specialty: specialty || "",
          feedbackCount: 0, ratingSum: 0, poorCount: 0, satisfiedCount: 0,
          totalAppointments: 0, cancelledAppointments: 0, missedAppointments: 0,
        };
      }
    };

    feedbackSnap.forEach(doc => {
      const d = doc.data();
      if (!d.doctorId) return;
      ensureDoctor(d.doctorId, d.doctorName, d.specialty);
      const entry = doctorMap[d.doctorId];
      if (typeof d.rating === "number") {
        entry.feedbackCount++;
        entry.ratingSum += d.rating;
        if (d.rating <= 2) entry.poorCount++;
        if (d.rating >= 4) entry.satisfiedCount++;
      }
    });

    reviewsSnap.forEach(doc => {
      const d = doc.data();
      if (!d.doctorId) return;
      ensureDoctor(d.doctorId, d.doctorName, d.specialty);
      const entry = doctorMap[d.doctorId];
      if (typeof d.rating === "number") {
        entry.feedbackCount++;
        entry.ratingSum += d.rating;
        if (d.rating <= 2) entry.poorCount++;
        if (d.rating >= 4) entry.satisfiedCount++;
      }
    });

    appointmentsSnap.forEach(doc => {
      const d = doc.data();
      if (!d.doctorId) return;
      ensureDoctor(d.doctorId, d.doctorName || d.doctor, "");
      const entry = doctorMap[d.doctorId];
      entry.totalAppointments++;
      if (d.status === "cancelled") entry.cancelledAppointments++;
      if (d.status === "no_show") entry.missedAppointments++;
    });

    const ratingDistribution = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
    feedbackSnap.forEach(doc => {
      const r = doc.data().rating;
      if (typeof r === "number") {
        const b = Math.round(r).toString();
        if (ratingDistribution[b] !== undefined) ratingDistribution[b]++;
      }
    });

    let platformRatingSum = 0; let platformFeedbackCount = 0; let platformPoorCount = 0;
    let platformSatisfiedCount = 0; let platformCancelled = 0; let platformMissed = 0; let platformTotal = 0;
    const doctorStats = {};
    const topPerformers = [];
    const lowPerformers = [];

    Object.values(doctorMap).forEach(entry => {
      const avgRating = entry.feedbackCount > 0 ? parseFloat((entry.ratingSum / entry.feedbackCount).toFixed(2)) : null;
      const satisfactionPercent = entry.feedbackCount > 0 ? Math.round((entry.satisfiedCount / entry.feedbackCount) * 100) : null;
      const poorPercent = entry.feedbackCount > 0 ? Math.round((entry.poorCount / entry.feedbackCount) * 100) : 0;
      const cancellationPercent = entry.totalAppointments > 0 ? Math.round((entry.cancelledAppointments / entry.totalAppointments) * 100) : 0;
      const flagReasons = [];
      if (avgRating !== null && avgRating < 3.0) flagReasons.push("Low average rating");
      if (satisfactionPercent !== null && satisfactionPercent < 50) flagReasons.push("Low patient satisfaction");
      if (poorPercent > 30) flagReasons.push("High poor-rating ratio");
      if (cancellationPercent > 40) flagReasons.push("High cancellation rate");
      if (entry.missedAppointments > 3) flagReasons.push("Frequent missed appointments");
      const isFlagged = flagReasons.length > 0;
      doctorStats[entry.doctorId] = { ...entry, avgRating, satisfactionPercent, poorPercent, cancellationPercent, isFlagged, flagReasons };
      platformFeedbackCount += entry.feedbackCount;
      platformRatingSum += entry.ratingSum;
      platformPoorCount += entry.poorCount;
      platformSatisfiedCount += entry.satisfiedCount;
      platformCancelled += entry.cancelledAppointments;
      platformMissed += entry.missedAppointments;
      platformTotal += entry.totalAppointments;
      if (avgRating !== null && avgRating >= 4.5 && entry.feedbackCount >= 3) {
        topPerformers.push({ doctorId: entry.doctorId, doctorName: entry.doctorName, avgRating, satisfactionPercent });
      }
      if (isFlagged) lowPerformers.push({ doctorId: entry.doctorId, doctorName: entry.doctorName, specialty: entry.specialty, avgRating, satisfactionPercent, flagReasons });
    });

    topPerformers.sort((a, b) => (b.avgRating || 0) - (a.avgRating || 0));
    lowPerformers.sort((a, b) => (a.avgRating || 99) - (b.avgRating || 99));

    const platformAvgRating = platformFeedbackCount > 0 ? parseFloat((platformRatingSum / platformFeedbackCount).toFixed(2)) : null;
    const platformSatisfactionPercent = platformFeedbackCount > 0 ? Math.round((platformSatisfiedCount / platformFeedbackCount) * 100) : null;
    const platformPoorPercent = platformFeedbackCount > 0 ? Math.round((platformPoorCount / platformFeedbackCount) * 100) : 0;

    const startYear = weekStart.getFullYear();
    const startDay = weekStart.getDay() || 7;
    const thursday = new Date(weekStart);
    thursday.setDate(weekStart.getDate() + (4 - startDay));
    const yearStart = new Date(thursday.getFullYear(), 0, 1);
    const weekNum = Math.ceil(((thursday - yearStart) / 86400000 + 1) / 7);
    const reportId = `manual-${startYear}-W${String(weekNum).padStart(2, "0")}-${Date.now()}`;

    await db.collection("weekly_quality_reports").doc(reportId).set({
      reportId,
      weekStart: weekStartTs,
      weekEnd: weekEndTs,
      generatedAt: FieldValue.serverTimestamp(),
      generatedBy: "manual",
      platformStats: {
        totalFeedback: platformFeedbackCount,
        avgRating: platformAvgRating,
        satisfactionPercent: platformSatisfactionPercent,
        poorConsultationPercent: platformPoorPercent,
        totalAppointments: platformTotal,
        totalCancelled: platformCancelled,
        totalMissed: platformMissed,
        flaggedDoctorsCount: lowPerformers.length,
      },
      ratingDistribution,
      doctorStats,
      topPerformers: topPerformers.slice(0, 10),
      lowPerformers: lowPerformers.slice(0, 10),
    });

    await db.collection("report_triggers").doc(event.params.triggerId).update({
      status: "completed",
      completedAt: FieldValue.serverTimestamp(),
      generatedReportId: reportId,
    });

    console.log(`Manual quality report ${reportId} generated.`);
  }
);

// ── Consultation Status Change Alert ─────────────────────────────────────────
//
// Notifies the patient when the doctor accepts or declines their request.
// Patient FCM token is read directly from the consultation document
// (written by the patient app at call-creation time) to avoid a separate
// Firestore lookup that could fail if the user is in a different collection.
exports.onConsultationStatusChange = onDocumentUpdated(
  "consultations/{consultationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    // Only fire on meaningful status transitions.
    if (before.status === after.status) return;

    const patientId = after.patientId;
    if (!patientId) return;

    // Primary: use the token stored on the consultation doc itself.
    let fcmToken = after.patientFcmToken || null;

    // Fallback: look up from the users collection.
    if (!fcmToken) {
      try {
        const userDoc = await getFirestore()
          .collection("users")
          .doc(patientId)
          .get();
        if (userDoc.exists) fcmToken = userDoc.data()?.fcmToken || null;
      } catch (_) {}
    }

    if (!fcmToken) {
      console.log(`No FCM token for patient ${patientId} — skipping push.`);
      return;
    }

    const roleLabel = _providerRoleLabel(after.callerType);
    const roleLabelLower = roleLabel.toLowerCase();

    let title = "";
    let body = "";

    if (after.status === "ongoing") {
      title = `${roleLabel} accepted your request`;
      body = `${after.doctorName || `Your ${roleLabelLower}`} is joining the call now.`;
    } else if (after.status === "declined") {
      title = "Request declined";
      body = `${after.doctorName || `The ${roleLabelLower}`} is unavailable right now. Please try again.`;
    } else if (after.status === "missed") {
      title = "No answer";
      body = `The ${roleLabelLower} did not respond. Please try again or schedule an appointment.`;
    } else if (after.status === "completed" || after.status === "ended") {
      title = "Consultation completed";
      body = `Your session with ${after.doctorName || `the ${roleLabelLower}`} has ended.`;
    } else {
      return; // Ignore other status values (e.g. active, cancelled).
    }

    const message = {
      token: fcmToken,
      data: {
        type: "consultation_update",
        status: after.status,
        consultationId: event.params.consultationId,
        doctorName: after.doctorName || "",
      },
      android: {
        priority: "high",
        notification: { title, body, channelId: "default" },
      },
      apns: {
        headers: { "apns-priority": "10" },
        payload: { aps: { alert: { title, body }, sound: "default" } },
      },
    };

    try {
      await getMessaging().send(message);
    } catch (err) {
      console.error("Status-change FCM failed:", err);
    }
  }
);

// ── Emergency Doctor Request ──────────────────────────────────────────────────
//
// Fires when a patient taps "Emergency Doctor". Deduplicates within 5 minutes,
// then broadcasts a critical FCM to every active doctor and writes an
// admin_alerts doc so the admin panel surfaces it instantly.
exports.onEmergencyDoctorRequest = onDocumentCreated(
  "service_requests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();

    if (data.type !== "emergency_doctor") return;

    const db = getFirestore();
    const patientId = data.patientId;
    const requestId = event.params.requestId;

    // Deduplication: 1 emergency per patient per 5 minutes.
    const fiveMinAgo = Timestamp.fromDate(new Date(Date.now() - 5 * 60 * 1000));
    const recentSnap = await db.collection("service_requests")
      .where("type", "==", "emergency_doctor")
      .where("patientId", "==", patientId)
      .where("status", "==", "pending")
      .where("createdAt", ">", fiveMinAgo)
      .get();

    const duplicates = recentSnap.docs.filter((d) => d.id !== requestId);
    if (duplicates.length > 0) {
      await snap.ref.update({
        status: "duplicate",
        reason: "Throttled — previous request still active",
      });
      console.log(`Emergency duplicate from ${patientId} — throttled.`);
      return;
    }

    // Resolve patient name.
    let patientName = "Patient";
    try {
      const userDoc = await db.collection("users").doc(patientId).get();
      if (userDoc.exists) {
        const u = userDoc.data();
        patientName = u.name || u.fullName || u.displayName || "Patient";
      }
    } catch (_) {}

    // Fetch ALL active doctors that have an FCM token.
    //
    // The `doctors` collection is shared by every partner role (doctor,
    // ambulance, pharmacy, lab, caregiver) in the mednu_doctor app — a
    // partner's `roles` array says which. Firestore can't express "array-
    // contains 'doctor' OR roles field missing" as a single query, and a
    // missing/empty `roles` field must still count as a doctor (legacy
    // accounts predate the field — see AppRoleX.listFrom's same fallback
    // on the client), so the role check happens in-memory after the fetch
    // rather than as a query-level filter.
    const doctorsSnap = await db.collection("doctors")
      .where("status", "==", "active")
      .get();

    const tokens = [];
    const doctorIds = [];
    doctorsSnap.forEach((doc) => {
      const data = doc.data();
      const roles = Array.isArray(data.roles) && data.roles.length > 0 ? data.roles : ["doctor"];
      if (!roles.includes("doctor")) return;

      const token = data.fcmToken;
      if (token) {
        tokens.push(token);
        doctorIds.push(doc.id);
      }
    });

    const notifTitle = "🚨 Emergency Doctor Request";
    const notifBody = `${patientName} needs immediate medical assistance.${
      data.latitude ? " Location shared." : ""
    }`;

    // Broadcast FCM in 500-token chunks (API limit).
    for (let i = 0; i < tokens.length; i += 500) {
      const chunk = tokens.slice(i, i + 500);
      const message = {
        tokens: chunk,
        data: {
          type: "emergency_doctor_request",
          requestId,
          patientId,
          patientName,
          latitude: data.latitude != null ? String(data.latitude) : "",
          longitude: data.longitude != null ? String(data.longitude) : "",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "emergency_alert",
            priority: "max",
            sound: "default",
            defaultVibrateTimings: false,
            vibrateTimingsMillis: ["0", "500", "100", "500", "100", "500"],
            title: notifTitle,
            body: notifBody,
          },
        },
        apns: {
          headers: { "apns-priority": "10", "apns-push-type": "alert" },
          payload: {
            aps: {
              alert: { title: notifTitle, body: notifBody },
              sound: "default",
              badge: 1,
              "content-available": 1,
              "interruption-level": "critical",
            },
          },
        },
      };

      try {
        const res = await getMessaging().sendEachForMulticast(message);
        console.log(`Emergency FCM batch ${Math.floor(i / 500) + 1}: ${res.successCount}/${chunk.length} sent.`);
      } catch (err) {
        console.error(`Emergency FCM batch ${Math.floor(i / 500) + 1} failed:`, err);
      }
    }

    // Write in-app notifications for each doctor + admin alert in batches.
    // Firestore batch limit is 500 writes.
    const BATCH_LIMIT = 490;
    let batch = db.batch();
    let opCount = 0;

    const flushBatch = async () => {
      if (opCount > 0) {
        await batch.commit();
        batch = db.batch();
        opCount = 0;
      }
    };

    for (const doctorId of doctorIds) {
      if (opCount >= BATCH_LIMIT) await flushBatch();
      const notifRef = db
        .collection("doctor_notifications")
        .doc(doctorId)
        .collection("items")
        .doc();
      batch.set(notifRef, {
        type: "emergency_request",
        title: notifTitle,
        body: notifBody,
        requestId,
        patientId,
        patientName,
        createdAt: FieldValue.serverTimestamp(),
        isRead: false,
        payload: {
          latitude: data.latitude || null,
          longitude: data.longitude || null,
        },
        expiresAt: Timestamp.fromDate(new Date(Date.now() + 90 * 24 * 60 * 60 * 1000)),
      });
      opCount++;
    }

    // Admin alert.
    if (opCount >= BATCH_LIMIT) await flushBatch();
    const alertRef = db.collection("admin_alerts").doc();
    batch.set(alertRef, {
      type: "emergency_doctor",
      severity: "critical",
      patientId,
      patientName,
      requestId,
      latitude: data.latitude || null,
      longitude: data.longitude || null,
      createdAt: FieldValue.serverTimestamp(),
      isRead: false,
    });

    await batch.commit();

    // See onSeriousComplaint's identical call above — this admin_alerts
    // producer also built its own doc directly and never pushed.
    await _pushToAllAdmins(db, getMessaging(), {
      title: "🚨 Emergency Doctor Request",
      body: `${patientName || "A patient"} needs an emergency doctor now.`,
      type: "emergency_doctor",
    });

    // Mark the request as notified.
    await snap.ref.update({
      status: "notified",
      patientName,
      doctorsNotified: doctorIds.length,
      notifiedAt: FieldValue.serverTimestamp(),
    });

    console.log(`Emergency ${requestId}: notified ${doctorIds.length} doctors + admin.`);
  }
);

// ── Stale Pending Consultation Auto-Expiry ────────────────────────────────────
//
// Runs every 2 minutes. Finds any consultation still in 'pending' status
// for more than 90 seconds and marks it 'missed'. This prevents ghost pending
// docs from accumulating in Firestore and triggering false call screens when
// the doctor app re-opens.
exports.expireStaleConsultations = onSchedule(
  { schedule: "every 2 minutes", timeZone: "UTC" },
  async () => {
    const db = getFirestore();
    const cutoff = Timestamp.fromDate(
      new Date(Date.now() - 90 * 1000) // 90 seconds ago
    );

    const staleSnap = await db
      .collection("consultations")
      .where("status", "==", "pending")
      .where("createdAt", "<=", cutoff)
      .limit(300) // bounded per run (and under the 500-write batch ceiling);
      .get();     // this runs every 2 minutes, so any remainder drains fast.

    if (staleSnap.empty) return;

    // Precondition-guarded per doc: a doctor accepting a consultation in the
    // seconds between this query and the write must not be clobbered back to
    // 'missed'. See _expireStaleDocs.
    const { updated, skipped } = await _expireStaleDocs(staleSnap.docs, {
      status: "missed",
      missedAt: FieldValue.serverTimestamp(),
      expiredBy: "auto_cleanup",
    });
    console.log(`Auto-expired ${updated} stale pending consultation(s); ${skipped} skipped (concurrently modified).`);
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// REAL-TIME NOTIFICATION ENGINE — All Service Modules
// ═══════════════════════════════════════════════════════════════════════════════
//
// Architecture:
//  • Every status change in any booking collection triggers a Cloud Function.
//  • The function calls _sendPatientNotification() which:
//      1. Deduplicates (no duplicate for same booking+status within 30s)
//      2. Writes to patient_notifications/{uid}/items (in-app notification center)
//      3. Sends FCM push to patient's device(s)
//  • deliverAt is set to 1 minute in the past so the Firestore stream
//    filter (deliverAt ≤ now) passes immediately regardless of clock skew.
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Internal helper — writes in-app notification + sends FCM to patient.
 * Never throws; all errors are caught and logged.
 */
async function _sendPatientNotification(db, messaging, patientId, opts) {
  const {
    title,
    body,
    type,
    serviceType = "general",
    bookingId = "",
    doctorId = "",
    actionType = "open_notifications",
    extraData = {},
  } = opts;

  if (!patientId || !title || !body || !type) {
    console.warn("_sendPatientNotification: missing required fields", opts);
    return;
  }

  // ── Deduplication ────────────────────────────────────────────────────────────
  // Prevents the same (type + bookingId) from being written twice within 30 s.
  if (bookingId) {
    const dedupKey = `${type}_${bookingId}`;
    const cutoff = Timestamp.fromDate(new Date(Date.now() - 30_000));
    try {
      const dup = await db
        .collection("patient_notifications")
        .doc(patientId)
        .collection("items")
        .where("dedupKey", "==", dedupKey)
        .where("createdAt", ">=", cutoff)
        .limit(1)
        .get();
      if (!dup.empty) {
        console.log(`Dedup skip: ${dedupKey} for patient ${patientId}`);
        return;
      }
    } catch (_) {}
  }

  // ── Write in-app notification ─────────────────────────────────────────────
  // deliverAt is set 90 seconds in the PAST so the Flutter query
  // (deliverAt ≤ Timestamp.now()) always resolves immediately.
  const deliverAt = Timestamp.fromDate(new Date(Date.now() - 90_000));

  const notifDoc = {
    type,
    title,
    body,
    serviceType,
    bookingId,
    doctorId,
    actionType,
    createdAt: FieldValue.serverTimestamp(),
    deliverAt,
    isRead: false,
    data: extraData,
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 90 * 24 * 60 * 60 * 1000)),
  };
  if (bookingId) notifDoc.dedupKey = `${type}_${bookingId}`;

  try {
    await db
      .collection("patient_notifications")
      .doc(patientId)
      .collection("items")
      .add(notifDoc);
  } catch (err) {
    console.error(`Failed to write in-app notification for ${patientId}:`, err);
    return;
  }

  // ── FCM push ─────────────────────────────────────────────────────────────────
  let fcmToken = null;
  try {
    const userDoc = await db.collection("users").doc(patientId).get();
    if (userDoc.exists) fcmToken = userDoc.data()?.fcmToken || null;
  } catch (_) {}

  if (!fcmToken) {
    console.log(`No FCM token for patient ${patientId} — in-app only.`);
    return;
  }

  // Build string-safe data payload (FCM data values must be strings).
  const fcmData = {
    type,
    serviceType,
    bookingId,
    doctorId,
    actionType,
  };
  for (const [k, v] of Object.entries(extraData)) {
    if (v != null) fcmData[k] = String(v);
  }

  const fcmMsg = {
    token: fcmToken,
    data: fcmData,
    android: {
      priority: "high",
      notification: {
        channelId: "mednu_default_channel",
        title,
        body,
        sound: "default",
        defaultVibrateTimings: true,
      },
    },
    apns: {
      headers: { "apns-priority": "5" },
      payload: {
        aps: {
          alert: { title, body },
          sound: "default",
          badge: 1,
        },
      },
    },
  };

  try {
    await messaging.send(fcmMsg);
    console.log(`FCM sent → patient ${patientId} [${type}]: "${title}"`);
  } catch (err) {
    console.error(`FCM failed for patient ${patientId} [${type}]:`, err.message);
  }
}

// ── Appointment Status Change ────────────────────────────────────────────────
//
// Fires on every status transition in the appointments collection. Booking
// is instant by design — there is no doctor accept/reject step, so only
// booked (incl. reschedule), completed and cancelled are ever actually
// written by either app. Handles exactly those three; anything else falls
// through to `default: return`.
exports.onAppointmentStatusChange = onDocumentUpdated(
  "appointments/{appointmentId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    // A doctor-initiated reschedule (dashboard_screen.dart in mednu_doctor)
    // deliberately keeps status == 'booked' rather than writing a separate
    // 'rescheduled' status value: the patient app's upcoming-appointments
    // query filters strictly on status == 'booked' (appointment_screen.dart),
    // so a literal 'rescheduled' status would silently drop the appointment
    // out of the patient's list entirely. That means this can't rely on the
    // status-changed check alone to notice a reschedule — it has to also
    // watch date/time.
    const statusChanged = before.status !== after.status;
    const rescheduled = before.status === "booked" && after.status === "booked" &&
      (before.date !== after.date || before.time !== after.time);
    if (!statusChanged && !rescheduled) return;

    const patientId = after.patientId;
    if (!patientId) return;

    const db        = getFirestore();
    const messaging = getMessaging();
    const apptId    = event.params.appointmentId;
    const doctorName = after.doctorName || "your doctor";
    const doctorId   = after.doctorId   || "";

    // Appointment is no longer going to happen (or already happened) —
    // delete the doctor's queued scheduled_reminders docs so a stale
    // "starting now" / T-N-min push can't fire after the fact. This is the
    // only cleanup path for a patient-initiated cancel/reject: the doctor
    // app only cancels its own queued reminders on a doctor-initiated
    // cancel/complete action, so without this a patient cancelling never
    // reaches the doctor's queued reminders.
    if (doctorId && ["cancelled", "completed"].includes(after.status)) {
      try {
        const batch = db.batch();
        batch.delete(db.collection("scheduled_reminders").doc(`${doctorId}_appt_${apptId}_reminder`));
        batch.delete(db.collection("scheduled_reminders").doc(`${doctorId}_appt_${apptId}_start`));
        await batch.commit();
      } catch (_) {}
    }

    // Format appointment date/time if available.
    let formattedDt = "";
    const raw = after.appointmentDate || after.scheduledAt || after.date || null;
    if (raw) {
      try {
        const d = raw.toDate ? raw.toDate() : new Date(raw);
        formattedDt = d.toLocaleString("en-IN", {
          day: "numeric", month: "short",
          hour: "2-digit", minute: "2-digit",
        });
      } catch (_) {}
    }

    let title = "";
    let body  = "";
    let type  = "";
    let actionType = "open_appointment";

    switch (after.status) {
      case "booked":
        if (rescheduled) {
          title = "Appointment Rescheduled";
          body  = formattedDt
            ? `Your appointment with Dr. ${doctorName} has been rescheduled to ${formattedDt}.`
            : `Your appointment with Dr. ${doctorName} has been rescheduled.`;
          type  = "appointment_rescheduled";
        } else {
          title = "Appointment Booked";
          body  = formattedDt
            ? `Your appointment with Dr. ${doctorName} has been booked for ${formattedDt}.`
            : `Your appointment with Dr. ${doctorName} has been successfully booked.`;
          type  = "appointment_booked";
        }
        break;
      case "completed":
        title = "Consultation Completed";
        body  = `Your consultation with Dr. ${doctorName} is complete.`;
        type  = "appointment_completed";
        break;
      case "cancelled":
        title = "Appointment Cancelled";
        body  = `Your appointment with Dr. ${doctorName} has been cancelled.`;
        type  = "appointment_cancelled";
        break;
      default:
        return;
    }

    await _sendPatientNotification(db, messaging, patientId, {
      title, body, type,
      serviceType: "appointment",
      bookingId: apptId,
      doctorId,
      actionType,
      extraData: { doctorName, appointmentDate: formattedDt },
    });
  }
);

// ── Service Request Status Change ────────────────────────────────────────────
//
// Handles all non-emergency service requests:
// ambulance, lab, diagnostics, home_care, caregiver, physiotherapy,
// hospital, quick_connect, nutrition, counselling, equipment, pharmacy.
exports.onServiceRequestStatusChange = onDocumentUpdated(
  "service_requests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status) return;

    // Emergency doctor is handled by onEmergencyDoctorRequest — skip here.
    if ((after.type || after.serviceType) === "emergency_doctor") return;
    // Internal-only status values — no user-facing notification needed.
    if (["duplicate", "notified", "pending"].includes(after.status)) return;

    const patientId = after.patientId || after.userId;
    if (!patientId) return;

    const db        = getFirestore();
    const messaging = getMessaging();
    const requestId = event.params.requestId;
    const svcType   = (after.type || after.serviceType || "general").toLowerCase();
    const newStatus = after.status;

    // Per-service, per-status notification content.
    // Key structure: statusMap[serviceType][status] = [title, body, notifType]
    const statusMap = {
      ambulance: {
        accepted:    ["Ambulance Booked", "An ambulance has been dispatched and is on the way.", "ambulance_accepted"],
        assigned:    ["Ambulance Assigned", "Your ambulance has been assigned and is heading to you.", "ambulance_assigned"],
        in_progress: ["Ambulance En Route", "Your ambulance is en route to your location.", "ambulance_en_route"],
        arrived:     ["Ambulance Arrived", "The ambulance has arrived at your location.", "ambulance_reached"],
        completed:   ["Ambulance Service Complete", "Your ambulance service has been completed.", "ambulance_completed"],
        rejected:    ["Ambulance Unavailable", "We could not fulfil your ambulance request right now. Please try again.", "ambulance_rejected"],
        cancelled:   ["Ambulance Booking Cancelled", "Your ambulance booking has been cancelled.", "ambulance_cancelled"],
      },
      lab_tests: {
        accepted:         ["Lab Booking Confirmed", "Your lab booking has been accepted. Our technician will visit you soon.", "lab_accepted"],
        assigned:         ["Technician Assigned", "A lab technician has been assigned to your booking.", "lab_assigned"],
        in_progress:      ["Technician on the Way", "Your lab technician is on the way to collect your sample.", "lab_in_progress"],
        sample_collected: ["Sample Collected", "Your sample has been collected and sent to the lab.", "lab_sample_collected"],
        report_ready:     ["Report Ready", "Your lab test report is now available. Tap to view.", "lab_report_ready"],
        completed:        ["Lab Test Completed", "Your lab test has been completed.", "lab_completed"],
        rejected:         ["Lab Booking Rejected", "Your lab booking could not be accepted. Please try again.", "lab_rejected"],
        cancelled:        ["Lab Booking Cancelled", "Your lab booking has been cancelled.", "lab_cancelled"],
      },
      diagnostics: {
        accepted:     ["Diagnostics Confirmed", "Your diagnostic booking has been accepted.", "lab_accepted"],
        assigned:     ["Technician Assigned", "A diagnostic technician has been assigned.", "lab_assigned"],
        in_progress:  ["Diagnostics In Progress", "Your diagnostic test is in progress.", "lab_in_progress"],
        // _LAB_TO_SERVICE_REQUEST_STATUS mirrors 'sample_collected' for BOTH
        // diagnostic types; without this key the type='diagnostics' variant
        // fell through to genericMap, which has no such status, and the
        // patient notification was silently dropped.
        sample_collected: ["Sample Collected", "Your sample has been collected and sent to the lab.", "lab_sample_collected"],
        report_ready: ["Report Ready", "Your diagnostic report is now available.", "lab_report_ready"],
        completed:    ["Diagnostics Completed", "Your diagnostic test has been completed.", "lab_completed"],
        rejected:     ["Diagnostics Rejected", "Your diagnostic booking was not accepted. Please try again.", "lab_rejected"],
        cancelled:    ["Diagnostics Cancelled", "Your diagnostics booking has been cancelled.", "lab_cancelled"],
      },
      home_care: {
        accepted:    ["Home Care Confirmed", "Your home care request has been accepted.", "homecare_accepted"],
        assigned:    ["Caregiver Assigned", "A caregiver has been assigned to you.", "caregiver_assigned"],
        in_progress: ["Home Care Started", "Your home care session has started.", "homecare_started"],
        completed:   ["Home Care Completed", "Your home care session has been completed.", "homecare_completed"],
        rejected:    ["Home Care Rejected", "Your home care request could not be accepted.", "homecare_rejected"],
        cancelled:   ["Home Care Cancelled", "Your home care booking has been cancelled.", "homecare_cancelled"],
      },
      caregiver: {
        accepted:    ["Caregiver Booking Accepted", "Your caregiver request has been accepted.", "caregiver_accepted"],
        assigned:    ["Caregiver Assigned", "A caregiver has been assigned to you.", "caregiver_assigned"],
        in_progress: ["Caregiver Service Started", "Your caregiver has arrived and the service has started.", "caregiver_started"],
        completed:   ["Caregiver Service Completed", "Your caregiver service has been completed.", "caregiver_completed"],
        rejected:    ["Caregiver Booking Rejected", "Your caregiver booking could not be accepted.", "caregiver_rejected"],
        cancelled:   ["Caregiver Booking Cancelled", "Your caregiver booking has been cancelled.", "caregiver_cancelled"],
      },
      // The patient app never writes the literal type 'caregiver' (singular)
      // — the cart checkout path writes 'care_assistant' or 'caregivers'
      // (see mednu/lib/features/cart/screens/cart_screen.dart). These two
      // keys reuse the `caregiver` copy verbatim so real bookings get
      // tailored notification text instead of the generic fallback.
      care_assistant: {
        accepted:    ["Caregiver Booking Accepted", "Your caregiver request has been accepted.", "caregiver_accepted"],
        assigned:    ["Caregiver Assigned", "A caregiver has been assigned to you.", "caregiver_assigned"],
        in_progress: ["Caregiver Service Started", "Your caregiver has arrived and the service has started.", "caregiver_started"],
        completed:   ["Caregiver Service Completed", "Your caregiver service has been completed.", "caregiver_completed"],
        rejected:    ["Caregiver Booking Rejected", "Your caregiver booking could not be accepted.", "caregiver_rejected"],
        cancelled:   ["Caregiver Booking Cancelled", "Your caregiver booking has been cancelled.", "caregiver_cancelled"],
      },
      caregivers: {
        accepted:    ["Caregiver Booking Accepted", "Your caregiver request has been accepted.", "caregiver_accepted"],
        assigned:    ["Caregiver Assigned", "A caregiver has been assigned to you.", "caregiver_assigned"],
        in_progress: ["Caregiver Service Started", "Your caregiver has arrived and the service has started.", "caregiver_started"],
        completed:   ["Caregiver Service Completed", "Your caregiver service has been completed.", "caregiver_completed"],
        rejected:    ["Caregiver Booking Rejected", "Your caregiver booking could not be accepted.", "caregiver_rejected"],
        cancelled:   ["Caregiver Booking Cancelled", "Your caregiver booking has been cancelled.", "caregiver_cancelled"],
      },
      physiotherapy: {
        accepted:    ["Physiotherapy Confirmed", "Your physiotherapy session has been confirmed.", "physio_accepted"],
        assigned:    ["Physiotherapist Assigned", "A physiotherapist has been assigned to your session.", "physio_assigned"],
        in_progress: ["Physiotherapy Session Started", "Your physiotherapy session has started.", "physio_started"],
        completed:   ["Physiotherapy Completed", "Your physiotherapy session has been completed.", "physio_completed"],
        rejected:    ["Physiotherapy Rejected", "Your physiotherapy booking could not be accepted.", "physio_rejected"],
        cancelled:   ["Physiotherapy Cancelled", "Your physiotherapy booking has been cancelled.", "physio_cancelled"],
      },
      hospital: {
        accepted:    ["Hospital Booking Confirmed", "Your hospital booking has been confirmed.", "hospital_accepted"],
        assigned:    ["Bed Assigned", "A bed has been assigned to you at the hospital.", "hospital_assigned"],
        in_progress: ["Admitted", "You have been admitted to the hospital.", "hospital_admitted"],
        completed:   ["Discharged", "You have been discharged from the hospital. Wishing you a speedy recovery.", "hospital_discharged"],
        rejected:    ["Hospital Booking Rejected", "Your hospital booking could not be confirmed. Please contact support.", "hospital_rejected"],
        cancelled:   ["Hospital Booking Cancelled", "Your hospital booking has been cancelled.", "hospital_cancelled"],
      },
      quick_connect: {
        accepted:    ["Doctor Accepted", "A doctor has accepted your quick connect request.", "quickconnect_accepted"],
        in_progress: ["Doctor is Connecting", "The doctor is joining your quick connect session.", "quickconnect_started"],
        completed:   ["Quick Connect Completed", "Your quick connect session has been completed.", "quickconnect_completed"],
        rejected:    ["Quick Connect Declined", "No doctor is available right now. Please try again shortly.", "quickconnect_rejected"],
        cancelled:   ["Quick Connect Cancelled", "Your quick connect request has been cancelled.", "quickconnect_cancelled"],
      },
      nutrition: {
        accepted:    ["Nutrition Consultation Confirmed", "Your nutrition consultation has been confirmed.", "nutrition_accepted"],
        in_progress: ["Nutrition Session Started", "Your nutrition consultation session has started.", "nutrition_started"],
        completed:   ["Nutrition Consultation Completed", "Your nutrition consultation has been completed.", "nutrition_completed"],
        rejected:    ["Nutrition Consultation Rejected", "Your nutrition consultation could not be accepted.", "nutrition_rejected"],
        cancelled:   ["Nutrition Consultation Cancelled", "Your nutrition consultation has been cancelled.", "nutrition_cancelled"],
      },
      counselling: {
        accepted:    ["Counselling Session Confirmed", "Your counselling session has been confirmed.", "counselling_accepted"],
        in_progress: ["Counselling Session Started", "Your counselling session has started.", "counselling_started"],
        completed:   ["Counselling Session Completed", "Your counselling session has been completed.", "counselling_completed"],
        cancelled:   ["Counselling Cancelled", "Your counselling session has been cancelled.", "counselling_cancelled"],
      },
      pregnancy_checkup: {
        accepted:  ["Checkup Confirmed", "Your pregnancy checkup has been confirmed.", "pregnancy_checkup_confirmed"],
        assigned:  ["Doctor Assigned", "A doctor has been assigned for your pregnancy checkup.", "pregnancy_checkup_assigned"],
        completed: ["Checkup Completed", "Your pregnancy checkup has been completed. Stay healthy!", "pregnancy_checkup_completed"],
        cancelled: ["Checkup Cancelled", "Your pregnancy checkup has been cancelled. Please reschedule.", "pregnancy_checkup_cancelled"],
      },
    };

    // Fallback: generic messages for unknown service types.
    const genericMap = {
      accepted:    ["Booking Confirmed", `Your ${svcType} booking has been confirmed.`, "booking_accepted"],
      assigned:    ["Staff Assigned", `A staff member has been assigned to your ${svcType} booking.`, "booking_assigned"],
      in_progress: ["Service Started", `Your ${svcType} service has started.`, "booking_started"],
      completed:   ["Service Completed", `Your ${svcType} service has been completed.`, "booking_completed"],
      rejected:    ["Booking Rejected", `Your ${svcType} booking was not accepted.`, "booking_rejected"],
      cancelled:   ["Booking Cancelled", `Your ${svcType} booking has been cancelled.`, "booking_cancelled"],
    };

    const typeMap = statusMap[svcType] || genericMap;
    const entry   = typeMap[newStatus] || genericMap[newStatus];
    if (!entry) return;

    const [title, body, notifType] = entry;

    // Personalise with assignee name when available.
    let finalBody = body;
    const assigneeName = after.assigneeName || after.caregiverName
      || after.technicianName || after.driverName || "";
    if (assigneeName) {
      finalBody = finalBody
        .replace("A caregiver", assigneeName)
        .replace("A lab technician", assigneeName)
        .replace("A staff member", assigneeName);
    }

    await _sendPatientNotification(db, messaging, patientId, {
      title,
      body: finalBody,
      type: notifType,
      serviceType: svcType,
      bookingId: requestId,
      actionType: "open_service",
      extraData: { svcType, assigneeName, status: newStatus },
    });
  }
);

// ── Medicine Order Status Change ──────────────────────────────────────────────
//
// Fires for every status transition in medicine_orders/{orderId}.
// Tracks the full delivery pipeline from accepted → delivered.
exports.onMedicineOrderStatusChange = onDocumentUpdated(
  "medicine_orders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status) return;

    const patientId = after.patientId || after.userId;
    if (!patientId) return;

    const db        = getFirestore();
    const messaging = getMessaging();
    const orderId   = event.params.orderId;

    const statusMap = {
      accepted:         ["Order Accepted", "Your medicine order has been accepted and is being prepared.", "medicine_accepted"],
      processing:       ["Order Processing", "Your medicine order is being processed.", "medicine_processing"],
      verified:         ["Order Verified", "Your medicine order has been verified by our pharmacist.", "medicine_verified"],
      packed:           ["Medicines Packed", "Your medicines are packed and ready for dispatch.", "medicine_packed"],
      dispatched:       ["Out for Delivery", "Your medicines are out for delivery and will arrive soon.", "medicine_out_for_delivery"],
      out_for_delivery: ["Out for Delivery", "Your medicines are on the way! Track your delivery.", "medicine_out_for_delivery"],
      delivered:        ["Order Delivered", "Your medicines have been delivered successfully.", "medicine_delivered"],
      rejected:         ["Order Rejected", "Your medicine order could not be processed. Please try again.", "medicine_rejected"],
      cancelled:        ["Order Cancelled", "Your medicine order has been cancelled.", "medicine_cancelled"],
      returned:         ["Order Returned", "Your medicine order has been returned.", "medicine_returned"],
    };

    const entry = statusMap[after.status];
    if (!entry) return;

    const [title, body, notifType] = entry;

    await _sendPatientNotification(db, messaging, patientId, {
      title, body, type: notifType,
      serviceType: "medicine",
      bookingId: orderId,
      actionType: "open_order",
      extraData: { orderId, status: after.status },
    });
  }
);

// ── Lab Booking Status Change ─────────────────────────────────────────────────
//
// Fires for every status transition in lab_bookings/{bookingId}.
// Covers: sample collection → lab processing → report ready.
exports.onLabBookingStatusChange = onDocumentUpdated(
  "lab_bookings/{bookingId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status) return;

    const patientId = after.patientId || after.userId;
    if (!patientId) return;

    const db        = getFirestore();
    const messaging = getMessaging();
    const bookingId = event.params.bookingId;
    const testName  = after.testName || after.serviceName || "your test";

    const statusMap = {
      accepted:         ["Lab Booking Accepted", `Your booking for ${testName} has been accepted.`, "lab_accepted"],
      assigned:         ["Technician Assigned", `A lab technician has been assigned for ${testName}.`, "lab_assigned"],
      in_progress:      ["Technician on the Way", `Our technician is on the way to collect your ${testName} sample.`, "lab_in_progress"],
      sample_collected: ["Sample Collected", `Your ${testName} sample has been collected and sent to the lab.`, "lab_sample_collected"],
      processing:       ["Sample Processing", `Your ${testName} sample is being analysed in the lab.`, "lab_processing"],
      report_ready:     ["Report Ready", `Your ${testName} report is ready. Tap to view your results.`, "lab_report_ready"],
      completed:        ["Lab Test Completed", `Your ${testName} has been completed.`, "lab_completed"],
      rejected:         ["Lab Booking Rejected", `Your booking for ${testName} could not be accepted. Please try again.`, "lab_rejected"],
      cancelled:        ["Lab Booking Cancelled", `Your booking for ${testName} has been cancelled.`, "lab_cancelled"],
    };

    const entry = statusMap[after.status];
    if (!entry) return;

    const [title, body, notifType] = entry;

    await _sendPatientNotification(db, messaging, patientId, {
      title, body, type: notifType,
      serviceType: "diagnostics",
      bookingId,
      actionType: "open_diagnostics",
      extraData: { testName, status: after.status },
    });
  }
);

// ── Pregnancy Checkup Status Change ──────────────────────────────────────────
//
// Fires for status transitions in pregnancy_checkups/{checkupId}.
// Covers: booked, reminder, confirmed, completed, cancelled.
exports.onPregnancyCheckupStatusChange = onDocumentUpdated(
  "pregnancy_checkups/{checkupId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status) return;

    const patientId = after.patientId || after.userId;
    if (!patientId) return;

    const db        = getFirestore();
    const messaging = getMessaging();
    const checkupId = event.params.checkupId;

    // Format checkup date if available. `scheduledDate` is the field the
    // Flutter model (mednu/lib/features/pregnancy/models/pregnancy_models.dart)
    // actually writes — `checkupDate`/`scheduledAt`/`date` never existed on
    // this doc, which silently left every notification below dateless.
    let formattedDate = "";
    const rawDate = after.scheduledDate || null;
    if (rawDate) {
      try {
        const d = rawDate.toDate ? rawDate.toDate() : new Date(rawDate);
        formattedDate = d.toLocaleDateString("en-IN", { day: "numeric", month: "long" });
      } catch (_) {}
    }

    const statusMap = {
      booked:     ["Checkup Scheduled", formattedDate ? `Your pregnancy checkup is scheduled for ${formattedDate}.` : "Your pregnancy checkup has been scheduled.", "pregnancy_checkup_booked"],
      reminder:   ["Checkup Reminder", formattedDate ? `Reminder: You have a pregnancy checkup on ${formattedDate}. Please be prepared.` : "You have a pregnancy checkup coming up. Please be prepared.", "pregnancy_checkup_reminder"],
      confirmed:  ["Checkup Confirmed", formattedDate ? `Your pregnancy checkup on ${formattedDate} has been confirmed.` : "Your pregnancy checkup has been confirmed.", "pregnancy_checkup_confirmed"],
      completed:  ["Checkup Completed", "Your pregnancy checkup has been completed. Stay healthy!", "pregnancy_checkup_completed"],
      cancelled:  ["Checkup Cancelled", "Your pregnancy checkup has been cancelled. Please reschedule.", "pregnancy_checkup_cancelled"],
      // The real status vocabulary (mednu's PregnancyCheckup model) is
      // upcoming/completed/missed/cancelled — `booked`/`reminder`/`confirmed`
      // above are legacy keys nothing ever writes; `missed` was the one
      // status with a live writer (`markCheckupMissed` in
      // pregnancy_provider.dart) that had no entry here at all, so a missed
      // checkup silently sent no notification.
      missed:     ["Checkup Missed", "You missed your pregnancy checkup. Please reschedule as soon as possible.", "pregnancy_checkup_missed"],
    };

    const entry = statusMap[after.status];
    if (!entry) return;

    const [title, body, notifType] = entry;

    await _sendPatientNotification(db, messaging, patientId, {
      title, body, type: notifType,
      serviceType: "pregnancy",
      bookingId: checkupId,
      actionType: "open_pregnancy",
      extraData: { checkupDate: formattedDate, status: after.status },
    });
  }
);

// ── Admin Broadcast Push ─────────────────────────────────────────────────────
//
// Fires when the admin writes a document to the `broadcasts` collection.
// Reads FCM tokens for the target audience and sends a push so that users
// receive a notification even when the app is closed/terminated.
// The in-app notification is written by the admin panel separately; this
// function only handles the FCM push delivery.
exports.onBroadcastCreated = onDocumentCreated(
  "broadcasts/{broadcastId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const { target, title, body, type = "general", link, targetUserId } = data;

    if (!title || !body) {
      console.warn(`Broadcast ${event.params.broadcastId}: missing title or body — skipping.`);
      return;
    }

    const db        = getFirestore();
    const messaging = getMessaging();
    const tokens    = [];
    // mednu-admin's sendBroadcast() already writes the in-app
    // patient_notifications/doctor_notifications record for every target,
    // including 'all_doctors' (see app.js) — this function only ever
    // handled the FCM push, and only ever collected patient tokens, so an
    // 'all_doctors' (or the doctor half of 'all_users') broadcast got its
    // bell entry but no push, i.e. never reached a doctor whose app was
    // closed. doctorTokens closes that gap.
    const doctorTokens = [];

    // ── Collect FCM tokens ───────────────────────────────────────────────────
    if (target === "all_patients" || target === "all_users") {
      // Paginate in pages of 500 to stay within Firestore read limits.
      let lastDoc = null;
      do {
        let q = db.collection("users").select("fcmToken").limit(500);
        if (lastDoc) q = q.startAfter(lastDoc);
        const page = await q.get();
        page.forEach((doc) => {
          const t = doc.data().fcmToken;
          if (t) tokens.push(t);
        });
        lastDoc = page.size === 500 ? page.docs[page.size - 1] : null;
      } while (lastDoc);
    }

    if (target === "all_doctors" || target === "all_users") {
      // Mirrors mednu-admin's own doctor fan-out: active doctors only.
      let lastDoc = null;
      do {
        let q = db.collection("doctors").where("status", "==", "active")
          .select("fcmToken").limit(500);
        if (lastDoc) q = q.startAfter(lastDoc);
        const page = await q.get();
        page.forEach((doc) => {
          const t = doc.data().fcmToken;
          if (t) doctorTokens.push(t);
        });
        lastDoc = page.size === 500 ? page.docs[page.size - 1] : null;
      } while (lastDoc);
    }

    if (target === "specific_user" && targetUserId) {
      const userDoc = await db.collection("users").doc(targetUserId).get();
      if (userDoc.exists) {
        const t = userDoc.data().fcmToken;
        if (t) tokens.push(t);
      }
    }

    if (!tokens.length && !doctorTokens.length) {
      console.log(`Broadcast ${event.params.broadcastId}: no FCM tokens — in-app only.`);
      return;
    }

    // ── Build FCM message ────────────────────────────────────────────────────
    const fcmData = { type: String(type || "general"), actionType: "open_notifications" };
    if (link) fcmData.link = String(link);

    let successCount = 0;
    let failCount    = 0;

    // channelId differs per app: mednu registers 'mednu_default_channel' as
    // its default notification channel; mednu_doctor never registered that
    // one — 'incoming_call' is the only channel that actually exists on a
    // doctor's device (see _notifyPartnerApproved above for the same
    // reasoning), so a doctor-bound push must use it instead.
    async function _sendChunked(tokenList, channelId) {
      for (let i = 0; i < tokenList.length; i += 500) {
        const chunk = tokenList.slice(i, i + 500);
        const msg = {
          tokens: chunk,
          data:   fcmData,
          android: {
            priority: "high",
            notification: {
              channelId,
              title,
              body,
              sound:                 "default",
              defaultVibrateTimings: true,
            },
          },
          apns: {
            headers: { "apns-priority": "5" },
            payload: {
              aps: {
                alert: { title, body },
                sound: "default",
                badge: 1,
              },
            },
          },
        };

        try {
          const res = await messaging.sendEachForMulticast(msg);
          successCount += res.successCount;
          failCount    += res.failureCount;
        } catch (err) {
          console.error(`Broadcast chunk ${Math.floor(i / 500) + 1} (${channelId}) FCM error:`, err);
        }
      }
    }

    await _sendChunked(tokens, "mednu_default_channel");
    await _sendChunked(doctorTokens, "incoming_call");

    // ── Mark broadcast as pushed ─────────────────────────────────────────────
    const totalTokens = tokens.length + doctorTokens.length;
    try {
      await snap.ref.update({
        fcmSentAt:       FieldValue.serverTimestamp(),
        fcmTokenCount:   totalTokens,
        fcmSuccessCount: successCount,
        fcmFailCount:    failCount,
      });
    } catch (_) {}

    console.log(
      `Broadcast ${event.params.broadcastId}: FCM ${successCount}/${totalTokens} sent, ${failCount} failed.`
    );
  }
);

// ═══════════════════════════════════════════════════════════════════════════
//  WALLET — server-authoritative balances
// ═══════════════════════════════════════════════════════════════════════════
//
// `users/{uid}.walletBalance`, `.mednuMoneyBalance` and `.referralPoints` are
// written ONLY from here (Admin SDK). firestore.rules blocks every client write
// to those fields. Every mutation writes, in ONE Firestore transaction:
//   1. the `users/{uid}` balance field,
//   2. an immutable `wallet_ledger/{entryId}` entry (new canonical audit trail),
//   3. the legacy `users/{uid}/transactions/{txId}` doc the app's existing
//      transactionsStream()/mednuMoneyTransactionsStream() already render.
// The dual-write keeps the shipped Flutter UI working with zero model changes.

function _logWallet(severity, event, data = {}) {
  const payload = { severity, module: "wallet", event, ...data };
  if (severity === "ERROR" || severity === "WARNING") {
    console.error(JSON.stringify(payload));
  } else {
    console.log(JSON.stringify(payload));
  }
}

const _WALLET_MAX_AMOUNT = 500000; // ₹5,00,000 — sanity ceiling on any single entry

// 'main' -> walletBalance, 'mednu_money' -> mednuMoneyBalance
function _walletField(walletType) {
  return walletType === "mednu_money" ? "mednuMoneyBalance" : "walletBalance";
}

// Reads a numeric balance field defensively (missing/legacy docs -> 0).
function _walletBalanceOf(snap, field) {
  if (!snap.exists) return 0;
  const raw = snap.get(field);
  return typeof raw === "number" && isFinite(raw) ? raw : 0;
}

// Deterministic `wallet_ledger` doc id derived from a stable `source` string.
// Firestore doc ids may not contain '/' and are capped at 1500 bytes.
function _ledgerId(source) {
  return String(source).replace(/[^A-Za-z0-9_:.\-]/g, "_").slice(0, 400);
}

// Validates and normalises a client-supplied rupee amount.
function _assertWalletAmount(amount) {
  if (typeof amount !== "number" || !isFinite(amount) || amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be a positive number.");
  }
  if (amount > _WALLET_MAX_AMOUNT) {
    throw new HttpsError("invalid-argument", "Amount exceeds the permitted limit.");
  }
  return Math.round(amount * 100) / 100;
}

// Shape of the legacy per-user transaction doc — must stay byte-compatible with
// WalletTransaction.fromDoc() in mednu/lib/features/wallet/wallet_service.dart.
function _legacyTxDoc({ title, amount, type, category, description, walletType }) {
  const doc = {
    title,
    amount,
    type,
    category,
    timestamp: FieldValue.serverTimestamp(),
    walletType: walletType || "main",
  };
  if (description) doc.description = description;
  return doc;
}

function _ledgerDoc({ uid, walletType, type, amount, category, title, description, source, balanceAfter }) {
  return {
    uid,
    walletType: walletType || "main",
    type,
    amount,
    category,
    title,
    description: description || null,
    source,
    balanceAfter,
    createdAt: FieldValue.serverTimestamp(),
  };
}

// ── Razorpay: Create Order ────────────────────────────────────────────────────
//
// Called from the Flutter app before opening the Razorpay checkout modal.
// Creates an order on Razorpay's servers and returns the order_id so the
// client can include it in the checkout options (required for Standard Checkout).
//
// The created order is ALSO persisted to `razorpay_orders/{order_id}` so that
// verifyRazorpayPayment can later determine the credited amount from a
// server-side record of what was actually ordered, rather than from anything
// the client sends at credit time. That persistence is what makes the wallet
// top-up amount server-authoritative.
//
// Request data: { amount: number (paise), currency?: string, receipt?: string,
//                 purpose?: string }
// Response:     { order_id: string, amount: number, currency: string }
exports.createRazorpayOrder = onCall({ enforceAppCheck: true }, async (request) => {
  const { amount, currency = "INR", receipt, purpose } = request.data || {};

  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to start a payment.");
  }

  if (!amount || typeof amount !== "number" || amount < 100) {
    throw new HttpsError("invalid-argument", "Amount must be a number ≥ 100 paise.");
  }

  const razorpay = new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID,
    key_secret: process.env.RAZORPAY_KEY_SECRET,
  });

  try {
    const order = await razorpay.orders.create({
      amount: Math.round(amount),
      currency,
      receipt: receipt || `rcpt_${Date.now()}`,
    });

    // Server-side record of what was ordered. verifyRazorpayPayment reads
    // `amountPaise` from here — never from its own request payload — so a
    // modified client cannot verify a small payment and credit a large amount.
    try {
      await getFirestore().collection("razorpay_orders").doc(order.id).set({
        uid,
        amountPaise: order.amount,
        currency: order.currency,
        purpose: typeof purpose === "string" && purpose ? purpose : "checkout",
        status: "created",
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (err) {
      _logWallet("ERROR", "razorpay_order_persist_failed", {
        uid, orderId: order.id, error: err.message,
      });
      throw new HttpsError("internal", "Failed to create Razorpay order.");
    }

    return {
      order_id: order.id,
      amount: order.amount,
      currency: order.currency,
    };
  } catch (err) {
    console.error("Razorpay createOrder error:", err);
    throw new HttpsError("internal", "Failed to create Razorpay order.");
  }
});

// ── Razorpay: Verify Payment Signature ───────────────────────────────────────
//
// Called from the Flutter app after Razorpay returns a successful payment.
// Verifies the HMAC-SHA256 signature using the KEY_SECRET so the server — not
// the client — confirms authenticity before marking the payment as successful.
//
// Request data: { razorpay_order_id, razorpay_payment_id, razorpay_signature }
// Response:     { verified: true }  — throws HttpsError on failure.
exports.verifyRazorpayPayment = onCall({ enforceAppCheck: true }, async (request) => {
  const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = request.data || {};

  if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
    throw new HttpsError("invalid-argument", "Missing payment verification fields.");
  }

  const body = `${razorpay_order_id}|${razorpay_payment_id}`;
  const expectedSignature = crypto
    .createHmac("sha256", process.env.RAZORPAY_KEY_SECRET)
    .update(body)
    .digest("hex");

  if (expectedSignature !== razorpay_signature) {
    console.warn(`Signature mismatch for order ${razorpay_order_id}`);
    throw new HttpsError("unauthenticated", "Payment signature verification failed.");
  }

  // Optionally record the verified payment in Firestore for audit trail.
  const db = getFirestore();
  try {
    await db.collection("razorpay_payments").add({
      orderId: razorpay_order_id,
      paymentId: razorpay_payment_id,
      verifiedAt: FieldValue.serverTimestamp(),
      patientId: request.auth?.uid || null,
    });
  } catch (err) {
    // Non-fatal — signature already verified; just log and continue.
    console.error("Failed to write payment audit record:", err);
  }

  // ── Server-authoritative wallet credit ─────────────────────────────────────
  // The credited amount comes from `razorpay_orders/{order_id}.amountPaise`,
  // written by createRazorpayOrder — never from this call's request payload.
  const uid = request.auth?.uid || null;
  const orderRef = db.collection("razorpay_orders").doc(razorpay_order_id);
  let orderSnap;
  try {
    orderSnap = await orderRef.get();
  } catch (err) {
    _logWallet("ERROR", "razorpay_order_read_failed", {
      uid, orderId: razorpay_order_id, error: err.message,
    });
    throw new HttpsError("internal", "Could not confirm the payment. Contact support.");
  }

  // Orders created before this function persisted them (older app builds) have
  // no record; the signature is still valid so the gateway leg succeeded, there
  // is simply nothing this server can authoritatively credit.
  if (!orderSnap.exists) {
    _logWallet("WARNING", "razorpay_order_not_found", { uid, orderId: razorpay_order_id });
    return { verified: true, credited: false };
  }

  const order = orderSnap.data() || {};
  if (order.purpose !== "wallet_topup") {
    // Checkout leg — nothing is credited to the wallet for these.
    return { verified: true, credited: false };
  }
  if (!uid || order.uid !== uid) {
    _logWallet("WARNING", "razorpay_order_uid_mismatch", {
      uid, orderUid: order.uid || null, orderId: razorpay_order_id,
    });
    throw new HttpsError("permission-denied", "This payment belongs to another account.");
  }
  if (order.status === "consumed") {
    // Legitimate retry after a flaky response — idempotent no-op, not an error.
    return { verified: true, credited: false, alreadyCredited: true };
  }

  const amount = Math.round(Number(order.amountPaise || 0)) / 100;
  if (!(amount > 0)) {
    _logWallet("ERROR", "razorpay_order_bad_amount", { uid, orderId: razorpay_order_id });
    throw new HttpsError("internal", "Order amount is invalid. Contact support.");
  }

  // `source` doubles as the wallet_ledger doc id, so one Razorpay payment can
  // only ever credit once even under at-least-once callable delivery.
  const source = `razorpay:${razorpay_payment_id}`;
  const ledgerRef = db.collection("wallet_ledger").doc(_ledgerId(source));
  const userRef = db.collection("users").doc(uid);

  try {
    const outcome = await db.runTransaction(async (t) => {
      const ledgerSnap = await t.get(ledgerRef);
      const freshOrder = await t.get(orderRef);
      const userSnap = await t.get(userRef);
      if (ledgerSnap.exists || freshOrder.get("status") === "consumed") {
        return { alreadyCredited: true, balanceAfter: null };
      }

      const balanceAfter = _walletBalanceOf(userSnap, "walletBalance") + amount;
      t.set(userRef, { walletBalance: balanceAfter }, { merge: true });
      t.set(
        userRef.collection("transactions").doc(),
        _legacyTxDoc({
          title: "Money Added",
          amount,
          type: "credit",
          category: "add_money",
          walletType: "main",
        })
      );
      t.set(
        ledgerRef,
        _ledgerDoc({
          uid,
          walletType: "main",
          type: "credit",
          amount,
          category: "add_money",
          title: "Money Added",
          source,
          balanceAfter,
        })
      );
      t.update(orderRef, {
        status: "consumed",
        paymentId: razorpay_payment_id,
        consumedAt: FieldValue.serverTimestamp(),
      });
      return { alreadyCredited: false, balanceAfter };
    });

    if (outcome.alreadyCredited) {
      return { verified: true, credited: false, alreadyCredited: true };
    }
    _logWallet("INFO", "wallet_topup_credited", {
      uid, orderId: razorpay_order_id, paymentId: razorpay_payment_id, amount,
      balanceAfter: outcome.balanceAfter,
    });
    return {
      verified: true,
      credited: true,
      amount,
      balanceAfter: outcome.balanceAfter,
    };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    _logWallet("ERROR", "wallet_topup_credit_failed", {
      uid, orderId: razorpay_order_id, paymentId: razorpay_payment_id, error: err.message,
    });
    throw new HttpsError("internal", "Payment verified but the wallet credit failed. Contact support.");
  }
});

// ── Wallet: Spend balance ─────────────────────────────────────────────────────
//
// Debits the caller's own wallet for an in-app purchase. Replaces the old
// client-side WalletService.deductPayment / deductMednuMoney transactions.
//
// Request data: { walletType: 'main'|'mednu_money', amount, title, category?,
//                 description? }
// Response:     { success: true, balanceAfter }
//
// KNOWN RESIDUAL LIMITATION: there is no independent server-side authority for
// what a checkout amount *should* be (the checkout flow itself is not yet
// server-authoritative), so this trusts the client's stated spend amount,
// subject to a sufficiency check. It closes the arbitrary-self-CREDIT exploit;
// a client under-reporting its own spend is a separate, narrower risk that
// needs the checkout flow to become server-authoritative.
exports.spendWalletBalance = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const {
    walletType = "main",
    amount: rawAmount,
    title,
    category = "payment",
    description,
    idempotencyKey,
  } = request.data || {};

  if (walletType !== "main" && walletType !== "mednu_money") {
    throw new HttpsError("invalid-argument", "Unknown wallet type.");
  }
  // Optional. When a caller supplies one, the debit is replay-safe: a client
  // retry after a timeout resolves to the same deterministic wallet_ledger doc
  // and becomes a no-op instead of a second debit. Callers that omit it keep
  // the previous at-least-once behaviour.
  if (idempotencyKey !== undefined &&
      (typeof idempotencyKey !== "string" || !idempotencyKey.trim() || idempotencyKey.length > 200)) {
    throw new HttpsError("invalid-argument", "idempotencyKey must be a short non-empty string.");
  }
  if (typeof title !== "string" || !title.trim()) {
    throw new HttpsError("invalid-argument", "A transaction title is required.");
  }
  const amount = _assertWalletAmount(rawAmount);

  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);
  const field = _walletField(walletType);
  const label = walletType === "mednu_money" ? "MedNU Money" : "wallet";

  // `source` doubles as the wallet_ledger doc id when the caller opted in, so a
  // retried checkout can only ever debit once.
  const source = idempotencyKey
    ? `spend:${uid}:${idempotencyKey.trim()}`
    : `spend:${uid}:${Date.now()}`;
  const ledgerRef = idempotencyKey
    ? db.collection("wallet_ledger").doc(_ledgerId(source))
    : db.collection("wallet_ledger").doc();

  try {
    const balanceAfter = await db.runTransaction(async (t) => {
      const userSnap = await t.get(userRef);
      if (idempotencyKey) {
        const existing = await t.get(ledgerRef);
        if (existing.exists) {
          // Legitimate retry after a flaky response — idempotent no-op.
          const seen = existing.get("balanceAfter");
          return typeof seen === "number" ? seen : _walletBalanceOf(userSnap, field);
        }
      }
      const current = _walletBalanceOf(userSnap, field);
      if (current < amount) {
        throw new HttpsError("failed-precondition", `Insufficient ${label} balance`);
      }
      const next = Math.round((current - amount) * 100) / 100;

      t.set(userRef, { [field]: next }, { merge: true });
      t.set(
        userRef.collection("transactions").doc(),
        _legacyTxDoc({
          title: title.trim(),
          amount,
          type: "debit",
          category,
          description,
          walletType,
        })
      );
      // Deterministic id when the caller supplied an idempotency key, random
      // otherwise; transaction atomicity is the guarantee in the latter case.
      t.set(
        ledgerRef,
        _ledgerDoc({
          uid,
          walletType,
          type: "debit",
          amount,
          category,
          title: title.trim(),
          description,
          source,
          balanceAfter: next,
        })
      );
      return next;
    });

    _logWallet("INFO", "wallet_spend", { uid, walletType, amount, balanceAfter });
    return { success: true, balanceAfter };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    _logWallet("ERROR", "wallet_spend_failed", { uid, walletType, amount, error: err.message });
    throw new HttpsError("internal", `Could not debit your ${label}. Please try again.`);
  }
});

// ── Wallet: Transfer to another MedNU user ────────────────────────────────────
//
// Request data: { recipientPhone: string, amount: number }
// Response:     { success: true, balanceAfter }
exports.transferWalletBalance = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const { recipientPhone, amount: rawAmount } = request.data || {};
  if (typeof recipientPhone !== "string" || !recipientPhone.trim()) {
    throw new HttpsError("invalid-argument", "Enter a valid phone number");
  }
  const amount = _assertWalletAmount(rawAmount);
  const phone = recipientPhone.trim();

  const db = getFirestore();
  const match = await db.collection("users").where("phone", "==", phone).limit(1).get();
  if (match.empty) {
    throw new HttpsError("not-found", "No MedNU account found with this phone number");
  }
  const recipientRef = match.docs[0].ref;
  if (recipientRef.id === uid) {
    throw new HttpsError("invalid-argument", "Cannot transfer to your own wallet");
  }

  // Sender label comes from the verified auth token, never from the client.
  const senderLabel =
    request.auth?.token?.phone_number || request.auth?.token?.email || "a MedNU user";
  const senderRef = db.collection("users").doc(uid);
  const stamp = Date.now();

  try {
    const balanceAfter = await db.runTransaction(async (t) => {
      const senderSnap = await t.get(senderRef);
      const recipientSnap = await t.get(recipientRef);

      const senderBalance = _walletBalanceOf(senderSnap, "walletBalance");
      if (senderBalance < amount) {
        throw new HttpsError("failed-precondition", "Insufficient wallet balance");
      }
      const senderAfter = Math.round((senderBalance - amount) * 100) / 100;
      const recipientAfter =
        Math.round((_walletBalanceOf(recipientSnap, "walletBalance") + amount) * 100) / 100;

      t.set(senderRef, { walletBalance: senderAfter }, { merge: true });
      t.set(recipientRef, { walletBalance: recipientAfter }, { merge: true });

      t.set(
        senderRef.collection("transactions").doc(),
        _legacyTxDoc({
          title: "Transfer Sent",
          amount,
          type: "debit",
          category: "transfer",
          description: `To: ${phone}`,
          walletType: "main",
        })
      );
      t.set(
        recipientRef.collection("transactions").doc(),
        _legacyTxDoc({
          title: "Transfer Received",
          amount,
          type: "credit",
          category: "transfer",
          description: `From: ${senderLabel}`,
          walletType: "main",
        })
      );

      t.set(
        db.collection("wallet_ledger").doc(),
        _ledgerDoc({
          uid,
          walletType: "main",
          type: "debit",
          amount,
          category: "transfer",
          title: "Transfer Sent",
          description: `To: ${phone}`,
          source: `transfer:${uid}:${recipientRef.id}:${stamp}`,
          balanceAfter: senderAfter,
        })
      );
      t.set(
        db.collection("wallet_ledger").doc(),
        _ledgerDoc({
          uid: recipientRef.id,
          walletType: "main",
          type: "credit",
          amount,
          category: "transfer",
          title: "Transfer Received",
          description: `From: ${senderLabel}`,
          source: `transfer:${uid}:${recipientRef.id}:${stamp}`,
          balanceAfter: recipientAfter,
        })
      );

      return senderAfter;
    });

    _logWallet("INFO", "wallet_transfer", {
      uid, recipientId: recipientRef.id, amount, balanceAfter,
    });
    return { success: true, balanceAfter };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    _logWallet("ERROR", "wallet_transfer_failed", { uid, amount, error: err.message });
    throw new HttpsError("internal", "Transfer failed. Please try again.");
  }
});

// ── Wallet: Grant referral reward ─────────────────────────────────────────────
//
// Credits BOTH parties of a referral in MedNU Money and increments the
// referrer's referralPoints. Replaces ReferralService._creditRewards' client
// batch write. Covers both Dart call sites — signup (`applyReferralCode`) and
// condition-based (`triggerReferralReward`) — because both know the referral
// doc id, which is all this needs: every amount is read from the referral doc
// server-side, never from the request payload.
//
// Request data: { referralId: string }
// Response:     { success: true, alreadyRewarded?: true }
exports.grantReferralReward = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const { referralId } = request.data || {};
  if (typeof referralId !== "string" || !referralId.trim()) {
    throw new HttpsError("invalid-argument", "A referral id is required.");
  }

  const db = getFirestore();
  const referralRef = db.collection("referrals").doc(referralId.trim());

  // Admin-configured ceilings — the referral doc is written by the client at
  // signup, so its stored amounts are capped by live config server-side.
  let capReferrer = Infinity;
  let capReferred = Infinity;
  try {
    const cfg = await db.collection("referralConfig").doc("settings").get();
    if (cfg.exists) {
      if (cfg.get("rewardsEnabled") === false) {
        throw new HttpsError("failed-precondition", "Referral rewards are currently disabled.");
      }
      const r = cfg.get("referrerReward");
      const d = cfg.get("referredReward");
      if (typeof r === "number") capReferrer = r;
      if (typeof d === "number") capReferred = d;
    }
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    _logWallet("WARNING", "referral_config_read_failed", { uid, referralId, error: err.message });
  }

  try {
    const outcome = await db.runTransaction(async (t) => {
      const refSnap = await t.get(referralRef);
      if (!refSnap.exists) {
        throw new HttpsError("not-found", "Referral not found.");
      }
      const r = refSnap.data() || {};

      // The referred user is the only party allowed to trigger the payout —
      // matching the existing Dart logic, where both call sites run as the
      // referred user.
      if (r.referredUserId !== uid) {
        throw new HttpsError("permission-denied", "You cannot trigger this referral reward.");
      }
      // Status doubles as the idempotency guard: a second call is a no-op.
      if (r.status === "rewarded") {
        return { alreadyRewarded: true };
      }
      if (r.status !== "pending") {
        throw new HttpsError("failed-precondition", "This referral is not eligible for a reward.");
      }

      const referrerId = typeof r.referrerId === "string" ? r.referrerId : "";
      if (!referrerId || referrerId === uid) {
        throw new HttpsError("failed-precondition", "Referral is malformed.");
      }

      const referrerReward = Math.max(
        0, Math.min(Number(r.referrerRewardAmount) || 0, capReferrer)
      );
      const referredReward = Math.max(
        0, Math.min(Number(r.referredRewardAmount) || 0, capReferred)
      );

      const referrerRef = db.collection("users").doc(referrerId);
      const referredRef = db.collection("users").doc(uid);
      const referrerLedger = db
        .collection("wallet_ledger")
        .doc(_ledgerId(`referral:${referralRef.id}:referrer`));
      const referredLedger = db
        .collection("wallet_ledger")
        .doc(_ledgerId(`referral:${referralRef.id}:referred`));

      const referrerSnap = await t.get(referrerRef);
      const referredSnap = await t.get(referredRef);
      const referrerLedgerSnap = await t.get(referrerLedger);
      const referredLedgerSnap = await t.get(referredLedger);
      if (referrerLedgerSnap.exists || referredLedgerSnap.exists) {
        return { alreadyRewarded: true };
      }

      if (referrerReward > 0) {
        const balanceAfter =
          Math.round((_walletBalanceOf(referrerSnap, "mednuMoneyBalance") + referrerReward) * 100) / 100;
        const points = Number(referrerSnap.get("referralPoints")) || 0;
        t.set(
          referrerRef,
          { mednuMoneyBalance: balanceAfter, referralPoints: points + 1 },
          { merge: true }
        );
        t.set(
          referrerRef.collection("transactions").doc(),
          _legacyTxDoc({
            title: "Referral Bonus",
            amount: referrerReward,
            type: "credit",
            category: "referral",
            description: "Your friend joined using your referral code",
            walletType: "mednu_money",
          })
        );
        t.set(
          referrerLedger,
          _ledgerDoc({
            uid: referrerId,
            walletType: "mednu_money",
            type: "credit",
            amount: referrerReward,
            category: "referral",
            title: "Referral Bonus",
            description: "Your friend joined using your referral code",
            source: `referral:${referralRef.id}:referrer`,
            balanceAfter,
          })
        );
      }

      if (referredReward > 0) {
        const balanceAfter =
          Math.round((_walletBalanceOf(referredSnap, "mednuMoneyBalance") + referredReward) * 100) / 100;
        t.set(referredRef, { mednuMoneyBalance: balanceAfter }, { merge: true });
        t.set(
          referredRef.collection("transactions").doc(),
          _legacyTxDoc({
            title: "Welcome Bonus",
            amount: referredReward,
            type: "credit",
            category: "referral",
            description: "Joined via referral code — use as MedNU Money for bookings",
            walletType: "mednu_money",
          })
        );
        t.set(
          referredLedger,
          _ledgerDoc({
            uid,
            walletType: "mednu_money",
            type: "credit",
            amount: referredReward,
            category: "referral",
            title: "Welcome Bonus",
            description: "Joined via referral code — use as MedNU Money for bookings",
            source: `referral:${referralRef.id}:referred`,
            balanceAfter,
          })
        );
      }

      t.update(referralRef, {
        status: "rewarded",
        rewardedAt: FieldValue.serverTimestamp(),
      });

      return { alreadyRewarded: false, referrerId, referrerReward, referredReward };
    });

    if (outcome.alreadyRewarded) {
      return { success: true, alreadyRewarded: true };
    }

    // ── In-app notifications (non-fatal, outside the transaction) ────────────
    const now = FieldValue.serverTimestamp();
    try {
      if (outcome.referrerReward > 0) {
        await db
          .collection("patient_notifications").doc(outcome.referrerId)
          .collection("items").add({
            type: "referral_reward",
            title: "Referral Reward Earned! 🎉",
            body: `You earned ₹${outcome.referrerReward.toFixed(0)} MedNU Money because a friend joined MedNU using your referral code. Use it for your next booking!`,
            createdAt: now,
            deliverAt: now,
            isRead: false,
            data: { ctaRoute: "/referral", screen: "referral" },
          });
      }
      if (outcome.referredReward > 0) {
        await db
          .collection("patient_notifications").doc(uid)
          .collection("items").add({
            type: "welcome_bonus",
            title: "Welcome Bonus Added! 🎁",
            body: `₹${outcome.referredReward.toFixed(0)} MedNU Money has been added as a welcome gift! Use it for any MedNU booking.`,
            createdAt: now,
            deliverAt: now,
            isRead: false,
            data: { ctaRoute: "/wallet", screen: "wallet" },
          });
      }
    } catch (err) {
      _logWallet("WARNING", "referral_notification_failed", { uid, referralId, error: err.message });
    }

    _logWallet("INFO", "referral_rewarded", {
      uid, referralId,
      referrerId: outcome.referrerId,
      referrerReward: outcome.referrerReward,
      referredReward: outcome.referredReward,
    });
    return { success: true };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    _logWallet("ERROR", "referral_reward_failed", { uid, referralId, error: err.message });
    throw new HttpsError("internal", "Could not grant the referral reward.");
  }
});

// ── MPIN Login: Verify MPIN + Issue Firebase Custom Token ────────────────────
//
// Enables passwordless login on any device without OTP.
// Flow: client sends phone + raw MPIN → function computes SHA-256 hash
// server-side → compares against users/{uid}.mpinHash → issues custom token.
// Lockout (5 attempts / 15 min) is enforced here just like verifyMpin() in Dart.
//
// Request data: { phone: "+919876543210", mpin: "1234" }
// Response:     { customToken: string }
exports.verifyMpinAndIssueToken = onCall(async (request) => {
  const { phone, mpin } = request.data || {};

  if (!phone || !/^\+91\d{10}$/.test(phone)) {
    throw new HttpsError("invalid-argument", "Invalid phone number.");
  }
  if (!mpin || !/^\d{4}$/.test(mpin)) {
    throw new HttpsError("invalid-argument", "Invalid MPIN format.");
  }

  const db   = getFirestore();
  const auth = getAuth();

  // 1. Resolve uid — fast path via phone_index, fallback via Firebase Auth
  let uid;
  const phoneSnap = await db.collection("phone_index").doc(phone).get();
  if (phoneSnap.exists && phoneSnap.data().uid) {
    uid = phoneSnap.data().uid;
  } else {
    // phone_index missing for users who registered before the index was added.
    // Resolve uid from Firebase Auth directly.
    try {
      uid = (await auth.getUserByPhoneNumber(phone)).uid;
    } catch (err) {
      if (err.code === "auth/user-not-found") {
        throw new HttpsError("not-found", "No account found for this number.");
      }
      throw new HttpsError("internal", "Authentication lookup failed.");
    }
  }

  // 2. Fetch user doc for stored hash + lockout state
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "Account not found.");
  }
  const data = userSnap.data();

  // 3. Lockout check
  const lockedUntilTs = data.lockedUntil;
  if (lockedUntilTs) {
    const lockedUntil = lockedUntilTs.toDate();
    if (new Date() < lockedUntil) {
      const remaining = Math.ceil((lockedUntil - new Date()) / 60000);
      throw new HttpsError(
        "resource-exhausted",
        `Account locked. Try again in ${remaining} minute(s).`
      );
    }
    // Lock expired — clear it
    await db.collection("users").doc(uid).update({
      lockedUntil: FieldValue.delete(),
      loginAttempts: 0,
    });
  }

  const storedHash = data.mpinHash;
  if (!storedHash) {
    throw new HttpsError(
      "failed-precondition",
      "MPIN not set. Please use OTP to log in."
    );
  }

  // 4. Compute hash server-side — same algorithm as Dart: SHA-256(uid:mpin:MEDNU_V1)
  const inputHash = crypto
    .createHash("sha256")
    .update(`${uid}:${mpin}:MEDNU_V1`)
    .digest("hex");

  const attempts = data.loginAttempts || 0;
  const MAX_ATTEMPTS = 5;
  const LOCK_MINUTES = 15;

  if (inputHash !== storedHash) {
    // Wrong MPIN — increment attempts, possibly lock
    const newAttempts = attempts + 1;
    if (newAttempts >= MAX_ATTEMPTS) {
      const lockUntil = new Date(Date.now() + LOCK_MINUTES * 60 * 1000);
      await db.collection("users").doc(uid).update({
        loginAttempts: newAttempts,
        lockedUntil: Timestamp.fromDate(lockUntil),
      });
      throw new HttpsError(
        "resource-exhausted",
        `Too many attempts. Account locked for ${LOCK_MINUTES} minutes.`
      );
    }
    await db.collection("users").doc(uid).update({ loginAttempts: newAttempts });
    const remaining = MAX_ATTEMPTS - newAttempts;
    throw new HttpsError(
      "unauthenticated",
      `Incorrect MPIN. ${remaining} attempt(s) left.`
    );
  }

  // 5. Correct MPIN — reset attempts, update lastLogin, issue token
  await db.collection("users").doc(uid).update({
    loginAttempts: 0,
    lockedUntil: FieldValue.delete(),
    lastLogin: FieldValue.serverTimestamp(),
  });

  // Heal phone_index if it was missing so the fast path works next time.
  if (!phoneSnap.exists || !phoneSnap.data().uid) {
    db.collection("phone_index").doc(phone).set(
      { hasMpin: true, uid, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    ).catch(() => {});
  }

  const customToken = await auth.createCustomToken(uid);
  console.log(`MPIN login success for uid ${uid}`);
  return { customToken };
});

// ═══════════════════════════════════════════════════════════════════════════════
// PAYMENT DISTRIBUTION & SETTLEMENT ENGINE
// ═══════════════════════════════════════════════════════════════════════════════
//
// One engine, used by every service type (consultation, video_consultation,
// diagnostics/lab_tests, pharmacy/medicine, ambulance, caregiver, and any
// future service). Money never moves directly from a patient to a provider:
//
//   Patient pays (Razorpay or in-app wallet)
//     -> capturePayment (server-authoritative: verifies the charge, applies
//        a coupon, computes commission, writes ONE immutable `payments` doc
//        + the matching `wallet_ledger` entries, all in one transaction)
//     -> booking is completed by the provider (each vertical's own
//        status-change trigger already existed before this section; each
//        now also calls _transitionPaymentToEligible once, on the same
//        pending->completed edge it already detects)
//     -> admin batches eligible payments into a `settlements` doc and
//        approves it (approveSettlement / bulkApproveSettlements)
//     -> admin marks it paid after transferring funds outside the app
//        (markSettlementPaid) -> provider_wallets updated, ledger entry
//        written, provider notified.
//
// Design notes that matter if you're extending this later:
//  - A specific provider is often NOT known at payment time (ambulance/lab/
//    caregiver are marketplace-matched; a patient's payment can land before
//    any partner has claimed the job). commission/providerAmount computed at
//    capture time are therefore PROVISIONAL, using the service's default
//    commission rule with no per-provider override. They are FINALIZED in
//    _transitionPaymentToEligible, which always runs at completion time —
//    by definition, the provider who did the work is known by then, however
//    early or late the initial assignment happened. A `commission_adjustment`
//    ledger entry captures the (usually zero) delta between the two.
//  - Coupon discount is treated as pure marketing spend: commission and the
//    provider's payout are computed from what the patient actually paid
//    (paidAmount), not the pre-discount price, matching the spec's own
//    "ProviderAmount = FinalPaidAmount − MedNuCommission" formula and its
//    "commission calculated on final payable amount" note. The one
//    exception is a `free_consultation` coupon: the provider is paid as if
//    the original price had been paid in full (commissionBase =
//    originalAmount even though paidAmount is 0) and the entire amount MedNu
//    fronts is booked as a Coupon Expense — otherwise providers would have
//    no incentive to honour a "free visit" campaign they didn't agree to.
//  - Every money-mutating write here goes through db.runTransaction with a
//    deterministic, existence-checked document id (via _ledgerId, same
//    helper the wallet functions above already use), so retries — whether
//    from a flaky client, an at-least-once Firestore trigger redelivery, or
//    a genuine double-tap — can never double-credit or double-debit.
// ═══════════════════════════════════════════════════════════════════════════════

const _COMMISSION_TYPES = ["percentage", "fixed", "hybrid"];
const _COUPON_DISCOUNT_TYPES = ["flat", "percentage", "free_consultation", "free_delivery", "cashback", "referral"];
const _LARGE_PAYMENT_ALERT_THRESHOLD = 20000; // ₹20,000 — tune as needed from settlement_config later.

// Where to find the assigned provider's id on each vertical's own booking
// doc, keyed by the `serviceType` the patient app already uses when it
// writes `service_requests`/`appointments`/`orders`. Extend this map — not
// the functions below — when a new service type is added.
const _PROVIDER_FIELD_BY_SERVICE = {
  consultation: "doctorId",
  video_consultation: "doctorId",
  diagnostics: "labId",
  lab_tests: "labId",
  medicine: "pharmacyId",
  pharmacy: "pharmacyId",
  ambulance: "ambulanceId",
  caregiver: "caregiverId",
  nursing: "caregiverId",
  home_care: "caregiverId",
  physiotherapy: "physiotherapistId",
  counselling: "counsellorId",
  nutrition: "nutritionistId",
  hospital_bill: "hospitalId",
  hospital_op: "hospitalId",
};

function _round2(n) {
  return Math.round((Number(n) || 0) * 100) / 100;
}

function _logSettlement(level, event, data) {
  console.log(JSON.stringify({ level, module: "settlement", event, ...data }));
}

async function _assertAdmin(db, uid) {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");
  const snap = await db.collection("admins").doc(uid).get();
  if (!snap.exists) throw new HttpsError("permission-denied", "Admin access required.");
  return snap;
}

// Every admin action that touches money or coupon/commission config writes
// one of these. Read-only for everyone but admins (see firestore.rules) —
// nothing else in the app ever writes to this collection.
function _auditLogDoc({ actorId, action, targetType, targetId, before, after }) {
  return {
    actorId, action, targetType, targetId,
    before: before === undefined ? null : before,
    after: after === undefined ? null : after,
    createdAt: FieldValue.serverTimestamp(),
  };
}

// ── Provider-side notification helper ─────────────────────────────────────────
// Mirrors _sendPatientNotification's shape/dedup/never-throw contract for the
// provider side, which previously had no shared equivalent (doctor/broadcast
// paths each inlined their own messaging().send() calls).
async function _sendProviderNotification(db, messaging, providerId, opts) {
  const { title, body, type, serviceType = "general", bookingId = "", extraData = {} } = opts;
  if (!providerId || !title || !body || !type) return;

  if (bookingId) {
    const dedupKey = `${type}_${bookingId}`;
    const cutoff = Timestamp.fromDate(new Date(Date.now() - 30_000));
    try {
      const dup = await db.collection("provider_notifications").doc(providerId)
        .collection("items").where("dedupKey", "==", dedupKey).where("createdAt", ">=", cutoff).limit(1).get();
      if (!dup.empty) return;
    } catch (_) {}
  }

  const deliverAt = Timestamp.fromDate(new Date(Date.now() - 90_000));
  const notifDoc = {
    type, title, body, serviceType, bookingId,
    createdAt: FieldValue.serverTimestamp(), deliverAt, isRead: false, data: extraData,
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 90 * 24 * 60 * 60 * 1000)),
  };
  if (bookingId) notifDoc.dedupKey = `${type}_${bookingId}`;

  try {
    await db.collection("provider_notifications").doc(providerId).collection("items").add(notifDoc);
  } catch (err) {
    console.error(`Failed to write provider notification for ${providerId}:`, err);
    return;
  }

  let fcmToken = null;
  try {
    // Providers may be doctors, labs, pharmacies, ambulances, or caregivers —
    // each keeps its profile in its own collection. Cheap enough to probe in
    // order since this only runs on real settlement/earnings events.
    const candidates = [
      "doctors", "lab_profiles", "pharmacy_profiles", "ambulance_profiles", "caregiver_profiles",
      "nutritionist_profiles", "physiotherapist_profiles", "counsellor_profiles",
    ];
    for (const col of candidates) {
      const snap = await db.collection(col).doc(providerId).get();
      if (snap.exists && snap.get("fcmToken")) { fcmToken = snap.get("fcmToken"); break; }
    }
  } catch (_) {}
  if (!fcmToken) return;

  try {
    await messaging.send({
      token: fcmToken,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries({ type, serviceType, bookingId, ...extraData }).map(([k, v]) => [k, String(v)])
      ),
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
    });
  } catch (err) {
    console.error(`FCM send failed for provider ${providerId}:`, err.message);
  }
}

// ── New-job broadcast helper ─────────────────────────────────────────────────
// Every pool-based vertical's "new job created" trigger used to write the
// job doc and stop — a provider only ever learned about it by having the
// right "incoming requests" screen open live. This pushes a "new job
// available" notification (in-app record + FCM) to every active provider of
// one type, so it also reaches a provider whose app is backgrounded or
// killed. Reuses `_sendProviderNotification` per provider — its bookingId
// dedup, `provider_notifications` write shape, and per-provider FCM send all
// apply unchanged; this only decides *who* gets one. Sends run in
// bounded-concurrency batches since a busy vertical could have many active
// providers and this must not slow down the write that triggered it.
async function _broadcastNewJobToActiveProviders(db, messaging, {
  profileCollection, title, body, type, serviceType, bookingId, extraData = {},
}) {
  let snap;
  try {
    snap = await db.collection(profileCollection).where("status", "==", "active").get();
  } catch (err) {
    console.error(`New-job broadcast: failed to query ${profileCollection}:`, err.message);
    return;
  }

  const providerIds = snap.docs.map((d) => d.id);
  const CONCURRENCY = 20;
  for (let i = 0; i < providerIds.length; i += CONCURRENCY) {
    const chunk = providerIds.slice(i, i + CONCURRENCY);
    await Promise.all(chunk.map((providerId) =>
      _sendProviderNotification(db, messaging, providerId, { title, body, type, serviceType, bookingId, extraData }),
    ));
  }
  console.log(`New-job broadcast (${type}): notified ${providerIds.length} active ${profileCollection}.`);
}

// ── Admin push helper ─────────────────────────────────────────────────────────
// Pushes FCM to every admin with a registered browser token (admins/{uid}.fcmToken,
// self-written by mednu-admin's initAdminPushNotifications — see firestore.rules).
// Not role-scoped: admin_alerts is a shared, cross-cutting "things that just
// happened" feed meant for every profile including Director, same as the bell
// it mirrors. Shared by _sendAdminAlert below and by the two admin_alerts
// writers (onSeriousComplaint, onEmergencyDoctorRequest) that build their own
// structured doc rather than going through _sendAdminAlert's opts shape. Never
// throws — an alert failing to send must never fail the operation that
// triggered it.
async function _pushToAllAdmins(db, messaging, { title, body, type }) {
  try {
    const tokensSnap = await db.collection("admins").get();
    const tokens = tokensSnap.docs.map((d) => d.get("fcmToken")).filter(Boolean);
    if (tokens.length) {
      await messaging.sendEachForMulticast({ tokens, notification: { title, body }, data: { type } });
    }
  } catch (err) {
    console.error("Failed to push admin alert:", err.message);
  }
}

// ── Admin alert helper ────────────────────────────────────────────────────────
// Writes to the existing `admin_alerts` collection and pushes FCM via
// _pushToAllAdmins above. Never throws — see that function's note.
async function _sendAdminAlert(db, messaging, opts) {
  const { title, body, type, extraData = {} } = opts;
  try {
    await db.collection("admin_alerts").add({
      title, body, type, data: extraData, isRead: false, createdAt: FieldValue.serverTimestamp(),
    });
  } catch (err) {
    console.error("Failed to write admin_alerts doc:", err.message);
  }
  await _pushToAllAdmins(db, messaging, { title, body, type });
}

// ── Commission engine ─────────────────────────────────────────────────────────
//
// `ruleSnap` must already have been read via tx.get(...) by the caller —
// this function does no I/O so it can be used on either side of a
// transaction's read/write boundary.
function _computeCommissionFromRule(ruleSnap, providerId, amount) {
  const base = _round2(Math.max(0, amount));
  if (base <= 0) return { commission: 0, providerAmount: 0 };
  if (!ruleSnap || !ruleSnap.exists) {
    // No admin-configured rule yet for this service — default to 0% rather
    // than guessing. Logged loudly elsewhere so it gets noticed.
    return { commission: 0, providerAmount: base };
  }
  const rule = ruleSnap.data() || {};
  const override = providerId && rule.providerOverrides ? rule.providerOverrides[providerId] : null;
  const type = (override && override.type) || rule.type;
  const percentage = Number((override && override.percentage) ?? rule.percentage ?? 0);
  const fixedAmount = Number((override && override.fixedAmount) ?? rule.fixedAmount ?? 0);

  let commission = 0;
  if (type === "percentage") {
    commission = base * (percentage / 100);
  } else if (type === "fixed") {
    commission = fixedAmount;
  } else if (type === "hybrid") {
    commission = fixedAmount + base * (percentage / 100);
  }
  commission = Math.max(0, Math.min(_round2(commission), base));
  return { commission, providerAmount: _round2(base - commission) };
}

// ── Coupon engine ─────────────────────────────────────────────────────────────
//
// Pure function — `couponSnap`/`redemptionSnap` must already be tx.get()'d
// by the caller. Throws HttpsError on any validation failure so the caller
// can surface it directly to the patient.
function _applyCoupon({ couponSnap, redemptionSnap, serviceType, orderAmount, now }) {
  if (!couponSnap || !couponSnap.exists) {
    throw new HttpsError("not-found", "This coupon code doesn't exist.");
  }
  const c = couponSnap.data();
  if (c.active === false) {
    throw new HttpsError("failed-precondition", "This coupon is no longer active.");
  }
  const start = c.startDate?.toDate?.();
  const end = c.endDate?.toDate?.();
  if (start && now < start) throw new HttpsError("failed-precondition", "This coupon isn't live yet.");
  if (end && now > end) throw new HttpsError("failed-precondition", "This coupon has expired.");

  // serviceType is normally one string; captureCartPayment passes an array
  // (a cart can mix service types under one coupon) — every item must be
  // covered, or the coupon is rejected for the whole cart rather than
  // partially applied.
  const applicable = Array.isArray(c.applicableServices) ? c.applicableServices : [];
  const requestedTypes = Array.isArray(serviceType) ? serviceType : [serviceType];
  if (applicable.length > 0 && !requestedTypes.every((st) => applicable.includes(st))) {
    throw new HttpsError("failed-precondition", "This coupon isn't valid for all items in your cart.");
  }
  const minOrder = Number(c.minOrderAmount) || 0;
  if (orderAmount < minOrder) {
    throw new HttpsError("failed-precondition", `Minimum order of ₹${minOrder} required for this coupon.`);
  }
  const usageLimit = Number(c.usageLimit) || 0;
  if (usageLimit > 0 && (Number(c.usedCount) || 0) >= usageLimit) {
    throw new HttpsError("failed-precondition", "This coupon has reached its usage limit.");
  }
  const perUserLimit = Number(c.perUserLimit) || 0;
  const userCount = redemptionSnap && redemptionSnap.exists ? Number(redemptionSnap.get("count")) || 0 : 0;
  if (perUserLimit > 0 && userCount >= perUserLimit) {
    throw new HttpsError("failed-precondition", "You've already used this coupon the maximum number of times.");
  }

  const discountType = c.discountType;
  if (!_COUPON_DISCOUNT_TYPES.includes(discountType)) {
    throw new HttpsError("internal", "This coupon is misconfigured. Contact support.");
  }

  const maxDiscount = Number(c.maxDiscount) || Infinity;
  let discount = 0;
  let isFreeConsultation = false;

  if (discountType === "flat" || discountType === "free_delivery") {
    discount = Math.min(Number(c.discountValue) || 0, maxDiscount, orderAmount);
  } else if (discountType === "percentage") {
    discount = Math.min(orderAmount * ((Number(c.discountValue) || 0) / 100), maxDiscount);
  } else if (discountType === "free_consultation") {
    discount = orderAmount;
    isFreeConsultation = true;
  } else if (discountType === "cashback" || discountType === "referral") {
    // These credit the patient's wallet AFTER payment rather than reducing
    // the amount due now — handled by the existing referral/cashback wallet
    // flow (grantReferralReward above), not here. No discount at capture time.
    discount = 0;
  }

  discount = _round2(Math.max(0, discount));
  return { discount, isFreeConsultation, discountType };
}

// ── OP/Rx reference number generator ──────────────────────────────────────────
// Mirrors the format the doctor app's write_prescription_screen.dart already
// uses for prescriptions ('MN-YYYYMMDD-XXXXXX') so an in-person appointment
// gets a real, unique reference the moment it's booked instead of the client
// falling back to a static 'RX-0000' placeholder before any prescription
// exists.
const _RX_ID_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
function _generateOpRxId() {
  const now = new Date();
  const date = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, "0")}${String(now.getDate()).padStart(2, "0")}`;
  const suffix = Array.from({ length: 6 }, () => _RX_ID_CHARS[crypto.randomInt(_RX_ID_CHARS.length)]).join("");
  return `MN-${date}-${suffix}`;
}

// ── Unified payment capture ───────────────────────────────────────────────────
//
// Replaces every screen's own hand-rolled "write a payments/booking doc after
// Razorpay succeeds" logic (previously duplicated across doctor_profile_
// screen.dart, cart_screen.dart, and service_booking_sheet.dart — and, as a
// server-verified-nothing phantom-paid bug, consultation_screen.dart) with
// one server-authoritative call. Every existing call site already follows a
// "pay first, then write the booking doc" flow (PaymentScreen opens before
// any booking doc exists), so this function CREATES the booking doc itself —
// atomically, together with the payments doc and its ledger entries — rather
// than requiring one to already exist. `bookingCollection` names which
// collection to create it in (`service_requests`, `appointments`, `orders`,
// etc.); `bookingData` is written verbatim as that doc's fields, exactly as
// each caller already builds it today.
//
// `walletPortionAmount` exists because the app's existing wallet/MedNU Money
// balances can cover PART of a payment even when the rest goes through
// Razorpay (see PaymentScreen._applyBalanceDeductions, which already debits
// that portion — atomically, server-side — before this function is ever
// called). This function never re-debits that portion; for paymentMethod
// 'razorpay' it only verifies the remaining gateway leg was actually charged
// the right amount (cross-checked against the server-recorded Razorpay
// order), and for 'already_settled' (the whole amount was wallet-covered,
// no gateway leg at all) it just records what already happened. The exact
// wallet debit amount is trusted from the client at that point because the
// debit itself already went through a separate, server-authoritative,
// balance-bounded call — the exposure this leaves is a possible small
// misstatement of commission/settlement math on the wallet-covered slice,
// not the ability to fabricate money; closing that fully would mean passing
// a ledger reference through and is left for a future hardening pass.
//
// Request data: {
//   serviceType, bookingCollection, bookingData: {...},
//   originalAmount, couponCode?,
//   paymentMethod: 'razorpay' | 'wallet' | 'already_settled',
//   walletPortionAmount?, // portion already debited from wallet/MedNU Money
//   // paymentMethod === 'razorpay':
//   razorpay_order_id?, razorpay_payment_id?, razorpay_signature?,
//   // paymentMethod === 'wallet' | 'already_settled':
//   idempotencyKey?,
// }
// Response: { paymentId, bookingId, ...payment fields } — a second call with
// the same Razorpay payment id (or the same idempotencyKey) returns the same
// result, including the same bookingId, without moving any money or
// creating a second booking.
exports.capturePayment = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const {
    serviceType, bookingCollection, bookingData,
    originalAmount: rawOriginal, couponCode,
    paymentMethod,
    walletPortionAmount: rawWalletPortion,
    razorpay_order_id, razorpay_payment_id, razorpay_signature,
    idempotencyKey,
  } = request.data || {};

  if (typeof serviceType !== "string" || !serviceType.trim()) {
    throw new HttpsError("invalid-argument", "serviceType is required.");
  }
  if (typeof bookingCollection !== "string" || !bookingCollection.trim()) {
    throw new HttpsError("invalid-argument", "bookingCollection is required.");
  }
  if (!bookingData || typeof bookingData !== "object" || Array.isArray(bookingData)) {
    throw new HttpsError("invalid-argument", "bookingData is required.");
  }
  const originalAmount = _assertWalletAmount(rawOriginal);
  if (!["razorpay", "wallet", "already_settled"].includes(paymentMethod)) {
    throw new HttpsError("invalid-argument", "Unknown payment method.");
  }
  let walletPortionAmount = 0;
  if (rawWalletPortion !== undefined) {
    if (typeof rawWalletPortion !== "number" || !isFinite(rawWalletPortion) || rawWalletPortion < 0) {
      throw new HttpsError("invalid-argument", "walletPortionAmount must be a non-negative number.");
    }
    walletPortionAmount = _round2(rawWalletPortion);
  }

  const db = getFirestore();
  const messaging = getMessaging();

  let paymentIdSource;
  let razorpayOrderRef = null;
  if (paymentMethod === "razorpay") {
    if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
      throw new HttpsError("invalid-argument", "Missing Razorpay verification fields.");
    }
    const body = `${razorpay_order_id}|${razorpay_payment_id}`;
    const expected = crypto.createHmac("sha256", process.env.RAZORPAY_KEY_SECRET).update(body).digest("hex");
    if (expected !== razorpay_signature) {
      _logSettlement("WARNING", "capture_signature_mismatch", { uid, orderId: razorpay_order_id });
      throw new HttpsError("unauthenticated", "Payment signature verification failed.");
    }
    paymentIdSource = `razorpay:${razorpay_payment_id}`;
    razorpayOrderRef = db.collection("razorpay_orders").doc(razorpay_order_id);
  } else {
    // 'wallet' (this function performs the debit) and 'already_settled' (the
    // debit already happened elsewhere) both need a client-supplied
    // idempotency key for the same replay-safety reason the razorpay path
    // gets for free from razorpay_payment_id.
    if (typeof idempotencyKey !== "string" || !idempotencyKey.trim() || idempotencyKey.length > 200) {
      throw new HttpsError("invalid-argument", "idempotencyKey is required.");
    }
    paymentIdSource = `${paymentMethod}:${uid}:${idempotencyKey.trim()}`;
  }

  const paymentId = _ledgerId(paymentIdSource);
  const paymentRef = db.collection("payments").doc(paymentId);
  const bookingRef = db.collection(bookingCollection).doc();
  const userRef = db.collection("users").doc(uid);
  const couponId = typeof couponCode === "string" && couponCode.trim() ? couponCode.trim().toUpperCase() : null;
  const couponRef = couponId ? db.collection("coupons").doc(couponId) : null;
  const redemptionRef = couponRef ? couponRef.collection("redemptions").doc(uid) : null;
  const commissionRuleRef = db.collection("commission_rules").doc(serviceType);

  let outcome;
  try {
    outcome = await db.runTransaction(async (tx) => {
      // ── Reads ────────────────────────────────────────────────────────────
      const existingPayment = await tx.get(paymentRef);
      if (existingPayment.exists) {
        return { alreadyCaptured: true, payment: existingPayment.data() };
      }
      const couponSnap = couponRef ? await tx.get(couponRef) : null;
      const redemptionSnap = redemptionRef ? await tx.get(redemptionRef) : null;
      const userSnap = paymentMethod === "wallet" ? await tx.get(userRef) : null;
      const ruleSnap = await tx.get(commissionRuleRef);
      const orderSnap = razorpayOrderRef ? await tx.get(razorpayOrderRef) : null;

      // ── Coupon ───────────────────────────────────────────────────────────
      let discount = 0;
      let isFreeConsultation = false;
      if (couponRef) {
        const applied = _applyCoupon({
          couponSnap, redemptionSnap, serviceType, orderAmount: originalAmount, now: new Date(),
        });
        discount = applied.discount;
        isFreeConsultation = applied.isFreeConsultation;
      }
      const paidAmount = _round2(Math.max(0, originalAmount - discount));

      if (walletPortionAmount > paidAmount + 0.01) {
        throw new HttpsError("invalid-argument", "walletPortionAmount cannot exceed the payable amount.");
      }

      if (paymentMethod === "wallet") {
        const balance = _walletBalanceOf(userSnap, "walletBalance");
        if (balance < paidAmount) throw new HttpsError("failed-precondition", "Insufficient wallet balance.");
      } else if (paymentMethod === "already_settled") {
        if (Math.abs(walletPortionAmount - paidAmount) > 0.01) {
          throw new HttpsError("failed-precondition",
            "walletPortionAmount must equal the full payable amount for already_settled payments.");
        }
      } else {
        // razorpay — cross-check the gateway leg's server-recorded order
        // amount against what this call claims was charged there (paidAmount
        // minus whatever the wallet already covered). Without this a client
        // could apply a coupon or claim a large walletPortionAmount while
        // paying the gateway only a token amount, and still have the full
        // paidAmount recorded.
        const gatewayAmount = _round2(paidAmount - walletPortionAmount);
        if (!orderSnap || !orderSnap.exists) {
          throw new HttpsError("failed-precondition", "Payment order not found. Contact support.");
        }
        // Bind the order to whoever created it — without this, a second
        // signed-in user presenting the same (order_id, payment_id,
        // signature) triplet could attribute someone else's Razorpay order
        // to their own patientId. Requires already possessing a valid
        // signature (only the paying client ever receives one), but costs
        // nothing to close outright.
        if (orderSnap.get("uid") !== uid) {
          _logSettlement("WARNING", "capture_order_uid_mismatch", { uid, orderUid: orderSnap.get("uid") });
          throw new HttpsError("permission-denied", "This payment order does not belong to you.");
        }
        const orderedAmount = _round2(Number(orderSnap.get("amountPaise") || 0) / 100);
        if (Math.abs(orderedAmount - gatewayAmount) > 0.01) {
          _logSettlement("WARNING", "capture_amount_mismatch", {
            uid, orderedAmount, gatewayAmount, paidAmount, walletPortionAmount,
          });
          throw new HttpsError("failed-precondition", "Payment amount does not match the order. Contact support.");
        }
      }

      // ── Commission (provisional if no provider is assigned yet) ────────────
      const providerId = bookingData[_PROVIDER_FIELD_BY_SERVICE[serviceType]] || bookingData.providerId || null;
      const commissionBase = isFreeConsultation ? originalAmount : paidAmount;
      const { commission, providerAmount } = _computeCommissionFromRule(ruleSnap, providerId, commissionBase);

      // ── Writes ───────────────────────────────────────────────────────────
      if (paymentMethod === "wallet") {
        const balance = _walletBalanceOf(userSnap, "walletBalance");
        const balanceAfter = _round2(balance - paidAmount);
        tx.set(userRef, { walletBalance: balanceAfter }, { merge: true });
        tx.set(userRef.collection("transactions").doc(), _legacyTxDoc({
          title: "Booking Payment", amount: paidAmount, type: "debit",
          category: "booking_payment", walletType: "main",
        }));
      }
      if (razorpayOrderRef) {
        tx.update(razorpayOrderRef, {
          status: "consumed", paymentId: razorpay_payment_id, consumedAt: FieldValue.serverTimestamp(),
        });
      }

      const isInPersonAppointment =
        bookingCollection === "appointments" && bookingData.consultationType === "In-Person";

      tx.set(bookingRef, {
        ...bookingData,
        ...(isInPersonAppointment ? { rxId: _generateOpRxId() } : {}),
        patientId: uid,
        paymentId,
        paymentStatus: "paid",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      const paymentDoc = {
        paymentId, patientId: uid, providerId, serviceType,
        bookingRef: { collection: bookingCollection, id: bookingRef.id },
        originalAmount, discount, couponCode: couponId,
        paidAmount, walletPortionAmount, commissionBase, commission, providerAmount,
        commissionFinal: !!providerId,
        paymentMethod,
        razorpayPaymentId: paymentMethod === "razorpay" ? razorpay_payment_id : null,
        status: "completed",
        settlementStatus: "pending",
        settlementId: null,
        createdAt: FieldValue.serverTimestamp(),
        completedAt: FieldValue.serverTimestamp(),
      };
      tx.set(paymentRef, paymentDoc);

      // Ledger — mirrors the spec's worked example: Payment Received /
      // Coupon Expense / Commission Reserved, written together as one batch.
      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid, walletType: "platform", type: "credit", amount: paidAmount,
        category: "payment_received", title: "Payment Received",
        description: serviceType, source: `payment:${paymentId}:received`, balanceAfter: null,
      }));
      if (discount > 0) {
        tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
          uid: "platform", walletType: "platform", type: "debit", amount: discount,
          category: "coupon_expense", title: "Coupon Expense",
          description: couponId, source: `payment:${paymentId}:coupon`, balanceAfter: null,
        }));
      }
      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid: "platform", walletType: "platform", type: "credit", amount: commission,
        category: "commission_reserved", title: "Commission Reserved",
        description: serviceType, source: `payment:${paymentId}:commission`, balanceAfter: null,
      }));

      if (couponRef) {
        tx.set(couponRef, { usedCount: FieldValue.increment(1) }, { merge: true });
        tx.set(redemptionRef, {
          count: FieldValue.increment(1), lastRedeemedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      return { alreadyCaptured: false, payment: paymentDoc, bookingId: bookingRef.id };
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    _logSettlement("ERROR", "capture_payment_failed", { uid, serviceType, error: err.message });
    _sendAdminAlert(db, messaging, {
      title: "Failed Payment", body: `capturePayment failed for ${serviceType}: ${err.message}`,
      type: "failed_payment", extraData: { uid, serviceType },
    }).catch(() => {});
    throw new HttpsError("internal", "Payment could not be recorded. Contact support before retrying.");
  }

  const bookingId = outcome.payment.bookingRef?.id || outcome.bookingId;
  _logSettlement("INFO", outcome.alreadyCaptured ? "capture_payment_replay" : "capture_payment_success", {
    paymentId, uid, serviceType, bookingId, paidAmount: outcome.payment.paidAmount,
  });

  if (!outcome.alreadyCaptured) {
    _sendPatientNotification(db, messaging, uid, {
      title: "Payment Successful",
      body: `₹${outcome.payment.paidAmount.toFixed(0)} paid successfully.`,
      type: "payment_successful", serviceType, bookingId,
    }).catch(() => {});
    if (outcome.payment.couponCode) {
      _sendPatientNotification(db, messaging, uid, {
        title: "Coupon Applied",
        body: `${outcome.payment.couponCode} saved you ₹${outcome.payment.discount.toFixed(0)}.`,
        type: "coupon_applied", serviceType, bookingId,
      }).catch(() => {});
    }
    if (outcome.payment.paidAmount >= _LARGE_PAYMENT_ALERT_THRESHOLD) {
      _sendAdminAlert(db, messaging, {
        title: "Large Payment Alert",
        body: `₹${outcome.payment.paidAmount.toFixed(0)} payment captured for ${serviceType}.`,
        type: "large_payment", extraData: { paymentId },
      }).catch(() => {});
    }
  }

  return { paymentId, bookingId, ...outcome.payment };
});

// ── Validate a coupon without paying (live discount preview in the app) ──────
exports.validateCoupon = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");
  const { couponCode, serviceType, orderAmount: rawAmount } = request.data || {};
  if (typeof couponCode !== "string" || !couponCode.trim()) {
    throw new HttpsError("invalid-argument", "A coupon code is required.");
  }
  const orderAmount = _assertWalletAmount(rawAmount);
  const db = getFirestore();
  const couponId = couponCode.trim().toUpperCase();
  const couponRef = db.collection("coupons").doc(couponId);
  const redemptionRef = couponRef.collection("redemptions").doc(uid);

  const [couponSnap, redemptionSnap] = await Promise.all([couponRef.get(), redemptionRef.get()]);
  const applied = _applyCoupon({ couponSnap, redemptionSnap, serviceType, orderAmount, now: new Date() });
  return {
    valid: true,
    discount: applied.discount,
    payable: _round2(Math.max(0, orderAmount - applied.discount)),
    title: couponSnap.get("title") || couponId,
    discountType: applied.discountType,
  };
});

// ── Cart checkout: one charge funding multiple bookings ───────────────────────
//
// cart_screen.dart lets a patient check out several different service items
// (and/or a bundled medicine order) in a single Razorpay charge. capturePayment
// above assumes one payment funds exactly one booking, which doesn't fit —
// this is the multi-item sibling: same verification/coupon/commission
// machinery, but it creates N booking docs and N `payments` docs (one per
// item, each independently valid to every downstream consumer — the
// settlement engine, refunds, the admin dashboard — which never need to know
// a "cart" was involved) in a single atomic transaction funded by one charge.
// A coupon applied to a cart is validated against every item's serviceType
// at once and its discount is prorated across items by each item's share of
// the cart total, so per-item commission still lands on the right number.
//
// Request data: {
//   items: [{ serviceType, bookingCollection, bookingData, amount }, ...],
//   couponCode?, paymentMethod: 'razorpay' | 'wallet' | 'already_settled',
//   walletPortionAmount?,
//   razorpay_order_id?, razorpay_payment_id?, razorpay_signature?,
//   idempotencyKey?,
// }
// Response: { payments: [{ paymentId, bookingId, bookingCollection,
//   serviceType, paidAmount }, ...] } — replaying the same razorpay payment
// id / idempotencyKey returns the same set without moving money twice.
exports.captureCartPayment = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const {
    items,
    couponCode,
    paymentMethod,
    walletPortionAmount: rawWalletPortion,
    razorpay_order_id, razorpay_payment_id, razorpay_signature,
    idempotencyKey,
  } = request.data || {};

  if (!Array.isArray(items) || !items.length) {
    throw new HttpsError("invalid-argument", "At least one cart item is required.");
  }
  if (items.length > 50) {
    throw new HttpsError("invalid-argument", "Too many items in one checkout.");
  }
  const normalizedItems = items.map((it, i) => {
    if (!it || typeof it.serviceType !== "string" || !it.serviceType.trim()) {
      throw new HttpsError("invalid-argument", `Item ${i}: serviceType is required.`);
    }
    if (typeof it.bookingCollection !== "string" || !it.bookingCollection.trim()) {
      throw new HttpsError("invalid-argument", `Item ${i}: bookingCollection is required.`);
    }
    if (!it.bookingData || typeof it.bookingData !== "object" || Array.isArray(it.bookingData)) {
      throw new HttpsError("invalid-argument", `Item ${i}: bookingData is required.`);
    }
    return {
      serviceType: it.serviceType.trim(),
      bookingCollection: it.bookingCollection.trim(),
      bookingData: it.bookingData,
      amount: _assertWalletAmount(it.amount),
    };
  });
  const originalAmount = _round2(normalizedItems.reduce((s, it) => s + it.amount, 0));
  if (!["razorpay", "wallet", "already_settled"].includes(paymentMethod)) {
    throw new HttpsError("invalid-argument", "Unknown payment method.");
  }
  let walletPortionAmount = 0;
  if (rawWalletPortion !== undefined) {
    if (typeof rawWalletPortion !== "number" || !isFinite(rawWalletPortion) || rawWalletPortion < 0) {
      throw new HttpsError("invalid-argument", "walletPortionAmount must be a non-negative number.");
    }
    walletPortionAmount = _round2(rawWalletPortion);
  }

  const db = getFirestore();
  const messaging = getMessaging();

  let paymentIdSource;
  let razorpayOrderRef = null;
  if (paymentMethod === "razorpay") {
    if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
      throw new HttpsError("invalid-argument", "Missing Razorpay verification fields.");
    }
    const body = `${razorpay_order_id}|${razorpay_payment_id}`;
    const expected = crypto.createHmac("sha256", process.env.RAZORPAY_KEY_SECRET).update(body).digest("hex");
    if (expected !== razorpay_signature) {
      _logSettlement("WARNING", "cart_capture_signature_mismatch", { uid, orderId: razorpay_order_id });
      throw new HttpsError("unauthenticated", "Payment signature verification failed.");
    }
    paymentIdSource = `razorpay:${razorpay_payment_id}`;
    razorpayOrderRef = db.collection("razorpay_orders").doc(razorpay_order_id);
  } else {
    if (typeof idempotencyKey !== "string" || !idempotencyKey.trim() || idempotencyKey.length > 200) {
      throw new HttpsError("invalid-argument", "idempotencyKey is required.");
    }
    paymentIdSource = `${paymentMethod}:${uid}:${idempotencyKey.trim()}`;
  }

  const cartId = _ledgerId(paymentIdSource);
  const couponId = typeof couponCode === "string" && couponCode.trim() ? couponCode.trim().toUpperCase() : null;
  const couponRef = couponId ? db.collection("coupons").doc(couponId) : null;
  const redemptionRef = couponRef ? couponRef.collection("redemptions").doc(uid) : null;
  const userRef = db.collection("users").doc(uid);

  // One paymentId per item, all derived from the same cart id. They're all
  // written in the same transaction, so the first one existing is proof the
  // whole cart already ran — that alone is enough for the idempotency check.
  const itemRefs = normalizedItems.map((it, i) => {
    const paymentId = _ledgerId(`${cartId}:${i}`);
    return {
      ...it, paymentId,
      paymentRef: db.collection("payments").doc(paymentId),
      bookingRef: db.collection(it.bookingCollection).doc(),
      ruleRef: db.collection("commission_rules").doc(it.serviceType),
    };
  });

  let outcome;
  try {
    outcome = await db.runTransaction(async (tx) => {
      // ── Reads ────────────────────────────────────────────────────────────
      const firstExisting = await tx.get(itemRefs[0].paymentRef);
      if (firstExisting.exists) {
        const allSnaps = await Promise.all(itemRefs.map((it) => tx.get(it.paymentRef)));
        return { alreadyCaptured: true, payments: allSnaps.map((s) => s.data()) };
      }
      const couponSnap = couponRef ? await tx.get(couponRef) : null;
      const redemptionSnap = redemptionRef ? await tx.get(redemptionRef) : null;
      const userSnap = paymentMethod === "wallet" ? await tx.get(userRef) : null;
      const orderSnap = razorpayOrderRef ? await tx.get(razorpayOrderRef) : null;
      const ruleSnaps = await Promise.all(itemRefs.map((it) => tx.get(it.ruleRef)));

      // ── Coupon — applied once against the cart total; the discount is
      // prorated across items by each item's share of that total so
      // per-item commission still lands on the right number ────────────────
      let discount = 0;
      let isFreeConsultation = false;
      if (couponRef) {
        const applied = _applyCoupon({
          couponSnap, redemptionSnap,
          serviceType: normalizedItems.map((it) => it.serviceType),
          orderAmount: originalAmount, now: new Date(),
        });
        discount = applied.discount;
        isFreeConsultation = applied.isFreeConsultation;
      }
      const paidAmount = _round2(Math.max(0, originalAmount - discount));

      if (walletPortionAmount > paidAmount + 0.01) {
        throw new HttpsError("invalid-argument", "walletPortionAmount cannot exceed the payable amount.");
      }

      if (paymentMethod === "wallet") {
        const balance = _walletBalanceOf(userSnap, "walletBalance");
        if (balance < paidAmount) throw new HttpsError("failed-precondition", "Insufficient wallet balance.");
      } else if (paymentMethod === "already_settled") {
        if (Math.abs(walletPortionAmount - paidAmount) > 0.01) {
          throw new HttpsError("failed-precondition",
            "walletPortionAmount must equal the full payable amount for already_settled payments.");
        }
      } else {
        const gatewayAmount = _round2(paidAmount - walletPortionAmount);
        if (!orderSnap || !orderSnap.exists) {
          throw new HttpsError("failed-precondition", "Payment order not found. Contact support.");
        }
        // See the identical check in capturePayment above for why.
        if (orderSnap.get("uid") !== uid) {
          _logSettlement("WARNING", "cart_capture_order_uid_mismatch", { uid, orderUid: orderSnap.get("uid") });
          throw new HttpsError("permission-denied", "This payment order does not belong to you.");
        }
        const orderedAmount = _round2(Number(orderSnap.get("amountPaise") || 0) / 100);
        if (Math.abs(orderedAmount - gatewayAmount) > 0.01) {
          _logSettlement("WARNING", "cart_capture_amount_mismatch", {
            uid, orderedAmount, gatewayAmount, paidAmount, walletPortionAmount,
          });
          throw new HttpsError("failed-precondition", "Payment amount does not match the order. Contact support.");
        }
      }

      // ── Writes ───────────────────────────────────────────────────────────
      if (paymentMethod === "wallet") {
        const balance = _walletBalanceOf(userSnap, "walletBalance");
        const balanceAfter = _round2(balance - paidAmount);
        tx.set(userRef, { walletBalance: balanceAfter }, { merge: true });
        tx.set(userRef.collection("transactions").doc(), _legacyTxDoc({
          title: "Cart Payment", amount: paidAmount, type: "debit",
          category: "booking_payment", walletType: "main",
        }));
      }
      if (razorpayOrderRef) {
        tx.update(razorpayOrderRef, {
          status: "consumed", paymentId: razorpay_payment_id, consumedAt: FieldValue.serverTimestamp(),
        });
      }

      const payments = [];
      itemRefs.forEach((it, i) => {
        const itemShare = originalAmount > 0 ? it.amount / originalAmount : 0;
        const itemDiscount = _round2(discount * itemShare);
        const itemPaid = _round2(Math.max(0, it.amount - itemDiscount));
        const providerId =
          it.bookingData[_PROVIDER_FIELD_BY_SERVICE[it.serviceType]] || it.bookingData.providerId || null;
        // Same free_consultation exception as capturePayment: the provider
        // is paid as if the original (pre-discount) price had been paid in
        // full — this cart path previously always used `itemPaid` here,
        // which silently zeroed out every provider's payout on a cart
        // checkout using a free_consultation coupon instead of honouring it.
        const itemCommissionBase = isFreeConsultation ? it.amount : itemPaid;
        const { commission, providerAmount } = _computeCommissionFromRule(ruleSnaps[i], providerId, itemCommissionBase);

        tx.set(it.bookingRef, {
          ...it.bookingData,
          patientId: uid,
          paymentId: it.paymentId,
          paymentStatus: "paid",
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });

        const paymentDoc = {
          paymentId: it.paymentId, patientId: uid, providerId, serviceType: it.serviceType,
          bookingRef: { collection: it.bookingCollection, id: it.bookingRef.id },
          cartId, originalAmount: it.amount, discount: itemDiscount, couponCode: couponId,
          paidAmount: itemPaid, commissionBase: itemCommissionBase, commission, providerAmount,
          commissionFinal: !!providerId,
          paymentMethod,
          razorpayPaymentId: paymentMethod === "razorpay" ? razorpay_payment_id : null,
          status: "completed", settlementStatus: "pending", settlementId: null,
          createdAt: FieldValue.serverTimestamp(), completedAt: FieldValue.serverTimestamp(),
        };
        tx.set(it.paymentRef, paymentDoc);
        payments.push(paymentDoc);

        tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
          uid, walletType: "platform", type: "credit", amount: itemPaid,
          category: "payment_received", title: "Payment Received",
          description: it.serviceType, source: `payment:${it.paymentId}:received`, balanceAfter: null,
        }));
        if (itemDiscount > 0) {
          tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
            uid: "platform", walletType: "platform", type: "debit", amount: itemDiscount,
            category: "coupon_expense", title: "Coupon Expense",
            description: couponId, source: `payment:${it.paymentId}:coupon`, balanceAfter: null,
          }));
        }
        tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
          uid: "platform", walletType: "platform", type: "credit", amount: commission,
          category: "commission_reserved", title: "Commission Reserved",
          description: it.serviceType, source: `payment:${it.paymentId}:commission`, balanceAfter: null,
        }));
      });

      if (couponRef) {
        tx.set(couponRef, { usedCount: FieldValue.increment(1) }, { merge: true });
        tx.set(redemptionRef, {
          count: FieldValue.increment(1), lastRedeemedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      return { alreadyCaptured: false, payments };
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    _logSettlement("ERROR", "cart_capture_payment_failed", { uid, error: err.message });
    _sendAdminAlert(db, messaging, {
      title: "Failed Payment", body: `captureCartPayment failed: ${err.message}`,
      type: "failed_payment", extraData: { uid },
    }).catch(() => {});
    throw new HttpsError("internal", "Payment could not be recorded. Contact support before retrying.");
  }

  _logSettlement("INFO", outcome.alreadyCaptured ? "cart_capture_replay" : "cart_capture_success", {
    uid, itemCount: outcome.payments.length,
  });

  if (!outcome.alreadyCaptured) {
    const total = _round2(outcome.payments.reduce((s, p) => s + p.paidAmount, 0));
    _sendPatientNotification(db, messaging, uid, {
      title: "Payment Successful",
      body: `₹${total.toFixed(0)} paid successfully for ${outcome.payments.length} item${outcome.payments.length === 1 ? "" : "s"}.`,
      type: "payment_successful",
    }).catch(() => {});
    if (outcome.payments[0]?.couponCode) {
      _sendPatientNotification(db, messaging, uid, {
        title: "Coupon Applied",
        body: `${outcome.payments[0].couponCode} applied to your order.`,
        type: "coupon_applied",
      }).catch(() => {});
    }
    if (total >= _LARGE_PAYMENT_ALERT_THRESHOLD) {
      _sendAdminAlert(db, messaging, {
        title: "Large Payment Alert",
        body: `₹${total.toFixed(0)} cart payment captured (${outcome.payments.length} items).`,
        type: "large_payment", extraData: { uid },
      }).catch(() => {});
    }
  }

  return {
    payments: outcome.payments.map((p) => ({
      paymentId: p.paymentId,
      bookingId: p.bookingRef.id,
      bookingCollection: p.bookingRef.collection,
      serviceType: p.serviceType,
      paidAmount: p.paidAmount,
    })),
  };
});

// ── Transition a payment into the settlement queue ────────────────────────────
//
// Called once by every vertical's own completion trigger, on the same
// "not-yet-completed -> completed" edge that trigger already detects for its
// own idempotency-guarded ledger write. Deliberately its OWN transaction,
// run AFTER the caller's existing ledger-credit transaction resolves rather
// than nested inside it — interleaving this function's reads into the
// middle of that transaction would violate Firestore's "all reads before
// all writes" rule. Safe to call unconditionally on every invocation of the
// caller's trigger, including redeliveries: it no-ops unless
// payments/{id}.settlementStatus is still "pending".
async function _transitionPaymentToEligible(db, { sourceCollection, sourceId, providerId, serviceType }) {
  if (!sourceCollection || !sourceId || !providerId) return;
  try {
    await db.runTransaction(async (tx) => {
      const sourceRef = db.collection(sourceCollection).doc(sourceId);
      const sourceSnap = await tx.get(sourceRef);
      const paymentId = sourceSnap.exists ? sourceSnap.get("paymentId") : null;
      if (!paymentId) return;

      const paymentRef = db.collection("payments").doc(paymentId);
      const paymentSnap = await tx.get(paymentRef);
      if (!paymentSnap.exists || paymentSnap.get("settlementStatus") !== "pending") return;
      const payment = paymentSnap.data();

      const ruleSnap = await tx.get(db.collection("commission_rules").doc(serviceType));
      const walletRef = db.collection("provider_wallets").doc(providerId);
      const walletSnap = await tx.get(walletRef);

      const commissionBase = Number(payment.commissionBase) || 0;
      const { commission, providerAmount } = _computeCommissionFromRule(ruleSnap, providerId, commissionBase);
      const adjustment = _round2(providerAmount - (Number(payment.providerAmount) || 0));

      tx.update(paymentRef, {
        providerId, commission, providerAmount, commissionFinal: true,
        settlementStatus: "eligible", eligibleAt: FieldValue.serverTimestamp(),
      });

      if (adjustment !== 0) {
        tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
          uid: "platform", walletType: "platform",
          type: adjustment > 0 ? "debit" : "credit", amount: Math.abs(adjustment),
          category: "commission_adjustment", title: "Commission Adjustment",
          description: `Finalized on provider assignment for payment ${paymentId}`,
          source: `payment:${paymentId}:adjustment`, balanceAfter: null,
        }));
      }

      const pendingBefore = walletSnap.exists ? Number(walletSnap.get("pendingEarnings")) || 0 : 0;
      tx.set(walletRef, {
        providerId, serviceType,
        pendingEarnings: _round2(pendingBefore + providerAmount),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });

      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid: providerId, walletType: "provider", type: "credit", amount: providerAmount,
        category: "settlement_pending", title: "Earnings Pending Settlement",
        description: serviceType, source: `payment:${paymentId}:eligible`, balanceAfter: null,
      }));
    });

    _sendProviderNotification(db, getMessaging(), providerId, {
      title: "New Earnings", body: "A completed booking is now pending settlement.",
      type: "new_earnings", serviceType,
    }).catch(() => {});
  } catch (err) {
    _logSettlement("ERROR", "transition_payment_failed", { sourceCollection, sourceId, providerId, error: err.message });
    throw err;
  }
}

// ── New Appointment Alert ─────────────────────────────────────────────────────
//
// `appointments` was the only booking collection with no onCreate trigger
// (compare onDiagnosticServiceRequestCreated etc.) — doctors got no alert at
// all when a new video/in-person appointment was booked. Writes into
// doctor_notifications/{doctorId}/items, the exact collection/schema
// NotificationService.streamForDoctor already reads (mednu_doctor
// notification_service.dart), plus an FCM push mirroring onNewConsultation's
// token lookup above so the doctor is alerted even with the app closed.
exports.onAppointmentCreated = onDocumentCreated(
  "appointments/{appointmentId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    const doctorId = data.doctorId;
    if (!doctorId) return;

    const db = getFirestore();
    const appointmentId = event.params.appointmentId;
    const isInPerson = data.consultationType === "In-Person";
    const slot = [data.date, data.time].filter(Boolean).join(" ");
    const title = "New Appointment Booked";
    const body = `${data.patientName || "A patient"} booked ${isInPerson ? "an in-person" : "a video"} appointment${slot ? ` for ${slot}` : ""}.`;

    await db.collection("doctor_notifications").doc(doctorId).collection("items").add({
      type: "appointment",
      title, body,
      createdAt: FieldValue.serverTimestamp(),
      deliverAt: FieldValue.serverTimestamp(),
      isRead: false,
      payload: { appointmentId, consultationType: data.consultationType || "Video", rxId: data.rxId || null },
    }).catch((err) => console.error("Failed to write doctor_notifications:", err.message));

    const doctorDoc = await db.collection("doctors").doc(doctorId).get();
    const fcmToken = doctorDoc.exists ? doctorDoc.data().fcmToken : null;
    if (!fcmToken) return;
    try {
      await getMessaging().send({
        token: fcmToken,
        notification: { title, body },
        data: { type: "new_appointment", appointmentId, doctorId },
        android: { priority: "high" },
        apns: { payload: { aps: { sound: "default" } } },
      });
    } catch (err) {
      console.error("FCM send failed for new appointment:", err.message);
    }
  }
);

// ── Doctor vertical parity ────────────────────────────────────────────────────
//
// The other 4 verticals (lab/pharmacy/ambulance/caregiver) already had their
// own completion -> ledger-credit triggers before this section existed;
// doctor never did (earnings were aggregated client-side from
// `appointments.fee`). This brings doctor onto the same engine as everyone
// else. A separate export (not merged into the existing
// exports.onAppointmentStatusChange notification trigger above) — Cloud
// Functions v2 allows multiple independent triggers on the same document
// path, and keeping this one separate means the working notification
// trigger is never touched.
exports.onAppointmentSettlement = onDocumentUpdated(
  "appointments/{appointmentId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status) return;
    if (after.status !== "completed" || !after.doctorId) return;

    await _transitionPaymentToEligible(getFirestore(), {
      sourceCollection: "appointments",
      sourceId: event.params.appointmentId,
      providerId: after.doctorId,
      // Every real writer of this field uses capitalized 'Video' (see
      // consultation_screen.dart, doctor_profile_screen.dart's
      // _consultationType) — this was comparing against lowercase 'video',
      // which never matched, so every appointment silently finalized
      // against the 'consultation' commission rule even when
      // capturePayment had correctly billed it as 'video_consultation'.
      serviceType: after.consultationType === "Video" ? "video_consultation" : "consultation",
    });
  }
);

// ── Support ticket resolved ────────────────────────────────────────────────
//
// `support_tickets/{ticketId}` is raised by either a patient
// (submit_ticket_screen.dart, role: 'patient', userId) or a doctor/partner
// (report_problem_screen.dart, role: 'doctor', doctorId) and, until now, its
// resolution was silent — mednu-admin's `saveTicketAdminNotes` writes
// `adminNotes` as explicitly internal ("not visible to the user" per its own
// placeholder text), so only the transition to `status: 'resolved'` (the
// admin's "Resolve" button) is the user-visible event worth a push for.
exports.onSupportTicketResolved = onDocumentUpdated(
  "support_tickets/{ticketId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status) return;
    if (after.status !== "resolved") return;

    const db = getFirestore();
    const messaging = getMessaging();
    const ticketId = event.params.ticketId;
    const title = "Support Ticket Resolved";
    const body = `Your ${after.category || "support"} ticket has been resolved. Tap to view.`;

    if (after.role === "doctor" && after.doctorId) {
      await _sendProviderNotification(db, messaging, after.doctorId, {
        title, body, type: "support_ticket_resolved", bookingId: ticketId,
      }).catch(() => {});
    } else if (after.userId) {
      await _sendPatientNotification(db, messaging, after.userId, {
        title, body, type: "support_ticket_resolved", bookingId: ticketId,
      }).catch(() => {});
    }
  }
);

// ── Support live-chat reply ──────────────────────────────────────────────────
//
// `support_chats/{uid}/messages` (live_chat_screen.dart, mednu_doctor) is a
// doctor/partner's own 1:1 thread with MedNU support — `uid` is the account
// that owns the thread, every message carries `senderId`. A reply from
// support (any `senderId` other than the thread owner) previously had no
// push at all; the owner only saw it by having the chat screen open.
exports.onSupportChatMessageCreated = onDocumentCreated(
  "support_chats/{uid}/messages/{messageId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    const uid = event.params.uid;
    if (!data.senderId || data.senderId === uid) return; // the owner's own message

    await _sendProviderNotification(getFirestore(), getMessaging(), uid, {
      title: "New reply from MedNU Support",
      body: (data.text || "").toString().slice(0, 120) || "You have a new message.",
      type: "support_chat_reply",
    }).catch(() => {});
  }
);

// ── Admin: Commission rules ───────────────────────────────────────────────────
//
// Request data: { serviceType, type: 'percentage'|'fixed'|'hybrid',
//                  percentage?, fixedAmount?, providerOverrides? }
exports.setCommissionRule = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdmin(db, uid);

  const { serviceType, type, percentage, fixedAmount, providerOverrides } = request.data || {};
  if (typeof serviceType !== "string" || !serviceType.trim()) {
    throw new HttpsError("invalid-argument", "serviceType is required.");
  }
  if (!_COMMISSION_TYPES.includes(type)) {
    throw new HttpsError("invalid-argument", "type must be percentage, fixed, or hybrid.");
  }
  const ruleRef = db.collection("commission_rules").doc(serviceType.trim());
  const before = (await ruleRef.get()).data() || null;
  const after = {
    serviceType: serviceType.trim(), type,
    percentage: Number(percentage) || 0,
    fixedAmount: Number(fixedAmount) || 0,
    providerOverrides: providerOverrides && typeof providerOverrides === "object" ? providerOverrides : {},
    updatedBy: uid, updatedAt: FieldValue.serverTimestamp(),
  };
  await ruleRef.set(after);
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "setCommissionRule", targetType: "commission_rules", targetId: serviceType, before, after,
  }));
  return { success: true };
});

// ── Admin: Coupons ────────────────────────────────────────────────────────────
function _validateCouponPayload(data) {
  const {
    code, title, description = "", discountType, discountValue,
    maxDiscount = null, minOrderAmount = 0, startDate, endDate,
    applicableServices = [], usageLimit = 0, perUserLimit = 0, active = true,
  } = data || {};
  if (typeof code !== "string" || !code.trim()) throw new HttpsError("invalid-argument", "A coupon code is required.");
  if (typeof title !== "string" || !title.trim()) throw new HttpsError("invalid-argument", "A title is required.");
  if (!_COUPON_DISCOUNT_TYPES.includes(discountType)) {
    throw new HttpsError("invalid-argument", "Invalid discountType.");
  }
  const needsValue = !["free_consultation", "cashback", "referral"].includes(discountType);
  if (needsValue && (typeof discountValue !== "number" || discountValue <= 0)) {
    throw new HttpsError("invalid-argument", "discountValue must be a positive number.");
  }
  return {
    code: code.trim().toUpperCase(), title: title.trim(), description,
    discountType, discountValue: Number(discountValue) || 0,
    maxDiscount: maxDiscount == null ? null : Number(maxDiscount),
    minOrderAmount: Number(minOrderAmount) || 0,
    startDate: startDate ? Timestamp.fromDate(new Date(startDate)) : null,
    endDate: endDate ? Timestamp.fromDate(new Date(endDate)) : null,
    applicableServices: Array.isArray(applicableServices) ? applicableServices : [],
    usageLimit: Number(usageLimit) || 0,
    perUserLimit: Number(perUserLimit) || 0,
    active: !!active,
  };
}

exports.createCoupon = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdmin(db, uid);
  const payload = _validateCouponPayload(request.data);
  const ref = db.collection("coupons").doc(payload.code);
  const existing = await ref.get();
  if (existing.exists) throw new HttpsError("already-exists", "A coupon with this code already exists.");
  const doc = { ...payload, usedCount: 0, createdBy: uid, createdAt: FieldValue.serverTimestamp() };
  await ref.set(doc);
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "createCoupon", targetType: "coupons", targetId: payload.code, before: null, after: doc,
  }));
  return { success: true, code: payload.code };
});

exports.updateCoupon = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdmin(db, uid);
  const { code } = request.data || {};
  if (typeof code !== "string" || !code.trim()) throw new HttpsError("invalid-argument", "code is required.");
  const payload = _validateCouponPayload({ ...request.data, code });
  const ref = db.collection("coupons").doc(payload.code);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Coupon not found.");
  const before = snap.data();
  const after = { ...payload, usedCount: before.usedCount || 0, updatedBy: uid, updatedAt: FieldValue.serverTimestamp() };
  await ref.set(after, { merge: true });
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "updateCoupon", targetType: "coupons", targetId: payload.code, before, after,
  }));
  return { success: true };
});

exports.toggleCoupon = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdmin(db, uid);
  const { code, active } = request.data || {};
  if (typeof code !== "string" || !code.trim()) throw new HttpsError("invalid-argument", "code is required.");
  const ref = db.collection("coupons").doc(code.trim().toUpperCase());
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Coupon not found.");
  await ref.update({ active: !!active, updatedBy: uid, updatedAt: FieldValue.serverTimestamp() });
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "toggleCoupon", targetType: "coupons", targetId: ref.id,
    before: { active: snap.get("active") }, after: { active: !!active },
  }));
  return { success: true };
});

// Soft-delete only — a hard delete would orphan coupon_redemptions history
// and make past `payments.couponCode` references unresolvable.
exports.deactivateCoupon = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdmin(db, uid);
  const { code } = request.data || {};
  if (typeof code !== "string" || !code.trim()) throw new HttpsError("invalid-argument", "code is required.");
  const ref = db.collection("coupons").doc(code.trim().toUpperCase());
  await ref.update({ active: false, deactivatedBy: uid, deactivatedAt: FieldValue.serverTimestamp() });
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "deactivateCoupon", targetType: "coupons", targetId: ref.id, before: null, after: { active: false },
  }));
  return { success: true };
});

// ── Admin: Settlement engine ──────────────────────────────────────────────────
//
// `settlements` batches N eligible `payments` docs for one provider. Moving
// a payment from "eligible" into a settlement (and later to "paid") always
// goes through these functions — the admin panel never writes settlement
// status directly, so every transition is audit-logged and provider_wallets
// stays in sync with reality.
async function _createSettlementForProvider(db, tx, { providerId, paymentDocs }) {
  const totalAmount = _round2(paymentDocs.reduce((sum, p) => sum + (Number(p.providerAmount) || 0), 0));
  const settlementRef = db.collection("settlements").doc();
  const settlement = {
    providerId,
    paymentIds: paymentDocs.map((p) => p.id),
    totalAmount,
    status: "pending", // awaiting admin review — see approveSettlement
    createdAt: FieldValue.serverTimestamp(),
  };
  tx.set(settlementRef, settlement);
  paymentDocs.forEach((p) => {
    tx.update(db.collection("payments").doc(p.id), { settlementStatus: "pending_review", settlementId: settlementRef.id });
  });
  return { id: settlementRef.id, ...settlement };
}

async function _runSettlementQueueOnce(db) {
  const eligibleSnap = await db.collection("payments").where("settlementStatus", "==", "eligible").limit(500).get();
  if (eligibleSnap.empty) return [];

  const byProvider = new Map();
  eligibleSnap.docs.forEach((d) => {
    const providerId = d.get("providerId");
    if (!providerId) return;
    if (!byProvider.has(providerId)) byProvider.set(providerId, []);
    byProvider.get(providerId).push({ id: d.id, ...d.data() });
  });

  const created = [];
  for (const [providerId, paymentDocs] of byProvider) {
    try {
      const settlement = await db.runTransaction(async (tx) => {
        // Re-check each payment is still eligible inside the transaction —
        // a concurrent refund or an earlier partial batch run could have
        // already moved one out from under us.
        const fresh = [];
        for (const p of paymentDocs) {
          const snap = await tx.get(db.collection("payments").doc(p.id));
          if (snap.exists && snap.get("settlementStatus") === "eligible") fresh.push({ id: p.id, ...snap.data() });
        }
        if (!fresh.length) return null;
        return _createSettlementForProvider(db, tx, { providerId, paymentDocs: fresh });
      });
      if (settlement) created.push(settlement);
    } catch (err) {
      _logSettlement("ERROR", "settlement_batch_failed", { providerId, error: err.message });
      _sendAdminAlert(db, getMessaging(), {
        title: "Settlement Failure", body: `Batching failed for provider ${providerId}: ${err.message}`,
        type: "settlement_failure", extraData: { providerId },
      }).catch(() => {});
    }
  }
  return created;
}

// Runs on the admin-configured schedule (settlement_config/global.frequency).
// "Manual" frequency skips the scheduled run entirely — admins use
// runManualSettlementBatch instead, which calls the exact same batching
// logic so both paths behave identically.
exports.runSettlementQueue = onSchedule({ schedule: "every 24 hours", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const configSnap = await db.collection("settlement_config").doc("global").get();
  const frequency = configSnap.exists ? configSnap.get("frequency") : "daily";
  if (frequency === "manual") {
    _logSettlement("INFO", "settlement_queue_skipped_manual_mode", {});
    return;
  }
  const created = await _runSettlementQueueOnce(db);
  _logSettlement("INFO", "settlement_queue_run", { frequency, batchesCreated: created.length });
});

exports.runManualSettlementBatch = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdmin(db, uid);
  const created = await _runSettlementQueueOnce(db);
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "runManualSettlementBatch", targetType: "settlements", targetId: null,
    before: null, after: { batchesCreated: created.length },
  }));
  return { success: true, batchesCreated: created.length };
});

exports.approveSettlement = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdmin(db, uid);
  const { settlementId } = request.data || {};
  if (typeof settlementId !== "string" || !settlementId.trim()) {
    throw new HttpsError("invalid-argument", "settlementId is required.");
  }
  const ref = db.collection("settlements").doc(settlementId);
  const before = (await ref.get()).data();
  if (!before) throw new HttpsError("not-found", "Settlement not found.");
  if (!["pending", "held"].includes(before.status)) {
    throw new HttpsError("failed-precondition", `Cannot approve a settlement in status "${before.status}".`);
  }
  await ref.update({
    status: "approved", approvedBy: uid, approvedAt: FieldValue.serverTimestamp(), holdReason: FieldValue.delete(),
  });
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "approveSettlement", targetType: "settlements", targetId: settlementId,
    before: { status: before.status }, after: { status: "approved" },
  }));
  _sendProviderNotification(db, getMessaging(), before.providerId, {
    title: "Settlement Approved",
    body: `Your settlement of ₹${before.totalAmount.toFixed(0)} has been approved for payout.`,
    type: "settlement_approved",
  }).catch(() => {});
  return { success: true };
});

exports.bulkApproveSettlements = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdmin(db, uid);
  const { settlementIds } = request.data || {};
  if (!Array.isArray(settlementIds) || !settlementIds.length) {
    throw new HttpsError("invalid-argument", "settlementIds must be a non-empty array.");
  }
  const results = [];
  for (const id of settlementIds) {
    try {
      const ref = db.collection("settlements").doc(id);
      const snap = await ref.get();
      if (!snap.exists || !["pending", "held"].includes(snap.get("status"))) {
        results.push({ id, success: false });
        continue;
      }
      await ref.update({
        status: "approved", approvedBy: uid, approvedAt: FieldValue.serverTimestamp(), holdReason: FieldValue.delete(),
      });
      results.push({ id, success: true });
    } catch (err) {
      results.push({ id, success: false, error: err.message });
    }
  }
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "bulkApproveSettlements", targetType: "settlements", targetId: null,
    before: null, after: { count: results.filter((r) => r.success).length },
  }));
  return { results };
});

exports.holdSettlement = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdmin(db, uid);
  const { settlementId, reason } = request.data || {};
  if (typeof settlementId !== "string" || !settlementId.trim()) {
    throw new HttpsError("invalid-argument", "settlementId is required.");
  }
  const ref = db.collection("settlements").doc(settlementId);
  const before = (await ref.get()).data();
  if (!before) throw new HttpsError("not-found", "Settlement not found.");
  // Unlike approveSettlement, this had no status guard at all — an admin
  // could hold a settlement already "paid" (money already transferred,
  // provider_wallets already updated by markSettlementPaid), silently
  // flipping it back to "held" with nothing reversed, desyncing the record
  // from reality. "paid" is terminal; nothing downstream of it should move.
  if (before.status === "paid") {
    throw new HttpsError("failed-precondition", "Cannot hold a settlement that has already been paid.");
  }
  await ref.update({ status: "held", holdReason: reason || "No reason given", heldBy: uid, heldAt: FieldValue.serverTimestamp() });
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "holdSettlement", targetType: "settlements", targetId: settlementId,
    before: { status: before.status }, after: { status: "held", reason },
  }));
  return { success: true };
});

// Admin has transferred the money outside the app (NEFT/UPI) and is
// recording that here. Writes the final `Provider Settlement` ledger entry
// and moves the amount from pendingEarnings to paidThisMonth.
exports.markSettlementPaid = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdmin(db, uid);
  const { settlementId, payoutReference } = request.data || {};
  if (typeof settlementId !== "string" || !settlementId.trim()) {
    throw new HttpsError("invalid-argument", "settlementId is required.");
  }
  const settlementRef = db.collection("settlements").doc(settlementId);

  let result;
  try {
    result = await db.runTransaction(async (tx) => {
      const settlementSnap = await tx.get(settlementRef);
      if (!settlementSnap.exists) throw new HttpsError("not-found", "Settlement not found.");
      const settlement = settlementSnap.data();
      if (settlement.status === "paid") return { alreadyPaid: true, settlement };
      if (settlement.status !== "approved") {
        throw new HttpsError("failed-precondition", `Settlement must be approved before it can be marked paid (currently "${settlement.status}").`);
      }

      const walletRef = db.collection("provider_wallets").doc(settlement.providerId);
      const walletSnap = await tx.get(walletRef);
      const pendingBefore = walletSnap.exists ? Number(walletSnap.get("pendingEarnings")) || 0 : 0;
      const paidBefore = walletSnap.exists ? Number(walletSnap.get("paidThisMonth")) || 0 : 0;

      tx.update(settlementRef, {
        status: "paid", paidBy: uid, paidAt: FieldValue.serverTimestamp(),
        payoutReference: payoutReference || null, payoutMethod: "manual",
      });
      settlement.paymentIds.forEach((pid) => {
        tx.update(db.collection("payments").doc(pid), { settlementStatus: "paid" });
      });
      tx.set(walletRef, {
        providerId: settlement.providerId,
        pendingEarnings: _round2(Math.max(0, pendingBefore - settlement.totalAmount)),
        paidThisMonth: _round2(paidBefore + settlement.totalAmount),
        availableBalance: _round2(paidBefore + settlement.totalAmount),
        lastPaidAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid: settlement.providerId, walletType: "provider", type: "debit", amount: settlement.totalAmount,
        category: "provider_settlement", title: "Provider Settlement",
        description: payoutReference || settlementId, source: `settlement:${settlementId}:paid`, balanceAfter: null,
      }));

      return { alreadyPaid: false, settlement };
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    _logSettlement("ERROR", "mark_settlement_paid_failed", { settlementId, error: err.message });
    _sendAdminAlert(getFirestore(), getMessaging(), {
      title: "Settlement Failure", body: `markSettlementPaid failed for ${settlementId}: ${err.message}`,
      type: "settlement_failure", extraData: { settlementId },
    }).catch(() => {});
    throw new HttpsError("internal", "Could not mark this settlement paid. Contact support.");
  }

  if (!result.alreadyPaid) {
    await db.collection("audit_logs").add(_auditLogDoc({
      actorId: uid, action: "markSettlementPaid", targetType: "settlements", targetId: settlementId,
      before: { status: "approved" }, after: { status: "paid", payoutReference },
    }));
    _sendProviderNotification(db, getMessaging(), result.settlement.providerId, {
      title: "Money Sent",
      body: `₹${result.settlement.totalAmount.toFixed(0)} has been settled to your account.`,
      type: "money_sent",
    }).catch(() => {});
  }
  return { success: true };
});

// ── Refund engine ──────────────────────────────────────────────────────────────
//
// Two paths, matching the spec exactly:
//  - Payment not yet settled to the provider: refund the patient immediately
//    and reverse the ledger — nothing has left the platform yet.
//  - Payment already settled ('paid'): the patient is STILL refunded
//    immediately (they shouldn't wait on a recovery process), but a
//    'recovery_pending' refund record + admin_alerts doc flag it for the
//    admin to recover from the provider directly or their next settlement.
exports.issueRefund = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdmin(db, uid);
  const { paymentId, reason } = request.data || {};
  if (typeof paymentId !== "string" || !paymentId.trim()) {
    throw new HttpsError("invalid-argument", "paymentId is required.");
  }

  const paymentRef = db.collection("payments").doc(paymentId);
  const paymentSnap = await paymentRef.get();
  if (!paymentSnap.exists) throw new HttpsError("not-found", "Payment not found.");
  const payment = paymentSnap.data();
  if (payment.status === "refunded") {
    throw new HttpsError("failed-precondition", "This payment has already been refunded.");
  }
  // Already batched into a settlement that hasn't been paid out yet
  // (`settlementStatus` moves 'eligible' -> 'pending_review' in
  // _createSettlementForProvider, then only becomes 'paid' once
  // markSettlementPaid actually runs). The settlement's own `totalAmount`/
  // `paymentIds` are frozen at creation and nothing re-validates them
  // against later refunds, so refunding here without pulling this payment
  // out of that batch first would let the provider still get paid the full
  // batch total once it's approved — an overpayment nothing would catch.
  // Safer to require the admin explicitly hold/deal with the settlement
  // first than to silently risk that.
  if (payment.settlementStatus === "pending_review") {
    throw new HttpsError(
      "failed-precondition",
      "This payment is already part of a pending settlement batch. Hold or resolve that settlement " +
      `(id: ${payment.settlementId || "unknown"}) before issuing a refund.`,
    );
  }

  // Reverse the gateway charge (or credit the wallet back) BEFORE touching
  // Firestore — a failed reversal must not leave a refund doc claiming money
  // moved when it didn't.
  if (payment.paymentMethod === "razorpay" && payment.razorpayPaymentId && payment.paidAmount > 0) {
    const razorpay = new Razorpay({ key_id: process.env.RAZORPAY_KEY_ID, key_secret: process.env.RAZORPAY_KEY_SECRET });
    try {
      await razorpay.payments.refund(payment.razorpayPaymentId, { amount: Math.round(payment.paidAmount * 100) });
    } catch (err) {
      _logSettlement("ERROR", "razorpay_refund_failed", { paymentId, error: err.message });
      throw new HttpsError("internal", "Refund could not be processed by the payment gateway.");
    }
  }

  const wasSettled = payment.settlementStatus === "paid";
  const refundStatus = wasSettled ? "recovery_pending" : "completed";
  const refundRef = db.collection("refunds").doc();

  await db.runTransaction(async (tx) => {
    // Re-check inside the transaction — the checks above read outside any
    // transaction, so two concurrent calls (admin double-click, or a retry)
    // could both pass them and both reach here. Without the 'refunded'
    // re-check, both would go on to credit the wallet a second time (no
    // external backstop on that path, unlike Razorpay which at least has
    // its own refund-of-a-refund rejection) and both would write a second
    // `refunds` doc. Without the 'pending_review' re-check, a settlement
    // batch created concurrently (between the read above and this
    // transaction) would slip through the same overpayment gap the earlier
    // check exists to close. Everything else read from `payment` above
    // (paymentMethod, patientId, paidAmount, commission) is immutable after
    // payment creation, so re-reading just these two fields is sufficient.
    const freshPayment = (await tx.get(paymentRef)).data();
    if (freshPayment?.status === "refunded") {
      throw new HttpsError("failed-precondition", "This payment has already been refunded.");
    }
    if (freshPayment?.settlementStatus === "pending_review") {
      throw new HttpsError(
        "failed-precondition",
        "This payment is already part of a pending settlement batch. Hold or resolve that settlement " +
        `(id: ${freshPayment.settlementId || "unknown"}) before issuing a refund.`,
      );
    }

    let userSnap = null;
    if (payment.paymentMethod === "wallet" && payment.paidAmount > 0) {
      userSnap = await tx.get(db.collection("users").doc(payment.patientId));
    }

    if (userSnap) {
      const userRef = db.collection("users").doc(payment.patientId);
      const balanceAfter = _round2(_walletBalanceOf(userSnap, "walletBalance") + payment.paidAmount);
      tx.set(userRef, { walletBalance: balanceAfter }, { merge: true });
      tx.set(userRef.collection("transactions").doc(), _legacyTxDoc({
        title: "Refund", amount: payment.paidAmount, type: "credit", category: "refund", walletType: "main",
      }));
    }

    tx.set(refundRef, {
      paymentId, patientId: payment.patientId, providerId: payment.providerId || null,
      amount: payment.paidAmount, reason: reason || "Not specified",
      status: refundStatus, initiatedBy: uid, createdAt: FieldValue.serverTimestamp(),
      completedAt: refundStatus === "completed" ? FieldValue.serverTimestamp() : null,
    });
    tx.update(paymentRef, { status: "refunded", settlementStatus: wasSettled ? "paid" : "failed" });

    if (payment.paidAmount > 0) {
      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid: "platform", walletType: "platform", type: "debit", amount: payment.paidAmount,
        category: "refund", title: "Refund Issued",
        description: reason || null, source: `payment:${paymentId}:refund`, balanceAfter: null,
      }));
    }
    if (!wasSettled && payment.commission > 0) {
      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid: "platform", walletType: "platform", type: "debit", amount: payment.commission,
        category: "commission_reversal", title: "Commission Reversed",
        source: `payment:${paymentId}:commission_reversal`, balanceAfter: null,
      }));
    }
  });

  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "issueRefund", targetType: "payments", targetId: paymentId,
    before: { status: payment.status }, after: { status: "refunded", refundStatus },
  }));

  const messaging = getMessaging();
  _sendPatientNotification(db, messaging, payment.patientId, {
    title: "Refund Processed",
    body: `₹${payment.paidAmount.toFixed(0)} has been refunded to you.`,
    type: "refund_processed", bookingId: payment.bookingRef?.id || "",
  }).catch(() => {});

  if (wasSettled) {
    _sendAdminAlert(db, messaging, {
      title: "Refund Recovery Needed",
      body: `Payment ${paymentId} was refunded after the provider was already settled — recover ₹${(payment.providerAmount || 0).toFixed(0)} from their next payout.`,
      type: "refund_recovery_pending", extraData: { paymentId, providerId: payment.providerId || "" },
    }).catch(() => {});
  }

  return { success: true, refundId: refundRef.id, status: refundStatus };
});

// ══════════════════════════════════════════════════════════════════════════
// ── Lab & Diagnostics module ────────────────────────────────────────────────
//
// The MedNu Patient app books diagnostics/lab tests through the existing,
// shared `service_requests` collection (type: 'diagnostics' | 'lab_tests') —
// it is NOT changed here. The Lab Partner module (mednu_doctor) instead
// operates against a dedicated `diagnostic_bookings` collection shaped for a
// lab's workflow (technician assignment, sample collection, report upload).
//
// These three triggers keep the two collections in sync with no possibility
// of an infinite loop, because writes only ever flow in one direction per
// hop:
//   service_requests  (create)          -> diagnostic_bookings (create)
//   service_requests  (patient cancels) -> diagnostic_bookings (status only)
//   diagnostic_bookings (lab updates)   -> service_requests (status/fields
//                                          the lab module recognizes only)
// Neither of the two "-> service_requests" hops writes back to
// diagnostic_bookings, and neither of the two "-> diagnostic_bookings" hops
// writes back to service_requests, so there is no cycle.
// ══════════════════════════════════════════════════════════════════════════

const _DIAGNOSTIC_TYPES = ["diagnostics", "lab_tests"];

// Lab-side status -> the exact service_requests status vocabulary already
// consumed by onServiceRequestStatusChange's `lab_tests`/`diagnostics` maps
// above (accepted, assigned, in_progress, sample_collected, report_ready,
// completed, rejected, cancelled). Statuses not present here (e.g. a
// lab-side 'pending') are intentionally not mirrored — 'pending' is in the
// internal-only skip list in onServiceRequestStatusChange already.
// 'expired' (see cleanupStaleDiagnosticBookings) maps onto the same patient
// message as 'cancelled' — from the patient's point of view an unclaimed
// booking that timed out and one they cancelled themselves both just mean
// "this booking didn't happen."
const _LAB_TO_SERVICE_REQUEST_STATUS = {
  accepted:            "accepted",
  rejected:             "rejected",
  technician_assigned: "assigned",
  sample_collected:    "sample_collected",
  processing:          "in_progress",
  report_uploaded:     "report_ready",
  completed:           "completed",
  expired:             "cancelled",
};

const _STALE_PENDING_HOURS = 24;

// Structured logging for every Lab module Cloud Function — one shape so
// these are easy to filter/alert on in Cloud Logging (`jsonPayload.module
// == "lab"`), independent of the free-text console.log calls the rest of
// this file already uses.
function _logLab(severity, event, data = {}) {
  const payload = { severity, module: "lab", event, ...data };
  if (severity === "ERROR" || severity === "WARNING") {
    console.error(JSON.stringify(payload));
  } else {
    console.log(JSON.stringify(payload));
  }
}

// ── 1) Mirror new diagnostics/lab_tests service_requests into diagnostic_bookings ──
exports.onDiagnosticServiceRequestCreated = onDocumentCreated(
  "service_requests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (!_DIAGNOSTIC_TYPES.includes(data.type)) return;

    const db = getFirestore();
    const requestId = event.params.requestId;
    const details = data.serviceDetails || {};
    const bookingRef = db.collection("diagnostic_bookings").doc(requestId);

    // Idempotency guard: at-least-once delivery can redeliver this event.
    // The write below is itself idempotent (same deterministic ID, same
    // content), but skipping entirely once the booking already exists
    // avoids bumping `updatedAt` and re-triggering downstream watchers
    // (e.g. the dashboard's realtime listeners) on a pure retry.
    const existing = await bookingRef.get();
    if (existing.exists) {
      _logLab("INFO", "service_request_create_skipped_existing", { requestId });
      return;
    }

    // A booking made from a specific lab's own test catalogue (see the Lab
    // Test Catalogue block below) carries that lab's id in serviceDetails —
    // pin it directly instead of dropping into the unclaimed pool, but only
    // if that lab is still active; a lab that got suspended between the
    // patient browsing and checking out falls back to the pool rather than
    // silently losing the booking.
    let pinnedLabId = null;
    if (details.sourceLabId) {
      const labSnap = await db.collection("lab_profiles").doc(details.sourceLabId).get();
      if (labSnap.exists && labSnap.data().status === "active") {
        pinnedLabId = details.sourceLabId;
      } else {
        _logLab("WARNING", "source_lab_inactive_falling_back_to_pool", {
          requestId, sourceLabId: details.sourceLabId,
        });
      }
    }

    await bookingRef.set({
      sourceRequestId: requestId,
      type: data.type,
      testName: details.testName || data.serviceName || "Diagnostic Test",
      price: details.price ?? data.amount ?? 0,
      amount: data.amount ?? details.price ?? 0,
      patientId: data.patientId,
      patientName: data.patientName || "Patient",
      patientPhone: data.patientPhone || "",
      address: data.address || "",
      preferredDate: data.preferredDate || "",
      preferredTime: data.preferredTime || "",
      notes: data.notes || "",
      labId: pinnedLabId,
      status: "pending",
      technicianId: null,
      technicianName: null,
      collectionTime: null,
      reportUrl: null,
      reportUploadedAt: null,
      reportVersion: 0,
      latestReportId: null,
      createdAt: data.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    _logLab("INFO", "diagnostic_booking_created", { requestId, type: data.type });

    const testLabel = details.testName || data.serviceName || "diagnostic test";
    if (pinnedLabId) {
      await _sendProviderNotification(db, getMessaging(), pinnedLabId, {
        title: "New Booking Assigned",
        body: `A new ${testLabel} booking has been assigned to you.`,
        type: "new_lab_booking", serviceType: "lab", bookingId: requestId,
      });
    } else {
      await _broadcastNewJobToActiveProviders(db, getMessaging(), {
        profileCollection: "lab_profiles",
        title: "New Test Booking Available",
        body: `A new ${testLabel} booking is available to claim.`,
        type: "new_lab_booking", serviceType: "lab", bookingId: requestId,
      });
    }
  }
);

// ── 2) Mirror a patient-initiated cancellation onto diagnostic_bookings ──────
exports.onDiagnosticServiceRequestCancelled = onDocumentUpdated(
  "service_requests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (!_DIAGNOSTIC_TYPES.includes(after.type)) return;
    if (before.status === after.status) return;
    if (after.status !== "cancelled") return;

    const db = getFirestore();
    const requestId = event.params.requestId;
    const bookingRef = db.collection("diagnostic_bookings").doc(requestId);

    // Idempotency guard doubles as the terminal-state guard: whether this
    // is a genuine first delivery or a redelivered retry, re-checking the
    // *current* stored status (not the before/after off this specific
    // event) is what makes repeated invocations converge safely.
    await db.runTransaction(async (tx) => {
      const bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) return;
      const currentStatus = bookingSnap.data().status;
      if (["completed", "cancelled", "rejected", "expired"].includes(currentStatus)) {
        _logLab("INFO", "cancel_mirror_skipped_terminal", { requestId, currentStatus });
        return;
      }
      tx.update(bookingRef, { status: "cancelled", updatedAt: FieldValue.serverTimestamp() });
    });
    _logLab("INFO", "diagnostic_booking_cancelled_by_patient", { requestId });
  }
);

// ── 3) Mirror lab-side booking updates back onto service_requests ───────────
// Also writes the immutable lab_transactions ledger entry once a booking is
// marked completed — mirrors the wallet architecture's
// "balance is never written directly by the client" rule: this is the one
// and only writer of lab_transactions.
exports.onDiagnosticBookingStatusChange = onDocumentUpdated(
  "diagnostic_bookings/{bookingId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    const bookingId = event.params.bookingId;
    const db = getFirestore();

    const statusChanged = before.status !== after.status;
    const technicianChanged = before.technicianName !== after.technicianName;
    const reportChanged = before.reportUrl !== after.reportUrl;

    // A failed mirror is remembered and rethrown at the very end rather than
    // immediately, so a mirror failure can never skip the ledger credit
    // below — the credit is transactionally idempotent, so it is safe to
    // have already run when the retry re-executes this function.
    let mirrorError = null;

    if (statusChanged || technicianChanged || reportChanged) {
      const update = { updatedAt: FieldValue.serverTimestamp() };

      const mappedStatus = _LAB_TO_SERVICE_REQUEST_STATUS[after.status];
      if (statusChanged && mappedStatus) update.status = mappedStatus;
      if (technicianChanged && after.technicianName) update.technicianName = after.technicianName;
      if (reportChanged && after.reportUrl) update["serviceDetails.reportUrl"] = after.reportUrl;

      if (Object.keys(update).length > 1) {
        const serviceRequestRef = db.collection("service_requests").doc(after.sourceRequestId || bookingId);
        // Idempotency: skip the write entirely if every field we're about
        // to set already matches what's stored — a redelivered event that
        // already landed becomes a no-op read instead of a redundant write
        // (and a redundant downstream patient notification).
        // Not caught: a failed read is transient and must surface as a
        // function failure (see the update below) rather than be silently
        // downgraded into "not applied yet".
        const current = await serviceRequestRef.get();
        const currentData = current.exists ? current.data() : null;
        const alreadyApplied = !!currentData &&
          (!update.status || currentData.status === update.status) &&
          (!update.technicianName || currentData.technicianName === update.technicianName) &&
          (!update["serviceDetails.reportUrl"] ||
            currentData.serviceDetails?.reportUrl === update["serviceDetails.reportUrl"]);

        if (!currentData) {
          // Permanent, not retryable — the source doc is gone. Logged loudly
          // instead of throwing, so this doesn't become an error that can
          // never succeed.
          _logLab("WARNING", "mirror_target_missing", { bookingId });
        } else if (alreadyApplied) {
          _logLab("INFO", "mirror_skipped_already_applied", { bookingId });
        } else {
          // Rethrown on failure: swallowing here would report success to the
          // platform and leave service_requests permanently stale.
          await serviceRequestRef.update(update).then(
            () => _logLab("INFO", "mirrored_to_service_request", { bookingId, fields: Object.keys(update) }),
            (err) => {
              _logLab("ERROR", "mirror_to_service_request_failed", { bookingId, error: err.message });
              mirrorError = err;
            },
          );
        }
      }
    }

    // Credit the lab's ledger exactly once, on the pending->completed edge.
    // Retry-safe: a deterministic doc ID (one ledger row per booking) plus a
    // transactional existence check means a redelivered event — or any
    // other code path that somehow re-fires this trigger for the same
    // completed booking — can never double-credit the lab.
    if (statusChanged && after.status === "completed" && before.status !== "completed" && after.labId) {
      const ledgerRef = db.collection("lab_transactions").doc(bookingId);
      const credited = await db.runTransaction(async (tx) => {
        const existing = await tx.get(ledgerRef);
        if (existing.exists) return false;
        tx.set(ledgerRef, {
          labId: after.labId,
          bookingId,
          type: "earning",
          amount: after.amount ?? after.price ?? 0,
          status: "credited",
          testName: after.testName || "Diagnostic Test",
          patientName: after.patientName || "Patient",
          createdAt: FieldValue.serverTimestamp(),
        });
        return true;
      });
      _logLab("INFO", credited ? "lab_ledger_credited" : "lab_ledger_credit_skipped_duplicate", {
        bookingId, labId: after.labId, amount: after.amount ?? after.price ?? 0,
      });

      // Settlement engine bridge — see PAYMENT DISTRIBUTION & SETTLEMENT
      // ENGINE above. No-ops if this booking's payments doc was already
      // transitioned (or was never paid through capturePayment at all).
      await _transitionPaymentToEligible(db, {
        sourceCollection: "service_requests",
        sourceId: after.sourceRequestId || bookingId,
        providerId: after.labId,
        serviceType: "diagnostics",
      });
    }

    if (mirrorError) throw mirrorError;
  }
);

// ── 4) Stale-booking cleanup ─────────────────────────────────────────────────
// A booking nobody claims eventually needs to stop showing up as "available"
// forever. Runs hourly; expires anything still `pending` after 24h, mirrored
// onto service_requests as 'cancelled' via the existing trigger #3 (by
// simply setting status: 'expired' here and letting _LAB_TO_SERVICE_REQUEST_
// STATUS + onDiagnosticBookingStatusChange do the rest — no duplicated
// mirroring logic).
// Shared by every stale-cleanup scheduled function below (Lab / Pharmacy /
// Ambulance / Caregiver). A plain batched update over a query snapshot is a
// lost-update race: a partner can claim (or a patient can cancel) one of
// these docs in the seconds between the query and the commit, and the batch
// would clobber that legitimate write back to expired/cancelled/missed.
// Each doc is instead written under a `lastUpdateTime` precondition, so a
// doc that changed after it was read is skipped rather than overwritten —
// and if it is still genuinely stale, the next hourly run picks it up.
// Per-doc (not batched) on purpose: one concurrently-modified doc must not
// fail the other 199.
async function _expireStaleDocs(docs, patch) {
  let updated = 0;
  let skipped = 0;
  await Promise.all(docs.map(async (doc) => {
    try {
      await doc.ref.update(patch, { lastUpdateTime: doc.updateTime });
      updated++;
    } catch {
      // FAILED_PRECONDITION == the doc moved on under us; anything else is
      // reported by the caller's log line as a skip too, deliberately: this
      // runs hourly and is fully self-healing on the next pass.
      skipped++;
    }
  }));
  return { updated, skipped };
}

exports.cleanupStaleDiagnosticBookings = onSchedule({ schedule: "every 60 minutes", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromDate(new Date(Date.now() - _STALE_PENDING_HOURS * 60 * 60 * 1000));

  const staleSnap = await db.collection("diagnostic_bookings")
    .where("status", "==", "pending")
    .where("createdAt", "<", cutoff)
    .limit(200) // bounded per run; the next hourly run picks up any remainder.
    .get();

  if (staleSnap.empty) {
    _logLab("INFO", "stale_cleanup_none_found");
    return;
  }

  const { updated, skipped } = await _expireStaleDocs(staleSnap.docs, { status: "expired", updatedAt: FieldValue.serverTimestamp() });
  _logLab("INFO", "stale_cleanup_expired", { count: updated, skippedConcurrentlyModified: skipped });
});

// ── 5) Lab test catalogue mirror ─────────────────────────────────────────────
// Same shape as Pharmacy's inventory -> medicines_catalogue mirror below: a
// lab's own tests, private at `lab_profiles/{labId}/tests`, get copied into
// the public `lab_tests_catalogue` only while that lab is `active`. This is
// what lets a patient browse and book a SPECIFIC lab's test directly (see
// `sourceLabId` handling in onDiagnosticServiceRequestCreated above) instead
// of only ever seeing the admin-curated, lab-agnostic `services` catalogue.
function _labTestCatalogueRef(db, labId, testId) {
  return db.collection("lab_tests_catalogue").doc(`ltinv_${labId}_${testId}`);
}

function _labTestCatalogueDoc(item, labId, testId, labName) {
  return {
    name: item.name || "",
    category: item.category || "",
    price: item.price ?? 0,
    duration: item.duration || "",
    homeCollectionAvailable: item.homeCollectionAvailable === true,
    isActive: item.isAvailable === true,
    sourceLabId: labId,
    sourceTestId: testId,
    labName: labName || "",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

exports.onLabTestInventoryWrite = onDocumentWritten(
  "lab_profiles/{labId}/tests/{testId}",
  async (event) => {
    const { labId, testId } = event.params;
    const db = getFirestore();
    const catalogueRef = _labTestCatalogueRef(db, labId, testId);

    const after = event.data.after;
    if (!after.exists) {
      await catalogueRef.delete().catch(() => {});
      _logLab("INFO", "test_mirror_deleted", { labId, testId });
      return;
    }

    const labSnap = await db.collection("lab_profiles").doc(labId).get();
    const labData = labSnap.exists ? labSnap.data() : null;

    if (!labData || labData.status !== "active") {
      // Pending/suspended labs keep their private test list but stay out of
      // the patient catalogue until (re)approved — the status-change sweep
      // below catches every existing test on that transition.
      await catalogueRef.delete().catch(() => {});
      return;
    }

    const item = after.data();
    await catalogueRef.set(
      _labTestCatalogueDoc(item, labId, testId, labData.name),
      { merge: true },
    );
    _logLab("INFO", "test_mirror_synced", { labId, testId, isActive: item.isAvailable === true });
  }
);

// When a lab's verification status flips, sweep every test it already has
// in/out of the patient catalogue — otherwise a test added while `pending`
// (or hidden after being suspended) would only reappear the next time the
// lab happened to edit that specific test again.
exports.onLabProfileStatusChangeForTests = onDocumentUpdated(
  "lab_profiles/{labId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status) return;

    const labId = event.params.labId;
    const db = getFirestore();
    const becameActive = after.status === "active";

    const testsSnap = await db
      .collection("lab_profiles").doc(labId).collection("tests")
      .get();
    if (testsSnap.empty) return;

    const batchSize = 400; // Firestore batch write limit is 500.
    for (let i = 0; i < testsSnap.docs.length; i += batchSize) {
      const batch = db.batch();
      for (const doc of testsSnap.docs.slice(i, i + batchSize)) {
        const ref = _labTestCatalogueRef(db, labId, doc.id);
        if (becameActive) {
          batch.set(ref, _labTestCatalogueDoc(doc.data(), labId, doc.id, after.name), { merge: true });
        } else {
          batch.delete(ref);
        }
      }
      await batch.commit();
    }
    _logLab("INFO", becameActive ? "test_bulk_synced" : "test_bulk_hidden", {
      labId, count: testsSnap.size,
    });
  }
);

// ── 4b) Past-due appointment cleanup ─────────────────────────────────────────
// A confirmed appointment whose scheduled date+time has passed with nobody
// marking it completed (no prescription written — see write_prescription_
// screen.dart — and no video call ended — see doctor_video_call_screen.dart)
// is a missed visit. Left alone it sits in the patient's "Upcoming" tab
// forever, since that tab filters purely on status. `date`/`time` on this
// collection are plain strings, not a Timestamp (see doctor_profile_screen.
// dart), and are written from the device's local calendar — assumed IST
// since the app is India-only. `_APPOINTMENT_GRACE_HOURS` absorbs late
// starts/clock skew before a slot is given up on.
const _APPOINTMENT_GRACE_HOURS = 3;
const _APPOINTMENT_STALE_STATUSES = ["booked", "confirmed", "accepted", "rescheduled"];

// Converts an appointment's IST wall-clock date+time into a UTC epoch ms.
// Returns null for anything that doesn't match the "h:mm AM/PM" slot format
// booking actually writes — such docs are left untouched rather than guessed at.
function _apptSlotStartMs(dateStr, timeStr) {
  const m = /^(\d{1,2}):(\d{2})\s*(AM|PM)$/i.exec((timeStr || "").trim());
  if (!m || !dateStr) return null;
  let hour = parseInt(m[1], 10) % 12;
  if (/pm/i.test(m[3])) hour += 12;
  const minute = parseInt(m[2], 10);
  const iso = `${dateStr}T${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:00+05:30`;
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? null : ms;
}

exports.expirePastDueAppointments = onSchedule({ schedule: "every 60 minutes", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const todayIST = new Date(Date.now() + 5.5 * 60 * 60 * 1000).toISOString().slice(0, 10);

  const candidatesSnap = await db.collection("appointments")
    .where("status", "in", _APPOINTMENT_STALE_STATUSES)
    .where("date", "<=", todayIST)
    .limit(300) // bounded per run; the next hourly run picks up any remainder.
    .get();

  if (candidatesSnap.empty) {
    console.log("expirePastDueAppointments: none found");
    return;
  }

  const graceMs = _APPOINTMENT_GRACE_HOURS * 60 * 60 * 1000;
  const now = Date.now();
  const toExpire = [];

  for (const doc of candidatesSnap.docs) {
    const d = doc.data();
    const slotStartMs = _apptSlotStartMs(d.date, d.time);
    if (slotStartMs === null || now - slotStartMs < graceMs) continue;

    // A video appointment mid-call must not be auto-cancelled underneath the
    // doctor — skip if the linked consultation is actively in progress.
    // consultationId only exists once someone actually tapped "join"
    // (appointment_screen.dart); its absence here means nobody ever did.
    if (d.consultationId) {
      try {
        const consultSnap = await db.collection("consultations").doc(d.consultationId).get();
        if (consultSnap.exists && consultSnap.data().status === "active") continue;
      } catch (_) {
        // Lookup failure shouldn't block cleanup of the parent appointment.
      }
    }

    toExpire.push(doc);
  }

  if (toExpire.length === 0) {
    console.log("expirePastDueAppointments: none past grace period");
    return;
  }

  const { updated, skipped } = await _expireStaleDocs(toExpire, {
    status: "cancelled",
    cancelReason: "auto_no_show",
    updatedAt: FieldValue.serverTimestamp(),
  });

  // Best-effort: mirror onto any linked consultation still sitting idle so
  // the doctor app's history doesn't show it as forever "scheduled".
  await Promise.all(toExpire.map(async (doc) => {
    const consultationId = doc.data().consultationId;
    if (!consultationId) return;
    try {
      const ref = db.collection("consultations").doc(consultationId);
      const snap = await ref.get();
      if (snap.exists && ["pending", "scheduled_waiting"].includes(snap.data().status)) {
        await ref.update({ status: "missed", updatedAt: FieldValue.serverTimestamp() });
      }
    } catch (_) {
      // Best-effort mirror only; the appointment doc is already updated.
    }
  }));

  console.log(`expirePastDueAppointments: cancelled ${updated} past-due appointment(s); ${skipped} skipped (concurrently modified).`);
});

// ── 5) Patient-visible report consistency audit ─────────────────────────────
// Detects (does not silently "fix") drift between a booking's own reportUrl
// and what the patient app actually sees on the mirrored service_requests
// doc. Auto-correcting here would risk masking a real bug in trigger #3
// behind a second, less-observable write path — this only ever logs, so a
// genuine mismatch surfaces to whoever's watching Cloud Logging rather than
// disappearing silently.
exports.auditDiagnosticReportConsistency = onSchedule({ schedule: "every 24 hours", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromDate(new Date(Date.now() - 7 * 24 * 60 * 60 * 1000));

  // Firestore only allows an inequality filter (>, <, !=, ...) on a single
  // field per query, and `updatedAt > cutoff` is the one that matters for
  // bounding this scan — `reportUrl` presence is filtered client-side
  // instead of adding a second inequality field.
  const snap = await db.collection("diagnostic_bookings")
    .where("updatedAt", ">", cutoff)
    .limit(500)
    .get();

  let mismatches = 0;
  for (const doc of snap.docs) {
    const booking = doc.data();
    if (!booking.reportUrl) continue;
    const requestId = booking.sourceRequestId || doc.id;
    const reqSnap = await db.collection("service_requests").doc(requestId).get();
    if (!reqSnap.exists) {
      _logLab("WARNING", "report_audit_missing_service_request", { bookingId: doc.id, requestId });
      mismatches++;
      continue;
    }
    const mirroredUrl = reqSnap.data().serviceDetails?.reportUrl;
    if (mirroredUrl !== booking.reportUrl) {
      _logLab("WARNING", "report_audit_url_mismatch", {
        bookingId: doc.id,
        requestId,
        bookingReportUrl: booking.reportUrl,
        mirroredReportUrl: mirroredUrl || null,
      });
      mismatches++;
    }
  }
  _logLab("INFO", "report_audit_complete", { checked: snap.size, mismatches });
});

// ══════════════════════════════════════════════════════════════════════════
// ── Pharmacy & Medical Equipment module ─────────────────────────────────────
//
// Unlike Lab (single source collection), Pharmacy bridges TWO real,
// already-live patient-side collections that were never designed to share a
// vocabulary:
//   - `orders`            — medicine line-item checkouts (multi-item, no
//                            existing status-notification pipeline at all).
//   - `service_requests`  — medical equipment rent/buy requests
//                            (type: 'equipment'), which DOES already ride
//                            onServiceRequestStatusChange's generic
//                            notification fallback, same as Lab's diagnostics
//                            bookings did.
// A dormant `medicine_orders` collection + `onMedicineOrderStatusChange`
// trigger already existed in this file before this module — nothing writes
// to it (confirmed: no patient-app code references it). It is NOT used
// here, deliberately, for the same reason `lab_bookings` wasn't used for
// Lab: mirroring from it would silently receive zero real orders.
//
// Both sources mirror into one unified `pharmacy_orders` collection (same
// doc ID as the source, `sourceCollection` records which one), so the
// Pharmacy Partner client only ever has to know one shape. Status flows
// one-directional per hop exactly like Lab's mirrors, so there is no cycle:
//   orders (create)                    -> pharmacy_orders (create)
//   service_requests[equipment] create -> pharmacy_orders (create)
//   pharmacy_orders (pharmacy updates) -> orders (status only, medicine)
//                                       -> service_requests (status only, equipment)
// ══════════════════════════════════════════════════════════════════════════

const _PHARMACY_STALE_PENDING_HOURS = 24;

function _logPharmacy(severity, event, data = {}) {
  const payload = { severity, module: "pharmacy", event, ...data };
  if (severity === "ERROR" || severity === "WARNING") {
    console.error(JSON.stringify(payload));
  } else {
    console.log(JSON.stringify(payload));
  }
}

// Pharmacy-side status -> `orders.status` (medicine). `orders` has no
// pre-existing consumer of this field beyond the owning patient's own
// cancel-only self-update, so these values are written verbatim rather than
// translated into some other app's vocabulary — there isn't one yet.
const _PHARMACY_TO_ORDER_STATUS = {
  verified:          "verified",
  packed:            "packed",
  out_for_delivery:  "out_for_delivery",
  delivered:         "delivered",
  cancelled:         "cancelled",
};

// Pharmacy-side status -> the existing service_requests vocabulary, reusing
// onServiceRequestStatusChange's generic fallback map (equipment isn't a
// named type in its per-service statusMap, so it already falls through to
// genericMap: accepted/assigned/in_progress/completed/rejected/cancelled).
const _PHARMACY_TO_SERVICE_REQUEST_STATUS = {
  verified:          "accepted",
  packed:            "assigned",
  out_for_delivery:  "in_progress",
  delivered:         "completed",
  cancelled:         "cancelled",
};

// Same-status-or-listed-forward-transition guard, mirrored server-side in
// firestore.rules too (client and Cloud Function agree on the same graph).
const _PHARMACY_VALID_TRANSITIONS = {
  pending:              ["prescription_required", "verified", "cancelled"],
  prescription_required: ["verified", "cancelled"],
  verified:             ["packed", "cancelled"],
  packed:               ["out_for_delivery", "cancelled"],
  out_for_delivery:     ["delivered", "cancelled"],
};

function _pharmacyStatusMessage(orderType, status) {
  const map = {
    // The pharmacy can move an order to 'prescription_required' (see
    // _PHARMACY_VALID_TRANSITIONS / firestore.rules). It is deliberately not
    // in _PHARMACY_TO_ORDER_STATUS — the patient-facing `orders.status`
    // vocabulary has no equivalent — but the patient still has to be told,
    // otherwise the order silently stalls until the 24h stale cleanup
    // cancels it.
    prescription_required: ["Prescription Required", "Your order needs a valid prescription. Tap to upload it."],
    verified:         ["Order Verified", "Your pharmacy order has been verified and is being prepared."],
    packed:           ["Order Packed", "Your order has been packed and will be dispatched soon."],
    out_for_delivery: ["Out for Delivery", "Your order is out for delivery."],
    delivered:        ["Order Delivered", "Your order has been delivered. Feel better soon!"],
    cancelled:        ["Order Cancelled", `Your ${orderType === "equipment" ? "equipment" : "pharmacy"} order was cancelled.`],
  };
  return map[status] || null;
}

// ── 1) Mirror new medicine `orders` into pharmacy_orders + pharmacy_order_items ──
exports.onMedicineOrderCreated = onDocumentCreated(
  "orders/{orderDocId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    const orderId = event.params.orderDocId;
    const db = getFirestore();

    const pharmacyOrderRef = db.collection("pharmacy_orders").doc(orderId);
    const existing = await pharmacyOrderRef.get();
    if (existing.exists) {
      _logPharmacy("INFO", "medicine_order_create_skipped_existing", { orderId });
      return;
    }

    const items = Array.isArray(data.items) ? data.items.slice(0, 50) : [];

    // A medicine requires a prescription per its `medicines_catalogue` doc,
    // not per order-line-item (the order snapshot doesn't carry the flag) —
    // look each one up. Bounded by `items.length` (already capped above).
    let requiresPrescription = false;
    try {
      const catalogueSnaps = await Promise.all(
        items
          .map((i) => i.id)
          .filter(Boolean)
          .map((id) => db.collection("medicines_catalogue").doc(String(id)).get()),
      );
      requiresPrescription = catalogueSnaps.some((s) => s.exists && s.data().requiresPrescription === true);
    } catch (err) {
      // Fail CLOSED. A transient read failure previously left this `false`,
      // which would let a prescription-only medicine through the pharmacy
      // pipeline with no prescription ever requested. Defaulting to `true`
      // costs at worst one unnecessary prescription prompt.
      requiresPrescription = true;
      _logPharmacy("ERROR", "prescription_lookup_failed_defaulting_required", { orderId, error: err.message });
    }

    const totalAmount = data.total ?? items.reduce((sum, i) => sum + (i.price || 0) * (i.count || 1), 0);

    // An order placed from a specific pharmacy's own menu carries that
    // pharmacy's id on the order doc (see cart_screen.dart's checkout,
    // hoisted from the cart-locked medicine items' `sourcePharmacyId`) — pin
    // it directly instead of dropping into the unclaimed pool, but only if
    // that pharmacy is still active; a pharmacy suspended between the patient
    // browsing and checking out falls back to the pool rather than silently
    // losing the order. Mirrors the lab pinning in
    // onDiagnosticServiceRequestCreated above.
    let pinnedPharmacyId = null;
    if (data.pharmacyId) {
      const pharmacySnap = await db.collection("pharmacy_profiles").doc(data.pharmacyId).get();
      if (pharmacySnap.exists && pharmacySnap.data().status === "active") {
        pinnedPharmacyId = data.pharmacyId;
      } else {
        _logPharmacy("WARNING", "source_pharmacy_inactive_falling_back_to_pool", {
          orderId, sourcePharmacyId: data.pharmacyId,
        });
      }
    }

    // The order doc and its line items are written in ONE batch with
    // deterministic item IDs (`{orderId}_{index}`). Previously the items used
    // auto-IDs in a second commit: two concurrent redeliveries could both
    // pass the existence check above and duplicate every line item, and a
    // failure between the two writes left an order with no items at all that
    // the existence check would then never repair.
    const batch = db.batch();
    batch.set(pharmacyOrderRef, {
      sourceCollection: "orders",
      sourceId: orderId,
      orderType: "medicine",
      pharmacyId: pinnedPharmacyId,
      status: "pending",
      requiresPrescription,
      // A prescription attached before checkout (medicine_screen.dart's
      // Upload Prescription action, carried into the order's own create-time
      // write) must be visible to the pharmacy immediately, not just ones
      // uploaded after the order already exists — this was unconditionally
      // null regardless of what the order doc actually had.
      prescriptionUrl: data.prescriptionUrl || null,
      patientId: data.patientId,
      patientName: data.deliveryName || "Patient",
      patientPhone: data.deliveryPhone || "",
      deliveryAddress: data.deliveryAddress || "",
      itemCount: items.length,
      totalAmount,
      deliveryPersonName: null,
      createdAt: data.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    items.forEach((item, i) => {
      batch.set(db.collection("pharmacy_order_items").doc(`${orderId}_${i}`), {
        orderId,
        // The `medicines_catalogue` doc id this line item was ordered from —
        // for pharmacy-sourced medicines this is `phinv_{pharmacyId}_{itemId}`
        // (see `_pharmacyInventoryCatalogueRef` below), which
        // PharmacyOrderService.acceptOrder (mednu_doctor) uses to decrement
        // that pharmacy's own inventory stock. null for admin-added catalogue
        // medicines, which carry no inventory doc to decrement.
        medicineId: item.id || null,
        name: item.name || "Item",
        brand: item.brand || "",
        price: item.price ?? 0,
        count: item.count ?? 1,
        subtotal: (item.price ?? 0) * (item.count ?? 1),
      });
    });
    await batch.commit();

    _logPharmacy("INFO", "pharmacy_order_created", { orderId, orderType: "medicine", items: items.length, requiresPrescription });

    const itemLabel = `${items.length} item${items.length === 1 ? "" : "s"}`;
    if (pinnedPharmacyId) {
      await _sendProviderNotification(db, getMessaging(), pinnedPharmacyId, {
        title: "New Order Assigned",
        body: `A new medicine order (${itemLabel}) has been assigned to you.`,
        type: "new_pharmacy_order", serviceType: "pharmacy", bookingId: orderId,
      });
    } else {
      await _broadcastNewJobToActiveProviders(db, getMessaging(), {
        profileCollection: "pharmacy_profiles",
        title: "New Medicine Order Available",
        body: `A new medicine order (${itemLabel}) is available to claim.`,
        type: "new_pharmacy_order", serviceType: "pharmacy", bookingId: orderId,
      });
    }
  }
);

// ── 2) Mirror new equipment service_requests into pharmacy_orders ───────────
exports.onEquipmentServiceRequestCreated = onDocumentCreated(
  "service_requests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (data.type !== "equipment") return;

    const db = getFirestore();
    const requestId = event.params.requestId;
    const pharmacyOrderRef = db.collection("pharmacy_orders").doc(requestId);

    const existing = await pharmacyOrderRef.get();
    if (existing.exists) {
      _logPharmacy("INFO", "equipment_request_create_skipped_existing", { requestId });
      return;
    }

    const details = data.serviceDetails || {};
    const amount = data.amount ?? details.purchasePrice ?? details.pricePerDay ?? 0;

    // One batch + a deterministic line-item ID, same reasoning as
    // onMedicineOrderCreated above (no duplicate item on a redelivery, no
    // order left permanently item-less by a partial failure).
    const batch = db.batch();
    batch.set(pharmacyOrderRef, {
      sourceCollection: "service_requests",
      sourceId: requestId,
      orderType: "equipment",
      pharmacyId: null,
      status: "pending",
      requiresPrescription: false,
      prescriptionUrl: null,
      patientId: data.patientId,
      patientName: data.patientName || "Patient",
      patientPhone: data.patientPhone || "",
      deliveryAddress: data.address || "",
      itemCount: 1,
      totalAmount: amount,
      deliveryPersonName: null,
      createdAt: data.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    batch.set(db.collection("pharmacy_order_items").doc(`${requestId}_0`), {
      orderId: requestId,
      name: details.equipmentName || data.serviceName || "Medical Equipment",
      brand: details.mode === "rent" ? `Rental • ${details.rentalDays || 1} day(s)` : "Purchase",
      price: amount,
      count: 1,
      subtotal: amount,
    });

    await batch.commit();

    _logPharmacy("INFO", "pharmacy_order_created", { orderId: requestId, orderType: "equipment" });

    await _broadcastNewJobToActiveProviders(db, getMessaging(), {
      profileCollection: "pharmacy_profiles",
      title: "New Equipment Request Available",
      body: `A new ${details.equipmentName || data.serviceName || "medical equipment"} request is available to claim.`,
      type: "new_pharmacy_order", serviceType: "equipment", bookingId: requestId,
    });
  }
);

// ── 2b) Mirror a patient's prescription upload onto pharmacy_orders ─────────
// Patients upload directly onto their own `orders` doc (see
// firestore.rules — patient can self-write prescriptionUrl/
// prescriptionFileType/prescriptionUploadedAt only, never the verification
// verdict). This one-way mirror is what makes it show up on the pharmacy
// side in realtime, and — since a re-upload should always restart
// verification — resets prescriptionVerified/prescriptionRejectedReason
// back to null on the SAME `orders` doc after mirroring. That reset write
// re-triggers this function, but the guard on `before.prescriptionUrl !==
// after.prescriptionUrl` makes the second pass a no-op (the URL didn't
// change on that hop), so this converges in exactly two invocations and
// never loops.
exports.onOrderPrescriptionUploaded = onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.prescriptionUrl === after.prescriptionUrl) return;

    const orderId = event.params.orderId;
    const db = getFirestore();

    const pharmacyOrderRef = db.collection("pharmacy_orders").doc(orderId);

    // The create-mirror (onMedicineOrderCreated) normally lands well before
    // any realistic upload timing, but Cloud Functions give no ordering
    // guarantee between two independent triggers on two different
    // documents. Rather than skip the mirror outright on a cold race,
    // retry with backoff for a few seconds — cheap, and turns a
    // theoretical race into a practical non-issue instead of a silently
    // dropped prescription.
    let pharmacyOrderSnap = await pharmacyOrderRef.get();
    let attempts = 0;
    while (!pharmacyOrderSnap.exists && attempts < 4) {
      attempts++;
      await new Promise((resolve) => setTimeout(resolve, 1500 * attempts));
      pharmacyOrderSnap = await pharmacyOrderRef.get();
    }
    if (!pharmacyOrderSnap.exists) {
      // Still missing after ~15s of backoff — genuinely abnormal (e.g.
      // onMedicineOrderCreated itself failed). Logged loudly so it's
      // actionable rather than silently creating a partial doc that
      // onMedicineOrderCreated's own idempotency guard would then never
      // fully populate.
      _logPharmacy("ERROR", "prescription_mirror_failed_no_pharmacy_order", { orderId, attempts });
      return;
    }

    // A fresh upload (or a removal) always invalidates any prior
    // verification decision on BOTH copies — pharmacy_orders (so the
    // pharmacist doesn't see a stale "rejected" badge next to a brand-new
    // file) and the source `orders` doc itself (reset separately below).
    await pharmacyOrderRef.update({
      prescriptionUrl: after.prescriptionUrl ?? null,
      prescriptionFileType: after.prescriptionFileType ?? null,
      prescriptionUploadedAt: after.prescriptionUploadedAt ?? FieldValue.serverTimestamp(),
      prescriptionVerified: null,
      prescriptionRejectedReason: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    _logPharmacy("INFO", "prescription_mirrored_to_pharmacy", { orderId });

    // Reset verification state on the source doc too — idempotent (only
    // writes if something would actually change), see the function-level
    // comment above for why this can't loop.
    if (after.prescriptionVerified != null || after.prescriptionRejectedReason != null) {
      await db.collection("orders").doc(orderId).update({
        prescriptionVerified: null,
        prescriptionRejectedReason: null,
      });
      _logPharmacy("INFO", "prescription_verification_reset", { orderId });
    }
  }
);

// ── 2c) Mirror a patient-initiated cancellation onto pharmacy_orders ────────
// Lab, Ambulance and Caregiver each already have this hop; Pharmacy was the
// one module missing it, so a patient cancelling their own `orders` doc (the
// only status write firestore.rules lets them make) or their equipment
// service_request left the pharmacy still seeing — and still fulfilling — an
// order the patient had already cancelled.
//
// No cycle: trigger #3's reverse mirror writes 'cancelled' onto the source,
// which re-fires this function, but by then pharmacy_orders is already
// 'cancelled' and the terminal-state guard below makes it a no-op.
async function _mirrorPharmacyCancellation(db, orderId) {
  const pharmacyOrderRef = db.collection("pharmacy_orders").doc(orderId);
  await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(pharmacyOrderRef);
    if (!orderSnap.exists) return;
    const currentStatus = orderSnap.data().status;
    if (["delivered", "cancelled"].includes(currentStatus)) {
      _logPharmacy("INFO", "cancel_mirror_skipped_terminal", { orderId, currentStatus });
      return;
    }
    tx.update(pharmacyOrderRef, { status: "cancelled", updatedAt: FieldValue.serverTimestamp() });
  });
  _logPharmacy("INFO", "pharmacy_order_cancelled_by_patient", { orderId });
}

exports.onMedicineOrderCancelledByPatient = onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status) return;
    if (after.status !== "cancelled") return;
    await _mirrorPharmacyCancellation(getFirestore(), event.params.orderId);
  }
);

exports.onEquipmentServiceRequestCancelled = onDocumentUpdated(
  "service_requests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (after.type !== "equipment") return;
    if (before.status === after.status) return;
    if (after.status !== "cancelled") return;
    await _mirrorPharmacyCancellation(getFirestore(), event.params.requestId);
  }
);

// ── 3) Mirror pharmacy-side updates back onto the correct source collection ──
// Also credits the immutable pharmacy_transactions ledger exactly once, on
// the ->delivered edge — same deterministic-ID-plus-transaction pattern
// used for lab_transactions, for the same double-credit-proofing reason.
exports.onPharmacyOrderStatusChange = onDocumentUpdated(
  "pharmacy_orders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    const orderId = event.params.orderId;
    const db = getFirestore();

    const statusChanged = before.status !== after.status;
    const deliveryPersonChanged = before.deliveryPersonName !== after.deliveryPersonName;
    const prescriptionDecisionChanged = before.prescriptionVerified !== after.prescriptionVerified;
    const isMedicine = after.sourceCollection === "orders";

    // Remembered and rethrown at the end (see the Lab mirror) so a failed
    // mirror never skips the notification or the ledger credit below, while
    // still failing the invocation instead of reporting a false success.
    let mirrorError = null;

    if (statusChanged || deliveryPersonChanged) {
      const mappedStatus = isMedicine
        ? _PHARMACY_TO_ORDER_STATUS[after.status]
        : _PHARMACY_TO_SERVICE_REQUEST_STATUS[after.status];

      if (statusChanged && mappedStatus) {
        const sourceRef = db.collection(after.sourceCollection).doc(after.sourceId || orderId);
        const current = await sourceRef.get();
        const alreadyApplied = current.exists && current.data().status === mappedStatus;

        if (!current.exists) {
          _logPharmacy("WARNING", "mirror_target_missing", { orderId, sourceCollection: after.sourceCollection });
        } else if (alreadyApplied) {
          _logPharmacy("INFO", "mirror_skipped_already_applied", { orderId });
        } else {
          await sourceRef.update({ status: mappedStatus, updatedAt: FieldValue.serverTimestamp() }).then(
            () => _logPharmacy("INFO", "mirrored_to_source", { orderId, sourceCollection: after.sourceCollection, mappedStatus }),
            (err) => {
              _logPharmacy("ERROR", "mirror_to_source_failed", { orderId, error: err.message });
              mirrorError = err;
            },
          );
        }
      }
    }

    // ── Prescription decision (medicine orders only) ──────────────────────
    // A pharmacist's verify/reject/re-request action writes
    // prescriptionVerified/prescriptionRejectedReason on pharmacy_orders —
    // mirrored back onto the real `orders` doc here, since the client never
    // writes those two fields on `orders` directly (see firestore.rules:
    // patient can only self-write prescriptionUrl/prescriptionFileType/
    // prescriptionUploadedAt, never the verification verdict).
    if (isMedicine && prescriptionDecisionChanged) {
      const sourceRef = db.collection(after.sourceCollection).doc(after.sourceId || orderId);
      await sourceRef.update({
        prescriptionVerified: after.prescriptionVerified ?? null,
        prescriptionRejectedReason: after.prescriptionRejectedReason ?? null,
        updatedAt: FieldValue.serverTimestamp(),
      }).then(
        () => _logPharmacy("INFO", "prescription_decision_mirrored", { orderId, verified: after.prescriptionVerified }),
        (err) => {
          _logPharmacy("ERROR", "prescription_decision_mirror_failed", { orderId, error: err.message });
          mirrorError = err;
        },
      );
    }

    // ── Notifications — at most one per update, prescription decisions take
    // priority over the generic status message when both changed in the
    // same write (e.g. "reject" sets prescriptionVerified:false AND
    // status:'cancelled' together). `orders` has no pre-existing
    // notification pipeline (unlike service_requests, which already gets
    // one for free via onServiceRequestStatusChange's generic fallback) —
    // sent directly here, reusing the existing _sendPatientNotification
    // helper rather than inventing a second notification path.
    if (isMedicine && after.patientId) {
      let notif = null;

      if (prescriptionDecisionChanged && after.prescriptionVerified === true) {
        notif = ["Prescription Verified", "Your prescription has been verified. Your order is being prepared.", "prescription_verified"];
      } else if (prescriptionDecisionChanged && after.prescriptionVerified === false) {
        const reason = after.prescriptionRejectedReason || "Please review and re-upload your prescription.";
        notif = after.status === "cancelled"
          ? ["Prescription Rejected", reason, "prescription_rejected"]
          : ["Prescription Needs Attention", reason, "prescription_reupload_requested"];
      } else if (statusChanged) {
        const messages = _pharmacyStatusMessage(after.orderType, after.status);
        if (messages) notif = [...messages, `pharmacy_${after.status}`];
      }

      if (notif) {
        await _sendPatientNotification(db, getMessaging(), after.patientId, {
          title: notif[0],
          body: notif[1],
          type: notif[2],
          serviceType: "medicine",
          bookingId: orderId,
          actionType: "open_service",
          extraData: { status: after.status, prescriptionVerified: after.prescriptionVerified ?? null },
        });
      }
    }

    if (statusChanged && after.status === "delivered" && before.status !== "delivered" && after.pharmacyId) {
      await _transitionPaymentToEligible(db, {
        sourceCollection: after.sourceCollection || "service_requests",
        sourceId: after.sourceId || after.sourceRequestId || orderId,
        providerId: after.pharmacyId,
        serviceType: isMedicine ? "medicine" : "pharmacy",
      });

      const ledgerRef = db.collection("pharmacy_transactions").doc(orderId);
      const credited = await db.runTransaction(async (tx) => {
        const existingTx = await tx.get(ledgerRef);
        if (existingTx.exists) return false;
        tx.set(ledgerRef, {
          pharmacyId: after.pharmacyId,
          orderId,
          type: "earning",
          amount: after.totalAmount ?? 0,
          status: "credited",
          orderType: after.orderType || "medicine",
          patientName: after.patientName || "Patient",
          createdAt: FieldValue.serverTimestamp(),
        });
        return true;
      });
      _logPharmacy("INFO", credited ? "pharmacy_ledger_credited" : "pharmacy_ledger_credit_skipped_duplicate", {
        orderId, pharmacyId: after.pharmacyId, amount: after.totalAmount ?? 0,
      });
    }

    if (mirrorError) throw mirrorError;
  }
);

// ── 4) Stale pending-order cleanup ───────────────────────────────────────────
exports.cleanupStalePharmacyOrders = onSchedule({ schedule: "every 60 minutes", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromDate(new Date(Date.now() - _PHARMACY_STALE_PENDING_HOURS * 60 * 60 * 1000));

  const staleSnap = await db.collection("pharmacy_orders")
    .where("status", "==", "pending")
    .where("createdAt", "<", cutoff)
    .limit(200)
    .get();

  if (staleSnap.empty) {
    _logPharmacy("INFO", "stale_cleanup_none_found");
    return;
  }

  const { updated, skipped } = await _expireStaleDocs(staleSnap.docs, { status: "cancelled", updatedAt: FieldValue.serverTimestamp() });
  _logPharmacy("INFO", "stale_cleanup_cancelled", { count: updated, skippedConcurrentlyModified: skipped });
});

// Mirrors PharmacyOrderService._ownInventoryDeltas (Dart) — resolves each
// pharmacy_order_items line back to that pharmacy's own inventory doc
// (`phinv_{pharmacyId}_{itemId}`), so this and the app's own
// accept/cancel/reject stock transactions stay reading the same shape.
async function _ownPharmacyInventoryDeltas(db, orderId, pharmacyId) {
  const itemsSnap = await db.collection("pharmacy_order_items").where("orderId", "==", orderId).get();
  const prefix = `phinv_${pharmacyId}_`;
  const byRefPath = new Map();
  for (const doc of itemsSnap.docs) {
    const medicineId = doc.get("medicineId");
    if (!medicineId || !medicineId.startsWith(prefix)) continue;
    const itemId = medicineId.slice(prefix.length);
    const ref = db.collection("pharmacy_profiles").doc(pharmacyId).collection("inventory").doc(itemId);
    byRefPath.set(ref.path, { ref, delta: (byRefPath.get(ref.path)?.delta || 0) + (Number(doc.get("count")) || 1) });
  }
  return [...byRefPath.values()];
}

// ── 4b) Stale prescription-required cleanup ─────────────────────────────────
// acceptOrder (pharmacy_order_service.dart) decrements stock the moment an
// order moves pending -> prescription_required — but until now nothing ever
// timed that state out. If the patient never uploads (or the pharmacy never
// acts on) the prescription, the order sat open forever with its stock
// permanently locked. Same 24h window as every other stale-pending sweep in
// this file; restores stock in the same transaction as the cancel so a
// crash mid-run can't credit stock without also cancelling (or vice versa).
exports.cleanupStalePharmacyPrescriptionOrders = onSchedule({ schedule: "every 60 minutes", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromDate(new Date(Date.now() - _PHARMACY_STALE_PENDING_HOURS * 60 * 60 * 1000));

  const staleSnap = await db.collection("pharmacy_orders")
    .where("status", "==", "prescription_required")
    .where("createdAt", "<", cutoff)
    .limit(200)
    .get();

  if (staleSnap.empty) {
    _logPharmacy("INFO", "stale_prescription_cleanup_none_found");
    return;
  }

  let updated = 0;
  let skipped = 0;
  for (const doc of staleSnap.docs) {
    const pharmacyId = doc.get("pharmacyId");
    try {
      const deltas = pharmacyId ? await _ownPharmacyInventoryDeltas(db, doc.id, pharmacyId) : [];
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        if (!snap.exists || snap.get("status") !== "prescription_required") {
          throw new Error("CONCURRENTLY_MODIFIED");
        }
        for (const { ref, delta } of deltas) {
          tx.set(ref, { stock: FieldValue.increment(delta) }, { merge: true });
        }
        tx.update(doc.ref, {
          status: "cancelled",
          prescriptionVerified: false,
          prescriptionRejectedReason: "No prescription was uploaded in time, so this order was automatically cancelled.",
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
      updated++;
    } catch (err) {
      skipped++;
      if (err.message !== "CONCURRENTLY_MODIFIED") {
        _logPharmacy("ERROR", "stale_prescription_cleanup_failed", { orderId: doc.id, error: err.message });
      }
    }
  }
  _logPharmacy("INFO", "stale_prescription_cleanup_cancelled", { count: updated, skippedConcurrentlyModified: skipped });
});

// ── 5) Mirror a pharmacy's own inventory into the patient-facing catalogue ──
//
// `pharmacy_profiles/{pharmacyId}/inventory` is a pharmacy's private stock
// list (firestore.rules: owner-only read/write — patients were never meant
// to query it directly). `medicines_catalogue` is the one collection MedNu
// Patient's Medicine Delivery screen actually reads (admin-managed, public
// read). Nothing ever wrote from one into the other, so an item a pharmacy
// added to its own inventory never appeared to patients. This mirrors every
// inventory write onto a deterministic `medicines_catalogue` doc
// (`phinv_{pharmacyId}_{itemId}`), the same "same-shape deterministic
// mirror" pattern used for pharmacy_orders above, so patients see it via
// their existing live `.snapshots()` listener within moments of it being
// saved — no patient-app changes needed.
//
// Only mirrors while the owning pharmacy is `status == 'active'` (the same
// bar patients already need to read that pharmacy's own profile), and hides
// the item (`isActive: false`) once stock hits zero — both re-evaluated on
// every write, so restocking or a pharmacy going inactive is reflected just
// as promptly.
function _pharmacyInventoryCatalogueRef(db, pharmacyId, itemId) {
  return db.collection("medicines_catalogue").doc(`phinv_${pharmacyId}_${itemId}`);
}

function _pharmacyInventoryCatalogueDoc(item, pharmacyId, itemId, pharmacyName) {
  return {
    name: item.name || "",
    brand: item.brand || "",
    price: item.price ?? 0,
    mrp: item.price ?? 0,
    qty: 1,
    unit: "Tablets",
    requiresPrescription: item.requiresPrescription === true,
    // Blocked wins over stock: a pharmacy pulling an item (recall, temporary
    // stop-sell) must hide it from patients even if `stock` is still > 0,
    // without losing the stock count itself.
    isActive: (item.stock ?? 0) > 0 && item.blocked !== true,
    sourcePharmacyId: pharmacyId,
    sourceItemId: itemId,
    pharmacyName: pharmacyName || "",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

exports.onPharmacyInventoryWrite = onDocumentWritten(
  "pharmacy_profiles/{pharmacyId}/inventory/{itemId}",
  async (event) => {
    const { pharmacyId, itemId } = event.params;
    const db = getFirestore();
    const catalogueRef = _pharmacyInventoryCatalogueRef(db, pharmacyId, itemId);

    const after = event.data.after;
    if (!after.exists) {
      await catalogueRef.delete().catch(() => {});
      _logPharmacy("INFO", "inventory_mirror_deleted", { pharmacyId, itemId });
      return;
    }

    const pharmacySnap = await db.collection("pharmacy_profiles").doc(pharmacyId).get();
    const pharmacyData = pharmacySnap.exists ? pharmacySnap.data() : null;

    if (!pharmacyData || pharmacyData.status !== "active") {
      // Pending/suspended pharmacies keep their private inventory but stay
      // out of the patient catalogue until (re)approved — the status-change
      // sweep below catches every existing item on that transition.
      await catalogueRef.delete().catch(() => {});
      return;
    }

    const item = after.data();
    await catalogueRef.set(
      _pharmacyInventoryCatalogueDoc(item, pharmacyId, itemId, pharmacyData.name),
      { merge: true },
    );
    _logPharmacy("INFO", "inventory_mirror_synced", { pharmacyId, itemId, isActive: (item.stock ?? 0) > 0 });
  }
);

// When a pharmacy's verification status flips, sweep every inventory item it
// already has in/out of the patient catalogue — otherwise an item added
// while `pending` (or hidden after being `suspended`) would only reappear
// the next time the pharmacist happened to edit that specific item again.
exports.onPharmacyProfileStatusChangeForInventory = onDocumentUpdated(
  "pharmacy_profiles/{pharmacyId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status) return;

    const pharmacyId = event.params.pharmacyId;
    const db = getFirestore();
    const becameActive = after.status === "active";

    const inventorySnap = await db
      .collection("pharmacy_profiles").doc(pharmacyId).collection("inventory")
      .get();
    if (inventorySnap.empty) return;

    const batchSize = 400; // Firestore batch write limit is 500.
    for (let i = 0; i < inventorySnap.docs.length; i += batchSize) {
      const batch = db.batch();
      for (const doc of inventorySnap.docs.slice(i, i + batchSize)) {
        const ref = _pharmacyInventoryCatalogueRef(db, pharmacyId, doc.id);
        if (becameActive) {
          batch.set(ref, _pharmacyInventoryCatalogueDoc(doc.data(), pharmacyId, doc.id, after.name), { merge: true });
        } else {
          batch.delete(ref);
        }
      }
      await batch.commit();
    }
    _logPharmacy("INFO", becameActive ? "inventory_bulk_synced" : "inventory_bulk_hidden", {
      pharmacyId, count: inventorySnap.size,
    });
  }
);

// ══════════════════════════════════════════════════════════════════════════
// ── Ambulance partner module ────────────────────────────────────────────────
//
// Same "Cloud Function mirror" shape as Lab and Pharmacy above: the partner
// client never writes `service_requests` itself, it only ever writes the
// additive `ambulance_requests` collection, and these triggers are the sole
// writer that carries status in both directions.
//
//   service_requests[type='ambulance'] create -> ambulance_requests (create)
//   ambulance_requests (partner updates)      -> service_requests (status)
//                                             -> ambulance_trips (once, on completed)
//                                             -> ambulance_transactions (once, on completed)
//
// The doc ID of an ambulance_requests doc is always the source
// service_requests doc ID (deterministic mirror, exactly like
// diagnostic_bookings), which is what makes every write here retry-safe.
// ══════════════════════════════════════════════════════════════════════════

// An unclaimed ambulance request is an *emergency* — leaving one sitting in
// the "available" queue for a full day (Lab/Pharmacy's 24h) would be absurd,
// so this module gets its own, much shorter constant.
const _AMBULANCE_STALE_PENDING_HOURS = 2;

// Ambulance-side status -> the `ambulance` block of
// onServiceRequestStatusChange's statusMap, which is already fully wired
// with real patient notification copy (accepted/assigned/in_progress/
// arrived/completed/rejected/cancelled). No new keys are needed there.
// 'cancelled' is deliberately absent from this map: whether it means
// "rejected while unclaimed" or "cancelled after acceptance" depends on the
// status it came *from*, so it is resolved per-event below rather than by a
// flat lookup.
const _AMBULANCE_TO_SERVICE_REQUEST_STATUS = {
  accepted:  "accepted",
  enRoute:   "in_progress",
  arrived:   "arrived",
  completed: "completed",
};

// Free-text ambulance type from the patient app's serviceDetails ->
// the exact EmergencyType enum vocabulary the partner app's Dart model
// parses (cardiac/accident/maternity/general). Anything unrecognised falls
// back to 'general' rather than producing a value the client can't parse.
function _ambulanceEmergencyType(raw) {
  const s = String(raw || "").toLowerCase();
  if (s.includes("cardiac") || s.includes("heart") || s.includes("icu")) return "cardiac";
  if (s.includes("accident") || s.includes("trauma") || s.includes("injury")) return "accident";
  if (s.includes("maternity") || s.includes("pregnan") || s.includes("delivery")) return "maternity";
  return "general";
}

function _logAmbulance(severity, event, data = {}) {
  const payload = { severity, module: "ambulance", event, ...data };
  if (severity === "ERROR" || severity === "WARNING") {
    console.error(JSON.stringify(payload));
  } else {
    console.log(JSON.stringify(payload));
  }
}

// Great-circle distance in km — used to pick the nearest online ambulance to
// a pickup point. Deliberately not a Firestore geo-range query: the online
// set is small enough (real-world concurrent online ambulances per city) that
// fetching it and comparing in-process is simpler and avoids maintaining a
// geohash index just for this.
function _haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// An ambulance beyond this is not a real candidate to dispatch, no matter how
// few are online — better to fall into the open pool (any active partner can
// still claim it, e.g. one that just went online without a location fix yet)
// than to auto-assign a unit 80 km away from a genuine emergency.
const _AMBULANCE_MAX_MATCH_RADIUS_KM = 25;

// Finds the nearest online, active ambulance to (lat, lng), or null if none
// is online/located/within radius. `excludeIds` lets the stale-assignment
// reassignment sweep below skip a driver who already timed out on this
// request once.
async function _findNearestOnlineAmbulance(db, lat, lng, excludeIds = []) {
  if (typeof lat !== "number" || typeof lng !== "number") return null;

  const snap = await db.collection("ambulance_profiles")
    .where("status", "==", "active")
    .where("isOnline", "==", true)
    .limit(200) // bounded — see comment on _haversineKm above.
    .get();

  let best = null;
  let bestDistance = Infinity;
  for (const doc of snap.docs) {
    if (excludeIds.includes(doc.id)) continue;
    const loc = doc.data().location; // GeoPoint, written by AmbulanceLocationService
    if (!loc) continue;
    const distance = _haversineKm(lat, lng, loc.latitude, loc.longitude);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = doc.id;
    }
  }
  return bestDistance <= _AMBULANCE_MAX_MATCH_RADIUS_KM ? best : null;
}

// ── 1) Mirror new ambulance service_requests into ambulance_requests ────────
exports.onAmbulanceServiceRequestCreated = onDocumentCreated(
  "service_requests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (data.type !== "ambulance") return;

    const db = getFirestore();
    const requestId = event.params.requestId;
    const details = data.serviceDetails || {};
    const requestRef = db.collection("ambulance_requests").doc(requestId);

    // Idempotency guard (same reasoning as onDiagnosticServiceRequestCreated):
    // at-least-once delivery can redeliver this event, and skipping outright
    // once the mirror exists avoids bumping `updatedAt` and re-triggering the
    // partner app's realtime listeners on a pure retry.
    const existing = await requestRef.get();
    if (existing.exists) {
      _logAmbulance("INFO", "service_request_create_skipped_existing", { requestId });
      return;
    }

    // Nearest-driver matching: the patient's pickup fix (see PreciseAddress.
    // toBookingMap() in the Flutter app) travels through as
    // serviceDetails.locationData.{lat,lng}. Pin the request straight to the
    // nearest online ambulance instead of dropping it in the open pool — a
    // stale-assignment sweep (reassignStaleAmbulanceAssignments) un-pins it
    // back to the pool if that driver doesn't respond in time.
    const pickupLat = details.locationData?.lat;
    const pickupLng = details.locationData?.lng;
    const matchedAmbulanceId = await _findNearestOnlineAmbulance(db, pickupLat, pickupLng);

    await requestRef.set({
      sourceRequestId: requestId,
      type: "ambulance",
      status: "pending",
      patientId: data.patientId,
      patientName: data.patientName || "Patient",
      patientPhone: data.patientPhone || "",
      pickupAddress: data.address || "",
      pickupLat: pickupLat ?? null,
      pickupLng: pickupLng ?? null,
      dropAddress: details.dropAddress || "",
      distanceKm: details.distanceKm ?? 0,
      etaMinutes: details.etaMinutes ?? 0,
      fare: data.amount ?? details.fare ?? 0,
      emergencyType: _ambulanceEmergencyType(details.ambulanceType),
      ambulanceId: matchedAmbulanceId,
      matchAttempts: matchedAmbulanceId ? [matchedAmbulanceId] : [],
      requestedAt: data.createdAt || FieldValue.serverTimestamp(),
      createdAt: data.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    // `onAmbulanceRequestStatusChange` (the onDocumentUpdated mirror below)
    // is what normally copies `ambulanceId` onto `service_requests` as
    // `assignedTo` — but it only fires on later UPDATES to `ambulance_requests`,
    // never on this initial create. Without this, a request matched here
    // would never expose which ambulance to live-track until some later
    // event (e.g. a stale reassignment) happened to touch `ambulanceId`
    // again. Mirrored directly here instead so the patient app can find the
    // right `ambulance_profiles/{assignedTo}` doc to stream from the moment
    // the match happens, not only after the driver accepts.
    if (matchedAmbulanceId) {
      await db.collection("service_requests").doc(requestId).update({
        assignedTo: matchedAmbulanceId,
      }).catch((err) => {
        _logAmbulance("WARNING", "initial_assignedTo_mirror_failed", { requestId, error: err.message });
      });
    }

    _logAmbulance("INFO", "ambulance_request_created", { requestId, matchedAmbulanceId });

    // Ambulance is always pinned to exactly one nearest driver, never
    // broadcast to the whole pool — a driver who wasn't matched has no way
    // to claim this request anyway, so notifying them would just be noise
    // (and would misrepresent an already-assigned job as open).
    if (matchedAmbulanceId) {
      await _sendProviderNotification(db, getMessaging(), matchedAmbulanceId, {
        title: "🚑 New Ambulance Request",
        body: "A new ambulance request needs your response now.",
        type: "new_ambulance_request", serviceType: "ambulance", bookingId: requestId,
      });
    }
  }
);

// ── 1b) Reassign a matched-but-unanswered request ────────────────────────────
// A request pinned to the nearest driver above still needs that driver to
// actually tap Accept. If they don't within the timeout — asleep, busy,
// phone face-down — the patient must not be stuck waiting on one driver
// forever. Runs every minute (an emergency queue can't wait an hour like
// Lab/Pharmacy's stale cleanup does): tries the next-nearest online driver,
// excluding everyone already tried on this request, and only falls back to
// the fully-open pool once no more online candidates exist.
const _AMBULANCE_MATCH_TIMEOUT_SECONDS = 45;

exports.reassignStaleAmbulanceAssignments = onSchedule(
  { schedule: "every 1 minutes", timeZone: "UTC" },
  async () => {
    const db = getFirestore();
    const cutoff = Timestamp.fromDate(new Date(Date.now() - _AMBULANCE_MATCH_TIMEOUT_SECONDS * 1000));

    // Single-field equality filter only (auto-indexed by Firestore) — the
    // `ambulanceId != null` and staleness checks happen in-process below,
    // deliberately avoiding a `!=` query, which would need its own composite
    // index and has awkward interactions with the other filters here.
    const pendingSnap = await db.collection("ambulance_requests")
      .where("status", "==", "pending")
      .limit(200)
      .get();

    if (pendingSnap.empty) return;

    let reassigned = 0;
    let openedToPool = 0;
    let skipped = 0;

    for (const doc of pendingSnap.docs) {
      const data = doc.data();
      if (!data.ambulanceId) continue; // already open-pool — nothing to reassign.
      const updatedAt = data.updatedAt?.toDate?.() ?? data.createdAt?.toDate?.() ?? new Date(0);
      if (updatedAt > cutoff.toDate()) continue; // matched recently — not stale yet.

      const tried = Array.isArray(data.matchAttempts) ? data.matchAttempts : [];
      const next = await _findNearestOnlineAmbulance(db, data.pickupLat, data.pickupLng, tried);

      try {
        await doc.ref.update(
          {
            ambulanceId: next,
            matchAttempts: next ? [...tried, next] : tried,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { lastUpdateTime: doc.updateTime }, // same lost-update guard as _expireStaleDocs.
        );
        if (next) {
          reassigned++;
          // Same reasoning as the initial-match push above — the previous
          // driver already timed out, so only the newly-matched one needs
          // to hear about it now.
          await _sendProviderNotification(db, getMessaging(), next, {
            title: "🚑 New Ambulance Request",
            body: "A new ambulance request needs your response now.",
            type: "new_ambulance_request", serviceType: "ambulance", bookingId: doc.id,
          });
        } else {
          openedToPool++;
        }
      } catch {
        skipped++; // driver acted on it between the query and this write — leave it alone.
      }
    }

    _logAmbulance("INFO", "stale_assignment_sweep", { reassigned, openedToPool, skippedConcurrentlyModified: skipped });
  }
);

// ── 2) Mirror a patient-initiated cancellation onto ambulance_requests ──────
exports.onAmbulanceServiceRequestCancelled = onDocumentUpdated(
  "service_requests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (after.type !== "ambulance") return;
    if (before.status === after.status) return;
    if (after.status !== "cancelled") return;

    const db = getFirestore();
    const requestId = event.params.requestId;
    const requestRef = db.collection("ambulance_requests").doc(requestId);

    // Re-reading the *current* stored status inside a transaction (rather
    // than trusting this event's before/after) is what makes repeated
    // invocations converge safely — same pattern as the Lab mirror.
    await db.runTransaction(async (tx) => {
      const reqSnap = await tx.get(requestRef);
      if (!reqSnap.exists) return;
      const currentStatus = reqSnap.data().status;
      if (["completed", "cancelled"].includes(currentStatus)) {
        _logAmbulance("INFO", "cancel_mirror_skipped_terminal", { requestId, currentStatus });
        return;
      }
      tx.update(requestRef, { status: "cancelled", updatedAt: FieldValue.serverTimestamp() });
    });
    _logAmbulance("INFO", "ambulance_request_cancelled_by_patient", { requestId });
  }
);

// ── 3) Mirror ambulance-side updates back onto service_requests ─────────────
// Also writes the immutable ambulance_trips record and the
// ambulance_transactions ledger entry exactly once, on the ->completed edge.
// Both use a deterministic doc ID (== requestId) inside a transaction, so a
// redelivered event can never double-write a trip or double-credit earnings.
exports.onAmbulanceRequestStatusChange = onDocumentUpdated(
  "ambulance_requests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    const requestId = event.params.requestId;
    const db = getFirestore();

    const statusChanged = before.status !== after.status;
    const claimChanged = before.ambulanceId !== after.ambulanceId;

    // Remembered and rethrown at the end (see the Lab mirror) so a mirror
    // failure never skips the trip/ledger write below, while still failing
    // the invocation instead of silently reporting success.
    let mirrorError = null;

    if (statusChanged || claimChanged) {
      const update = { updatedAt: FieldValue.serverTimestamp() };

      let mappedStatus = _AMBULANCE_TO_SERVICE_REQUEST_STATUS[after.status];
      // A 'cancelled' ambulance_request means two different things to the
      // patient depending on where it came from: declining a request nobody
      // had claimed yet is a *rejection* (we could not fulfil this),
      // whereas cancelling one already accepted is a *cancellation*. The
      // existing `ambulance` statusMap already has distinct copy for both.
      if (statusChanged && after.status === "cancelled") {
        mappedStatus = before.status === "pending" ? "rejected" : "cancelled";
      }
      if (statusChanged && mappedStatus) update.status = mappedStatus;
      if (claimChanged && after.ambulanceId) update.assignedTo = after.ambulanceId;

      if (Object.keys(update).length > 1) {
        const serviceRequestRef = db.collection("service_requests").doc(after.sourceRequestId || requestId);
        // Skip the write entirely if everything we'd set already matches —
        // a redelivered event becomes a no-op read instead of a redundant
        // write (and a redundant duplicate patient notification).
        const current = await serviceRequestRef.get();
        const currentData = current.exists ? current.data() : null;
        const alreadyApplied = !!currentData &&
          (!update.status || currentData.status === update.status) &&
          (!update.assignedTo || currentData.assignedTo === update.assignedTo);

        if (!currentData) {
          _logAmbulance("WARNING", "mirror_target_missing", { requestId });
        } else if (alreadyApplied) {
          _logAmbulance("INFO", "mirror_skipped_already_applied", { requestId });
        } else {
          await serviceRequestRef.update(update).then(
            () => _logAmbulance("INFO", "mirrored_to_service_request", { requestId, fields: Object.keys(update) }),
            (err) => {
              _logAmbulance("ERROR", "mirror_to_service_request_failed", { requestId, error: err.message });
              mirrorError = err;
            },
          );
        }
      }
    }

    // ── Completion: trip record + ledger credit, both exactly once ─────────
    if (statusChanged && after.status === "completed" && before.status !== "completed" && after.ambulanceId) {
      const tripRef   = db.collection("ambulance_trips").doc(requestId);
      const ledgerRef = db.collection("ambulance_transactions").doc(requestId);

      // Trip duration is measured from when the patient actually requested
      // the ambulance to the moment it was marked complete — the number the
      // partner (and any later audit) cares about is real elapsed service
      // time, not time-since-acceptance.
      const requestedAt = after.requestedAt?.toDate?.() || after.createdAt?.toDate?.() || new Date();
      const durationMinutes = Math.max(0, Math.round((Date.now() - requestedAt.getTime()) / 60000));
      const fare = after.fare ?? 0;

      const written = await db.runTransaction(async (tx) => {
        const existingTrip = await tx.get(tripRef);
        const existingTx   = await tx.get(ledgerRef);
        if (existingTrip.exists && existingTx.exists) return false;

        if (!existingTrip.exists) {
          tx.set(tripRef, {
            id: requestId,
            ambulanceId: after.ambulanceId,
            type: after.emergencyType || "general",
            patientName: after.patientName || "Patient",
            pickupAddress: after.pickupAddress || "",
            dropAddress: after.dropAddress || "",
            distanceKm: after.distanceKm ?? 0,
            durationMinutes,
            fare,
            rating: null,
            completedAt: FieldValue.serverTimestamp(),
          });
        }
        if (!existingTx.exists) {
          tx.set(ledgerRef, {
            ambulanceId: after.ambulanceId,
            requestId,
            type: "earning",
            amount: fare,
            status: "credited",
            patientName: after.patientName || "Patient",
            createdAt: FieldValue.serverTimestamp(),
          });
        }
        return true;
      });

      _logAmbulance("INFO", written ? "ambulance_trip_and_ledger_written" : "ambulance_completion_skipped_duplicate", {
        requestId, ambulanceId: after.ambulanceId, amount: fare, durationMinutes,
      });

      await _transitionPaymentToEligible(db, {
        sourceCollection: "service_requests",
        sourceId: after.sourceRequestId || requestId,
        providerId: after.ambulanceId,
        serviceType: "ambulance",
      });
    }

    if (mirrorError) throw mirrorError;
  }
);

// ── 4) Stale pending-request cleanup ────────────────────────────────────────
// Runs hourly. Anything still unclaimed after _AMBULANCE_STALE_PENDING_HOURS
// is cancelled here; trigger #3 above then mirrors that onto
// service_requests as 'rejected' (it came from 'pending'), so no mirroring
// logic is duplicated in this function.
exports.cleanupStaleAmbulanceRequests = onSchedule({ schedule: "every 60 minutes", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromDate(new Date(Date.now() - _AMBULANCE_STALE_PENDING_HOURS * 60 * 60 * 1000));

  const staleSnap = await db.collection("ambulance_requests")
    .where("status", "==", "pending")
    .where("createdAt", "<", cutoff)
    .limit(200) // bounded per run; the next hourly run picks up any remainder.
    .get();

  if (staleSnap.empty) {
    _logAmbulance("INFO", "stale_cleanup_none_found");
    return;
  }

  const { updated, skipped } = await _expireStaleDocs(staleSnap.docs, { status: "cancelled", updatedAt: FieldValue.serverTimestamp() });
  _logAmbulance("INFO", "stale_cleanup_cancelled", { count: updated, skippedConcurrentlyModified: skipped });
});

// ══════════════════════════════════════════════════════════════════════════
// ── Caregiver partner module ────────────────────────────────────────────────
//
// Same mirror shape again, with one wrinkle: the patient app has no single
// "caregiver" service type. Caregiver-shaped bookings reach
// `service_requests` through the CART checkout path
// (mednu/lib/features/cart/screens/cart_screen.dart), which forwards each
// non-medicine cart item's own type straight into
// BookingService.createRequest — producing TWO live values:
// 'care_assistant' and 'caregivers' (plural). The dormant 'home_care' type
// in onServiceRequestStatusChange's statusMap is scaffolding only; nothing
// in the patient app ever writes it, so mirroring from it would receive
// zero real bookings (same trap as Lab's unused `lab_bookings`).
//
//   service_requests[care_assistant|caregivers] create
//                                     -> caregiver_visits (create)
//                                     -> caregiver_visits/{id}/tasks (4 defaults)
//   caregiver_visits (partner updates) -> service_requests (status/assignedTo)
//                                     -> caregiver_transactions (once, completed)
//
// Tasks and notes live as subcollections of the visit rather than as
// top-level collections: they are naturally visit-scoped, which keeps their
// ownership rules a single parent lookup and avoids a fan-out collection
// that would need its own visitId index.
// ══════════════════════════════════════════════════════════════════════════

const _CAREGIVER_TYPES = ["care_assistant", "caregivers"];

const _CAREGIVER_STALE_PENDING_HOURS = 24;

// Caregiver-side status -> the existing `caregiver`/`care_assistant`/
// `caregivers` statusMap blocks in onServiceRequestStatusChange. A visit the
// caregiver never showed up for ('missed') reads to the patient exactly like
// a cancellation — there is no separate patient-facing copy for it, and
// inventing one would mean touching the shared statusMap's existing entries.
const _CAREGIVER_TO_SERVICE_REQUEST_STATUS = {
  checkedIn: "in_progress",
  completed: "completed",
  cancelled: "cancelled",
  missed:    "cancelled",
};

// The 4 generic checklist items every mirrored visit starts with. Kept
// deliberately generic (the patient booking carries no per-visit task list),
// matching the shape MockCaregiverRepository seeded.
const _CAREGIVER_DEFAULT_TASKS = [
  { title: "Check vitals",           subtitle: "Blood pressure, pulse and temperature" },
  { title: "Assist with medication", subtitle: "Confirm dosage and timing" },
  { title: "Mobility support",       subtitle: "Assisted movement or light exercises" },
  { title: "Update care log",        subtitle: "Record observations for the family" },
];

// Free-text specialty/shift text from the patient app's serviceDetails ->
// the exact CareType enum vocabulary the partner app's Dart model parses.
function _caregiverCareType(raw) {
  const s = String(raw || "").toLowerCase();
  if (s.includes("elder") || s.includes("senior") || s.includes("geriatric")) return "elderlyCare";
  if (s.includes("surgery") || s.includes("post-op") || s.includes("postop")) return "postSurgery";
  if (s.includes("physio") || s.includes("rehab")) return "physiotherapy";
  if (s.includes("medicat") || s.includes("pharma")) return "medicationManagement";
  return "generalNursing";
}

// preferredDate ('yyyy-MM-dd') + preferredTime ('HH:mm' or '10:00 AM') as
// written by BookingService.createRequest. Anything unparseable falls back
// to the booking's own createdAt rather than throwing — a visit with a
// slightly wrong scheduled time is far better than a visit that never
// mirrors at all.
function _caregiverScheduledAt(data) {
  const date = String(data.preferredDate || "").trim();
  const time = String(data.preferredTime || "").trim();
  if (date) {
    const parsed = new Date(time ? `${date} ${time}` : date);
    if (!isNaN(parsed.getTime())) return Timestamp.fromDate(parsed);
  }
  return data.createdAt || FieldValue.serverTimestamp();
}

function _logCaregiver(severity, event, data = {}) {
  const payload = { severity, module: "caregiver", event, ...data };
  if (severity === "ERROR" || severity === "WARNING") {
    console.error(JSON.stringify(payload));
  } else {
    console.log(JSON.stringify(payload));
  }
}

// ── 1) Mirror new caregiver service_requests into caregiver_visits ─────────
exports.onCaregiverServiceRequestCreated = onDocumentCreated(
  "service_requests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (!_CAREGIVER_TYPES.includes(data.type)) return;

    const db = getFirestore();
    const requestId = event.params.requestId;
    const details = data.serviceDetails || {};
    const visitRef = db.collection("caregiver_visits").doc(requestId);

    const existing = await visitRef.get();
    if (existing.exists) {
      _logCaregiver("INFO", "service_request_create_skipped_existing", { requestId });
      return;
    }

    const shiftHours = Number(details.shiftHours);
    const durationMinutes = Number.isFinite(shiftHours) && shiftHours > 0
      ? Math.round(shiftHours * 60)
      : 60;

    // A visit booked from a specific caregiver's own profile card (see
    // caregivers_screen.dart's `sourceCaregiverId`) pins straight to them
    // instead of dropping into the unclaimed pool — same reasoning as Lab's
    // `sourceLabId` handling. Falls back to the pool if that caregiver is no
    // longer active by the time the patient checks out.
    let pinnedCaregiverId = null;
    if (details.sourceCaregiverId) {
      const caregiverSnap = await db.collection("caregiver_profiles").doc(details.sourceCaregiverId).get();
      if (caregiverSnap.exists && caregiverSnap.data().status === "active") {
        pinnedCaregiverId = details.sourceCaregiverId;
      } else {
        _logCaregiver("WARNING", "source_caregiver_inactive_falling_back_to_pool", {
          requestId, sourceCaregiverId: details.sourceCaregiverId,
        });
      }
    }

    const batch = db.batch();
    batch.set(visitRef, {
      sourceRequestId: requestId,
      sourceType: data.type,
      type: _caregiverCareType(details.specialty || details.shiftType || data.serviceName),
      status: "scheduled",
      patientId: data.patientId,
      patientName: data.patientName || "Patient",
      patientPhone: data.patientPhone || "",
      patientAge: 0,
      address: data.address || "",
      scheduledAt: _caregiverScheduledAt(data),
      durationMinutes,
      fare: data.amount ?? 0,
      photoUrls: [],
      caregiverId: pinnedCaregiverId,
      createdAt: data.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    // Seeded in the same batch as the visit itself, so a visit never exists
    // with a half-written checklist.
    _CAREGIVER_DEFAULT_TASKS.forEach((task, i) => {
      batch.set(visitRef.collection("tasks").doc(`t${i + 1}`), {
        title: task.title,
        subtitle: task.subtitle,
        isDone: false,
        order: i,
      });
    });

    await batch.commit();

    // Same gap as Ambulance's initial match: `onCaregiverVisitStatusChange`
    // (the onDocumentUpdated mirror below) only fires on later UPDATES to
    // caregiver_visits, never on this create — so a caregiver pinned here
    // would never show up as `assignedTo` on the patient's own
    // `service_requests` doc without this direct write.
    if (pinnedCaregiverId) {
      await db.collection("service_requests").doc(requestId).update({
        assignedTo: pinnedCaregiverId,
      }).catch((err) => {
        _logCaregiver("WARNING", "initial_assignedTo_mirror_failed", { requestId, error: err.message });
      });
    }

    _logCaregiver("INFO", "caregiver_visit_created", { requestId, sourceType: data.type });

    if (pinnedCaregiverId) {
      await _sendProviderNotification(db, getMessaging(), pinnedCaregiverId, {
        title: "New Visit Assigned",
        body: `A new ${data.serviceName || "caregiver"} visit has been assigned to you.`,
        type: "new_caregiver_visit", serviceType: "caregiver", bookingId: requestId,
      });
    } else {
      await _broadcastNewJobToActiveProviders(db, getMessaging(), {
        profileCollection: "caregiver_profiles",
        title: "New Visit Request Available",
        body: `A new ${data.serviceName || "caregiver"} visit request is available to claim.`,
        type: "new_caregiver_visit", serviceType: "caregiver", bookingId: requestId,
      });
    }
  }
);

// ── 2) Mirror a patient-initiated cancellation onto caregiver_visits ───────
exports.onCaregiverServiceRequestCancelled = onDocumentUpdated(
  "service_requests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (!_CAREGIVER_TYPES.includes(after.type)) return;
    if (before.status === after.status) return;
    if (after.status !== "cancelled") return;

    const db = getFirestore();
    const requestId = event.params.requestId;
    const visitRef = db.collection("caregiver_visits").doc(requestId);

    await db.runTransaction(async (tx) => {
      const visitSnap = await tx.get(visitRef);
      if (!visitSnap.exists) return;
      const currentStatus = visitSnap.data().status;
      if (["completed", "cancelled", "missed"].includes(currentStatus)) {
        _logCaregiver("INFO", "cancel_mirror_skipped_terminal", { requestId, currentStatus });
        return;
      }
      tx.update(visitRef, { status: "cancelled", updatedAt: FieldValue.serverTimestamp() });
    });
    _logCaregiver("INFO", "caregiver_visit_cancelled_by_patient", { requestId });
  }
);

// ── 3) Mirror caregiver-side visit updates back onto service_requests ──────
// Also credits the immutable caregiver_transactions ledger exactly once, on
// the ->completed edge (deterministic ID + transactional existence check,
// same double-credit proofing as lab_transactions/pharmacy_transactions).
exports.onCaregiverVisitStatusChange = onDocumentUpdated(
  "caregiver_visits/{visitId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    const visitId = event.params.visitId;
    const db = getFirestore();

    const statusChanged = before.status !== after.status;
    const claimChanged = before.caregiverId !== after.caregiverId;

    // Remembered and rethrown at the end (see the Lab mirror) so a mirror
    // failure never skips the ledger credit below.
    let mirrorError = null;

    if (statusChanged || claimChanged) {
      const update = { updatedAt: FieldValue.serverTimestamp() };

      const mappedStatus = _CAREGIVER_TO_SERVICE_REQUEST_STATUS[after.status];
      if (statusChanged && mappedStatus) update.status = mappedStatus;
      if (claimChanged && after.caregiverId) update.assignedTo = after.caregiverId;

      if (Object.keys(update).length > 1) {
        const serviceRequestRef = db.collection("service_requests").doc(after.sourceRequestId || visitId);
        const current = await serviceRequestRef.get();
        const currentData = current.exists ? current.data() : null;

        // Claiming a visit doesn't change its own status (a claimed visit is
        // still 'scheduled' until check-in), but the patient should still see
        // it move from 'pending' to 'accepted' with a caregiver attached.
        // Gated on the *current* patient-side status: a re-assignment after
        // check-in must never drag 'in_progress' backwards to 'accepted'.
        if (update.assignedTo && !update.status && currentData?.status === "pending") {
          update.status = "accepted";
        }

        const alreadyApplied = !!currentData &&
          (!update.status || currentData.status === update.status) &&
          (!update.assignedTo || currentData.assignedTo === update.assignedTo);

        if (!currentData) {
          _logCaregiver("WARNING", "mirror_target_missing", { visitId });
        } else if (alreadyApplied) {
          _logCaregiver("INFO", "mirror_skipped_already_applied", { visitId });
        } else {
          await serviceRequestRef.update(update).then(
            () => _logCaregiver("INFO", "mirrored_to_service_request", { visitId, fields: Object.keys(update) }),
            (err) => {
              _logCaregiver("ERROR", "mirror_to_service_request_failed", { visitId, error: err.message });
              mirrorError = err;
            },
          );
        }
      }
    }

    if (statusChanged && after.status === "completed" && before.status !== "completed" && after.caregiverId) {
      const ledgerRef = db.collection("caregiver_transactions").doc(visitId);
      const credited = await db.runTransaction(async (tx) => {
        const existingTx = await tx.get(ledgerRef);
        if (existingTx.exists) return false;
        tx.set(ledgerRef, {
          caregiverId: after.caregiverId,
          visitId,
          type: "earning",
          amount: after.fare ?? 0,
          status: "credited",
          patientName: after.patientName || "Patient",
          createdAt: FieldValue.serverTimestamp(),
        });
        return true;
      });
      _logCaregiver("INFO", credited ? "caregiver_ledger_credited" : "caregiver_ledger_credit_skipped_duplicate", {
        visitId, caregiverId: after.caregiverId, amount: after.fare ?? 0,
      });

      await _transitionPaymentToEligible(db, {
        sourceCollection: "service_requests",
        sourceId: after.sourceRequestId || visitId,
        providerId: after.caregiverId,
        serviceType: "caregiver",
      });
    }

    if (mirrorError) throw mirrorError;
  }
);

// ── 4) Stale scheduled-visit cleanup ───────────────────────────────────────
// A visit nobody ever checked into is a *missed* visit, not a cancelled one
// — the distinction matters for the caregiver-side history view. Trigger #3
// mirrors 'missed' onto service_requests as 'cancelled' (the patient has no
// separate "missed" concept), so no mirroring logic is duplicated here.
exports.cleanupStaleCaregiverVisits = onSchedule({ schedule: "every 60 minutes", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromDate(new Date(Date.now() - _CAREGIVER_STALE_PENDING_HOURS * 60 * 60 * 1000));

  const staleSnap = await db.collection("caregiver_visits")
    .where("status", "==", "scheduled")
    .where("createdAt", "<", cutoff)
    .limit(200)
    .get();

  if (staleSnap.empty) {
    _logCaregiver("INFO", "stale_cleanup_none_found");
    return;
  }

  const { updated, skipped } = await _expireStaleDocs(staleSnap.docs, { status: "missed", updatedAt: FieldValue.serverTimestamp() });
  _logCaregiver("INFO", "stale_cleanup_missed", { count: updated, skippedConcurrentlyModified: skipped });
});

// ── Profile visibility mirror ────────────────────────────────────────────────
// `caregivers_screen.dart` (mednu) browses a top-level `caregivers` collection
// that, before this, nothing ever wrote — approval only sent a push
// notification. Mirrors `caregiver_profiles/{uid}` into `caregivers/{uid}`
// (same doc id, 1:1 — no subcollection involved, unlike Lab/Pharmacy's
// per-item inventory) whenever it's active, so a real registered-and-approved
// caregiver actually shows up to patients, and disappears again if suspended.
//
// Field mapping is lossy in one direction: `caregiver_profiles` has no
// `gender`/`location` fields at all (never collected at registration), so
// those are left blank — the patient screen already renders gracefully
// without them, and nothing here fabricates a value data doesn't support.
// `type` (Nurse/Maid/...) is approximated from the first entry in
// `specialties` for the same reason — there's no dedicated role field.
function _caregiverListingDoc(profile, existingCreatedAt) {
  const specialties = Array.isArray(profile.specialties) ? profile.specialties : [];
  const hourlyRate = profile.hourlyRate ?? 0;
  return {
    name: profile.name || "Caregiver",
    photoUrl: profile.photoUrl || "",
    type: specialties.length > 0 ? specialties[0] : "Caregiver",
    specialty: specialties.length > 0 ? specialties.join(", ") : "Home Care",
    experience: `${profile.experienceYears ?? 0} yrs`,
    ratePerDay: Math.round(hourlyRate * 8),
    ratePerHour: hourlyRate,
    ratePer12Hr: Math.round(hourlyRate * 12),
    rating: profile.rating ?? 0,
    // Patient-side caregivers_screen.dart already reads `location` (a
    // pre-existing field name distinct from `city` used by the other
    // verticals) — matching it here rather than introducing a second name.
    location: profile.city || "",
    ...(profile.lat != null && profile.lng != null
      ? { lat: profile.lat, lng: profile.lng }
      : {}),
    isVerified: profile.documentsVerified === true,
    isActive: true,
    createdAt: existingCreatedAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

exports.onCaregiverProfileWriteForVisibility = onDocumentWritten(
  "caregiver_profiles/{caregiverId}",
  async (event) => {
    const caregiverId = event.params.caregiverId;
    const db = getFirestore();
    const listingRef = db.collection("caregivers").doc(caregiverId);

    const after = event.data.after;
    if (!after.exists) {
      await listingRef.delete().catch(() => {});
      _logCaregiver("INFO", "listing_mirror_deleted", { caregiverId });
      return;
    }

    const profile = after.data();
    if (profile.status !== "active") {
      // Pending/suspended caregivers stay out of the patient list until
      // (re)approved. `caregivers.isActive` is redundant with the doc simply
      // not existing, but keeping the field lets the patient query stay a
      // plain `where('isActive', '==', true)` if this ever needs to become a
      // sweep-based mirror (subcollection-style) instead of 1:1 later.
      await listingRef.delete().catch(() => {});
      return;
    }

    const existing = await listingRef.get();
    await listingRef.set(
      _caregiverListingDoc(profile, existing.exists ? existing.data().createdAt : null),
      { merge: true },
    );
    _logCaregiver("INFO", "listing_mirror_synced", { caregiverId });
  }
);

// ══════════════════════════════════════════════════════════════════════════
// ── Physiotherapy & Counselling modules ─────────────────────────────────────
//
// Same mirror shape as Lab/Ambulance/Caregiver above, once per module. Both
// service types reach `service_requests` through the CART checkout path
// (mednu/lib/features/cart/screens/cart_screen.dart -> BookingService.
// createRequest), with the literal `type` values 'physiotherapy' and
// 'counselling' — confirmed at mednu/lib/features/services/physiotherapy/
// physio_screen.dart and the shared ServiceBookingSheet's direct-book path.
// (Counselling's "Talk Now" / "Book a Therapist" entry points route into the
// existing doctor/consultation flow instead and are already tracked there —
// only bookings that actually land in `service_requests` need this mirror.)
//
// Each is a single-practitioner service (no separate "assign a staff member"
// step the way Lab/Pharmacy have), so claiming a session is a single step
// exactly like Ambulance: providerId moves from null to the caller AND
// status moves from 'pending' to 'accepted' (or 'cancelled', to decline) in
// the same write. 'rejected' stays defined in onServiceRequestStatusChange's
// notification maps but is unreachable here, same as Ambulance's own
// 'rejected' key today — declining an unclaimed session is expressed as a
// cancel, not a distinct status.
//
//   service_requests[physiotherapy] create -> physio_sessions (create)
//   service_requests[counselling]   create -> counselling_sessions (create)
//   service_requests  (patient cancels)    -> <module>_sessions (status only)
//   <module>_sessions (partner updates)    -> service_requests (status only)
//                                           -> <module>_transactions (once,
//                                              completed)
// ══════════════════════════════════════════════════════════════════════════

const _PHYSIO_STALE_PENDING_HOURS = 24;
const _COUNSELLING_STALE_PENDING_HOURS = 24;

// Provider-side status -> the exact service_requests status vocabulary
// already consumed by onServiceRequestStatusChange's `physiotherapy`/
// `counselling` maps (accepted, in_progress, completed, cancelled).
// 'expired' (see the stale-cleanup schedules below) reads to the patient
// exactly like a cancellation, same as every other module's stale cleanup.
const _PHYSIO_TO_SERVICE_REQUEST_STATUS = {
  accepted:    "accepted",
  in_progress: "in_progress",
  completed:   "completed",
  cancelled:   "cancelled",
  expired:     "cancelled",
};
const _COUNSELLING_TO_SERVICE_REQUEST_STATUS = { ..._PHYSIO_TO_SERVICE_REQUEST_STATUS };

function _logPhysio(severity, event, data = {}) {
  const payload = { severity, module: "physiotherapy", event, ...data };
  if (severity === "ERROR" || severity === "WARNING") console.error(JSON.stringify(payload));
  else console.log(JSON.stringify(payload));
}
function _logCounselling(severity, event, data = {}) {
  const payload = { severity, module: "counselling", event, ...data };
  if (severity === "ERROR" || severity === "WARNING") console.error(JSON.stringify(payload));
  else console.log(JSON.stringify(payload));
}

// `assignedTo` on service_requests has always been the provider's raw uid
// (a foreign key, not a display value) — every module's "My Services" view
// resolves it straight to the screen with no name lookup, so a patient sees
// a uid where a person's name belongs. This looks the name up once at
// mirror-write time and stores it alongside as `assignedToName`, rather than
// changing what `assignedTo` itself means (other code may still rely on it
// being a bare uid).
async function _providerDisplayName(db, profileCollection, id) {
  if (!id) return null;
  try {
    const snap = await db.collection(profileCollection).doc(id).get();
    return snap.exists ? (snap.data().name || null) : null;
  } catch (_) {
    return null;
  }
}

// Builds the mirrored session doc from a service_requests doc. Identical
// shape for both modules; only the provider-id field name differs, which the
// caller passes in.
//
// A patient booking a specific provider directly (e.g. from the
// "Physiotherapists Near You" list) sets `[providerIdField]` on the
// service_requests doc itself at creation — this mirror honors that instead
// of always dropping the request into the unclaimed pool, going straight to
// 'accepted' for that provider exactly as if they'd just claimed it
// themselves. A request with no pre-assigned provider behaves exactly as
// before: unclaimed and 'pending'.
function _buildSessionDoc(data, providerIdField) {
  const details = data.serviceDetails || {};
  const preAssignedProviderId = data[providerIdField] || null;
  return {
    sourceRequestId: null, // overwritten by the caller with the real requestId
    type: data.type,
    sessionTitle: details.title || details.sessionType || data.serviceName || "Session",
    price: details.price ?? data.amount ?? 0,
    amount: data.amount ?? details.price ?? 0,
    patientId: data.patientId,
    patientName: data.patientName || "Patient",
    patientPhone: data.patientPhone || "",
    address: data.address || "",
    preferredDate: data.preferredDate || "",
    preferredTime: data.preferredTime || "",
    notes: data.notes || "",
    [providerIdField]: preAssignedProviderId,
    status: preAssignedProviderId ? "accepted" : "pending",
    createdAt: data.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

// ── 1) Mirror new physiotherapy service_requests into physio_sessions ──────
exports.onPhysioServiceRequestCreated = onDocumentCreated(
  "service_requests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (data.type !== "physiotherapy") return;

    const db = getFirestore();
    const requestId = event.params.requestId;
    const sessionRef = db.collection("physio_sessions").doc(requestId);

    const existing = await sessionRef.get();
    if (existing.exists) {
      _logPhysio("INFO", "service_request_create_skipped_existing", { requestId });
      return;
    }

    const sessionDoc = {
      ..._buildSessionDoc(data, "physiotherapistId"),
      sourceRequestId: requestId,
    };
    await sessionRef.set(sessionDoc);

    // A pre-assigned booking (patient picked a specific physiotherapist
    // directly, rather than requesting any available one) is born already
    // 'accepted' — that transition happens entirely within this create, so
    // onPhysioSessionStatusChange (function 3 below, which only reacts to
    // *updates* on physio_sessions) never observes it. Mirror it back onto
    // the source service_requests doc here instead, so the patient's live
    // "My Services" view reflects the real status/assigned provider
    // immediately rather than staying stuck on 'pending' until some later
    // status change happens to fire an update.
    if (sessionDoc.physiotherapistId) {
      const providerName = await _providerDisplayName(db, "physiotherapist_profiles", sessionDoc.physiotherapistId);
      await snap.ref.update({
        status: "accepted",
        assignedTo: sessionDoc.physiotherapistId,
        ...(providerName ? { assignedToName: providerName } : {}),
        updatedAt: FieldValue.serverTimestamp(),
      }).catch((err) => {
        _logPhysio("ERROR", "preassigned_service_request_mirror_failed", { requestId, error: err.message });
      });

      await _sendProviderNotification(db, getMessaging(), sessionDoc.physiotherapistId, {
        title: "New Session Assigned",
        body: "A new physiotherapy session has been assigned to you.",
        type: "new_physio_session", serviceType: "physiotherapy", bookingId: requestId,
      });
    } else {
      await _broadcastNewJobToActiveProviders(db, getMessaging(), {
        profileCollection: "physiotherapist_profiles",
        title: "New Session Request Available",
        body: "A new physiotherapy session request is available to claim.",
        type: "new_physio_session", serviceType: "physiotherapy", bookingId: requestId,
      });
    }

    _logPhysio("INFO", "physio_session_created", { requestId });
  }
);

// ── 2) Mirror a patient-initiated cancellation onto physio_sessions ────────
exports.onPhysioServiceRequestCancelled = onDocumentUpdated(
  "service_requests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (after.type !== "physiotherapy") return;
    if (before.status === after.status) return;
    if (after.status !== "cancelled") return;

    const db = getFirestore();
    const requestId = event.params.requestId;
    const sessionRef = db.collection("physio_sessions").doc(requestId);

    await db.runTransaction(async (tx) => {
      const sessionSnap = await tx.get(sessionRef);
      if (!sessionSnap.exists) return;
      const currentStatus = sessionSnap.data().status;
      if (["completed", "cancelled", "expired"].includes(currentStatus)) {
        _logPhysio("INFO", "cancel_mirror_skipped_terminal", { requestId, currentStatus });
        return;
      }
      tx.update(sessionRef, { status: "cancelled", updatedAt: FieldValue.serverTimestamp() });
    });
    _logPhysio("INFO", "physio_session_cancelled_by_patient", { requestId });
  }
);

// ── 3) Mirror physiotherapist-side session updates back onto service_requests ──
// Also credits the immutable physio_transactions ledger exactly once, on the
// ->completed edge (deterministic ID + transactional existence check, same
// double-credit proofing as every other module's ledger).
exports.onPhysioSessionStatusChange = onDocumentUpdated(
  "physio_sessions/{sessionId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    const sessionId = event.params.sessionId;
    const db = getFirestore();

    const statusChanged = before.status !== after.status;
    const claimChanged = before.physiotherapistId !== after.physiotherapistId;

    let mirrorError = null;

    if (statusChanged || claimChanged) {
      const update = { updatedAt: FieldValue.serverTimestamp() };

      const mappedStatus = _PHYSIO_TO_SERVICE_REQUEST_STATUS[after.status];
      if (statusChanged && mappedStatus) update.status = mappedStatus;
      if (claimChanged && after.physiotherapistId) {
        update.assignedTo = after.physiotherapistId;
        const providerName = await _providerDisplayName(db, "physiotherapist_profiles", after.physiotherapistId);
        if (providerName) update.assignedToName = providerName;
      }

      if (Object.keys(update).length > 1) {
        const serviceRequestRef = db.collection("service_requests").doc(after.sourceRequestId || sessionId);
        const current = await serviceRequestRef.get();
        const currentData = current.exists ? current.data() : null;

        const alreadyApplied = !!currentData &&
          (!update.status || currentData.status === update.status) &&
          (!update.assignedTo || currentData.assignedTo === update.assignedTo);

        if (!currentData) {
          _logPhysio("WARNING", "mirror_target_missing", { sessionId });
        } else if (alreadyApplied) {
          _logPhysio("INFO", "mirror_skipped_already_applied", { sessionId });
        } else {
          await serviceRequestRef.update(update).then(
            () => _logPhysio("INFO", "mirrored_to_service_request", { sessionId, fields: Object.keys(update) }),
            (err) => {
              _logPhysio("ERROR", "mirror_to_service_request_failed", { sessionId, error: err.message });
              mirrorError = err;
            },
          );
        }
      }
    }

    if (statusChanged && after.status === "completed" && before.status !== "completed" && after.physiotherapistId) {
      const ledgerRef = db.collection("physio_transactions").doc(sessionId);
      const credited = await db.runTransaction(async (tx) => {
        const existingTx = await tx.get(ledgerRef);
        if (existingTx.exists) return false;
        tx.set(ledgerRef, {
          physiotherapistId: after.physiotherapistId,
          sessionId,
          type: "earning",
          amount: after.amount ?? 0,
          status: "credited",
          patientName: after.patientName || "Patient",
          createdAt: FieldValue.serverTimestamp(),
        });
        return true;
      });
      _logPhysio("INFO", credited ? "physio_ledger_credited" : "physio_ledger_credit_skipped_duplicate", {
        sessionId, physiotherapistId: after.physiotherapistId, amount: after.amount ?? 0,
      });

      await _transitionPaymentToEligible(db, {
        sourceCollection: "service_requests",
        sourceId: after.sourceRequestId || sessionId,
        providerId: after.physiotherapistId,
        serviceType: "physiotherapy",
      });
    }

    if (mirrorError) throw mirrorError;
  }
);

// ── 4) Stale pending-session cleanup ────────────────────────────────────────
exports.cleanupStalePhysioSessions = onSchedule({ schedule: "every 60 minutes", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromDate(new Date(Date.now() - _PHYSIO_STALE_PENDING_HOURS * 60 * 60 * 1000));

  const staleSnap = await db.collection("physio_sessions")
    .where("status", "==", "pending")
    .where("createdAt", "<", cutoff)
    .limit(200)
    .get();

  if (staleSnap.empty) {
    _logPhysio("INFO", "stale_cleanup_none_found");
    return;
  }

  const { updated, skipped } = await _expireStaleDocs(staleSnap.docs, { status: "expired", updatedAt: FieldValue.serverTimestamp() });
  _logPhysio("INFO", "stale_cleanup_expired", { count: updated, skippedConcurrentlyModified: skipped });
});

// ── 1) Mirror new counselling service_requests into counselling_sessions ───
exports.onCounsellingServiceRequestCreated = onDocumentCreated(
  "service_requests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (data.type !== "counselling") return;

    const db = getFirestore();
    const requestId = event.params.requestId;
    const sessionRef = db.collection("counselling_sessions").doc(requestId);

    const existing = await sessionRef.get();
    if (existing.exists) {
      _logCounselling("INFO", "service_request_create_skipped_existing", { requestId });
      return;
    }

    const sessionDoc = {
      ..._buildSessionDoc(data, "counsellorId"),
      sourceRequestId: requestId,
    };
    await sessionRef.set(sessionDoc);

    // Mirrors physiotherapy's equivalent block above: a pre-assigned booking
    // is born already 'accepted' by `_buildSessionDoc`, but that transition
    // happens entirely within this create, so `onCounsellingSessionStatusChange`
    // (which only reacts to *updates*) never observes it. Without this, the
    // patient's live "My Services" view stayed stuck on 'pending' for a
    // directly-booked counsellor until some later status change happened to
    // touch the doc — this case was previously handled for physio but missed
    // here.
    if (sessionDoc.counsellorId) {
      const providerName = await _providerDisplayName(db, "counsellor_profiles", sessionDoc.counsellorId);
      await snap.ref.update({
        status: "accepted",
        assignedTo: sessionDoc.counsellorId,
        ...(providerName ? { assignedToName: providerName } : {}),
        updatedAt: FieldValue.serverTimestamp(),
      }).catch((err) => {
        _logCounselling("ERROR", "preassigned_service_request_mirror_failed", { requestId, error: err.message });
      });

      await _sendProviderNotification(db, getMessaging(), sessionDoc.counsellorId, {
        title: "New Session Assigned",
        body: "A new counselling session has been assigned to you.",
        type: "new_counselling_session", serviceType: "counselling", bookingId: requestId,
      });
    } else {
      await _broadcastNewJobToActiveProviders(db, getMessaging(), {
        profileCollection: "counsellor_profiles",
        title: "New Session Request Available",
        body: "A new counselling session request is available to claim.",
        type: "new_counselling_session", serviceType: "counselling", bookingId: requestId,
      });
    }

    _logCounselling("INFO", "counselling_session_created", { requestId });
  }
);

// ── 2) Mirror a patient-initiated cancellation onto counselling_sessions ───
exports.onCounsellingServiceRequestCancelled = onDocumentUpdated(
  "service_requests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (after.type !== "counselling") return;
    if (before.status === after.status) return;
    if (after.status !== "cancelled") return;

    const db = getFirestore();
    const requestId = event.params.requestId;
    const sessionRef = db.collection("counselling_sessions").doc(requestId);

    await db.runTransaction(async (tx) => {
      const sessionSnap = await tx.get(sessionRef);
      if (!sessionSnap.exists) return;
      const currentStatus = sessionSnap.data().status;
      if (["completed", "cancelled", "expired"].includes(currentStatus)) {
        _logCounselling("INFO", "cancel_mirror_skipped_terminal", { requestId, currentStatus });
        return;
      }
      tx.update(sessionRef, { status: "cancelled", updatedAt: FieldValue.serverTimestamp() });
    });
    _logCounselling("INFO", "counselling_session_cancelled_by_patient", { requestId });
  }
);

// ── 3) Mirror counsellor-side session updates back onto service_requests ───
// Also credits the immutable counselling_transactions ledger exactly once,
// on the ->completed edge.
exports.onCounsellingSessionStatusChange = onDocumentUpdated(
  "counselling_sessions/{sessionId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    const sessionId = event.params.sessionId;
    const db = getFirestore();

    const statusChanged = before.status !== after.status;
    const claimChanged = before.counsellorId !== after.counsellorId;

    let mirrorError = null;

    if (statusChanged || claimChanged) {
      const update = { updatedAt: FieldValue.serverTimestamp() };

      const mappedStatus = _COUNSELLING_TO_SERVICE_REQUEST_STATUS[after.status];
      if (statusChanged && mappedStatus) update.status = mappedStatus;
      if (claimChanged && after.counsellorId) {
        update.assignedTo = after.counsellorId;
        const providerName = await _providerDisplayName(db, "counsellor_profiles", after.counsellorId);
        if (providerName) update.assignedToName = providerName;
      }

      if (Object.keys(update).length > 1) {
        const serviceRequestRef = db.collection("service_requests").doc(after.sourceRequestId || sessionId);
        const current = await serviceRequestRef.get();
        const currentData = current.exists ? current.data() : null;

        const alreadyApplied = !!currentData &&
          (!update.status || currentData.status === update.status) &&
          (!update.assignedTo || currentData.assignedTo === update.assignedTo);

        if (!currentData) {
          _logCounselling("WARNING", "mirror_target_missing", { sessionId });
        } else if (alreadyApplied) {
          _logCounselling("INFO", "mirror_skipped_already_applied", { sessionId });
        } else {
          await serviceRequestRef.update(update).then(
            () => _logCounselling("INFO", "mirrored_to_service_request", { sessionId, fields: Object.keys(update) }),
            (err) => {
              _logCounselling("ERROR", "mirror_to_service_request_failed", { sessionId, error: err.message });
              mirrorError = err;
            },
          );
        }
      }
    }

    if (statusChanged && after.status === "completed" && before.status !== "completed" && after.counsellorId) {
      const ledgerRef = db.collection("counselling_transactions").doc(sessionId);
      const credited = await db.runTransaction(async (tx) => {
        const existingTx = await tx.get(ledgerRef);
        if (existingTx.exists) return false;
        tx.set(ledgerRef, {
          counsellorId: after.counsellorId,
          sessionId,
          type: "earning",
          amount: after.amount ?? 0,
          status: "credited",
          patientName: after.patientName || "Patient",
          createdAt: FieldValue.serverTimestamp(),
        });
        return true;
      });
      _logCounselling("INFO", credited ? "counselling_ledger_credited" : "counselling_ledger_credit_skipped_duplicate", {
        sessionId, counsellorId: after.counsellorId, amount: after.amount ?? 0,
      });

      await _transitionPaymentToEligible(db, {
        sourceCollection: "service_requests",
        sourceId: after.sourceRequestId || sessionId,
        providerId: after.counsellorId,
        serviceType: "counselling",
      });
    }

    if (mirrorError) throw mirrorError;
  }
);

// ── 4) Stale pending-session cleanup ────────────────────────────────────────
exports.cleanupStaleCounsellingSessions = onSchedule({ schedule: "every 60 minutes", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromDate(new Date(Date.now() - _COUNSELLING_STALE_PENDING_HOURS * 60 * 60 * 1000));

  const staleSnap = await db.collection("counselling_sessions")
    .where("status", "==", "pending")
    .where("createdAt", "<", cutoff)
    .limit(200)
    .get();

  if (staleSnap.empty) {
    _logCounselling("INFO", "stale_cleanup_none_found");
    return;
  }

  const { updated, skipped } = await _expireStaleDocs(staleSnap.docs, { status: "expired", updatedAt: FieldValue.serverTimestamp() });
  _logCounselling("INFO", "stale_cleanup_expired", { count: updated, skippedConcurrentlyModified: skipped });
});

// ══════════════════════════════════════════════════════════════════════════
// ── Nutrition partner access ─────────────────────────────────────────────────
//
// Booking itself still needs no mirror: the patient app writes
// `nutrition_appointments` directly (mednu/lib/features/services/nutrition/
// services/nutrition_service.dart) with `nutritionistId` already set at
// booking time — the patient picks a specific nutritionist up front, same
// pre-assignment model as a doctor appointment. The Partner app reads/writes
// that collection directly; nothing to mirror or trigger there.
//
// What DOES need a mirror now: registration. Nutritionist used to be fully
// admin-provisioned (no `nutritionist_profiles` collection existed at all —
// an admin hand-created both the role grant and the `nutritionists/{uid}`
// catalogue entry). Nutritionist is now a normal self-serve role like Lab/
// Pharmacy/Caregiver: register -> `nutritionist_profiles/{uid}` (status
// 'pending') -> admin approves -> this mirror publishes it into the
// patient-facing `nutritionists/{uid}` catalogue. Same 1:1-doc mirror shape
// as `onCaregiverProfileWriteForVisibility` (no subcollection involved).
function _nutritionistListingDoc(profile, existingCreatedAt) {
  return {
    name: profile.name || "Nutritionist",
    qualification: profile.qualification || "",
    specialization: profile.specialization || "",
    experienceYears: profile.experienceYears ?? 0,
    bio: profile.bio || "",
    consultationFee: profile.consultationFee ?? 0,
    city: profile.city || "",
    ...(profile.lat != null && profile.lng != null
      ? { lat: profile.lat, lng: profile.lng }
      : {}),
    rating: profile.rating ?? 0,
    reviewCount: profile.reviewCount ?? 0,
    isAvailable: true,
    isOnlineAvailable: true,
    isInPersonAvailable: false,
    languages: profile.languages || [],
    expertiseAreas: [],
    availableDays: [],
    slots: {},
    createdAt: existingCreatedAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

exports.onNutritionistProfileWriteForVisibility = onDocumentWritten(
  "nutritionist_profiles/{nutritionistId}",
  async (event) => {
    const nutritionistId = event.params.nutritionistId;
    const db = getFirestore();
    const listingRef = db.collection("nutritionists").doc(nutritionistId);

    const after = event.data.after;
    if (!after.exists) {
      await listingRef.delete().catch(() => {});
      return;
    }

    const profile = after.data();
    if (profile.status !== "active") {
      await listingRef.delete().catch(() => {});
      return;
    }

    const existing = await listingRef.get();
    await listingRef.set(
      _nutritionistListingDoc(profile, existing.exists ? existing.data().createdAt : null),
      { merge: true },
    );
  }
);

exports.onNutritionistProfileApproved = onDocumentUpdated("nutritionist_profiles/{uid}", async (event) => {
  await _notifyPartnerApproved(
    getFirestore(), getMessaging(), "nutritionist", event.params.uid,
    event.data.before.data(), event.data.after.data(),
  );
});

// Nutrition appointment booking never had a trigger at all — the patient app
// writes `nutrition_appointments` directly with `nutritionistId` already set
// (see nutrition_service.dart's bookAppointment and the "Nutrition partner
// access" comment above), and mednu_doctor's own
// nutrition_appointment_service.dart doc comment says as much: "there is no
// Cloud [Function]" backing this collection. Every other vertical pushes a
// notification to the assigned/matched provider the moment a booking lands
// (_sendProviderNotification / _broadcastNewJobToActiveProviders) — a
// nutritionist only ever found out by having the app open to see the live
// Firestore listener update. This is always a directly-picked provider (the
// patient chooses a specific nutritionist before booking, same pre-assignment
// model as a doctor appointment), so it always notifies one provider — never
// broadcasts to a pool.
exports.onNutritionAppointmentCreated = onDocumentCreated(
  "nutrition_appointments/{appointmentId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    const nutritionistId = data.nutritionistId;
    if (!nutritionistId) return;

    await _sendProviderNotification(getFirestore(), getMessaging(), nutritionistId, {
      title: "New Appointment Booked",
      body: `${data.userName || "A patient"} booked a ${data.consultationType || "consultation"}` +
        (data.date ? ` on ${data.date}` : "") + (data.timeSlot ? ` at ${data.timeSlot}` : "") + ".",
      type: "new_nutrition_appointment", serviceType: "nutrition", bookingId: event.params.appointmentId,
    });
  }
);

// ── Nutrition vertical parity with the Settlement Engine ────────────────────
// `nutrition_appointments` captures real payment via capturePayment
// (book_nutrition_appointment_screen.dart) but, until now, had no
// completion -> ledger-eligible trigger — captured commission could never
// be batched or paid out. `nutrition_appointment_detail_screen.dart`'s
// "Mark Completed" action (_setStatus('completed', ...)) is the same
// pending->completed edge every other vertical already keys off.
exports.onNutritionAppointmentSettlement = onDocumentUpdated(
  "nutrition_appointments/{appointmentId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status) return;
    if (after.status !== "completed" || !after.nutritionistId) return;

    await _transitionPaymentToEligible(getFirestore(), {
      sourceCollection: "nutrition_appointments",
      sourceId: event.params.appointmentId,
      providerId: after.nutritionistId,
      serviceType: "nutrition",
    });
  }
);

// ── Hospital vertical parity with the Settlement Engine ─────────────────────
//
// Two independent hospital payment paths, each captures real money via
// capturePayment but, until now, had no completion -> ledger-eligible
// trigger — captured commission could never be batched or paid out:
//
//  - `hospital_bill_payments` (pay_hospital_bill_screen.dart): the billing
//    desk's one available action is `markVerified` (HospitalPaymentService,
//    mednu_doctor) flipping `hospitalVerified` true — that confirmation
//    IS this vertical's completion signal (the bill was already for a
//    real-world charge that already happened; verifying is the hospital
//    confirming the money landed, not confirming work still to be done).
//  - `hospital_appointments` (hospital_appointment_booking_screen.dart, a
//    flat-fee OP registration token — kHospitalOpFee): now has a real
//    mednu_doctor queue screen (HospitalAppointmentsScreen) driving
//    booked -> checked_in -> completed/no_show, so `completed` is this
//    vertical's real completion signal too — see
//    onHospitalAppointmentStatusChange below, which is what now calls
//    _transitionPaymentToEligible (onHospitalAppointmentCreated no longer
//    does, since booking is no longer the same moment the OP visit
//    actually happens).
exports.onHospitalBillPaymentVerified = onDocumentUpdated(
  "hospital_bill_payments/{paymentId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.hospitalVerified === after.hospitalVerified) return;
    if (after.hospitalVerified !== true || !after.hospitalId) return;

    await _transitionPaymentToEligible(getFirestore(), {
      sourceCollection: "hospital_bill_payments",
      sourceId: event.params.paymentId,
      providerId: after.hospitalId,
      serviceType: "hospital_bill",
    });
  }
);

// A hospital billing-desk login isn't itself the earning/operational entity
// — it links to a shared `hospitals/{hospitalId}` catalog id (potentially
// more than one active login per hospital), so notifying "the hospital"
// means fanning out to every `hospital_profiles` doc with a matching
// hospitalId, same shape as _broadcastNewJobToActiveProviders but filtered
// to one hospital instead of every active provider in a whole vertical.
async function _notifyHospitalStaff(db, messaging, hospitalId, opts) {
  if (!hospitalId) return;
  let snap;
  try {
    snap = await db.collection("hospital_profiles")
      .where("hospitalId", "==", hospitalId)
      .where("status", "==", "active")
      .get();
  } catch (err) {
    console.error(`Hospital staff notify: failed to query hospital_profiles for ${hospitalId}:`, err.message);
    return;
  }
  await Promise.all(snap.docs.map((d) => _sendProviderNotification(db, messaging, d.id, opts)));
}

exports.onHospitalAppointmentCreated = onDocumentCreated(
  "hospital_appointments/{appointmentId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (!data.hospitalId) return;

    await _notifyHospitalStaff(getFirestore(), getMessaging(), data.hospitalId, {
      title: "New OP Appointment",
      body: `${data.patientName || "A patient"} booked an OP visit` +
        (data.date ? ` on ${data.date}` : "") + (data.time ? ` at ${data.time}` : "") + ".",
      type: "new_hospital_appointment", serviceType: "hospital_op", bookingId: event.params.appointmentId,
    });
  }
);

// Drives the OP queue's patient-facing notifications and, on `completed`,
// the same settlement-eligible transition every other vertical fires on its
// own completion edge (see the "Hospital vertical parity" comment above).
exports.onHospitalAppointmentStatusChange = onDocumentUpdated(
  "hospital_appointments/{appointmentId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status) return;

    const patientId = after.patientId;
    const appointmentId = event.params.appointmentId;

    if (patientId) {
      let title = "";
      let body = "";
      let type = "";
      switch (after.status) {
        case "checked_in":
          title = "Checked In";
          body = `You've been checked in at ${after.hospitalName || "the hospital"}. Please wait to be called.`;
          type = "hospital_appointment_checked_in";
          break;
        case "completed":
          title = "OP Visit Completed";
          body = `Your OP visit at ${after.hospitalName || "the hospital"} is complete.`;
          type = "hospital_appointment_completed";
          break;
        case "no_show":
          title = "Marked as No-Show";
          body = `${after.hospitalName || "The hospital"} marked your OP appointment as a no-show.`;
          type = "hospital_appointment_no_show";
          break;
        default:
          break;
      }
      if (title) {
        await _sendPatientNotification(getFirestore(), getMessaging(), patientId, {
          title, body, type, serviceType: "hospital_op", bookingId: appointmentId, actionType: "open_appointment",
        });
      }
    }

    if (after.status === "completed" && after.hospitalId) {
      await _transitionPaymentToEligible(getFirestore(), {
        sourceCollection: "hospital_appointments",
        sourceId: appointmentId,
        providerId: after.hospitalId,
        serviceType: "hospital_op",
      });
    }
  }
);

// ══════════════════════════════════════════════════════════════════════════
// ── Physiotherapist public catalogue mirror ──────────────────────────────────
//
// Physiotherapy already has a live booking pipeline (service_requests[type
// 'physiotherapy'] -> physio_sessions, see above) that assigns any available
// physiotherapist to an unclaimed request. What was missing is a way for a
// patient to browse and pick a SPECIFIC physiotherapist up front (by
// language/city, same as Doctors) rather than always getting auto-matched.
// This mirror publishes an approved `physiotherapist_profiles/{uid}` into a
// new public `physiotherapists/{uid}` catalogue a patient can browse — same
// 1:1-doc mirror shape as `onNutritionistProfileWriteForVisibility`. Booking
// a specific physiotherapist from that catalogue still goes through the
// existing service_requests -> physio_sessions pipeline unchanged; it just
// pre-sets `physiotherapistId` on the request (see `_buildSessionDoc` above),
// skipping the unclaimed pool instead of bypassing it.
function _physiotherapistListingDoc(profile, existingCreatedAt) {
  return {
    name: profile.name || "Physiotherapist",
    photoUrl: profile.photoUrl || "",
    certifications: profile.certifications || [],
    specialties: profile.specialties || [],
    experienceYears: profile.experienceYears ?? 0,
    hourlyRate: profile.hourlyRate ?? 0,
    rating: profile.rating ?? 0,
    totalSessions: profile.totalSessions ?? 0,
    city: profile.city || "",
    languages: profile.languages || [],
    ...(profile.clinicLat != null && profile.clinicLng != null
      ? { clinicLat: profile.clinicLat, clinicLng: profile.clinicLng }
      : {}),
    // `isAvailable` means "listed" (approved + active) — kept `true`
    // unconditionally so the existing browse/schedule screens keep showing
    // every approved physiotherapist, not just ones online right now.
    // `isOnline`/`lastHeartbeat` are the separate realtime-presence fields
    // PhysioPresenceService's heartbeat writes onto the source profile
    // (mednu_doctor/core/services/physio_presence_service.dart) — mirrored
    // through as-is so a patient-facing "online now" badge/filter can use
    // the same staleness check the doctor Quick Connect screen already does
    // (isOnline === true AND lastHeartbeat within the last few minutes).
    isAvailable: true,
    isOnline: profile.isOnline === true,
    lastHeartbeat: profile.lastHeartbeat || null,
    createdAt: existingCreatedAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

exports.onPhysiotherapistProfileWriteForVisibility = onDocumentWritten(
  "physiotherapist_profiles/{physiotherapistId}",
  async (event) => {
    const physiotherapistId = event.params.physiotherapistId;
    const db = getFirestore();
    const listingRef = db.collection("physiotherapists").doc(physiotherapistId);

    const after = event.data.after;
    if (!after.exists) {
      await listingRef.delete().catch(() => {});
      return;
    }

    const profile = after.data();
    if (profile.status !== "active") {
      await listingRef.delete().catch(() => {});
      return;
    }

    const existing = await listingRef.get();
    await listingRef.set(
      _physiotherapistListingDoc(profile, existing.exists ? existing.data().createdAt : null),
      { merge: true },
    );
  }
);
// ══════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════
// ── Counsellor public catalogue mirror ───────────────────────────────────
//
// Same gap as Physiotherapist above, but Counselling had it worse: there was
// no way at all for a patient to discover a `counsellor_profiles` partner —
// the patient app's Counselling screen only ever booked an actual Doctor
// whose specialty happens to be Psychiatry/Psychology/Counselling. The
// counselling_sessions booking pipeline (service_requests[type
// 'counselling'] -> counselling_sessions, see above) already exists and
// already honors a pre-assigned `counsellorId`; this mirror is what a
// patient-facing browse screen needs to read from. Counsellor registration
// collects no city/location/languages (session delivery is remote-only), so
// unlike the physiotherapist listing doc this one carries no
// clinicLat/clinicLng/languages fields.
function _counsellorListingDoc(profile, existingCreatedAt) {
  return {
    name: profile.name || "Counsellor",
    photoUrl: profile.photoUrl || "",
    certifications: profile.certifications || [],
    specialties: profile.specialties || [],
    experienceYears: profile.experienceYears ?? 0,
    hourlyRate: profile.hourlyRate ?? 0,
    rating: profile.rating ?? 0,
    totalSessions: profile.totalSessions ?? 0,
    // See the matching comment in `_physiotherapistListingDoc` above:
    // `isAvailable` stays `true` unconditionally (means "listed"), while
    // `isOnline`/`lastHeartbeat` mirror CounsellorPresenceService's realtime
    // heartbeat for an "online now" badge/filter.
    isAvailable: true,
    isOnline: profile.isOnline === true,
    lastHeartbeat: profile.lastHeartbeat || null,
    createdAt: existingCreatedAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

exports.onCounsellorProfileWriteForVisibility = onDocumentWritten(
  "counsellor_profiles/{counsellorId}",
  async (event) => {
    const counsellorId = event.params.counsellorId;
    const db = getFirestore();
    const listingRef = db.collection("counsellors").doc(counsellorId);

    const after = event.data.after;
    if (!after.exists) {
      await listingRef.delete().catch(() => {});
      return;
    }

    const profile = after.data();
    if (profile.status !== "active") {
      await listingRef.delete().catch(() => {});
      return;
    }

    const existing = await listingRef.get();
    await listingRef.set(
      _counsellorListingDoc(profile, existing.exists ? existing.data().createdAt : null),
      { merge: true },
    );
  }
);
// ══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// ── Server-driven reminders (water / period / booking / appointment) ───────────
//
// On-device alarms (flutter_local_notifications) get killed by OEM battery
// optimization, so client-scheduled reminders silently stop firing once the
// app is backgrounded/closed. Delivery is moved here instead: the client
// still decides *what* and *when* — writing a row to `scheduled_reminders`
// for one-time reminders, or (for water, which repeats daily) just keeping
// its existing settings doc current — and these two scheduled functions own
// *firing*, riding FCM's battery-exempt push channel the same way
// onNewConsultation etc. above already do, instead of depending on the
// phone's AlarmManager staying alive.
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Sends one reminder push. Looks up the FCM token by uid+role, sends a
 * notification+data message — displayed by the OS itself even if the app
 * process is dead, unlike a data-only message, which needs the app's own
 * background isolate to run and is just as Doze-exposed as a local alarm —
 * and clears the stale token on send failure. Never throws.
 */
async function _sendReminderPush(db, messaging, { uid, role, title, body, channelId, data = {} }) {
  const tokenCollections = role === "doctor" ? ["doctors"] : ["users", "patients"];

  let token = null;
  const tokenDocs = [];
  for (const col of tokenCollections) {
    try {
      const snap = await db.collection(col).doc(uid).get();
      if (snap.exists && snap.data()?.fcmToken) {
        tokenDocs.push(snap.ref);
        if (!token) token = snap.data().fcmToken;
      }
    } catch (_) {}
  }

  if (!token) {
    console.log(`_sendReminderPush: no FCM token for ${role} ${uid} — skipped`);
    return;
  }

  const fcmData = {};
  for (const [k, v] of Object.entries(data)) {
    if (v != null) fcmData[k] = String(v);
  }

  try {
    await messaging.send({
      token,
      data: fcmData,
      android: {
        priority: "high",
        notification: { channelId, title, body, sound: "default", defaultVibrateTimings: true },
      },
      apns: {
        headers: { "apns-priority": "5" },
        payload: { aps: { alert: { title, body }, sound: "default" } },
      },
    });
    console.log(`Reminder push sent → ${role} ${uid}: "${title}"`);
  } catch (err) {
    console.error(`Reminder push failed for ${role} ${uid}:`, err.message);
    // Stale/uninstalled-app token — clear it everywhere it's mirrored so we
    // stop paying for a send that will never succeed again.
    if (err.code === "messaging/registration-token-not-registered" ||
        err.code === "messaging/invalid-registration-token") {
      await Promise.all(tokenDocs.map((ref) =>
        ref.update({ fcmToken: FieldValue.delete() }).catch(() => {})));
    }
  }
}

// ── One-time reminder queue ─────────────────────────────────────────────────
// Populated by the client (period pre-alerts, period wellness check-ins,
// patient booking reminders, doctor appointment reminders) with a
// deterministic doc ID per reminder instance, so cancel/reschedule is a
// plain delete-by-ID on the client side. This function only delivers
// whatever's due — no scheduling logic is duplicated here.
exports.processDueReminders = onSchedule({ schedule: "every 5 minutes", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const messaging = getMessaging();
  const now = Timestamp.now();

  const dueSnap = await db.collection("scheduled_reminders")
    .where("status", "==", "pending")
    .where("fireAt", "<=", now)
    .limit(300) // bounded per run; the next 5-minute tick picks up any remainder.
    .get();

  if (dueSnap.empty) return;

  let sent = 0;
  await Promise.all(dueSnap.docs.map(async (doc) => {
    const r = doc.data();
    if (!r.uid || !r.title || !r.body) {
      await doc.ref.update({ status: "sent", updatedAt: FieldValue.serverTimestamp() }).catch(() => {});
      return;
    }
    await _sendReminderPush(db, messaging, {
      uid: r.uid,
      role: r.role === "doctor" ? "doctor" : "patient",
      title: r.title,
      body: r.body,
      channelId: r.channelId || "mednu_default_channel",
      data: r.data || {},
    });
    await doc.ref.update({ status: "sent", updatedAt: FieldValue.serverTimestamp() }).catch(() => {});
    sent++;
  }));
  console.log(`processDueReminders: sent ${sent}/${dueSnap.size}`);
});

// ── Recurring water reminders ───────────────────────────────────────────────
// Water reminders repeat daily on an interval grid (see nextReminderTime()
// in health_notification_service.dart) rather than firing once, so they
// don't fit the one-shot queue above — this re-evaluates the grid every
// tick directly against each user's settings doc instead. The app is
// India-only (see the IST assumption on _apptSlotStartMs above), so IST is
// hardcoded rather than requiring a new stored per-user timezone field.
const _WATER_TICK_MINUTES = 15;      // matches this function's own schedule below
// Hard quiet-hours gate: never send outside 9 AM-11 PM, no matter what start
// hour/interval the user picked (matches _waterWindow* client-side).
const _WATER_WINDOW_START_MINUTES = 9 * 60;  // 9:00 AM
const _WATER_WINDOW_END_MINUTES = 23 * 60;   // 11:00 PM

function _istNowParts() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Kolkata",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hour12: false,
  }).formatToParts(new Date());
  const get = (t) => parts.find((p) => p.type === t).value;
  return {
    dateKey: `${get("year")}-${get("month")}-${get("day")}`,
    minutesOfDay: Number(get("hour")) * 60 + Number(get("minute")),
  };
}

exports.sendDueWaterReminders = onSchedule({ schedule: "every 15 minutes", timeZone: "Asia/Kolkata" }, async () => {
  const db = getFirestore();
  const messaging = getMessaging();
  const { dateKey, minutesOfDay } = _istNowParts();

  // `settings` is also the parent of period-tracker settings docs (same
  // subcollection name, different doc ID) — filtered out below by doc.ref.id.
  const snap = await db.collectionGroup("settings")
    .where("remindersEnabled", "==", true)
    .get();

  let sent = 0;
  await Promise.all(snap.docs.map(async (doc) => {
    if (doc.ref.id !== "water") return;
    const w = doc.data();
    const uid = doc.ref.parent.parent?.id;
    if (!uid) return;

    const intervalMinutes = (w.reminderIntervalHours || 2) * 60;
    const configuredStartMinutes = (w.reminderStartHour ?? 8) * 60 + (w.reminderStartMinute ?? 0);
    // Clamp the grid's start to the quiet-hours window so an early configured
    // start time can't pull slots earlier than 9 AM.
    const startMinutes = Math.max(configuredStartMinutes, _WATER_WINDOW_START_MINUTES);

    // Which slot (if any) falls inside this tick's window? Slots stop at
    // _WATER_WINDOW_END_MINUTES so the grid can never roll into the night.
    let matchedSlot = null;
    for (let slotMinute = startMinutes; slotMinute < _WATER_WINDOW_END_MINUTES; slotMinute += intervalMinutes) {
      if (slotMinute >= minutesOfDay && slotMinute < minutesOfDay + _WATER_TICK_MINUTES) {
        matchedSlot = slotMinute;
        break;
      }
    }
    if (matchedSlot == null) return;

    const slotKey = `${dateKey}T${String(Math.floor(matchedSlot / 60)).padStart(2, "0")}:${String(matchedSlot % 60).padStart(2, "0")}`;
    if (w.lastSentSlotKey === slotKey) return; // already sent this exact slot

    await _sendReminderPush(db, messaging, {
      uid,
      role: "patient",
      title: "💧 Time to hydrate!",
      body: "Keep it up — drink a glass of water to stay healthy.",
      channelId: "water_reminders",
      data: { type: "water_reminder" },
    });
    await doc.ref.update({ lastSentSlotKey: slotKey }).catch(() => {});
    sent++;
  }));
  console.log(`sendDueWaterReminders: sent ${sent}`);
});

// ── Partner Application Approved ─────────────────────────────────────────────
//
// Fires when an admin flips a Lab/Pharmacy/Ambulance/Caregiver profile's
// `status` to 'active' in the admin panel. Pushes a notification straight to
// the partner's device using the `fcmToken` already on the document —
// VerificationPendingScreen's "we'll notify you" promise had nothing behind
// it until this.
async function _notifyPartnerApproved(db, messaging, role, uid, before, after) {
  if (before.status === after.status) return;
  if (after.status !== "active") return;

  const title = "Application Approved";
  const body = "Your MedNU partner account is verified — you can start receiving bookings now.";

  // In-app record — this previously only ever sent the FCM push, so the
  // approval never showed up in the notification bell even for a partner
  // who missed the OS push (app closed at the time, notification swiped
  // away, etc.). Same collection/shape `_sendProviderNotification` writes,
  // so it renders identically to every other provider-side notification.
  await db.collection("provider_notifications").doc(uid).collection("items").add({
    type: "account_approved", title, body, role,
    createdAt: FieldValue.serverTimestamp(),
    deliverAt: FieldValue.serverTimestamp(),
    isRead: false,
    data: {},
  }).catch((err) => console.error(`Failed to write provider_notifications for ${role} ${uid}:`, err.message));

  const fcmToken = after.fcmToken;
  if (!fcmToken) {
    console.log(`No fcmToken on ${role}_profiles/${uid} — approval push skipped`);
    return;
  }

  try {
    await messaging.send({
      token: fcmToken,
      data: { type: "partner_approved", role },
      android: {
        priority: "high",
        notification: {
          // Not mednu_doctor's default channel (there isn't one registered
          // client-side) — "incoming_call" is the one channel that actually
          // exists on the device (created by CallNotificationService.init(),
          // and set as the AndroidManifest fallback too), and is also what
          // showGenericNotification() uses for this same message type when
          // the app is foregrounded — keeping both paths on one channel.
          channelId: "incoming_call",
          title,
          body,
          sound: "default",
          defaultVibrateTimings: true,
        },
      },
      apns: {
        headers: { "apns-priority": "5" },
        payload: {
          aps: { alert: { title, body }, sound: "default", badge: 1 },
        },
      },
    });
    console.log(`Approval push sent → ${role} partner ${uid}`);
  } catch (err) {
    console.error(`Approval push failed for ${role} partner ${uid}:`, err.message);
  }
}

exports.onLabProfileApproved = onDocumentUpdated("lab_profiles/{uid}", async (event) => {
  await _notifyPartnerApproved(
    getFirestore(), getMessaging(), "lab", event.params.uid,
    event.data.before.data(), event.data.after.data(),
  );
});

exports.onPharmacyProfileApproved = onDocumentUpdated("pharmacy_profiles/{uid}", async (event) => {
  await _notifyPartnerApproved(
    getFirestore(), getMessaging(), "pharmacy", event.params.uid,
    event.data.before.data(), event.data.after.data(),
  );
});

exports.onAmbulanceProfileApproved = onDocumentUpdated("ambulance_profiles/{uid}", async (event) => {
  await _notifyPartnerApproved(
    getFirestore(), getMessaging(), "ambulance", event.params.uid,
    event.data.before.data(), event.data.after.data(),
  );
});

exports.onCaregiverProfileApproved = onDocumentUpdated("caregiver_profiles/{uid}", async (event) => {
  await _notifyPartnerApproved(
    getFirestore(), getMessaging(), "caregiver", event.params.uid,
    event.data.before.data(), event.data.after.data(),
  );
});

// Physiotherapist and Counsellor never had an approval-push trigger either —
// same gap as Doctor below, just for the two roles that only just gained a
// document-verification step (see PartnerDocumentType.physiotherapist /
// .counsellor in mednu_doctor's partner_document_models.dart).
exports.onPhysiotherapistProfileApproved = onDocumentUpdated("physiotherapist_profiles/{uid}", async (event) => {
  await _notifyPartnerApproved(
    getFirestore(), getMessaging(), "physiotherapist", event.params.uid,
    event.data.before.data(), event.data.after.data(),
  );
});

exports.onCounsellorProfileApproved = onDocumentUpdated("counsellor_profiles/{uid}", async (event) => {
  await _notifyPartnerApproved(
    getFirestore(), getMessaging(), "counsellor", event.params.uid,
    event.data.before.data(), event.data.after.data(),
  );
});

// Doctor accounts use the exact same `doctors/{uid}.status: 'pending' ->
// 'active'` convention as every partner profile (see doctor_auth_service.dart
// registration + mednu-admin's approve action) but, unlike the 5 partner
// verticals above, never had an approval-push trigger at all.
exports.onDoctorProfileApproved = onDocumentUpdated("doctors/{uid}", async (event) => {
  await _notifyPartnerApproved(
    getFirestore(), getMessaging(), "doctor", event.params.uid,
    event.data.before.data(), event.data.after.data(),
  );
});

// ── Guest Join: family-member call access without a MedNu account ───────────
//
// Lets the account holder who booked a *scheduled* consultation for a family
// member (who has no MedNu login of their own) share a signed, time-boxed
// link so that family member can join the call from their own phone.
//
// The link is bound to the appointmentId, not a consultationId — the
// consultation doc for a scheduled appointment doesn't exist yet at booking
// time; it's only created later when the doctor actually starts the call
// (see mednu_doctor's dashboard_screen.dart, _startCallForAppointment). The
// guest's Firebase custom-token session carries a `guestAppointmentId` claim,
// which Firestore rules and generateAgoraToken (below) check against instead
// of requiring the guest to be the doctor/patient uid on the doc.
//
// The token itself is an HMAC over the appointmentId + expiry, verified
// server-side with no Firebase Auth required to redeem it (the whole point
// is the guest has no account) — same crypto.createHmac pattern already used
// for Razorpay webhook verification elsewhere in this file.

// Request data: { appointmentId: string }
// Response:     { deepLink: string }
exports.createGuestJoinLink = onCall({ secrets: ["GUEST_LINK_SECRET"] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const { appointmentId } = request.data || {};
  if (typeof appointmentId !== "string" || !appointmentId.trim()) {
    throw new HttpsError("invalid-argument", "appointmentId is required.");
  }

  const db = getFirestore();
  const apptSnap = await db.collection("appointments").doc(appointmentId).get();
  if (!apptSnap.exists) {
    throw new HttpsError("not-found", "Appointment not found.");
  }
  const appt = apptSnap.data();
  if (appt.patientId !== uid) {
    throw new HttpsError("permission-denied", "You can only share a join link for your own booking.");
  }
  const guestPhone = (appt.guestPhone || "").trim();
  if (!guestPhone) {
    throw new HttpsError(
      "failed-precondition",
      "This booking has no guest phone number — add one when booking to enable this.",
    );
  }

  // Expiry: the appointment's scheduled date/time (IST) + 3 hours, so a late
  // start is still covered. Falls back to 24h from now if date/time are
  // missing or in an unexpected format, rather than failing outright.
  let exp;
  const dateStr = appt.date;
  const timeMatch = /^(\d{2}):(\d{2})\s*(AM|PM)$/i.exec((appt.time || "").trim());
  if (typeof dateStr === "string" && /^\d{4}-\d{2}-\d{2}$/.test(dateStr) && timeMatch) {
    let hour = parseInt(timeMatch[1], 10) % 12;
    if (timeMatch[3].toUpperCase() === "PM") hour += 12;
    const scheduled = new Date(`${dateStr}T${String(hour).padStart(2, "0")}:${timeMatch[2]}:00+05:30`);
    exp = Math.floor(scheduled.getTime() / 1000) + 3 * 3600;
  } else {
    exp = Math.floor(Date.now() / 1000) + 24 * 3600;
  }

  const secret = process.env.GUEST_LINK_SECRET;
  if (!secret) {
    throw new HttpsError("failed-precondition", "Guest join is not configured.");
  }
  const token = crypto
    .createHmac("sha256", secret)
    .update(`${appointmentId}.${exp}`)
    .digest("hex");

  // Wrapped in an https:// landing page (mednu_web/web/join.html) rather than
  // handed out as a bare mednu:// custom-scheme link: most share targets
  // (WhatsApp, SMS, iMessage) only auto-linkify http(s) URLs, so a raw custom
  // scheme often isn't even tappable. The landing page redirects into this
  // same mednu://join deep link once opened in a real browser.
  return {
    deepLink: `https://mednu-web.web.app/join.html?a=${appointmentId}&t=${token}&exp=${exp}`,
  };
});

// Request data: { appointmentId: string, token: string, exp: number }
// Response:     { customToken, doctorName, doctorSpecialty, date, time, consultationId }
exports.redeemGuestJoinLink = onCall({ secrets: ["GUEST_LINK_SECRET"] }, async (request) => {
  const { appointmentId, token, exp } = request.data || {};
  if (
    typeof appointmentId !== "string" || !appointmentId.trim() ||
    typeof token !== "string" || !token.trim() ||
    typeof exp !== "number"
  ) {
    throw new HttpsError("invalid-argument", "Invalid join link.");
  }

  if (Math.floor(Date.now() / 1000) > exp) {
    throw new HttpsError("deadline-exceeded", "This join link has expired.");
  }

  const secret = process.env.GUEST_LINK_SECRET;
  if (!secret) {
    throw new HttpsError("failed-precondition", "Guest join is not configured.");
  }
  const expected = crypto
    .createHmac("sha256", secret)
    .update(`${appointmentId}.${exp}`)
    .digest("hex");

  let valid = false;
  try {
    const expectedBuf = Buffer.from(expected, "hex");
    const givenBuf = Buffer.from(token, "hex");
    valid = expectedBuf.length === givenBuf.length && crypto.timingSafeEqual(expectedBuf, givenBuf);
  } catch (_) {
    valid = false;
  }
  if (!valid) {
    throw new HttpsError("permission-denied", "Invalid join link.");
  }

  const db = getFirestore();
  const apptSnap = await db.collection("appointments").doc(appointmentId).get();
  if (!apptSnap.exists) {
    throw new HttpsError("not-found", "This appointment no longer exists.");
  }
  const appt = apptSnap.data();
  if (!(appt.guestPhone || "").trim()) {
    throw new HttpsError("failed-precondition", "This booking is not guest-enabled.");
  }
  if (appt.status === "cancelled") {
    throw new HttpsError("failed-precondition", "This appointment was cancelled.");
  }
  if (appt.status === "completed") {
    throw new HttpsError("failed-precondition", "This consultation has already ended.");
  }

  const customToken = await getAuth().createCustomToken(`guest_${appointmentId}`, {
    guestAppointmentId: appointmentId,
  });

  return {
    customToken,
    doctorName: appt.doctorName || "your doctor",
    doctorSpecialty: appt.doctorSpecialty || "",
    date: appt.date || "",
    time: appt.time || "",
    consultationId: appt.consultationId || null,
  };
});

// ── Agora RTC token ───────────────────────────────────────────────────────
// The App ID is public (embedded in both client apps' AgoraCallService); the
// App Certificate is the actual secret that must never leave the server, so
// it's read from AGORA_APP_CERTIFICATE at runtime — set it the same way
// RAZORPAY_KEY_SECRET is already configured for this project.
const AGORA_APP_ID = "b0143ffdfef74f399a420c7cd73c9e8b";

exports.generateAgoraToken = onCall({ secrets: ["AGORA_APP_CERTIFICATE"] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const { channelName } = request.data || {};
  if (typeof channelName !== "string" || !channelName.trim()) {
    throw new HttpsError("invalid-argument", "channelName is required.");
  }
  const consultationId = channelName.trim();

  // Both apps use the consultation's own Firestore doc id as the Agora
  // channel name, so this doubles as the join authorization check — only
  // the doctor or patient actually on this consultation, or a guest holding
  // a valid guestAppointmentId claim for it (see createGuestJoinLink above),
  // may obtain a token for it. Without this, any signed-in user who
  // learned/guessed a consultationId could join someone else's call.
  const db = getFirestore();
  const consultSnap = await db.collection("consultations").doc(consultationId).get();
  if (!consultSnap.exists) {
    throw new HttpsError("not-found", "Consultation not found.");
  }
  const consult = consultSnap.data();
  const guestAppointmentId = request.auth?.token?.guestAppointmentId;
  const isGuest = !!guestAppointmentId && !!consult.appointmentId &&
    guestAppointmentId === consult.appointmentId;
  if (consult.doctorId !== uid && consult.patientId !== uid && !isGuest) {
    throw new HttpsError("permission-denied", "You are not a participant in this consultation.");
  }

  const appCertificate = process.env.AGORA_APP_CERTIFICATE;
  if (!appCertificate) {
    throw new HttpsError("failed-precondition", "Video calling is not configured.");
  }

  // Fixed uid per verified role on this consultation, not a client-supplied
  // or auto-assigned (0) uid — this lets a 3-party call (patient + a family
  // member joining as guest + doctor) tell participants' video tiles apart.
  // Assigned from the caller's *verified* identity above, never trusted from
  // the client, so a guest can't claim the doctor's uid. Ordinary 1:1 calls
  // only ever use uid 1/2, so this is unchanged for every call in flight.
  const assignedUid = consult.doctorId === uid ? 1 : consult.patientId === uid ? 2 : 3;

  const expirationInSeconds = 3600;
  const currentTs = Math.floor(Date.now() / 1000);
  const privilegeExpiredTs = currentTs + expirationInSeconds;

  const token = RtcTokenBuilder.buildTokenWithUid(
    AGORA_APP_ID, appCertificate, consultationId, assignedUid,
    RtcRole.PUBLISHER, privilegeExpiredTs, privilegeExpiredTs,
  );

  return { token, uid: assignedUid, expiresAt: privilegeExpiredTs };
});
