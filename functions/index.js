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
const _PROVIDER_INITIATED_CALLER_TYPES = ["doctor", "physiotherapist", "counsellor", "nutritionist"];

function _providerRoleLabel(callerType) {
  switch (callerType) {
    case "physiotherapist": return "Physiotherapist";
    case "counsellor": return "Counsellor";
    case "nutritionist": return "Dietician";
    default: return "Doctor";
  }
}

async function _pushIncomingDoctorCallToPatient(data, consultationId) {
  const patientId = data.patientId;
  if (!patientId) return;

  // Looked up here rather than trusted from the caller: provider accounts
  // can't read patient profile docs (firestore.rules), so the client-side
  // `patientFcmToken` on the consultation is usually empty. The patient app
  // writes its token to `patients/{uid}`, older builds to `users/{uid}`.
  let fcmToken = null;
  try {
    for (const col of ["patients", "users"]) {
      const snap = await getFirestore().collection(col).doc(patientId).get();
      fcmToken = (snap.exists && snap.data()?.fcmToken) || null;
      if (fcmToken) break;
    }
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

    // Freshest FCM token for this doctor (doctors/{uid} + role profiles),
    // newest `fcmTokenUpdatedAt` wins so a new phone gets the call.
    const tokenCandidates = await _providerTokenCandidates(getFirestore(), doctorId);
    if (!tokenCandidates.length) {
      console.log(`Doctor ${doctorId} has no FCM token — skipping push.`);
      return;
    }

    const patientName = data.patientName || "Patient";
    const complaint = data.chiefComplaint || "";
    const consultationType = data.consultationType || "Video";

    const message = {
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

    const sent = await _sendToProviderCandidates(getMessaging(), tokenCandidates, message, `doctor ${doctorId}`);
    if (sent) console.log(`FCM sent to doctor ${doctorId}`);
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

    // Fallback: the patient app writes its token to `patients/{uid}`, older
    // builds to `users/{uid}`. Provider-initiated calls usually land here,
    // since provider accounts can't read patient docs to fill it in.
    if (!fcmToken) {
      try {
        for (const col of ["patients", "users"]) {
          const snap = await getFirestore().collection(col).doc(patientId).get();
          fcmToken = (snap.exists && snap.data()?.fcmToken) || null;
          if (fcmToken) break;
        }
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
        // Drop tokens FCM reports as dead so they stop being targeted.
        await Promise.all(res.responses.map((r, j) => {
          if (r.success || !_INVALID_FCM_TOKEN_CODES.includes(r.error && r.error.code)) return null;
          const uid = doctorIds[i + j];
          return uid && db.collection("doctors").doc(uid).update({
            fcmToken: FieldValue.delete(),
            fcmTokenUpdatedAt: FieldValue.delete(),
            fcmPlatform: FieldValue.delete(),
          }).catch(() => {});
        }));
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
    const slotConflictWrite = !!after.slotConflictAt &&
      !after.slotConflictAt.isEqual?.(before.slotConflictAt);

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

    if (slotConflictWrite) return; // patient already told by _resolveSlotConflict

    if (statusChanged && after.status === "cancelled" && after.cancelledBy === "patient") {
      await _notifyProviderOfPatientCancel(db, doctorId, {
        serviceType: "appointment", bookingId: apptId, what: "appointment",
      });
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

// ── Public slot index for doctor appointments ──────────────────────────────
// Patients need to know which of a doctor's slots are taken, but must not be
// able to read other patients' appointments (name, specialty, guest phone).
// `appointment_slots/{doctorId}_{date}_{time}` holds only doctorId/date/time
// (+ the owning appointmentId, so a stale write can't free someone else's
// slot) and is the only thing booking screens query. Server-written only —
// see firestore.rules' appointment_slots.
function _slotKey(doctorId, date, time) {
  return `${doctorId}_${date}_${String(time).replace(/[^A-Za-z0-9]/g, "-")}`;
}

function _bookedSlotOf(appt) {
  if (!appt || appt.status !== "booked" || !appt.doctorId || !appt.date || !appt.time) return null;
  return { key: _slotKey(appt.doctorId, appt.date, appt.time), doctorId: appt.doctorId, date: appt.date, time: appt.time };
}

exports.onAppointmentWrittenForSlots = onDocumentWritten(
  "appointments/{appointmentId}",
  async (event) => {
    const db = getFirestore();
    const appointmentId = event.params.appointmentId;
    const beforeData = event.data.before?.exists ? event.data.before.data() : null;
    const afterData = event.data.after?.exists ? event.data.after.data() : null;
    const prev = _bookedSlotOf(beforeData);
    const next = _bookedSlotOf(afterData);
    if (prev && next && prev.key === next.key) return;

    // Claim the new slot first. Every booking path (in-app, web portal,
    // capturePayment, reschedule) ends in an appointments write, so this one
    // transaction is the single place a slot is granted: first to commit
    // wins, and the slot doc can only be held by a still-booked appointment.
    if (next) {
      const slotRef = db.collection("appointment_slots").doc(next.key);
      const conflict = await db.runTransaction(async (tx) => {
        const slotSnap = await tx.get(slotRef);
        const holderId = slotSnap.exists ? slotSnap.data().appointmentId : null;
        if (holderId && holderId !== appointmentId) {
          const holder = await tx.get(db.collection("appointments").doc(holderId));
          if (holder.exists && _bookedSlotOf(holder.data())?.key === next.key) return true;
        }
        tx.set(slotRef, {
          doctorId: next.doctorId, date: next.date, time: next.time, appointmentId,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return false;
      });
      if (conflict) {
        await _resolveSlotConflict(db, appointmentId, beforeData, afterData, prev);
        return; // keep `prev` held: a rejected reschedule goes straight back to it
      }
    }

    if (prev) {
      const ref = db.collection("appointment_slots").doc(prev.key);
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (snap.exists && snap.data().appointmentId === appointmentId) tx.delete(ref);
      });
    }
  }
);

// The losing side of a slot race. A reschedule into a taken slot is put back
// on its original date/time (the patient keeps the appointment they already
// had); a brand-new booking is cancelled and auto-refunded if it was paid.
// `slotConflictAt` tells onAppointmentStatusChange to stay quiet — this sends
// the one notification that actually explains what happened.
async function _resolveSlotConflict(db, appointmentId, beforeData, afterData, prev) {
  const ref = db.collection("appointments").doc(appointmentId);
  const patientId = afterData.patientId;
  const doctorName = afterData.doctorName || "the doctor";
  const isReschedule = !!prev;

  if (isReschedule) {
    await ref.update({
      date: beforeData.date,
      time: beforeData.time,
      slotConflictAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } else {
    await ref.update({
      status: "cancelled",
      cancelledBy: "system",
      cancelReason: "slot_taken",
      slotConflictAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    await _autoRefundBooking(db, "appointments", appointmentId,
      "Slot was booked by another patient at the same moment");
  }
  console.log(JSON.stringify({
    module: "appointment_slots", event: isReschedule ? "reschedule_reverted" : "booking_cancelled_slot_taken",
    appointmentId, doctorId: afterData.doctorId, date: afterData.date, time: afterData.time,
  }));

  if (!patientId) return;
  await _sendPatientNotification(db, getMessaging(), patientId, isReschedule ? {
    title: "Reschedule Not Possible",
    body: `${afterData.time} on ${afterData.date} was just booked by someone else. Your appointment with Dr. ${doctorName} stays at ${beforeData.time} on ${beforeData.date}.`,
    type: "appointment_reschedule_conflict",
    serviceType: "appointment",
    bookingId: appointmentId,
    actionType: "open_appointment",
  } : {
    title: "Slot Just Taken",
    body: `Someone booked Dr. ${doctorName} at ${afterData.time} on ${afterData.date} a moment before you. Please pick another time${afterData.paymentId ? " — your payment is being refunded" : ""}.`,
    type: "appointment_slot_taken",
    serviceType: "appointment",
    bookingId: appointmentId,
    actionType: "open_appointment",
  }).catch(() => {});
}

// Rebuilds today-onwards slots from the appointments themselves: backfills
// bookings made before the index existed and repairs any missed trigger
// (e.g. two appointments double-booked into one slot before this lock).
exports.reconcileAppointmentSlots = onSchedule(
  { schedule: "every 30 minutes", timeZone: "Asia/Kolkata" },
  async () => {
    const db = getFirestore();
    const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata" }).format(new Date()); // yyyy-MM-dd
    const [appts, slots] = await Promise.all([
      db.collection("appointments").where("date", ">=", today).get(),
      db.collection("appointment_slots").where("date", ">=", today).get(),
    ]);
    const expected = new Map();
    appts.docs.forEach((d) => {
      const slot = _bookedSlotOf(d.data());
      if (slot && !expected.has(slot.key)) expected.set(slot.key, { ...slot, appointmentId: d.id });
    });
    const existing = new Map(slots.docs.map((d) => [d.id, d.data()]));

    let writer = db.batch();
    let ops = 0;
    let added = 0;
    let removed = 0;
    const flush = async () => { if (ops) { await writer.commit(); writer = db.batch(); ops = 0; } };
    for (const [key, slot] of expected) {
      const cur = existing.get(key);
      if (cur && cur.appointmentId === slot.appointmentId) continue;
      writer.set(db.collection("appointment_slots").doc(key), {
        doctorId: slot.doctorId, date: slot.date, time: slot.time, appointmentId: slot.appointmentId,
        updatedAt: FieldValue.serverTimestamp(),
      });
      added++;
      if (++ops >= 400) await flush();
    }
    for (const key of existing.keys()) {
      if (expected.has(key)) continue;
      writer.delete(db.collection("appointment_slots").doc(key));
      removed++;
      if (++ops >= 400) await flush();
    }
    await flush();
    console.log(JSON.stringify({ module: "appointment_slots", event: "reconciled", today, added, removed, total: expected.size }));
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

    // Emergency doctor creation is handled by onEmergencyDoctorRequest. The
    // one later status the patient must hear about is a doctor picking it up
    // ("Mark Handled" in the partner app's emergency_requests_screen.dart).
    if ((after.type || after.serviceType) === "emergency_doctor") {
      const emergencyPatientId = after.patientId || after.userId;
      if (after.status === "acknowledged" && emergencyPatientId) {
        const who = after.acknowledgedByName ? `Dr. ${after.acknowledgedByName}` : "A MedNU doctor";
        await _sendPatientNotification(getFirestore(), getMessaging(), emergencyPatientId, {
          title: "Doctor Responding",
          body: `${who} has picked up your emergency request and will contact you shortly.`,
          type: "emergency_acknowledged",
          serviceType: "emergency_doctor",
          bookingId: event.params.requestId,
          actionType: "open_service",
          extraData: { status: after.status },
        });
      }
      return;
    }
    // Internal-only status values — no user-facing notification needed.
    if (["duplicate", "notified", "pending"].includes(after.status)) return;
    // _rejectPinnedProviderNotAccepting already sent the patient its own message.
    if (after.status === "cancelled" && after.cancelReason === "provider_not_accepting") return;
    // Same for the vendor-less equipment rejection (_rejectEquipmentVendorRequired).
    if (after.status === "cancelled" && after.cancelReason === "equipment_vendor_required") return;
    // Same for the unpaid-previous-ambulance-trip block (onAmbulanceServiceRequestCreated).
    if (after.status === "cancelled" && after.cancelReason === "previous_trip_unpaid") return;

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
      equipment: {
        accepted:    ["Equipment Order Confirmed", "The vendor has accepted your equipment order and is preparing it.", "equipment_accepted"],
        in_progress: ["Equipment Out for Delivery", "Your equipment is on its way to you.", "equipment_out_for_delivery"],
        completed:   ["Equipment Order Complete", "Your equipment order has been completed. Thank you!", "equipment_completed"],
        rejected:    ["Equipment Order Declined", "The vendor could not fulfil your equipment order. Your payment will be refunded.", "equipment_rejected"],
        cancelled:   ["Equipment Order Cancelled", "Your equipment order has been cancelled.", "equipment_cancelled"],
      },
      lab_tests: {
        accepted:         ["Lab Booking Confirmed", "Your lab booking has been accepted. Our technician will visit you soon.", "lab_accepted"],
        assigned:         ["Technician Assigned", "A lab technician has been assigned to your booking.", "lab_assigned"],
        // Only ever reached from the lab's 'processing' step, *after*
        // sample collection (_LAB_TO_SERVICE_REQUEST_STATUS) — the patient
        // timeline labels this step "Processing" too.
        in_progress:      ["Sample Processing", "Your sample is being analysed at the lab.", "lab_processing"],
        sample_collected: ["Sample Collected", "Your sample has been collected and sent to the lab.", "lab_sample_collected"],
        report_ready:     ["Report Ready", "Your lab test report is now available. Tap to view.", "lab_report_ready"],
        completed:        ["Lab Test Completed", "Your lab test has been completed.", "lab_completed"],
        rejected:         ["Lab Booking Rejected", "Your lab booking could not be accepted. Please try again.", "lab_rejected"],
        cancelled:        ["Lab Booking Cancelled", "Your lab booking has been cancelled.", "lab_cancelled"],
      },
      diagnostics: {
        accepted:     ["Diagnostics Confirmed", "Your diagnostic booking has been accepted.", "lab_accepted"],
        assigned:     ["Technician Assigned", "A diagnostic technician has been assigned.", "lab_assigned"],
        in_progress:  ["Sample Processing", "Your sample is being analysed at the lab.", "lab_processing"],
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
        assigned:    ["Nurse Assigned", "A nurse has been assigned to you.", "caregiver_assigned"],
        in_progress: ["Home Care Started", "Your home care session has started.", "homecare_started"],
        completed:   ["Home Care Completed", "Your home care session has been completed.", "homecare_completed"],
        rejected:    ["Home Care Rejected", "Your home care request could not be accepted.", "homecare_rejected"],
        cancelled:   ["Home Care Cancelled", "Your home care booking has been cancelled.", "homecare_cancelled"],
      },
      nurse: {
        accepted:    ["Nurse Booking Accepted", "Your nurse request has been accepted.", "caregiver_accepted"],
        assigned:    ["Nurse Assigned", "A nurse has been assigned to you.", "caregiver_assigned"],
        in_progress: ["Nurse Service Started", "Your nurse has arrived and the service has started.", "caregiver_started"],
        completed:   ["Nurse Service Completed", "Your nurse service has been completed.", "caregiver_completed"],
        rejected:    ["Nurse Booking Rejected", "Your nurse booking could not be accepted.", "caregiver_rejected"],
        cancelled:   ["Nurse Booking Cancelled", "Your nurse booking has been cancelled.", "caregiver_cancelled"],
      },
      // The patient app never writes the literal type 'nurse' (singular)
      // — the cart checkout path writes 'care_assistant' or 'caregivers'
      // (see mednu/lib/features/cart/screens/cart_screen.dart). These two
      // keys reuse the `nurse` copy verbatim so real bookings get
      // tailored notification text instead of the generic fallback.
      care_assistant: {
        accepted:    ["Care Assistant Accepted", "Your care assistant has accepted your request.", "caregiver_accepted"],
        assigned:    ["Care Assistant Assigned", "A care assistant has been assigned to you.", "caregiver_assigned"],
        in_progress: ["Care Assistance Started", "Your care assistant has started the job.", "caregiver_started"],
        completed:   ["Care Assistance Completed", "Your care assistant job has been completed.", "caregiver_completed"],
        rejected:    ["Care Request Declined", "Your care assistant request could not be accepted.", "caregiver_rejected"],
        cancelled:   ["Care Assistant Booking Cancelled", "Your care assistant booking has been cancelled.", "caregiver_cancelled"],
      },
      caregivers: {
        accepted:    ["Nurse Booking Accepted", "Your nurse request has been accepted.", "caregiver_accepted"],
        assigned:    ["Nurse Assigned", "A nurse has been assigned to you.", "caregiver_assigned"],
        in_progress: ["Nurse Service Started", "Your nurse has arrived and the service has started.", "caregiver_started"],
        completed:   ["Nurse Service Completed", "Your nurse service has been completed.", "caregiver_completed"],
        rejected:    ["Nurse Booking Rejected", "Your nurse booking could not be accepted.", "caregiver_rejected"],
        cancelled:   ["Nurse Booking Cancelled", "Your nurse booking has been cancelled.", "caregiver_cancelled"],
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
        .replace("A nurse", assigneeName)
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
  _emitLog(severity, payload);
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
  let { amount, currency = "INR", receipt, purpose, tripRequestId } = request.data || {};

  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to start a payment.");
  }
  await _rateLimit(getFirestore(), `createRazorpayOrder:${uid}`, 20, 600);

  // Pay-after-trip (ambulance): the order is for the server-stored amount due
  // on THIS existing booking, never a client-sent figure. captureTripPayment
  // binds the order to the request via `purpose`.
  if (tripRequestId !== undefined && tripRequestId !== null) {
    const due = await _tripPaymentDue(getFirestore(), uid, tripRequestId);
    amount = Math.round(due.amountDue * 100);
    purpose = `trip:${due.id}`;
    receipt = `trip_${due.id}`.slice(0, 40);
  }

  if (!amount || typeof amount !== "number" || amount < 100) {
    throw new HttpsError("invalid-argument", "Amount must be a number ≥ 100 paise.");
  }

  // Early price check (checkout orders only): the payment screen passes the
  // booking context so a stale/tampered price is rejected BEFORE the customer
  // is charged at the gateway. capturePayment/captureCartPayment re-check
  // authoritatively (and bind the order amount), so omitting this context
  // gains a cheat nothing — see price notes above _expectedPriceFor.
  {
    const ctx = request.data || {};
    const db0 = getFirestore();
    const cartItems = Array.isArray(ctx.items) ? ctx.items : null;
    const single = typeof ctx.serviceType === "string" && typeof ctx.bookingCollection === "string" &&
      ctx.bookingData && typeof ctx.bookingData === "object" && !Array.isArray(ctx.bookingData);
    if (single) _assertBookingCollectionAllowed(ctx.bookingCollection);
    if (cartItems) {
      for (const it of cartItems) {
        if (it && typeof it.bookingCollection === "string") _assertBookingCollectionAllowed(it.bookingCollection);
      }
    }
    if ((cartItems && cartItems.length && cartItems.length <= 50) || single) {
      const enforce0 = await _priceCheckEnforced(db0);
      if (single && !cartItems) {
        const claimed = Number(ctx.originalAmount);
        if (Number.isFinite(claimed) && claimed > 0) {
          await _verifyBookingPrice(db0, {
            uid, serviceType: ctx.serviceType.trim(), bookingCollection: ctx.bookingCollection.trim(),
            bookingData: ctx.bookingData, claimedAmount: claimed, enforce: enforce0, source: "createRazorpayOrder",
          });
        }
      } else if (cartItems) {
        for (const it of cartItems) {
          const claimed = Number(it && it.amount);
          if (!it || typeof it.serviceType !== "string" || typeof it.bookingCollection !== "string" ||
              !it.bookingData || typeof it.bookingData !== "object" || !(claimed > 0)) continue;
          await _verifyBookingPrice(db0, {
            uid, serviceType: it.serviceType.trim(), bookingCollection: it.bookingCollection.trim(),
            bookingData: it.bookingData, claimedAmount: claimed, enforce: enforce0, source: "createRazorpayOrder",
          });
        }
      }
    }
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
  if (order.refundState) {
    // The reconciler already refunded this gateway charge to the original
    // payment method — crediting the wallet as well would pay it out twice.
    throw new HttpsError("failed-precondition", "This payment was refunded to your original payment method.");
  }

  const amount =Math.round(Number(order.amountPaise || 0)) / 100;
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
      if (ledgerSnap.exists || freshOrder.get("status") === "consumed" || freshOrder.get("refundState")) {
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

// ── Wallet: reverse an in-app debit whose booking capture failed ──────────────
//
// payment_screen debits MedNU Money / the main wallet via spendWalletBalance
// (idempotency keys `<base>-mm` / `<base>-w`) BEFORE calling capturePayment /
// captureCartPayment. If that capture then fails, this credits both legs back
// exactly once. It refuses when a payments doc exists for the attempt (the
// booking WAS captured) and when the debit entry does not exist for the caller.
// Ledger ids are deterministic, so retries are no-ops.
//
// Request data: { idempotencyKey: <base key>, razorpayPaymentId?: string }
// Response:     { success: true, refunded: <rupees>, alreadyRefunded?: true }
exports.refundWalletSpend = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const { idempotencyKey, razorpayPaymentId } = request.data || {};
  if (typeof idempotencyKey !== "string" || !idempotencyKey.trim() || idempotencyKey.length > 190) {
    throw new HttpsError("invalid-argument", "idempotencyKey is required.");
  }
  const base = idempotencyKey.trim();
  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);

  // Every payments doc id this attempt could have produced (see capturePayment
  // / captureCartPayment: `<method>:<uid>:<key>`, razorpay by payment id, cart
  // items `<cartId>:<i>`).
  const paymentIds = [
    _ledgerId(`already_settled:${uid}:${base}`),
    _ledgerId(`wallet:${uid}:${base}`),
    _ledgerId(`${_ledgerId(`already_settled:${uid}:${base}`)}:0`),
  ];
  if (typeof razorpayPaymentId === "string" && razorpayPaymentId.trim()) {
    const rzCart = _ledgerId(`razorpay:${razorpayPaymentId.trim()}`);
    paymentIds.push(rzCart, _ledgerId(`${rzCart}:0`));
  }

  const legs = [
    { walletType: "mednu_money", suffix: "-mm", label: "MedNU Money" },
    { walletType: "main", suffix: "-w", label: "wallet" },
  ].map((l) => {
    const spendSource = `spend:${uid}:${base}${l.suffix}`;
    const reverseSource = `spend_reversal:${uid}:${base}${l.suffix}`;
    return {
      ...l, reverseSource,
      spendRef: db.collection("wallet_ledger").doc(_ledgerId(spendSource)),
      reverseRef: db.collection("wallet_ledger").doc(_ledgerId(reverseSource)),
    };
  });

  try {
    const outcome = await db.runTransaction(async (t) => {
      const userSnap = await t.get(userRef);
      const paymentSnaps = await Promise.all(paymentIds.map((id) => t.get(db.collection("payments").doc(id))));
      const legSnaps = await Promise.all(legs.map(async (l) => ({
        spend: await t.get(l.spendRef), reverse: await t.get(l.reverseRef),
      })));

      if (paymentSnaps.some((s) => s.exists)) {
        throw new HttpsError("failed-precondition", "This booking was already recorded; nothing to refund.");
      }
      const toRefund = legs
        .map((l, i) => ({ ...l, ...legSnaps[i] }))
        .filter((l) => l.spend.exists && l.spend.get("uid") === uid && l.spend.get("type") === "debit");
      if (!toRefund.length) {
        throw new HttpsError("not-found", "No wallet debit found for this payment attempt.");
      }

      let refunded = 0;
      const balances = { walletBalance: _walletBalanceOf(userSnap, "walletBalance"),
                         mednuMoneyBalance: _walletBalanceOf(userSnap, "mednuMoneyBalance") };
      for (const l of toRefund) {
        if (l.reverse.exists) continue; // already reversed
        const amount = _round2(Number(l.spend.get("amount")) || 0);
        if (!(amount > 0)) continue;
        const field = _walletField(l.walletType);
        balances[field] = _round2(balances[field] + amount);
        refunded = _round2(refunded + amount);
        t.set(userRef, { [field]: balances[field] }, { merge: true });
        t.set(userRef.collection("transactions").doc(), _legacyTxDoc({
          title: "Payment Refunded", amount, type: "credit", category: "refund",
          description: "Booking could not be completed", walletType: l.walletType,
        }));
        t.set(l.reverseRef, _ledgerDoc({
          uid, walletType: l.walletType, type: "credit", amount, category: "refund",
          title: "Payment Refunded", description: "Booking could not be completed",
          source: l.reverseSource, balanceAfter: balances[field],
        }));
      }
      return { refunded, alreadyRefunded: refunded === 0 };
    });
    _logWallet("INFO", "wallet_spend_reversed", { uid, base, ...outcome });
    return { success: true, ...outcome };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    _logWallet("ERROR", "wallet_spend_reverse_failed", { uid, base, error: err.message });
    throw new HttpsError("internal", "Could not refund your wallet right now. Please contact support.");
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
// Shared payout: used by the callable below (legacy conditions) and by the
// first-booking trigger (`system: true`). `uid` is always the REFERRED user.
async function _grantReferralRewardCore(db, referralId, uid, { system = false } = {}) {
  const referralRef = db.collection("referrals").doc(referralId);

  // Reward amount is set by the admin at app_config/referral and read HERE, at
  // grant time (never from the referral doc or the client). Missing doc,
  // enabled !== true or amount 0 => nothing is granted and the referral stays
  // 'pending'. Only the REFERRER is rewarded.
  const cfgSnap = await db.collection("app_config").doc("referral").get();
  const rewardAmount = cfgSnap.exists && cfgSnap.get("enabled") === true
    ? _round2(Math.max(0, Number(cfgSnap.get("rewardAmount")) || 0)) : 0;
  if (!(rewardAmount > 0)) {
    return { success: true, granted: false };
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
      // First-booking referrals are paid ONLY by the server-side booking
      // trigger (_grantReferralOnFirstBooking), never on a client's say-so.
      if (r.triggerCondition === "first_booking" && !system) {
        throw new HttpsError("failed-precondition", "This reward is granted automatically after your first booking.");
      }

      const referrerId = typeof r.referrerId === "string" ? r.referrerId : "";
      if (!referrerId || referrerId === uid) {
        throw new HttpsError("failed-precondition", "Referral is malformed.");
      }

      const referrerReward = rewardAmount;
      const referredReward = 0; // the referred customer gets nothing

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
        rewardedAmount: referrerReward,
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
}

exports.grantReferralReward = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const { referralId } = request.data || {};
  if (typeof referralId !== "string" || !referralId.trim()) {
    throw new HttpsError("invalid-argument", "A referral id is required.");
  }
  return _grantReferralRewardCore(getFirestore(), referralId.trim(), uid);
});

// ── Referral: apply a code at sign-up (server-side lookup) ────────────────────
//
// `users` is owner-readable only, so the client can never look up the owner of
// a referral code. This does it with the Admin SDK: rejects unknown codes and
// self-referral, records `referredBy`/`referredByCode` on the caller's own
// user doc ONCE, and creates the `referrals/ref_<uid>` doc (status 'pending',
// triggerCondition 'first_booking'). The reward itself is paid by
// _grantReferralOnFirstBooking when that user's first booking is COMPLETED.
// Only the referrer is rewarded; the amount is the admin's app_config/referral
// rewardAmount, read at grant time.
//
// Request data: { code: string }
// Response:     { success: true, applied: boolean, reason?: string }
exports.applyReferralCode = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");
  const code = String(request.data?.code ?? "").trim().toUpperCase();
  if (!code || code.length > 32) throw new HttpsError("invalid-argument", "Enter a valid referral code.");

  const db = getFirestore();
  await _rateLimit(db, `applyReferralCode:${uid}`, 5, 3600);
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) throw new HttpsError("failed-precondition", "Complete your profile first.");
  if (userSnap.get("referredBy")) return { success: true, applied: false, reason: "already_applied" };

  const cfgSnap = await db.collection("referralConfig").doc("settings").get();
  const cfg = cfgSnap.exists ? cfgSnap.data() : {};
  if (cfg.referralEnabled === false) {
    throw new HttpsError("failed-precondition", "Referral program is currently inactive.");
  }
  const expiry = cfg.offerExpiryDate?.toDate?.();
  if (expiry && expiry.getTime() < Date.now()) {
    throw new HttpsError("failed-precondition", "Referral program is currently inactive.");
  }

  const ownerSnap = await db.collection("users").where("referralCode", "==", code).limit(1).get();
  if (ownerSnap.empty) throw new HttpsError("not-found", "Invalid referral code.");
  const referrerDoc = ownerSnap.docs[0];
  if (referrerDoc.id === uid) throw new HttpsError("invalid-argument", "You cannot use your own referral code.");

  const maxLimit = Number(cfg.maxReferralLimit) || 0;
  if (maxLimit > 0) {
    const used = await db.collection("referrals").where("referrerId", "==", referrerDoc.id).get();
    if (used.size >= maxLimit) {
      throw new HttpsError("failed-precondition", "This referral code has reached its limit.");
    }
  }

  const referralRef = db.collection("referrals").doc(`ref_${uid}`);
  const applied = await db.runTransaction(async (t) => {
    const [freshUser, existing] = await Promise.all([t.get(userRef), t.get(referralRef)]);
    if (freshUser.get("referredBy") || existing.exists) return false;
    t.set(referralRef, {
      referrerId: referrerDoc.id,
      referrerName: referrerDoc.get("name") || "",
      referredUserId: uid,
      referralCode: code,
      status: "pending",
      // Amount is NOT stored: it is read from app_config/referral at grant time.
      referrerRewardAmount: 0,
      referredRewardAmount: 0,
      triggerCondition: "first_booking",
      createdAt: FieldValue.serverTimestamp(),
      rewardedAt: null,
    });
    t.set(userRef, { referredBy: referrerDoc.id, referredByCode: code }, { merge: true });
    return true;
  });
  return { success: true, applied, ...(applied ? {} : { reason: "already_applied" }) };
});

// Pays the referral once the referred user's FIRST booking is completed. Idempotent
// twice over: the referral doc must still be 'pending', and the payout
// transaction writes deterministic `referral:<id>:*` ledger entries.
async function _grantReferralOnFirstBooking(patientId) {
  if (!patientId) return;
  const db = getFirestore();
  try {
    const snap = await db.collection("referrals")
      .where("referredUserId", "==", patientId).where("status", "==", "pending").limit(1).get();
    if (snap.empty || snap.docs[0].get("triggerCondition") !== "first_booking") return;
    await _grantReferralRewardCore(db, snap.docs[0].id, patientId, { system: true });
  } catch (err) {
    // Non-fatal (e.g. rewards currently disabled): stays 'pending' and is
    // retried when the patient's next booking completes.
    _logWallet("WARNING", "referral_first_booking_failed", { patientId, error: err.message });
  }
}
// Owner rule: the reward is paid when the referred user's FIRST booking is
// COMPLETED (not created). Fires only on the status transition INTO the
// collection's completed state; cancelled/other statuses never pay. The first
// booking to complete flips the referral out of 'pending', so later completed
// bookings find nothing pending and do nothing (no double pay).
function _completedReferralTrigger(collection, patientFields, completedStatuses) {
  return onDocumentUpdated(`${collection}/{docId}`, async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after || before.status === after.status) return;
    if (!completedStatuses.includes(after.status)) return;
    if (completedStatuses.includes(before.status)) return;
    const patientId = patientFields.map((f) => after[f]).find((v) => v);
    await _grantReferralOnFirstBooking(patientId);
  });
}
exports.onServiceRequestCompletedReferral = _completedReferralTrigger("service_requests", ["patientId", "userId"], ["completed"]);
exports.onAppointmentCompletedReferral = _completedReferralTrigger("appointments", ["patientId"], ["completed"]);
exports.onOrderCompletedReferral = _completedReferralTrigger("orders", ["patientId", "userId"], ["delivered", "completed"]);
exports.onNutritionAppointmentCompletedReferral = _completedReferralTrigger("nutrition_appointments", ["userId", "patientId"], ["completed"]);
exports.onConsultationCompletedReferral = _completedReferralTrigger("consultations", ["patientId"], ["completed", "ended"]);
exports.onHospitalAppointmentCompletedReferral = _completedReferralTrigger("hospital_appointments", ["patientId"], ["completed"]);

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
  equipment: "vendorId",
  ambulance: "ambulanceId",
  caregiver: "caregiverId",
  care_assistant: "caregiverId",
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

// Shared structured-log emitter. Cloud Logging reads `severity` (not `level`)
// from a JSON log line, so every module logger goes through here. `level` is
// kept on _logSettlement lines for backward compatibility. Event names are
// stable (alerts key on them).
function _emitLog(severity, payload) {
  const sev = String(severity || "INFO").toUpperCase();
  const line = JSON.stringify({ severity: sev, ...payload });
  if (sev === "ERROR" || sev === "CRITICAL") console.error(line);
  else if (sev === "WARNING") console.warn(line);
  else console.log(line);
}

function _logSettlement(level, event, data) {
  _emitLog(level, { level, module: "settlement", event, ...data });
}

async function _assertAdmin(db, uid) {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");
  const snap = await db.collection("admins").doc(uid).get();
  if (!snap.exists) throw new HttpsError("permission-denied", "Admin access required.");
  return snap;
}

// Fixed-window rate limiter backed by a transactional counter doc in
// `rate_limits/{sha256(key)}` (server-only: firestore.rules has a default-deny
// catch-all). Fields: count, windowStart (ms), expireAt (Timestamp, for a
// Firestore TTL policy on `expireAt`). Throws resource-exhausted when over
// `max` within `windowSec`. Fails OPEN: if the limiter itself errors, it logs a
// WARNING and allows the call so a limiter outage never blocks payments.
// The key is hashed so raw ids/IPs are never stored in document ids.
async function _rateLimit(db, key, max, windowSec) {
  let allowed = true;
  try {
    const id = crypto.createHash("sha256").update(`${key}|${windowSec}`).digest("hex");
    const ref = db.collection("rate_limits").doc(id);
    const nowMs = Date.now();
    const windowMs = windowSec * 1000;
    allowed = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const d = snap.exists ? snap.data() : null;
      if (!d || typeof d.windowStart !== "number" || nowMs - d.windowStart >= windowMs) {
        tx.set(ref, { count: 1, windowStart: nowMs, expireAt: Timestamp.fromMillis(nowMs + windowMs + 3600 * 1000) });
        return true;
      }
      if ((Number(d.count) || 0) >= max) return false;
      tx.update(ref, { count: (Number(d.count) || 0) + 1 });
      return true;
    });
  } catch (err) {
    _logSettlement("WARNING", "rate_limit_check_failed", { error: err && err.message });
    return;
  }
  if (!allowed) {
    throw new HttpsError("resource-exhausted", "Too many requests. Please try again later.");
  }
}

// Validates a client-supplied id before it is used in a `.doc(...)` path, where
// a '/' would silently change the path. Returns the id unchanged (no trimming).
function _safeId(value, label) {
  const name = label || "id";
  const v = typeof value === "string" ? value : "";
  if (!v || v.length > 128 || v.includes("/") || v.includes("..") || !/^[A-Za-z0-9_:.\-]+$/.test(v)) {
    throw new HttpsError("invalid-argument", `${name} is invalid.`);
  }
  return v;
}

// Role-gated admin check. admins/{uid}.role is one of director | hr | finance |
// support | marketing; a missing role means 'director' (same default the admin
// panel's verifyAdminRole uses). Returns the admin snapshot.
async function _assertAdminRole(db, uid, allowedRoles) {
  const snap = await _assertAdmin(db, uid);
  const role = snap.get("role") || "director";
  if (!allowedRoles.includes(role)) {
    const label = allowedRoles.map((r) => r.charAt(0).toUpperCase() + r.slice(1)).join(" or ");
    throw new HttpsError("permission-denied", `${label} access required.`);
  }
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
// Hospital earnings/settlement/appointment notifications are addressed to the
// hospital CATALOG id, but billing-desk logins are keyed by their own uid
// (`hospital_profiles/{uid}.hospitalId` links them). Resolves a catalog id to
// the active linked login uid(s); returns [] when none (or on any error).
async function _resolveHospitalRecipients(db, hospitalId) {
  try {
    const snap = await db.collection("hospital_profiles")
      .where("hospitalId", "==", String(hospitalId))
      .where("status", "==", "active")
      .limit(10).get();
    return snap.docs.map((d) => d.id).filter((id) => id !== hospitalId);
  } catch (_) {
    return [];
  }
}

// ── Freshest-token resolution for provider pushes ────────────────────────────
// A partner can hold several docs that each carry an `fcmToken` (doctors/{uid}
// plus one {role}_profiles/{uid} per role). The apps now write
// `fcmTokenUpdatedAt` alongside the token, so when the partner moves to a new
// phone the newest write wins. Candidates are returned best-first and
// de-duplicated by token string (refs = every doc holding that token, so a
// dead token can be cleaned from all of them).
const _PROVIDER_TOKEN_COLLECTIONS = [
  "doctors", "lab_profiles", "pharmacy_profiles", "ambulance_profiles", "caregiver_profiles",
  "nutritionist_profiles", "physiotherapist_profiles", "counsellor_profiles",
  "hospital_profiles", "equipment_profiles",
];
const _INVALID_FCM_TOKEN_CODES = [
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
];

async function _providerTokenCandidates(db, uid, collections = _PROVIDER_TOKEN_COLLECTIONS) {
  const snaps = await Promise.all(collections.map((col) =>
    db.collection(col).doc(uid).get().catch(() => null)));
  const byToken = new Map();
  snaps.forEach((snap, order) => {
    if (!snap || !snap.exists) return;
    const token = snap.get("fcmToken");
    if (!token || typeof token !== "string") return;
    const ts = snap.get("fcmTokenUpdatedAt");
    const ms = ts && typeof ts.toMillis === "function" ? ts.toMillis() : 0;
    const cur = byToken.get(token);
    if (cur) {
      cur.refs.push(snap.ref);
      if (ms > cur.ms) cur.ms = ms;
    } else {
      byToken.set(token, { token, ms, order, refs: [snap.ref] });
    }
  });
  // Newest timestamp first; missing timestamps (legacy) sort last, ties keep
  // collection order (doctors first).
  return [...byToken.values()].sort((a, b) => (b.ms - a.ms) || (a.order - b.order));
}

// Sends `message` (without `token`) to the freshest candidate. Only an
// invalid/unregistered-token error moves on to the next candidate (and deletes
// the dead token from every doc it came from); any other failure is logged.
// Returns true when a send succeeded. Never throws.
async function _sendToProviderCandidates(messaging, candidates, message, label = "provider") {
  for (const cand of candidates) {
    try {
      await messaging.send({ ...message, token: cand.token });
      return true;
    } catch (err) {
      if (_INVALID_FCM_TOKEN_CODES.includes(err && err.code)) {
        console.warn(`FCM token invalid for ${label}; removing it from ${cand.refs.map((r) => r.path).join(", ")}`);
        await Promise.all(cand.refs.map((ref) => ref.update({
          fcmToken: FieldValue.delete(),
          fcmTokenUpdatedAt: FieldValue.delete(),
          fcmPlatform: FieldValue.delete(),
        }).catch(() => {})));
        continue;
      }
      console.error(`FCM send failed for ${label}:`, err && err.message);
      return false;
    }
  }
  return false;
}

async function _sendProviderNotification(db, messaging, providerId, opts) {
  const { title, body, type, serviceType = "general", bookingId = "", extraData = {} } = opts;
  if (!providerId || !title || !body || !type) return;

  // Hospital service types: the id is a catalog id, so fan out to the linked
  // billing-desk uid(s) up front. `_hospitalResolved` stops recursion.
  if (!opts._hospitalResolved && String(serviceType).startsWith("hospital")) {
    const uids = await _resolveHospitalRecipients(db, providerId);
    if (uids.length) {
      await Promise.all(uids.map((u) =>
        _sendProviderNotification(db, messaging, u, { ...opts, _hospitalResolved: true })));
      return;
    }
  }

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

  // Providers may be doctors, labs, pharmacies, ambulances, caregivers, etc. —
  // each keeps its profile in its own collection. Pick the FRESHEST token
  // across all of them (new phone wins), de-duplicated.
  let tokenCandidates = [];
  try {
    tokenCandidates = await _providerTokenCandidates(db, providerId);
  } catch (_) {}
  if (!tokenCandidates.length) {
    // No direct token: the id may be a hospital catalog id (e.g. from a
    // settlement notification whose serviceType isn't hospital_*). Only then
    // pay for the hospital lookup, and never recurse twice.
    if (!opts._hospitalResolved) {
      const uids = await _resolveHospitalRecipients(db, providerId);
      await Promise.all(uids.map((u) =>
        _sendProviderNotification(db, messaging, u, { ...opts, _hospitalResolved: true })));
    }
    return;
  }

  await _sendToProviderCandidates(messaging, tokenCandidates, {
    notification: { title, body },
    data: Object.fromEntries(
      Object.entries({ type, serviceType, bookingId, ...extraData }).map(([k, v]) => [k, String(v)])
    ),
    android: { priority: "high" },
    apns: { payload: { aps: { sound: "default" } } },
  }, `provider ${providerId}`);
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
  // Optional per-profile predicate (receives the profile doc snapshot) for
  // verticals that share one profile collection between distinct roles, e.g.
  // Nurse vs Care Assistant in `caregiver_profiles`.
  profileFilter = null, excludeIds = [],
}) {
  let snap;
  try {
    snap = await db.collection(profileCollection).where("status", "==", "active").get();
  } catch (err) {
    console.error(`New-job broadcast: failed to query ${profileCollection}:`, err.message);
    return;
  }

  const providerIds = snap.docs
    .filter((d) => !excludeIds.includes(d.id) && (!profileFilter || profileFilter(d)))
    .map((d) => d.id);
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
// A patient cancelled a booking a provider had already claimed. The
// provider's own list updates live, but someone already travelling to the
// patient (technician, caregiver, driver, physio) needs an actual push.
// Best-effort: a failed push must never fail the cancel mirror itself.
async function _notifyProviderOfPatientCancel(db, providerId, { serviceType, bookingId, what }) {
  if (!providerId) return;
  try {
    await _sendProviderNotification(db, getMessaging(), providerId, {
      title: "Booking Cancelled by Patient",
      body: `The patient has cancelled this ${what}. No further action is needed.`,
      type: "booking_cancelled_by_patient",
      serviceType,
      bookingId,
      extraData: { cancelledBy: "patient" },
    });
  } catch (err) {
    console.error(`Patient-cancel push failed for provider ${providerId}:`, err.message);
  }
}

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

// State-changing write whose failure must never change the caller's outcome
// but must not be silent either: runs `fn`, retries once, then logs `event` at
// ERROR (and optionally raises an admin alert). Never throws; resolves true/false.
async function _guardedWrite(event, ctx, fn, alertOpts) {
  let lastErr = null;
  for (let i = 0; i < 2; i++) {
    try {
      await fn();
      return true;
    } catch (err) {
      lastErr = err;
    }
  }
  _logSettlement("ERROR", event, { ...ctx, error: lastErr && lastErr.message });
  if (alertOpts) {
    try {
      await _sendAdminAlert(getFirestore(), getMessaging(), alertOpts);
    } catch (e) {
      console.error(JSON.stringify({ severity: "ERROR", event: `${event}_alert_failed`, error: e && e.message }));
    }
  }
  return false;
}

// ── Settlement engine: fee-only model ─────────────────────────────────────────
//
// Owner decision: the platform earns ONLY the admin-set platform fee
// (app_config/platform_fee, per service type) that the patient app adds on top
// of the price. No commission is taken from providers: commission is always 0
// and providerAmount = paidAmount - platformFee (floor 0).
//
// Reads app_config/platform_fee inside a transaction (read phase). The fee is
// recomputed server-side with the same normalisation as the patient app.
async function _readCommissionRuleTx(db, tx) {
  // Name kept for call-site compatibility; it now returns the platform-fee config.
  return tx.get(db.collection("app_config").doc("platform_fee"));
}

// `feeSnap` is the snapshot from _readCommissionRuleTx. Pure: no I/O.
// `amount` = what the provider is settled against (paid amount, or the full
// pre-discount amount for free_consultation coupons). The fee is capped at the
// original (pre-discount) amount so a mis-set fee can never exceed the payment.
// `feeProviderId` (optional) enables the partner-specific fee override.
function _computeProviderSplit(feeSnap, serviceType, amount, originalAmount, feeProviderId) {
  const base = _round2(Math.max(0, Number(amount) || 0));
  const cfg = feeSnap && feeSnap.exists ? feeSnap.data() : null;
  const cap = _round2(Math.max(0, originalAmount === undefined ? base : Number(originalAmount) || 0));
  const platformFee = Math.min(PriceH.platformFeeFor(cfg, serviceType, feeProviderId), cap);
  const providerAmount = _round2(Math.max(0, base - platformFee));
  return {
    commission: 0, platformFee, providerAmount,
    baseAmount: _round2(Math.max(0, cap - platformFee)),
  };
}

// Back-compat wrapper (deprecated: fee-only model): commission is always 0.
function _computeCommissionFromRule(feeSnap, providerId, amount, serviceType, originalAmount) {
  const r = _computeProviderSplit(feeSnap, serviceType, amount, originalAmount, providerId);
  return { commission: 0, providerAmount: r.providerAmount, platformFee: r.platformFee, baseAmount: r.baseAmount };
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

// ── Server-authoritative pricing ─────────────────────────────────────────────
//
// The patient app sends the amount it wants to pay; nothing used to compare it
// with the real price. `_expectedPriceFor` derives the acceptable total from
// trusted Firestore data (provider/catalogue docs + app_config/platform_fee);
// `_verifyBookingPrice` rejects a mismatch BEFORE any money is recorded.
// Flag: settlement_config/global.enforcePriceCheck — enforced unless it is
// explicitly `false` (then mismatches are only logged as price_mismatch).
// Types whose price cannot be derived are skipped and logged price_check_skipped.
const PriceH = require("./price_helpers");
const _PRICE_ERR_MISMATCH = "Price mismatch. Please refresh and try again.";
const _PRICE_ERR_UNAVAILABLE = "One or more items are no longer available. Please refresh and try again.";
const _HOSPITAL_OP_DEFAULT_FEE = 99; // mirrors kHospitalOpFee in the patient app
const _AMBULANCE_DEFAULT_RATES = { basic: 500, als: 1200, icu: 2500 };
const _PRICED_SERVICE_TYPES = new Set([
  "ambulance", "physiotherapy", "counselling", "diagnostics", "lab_tests", "equipment",
  "equipment_hiring", "caregivers", "caregiver", "nursing", "home_care", "care_assistant",
]);
// Exactly the collections the patient app books into through PaymentScreen
// (grep `bookingCollection:` in mednu/lib). capturePayment / captureCartPayment
// create the booking doc in the collection the client names, so anything else
// would let a client write arbitrary docs (e.g. into `users`) as itself.
const _ALLOWED_BOOKING_COLLECTIONS = new Set([
  "appointments", "consultations", "service_requests", "orders",
  "nutrition_appointments", "hospital_appointments", "hospital_bill_payments",
]);
function _assertBookingCollectionAllowed(col) {
  if (typeof col !== "string" || !_ALLOWED_BOOKING_COLLECTIONS.has(col)) {
    throw new HttpsError("invalid-argument", "Unsupported booking collection.");
  }
}

// ── Prepaid weight-loss plan (nutrition subscription) ────────────────────────
// The customer pays the whole plan once: base = admin monthly price (diet_plans
// doc) x months, plus the platform fee ONCE. The dietician's own consultationFee
// is never charged for plan bookings. The monthly price is ALWAYS read here from
// the diet_plans doc; the client's price is only a hint and never trusted.
const PlanH = require("./plan_helpers");
const _PLAN_ERR_UPDATE = "Please update the app to buy this plan.";
const _PLAN_ERR_UNAVAILABLE = "This plan is not available right now. Please try again later.";

// Throws unless a nutrition booking that carries plan fields speaks the new
// contract (planContract === 2, months 2/4/6). No-op for every other booking.
function _assertPlanContract(bookingCollection, bd) {
  if (bookingCollection !== "nutrition_appointments" || !PlanH.isPlanBooking(bd)) return;
  const months = Number(bd.planMonths);
  if (Number(bd.planContract) !== PlanH.PLAN_CONTRACT || !PlanH.PLAN_MONTHS.includes(months)) {
    throw new HttpsError("failed-precondition", _PLAN_ERR_UPDATE);
  }
}

// Resolves the admin plan for a plan booking from trusted docs.
// Returns { planId, planTitle, monthly, months }. Throws HttpsError when the
// plan (or the dietician) cannot be read: the purchase is then refused, never
// priced from the dietician's fee.
async function _resolveWeightLossPlan(db, bd) {
  const months = Number(bd.planMonths);
  if (!PlanH.PLAN_MONTHS.includes(months)) throw new HttpsError("failed-precondition", _PLAN_ERR_UPDATE);
  const nid = typeof bd.nutritionistId === "string" && bd.nutritionistId.trim() && !bd.nutritionistId.includes("/")
    ? bd.nutritionistId.trim() : null;
  if (!nid) throw new HttpsError("failed-precondition", _PLAN_ERR_UNAVAILABLE);
  const [n1, n2] = await Promise.all([
    db.collection("nutritionists").doc(nid).get(),
    db.collection("nutritionist_profiles").doc(nid).get(),
  ]);
  if (!n1.exists && !n2.exists) throw new HttpsError("failed-precondition", _PLAN_ERR_UNAVAILABLE);

  const isWL = (d) => typeof d.title === "string" && d.title.toLowerCase().includes("weight loss");
  let planDoc = null;
  const claimed = typeof bd.planId === "string" && bd.planId.trim() && !bd.planId.includes("/") && bd.planId.length < 200
    ? bd.planId.trim() : null;
  if (claimed) {
    const s = await db.collection("diet_plans").doc(claimed).get();
    if (s.exists) planDoc = { id: s.id, ...s.data() };
  } else {
    const q = await db.collection("diet_plans").where("isActive", "==", true).limit(50).get();
    const list = q.docs.map((d) => ({ id: d.id, ...d.data() })).filter(isWL)
      .sort((a, b) => (Number(a.order) || 99) - (Number(b.order) || 99));
    planDoc = list[0] || null;
  }
  if (!planDoc || planDoc.isActive === false || !isWL(planDoc)) {
    throw new HttpsError("failed-precondition", _PLAN_ERR_UNAVAILABLE);
  }
  const monthly = PlanH.monthlyFromPrice(planDoc.price);
  if (monthly === null) throw new HttpsError("failed-precondition", _PLAN_ERR_UNAVAILABLE);
  return { planId: planDoc.id, planTitle: String(planDoc.title || "Weight Loss Plan"), monthly, months };
}

async function _nutritionPlanConfig(db) {
  try {
    const s = await db.collection("app_config").doc("nutrition_plans").get();
    const d = s.exists ? s.data() : {};
    return {
      refundUnused: d.refundUnused === true,
      lapsePolicy: d.lapsePolicy === "refund_to_wallet" ? "refund_to_wallet" : "forfeit",
    };
  } catch (err) {
    return { refundUnused: false, lapsePolicy: "forfeit" };
  }
}

// Builds the nutrition_subscriptions doc for a plan purchase (pure apart from
// the clock). Consultation #1 is the purchase booking itself (status 'booked').
// Callers add startedAt/createdAt server timestamps.
function _buildPlanSubscription({ plan, bd, uid, paymentId, platformFee, firstAppointmentId, mode, now = new Date() }) {
  const startDate = PlanH.istDateKey(now);
  const windows = PlanH.buildWindows(startDate, plan.months);
  // The first slot may sit a day or two past window 1 (date strip is ~30 days).
  const firstDate = typeof bd.date === "string" ? bd.date : null;
  if (firstDate && PlanH.parseKey(firstDate) && firstDate > windows[0].windowEnd) windows[0].windowEnd = firstDate;
  const consultations = windows.map((w) => ({
    index: w.index, windowStart: w.windowStart, windowEnd: w.windowEnd,
    status: w.index === 1 ? "booked" : "available",
    ...(w.index === 1 ? { appointmentId: firstAppointmentId } : {}),
  }));
  const lastEnd = windows[windows.length - 1].windowEnd;
  const endsAtDate = PlanH.addDaysKey(lastEnd, 1);
  return {
    doc: {
      patientId: uid,
      patientName: typeof bd.userName === "string" ? bd.userName.slice(0, 120) : "Patient",
      patientPhone: typeof bd.userPhone === "string" ? bd.userPhone.slice(0, 30) : "",
      nutritionistId: bd.nutritionistId,
      nutritionistName: typeof bd.nutritionistName === "string" ? bd.nutritionistName.slice(0, 120) : "",
      nutritionistSpecialization: typeof bd.nutritionistSpecialization === "string" ? bd.nutritionistSpecialization.slice(0, 120) : "",
      planType: PlanH.PLAN_TYPE, planId: plan.planId, planTitle: plan.planTitle,
      months: plan.months, monthlyPrice: plan.monthly, baseTotal: plan.monthly * plan.months,
      platformFee: platformFee || 0,
      paymentId: paymentId || null,
      paymentMode: mode, // 'paid' | 'not_required' (test mode)
      startDate, endsAtDate,
      endsAt: Timestamp.fromMillis(Date.parse(`${endsAtDate}T00:00:00+05:30`)),
      status: "active",
      consultations,
    },
  };
}

async function _priceCheckEnforced(db) {
  try {
    const s = await db.collection("settlement_config").doc("global").get();
    return !(s.exists && s.get("enforcePriceCheck") === false);
  } catch (err) {
    return true;
  }
}

// Returns {skipped, reason} | {unavailable, reason} | {specs:[...], platformFee}.
// `specs` are the acceptable TOTALS (base price + platform fee), see price_helpers.matchesSpec.
// `feeProviderId` MUST be the server-verified partner id (see
// PriceH.verifiedFeeProviderId) — never the raw client-supplied one.
async function _expectedPriceFor(db, serviceType, bookingCollection, bookingData, uid, feeProviderId = null) {
  const bd = bookingData && typeof bookingData === "object" ? bookingData : {};
  const sd = bd.serviceDetails && typeof bd.serviceDetails === "object" ? bd.serviceDetails : {};
  const skip = (reason) => ({ skipped: true, reason });
  const gone = (reason) => ({ unavailable: true, reason });
  const safeId = (v) => (typeof v === "string" && v.trim() && !v.includes("/") && v.length < 400 ? v.trim() : null);
  const getDoc = async (col, id) => {
    const s = await db.collection(col).doc(id).get();
    return s.exists ? s.data() : null;
  };

  const pfSnap = await db.collection("app_config").doc("platform_fee").get();
  const pfCfg = pfSnap.exists ? pfSnap.data() : null;
  const pf = PriceH.platformFeeFor(pfCfg, serviceType, feeProviderId);
  const exact =(base) => ({ specs: [{ type: "exact", value: base + pf }], platformFee: pf });
  const multiple = (units, maxQty = 100) => {
    const u = [...new Set(units.filter((x) => x > 0))];
    return u.length ? { specs: u.map((unit) => ({ type: "multiple", unit, maxQty, extra: pf })), platformFee: pf } : null;
  };
  const byName = async (types, name) => {
    const n = typeof name === "string" ? name.trim() : "";
    if (!n) return [];
    const q = await db.collection("services").where("name", "==", n).limit(20).get();
    return q.docs.map((d) => d.data()).filter((d) => types.includes(d.type));
  };

  // ── Collection-keyed bookings ──────────────────────────────────────────────
  if (bookingCollection === "appointments") {
    const id = safeId(bd.doctorId);
    if (!id) return gone("missing_doctor");
    const d = await getDoc("doctors", id);
    if (!d) return gone("doctor_not_found");
    const fee = PriceH.parseRupees(d.fee);
    if (fee === null || fee <= 0) return skip("doctor_fee_unavailable");
    const dur = [15, 30, 45, 60].includes(Number(bd.duration)) ? Number(bd.duration) : 30;
    return exact(PriceH.feeForDuration(Math.round(fee), dur));
  }
  if (bookingCollection === "consultations") {
    const id = safeId(bd.doctorId);
    if (!id) return gone("missing_provider");
    if (bd.providerRole === "physiotherapist") {
      const d = await getDoc("physiotherapists", id);
      if (!d) return gone("physio_not_found");
      const rate = PriceH.parseRupees(d.onlineRate);
      if (rate === null || rate <= 0) return skip("physio_online_rate_unavailable");
      return exact(Math.round(rate));
    }
    const d = await getDoc("doctors", id);
    if (!d) return gone("doctor_not_found");
    const fee = PriceH.parseRupees(d.fee);
    if (fee === null || fee <= 0) return skip("doctor_fee_unavailable");
    return exact(Math.round(fee));
  }
  if (bookingCollection === "nutrition_appointments") {
    if (PlanH.isPlanBooking(bd)) {
      // Prepaid plan: monthly (diet_plans) x months + the fee once.
      try {
        const plan = await _resolveWeightLossPlan(db, bd);
        return exact(plan.monthly * plan.months);
      } catch (err) {
        return gone("plan_unavailable");
      }
    }
    const id = safeId(bd.nutritionistId);
    if (!id) return gone("missing_nutritionist");
    const d = (await getDoc("nutritionists", id)) || (await getDoc("nutritionist_profiles", id));
    if (!d) return gone("nutritionist_not_found");
    const fee = PriceH.parseRupees(d.consultationFee);
    if (fee === null || fee <= 0) return skip("nutrition_fee_unavailable");
    return exact(Math.trunc(fee));
  }
  if (bookingCollection === "hospital_appointments") {
    // Flat OP fee in the app (kHospitalOpFee) — only underpayment is rejected.
    let base = _HOSPITAL_OP_DEFAULT_FEE;
    const cfg = await getDoc("settlement_config", "global");
    const cfgFee = cfg ? PriceH.parseRupees(cfg.hospitalOpFee) : null;
    if (cfgFee !== null && cfgFee > 0) base = cfgFee;
    return { specs: [{ type: "atLeast", value: base + pf }], platformFee: pf };
  }
  if (bookingCollection === "hospital_bill_payments") {
    return skip("hospital_bill_amount_entered_by_patient");
  }
  if (bookingCollection === "orders") {
    const items = Array.isArray(bd.items) ? bd.items : [];
    if (!items.length || items.length > 50) return gone("bad_order_items");
    const ids = items.map((i) => safeId(i && i.id));
    if (ids.some((x) => !x)) return gone("order_item_missing_id");
    const uniq = [...new Set(ids)];
    const snaps = await db.getAll(...uniq.map((id) => db.collection("medicines_catalogue").doc(id)));
    const priceById = {};
    for (const s of snaps) {
      if (!s.exists || s.get("isActive") === false) return gone("medicine_unavailable");
      priceById[s.id] = s.get("price");
    }
    const total = PriceH.sumLines(items.map((i, k) => ({ price: priceById[ids[k]], count: i.count })));
    if (total === null || !(total > 0)) return gone("bad_order_lines");
    return exact(total);
  }

  // ── service_requests: keyed by service type ────────────────────────────────
  if (bookingCollection === "service_requests") {
    const t = _PRICED_SERVICE_TYPES.has(serviceType) ? serviceType
      : (_PRICED_SERVICE_TYPES.has(bd.type) ? bd.type : serviceType);

    if (t === "ambulance") {
      const n = String(sd.ambulanceType || "").trim().toLowerCase();
      const key = n === "basic" ? "basic"
        : (n === "advanced life support" || n === "als") ? "als"
          : (n === "icu ambulance" || n === "icu") ? "icu" : null;
      if (!key) return gone("unknown_ambulance_type");
      const cfg = await getDoc("app_config", "ambulance_rates");
      const r = cfg && cfg.types && cfg.types[key];
      const min = r ? PriceH.parseRupees(r.min) : null;
      const max = r ? PriceH.parseRupees(r.max) : null;
      if (min !== null && max !== null && max >= min) {
        return { specs: [{ type: "range", min: min + pf, max: max + pf }], platformFee: pf };
      }
      return exact(_AMBULANCE_DEFAULT_RATES[key]);
    }
    if (t === "counselling") {
      const id = safeId(bd.counsellorId);
      if (!id) return gone("missing_counsellor");
      const d = await getDoc("counsellors", id);
      if (!d) return gone("counsellor_not_found");
      const rate = PriceH.parseRupees(d.hourlyRate);
      if (rate === null || rate <= 0) return skip("counsellor_rate_unavailable");
      return exact(Math.round(rate));
    }
    if (t === "physiotherapy") {
      if (sd.sessionType) {
        // Cart item priced from the admin `services` catalogue (no id carried).
        const docs = await byName(["physiotherapy"], bd.serviceName || sd.sessionType);
        const r = multiple(docs.map((d) => Math.trunc(Number(d.price) || 0)));
        return r || skip("physio_catalogue_entry_not_found");
      }
      const id = safeId(bd.physiotherapistId);
      if (!id) return gone("missing_physiotherapist");
      const d = await getDoc("physiotherapists", id);
      if (!d) return gone("physio_not_found");
      const field = { online: "onlineRate", home: "homeRate", clinic: "clinicRate" }[bd.consultMode] || "hourlyRate";
      const rate = PriceH.parseRupees(d[field]);
      if (rate === null || rate <= 0) return skip("physio_rate_unavailable");
      return exact(Math.round(rate));
    }
    if (t === "diagnostics" || t === "lab_tests") {
      const lab = safeId(sd.sourceLabId);
      const test = safeId(sd.sourceTestId);
      if (lab && test) {
        const d = await getDoc("lab_tests_catalogue", `ltinv_${lab}_${test}`);
        if (!d || d.isActive === false) return gone("lab_test_unavailable");
        return multiple([Math.trunc(Number(d.price) || 0)]) || skip("lab_test_price_unavailable");
      }
      const docs = await byName(["diagnostics", "lab_tests"], bd.serviceName || sd.testName);
      return multiple(docs.map((d) => Math.trunc(Number(d.price) || 0))) || skip("diagnostics_catalogue_entry_not_found");
    }
    if (t === "equipment" || t === "equipment_hiring") {
      const mode = sd.mode;
      if (mode !== "rent" && mode !== "buy") return gone("bad_equipment_mode");
      const days = Number(sd.rentalDays);
      if (mode === "rent" && !(Number.isInteger(days) && days >= 1 && days <= 365)) return gone("bad_rental_days");
      const unitOf = (d) => (mode === "rent" ? Math.trunc(Number(d.price) || 0) * days : Math.trunc(Number(d.purchasePrice) || 0));
      // Vendor-only equipment: a vendor + item is mandatory. The admin
      // catalogue is never priced by name any more (no vendor => unavailable).
      const v = safeId(sd.sourceVendorId);
      const it = safeId(sd.sourceItemId);
      if (!v || !it) return gone("equipment_vendor_required");
      const d = await getDoc("services", `eqi_${v}_${it}`);
      if (!d || d.isEnabled === false || safeId(d.sourceVendorId) !== v) return gone("equipment_unavailable");
      const units = [unitOf(d)].filter((x) => x > 0);
      if (!units.length) return skip("equipment_price_unavailable");
      const q = Number(sd.quantity);
      if (Number.isInteger(q) && q >= 1 && q <= 100) {
        return { specs: units.map((u) => ({ type: "exact", value: u * q + pf })), platformFee: pf };
      }
      return multiple(units);
    }
    if (["caregivers", "caregiver", "nursing", "home_care"].includes(t)) {
      const id = safeId(sd.sourceCaregiverId);
      if (!id) return gone("missing_caregiver");
      const d = await getDoc("caregivers", id);
      if (!d) return gone("caregiver_not_found");
      const day = Math.trunc(Number(d.ratePerDay) || 0);
      const hour = d.ratePerHour != null ? Math.trunc(Number(d.ratePerHour) || 0) : (day > 0 ? Math.floor(day / 8) : 0);
      const h12 = d.ratePer12Hr != null ? Math.trunc(Number(d.ratePer12Hr) || 0) : (hour > 0 ? hour * 12 : 0);
      const unit = ["morning", "evening", "night"].includes(sd.shiftType) ? day
        : ["day12", "night12"].includes(sd.shiftType) ? h12 : null;
      if (unit === null) return gone("bad_shift_type");
      return multiple([unit]) || skip("caregiver_rate_unavailable");
    }
    if (t === "care_assistant") {
      const id = safeId(sd.assistantId);
      if (!id) return gone("missing_assistant");
      const d = await getDoc("care_assistants", id);
      if (!d) return gone("assistant_not_found");
      const field = { hourly: "rateHourly", halfDay: "rateHalfDay", fullDay: "rateFullDay", multiDay: "rateMultiDay" }[sd.duration];
      if (!field) return gone("bad_assistant_duration");
      return multiple([Math.trunc(Number(d[field]) || 0)]) || skip("assistant_rate_unavailable");
    }
    // Unknown service type for a service_requests booking: never silently
    // skip the price check (that was a bypass). Rejected when enforcing.
    return { unavailable: true, unsupported: true, reason: "unsupported_service_type" };
  }
  return { unavailable: true, unsupported: true, reason: "unsupported_booking_collection" };
}

// Throws HttpsError on mismatch when enforcing. Returns {checked, platformFee}.
// Lookup failures never block a payment (logged, treated as skipped).
async function _verifyBookingPrice(db, { uid, serviceType, bookingCollection, bookingData, claimedAmount, enforce, source }) {
  // Partner id for the per-partner fee override, verified against trusted
  // docs. Unverifiable => null => service/default fee (never the client's id).
  let feeProviderId = null;
  try {
    const getDoc = async (col, id) => {
      const s = await db.collection(col).doc(id).get();
      return s.exists ? s.data() : null;
    };
    const v = await PriceH.verifiedFeeProviderId(getDoc, serviceType, bookingCollection, bookingData);
    feeProviderId = v.id || null;
    const claimedId = PriceH.feeProviderIdFor(serviceType, bookingData);
    if (!feeProviderId && claimedId) {
      _logSettlement("WARNING", "fee_provider_unverified", {
        uid, serviceType, bookingCollection, source, claimedId, reason: v.reason || "unverified",
      });
    } else if (feeProviderId && claimedId && feeProviderId !== claimedId) {
      _logSettlement("WARNING", "fee_provider_unverified", {
        uid, serviceType, bookingCollection, source, claimedId, verifiedId: feeProviderId, reason: "client_id_differs",
      });
    }
  } catch (err) {
    feeProviderId = null;
    _logSettlement("WARNING", "fee_provider_unverified", {
      uid, serviceType, bookingCollection, source, reason: "lookup_error", error: err.message,
    });
  }
  let exp;
  try {
    exp = await _expectedPriceFor(db, serviceType, bookingCollection, bookingData, uid, feeProviderId);
  } catch (err) {
    _logSettlement("ERROR", "price_check_error", { uid, serviceType, bookingCollection, source, error: err.message });
    return { checked: false, platformFee: 0, feeProviderId };
  }
  if (exp.skipped) {
    _logSettlement("INFO", "price_check_skipped", { uid, serviceType, bookingCollection, source, reason: exp.reason });
    return { checked: false, platformFee: 0, feeProviderId };
  }
  const bad = exp.unavailable || !PriceH.matchesAny(claimedAmount, exp.specs);
  if (bad) {
    _logSettlement("WARNING", "price_mismatch", {
      uid, serviceType, bookingCollection, source, claimedAmount, enforce,
      reason: exp.unavailable ? exp.reason : "amount_differs",
      expected: exp.unavailable ? null : exp.specs,
    });
    if (enforce) {
      if (exp.unsupported) throw new HttpsError("invalid-argument", "Unsupported service type.");
      throw new HttpsError("failed-precondition", exp.unavailable ? _PRICE_ERR_UNAVAILABLE : _PRICE_ERR_MISMATCH);
    }
    return { checked: false, platformFee: 0, feeProviderId };
  }
  return { checked: true, platformFee: exp.platformFee || 0, feeProviderId };
}

// Booking docs are written verbatim from the client's bookingData, and several
// partner-side triggers read the price straight off them (service_requests.amount,
// orders.total). After a successful check, stamp the server-known base price so a
// payer cannot pay the validated total yet record an inflated amount for payouts.
function _stampedPrice(bookingCollection, check, claimedAmount) {
  if (!check || !check.checked) return {};
  const base = _round2(claimedAmount - check.platformFee);
  if (!(base > 0)) return {};
  if (bookingCollection === "service_requests") return { amount: base };
  if (bookingCollection === "orders") return { total: base };
  return {};
}

// Wallet-leg verification. payment_screen debits MedNU Money / main wallet via
// spendWalletBalance with deterministic wallet_ledger ids derived from
// `spend:<uid>:<base>-mm` and `...-w` BEFORE capture, so a claimed
// walletPortionAmount can be proved: the ledger docs must exist, belong to this
// uid and be debits. Reads happen inside the capture transaction.
// Returns { sum, legs } or throws when enforcing and the claim is not backed.
async function _verifyWalletPortion(tx, db, { uid, baseKey, claimed, enforce, source }) {
  if (!(claimed > 0.005)) return { sum: 0, verified: true, legs: null };
  const key = typeof baseKey === "string" ? baseKey.trim() : "";
  let sum = 0;
  let legs = null;
  if (key && key.length <= 190) {
    const refs = ["-mm", "-w"].map((s) => db.collection("wallet_ledger").doc(_ledgerId(`spend:${uid}:${key}${s}`)));
    const snaps = await Promise.all(refs.map((r) => tx.get(r)));
    const docs = snaps.map((s) => (s.exists ? s.data() : null));
    sum = PriceH.sumVerifiedDebits(docs, uid);
    // Per-wallet split ({ main, mednuMoney }) so a refund can return each leg to
    // the balance it came from. Sums exactly to `claimed`, or null if unbacked.
    legs = PriceH.fitWalletLegs(PriceH.verifiedDebitLegs(docs, uid), claimed);
  }
  const ok = sum + 0.01 >= claimed;
  if (!ok) {
    _logSettlement("WARNING", "wallet_portion_unverified", { uid, source, claimed, found: sum, hasKey: !!key, enforce });
    if (enforce) {
      throw new HttpsError("failed-precondition", "Wallet payment could not be verified. Contact support.");
    }
  }
  return { sum, verified: ok, legs: ok ? legs : null };
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
exports.capturePayment = onCall({ enforceAppCheck: true }, _withCaptureRefund(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const {
    serviceType, bookingCollection, bookingData,
    originalAmount: rawOriginal, couponCode,
    paymentMethod,
    walletPortionAmount: rawWalletPortion,
    razorpay_order_id, razorpay_payment_id, razorpay_signature,
    idempotencyKey, walletDebitKey,
  } = request.data || {};

  if (typeof serviceType !== "string" || !serviceType.trim()) {
    throw new HttpsError("invalid-argument", "serviceType is required.");
  }
  if (typeof bookingCollection !== "string" || !bookingCollection.trim()) {
    throw new HttpsError("invalid-argument", "bookingCollection is required.");
  }
  _assertBookingCollectionAllowed(bookingCollection);
  if (!bookingData || typeof bookingData !== "object" || Array.isArray(bookingData)) {
    throw new HttpsError("invalid-argument", "bookingData is required.");
  }
  _assertPlanContract(bookingCollection, bookingData);
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

  const enforcePrice = await _priceCheckEnforced(db);
  // Prepaid weight-loss plan: resolve the real monthly price BEFORE any money
  // is recorded; an unreadable plan refuses the purchase (HttpsError).
  const isPlanPurchase = bookingCollection === "nutrition_appointments" && PlanH.isPlanBooking(bookingData);
  const planInfo = isPlanPurchase ? await _resolveWeightLossPlan(db, bookingData) : null;
  const planSubRef = isPlanPurchase ? db.collection("nutrition_subscriptions").doc(_ledgerId(`plansub:${paymentId}`)) : null;
  let outcome;
  try {
    outcome = await db.runTransaction(async (tx) => {
      // ── Reads ────────────────────────────────────────────────────────────
      const existingPayment = await tx.get(paymentRef);
      if (existingPayment.exists) {
        return { alreadyCaptured: true, payment: existingPayment.data() };
      }
      // Server-authoritative price check — before any money is recorded.
      const priceCheck = await _verifyBookingPrice(db, {
        uid, serviceType, bookingCollection, bookingData,
        claimedAmount: originalAmount, enforce: enforcePrice, source: "capturePayment",
      });
      // A plan is always price-enforced (the subscription is built from this
      // price), even when the global enforcePriceCheck flag is off.
      if (isPlanPurchase && !priceCheck.checked) {
        throw new HttpsError("failed-precondition", _PRICE_ERR_MISMATCH);
      }
      const couponSnap = couponRef ? await tx.get(couponRef) : null;
      const redemptionSnap = redemptionRef ? await tx.get(redemptionRef) : null;
      const userSnap = paymentMethod === "wallet" ? await tx.get(userRef) : null;
      const feeSnap = await _readCommissionRuleTx(db, tx);
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
      // The wallet / MedNU Money legs were debited by spendWalletBalance before
      // this call (see payment_screen). Prove the claimed portion from the
      // deterministic ledger entries instead of trusting the client's number.
      let walletLegs = null; // { main, mednuMoney } — which balance each wallet rupee came from
      if (paymentMethod !== "wallet" && walletPortionAmount > 0) {
        const walletCheck = await _verifyWalletPortion(tx, db, {
          uid, baseKey: paymentMethod === "razorpay" ? walletDebitKey : idempotencyKey,
          claimed: walletPortionAmount, enforce: enforcePrice, source: "capturePayment",
        });
        walletLegs = walletCheck.legs || null;
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
        if (orderSnap.get("refundState")) {
          throw new HttpsError("failed-precondition", "This payment is being refunded and can no longer be used.");
        }
        const orderedAmount = _round2(Number(orderSnap.get("amountPaise") || 0) / 100);
        if (Math.abs(orderedAmount - gatewayAmount) > 0.01) {
          _logSettlement("WARNING", "capture_amount_mismatch", {
            uid, orderedAmount, gatewayAmount, paidAmount, walletPortionAmount,
          });
          throw new HttpsError("failed-precondition", "Payment amount does not match the order. Contact support.");
        }
      }

      // ── Fee-only split (no commission): provider gets paid - platform fee ──
      const providerId = bookingData[_PROVIDER_FIELD_BY_SERVICE[serviceType]] || bookingData.providerId || null;
      const commissionBase = isFreeConsultation ? originalAmount : paidAmount;
      const { commission, platformFee, baseAmount, providerAmount } =
        _computeProviderSplit(feeSnap, serviceType, commissionBase, originalAmount,
          priceCheck.feeProviderId || null);

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

      // Prepaid plan: the purchase booking is consultation #1 of a new
      // subscription (server-built from the diet_plans price, never the client's).
      let planBookingFields = {};
      if (isPlanPurchase) {
        const sub = _buildPlanSubscription({
          plan: planInfo, bd: bookingData, uid, paymentId, platformFee,
          firstAppointmentId: bookingRef.id, mode: "paid",
        });
        tx.set(planSubRef, { ...sub.doc, startedAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp() });
        planBookingFields = {
          subscriptionId: planSubRef.id, planIndex: 1, planId: planInfo.planId,
          planMonths: planInfo.months, planConsultations: planInfo.months,
          planMonthlyPrice: planInfo.monthly, planBaseTotal: planInfo.monthly * planInfo.months,
          // The dietician earns an equal share per completed consultation.
          fee: PlanH.splitPayout(providerAmount, planInfo.months)[0] || 0,
        };
      }

      tx.set(bookingRef, {
        ...PriceH.sanitizeBookingData(bookingCollection, bookingData),
        ..._stampedPrice(bookingCollection, priceCheck, originalAmount),
        ...planBookingFields,
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
        paidAmount, walletPortionAmount, commissionBase, baseAmount, platformFee, commission, providerAmount,
        ...(walletLegs ? { walletLegs } : {}),
        commissionFinal: true,
        paymentMethod,
        razorpayPaymentId: paymentMethod === "razorpay" ? razorpay_payment_id : null,
        status: "completed",
        // A plan payment is never settled as a whole: each completed
        // consultation releases its share through a child `payments` doc
        // (see _completePlanConsultation). 'plan_hold' keeps it out of the queue.
        settlementStatus: isPlanPurchase ? "plan_hold" : "pending",
        ...(isPlanPurchase ? { planSubscriptionId: planSubRef.id, planMonths: planInfo.months } : {}),
        settlementId: null,
        createdAt: FieldValue.serverTimestamp(),
        completedAt: FieldValue.serverTimestamp(),
      };
      tx.set(paymentRef, paymentDoc);

      // Ledger — mirrors the spec's worked example: Payment Received /
      // Coupon Expense / Platform fee, written together as one batch.
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
        uid: "platform", walletType: "platform", type: "credit", amount: platformFee,
        category: "commission_reserved", title: "Platform fee",
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
}));

// ── Free (zero-price) bookings, server-created ───────────────────────────────
//
// While app_config/payments.requirePayment is ON, firestore.rules deny client
// creates of booking docs (rules cannot see the real price, so a client-written
// `fee: 0` would otherwise book a paid service for free). A booking whose REAL
// price is zero is therefore created here with the Admin SDK instead, after the
// server proves the price is zero. No payment doc / ledger / coupon logic.
//
// Free = the server-side price machinery reports the base price as
// zero/unset for the named provider/catalogue entry (the `*_unavailable` skip
// reasons of _expectedPriceFor, which are returned exactly when the provider's
// fee/rate is <= 0 or unparseable). Following the patient app's convention
// (payment_screen `_feeForBase`: base <= 0 never carries a platform fee) no
// platform fee applies to a zero base. Everything else - positive prices,
// missing provider docs, unsupported types, hospital_bill_payments and
// catalogue entries that cannot be priced - is refused.
const _FREE_BOOKING_ZERO_PRICE_REASONS = new Set([
  "doctor_fee_unavailable", "nutrition_fee_unavailable", "physio_online_rate_unavailable",
  "physio_rate_unavailable", "counsellor_rate_unavailable", "lab_test_price_unavailable",
  "equipment_price_unavailable", "caregiver_rate_unavailable", "assistant_rate_unavailable",
]);
const _FREE_BOOKING_STRIP_FIELDS = [
  "paymentId", "paymentStatus", "platformFee", "baseAmount", "amountDue", "fareFinal", "paidAt", "rxId",
];

exports.createFreeBooking = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");
  const { serviceType, bookingCollection, bookingData, idempotencyKey } = request.data || {};
  await _rateLimit(getFirestore(), `createFreeBooking:${uid}`, 30, 3600);

  if (typeof serviceType !== "string" || !serviceType.trim()) {
    throw new HttpsError("invalid-argument", "serviceType is required.");
  }
  _assertBookingCollectionAllowed(bookingCollection);
  if (bookingCollection === "hospital_bill_payments") {
    throw new HttpsError("failed-precondition", "This booking requires payment.");
  }
  if (!bookingData || typeof bookingData !== "object" || Array.isArray(bookingData)) {
    throw new HttpsError("invalid-argument", "bookingData is required.");
  }
  if (typeof idempotencyKey !== "string" || !idempotencyKey.trim() || idempotencyKey.length > 200) {
    throw new HttpsError("invalid-argument", "idempotencyKey is required.");
  }
  // A weight-loss plan is never free (priced from diet_plans, see
  // _expectedPriceFor); old builds without the plan contract get the update hint.
  _assertPlanContract(bookingCollection, bookingData);

  const db = getFirestore();

  // Verified partner id (never the client's), as in _verifyBookingPrice.
  let feeProviderId = null;
  try {
    const getDoc = async (col, id) => {
      const s = await db.collection(col).doc(id).get();
      return s.exists ? s.data() : null;
    };
    const v = await PriceH.verifiedFeeProviderId(getDoc, serviceType, bookingCollection, bookingData);
    feeProviderId = v.id || null;
  } catch (err) {
    feeProviderId = null;
  }

  let exp;
  try {
    exp = await _expectedPriceFor(db, serviceType, bookingCollection, bookingData, uid, feeProviderId);
  } catch (err) {
    _logSettlement("ERROR", "free_booking_price_error", { uid, serviceType, bookingCollection, error: err.message });
    throw new HttpsError("internal", "Could not verify the booking. Please try again.");
  }
  const isFree = !!(exp && exp.skipped && _FREE_BOOKING_ZERO_PRICE_REASONS.has(exp.reason));
  if (!isFree) {
    _logSettlement("WARNING", "free_booking_refused", {
      uid, serviceType, bookingCollection,
      reason: exp && (exp.reason || "priced"),
    });
    if (exp && exp.unavailable && !exp.unsupported) {
      throw new HttpsError("failed-precondition", _PRICE_ERR_UNAVAILABLE);
    }
    throw new HttpsError("failed-precondition", "This booking requires payment.");
  }

  const clean = PriceH.sanitizeBookingData(bookingCollection, bookingData);
  for (const f of _FREE_BOOKING_STRIP_FIELDS) delete clean[f];
  const isInPersonAppointment =
    bookingCollection === "appointments" && clean.consultationType === "In-Person";

  // Deterministic id: a retry with the same key returns the same booking.
  const bookingRef = db.collection(bookingCollection)
    .doc(_ledgerId(`freebooking:${uid}:${idempotencyKey.trim()}`));
  try {
    await db.runTransaction(async (tx) => {
      const existing = await tx.get(bookingRef);
      if (existing.exists) return;
      tx.set(bookingRef, {
        ...clean,
        ...(isInPersonAppointment ? { rxId: _generateOpRxId() } : {}),
        platformFee: 0,
        baseAmount: 0,
        patientId: uid,
        paymentStatus: "not_required",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    _logSettlement("ERROR", "free_booking_failed", { uid, serviceType, bookingCollection, error: err.message });
    throw new HttpsError("internal", "Could not create the booking. Please try again.");
  }
  _logSettlement("INFO", "free_booking_created", { uid, serviceType, bookingCollection, bookingId: bookingRef.id });
  return { bookingId: bookingRef.id };
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
  await _rateLimit(db, `validateCoupon:min:${uid}`, 10, 60);
  await _rateLimit(db, `validateCoupon:day:${uid}`, 50, 86400);
  const couponId = _safeId(couponCode.trim().toUpperCase(), "couponCode");
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
exports.captureCartPayment = onCall({ enforceAppCheck: true }, _withCaptureRefund(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const {
    items,
    couponCode,
    paymentMethod,
    walletPortionAmount: rawWalletPortion,
    razorpay_order_id, razorpay_payment_id, razorpay_signature,
    idempotencyKey, walletDebitKey,
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
    _assertBookingCollectionAllowed(it.bookingCollection);
    if (!it.bookingData || typeof it.bookingData !== "object" || Array.isArray(it.bookingData)) {
      throw new HttpsError("invalid-argument", `Item ${i}: bookingData is required.`);
    }
    // A prepaid plan builds a subscription: capturePayment only, never a cart.
    if (it.bookingCollection.trim() === "nutrition_appointments" && PlanH.isPlanBooking(it.bookingData)) {
      throw new HttpsError("failed-precondition", _PLAN_ERR_UPDATE);
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
    };
  });

  const enforcePrice = await _priceCheckEnforced(db);
  let outcome;
  try {
    outcome = await db.runTransaction(async (tx) => {
      // ── Reads ────────────────────────────────────────────────────────────
      const firstExisting = await tx.get(itemRefs[0].paymentRef);
      if (firstExisting.exists) {
        const allSnaps = await Promise.all(itemRefs.map((it) => tx.get(it.paymentRef)));
        return { alreadyCaptured: true, payments: allSnaps.map((s) => s.data()) };
      }
      // Server-authoritative price check per item — before any money is recorded.
      const priceChecks = [];
      for (const it of itemRefs) {
        priceChecks.push(await _verifyBookingPrice(db, {
          uid, serviceType: it.serviceType, bookingCollection: it.bookingCollection,
          bookingData: it.bookingData, claimedAmount: it.amount,
          enforce: enforcePrice, source: "captureCartPayment",
        }));
      }
      const couponSnap = couponRef ? await tx.get(couponRef) : null;
      const redemptionSnap = redemptionRef ? await tx.get(redemptionRef) : null;
      const userSnap = paymentMethod === "wallet" ? await tx.get(userRef) : null;
      const orderSnap = razorpayOrderRef ? await tx.get(razorpayOrderRef) : null;
      const feeSnap = await _readCommissionRuleTx(db, tx);

      // ── Coupon — applied once against the cart total; the discount is
      // prorated across items by each item's share of that total so
      // per-item provider amount still lands on the right number ───────────
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
      // Prove the claimed wallet / MedNU Money portion from the deterministic
      // wallet_ledger debits (same as capturePayment). Stays in the READ phase.
      let walletLegs = null; // order-level { main, mednuMoney }, split per item below
      if (paymentMethod !== "wallet" && walletPortionAmount > 0) {
        const walletCheck = await _verifyWalletPortion(tx, db, {
          uid, baseKey: paymentMethod === "razorpay" ? walletDebitKey : idempotencyKey,
          claimed: walletPortionAmount, enforce: enforcePrice, source: "captureCartPayment",
        });
        walletLegs = walletCheck.legs || null;
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
        if (orderSnap.get("refundState")) {
          throw new HttpsError("failed-precondition", "This payment is being refunded and can no longer be used.");
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
      let discountAllocated = 0;
      let walletAllocated = 0;
      let mednuMoneyAllocated = 0;
      itemRefs.forEach((it, i) => {
        const isLast = i === itemRefs.length - 1;
        const itemShare = originalAmount > 0 ? it.amount / originalAmount : 0;
        // Rounding remainder goes on the last item so per-item discounts sum
        // exactly to the cart discount (and itemPaid to paidAmount).
        const itemDiscount = isLast
          ? _round2(Math.max(0, discount - discountAllocated))
          : _round2(discount * itemShare);
        discountAllocated = _round2(discountAllocated + itemDiscount);
        const itemPaid = _round2(Math.max(0, it.amount - itemDiscount));
        // Each item's share of the (verified) wallet portion, so refunds split
        // gateway vs wallet per item; remainder on the last item.
        let itemWallet = 0;
        if (walletPortionAmount > 0 && paidAmount > 0) {
          itemWallet = isLast
            ? _round2(Math.max(0, walletPortionAmount - walletAllocated))
            : _round2(walletPortionAmount * itemPaid / paidAmount);
          itemWallet = Math.min(itemWallet, itemPaid);
          walletAllocated = _round2(walletAllocated + itemWallet);
        }
        const itemLegs = walletLegs && itemWallet > 0
          ? PriceH.itemWalletLegs(walletLegs, walletPortionAmount, itemWallet, mednuMoneyAllocated, isLast)
          : null;
        if (itemLegs) mednuMoneyAllocated = _round2(mednuMoneyAllocated + itemLegs.mednuMoney);
        const providerId =
          it.bookingData[_PROVIDER_FIELD_BY_SERVICE[it.serviceType]] || it.bookingData.providerId || null;
        // Same free_consultation exception as capturePayment: the provider
        // is paid as if the original (pre-discount) price had been paid in
        // full — this cart path previously always used `itemPaid` here,
        // which silently zeroed out every provider's payout on a cart
        // checkout using a free_consultation coupon instead of honouring it.
        const itemCommissionBase = isFreeConsultation ? it.amount : itemPaid;
        const { commission, platformFee, baseAmount, providerAmount } =
          _computeProviderSplit(feeSnap, it.serviceType, itemCommissionBase, it.amount,
            priceChecks[i].feeProviderId || null);

        tx.set(it.bookingRef, {
          ...PriceH.sanitizeBookingData(it.bookingCollection, it.bookingData),
          ..._stampedPrice(it.bookingCollection, priceChecks[i], it.amount),
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
          paidAmount: itemPaid, walletPortionAmount: itemWallet, commissionBase: itemCommissionBase, baseAmount, platformFee, commission, providerAmount,
          ...(itemLegs ? { walletLegs: itemLegs } : {}),
          commissionFinal: true,
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
          uid: "platform", walletType: "platform", type: "credit", amount: platformFee,
          category: "commission_reserved", title: "Platform fee",
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
}));

// ── Pay-after-trip (ambulance) ────────────────────────────────────────────────
//
// Real-mode ambulance bookings are created with paymentStatus 'pay_after_trip'
// and amount 0. On completion the server (onAmbulanceRequestStatusChange ->
// _recordAmbulanceFinalFare) records `fareFinal` (matched driver's rate clamped
// into the admin range), adds the platform fee and flips the booking to
// 'payment_due' with `amountDue`. Those fields are server-written only
// (firestore.rules blocks client create/update of them), so `amountDue` is the
// server-computed amount. captureTripPayment settles THAT existing booking —
// it must not use capturePayment, which creates a new booking doc.
async function _tripPaymentDue(db, uid, requestId) {
  if (typeof requestId !== "string" || !requestId.trim() || requestId.includes("/")) {
    throw new HttpsError("invalid-argument", "requestId is required.");
  }
  const snap = await db.collection("service_requests").doc(requestId.trim()).get();
  if (!snap.exists || snap.get("patientId") !== uid) {
    throw new HttpsError("permission-denied", "This booking does not belong to you.");
  }
  if (snap.get("type") !== "ambulance" || snap.get("paymentStatus") !== "payment_due") {
    throw new HttpsError("failed-precondition", "No payment is due for this booking.");
  }
  const amountDue = _round2(Number(snap.get("amountDue")));
  if (!Number.isFinite(amountDue) || amountDue <= 0) {
    throw new HttpsError("failed-precondition", "Amount due is not available yet. Please try again shortly.");
  }
  return { id: snap.id, data: snap.data(), amountDue };
}

// Request data: { requestId, paymentMethod: 'razorpay' | 'wallet',
//   razorpay_order_id?, razorpay_payment_id?, razorpay_signature?, idempotencyKey? }
// (walletPortionAmount is accepted but must be 0: trip payments are either
// fully wallet or fully gateway.) Replaying the same razorpay payment id /
// idempotencyKey returns the same result without moving money twice.
exports.captureTripPayment = onCall({ enforceAppCheck: true }, _withCaptureRefund(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const {
    requestId, paymentMethod, walletPortionAmount: rawWalletPortion,
    razorpay_order_id, razorpay_payment_id, razorpay_signature, idempotencyKey,
  } = request.data || {};

  if (!["razorpay", "wallet"].includes(paymentMethod)) {
    throw new HttpsError("invalid-argument", "Unknown payment method.");
  }
  if (rawWalletPortion !== undefined && Number(rawWalletPortion) !== 0) {
    throw new HttpsError("invalid-argument", "Trip payments cannot be split between wallet and gateway.");
  }
  const rid = typeof requestId === "string" ? requestId.trim() : "";
  if (!rid || rid.includes("/")) throw new HttpsError("invalid-argument", "requestId is required.");

  const db = getFirestore();
  const messaging = getMessaging();

  let paymentIdSource;
  let razorpayOrderRef = null;
  if (paymentMethod === "razorpay") {
    if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
      throw new HttpsError("invalid-argument", "Missing Razorpay verification fields.");
    }
    const expected = crypto.createHmac("sha256", process.env.RAZORPAY_KEY_SECRET)
      .update(`${razorpay_order_id}|${razorpay_payment_id}`).digest("hex");
    if (expected !== razorpay_signature) {
      _logSettlement("WARNING", "trip_capture_signature_mismatch", { uid, orderId: razorpay_order_id });
      throw new HttpsError("unauthenticated", "Payment signature verification failed.");
    }
    paymentIdSource = `razorpay:${razorpay_payment_id}`;
    razorpayOrderRef = db.collection("razorpay_orders").doc(String(razorpay_order_id));
  } else {
    if (typeof idempotencyKey !== "string" || !idempotencyKey.trim() || idempotencyKey.length > 200) {
      throw new HttpsError("invalid-argument", "idempotencyKey is required.");
    }
    paymentIdSource = `wallet:${uid}:${idempotencyKey.trim()}`;
  }

  const paymentId = _ledgerId(paymentIdSource);
  const paymentRef = db.collection("payments").doc(paymentId);
  const userRef = db.collection("users").doc(uid);
  const requestRef = db.collection("service_requests").doc(rid);

  let outcome;
  try {
    outcome = await db.runTransaction(async (tx) => {
      // ── Reads ──────────────────────────────────────────────────────────
      const existingPayment = await tx.get(paymentRef);
      if (existingPayment.exists) {
        const ref = existingPayment.get("bookingRef");
        if (!ref || ref.id !== rid || existingPayment.get("patientId") !== uid) {
          throw new HttpsError("failed-precondition", "This payment was already used for another booking.");
        }
        return { alreadyCaptured: true, payment: existingPayment.data() };
      }
      const reqSnap = await tx.get(requestRef);
      if (!reqSnap.exists || reqSnap.get("patientId") !== uid) {
        throw new HttpsError("permission-denied", "This booking does not belong to you.");
      }
      if (reqSnap.get("type") !== "ambulance" || reqSnap.get("paymentStatus") !== "payment_due") {
        throw new HttpsError("failed-precondition", "No payment is due for this booking.");
      }
      // Server-computed amount (written at trip completion) — never client input.
      const amountDue = _round2(Number(reqSnap.get("amountDue")));
      const fareFinal = _round2(Number(reqSnap.get("fareFinal")));
      const platformFee = _round2(Number(reqSnap.get("platformFee")) || 0);
      if (!(amountDue > 0) || !(fareFinal > 0)) {
        throw new HttpsError("failed-precondition", "Amount due is not available yet. Please try again shortly.");
      }
      const providerId = reqSnap.get("assignedTo") || null;
      if (!providerId) {
        throw new HttpsError("failed-precondition", "This trip has no assigned ambulance.");
      }
      const userSnap = paymentMethod === "wallet" ? await tx.get(userRef) : null;
      const orderSnap = razorpayOrderRef ? await tx.get(razorpayOrderRef) : null;

      if (paymentMethod === "wallet") {
        if (_walletBalanceOf(userSnap, "walletBalance") < amountDue) {
          throw new HttpsError("failed-precondition", "Insufficient wallet balance.");
        }
      } else {
        if (!orderSnap || !orderSnap.exists) {
          throw new HttpsError("failed-precondition", "Payment order not found. Contact support.");
        }
        if (orderSnap.get("uid") !== uid) {
          _logSettlement("WARNING", "trip_capture_order_uid_mismatch", { uid, orderUid: orderSnap.get("uid") });
          throw new HttpsError("permission-denied", "This payment order does not belong to you.");
        }
        // The order must have been created for THIS booking and for the amount due.
        if (orderSnap.get("purpose") !== `trip:${rid}` || orderSnap.get("status") === "consumed" ||
            orderSnap.get("refundState")) {
          throw new HttpsError("failed-precondition", "Payment order does not match this booking. Contact support.");
        }
        const orderedAmount = _round2(Number(orderSnap.get("amountPaise") || 0) / 100);
        if (Math.abs(orderedAmount - amountDue) > 0.01) {
          _logSettlement("WARNING", "trip_capture_amount_mismatch", { uid, orderedAmount, amountDue });
          throw new HttpsError("failed-precondition", "Payment amount does not match the amount due. Contact support.");
        }
      }

      // Fee-only model: provider earns the trip fare, the platform keeps the
      // platform fee recorded on the booking at completion; no commission.
      const commissionBase = amountDue;
      const commission = 0;
      const baseAmount = fareFinal;
      const providerAmount = fareFinal;

      // ── Writes ─────────────────────────────────────────────────────────
      if (paymentMethod === "wallet") {
        const balance = _walletBalanceOf(userSnap, "walletBalance");
        tx.set(userRef, { walletBalance: _round2(balance - amountDue) }, { merge: true });
        tx.set(userRef.collection("transactions").doc(), _legacyTxDoc({
          title: "Ambulance Trip Payment", amount: amountDue, type: "debit",
          category: "booking_payment", walletType: "main",
        }));
      }
      if (razorpayOrderRef) {
        tx.update(razorpayOrderRef, {
          status: "consumed", paymentId: razorpay_payment_id, consumedAt: FieldValue.serverTimestamp(),
        });
      }

      const paymentDoc = {
        paymentId, patientId: uid, providerId, serviceType: "ambulance",
        bookingRef: { collection: "service_requests", id: rid },
        originalAmount: amountDue, discount: 0, couponCode: null,
        paidAmount: amountDue, walletPortionAmount: paymentMethod === "wallet" ? amountDue : 0,
        commissionBase, baseAmount, platformFee, commission, providerAmount,
        // Trip wallet payments are debited from the MAIN wallet by this function.
        ...(paymentMethod === "wallet" ? { walletLegs: { main: amountDue, mednuMoney: 0 } } : {}),
        commissionFinal: true,
        paymentMethod,
        razorpayPaymentId: paymentMethod === "razorpay" ? razorpay_payment_id : null,
        status: "completed",
        settlementStatus: "pending",
        settlementId: null,
        createdAt: FieldValue.serverTimestamp(),
        completedAt: FieldValue.serverTimestamp(),
      };
      tx.set(paymentRef, paymentDoc);
      tx.update(requestRef, {
        paymentId, paymentStatus: "paid", paidAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid, walletType: "platform", type: "credit", amount: amountDue,
        category: "payment_received", title: "Payment Received",
        description: "ambulance", source: `payment:${paymentId}:received`, balanceAfter: null,
      }));
      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid: "platform", walletType: "platform", type: "credit", amount: platformFee,
        category: "commission_reserved", title: "Platform fee",
        description: "ambulance", source: `payment:${paymentId}:commission`, balanceAfter: null,
      }));

      return {
        alreadyCaptured: false, payment: paymentDoc, providerId, fareFinal,
        patientName: reqSnap.get("patientName"),
      };
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    _logSettlement("ERROR", "capture_trip_payment_failed", { uid, requestId: rid, error: err.message });
    _sendAdminAlert(db, messaging, {
      title: "Failed Payment", body: `captureTripPayment failed for ${rid}: ${err.message}`,
      type: "failed_payment", extraData: { uid, requestId: rid },
    }).catch(() => {});
    throw new HttpsError("internal", "Payment could not be recorded. Contact support before retrying.");
  }

  if (!outcome.alreadyCaptured) {
    // Single provider credit path = settlement: makes this payment 'eligible'
    // and credits provider_wallets.pendingEarnings exactly once.
    try {
      await _transitionPaymentToEligible(db, {
        sourceCollection: "service_requests", sourceId: rid,
        providerId: outcome.providerId, serviceType: "ambulance",
      });
    } catch (err) {
      _logSettlement("ERROR", "trip_payment_eligible_failed", { requestId: rid, error: err.message });
    }
    // The partner's legacy earnings ledger was deferred at completion for this
    // booking; write it now (create() never duplicates).
    try {
      await db.collection("ambulance_transactions").doc(rid).create({
        ambulanceId: outcome.providerId, requestId: rid, type: "earning",
        amount: outcome.fareFinal, status: "credited",
        patientName: outcome.patientName || "Patient",
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (err) {
      if (err.code !== 6 && !/already exists/i.test(String(err.message))) {
        _logSettlement("WARNING", "trip_ledger_write_failed", { requestId: rid, error: err.message });
      }
    }
    _sendPatientNotification(db, messaging, uid, {
      title: "Payment Successful",
      body: `₹${outcome.payment.paidAmount.toFixed(0)} paid for your ambulance trip.`,
      type: "payment_successful", serviceType: "ambulance", bookingId: rid,
    }).catch(() => {});
  }
  _logSettlement("INFO", outcome.alreadyCaptured ? "trip_capture_replay" : "trip_capture_success", {
    paymentId, uid, requestId: rid, paidAmount: outcome.payment.paidAmount,
  });
  return { paymentId, bookingId: rid, ...outcome.payment };
}));

// ── Automatic Razorpay refund: charged at the gateway, booking not recorded ───
//
// OWNER-APPROVED money-safety net. If the customer completed the Razorpay
// payment (valid signature) but the booking could not be recorded — capture*
// rejected after the charge, or the client died before calling capture at all —
// the gateway charge is refunded to the ORIGINAL payment method.
//
// What is NOT refunded here (deliberately):
//  - signature mismatch (payment not proven), order owned by another user;
//  - payments that were recorded (razorpay_orders.status 'consumed' / a
//    payments doc with that razorpayPaymentId): those go through
//    _refundPayment (admin issueRefund / _autoRefundBooking) as before;
//  - the wallet / MedNU Money legs of a split payment: refundWalletSpend does
//    those. Only the GATEWAY amount (razorpay_orders.amountPaise) is refunded
//    here, so nothing can be refunded twice across the two mechanisms.
//
// Idempotency: razorpay_refunds/{razorpayPaymentId} is claimed in a transaction
// BEFORE the gateway call (requested -> succeeded | failed | not_refundable);
// the order doc gets `refundState` in the same transaction, which every
// capture transaction checks, so a later capture retry can't book a payment
// that was refunded. Before refunding, the payment is fetched from Razorpay and
// only the still-unrefunded remainder is requested.
const RzpRefund = require("./razorpay_refund_helpers");

function _rupeesLabel(paise) {
  return `₹${(paise / 100).toFixed(paise % 100 === 0 ? 0 : 2)}`;
}

// Returns { status: 'succeeded'|'requested'|'failed'|'skipped'|'not_refundable', refundId?, reason? }
// Never throws.
async function _refundRazorpayPayment(db, { paymentId, amountPaise, reason, orderId, uid, allowRetry = false }) {
  const messaging = getMessaging();
  if (typeof paymentId !== "string" || !paymentId.trim() || paymentId.includes("/")) {
    return { status: "skipped", reason: "bad_payment_id" };
  }
  const refundRef = db.collection("razorpay_refunds").doc(paymentId);
  const orderRef = orderId ? db.collection("razorpay_orders").doc(String(orderId)) : null;
  let claimed;
  try {
    claimed = await db.runTransaction(async (tx) => {
      const refundSnap = await tx.get(refundRef);
      const orderSnap = orderRef ? await tx.get(orderRef) : null;
      const recorded = await tx.get(db.collection("payments").where("razorpayPaymentId", "==", paymentId).limit(1));
      if (recorded && !recorded.empty) return { go: false, why: "payment_recorded" };
      if (orderSnap && orderSnap.exists && orderSnap.get("status") === "consumed") return { go: false, why: "order_consumed" };
      const prev = refundSnap.exists ? refundSnap.data() : null;
      const decision = RzpRefund.decideRefundClaim(
        prev ? { ...prev, requestedAtMs: prev.requestedAtMs } : null, Date.now(), { allowRetry });
      if (decision !== "claim") return { go: false, why: prev ? `already_${prev.status}` : "skip", prev };
      tx.set(refundRef, {
        paymentId, orderId: orderId || null, uid: uid || null,
        amountPaise: Math.round(Number(amountPaise) || 0),
        reason: String(reason || "capture_failed").slice(0, 300),
        status: "requested", attempts: (prev ? Number(prev.attempts) || 1 : 0) + 1,
        requestedAt: FieldValue.serverTimestamp(), requestedAtMs: Date.now(),
        createdAt: prev && prev.createdAt ? prev.createdAt : FieldValue.serverTimestamp(),
      });
      if (orderSnap && orderSnap.exists) tx.update(orderRef, { refundState: "refunding" });
      return { go: true };
    });
  } catch (err) {
    _logSettlement("ERROR", "razorpay_refund_claim_failed", { paymentId, orderId, error: err.message });
    _sendAdminAlert(db, messaging, {
      title: "Razorpay Auto-Refund Needs Manual Action",
      body: `Payment ${paymentId} (order ${orderId || "?"}) was charged but not booked and the auto-refund could not start: ${err.message}. Refund it manually in Razorpay.`,
      type: "razorpay_auto_refund_failed", extraData: { paymentId, orderId: orderId || "", uid: uid || "" },
    }).catch(() => {});
    return { status: "failed", reason: "claim_failed" };
  }
  if (!claimed.go) {
    const prev = claimed.prev;
    return { status: prev && prev.status === "succeeded" ? "succeeded" : "skipped", reason: claimed.why };
  }

  const fail = async (msg, alertTitle) => {
    await _guardedWrite("refund_marker_write_failed", { paymentId, orderId, marker: "failed" },
      () => refundRef.set({ status: "failed", error: String(msg).slice(0, 500), failedAt: FieldValue.serverTimestamp() }, { merge: true }));
    if (orderRef) {
      await _guardedWrite("refund_state_write_failed", { paymentId, orderId, refundState: "refund_failed" },
        () => orderRef.update({ refundState: "refund_failed" }));
    }
    _logSettlement("ERROR", "razorpay_auto_refund_failed", { paymentId, orderId, error: String(msg) });
    _sendAdminAlert(db, messaging, {
      title: alertTitle || "Razorpay Auto-Refund Needs Manual Action",
      body: `Payment ${paymentId} (order ${orderId || "?"}, customer ${uid || "?"}) was charged at the gateway but the booking was not recorded, and the automatic refund failed: ${msg}. Refund it manually in Razorpay.`,
      type: "razorpay_auto_refund_failed", extraData: { paymentId, orderId: orderId || "", uid: uid || "" },
    }).catch(() => {});
    return { status: "failed", reason: String(msg) };
  };

  try {
    const razorpay = new Razorpay({ key_id: process.env.RAZORPAY_KEY_ID, key_secret: process.env.RAZORPAY_KEY_SECRET });
    const pay = await razorpay.payments.fetch(paymentId);
    if (orderId && pay.order_id && pay.order_id !== orderId) {
      return await fail("payment does not belong to this order");
    }
    if (pay.status !== "captured" && pay.status !== "refunded") {
      // 'authorized' is voided by Razorpay itself after its auto-refund window;
      // 'created'/'failed' means no money was taken. Nothing to refund via API.
      await refundRef.set({ status: "not_refundable", gatewayStatus: pay.status, completedAt: FieldValue.serverTimestamp() }, { merge: true });
      if (orderRef) {
        await _guardedWrite("refund_state_write_failed", { paymentId, orderId, refundState: pay.status },
          () => orderRef.update({ refundState: pay.status === "authorized" ? "authorized_auto_void" : FieldValue.delete() }));
      }
      if (pay.status === "authorized") {
        _sendAdminAlert(db, messaging, {
          title: "Razorpay Payment Authorized, Not Captured",
          body: `Payment ${paymentId} (order ${orderId || "?"}) is only authorized and its booking was not recorded; Razorpay will auto-refund it, or void it in the dashboard.`,
          type: "razorpay_auto_refund_failed", extraData: { paymentId, orderId: orderId || "", uid: uid || "" },
        }).catch(() => {});
      }
      return { status: "not_refundable", reason: `gateway_${pay.status}` };
    }
    const calc = RzpRefund.computeRefundAmount({
      orderAmountPaise: amountPaise, paymentAmountPaise: pay.amount, alreadyRefundedPaise: pay.amount_refunded,
    });
    let refundId = null;
    let refundedPaise = Number(pay.amount_refunded) || 0;
    if (!calc.alreadyDone) {
      if (!(calc.amount > 0)) return await fail("nothing refundable on this payment");
      const rf = await razorpay.payments.refund(paymentId, {
        amount: calc.amount, speed: "normal",
        notes: { reason: String(reason || "capture_failed").slice(0, 200), orderId: String(orderId || "") },
      });
      refundId = rf && rf.id ? rf.id : null;
      refundedPaise = calc.amount;
    }
    await refundRef.set({
      status: "succeeded", refundId, refundedPaise, completedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    if (orderRef) {
      await _guardedWrite("refund_state_write_failed", { paymentId, orderId, refundState: "refunded", refundId },
        () => orderRef.update({ refundState: "refunded", refundId, refundedAt: FieldValue.serverTimestamp() }), {
          title: "Refund Done But Order State Not Updated",
          body: `Payment ${paymentId} (order ${orderId || "?"}) was refunded at Razorpay (refund ${refundId || "?"}) but the order record could not be updated. No money action is needed; check the order document.`,
          type: "refund_state_write_failed", extraData: { paymentId, orderId: orderId || "", uid: uid || "" },
        });
    }
    _logSettlement("INFO", "razorpay_auto_refund_succeeded", { paymentId, orderId, refundId, refundedPaise });
    if (uid && refundedPaise > 0) {
      _sendPatientNotification(db, messaging, uid, {
        title: "Payment Refunded",
        body: `We have refunded ${_rupeesLabel(refundedPaise)} to your original payment method. It can take 5-7 working days to reflect.`,
        type: "refund_processed", bookingId: String(orderId || paymentId),
      }).catch(() => {});
    }
    return { status: "succeeded", refundId };
  } catch (err) {
    const msg = (err && (err.error && err.error.description || err.message)) || "unknown gateway error";
    return await fail(msg);
  }
}

// Called from a capture* wrapper after a rejection. Only refunds a payment
// whose signature was verified, whose order belongs to `uid` and that was not
// recorded. Never throws.
async function _refundAfterCaptureFailure(db, { uid, orderId, paymentId, reason }) {
  try {
    const orderSnap = await db.collection("razorpay_orders").doc(String(orderId)).get();
    if (!orderSnap.exists || orderSnap.get("uid") !== uid) return { status: "skipped", reason: "order_not_owned" };
    if (orderSnap.get("status") === "consumed") return { status: "skipped", reason: "order_consumed" };
    return await _refundRazorpayPayment(db, {
      paymentId, amountPaise: Number(orderSnap.get("amountPaise")) || 0, reason, orderId, uid,
    });
  } catch (err) {
    _logSettlement("ERROR", "razorpay_refund_after_capture_failed", { paymentId, orderId, error: err.message });
    return { status: "failed", reason: err.message };
  }
}

// Wraps a capture* onCall handler. Before the handler runs, a signature-valid
// payment id is stamped on the order (`paymentIdSeen`) so even a rejected
// capture is refundable; if the handler rejects with a refund-eligible error
// the gateway charge is refunded and the error message says so.
function _withCaptureRefund(handler) {
  return async (request) => {
    const uid = request.auth?.uid;
    const d = request.data || {};
    let paid = null;
    if (uid && d.paymentMethod === "razorpay" && typeof d.razorpay_order_id === "string" &&
        typeof d.razorpay_payment_id === "string" && typeof d.razorpay_signature === "string" &&
        d.razorpay_order_id && d.razorpay_payment_id && !d.razorpay_order_id.includes("/") &&
        !d.razorpay_payment_id.includes("/") && process.env.RAZORPAY_KEY_SECRET) {
      const expected = crypto.createHmac("sha256", process.env.RAZORPAY_KEY_SECRET)
        .update(`${d.razorpay_order_id}|${d.razorpay_payment_id}`).digest("hex");
      if (expected === d.razorpay_signature) {
        paid = { orderId: d.razorpay_order_id, paymentId: d.razorpay_payment_id };
        try {
          const db0 = getFirestore();
          const oref = db0.collection("razorpay_orders").doc(paid.orderId);
          const osnap = await oref.get();
          if (osnap.exists && osnap.get("uid") === uid && osnap.get("status") !== "consumed") {
            await oref.update({ paymentIdSeen: paid.paymentId, paymentIdSeenAt: FieldValue.serverTimestamp() });
          }
        } catch (err) {
          _logSettlement("WARNING", "payment_id_stamp_failed", { orderId: paid.orderId, error: err.message });
        }
      }
    }
    try {
      return await handler(request);
    } catch (err) {
      if (!paid) throw err;
      const cls = RzpRefund.classifyCaptureError(err);
      if (!cls.refund) throw err;
      const out = await _refundAfterCaptureFailure(getFirestore(), {
        uid, orderId: paid.orderId, paymentId: paid.paymentId, reason: `${cls.reason}: ${err.message || ""}`,
      });
      const dup = out.status === "skipped" && /^already_(succeeded|requested)$/.test(out.reason || "");
      const refunded = out.status === "succeeded" || dup;
      if ((out.status === "skipped" && !dup) || out.status === "not_refundable") throw err;
      const note = refunded
        ? " Your payment will be refunded to your original payment method automatically."
        : " If money was deducted, our team has been alerted and will refund it to your original payment method.";
      const code = err instanceof HttpsError ? err.code : "internal";
      const base = err instanceof HttpsError ? err.message : "Payment could not be recorded.";
      const prevDetails = err instanceof HttpsError && err.details && typeof err.details === "object" ? err.details : {};
      throw new HttpsError(code, base + note, { ...prevDetails, refund: out.status, refundInitiated: refunded });
    }
  };
}

// Every 15 min: customers who paid but whose app never called capture (crash,
// network drop) and orders whose refund previously failed / got stuck.
exports.reconcileRazorpayPayments = onSchedule({ schedule: "every 15 minutes", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const now = Date.now();
  let refunded = 0, checked = 0;

  // Pass A — paid-but-unconsumed orders. Single-field createdAt range (no
  // composite index); status is filtered in memory. Bounded API calls per run.
  const snap = await db.collection("razorpay_orders")
    .where("createdAt", ">=", Timestamp.fromMillis(now - RzpRefund.RECONCILE_MAX_AGE_MS))
    .where("createdAt", "<=", Timestamp.fromMillis(now - RzpRefund.RECONCILE_MIN_AGE_MS))
    .orderBy("createdAt", "desc").limit(400).get();
  const razorpay = new Razorpay({ key_id: process.env.RAZORPAY_KEY_ID, key_secret: process.env.RAZORPAY_KEY_SECRET });
  for (const doc of snap.docs) {
    const o = doc.data();
    const createdAtMs = o.createdAt && o.createdAt.toMillis ? o.createdAt.toMillis() : null;
    if (!RzpRefund.isReconcileCandidate({ ...o, createdAtMs }, now)) continue;
    if (checked >= 60) break;
    checked++;
    try {
      const res = await razorpay.orders.fetchPayments(doc.id);
      const items = (res && res.items) || [];
      const captured = items.find((p) => p.status === "captured") ||
        items.find((p) => p.status === "refunded");
      const fresh = await doc.ref.get();
      if (!fresh.exists || fresh.get("status") !== "created") continue; // consumed meanwhile
      if (!captured) {
        await doc.ref.update({ reconcileChecks: FieldValue.increment(1), lastReconcileAt: FieldValue.serverTimestamp() });
        continue;
      }
      const out = await _refundRazorpayPayment(db, {
        paymentId: captured.id, amountPaise: Number(o.amountPaise) || 0, orderId: doc.id, uid: o.uid || null,
        reason: "reconciler: paid at gateway but never recorded",
      });
      if (out.status === "succeeded") refunded++;
    } catch (err) {
      console.error(`reconcileRazorpayPayments: order ${doc.id} failed:`, err.message);
    }
  }

  // Pass B — retry refunds that failed or were left 'requested' by a crash.
  // The helper re-checks the payment at Razorpay, so a refund that actually
  // went through is recorded, not repeated.
  for (const st of ["failed", "requested"]) {
    const rs = await db.collection("razorpay_refunds").where("status", "==", st).limit(25).get();
    for (const r of rs.docs) {
      const x = r.data();
      try {
        const out = await _refundRazorpayPayment(db, {
          paymentId: r.id, amountPaise: x.amountPaise, orderId: x.orderId, uid: x.uid,
          reason: x.reason || "reconciler retry", allowRetry: true,
        });
        if (out.status === "succeeded") refunded++;
      } catch (err) {
        console.error(`reconcileRazorpayPayments: retry ${r.id} failed:`, err.message);
      }
    }
  }
  console.log(`reconcileRazorpayPayments: checked ${checked} order(s), refunded ${refunded}.`);
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
// ── TEST-MODE earnings (bookings made while kRequirePayment is false) ─────────
//
// The patient app creates those bookings directly with paymentStatus
// 'not_required' and no paymentId, so the real engine has nothing to settle and
// the partner's wallet stayed empty. When `settlement_config/global.
// testCreditEnabled === true` (default OFF — set it only on a test project), a
// completed not_required booking credits the provider's `pendingEarnings` and
// writes one `wallet_ledger` entry flagged `isTest: true`; the provider gets the full amount (fee-only model, no commission).
// It never creates a `payments` doc or an `eligible` payment, so the daily
// settlement queue can never batch test money into a real payout.
//
// Safety: the flag is the only thing standing between a client-written
// `paymentStatus: 'not_required'` and a wallet credit, so it MUST stay off in
// production. The ledger doc id is deterministic, so redeliveries and replays
// never double-credit. Must be called inside the caller's transaction BEFORE
// any write (all reads first).
async function _creditTestEarningsTx(db, tx, { sourceSnap, sourceCollection, sourceId, providerId, serviceType }) {
  const cfgSnap = await tx.get(db.collection("settlement_config").doc("global"));
  if (!cfgSnap.exists || cfgSnap.get("testCreditEnabled") !== true) return false;
  // Auto-expiry: the flag is only honoured for 7 days after the admin enabled it
  // (testCreditEnabledAt). A flag with no timestamp is treated as expired.
  const _enabledAt = cfgSnap.get("testCreditEnabledAt");
  const _enabledMs = _enabledAt && typeof _enabledAt.toMillis === "function" ? _enabledAt.toMillis() : 0;
  if (!_enabledMs || Date.now() - _enabledMs > 7 * 24 * 60 * 60 * 1000) return false;
  // Never credit once real payments are required (production), even if the flag is on.
  const _payCfg = await tx.get(db.collection("app_config").doc("payments"));
  if (_payCfg.exists && _payCfg.get("requirePayment") === true) return false;

  const ledgerId = _ledgerId(`test:${sourceCollection}:${sourceId}`);
  const ledgerRef = db.collection("wallet_ledger").doc(ledgerId);
  const existing = await tx.get(ledgerRef);
  if (existing.exists) return false;

  const src = sourceSnap.data() || {};
  // Each vertical's booking doc names its price differently.
  // (hospital_bill_payments stores the discounted charge as `finalAmount`.)
  // Ambulance bookings are charged the range max but earn the matched driver's
  // rate: `fareFinal` (set by onAmbulanceRequestStatusChange before this runs).
  const ambulanceFinal = serviceType === "ambulance" && Number(src.fareFinal) > 0 ? Number(src.fareFinal) : null;
  const amount = _round2(ambulanceFinal ?? Number(src.amount ?? src.fee ?? src.total ?? src.fare ?? src.totalAmount ?? src.finalAmount ?? 0));
  if (!(amount > 0)) {
    _logSettlement("WARNING", "test_credit_skipped_no_amount", { sourceCollection, sourceId, serviceType });
    return false;
  }

  const walletRef = db.collection("provider_wallets").doc(providerId);
  const walletSnap = await tx.get(walletRef);

  // Fee-only model: provider is credited the full booking amount.
  const providerAmount = amount;
  const pendingBefore = walletSnap.exists ? Number(walletSnap.get("pendingEarnings")) || 0 : 0;

  tx.set(walletRef, {
    providerId, serviceType,
    pendingEarnings: _round2(pendingBefore + providerAmount),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  tx.set(ledgerRef, {
    ..._ledgerDoc({
      uid: providerId, walletType: "provider", type: "credit", amount: providerAmount,
      category: "settlement_pending", title: "Earnings (Test Booking)",
      description: `${serviceType} · booking ₹${amount}`,
      source: `test:${sourceCollection}:${sourceId}`, balanceAfter: null,
    }),
    isTest: true,
  });
  return true;
}

async function _transitionPaymentToEligible(db, { sourceCollection, sourceId, providerId, serviceType }) {
  if (!sourceCollection || !sourceId || !providerId) return;
  try {
    const transitioned = await db.runTransaction(async (tx) => {
      const sourceRef = db.collection(sourceCollection).doc(sourceId);
      const sourceSnap = await tx.get(sourceRef);
      const paymentId = sourceSnap.exists ? sourceSnap.get("paymentId") : null;
      if (!paymentId) {
        if (sourceSnap.exists && sourceSnap.get("paymentStatus") === "not_required") {
          return await _creditTestEarningsTx(db, tx, { sourceSnap, sourceCollection, sourceId, providerId, serviceType });
        }
        return false;
      }

      const paymentRef = db.collection("payments").doc(paymentId);
      const paymentSnap = await tx.get(paymentRef);
      if (!paymentSnap.exists || paymentSnap.get("settlementStatus") !== "pending") return false;
      const payment = paymentSnap.data();

      // New (fee-only) payments already carry the final split. Legacy docs
      // (no platformFee field) are re-split fee-only so no commission survives.
      const hasFeeSplit = typeof payment.platformFee === "number";
      const feeSnap = hasFeeSplit ? null : await _readCommissionRuleTx(db, tx);
      const walletRef = db.collection("provider_wallets").doc(providerId);
      const walletSnap = await tx.get(walletRef);

      const commissionBase = Number(payment.commissionBase) || 0;
      const split = hasFeeSplit
        ? { commission: 0, platformFee: payment.platformFee, providerAmount: Number(payment.providerAmount) || 0 }
        : _computeProviderSplit(feeSnap, payment.serviceType || serviceType, commissionBase, Number(payment.originalAmount) || commissionBase, providerId);
      const { commission, providerAmount } = split;
      const adjustment = _round2(providerAmount - (Number(payment.providerAmount) || 0));

      tx.update(paymentRef, {
        providerId, commission, providerAmount, commissionFinal: true,
        ...(hasFeeSplit ? {} : { platformFee: split.platformFee, baseAmount: split.baseAmount }),
        settlementStatus: "eligible", eligibleAt: FieldValue.serverTimestamp(),
      });

      if (adjustment !== 0) {
        tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
          uid: "platform", walletType: "platform",
          type: adjustment > 0 ? "debit" : "credit", amount: Math.abs(adjustment),
          category: "commission_adjustment", title: "Platform fee adjustment",
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
      return true;
    });

    // Only notify when this call actually credited something — redeliveries,
    // unpaid bookings and disabled test-credit are silent no-ops.
    if (transitioned) _sendProviderNotification(db, getMessaging(), providerId, {
      title: "New Earnings", body: "A completed booking is now pending settlement.",
      type: "new_earnings", serviceType,
    }).catch((e) => console.warn(JSON.stringify({ severity: "WARNING", event: "earnings_notification_failed", providerId, error: e && e.message })));
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

    const tokenCandidates = await _providerTokenCandidates(db, doctorId);
    if (!tokenCandidates.length) return;
    await _sendToProviderCandidates(getMessaging(), tokenCandidates, {
      notification: { title, body },
      data: { type: "new_appointment", appointmentId, doctorId },
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
    }, `doctor ${doctorId} (new appointment)`);
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
    // Only a genuine 'completed' credits; 'cancelled' (or anything else) never does.
    if (after.status !== "completed" || after.status === "cancelled" || !after.doctorId) return;

    // Owner rule: a booked appointment earns even if the patient never joined
    // (no-show), but only once the booked slot has COMPLETED. If the call was
    // ended / marked completed before the slot's end, defer crediting to
    // settleDeferredAppointments. Unparseable date/time -> slotEnd null ->
    // credit immediately (previous behaviour).
    const db = getFirestore();
    const slotEndMs = await _apptSlotEndMs(db, after);
    if (slotEndMs !== null && Date.now() < slotEndMs) {
      await event.data.after.ref.update({
        settlementDeferredUntil: Timestamp.fromMillis(slotEndMs),
      });
      return;
    }

    await _transitionPaymentToEligible(db, _appointmentSettlementArgs(event.params.appointmentId, after));
  }
);

// Slot end (UTC epoch ms) = IST slot start + doctor's availability.slotDuration
// (minutes, default 30). Pure arithmetic lives in _slotEndFromStartMs.
const _DEFAULT_SLOT_MINUTES = 30;
function _slotEndFromStartMs(startMs, slotMinutes) {
  const mins = Number(slotMinutes);
  const dur = Number.isFinite(mins) && mins > 0 ? mins : _DEFAULT_SLOT_MINUTES;
  return startMs + dur * 60 * 1000;
}
async function _apptSlotEndMs(db, appt) {
  const startMs = _apptSlotStartMs(appt.date, appt.time);
  if (startMs === null) return null;
  let slotMinutes = _DEFAULT_SLOT_MINUTES;
  try {
    if (appt.doctorId) {
      const docSnap = await db.collection("doctors").doc(appt.doctorId).get();
      const v = docSnap.exists ? docSnap.get("availability.slotDuration") : null;
      if (typeof v === "number" && v > 0) slotMinutes = v;
    }
  } catch (_) {
    // fall back to default slot length
  }
  return _slotEndFromStartMs(startMs, slotMinutes);
}
// Every real writer of consultationType uses capitalized 'Video' (see
// consultation_screen.dart, doctor_profile_screen.dart's _consultationType) —
// a lowercase compare never matched and finalized video bookings against the
// 'consultation' commission rule.
function _appointmentSettlementArgs(appointmentId, appt) {
  return {
    sourceCollection: "appointments",
    sourceId: appointmentId,
    providerId: appt.doctorId,
    serviceType: appt.consultationType === "Video" ? "video_consultation" : "consultation",
  };
}

// Credits appointments that were marked completed before their slot ended,
// once the slot end has passed. Idempotent: _transitionPaymentToEligible only
// acts on payments still 'pending' (and test credits are guarded likewise), and
// the marker is cleared afterwards so a redelivered run skips the doc.
exports.settleDeferredAppointments = onSchedule({ schedule: "every 15 minutes", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const snap = await db.collection("appointments")
    .where("settlementDeferredUntil", "<=", Timestamp.now())
    .limit(300)
    .get();
  if (snap.empty) return;

  let settled = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    try {
      // Status may have changed since deferral (e.g. cancelled): never credit then.
      if (d.status === "completed" && d.doctorId) {
        await _transitionPaymentToEligible(db, _appointmentSettlementArgs(doc.id, d));
        settled++;
      }
      await doc.ref.update({ settlementDeferredUntil: FieldValue.delete() });
    } catch (err) {
      console.error(`settleDeferredAppointments: ${doc.id} failed:`, err.message);
    }
  }
  console.log(`settleDeferredAppointments: settled ${settled} of ${snap.size} deferred appointment(s).`);
});

// ── Quick (instant) video consultations ──────────────────────────────────────
//
// `consultations` is where "Quick Connect" bookings land (consultation_screen
// .dart pays for them via capturePayment with serviceType 'video_consultation'),
// but unlike `appointments` it had NO completion -> settlement bridge, so the
// doctor was never credited for them. The provider video call screen ends the
// session with status 'ended'; the patient-side flow can also set 'completed'.
// Provider-initiated calls have no paymentId / paymentStatus, so this no-ops
// for them.
exports.onConsultationSettlement = onDocumentUpdated(
  "consultations/{consultationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status) return;
    if (!["completed", "ended"].includes(after.status) || !after.doctorId) return;
    if (["completed", "ended"].includes(before.status)) return;
    // Scheduled-appointment consultation docs never credit: only the parent
    // appointment does (onAppointmentSettlement, after the slot has ended).
    if (after.appointmentId) return;
    // A PATIENT can end their own consultation, so a payout needs proof the
    // doctor actually joined: the doctor reached 'active' (a status the patient
    // cannot write; patient may only write ongoing/declined/missed/cancelled/
    // ended) — either the previous status was 'active' or onConsultationDoctorJoined
    // already stamped doctorJoinedAt. Fallback when the doctor app's 'active'
    // write was lost: doctor-ended from 'ongoing' after >= 30s (endedBy is
    // doctor-only in rules) — see PriceH.consultationCreditDecision.
    // Never credited otherwise (no earnings).
    const creditDecision = PriceH.consultationCreditDecision(before, after);
    if (!creditDecision.credit) {
      _logSettlement("WARNING", "consultation_credit_skipped_doctor_not_joined", {
        consultationId: event.params.consultationId, from: before.status, to: after.status,
        reason: creditDecision.reason,
      });
      return;
    }
    if (creditDecision.reason !== "doctor_active") {
      _logSettlement("INFO", "consultation_credit_doctor_ended_fallback", {
        consultationId: event.params.consultationId, reason: creditDecision.reason,
      });
    }

    await _transitionPaymentToEligible(getFirestore(), {
      sourceCollection: "consultations",
      sourceId: event.params.consultationId,
      providerId: after.doctorId,
      // Physio video calls were paid as serviceType 'physiotherapy' (physio fee).
      serviceType: after.providerRole === "physiotherapist" ? "physiotherapy" : "video_consultation",
    });
  }
);

// ── Server-side appointment completion (patients can't self-complete) ───────
//
// firestore.rules no longer lets a patient write appointments.status =
// 'completed' (it can trigger provider earnings via onAppointmentSettlement).
// Completion is decided server-side from the consultation instead:
//   1. When the doctor/provider joins (consultation status -> 'active', which a
//      patient is barred from writing) stamp `doctorJoinedAt` — evidence that the
//      call really took place.
//   2. When the consultation transitions to 'ended'/'completed' and has an
//      `appointmentId`, complete that appointment if it is still in an active
//      state and the doctor joined. Idempotent; never overrides
//      cancelled/missed/expired/completed. onAppointmentSettlement then runs as
//      designed (credit after the slot end via settlementDeferredUntil).
// The doctor app's own direct completion writes keep working (provider branch).
exports.onConsultationDoctorJoined = onDocumentUpdated(
  "consultations/{consultationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status || after.status !== "active") return;
    if (after.doctorJoinedAt) return;
    await event.data.after.ref.update({ doctorJoinedAt: FieldValue.serverTimestamp() });
  }
);

// Quick Connect paid up front (capturePayment -> consultations, status
// 'pending'). If the doctor declines or never answers (expireStaleConsultations
// -> 'missed') the patient gets the full amount back automatically, matching
// the other services' provider-failure refunds. Appointment-linked consultation
// docs carry no paymentId of their own, so _autoRefundBooking no-ops for them.
exports.onConsultationNoAnswerRefund = onDocumentUpdated(
  "consultations/{consultationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status || !["missed", "declined"].includes(after.status)) return;
    // Only a request that was never accepted ('pending'); once the doctor accepted
    // ('ongoing') a patient-written 'missed' must not trigger a refund.
    if (before.status !== "pending") return;
    if (after.appointmentId || !after.paymentId || after.cancelledBy === "patient") return;
    await _autoRefundBooking(getFirestore(), "consultations", event.params.consultationId,
      "The doctor did not answer the Quick Connect request");
  }
);

const _COMPLETABLE_APPOINTMENT_STATUSES = [
  "booked", "confirmed", "upcoming", "scheduled", "ongoing", "in_progress",
  "active", "consultation_started",
];
exports.onConsultationEndedCompleteAppointment = onDocumentUpdated(
  "consultations/{consultationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status) return;
    if (!["ended", "completed"].includes(after.status)) return;
    if (["ended", "completed"].includes(before.status)) return;
    const appointmentId = after.appointmentId;
    if (!appointmentId || typeof appointmentId !== "string") return;
    // The call must really have happened: the doctor reached 'active'
    // (before.status) or was stamped doctorJoinedAt by the trigger above.
    if (before.status !== "active" && !after.doctorJoinedAt) return;

    const db = getFirestore();
    const apptRef = db.collection("appointments").doc(appointmentId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(apptRef);
      if (!snap.exists) return;
      const appt = snap.data();
      // The consultation must belong to this appointment's own patient/doctor.
      if (appt.patientId !== after.patientId || appt.doctorId !== after.doctorId) return;
      if (!_COMPLETABLE_APPOINTMENT_STATUSES.includes(appt.status)) return;
      tx.update(apptRef, {
        status: "completed",
        completedAt: FieldValue.serverTimestamp(),
        completedBy: "system",
      });
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
// deprecated: fee-only model — the settlement engine no longer reads
// commission_rules. Kept (with its data) for rollback/audit; nothing calls it.
//
// Request data: { serviceType, type: 'percentage'|'fixed'|'hybrid',
//                  percentage?, fixedAmount?, providerOverrides? }
exports.setCommissionRule = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdminRole(db, uid, ["director"]);

  const { serviceType, type, percentage, fixedAmount, providerOverrides } = request.data || {};
  if (typeof serviceType !== "string" || !serviceType.trim()) {
    throw new HttpsError("invalid-argument", "serviceType is required.");
  }
  if (!_COMMISSION_TYPES.includes(type)) {
    throw new HttpsError("invalid-argument", "type must be percentage, fixed, or hybrid.");
  }
  // Every service type the settlement engine can finalise with (a typo'd id
  // would otherwise create a rule nothing ever reads).
  if (!Object.prototype.hasOwnProperty.call(_PROVIDER_FIELD_BY_SERVICE, serviceType.trim())) {
    throw new HttpsError("invalid-argument", `Unknown serviceType "${serviceType.trim()}".`);
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

// Coupon management roles. Matches the admin panel, where the Coupons tab sits
// under the Finance heading (visible to director, hr, finance). Marketing has no
// Coupons tab in the panel, so it is not granted here.
const _COUPON_ADMIN_ROLES = ["director", "hr", "finance", "marketing"];

exports.createCoupon = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdminRole(db, uid, _COUPON_ADMIN_ROLES);
  const payload = _validateCouponPayload(request.data);
  const ref = db.collection("coupons").doc(_safeId(payload.code, "code"));
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
  await _assertAdminRole(db, uid, _COUPON_ADMIN_ROLES);
  const { code } = request.data || {};
  if (typeof code !== "string" || !code.trim()) throw new HttpsError("invalid-argument", "code is required.");
  const payload = _validateCouponPayload({ ...request.data, code });
  const ref = db.collection("coupons").doc(_safeId(payload.code, "code"));
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
  await _assertAdminRole(db, uid, _COUPON_ADMIN_ROLES);
  const { code, active } = request.data || {};
  if (typeof code !== "string" || !code.trim()) throw new HttpsError("invalid-argument", "code is required.");
  const ref = db.collection("coupons").doc(_safeId(code.trim().toUpperCase(), "code"));
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
  await _assertAdminRole(db, uid, _COUPON_ADMIN_ROLES);
  const { code } = request.data || {};
  if (typeof code !== "string" || !code.trim()) throw new HttpsError("invalid-argument", "code is required.");
  const ref = db.collection("coupons").doc(_safeId(code.trim().toUpperCase(), "code"));
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
// `extra` (optional) carries partner-requested payout fields (requestedByPartner,
// payoutAccountSnapshot, ...). It is spread FIRST so it can never override the
// engine-owned fields below.
async function _createSettlementForProvider(db, tx, { providerId, paymentDocs, extra }) {
  const grossAmount = _round2(paymentDocs.reduce((sum, p) => sum + (Number(p.providerAmount) || 0), 0));
  // Carry-forward recovery: earnings of refunded services that were already
  // settled/paid are netted off this payout (provider_wallets.recoverableDebt).
  // Read BEFORE any write (all reads first). totalAmount is the NET payout the
  // admin transfers; grossAmount is what leaves pendingEarnings (markSettlementPaid).
  const walletRef = db.collection("provider_wallets").doc(providerId);
  const walletSnap = await tx.get(walletRef);
  const debtBefore = walletSnap.exists ? Number(walletSnap.get("recoverableDebt")) || 0 : 0;
  const net = PlanH.netRecovery(grossAmount, debtBefore);
  const totalAmount = net.netTotal;
  const settlementRef = db.collection("settlements").doc();
  const settlement = {
    ...(extra || {}),
    providerId,
    paymentIds: paymentDocs.map((p) => p.id),
    totalAmount,
    grossAmount,
    recoveryApplied: net.recoveryApplied,
    status: "pending", // awaiting admin review — see approveSettlement
    createdAt: FieldValue.serverTimestamp(),
  };
  tx.set(settlementRef, settlement);
  if (net.recoveryApplied > 0) {
    tx.set(walletRef, { providerId, recoverableDebt: net.debtAfter, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.set(db.collection("wallet_ledger").doc(_ledgerId(`recovery_applied:${settlementRef.id}`)), _ledgerDoc({
      uid: providerId, walletType: "provider", type: "info", amount: net.recoveryApplied,
      category: "recovery_applied", title: "Recovery of refunded service deducted from payout",
      description: `Settlement ${settlementRef.id}: ₹${net.recoveryApplied} netted, ₹${net.debtAfter} still to recover`,
      source: `recovery_applied:${settlementRef.id}`, balanceAfter: null,
    }));
  }
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
  await _assertAdminRole(db, uid, ["director", "finance"]);
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
  await _assertAdminRole(db, uid, ["director", "finance"]);
  const { settlementId } = request.data || {};
  if (typeof settlementId !== "string" || !settlementId.trim()) {
    throw new HttpsError("invalid-argument", "settlementId is required.");
  }
  _safeId(settlementId, "settlementId");
  const ref = db.collection("settlements").doc(settlementId);
  // Transactional so a partner cancelling their payout request (cancelPayoutRequest)
  // cannot interleave with this approval and leave a cancelled settlement approved.
  const before = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const cur = snap.exists ? snap.data() : null;
    if (!cur) throw new HttpsError("not-found", "Settlement not found.");
    if (!["pending", "held"].includes(cur.status)) {
      throw new HttpsError("failed-precondition", `Cannot approve a settlement in status "${cur.status}".`);
    }
    tx.update(ref, {
      status: "approved", approvedBy: uid, approvedAt: FieldValue.serverTimestamp(), holdReason: FieldValue.delete(),
    });
    return cur;
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
  // Destination hint for the admin UI (partner-requested payouts only).
  return { success: true, destination: before.payoutAccountSnapshot || null };
});

exports.bulkApproveSettlements = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdminRole(db, uid, ["director", "finance"]);
  const { settlementIds } = request.data || {};
  if (!Array.isArray(settlementIds) || !settlementIds.length) {
    throw new HttpsError("invalid-argument", "settlementIds must be a non-empty array.");
  }
  const results = [];
  for (const id of settlementIds) {
    try {
      const ref = db.collection("settlements").doc(id);
      const ok = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists || !["pending", "held"].includes(snap.get("status"))) return false;
        tx.update(ref, {
          status: "approved", approvedBy: uid, approvedAt: FieldValue.serverTimestamp(), holdReason: FieldValue.delete(),
        });
        return true;
      });
      results.push({ id, success: ok });
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
  await _assertAdminRole(db, uid, ["director", "finance"]);
  const { settlementId, reason } = request.data || {};
  if (typeof settlementId !== "string" || !settlementId.trim()) {
    throw new HttpsError("invalid-argument", "settlementId is required.");
  }
  _safeId(settlementId, "settlementId");
  const ref = db.collection("settlements").doc(settlementId);
  const before = (await ref.get()).data();
  if (!before) throw new HttpsError("not-found", "Settlement not found.");
  if (before.status === "cancelled") {
    throw new HttpsError("failed-precondition", "Cannot hold a settlement that was cancelled by the partner.");
  }
  // Unlike approveSettlement, this had no status guard at all — an admin
  // could hold a settlement already "paid" (money already transferred,
  // provider_wallets already updated by markSettlementPaid), silently
  // flipping it back to "held" with nothing reversed, desyncing the record
  // from reality. "paid" is terminal; nothing downstream of it should move.
  if (before.status === "paid") {
    throw new HttpsError("failed-precondition", "Cannot hold a settlement that has already been paid.");
  }
  await db.runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data();
    if (!cur) throw new HttpsError("not-found", "Settlement not found.");
    if (cur.status === "paid" || cur.status === "cancelled") {
      throw new HttpsError("failed-precondition", `Cannot hold a settlement in status "${cur.status}".`);
    }
    tx.update(ref, { status: "held", holdReason: reason || "No reason given", heldBy: uid, heldAt: FieldValue.serverTimestamp() });
  });
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
  await _assertAdminRole(db, uid, ["director", "finance"]);
  const { settlementId, payoutReference } = request.data || {};
  if (typeof settlementId !== "string" || !settlementId.trim()) {
    throw new HttpsError("invalid-argument", "settlementId is required.");
  }
  _safeId(settlementId, "settlementId");
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
      // pendingEarnings was credited with the GROSS share amounts; totalAmount is
      // the net payout after recovery netting. Legacy settlements have no grossAmount.
      const grossOf = typeof settlement.grossAmount === "number" ? settlement.grossAmount : settlement.totalAmount;

      tx.update(settlementRef, {
        status: "paid", paidBy: uid, paidAt: FieldValue.serverTimestamp(),
        payoutReference: payoutReference || null, payoutMethod: "manual",
      });
      settlement.paymentIds.forEach((pid) => {
        tx.update(db.collection("payments").doc(pid), { settlementStatus: "paid" });
      });
      tx.set(walletRef, {
        providerId: settlement.providerId,
        pendingEarnings: _round2(Math.max(0, pendingBefore - grossOf)),
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
  // Destination hint for the admin UI (partner-requested payouts only).
  return { success: true, destination: result.settlement.payoutAccountSnapshot || null };
});

// ── Partner payouts (withdrawals) ─────────────────────────────────────────────
//
// Any provider role can save payout details (payout_accounts/{providerId},
// verified by Finance/Director) and then request a withdrawal. A request creates
// an ordinary `settlements` doc through _createSettlementForProvider (so recovery
// netting, grossAmount and payment flagging all behave exactly like the daily
// queue) with requestedByPartner:true plus a MASKED account snapshot. Approval and
// "mark paid" stay admin-only (approveSettlement / markSettlementPaid).
const _PAYOUT_PARTNER_ROLES = [
  "doctor", "ambulance", "pharmacy", "lab", "equipment", "caregiver",
  "care_assistant", "physiotherapist", "counsellor", "nutritionist", "hospital",
];
const _PAYOUT_OPEN_STATUSES = ["pending", "approved", "held"];
const _PAYOUT_DEFAULT_MIN = 500;

// Wallet id for the caller: the uid for every role except hospital, whose wallet
// is keyed by hospitals/{hospitalId} (billing-desk login -> hospital_profiles/{uid}.hospitalId).
async function _resolvePayoutProvider(db, uid) {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const [docSnap, hospSnap] = await Promise.all([
    db.collection("doctors").doc(uid).get(),
    db.collection("hospital_profiles").doc(uid).get(),
  ]);
  const roles = docSnap.exists && Array.isArray(docSnap.get("roles")) ? docSnap.get("roles") : [];
  const hasPartnerRole = roles.some((r) => _PAYOUT_PARTNER_ROLES.includes(r));
  const hospitalId = hospSnap.exists && hospSnap.get("status") === "active" ? hospSnap.get("hospitalId") : null;
  if (hospitalId && typeof hospitalId === "string" && (!hasPartnerRole || roles.includes("hospital"))) {
    return { providerId: hospitalId, role: "hospital", name: hospSnap.get("name") || hospSnap.get("hospitalName") || hospitalId };
  }
  if (!docSnap.exists || !hasPartnerRole) {
    throw new HttpsError("permission-denied", "Only service partners can request payouts.");
  }
  return { providerId: uid, role: roles.find((r) => _PAYOUT_PARTNER_ROLES.includes(r)), name: docSnap.get("name") || docSnap.get("fullName") || uid };
}

exports.requestPayout = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  const { providerId, role, name } = await _resolvePayoutProvider(db, uid);
  await _rateLimit(db, `requestPayout:${uid}`, 5, 3600);

  const cfgSnap = await db.collection("app_config").doc("payouts").get();
  if (cfgSnap.exists && cfgSnap.get("enabled") === false) {
    throw new HttpsError("failed-precondition", "Payout requests are temporarily unavailable.");
  }
  const cfgMin = cfgSnap.exists ? Number(cfgSnap.get("minAmount")) : NaN;
  const minAmount = Number.isFinite(cfgMin) && cfgMin >= 0 ? cfgMin : _PAYOUT_DEFAULT_MIN;

  const acctRef = db.collection("payout_accounts").doc(providerId);
  const acctSnap = await acctRef.get();
  if (!acctSnap.exists || acctSnap.get("ownerUid") !== uid) {
    throw new HttpsError("failed-precondition", "Add your bank details before requesting a payout.");
  }
  if (acctSnap.get("status") !== "verified") {
    throw new HttpsError("failed-precondition", "Your payout details are awaiting verification.");
  }

  // One open request at a time.
  const openSnap = await db.collection("settlements")
    .where("providerId", "==", providerId).where("requestedByPartner", "==", true).limit(50).get();
  const open = openSnap.docs.find((d) => _PAYOUT_OPEN_STATUSES.includes(d.get("status")));
  if (open) {
    throw new HttpsError("already-exists", "You already have a payout request in progress.");
  }

  const eligSnap = await db.collection("payments")
    .where("providerId", "==", providerId).where("settlementStatus", "==", "eligible").limit(500).get();
  if (eligSnap.empty) throw new HttpsError("failed-precondition", "No earnings are available to withdraw yet.");

  const num = String(acctSnap.get("accountNumber") || "");
  const snapshot = {
    holderName: acctSnap.get("holderName") || "",
    bankName: acctSnap.get("bankName") || "",
    ifsc: acctSnap.get("ifsc") || "",
    accountNumberMasked: `XXXXXX${num.slice(-4)}`,
    upiId: acctSnap.get("upiId") || null,
  };

  let settlement;
  try {
    settlement = await db.runTransaction(async (tx) => {
      // Re-check each payment is still eligible (refund / queue run may have moved it).
      const fresh = [];
      for (const d of eligSnap.docs) {
        const s = await tx.get(db.collection("payments").doc(d.id));
        if (s.exists && s.get("settlementStatus") === "eligible" && s.get("providerId") === providerId) {
          fresh.push({ id: d.id, ...s.data() });
        }
      }
      const gross = _round2(fresh.reduce((sum, p) => sum + (Number(p.providerAmount) || 0), 0));
      if (!fresh.length || gross < minAmount) {
        throw new HttpsError("failed-precondition",
          `Minimum payout is ₹${minAmount}. Available to withdraw: ₹${gross}.`);
      }
      const wSnap = await tx.get(db.collection("provider_wallets").doc(providerId));
      const debt = wSnap.exists ? Number(wSnap.get("recoverableDebt")) || 0 : 0;
      if (PlanH.netRecovery(gross, debt).netTotal <= 0) {
        throw new HttpsError("failed-precondition",
          "Your available earnings are fully offset by a pending refund recovery, so there is nothing to pay out yet.");
      }
      return _createSettlementForProvider(db, tx, {
        providerId, paymentDocs: fresh,
        extra: {
          requestedByPartner: true, requestedAt: FieldValue.serverTimestamp(), requestedBy: uid,
          payoutAccountSnapshot: snapshot,
        },
      });
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    _logSettlement("ERROR", "request_payout_failed", { providerId, error: err.message });
    throw new HttpsError("internal", "Could not create your payout request. Please try again.");
  }

  const amount = settlement.totalAmount;
  await _guardedWrite("audit_write_failed", { action: "requestPayout", targetId: settlement.id, actorId: uid },
    () => db.collection("audit_logs").add(_auditLogDoc({
      actorId: uid, action: "requestPayout", targetType: "settlements", targetId: settlement.id,
      before: null, after: { providerId, role, amount, grossAmount: settlement.grossAmount },
    })), {
      title: "Audit Log Write Failed", body: `The audit entry for payout request ${settlement.id} could not be written. The payout itself succeeded.`,
      type: "audit_write_failed", extraData: { action: "requestPayout", targetId: settlement.id },
    });
  _sendAdminAlert(db, getMessaging(), {
    title: "Payout Requested", body: `${name} requested a payout of ₹${amount.toFixed(0)}.`,
    type: "payout_requested", extraData: { settlementId: settlement.id, providerId, amount: String(amount) },
  }).catch(() => {});
  _sendProviderNotification(db, getMessaging(), providerId, {
    title: "Payout requested",
    body: `Payout requested: ₹${amount.toFixed(0)}. You will be notified when it is paid.`,
    type: "payout_requested", serviceType: role === "hospital" ? "hospital" : "general",
  }).catch(() => {});
  return { settlementId: settlement.id, amount };
});

// Provider cancels THEIR OWN request while it is still awaiting admin review
// ('pending'). Releases the payments back to 'eligible' and restores any recovery
// debt netted into the request, all in one transaction. The settlement is kept as
// status 'cancelled' for the audit trail (approve/hold/markPaid all refuse it).
exports.cancelPayoutRequest = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  const { providerId } = await _resolvePayoutProvider(db, uid);
  let { settlementId } = request.data || {};
  if (settlementId !== undefined && (typeof settlementId !== "string" || !settlementId.trim())) {
    throw new HttpsError("invalid-argument", "settlementId must be a string.");
  }
  if (settlementId) _safeId(settlementId, "settlementId");
  if (!settlementId) {
    const q = await db.collection("settlements")
      .where("providerId", "==", providerId).where("requestedByPartner", "==", true).limit(50).get();
    const pend = q.docs.find((d) => d.get("status") === "pending");
    if (!pend) throw new HttpsError("not-found", "No cancellable payout request found.");
    settlementId = pend.id;
  }
  const ref = db.collection("settlements").doc(settlementId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Payout request not found.");
    const s = snap.data();
    if (s.providerId !== providerId || s.requestedByPartner !== true) {
      throw new HttpsError("permission-denied", "You can only cancel your own payout request.");
    }
    if (s.status !== "pending") {
      throw new HttpsError("failed-precondition",
        s.status === "cancelled" ? "This request was already cancelled."
          : `This request is already ${s.status} and can no longer be cancelled.`);
    }
    const paymentRefs = (s.paymentIds || []).map((id) => db.collection("payments").doc(id));
    const paySnaps = [];
    for (const r of paymentRefs) paySnaps.push(await tx.get(r));
    const walletRef = db.collection("provider_wallets").doc(providerId);
    const wSnap = await tx.get(walletRef);
    const recovery = Number(s.recoveryApplied) || 0;

    tx.update(ref, { status: "cancelled", cancelledBy: uid, cancelledAt: FieldValue.serverTimestamp() });
    paySnaps.forEach((ps, i) => {
      if (ps.exists && ps.get("settlementStatus") === "pending_review" && ps.get("settlementId") === settlementId) {
        tx.update(paymentRefs[i], { settlementStatus: "eligible", settlementId: FieldValue.delete() });
      }
    });
    if (recovery > 0) {
      const debtNow = wSnap.exists ? Number(wSnap.get("recoverableDebt")) || 0 : 0;
      tx.set(walletRef, { providerId, recoverableDebt: _round2(debtNow + recovery), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      tx.set(db.collection("wallet_ledger").doc(_ledgerId(`recovery_restored:${settlementId}`)), _ledgerDoc({
        uid: providerId, walletType: "provider", type: "info", amount: recovery,
        category: "recovery_restored", title: "Recovery restored (payout request cancelled)",
        description: `Settlement ${settlementId} cancelled: ₹${recovery} returned to recoverable debt`,
        source: `recovery_restored:${settlementId}`, balanceAfter: null,
      }));
    }
  });

  await _guardedWrite("audit_write_failed", { action: "cancelPayoutRequest", targetId: settlementId, actorId: uid },
    () => db.collection("audit_logs").add(_auditLogDoc({
      actorId: uid, action: "cancelPayoutRequest", targetType: "settlements", targetId: settlementId,
      before: { status: "pending" }, after: { status: "cancelled" },
    })), {
      title: "Audit Log Write Failed", body: `The audit entry for cancelling payout request ${settlementId} could not be written. The cancellation itself succeeded.`,
      type: "audit_write_failed", extraData: { action: "cancelPayoutRequest", targetId: settlementId },
    });
  return { success: true, settlementId };
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
  await _assertAdminRole(db, uid, ["director", "finance"]);
  const { paymentId, reason } = request.data || {};
  if (typeof paymentId !== "string" || !paymentId.trim()) {
    throw new HttpsError("invalid-argument", "paymentId is required.");
  }
  return _refundPayment(db, paymentId, reason, uid);
});

// Shared by the admin panel (issueRefund above) and automatic refunds when a
// provider declines/cancels (_autoRefundBooking below) so both move money
// through exactly the same checks. `actorId` is the admin uid or
// "system:auto_refund".
//
// `opts.refundAmount` (rupees, optional) makes it a PARTIAL refund (prepaid plan
// cancellation: the base is returned, the non-refundable platform fee stays with
// the platform). The gateway/wallet legs are prorated by computeRefundSplit, the
// platform fee is NOT reversed, and the payment still ends 'refunded' so it can
// never be refunded twice.
async function _refundPayment(db, paymentId, reason, actorId, opts = {}) {
  const uid = actorId;
  const isPartial = opts.refundAmount !== undefined && opts.refundAmount !== null;

  const paymentRef = db.collection("payments").doc(paymentId);
  const paymentSnap = await paymentRef.get();
  if (!paymentSnap.exists) throw new HttpsError("not-found", "Payment not found.");
  const payment = paymentSnap.data();
  if (payment.status === "refunded") {
    throw new HttpsError("failed-precondition", "This payment has already been refunded.");
  }
  if (payment.isWriteOff === true) {
    throw new HttpsError("failed-precondition", "This is a platform write-off record; nothing was collected from a customer to refund.");
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
  // A payment can be split between the in-app wallet (walletPortionAmount,
  // already debited) and the gateway. Razorpay only holds the gateway portion,
  // so asking it to refund the full paidAmount is rejected. Refund each leg to
  // where it came from: gateway portion -> Razorpay, wallet portion -> wallet
  // (credited in the transaction below). Legs are tracked on the payment doc
  // (refundGatewayDone / refundWalletDone) so a retry after a partial failure
  // only completes the missing leg. See computeRefundSplit (full refund here).
  const split = RzpRefund.computeRefundSplit({
    paidAmount: payment.paidAmount, walletPortionAmount: payment.walletPortionAmount,
    paymentMethod: payment.paymentMethod,
    walletLegs: payment.walletLegs || null,
    ...(isPartial ? { refundAmount: opts.refundAmount } : {}),
  });
  if (isPartial && !(split.refundPaise > 0)) {
    throw new HttpsError("failed-precondition", "There is nothing to refund for this payment.");
  }
  if (split.gatewayPaise > 0 && payment.razorpayPaymentId && payment.refundGatewayDone !== true) {
    const razorpay = new Razorpay({ key_id: process.env.RAZORPAY_KEY_ID, key_secret: process.env.RAZORPAY_KEY_SECRET });
    let alreadyRefunded = false;
    try {
      // A partial refund retried after a crash would NOT be rejected by the
      // gateway as "already refunded", so check what it already returned.
      let gatewayDoneAlready = false;
      if (isPartial) {
        const gp = await razorpay.payments.fetch(payment.razorpayPaymentId);
        gatewayDoneAlready = Number(gp && gp.amount_refunded) >= split.gatewayPaise;
      }
      if (!gatewayDoneAlready) {
        await razorpay.payments.refund(payment.razorpayPaymentId, { amount: split.gatewayPaise });
      }
    } catch (err) {
      // The gateway portion is the entire captured amount, so a retry after a
      // crash between the gateway call and the flag write is rejected as
      // "already refunded" — treat that as the leg being done.
      const desc = String((err && err.error && err.error.description) || (err && err.message) || "");
      alreadyRefunded = /already.*(fully )?refunded|fully refunded/i.test(desc);
      if (!alreadyRefunded) {
        _logSettlement("ERROR", "razorpay_refund_failed", {
          paymentId, error: desc, gatewayPaise: split.gatewayPaise, walletPaise: split.walletPaise,
        });
        throw new HttpsError("internal", "Refund could not be processed by the payment gateway.");
      }
    }
    // Persist the leg immediately (outside the main transaction: the gateway
    // call can't be rolled back, so record it even if a later step fails).
    await paymentRef.set({
      refundGatewayDone: true, refundGatewayPaise: split.gatewayPaise,
      refundGatewayAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    payment.refundGatewayDone = true;
  }

  const wasSettled = payment.settlementStatus === "paid";
  const refundStatus = wasSettled ? "recovery_pending" : "completed";
  const refundRef = db.collection("refunds").doc();
  let planReversalOutcome = null; // set inside the transaction for plan payments

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

    // Wallet leg: full wallet payments, already_settled payments and the wallet
    // portion of split razorpay payments are credited back to the main wallet.
    // The deterministic ledger doc is the replay guard (never credited twice).
    // When the payment recorded per-wallet legs (walletLegs, set at capture) each
    // leg goes back to its own balance (main -> walletBalance, MedNU Money ->
    // mednuMoneyBalance) under its own deterministic ledger id; payments without
    // legs (older docs, plain 'wallet' payments) keep the single main-wallet credit.
    const walletRefund = _round2(split.walletPaise / 100);
    const hasLegSplit = split.walletMainPaise !== undefined && split.walletMednuPaise !== undefined;
    const walletCredits = !(walletRefund > 0) ? [] : hasLegSplit
      ? [
        { walletType: "main", amount: _round2(split.walletMainPaise / 100), suffix: "wallet-main" },
        { walletType: "mednu_money", amount: _round2(split.walletMednuPaise / 100), suffix: "wallet-mednu" },
      ].filter((l) => l.amount > 0)
      : [{ walletType: "main", amount: walletRefund, suffix: "wallet" }];
    walletCredits.forEach((l) => {
      l.ref = db.collection("wallet_ledger").doc(_ledgerId(`refund:${paymentId}:${l.suffix}`));
    });
    let userSnap = null;
    const walletLedgerExistsBySuffix = {};
    if (walletRefund > 0 && freshPayment?.refundWalletDone !== true) {
      userSnap = await tx.get(db.collection("users").doc(payment.patientId));
      for (const l of walletCredits) {
        walletLedgerExistsBySuffix[l.suffix] = (await tx.get(l.ref)).exists;
      }
    }

    // An 'eligible' payment already credited the provider's pendingEarnings
    // (see _transitionPaymentToEligible) but isn't in any settlement batch, so
    // nothing else would ever take that credit back. Read here (all reads
    // before writes) and reverse below.
    const reverseProviderPending = freshPayment?.settlementStatus === "eligible" &&
      freshPayment.providerId && Number(freshPayment.providerAmount) > 0;
    const providerWalletRef = reverseProviderPending
      ? db.collection("provider_wallets").doc(freshPayment.providerId) : null;
    const providerWalletSnap = providerWalletRef ? await tx.get(providerWalletRef) : null;

    // Manual FULL refund of a prepaid plan payment: earnings already released for
    // completed consultations (child `planshare:<sub>:<i>` payments) are reversed
    // while still 'eligible'; shares already in a settlement / paid are NOT
    // clawed back (flagged + admin alert). Children are read by their
    // deterministic ids inside this transaction, so a share created concurrently
    // by _completePlanConsultation conflicts and is never missed.
    let planReversal = { reverse: [], skipped: [] };
    const planWalletSnaps = {};
    const planChildRefs = [];
    if (!isPartial && freshPayment?.planSubscriptionId) {
      const months = Math.min(12, Math.max(0, Number(freshPayment.planMonths) || 0));
      for (let i = 1; i <= months; i++) {
        planChildRefs.push(db.collection("payments").doc(_ledgerId(`planshare:${freshPayment.planSubscriptionId}:${i}`)));
      }
      const childSnaps = await Promise.all(planChildRefs.map((r) => tx.get(r)));
      planReversal = PlanH.planShareReversalDecision(childSnaps.map((s) => (s.exists ? {
        id: s.id, exists: true, status: s.get("status"), settlementStatus: s.get("settlementStatus"),
        shareReversed: s.get("shareReversed") === true, providerId: s.get("providerId"),
        providerAmount: s.get("providerAmount"),
      } : { exists: false })));
      for (const pid of new Set(planReversal.reverse.map((c) => c.providerId))) {
        planWalletSnaps[pid] = await tx.get(db.collection("provider_wallets").doc(pid));
      }
    }

    // Carry-forward recovery (reads first): earnings already in a settlement or
    // paid out can't be clawed back directly, so they become the provider's
    // recoverableDebt, netted off their next settlement (_createSettlementForProvider).
    const recoveryTargets = []; // [{ providerId, amount, refId, childId|null, reason }]
    if (!isPartial) {
      for (const c of planReversal.skipped) {
        recoveryTargets.push({ providerId: c.providerId, amount: c.amount, refId: c.id, childId: c.id, reason: c.reason });
      }
      if (freshPayment?.settlementStatus === "paid" && freshPayment.recoveryRecorded !== true &&
          freshPayment.providerId && Number(freshPayment.providerAmount) > 0) {
        recoveryTargets.push({
          providerId: freshPayment.providerId, amount: _round2(Number(freshPayment.providerAmount)),
          refId: paymentId, childId: null, reason: "paid",
        });
      }
    }
    const recoveryWalletSnaps = {};
    for (const pid of new Set(recoveryTargets.map((t) => t.providerId))) {
      recoveryWalletSnaps[pid] = await tx.get(db.collection("provider_wallets").doc(pid));
    }

    if (userSnap) {
      const userRef = db.collection("users").doc(payment.patientId);
      const running = {
        walletBalance: _walletBalanceOf(userSnap, "walletBalance"),
        mednuMoneyBalance: _walletBalanceOf(userSnap, "mednuMoneyBalance"),
      };
      for (const l of walletCredits) {
        if (walletLedgerExistsBySuffix[l.suffix]) continue; // replay guard
        const field = _walletField(l.walletType);
        running[field] = _round2(running[field] + l.amount);
        tx.set(userRef, { [field]: running[field] }, { merge: true });
        tx.set(userRef.collection("transactions").doc(), _legacyTxDoc({
          title: "Refund", amount: l.amount, type: "credit", category: "refund", walletType: l.walletType,
        }));
        tx.set(l.ref, _ledgerDoc({
          uid: payment.patientId, walletType: l.walletType, type: "credit", amount: l.amount,
          category: "refund", title: "Refund", description: reason || null,
          source: `refund:${paymentId}:${l.suffix}`, balanceAfter: running[field],
        }));
      }
    }

    tx.set(refundRef, {
      paymentId, patientId: payment.patientId, providerId: payment.providerId || null,
      amount: isPartial ? split.refundPaise / 100 : payment.paidAmount, reason: reason || "Not specified",
      ...(isPartial ? { partial: true, nonRefundableFee: Number(opts.nonRefundableFee) || 0 } : {}),
      status: refundStatus, initiatedBy: uid, createdAt: FieldValue.serverTimestamp(),
      completedAt: refundStatus === "completed" ? FieldValue.serverTimestamp() : null,
    });
    tx.update(paymentRef, {
      status: "refunded", settlementStatus: wasSettled ? "paid" : "failed",
      refundGatewayDone: split.gatewayPaise > 0 && payment.refundGatewayDone === true ? true : (freshPayment?.refundGatewayDone === true),
      refundWalletDone: walletRefund > 0 ? true : (freshPayment?.refundWalletDone === true),
      refundWalletAmount: walletRefund,
    });

    if (providerWalletRef) {
      const reverseAmt = _round2(Number(freshPayment.providerAmount));
      const pendingNow = providerWalletSnap.exists ? Number(providerWalletSnap.get("pendingEarnings")) || 0 : 0;
      tx.set(providerWalletRef, {
        pendingEarnings: _round2(Math.max(0, pendingNow - reverseAmt)),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid: freshPayment.providerId, walletType: "provider", type: "debit", amount: reverseAmt,
        category: "settlement_reversal", title: "Earnings Reversed (Refund)",
        description: `Payment ${paymentId} refunded before settlement`,
        source: `payment:${paymentId}:provider_reversal`, balanceAfter: null,
      }));
    }

    // Plan payment: reverse the shares still 'eligible', flag the rest.
    if (planReversal.reverse.length || planReversal.skipped.length) {
      const pendingByProvider = {};
      for (const c of planReversal.reverse) {
        const snap = planWalletSnaps[c.providerId];
        if (pendingByProvider[c.providerId] === undefined) {
          pendingByProvider[c.providerId] = snap && snap.exists ? Number(snap.get("pendingEarnings")) || 0 : 0;
        }
        pendingByProvider[c.providerId] = _round2(Math.max(0, pendingByProvider[c.providerId] - c.amount));
        tx.set(db.collection("wallet_ledger").doc(_ledgerId(`plan_reversal:${c.id}`)), _ledgerDoc({
          uid: c.providerId, walletType: "provider", type: "debit", amount: c.amount,
          category: "settlement_reversal", title: "Earnings Reversed (Plan Refund)",
          description: `Plan payment ${paymentId} refunded; consultation share ${c.id} reversed`,
          source: `plan_reversal:${c.id}`, balanceAfter: null,
        }));
        tx.update(db.collection("payments").doc(c.id), {
          status: "refunded", settlementStatus: "failed", shareReversed: true,
          reversedAt: FieldValue.serverTimestamp(), reversedByPaymentId: paymentId,
        });
      }
      for (const pid of Object.keys(pendingByProvider)) {
        tx.set(db.collection("provider_wallets").doc(pid), {
          pendingEarnings: pendingByProvider[pid], updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      for (const c of planReversal.skipped) {
        tx.update(db.collection("payments").doc(c.id), {
          reversalSkipped: true, reversalSkippedReason: `share_${c.reason}`,
          reversalSkippedAt: FieldValue.serverTimestamp(), reversalParentPaymentId: paymentId,
        });
      }
      const sum = (arr) => _round2(arr.reduce((a, c) => a + c.amount, 0));
      planReversalOutcome = {
        reversed: planReversal.reverse.length, reversedAmount: sum(planReversal.reverse),
        skipped: planReversal.skipped.length, skippedAmount: sum(planReversal.skipped),
        skippedProviders: [...new Set(planReversal.skipped.map((c) => c.providerId))],
      };
      tx.update(paymentRef, { planShareReversal: planReversalOutcome });
    }

    if (recoveryTargets.length) {
      const debtNow = {};
      for (const t of recoveryTargets) {
        const snap = recoveryWalletSnaps[t.providerId];
        if (debtNow[t.providerId] === undefined) {
          debtNow[t.providerId] = snap && snap.exists ? Number(snap.get("recoverableDebt")) || 0 : 0;
        }
        debtNow[t.providerId] = _round2(debtNow[t.providerId] + t.amount);
        tx.set(db.collection("wallet_ledger").doc(_ledgerId(`plan_recovery:${t.refId}`)), _ledgerDoc({
          uid: t.providerId, walletType: "provider", type: "debit", amount: t.amount,
          category: "recovery_due", title: "Recovery of refunded service",
          description: `Payment ${paymentId} was refunded after ${t.childId ? "this share" : "your earnings"} was already settled; deducted from your next payout`,
          source: `plan_recovery:${t.refId}`, balanceAfter: null,
        }));
        if (t.childId) tx.update(db.collection("payments").doc(t.childId), { recoveryRecorded: true });
      }
      for (const pid of Object.keys(debtNow)) {
        tx.set(db.collection("provider_wallets").doc(pid), {
          providerId: pid, recoverableDebt: debtNow[pid], updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      if (recoveryTargets.some((t) => !t.childId)) tx.update(paymentRef, { recoveryRecorded: true });
    }

    if (payment.paidAmount > 0) {
      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid: "platform", walletType: "platform", type: "debit",
        amount: isPartial ? split.refundPaise / 100 : payment.paidAmount,
        category: "refund", title: "Refund Issued",
        description: reason || null, source: `payment:${paymentId}:refund`, balanceAfter: null,
      }));
    }
    // Fee-only model: reverse the platform fee (legacy docs: their stored commission).
    const feeToReverse = Number(payment.platformFee) > 0 ? Number(payment.platformFee) : Number(payment.commission) || 0;
    // Partial (plan cancellation): the platform fee is non-refundable, so it is NOT reversed.
    if (!isPartial && !wasSettled && feeToReverse > 0) {
      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid: "platform", walletType: "platform", type: "debit", amount: feeToReverse,
        category: "commission_reversal", title: "Platform fee reversed",
        source: `payment:${paymentId}:commission_reversal`, balanceAfter: null,
      }));
    }
  });

  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "issueRefund", targetType: "payments", targetId: paymentId,
    before: { status: payment.status }, after: { status: "refunded", refundStatus },
  }));

  const messaging = getMessaging();
  const refundedRupees = isPartial ? split.refundPaise / 100 : payment.paidAmount;
  const keptFee = isPartial ? Number(opts.nonRefundableFee) || 0 : 0;
  _sendPatientNotification(db, messaging, payment.patientId, {
    title: "Refund Processed",
    body: `₹${refundedRupees.toFixed(0)} has been refunded to you.` +
      (keptFee > 0 ? ` The platform fee of ₹${keptFee.toFixed(0)} is non-refundable.` : ""),
    type: "refund_processed", bookingId: payment.bookingRef?.id || "",
  }).catch(() => {});

  // A refunded plan payment ends the subscription (an admin full refund too).
  if (payment.planSubscriptionId) {
    await _guardedWrite("plan_subscription_cancel_write_failed", { paymentId, subscriptionId: payment.planSubscriptionId },
      () => db.collection("nutrition_subscriptions").doc(payment.planSubscriptionId).set({
        status: "cancelled", paymentRefunded: true, refundedAmount: refundedRupees,
        cancelledAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true }), {
        title: "Plan Not Closed After Refund",
        body: `Payment ${paymentId} was refunded but plan subscription ${payment.planSubscriptionId} could not be marked cancelled. Close it manually.`,
        type: "plan_subscription_cancel_write_failed", extraData: { paymentId, subscriptionId: payment.planSubscriptionId },
      });
  }

  if (wasSettled) {
    _sendAdminAlert(db, messaging, {
      title: "Refund Recovery Needed",
      body: `Payment ${paymentId} was refunded after the provider was already settled — recover ₹${(payment.providerAmount || 0).toFixed(0)} from their next payout.`,
      type: "refund_recovery_pending", extraData: { paymentId, providerId: payment.providerId || "" },
    }).catch(() => {});
  }

  if (planReversalOutcome && planReversalOutcome.skipped > 0) {
    _sendAdminAlert(db, messaging, {
      title: "Plan Refund: Earnings Not Reversed",
      body: `Plan payment ${paymentId} was refunded, but ₹${planReversalOutcome.skippedAmount.toFixed(0)} already ` +
        `in a settlement or paid out to the dietician was not clawed back. Recover it manually.`,
      type: "plan_refund_reversal_skipped",
      extraData: { paymentId, providerId: planReversalOutcome.skippedProviders[0] || "" },
    }).catch(() => {});
  }
  if (planReversalOutcome) {
    _logSettlement("INFO", "plan_refund_share_reversal", { paymentId, ...planReversalOutcome });
  }

  return { success: true, refundId: refundRef.id, status: refundStatus };
}

// ── Automatic refunds (provider-side decline / cancel / expiry) ───────────
// The patient picked one provider; if that provider declines, cancels, or
// never responds, the booking fails through no fault of the patient, so the
// full amount is refunded straight away rather than waiting on an admin.
// Patient-initiated cancels are excluded: the patient-cancel mirrors stamp
// `cancelledBy: "patient"` on the provider-side doc. Anything that can't be
// refunded automatically (already in a pending settlement batch, gateway
// failure) raises an admin alert so it's handled manually via issueRefund.
async function _autoRefundBooking(db, sourceCollection, sourceId, reason) {
  let paymentId = null;
  try {
    const src = await db.collection(sourceCollection).doc(sourceId).get();
    paymentId = src.exists ? src.get("paymentId") : null;
    if (!paymentId) return; // unpaid / pay-later booking — nothing to refund.

    // Claim first so a redelivered trigger can't call the gateway twice.
    const paymentRef = db.collection("payments").doc(paymentId);
    const claimed = await db.runTransaction(async (tx) => {
      const p = (await tx.get(paymentRef)).data();
      if (!p || p.status !== "completed" || p.autoRefundClaimedAt) return false;
      tx.update(paymentRef, { autoRefundClaimedAt: FieldValue.serverTimestamp() });
      return true;
    });
    if (!claimed) return;

    await _refundPayment(db, paymentId, reason, "system:auto_refund");
    _logSettlement("INFO", "auto_refund_issued", { paymentId, sourceCollection, sourceId });
  } catch (err) {
    _logSettlement("ERROR", "auto_refund_failed", { paymentId, sourceCollection, sourceId, error: err.message });
    _sendAdminAlert(db, getMessaging(), {
      title: "Auto-Refund Needs Manual Action",
      body: `Booking ${sourceId} was declined by the provider but could not be refunded automatically: ${err.message}`,
      type: "auto_refund_failed", extraData: { paymentId: paymentId || "", sourceId },
    }).catch(() => {});
  }
}

async function _autoRefundOnProviderFailure(db, before, after, failStatuses, sourceCollection, sourceId, reason) {
  if (before.status === after.status || !failStatuses.includes(after.status)) return;
  if (after.cancelledBy === "patient") return;
  await _autoRefundBooking(db, sourceCollection, sourceId, reason);
}

// ── Pinned provider has paused orders (the "accepting orders" switch) ───────
// A patient pinned an order/booking to one pharmacy / lab / equipment vendor
// that has its switch off (`acceptingOrders` / lab `acceptingBookings` ===
// false). The patient app greys such providers out and blocks adding to the
// cart, so this only fires for a race (switch flipped after the cart was
// built) or a direct write. Same shape as the `slot_taken` system cancel:
// the source doc is cancelled by "system", a paid booking is auto-refunded
// through _autoRefundBooking, and the patient is told why. No provider-side
// doc is ever created, so the paused partner is never bothered.
// onServiceRequestStatusChange skips its generic "cancelled" push for this
// cancelReason (see there) so the patient gets exactly one message.
async function _rejectPinnedProviderNotAccepting(db, sourceCollection, sourceId, data, providerName, label) {
  const ref = db.collection(sourceCollection).doc(sourceId);
  await ref.update({
    status: "cancelled",
    cancelledBy: "system",
    cancelReason: "provider_not_accepting",
    updatedAt: FieldValue.serverTimestamp(),
  });
  await _autoRefundBooking(db, sourceCollection, sourceId, "The provider is not accepting orders right now");
  console.log(JSON.stringify({
    module: "provider_availability", event: "order_rejected_provider_not_accepting",
    sourceCollection, sourceId, label,
  }));
  const patientId = data.patientId || data.userId;
  if (!patientId) return;
  const who = providerName || `This ${label}`;
  await _sendPatientNotification(db, getMessaging(), patientId, {
    title: "Provider Unavailable",
    body: `${who} isn't accepting orders right now. Please pick another${data.paymentId ? " — your payment is being refunded" : ""}.`,
    type: "provider_not_accepting",
    bookingId: sourceId,
    actionType: "open_service",
  }).catch(() => {});
}

// ── Equipment must come from an equipment vendor (vendor-only marketplace) ──
// An equipment service_request with no valid pinned vendor (legacy admin-listed
// item, or a vendor that is no longer an active partner) is never routed to
// the pharmacy pool. It is cancelled by "system", a paid booking is refunded
// via _autoRefundBooking, and the patient gets one message.
async function _rejectEquipmentVendorRequired(db, requestId, data) {
  const ref = db.collection("service_requests").doc(requestId);
  const cur = await ref.get();
  if (!cur.exists) return;
  // Redelivery guard: already rejected -> no second refund attempt / message.
  if (cur.data().cancelReason === "equipment_vendor_required") return;
  await ref.update({
    status: "cancelled",
    cancelledBy: "system",
    cancelReason: "equipment_vendor_required",
    updatedAt: FieldValue.serverTimestamp(),
  });
  await _autoRefundBooking(db, "service_requests", requestId, "Equipment is only available from equipment vendors");
  console.log(JSON.stringify({
    module: "equipment", event: "equipment_request_rejected_vendor_required", requestId,
  }));
  const patientId = data.patientId || data.userId;
  if (!patientId) return;
  await _sendPatientNotification(db, getMessaging(), patientId, {
    title: "Equipment Unavailable",
    body: `This equipment is no longer available. Please choose an item from an equipment vendor.${data.paymentId ? " Your payment is being refunded." : ""}`,
    type: "equipment_vendor_required",
    serviceType: "equipment",
    bookingId: requestId,
    actionType: "open_service",
  }).catch(() => {});
}

// ── Customer-cancel refund policy (paid bookings only) ──────────────────────
// A no-op for bookings without a paymentId (test/pay-later bookings).
//   a) provider has NOT accepted yet (previous status in `preAccept`)
//        -> full automatic refund via _autoRefundBooking (idempotent: it
//           claims payments/{id}.autoRefundClaimedAt first).
//   b) provider accepted but the service has not started
//        -> NO automatic refund; a `refund_requests/{id}` doc is created for
//           the admin to Approve/Reject (resolveRefundRequest). Deterministic
//           doc id + create() => redelivered triggers cannot duplicate it.
//   c) service already started (_CANCEL_STARTED_STATUSES) -> nothing; the
//      patient UI does not offer cancel there.
// The patient is recognised by `cancelledBy: "patient"`, which the patient
// app stamps and firestore.rules only let the patient set to that value
// (provider mirrors/system cancels never carry it).
const _CANCEL_POLICY = {
  service_requests: { patientField: "patientId", preAccept: ["pending", "requested"] },
  appointments: { patientField: "patientId", preAccept: ["pending"] },
  orders: { patientField: "patientId", preAccept: ["pending", "prescription_required"] },
  nutrition_appointments: { patientField: "userId", preAccept: ["pending"] },
  consultations: { patientField: "patientId", preAccept: ["pending", "ringing", "calling"] },
  hospital_appointments: { patientField: "patientId", preAccept: [] },
};
const _CANCEL_STARTED_STATUSES = [
  "in_progress", "started", "arrived", "consultation_started", "active", "checked_in",
  "sample_collected", "report_ready", "out_for_delivery", "delivered", "completed", "ended",
];

async function _applyCancelRefundPolicy(db, collection, bookingId, before, after) {
  if (!before || !after) return;
  if (before.status === after.status || after.status !== "cancelled") return;
  if (after.cancelledBy !== "patient" || !after.paymentId) return;
  // Prepaid plan consultation: cancelling one visit is not a plan refund (the
  // credit returns; the plan itself is cancelled via cancelWeightLossPlan).
  if (collection === "nutrition_appointments" && after.subscriptionId) return;
  const cfg = _CANCEL_POLICY[collection];
  if (!cfg) return;
  const prev = String(before.status || "").toLowerCase();
  if (_CANCEL_STARTED_STATUSES.includes(prev)) {
    _logSettlement("INFO", "cancel_after_start_ignored", { collection, bookingId, prev });
    return;
  }

  if (cfg.preAccept.includes(prev)) {
    await _autoRefundBooking(db, collection, bookingId, "Cancelled by the customer before the provider accepted");
    return;
  }

  try {
    const paymentSnap = await db.collection("payments").doc(after.paymentId).get();
    if (!paymentSnap.exists) return;
    const payment = paymentSnap.data();
    if (payment.status !== "completed" || !(Number(payment.paidAmount) > 0)) return;
    const patientId = after[cfg.patientField] || payment.patientId;
    const requestRef = db.collection("refund_requests").doc(_ledgerId(`${collection}:${bookingId}`));
    try {
      await requestRef.create({
        paymentId: after.paymentId, bookingCollection: collection, bookingId, patientId,
        amount: payment.paidAmount, serviceType: payment.serviceType || null,
        providerId: payment.providerId || null,
        reason: after.cancelReason || "Cancelled by the customer after the provider accepted",
        status: "pending", createdAt: FieldValue.serverTimestamp(),
      });
    } catch (err) {
      if (err.code === 6 || /ALREADY_EXISTS/.test(String(err.message))) return; // redelivery
      throw err;
    }
    const messaging = getMessaging();
    _sendPatientNotification(db, messaging, patientId, {
      title: "Cancellation Received",
      body: "Your booking was cancelled. As the provider had already accepted it, your refund request has been sent to our team for review.",
      type: "refund_request_received", bookingId,
    }).catch(() => {});
    _sendAdminAlert(db, messaging, {
      title: "Refund Request",
      body: `A customer cancelled an accepted booking (${collection}/${bookingId}). Review the refund of ₹${Number(payment.paidAmount).toFixed(0)}.`,
      type: "refund_request", extraData: { paymentId: after.paymentId, bookingId, bookingCollection: collection },
    }).catch(() => {});
  } catch (err) {
    _logSettlement("ERROR", "refund_request_create_failed", { collection, bookingId, error: err.message });
    throw err; // let the platform retry the trigger
  }
}

function _cancelPolicyTrigger(collection) {
  return onDocumentUpdated(`${collection}/{docId}`, async (event) => {
    await _applyCancelRefundPolicy(
      getFirestore(), collection, event.params.docId,
      event.data.before.data(), event.data.after.data());
  });
}
exports.onServiceRequestCancelRefundPolicy = _cancelPolicyTrigger("service_requests");
exports.onAppointmentCancelRefundPolicy = _cancelPolicyTrigger("appointments");
exports.onOrderCancelRefundPolicy = _cancelPolicyTrigger("orders");
exports.onNutritionCancelRefundPolicy = _cancelPolicyTrigger("nutrition_appointments");
exports.onConsultationCancelRefundPolicy = _cancelPolicyTrigger("consultations");
exports.onHospitalAppointmentCancelRefundPolicy = _cancelPolicyTrigger("hospital_appointments");

// Admin decision on a refund request. Approve reuses the shared refund engine
// (same checks as issueRefund); Reject records the note. Either way the
// patient is notified. The request is claimed ('processing') first so a
// double-click cannot refund twice.
// Request data: { requestId, decision: 'approve'|'reject', note? }
exports.resolveRefundRequest = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  await _assertAdminRole(db, uid, ["director", "finance"]);
  const { requestId, decision, note } = request.data || {};
  if (typeof requestId !== "string" || !requestId.trim()) {
    throw new HttpsError("invalid-argument", "requestId is required.");
  }
  _safeId(requestId, "requestId");
  if (decision !== "approve" && decision !== "reject") {
    throw new HttpsError("invalid-argument", "decision must be approve or reject.");
  }
  const adminNote = typeof note === "string" ? note.trim().slice(0, 500) : "";
  if (decision === "reject" && !adminNote) {
    throw new HttpsError("invalid-argument", "Add a note explaining why the refund is rejected.");
  }

  const reqRef = db.collection("refund_requests").doc(requestId.trim());
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(reqRef);
    if (!snap.exists) throw new HttpsError("not-found", "Refund request not found.");
    if (snap.get("status") !== "pending") {
      throw new HttpsError("failed-precondition", `This request is already ${snap.get("status")}.`);
    }
    tx.update(reqRef, { status: "processing" });
    return snap.data();
  });

  const messaging = getMessaging();
  if (decision === "reject") {
    await reqRef.update({
      status: "rejected", adminNote, resolvedBy: uid, resolvedAt: FieldValue.serverTimestamp(),
    });
    await db.collection("audit_logs").add(_auditLogDoc({
      actorId: uid, action: "rejectRefundRequest", targetType: "refund_requests", targetId: reqRef.id,
      before: { status: "pending" }, after: { status: "rejected", adminNote },
    }));
    _sendPatientNotification(db, messaging, claimed.patientId, {
      title: "Refund Request Update",
      body: `Your refund request was not approved. ${adminNote}`,
      type: "refund_request_rejected", bookingId: claimed.bookingId,
    }).catch(() => {});
    return { success: true, status: "rejected" };
  }

  let result;
  try {
    result = await _refundPayment(db, claimed.paymentId, adminNote || "Customer cancellation approved by admin", uid);
  } catch (err) {
    // let the admin retry or reject
    await _guardedWrite("refund_request_revert_failed", { requestId: reqRef.id },
      () => reqRef.update({ status: "pending" }), {
        title: "Refund Request Stuck", body: `Refund request ${reqRef.id} failed and could not be reset to pending. Check it manually.`,
        type: "refund_request_revert_failed", extraData: { requestId: reqRef.id },
      });
    throw err;
  }
  await reqRef.update({
    status: "approved", adminNote, refundId: result.refundId,
    resolvedBy: uid, resolvedAt: FieldValue.serverTimestamp(),
  });
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "approveRefundRequest", targetType: "refund_requests", targetId: reqRef.id,
    before: { status: "pending" }, after: { status: "approved", refundId: result.refundId },
  }));
  // _refundPayment already sent the "Refund Processed" push to the patient.
  return { success: true, status: "approved", refundId: result.refundId };
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

// ── Unclaimed-job privacy ────────────────────────────────────────────────
// A job nobody has claimed yet is readable by EVERY approved partner of that
// role (firestore.rules' `providerField == null && is<Role>Partner()`), so
// it must not carry the patient's full contact details. While unclaimed the
// job doc gets only a first name + rough area; the full phone/address/notes
// live in `job_contacts/{collection}__{id}` (no client access at all) and
// are copied onto the job the moment a partner claims it. A job born
// already assigned (patient picked that provider, or ambulance auto-match)
// keeps full details from the start — only one provider can read it.
const _POOL_JOB_SPECS = {
  diagnostic_bookings:  { providerField: "labId",             areaField: "address",         hidden: ["patientPhone", "address", "notes"],   terminal: ["completed", "cancelled", "rejected", "expired"] },
  pharmacy_orders:      { providerField: "pharmacyId",        areaField: "deliveryAddress", hidden: ["patientPhone", "deliveryAddress"],    terminal: ["delivered", "cancelled"] },
  ambulance_requests:   { providerField: "ambulanceId",       areaField: "pickupAddress",   hidden: ["patientPhone", "pickupAddress", "pickupLat", "pickupLng"], terminal: ["completed", "cancelled"], roundLatLng: ["pickupLat", "pickupLng"] },
  caregiver_visits:     { providerField: "caregiverId",       areaField: "address",         hidden: ["patientPhone", "address"],            terminal: ["completed", "cancelled", "missed"] },
  physio_sessions:      { providerField: "physiotherapistId", areaField: "address",         hidden: ["patientPhone", "address", "notes"],   terminal: ["completed", "cancelled", "expired"] },
  counselling_sessions: { providerField: "counsellorId",      areaField: "address",         hidden: ["patientPhone", "address", "notes"],   terminal: ["completed", "cancelled", "expired"] },
};

// "Flat 4B, 12 MG Road, Indiranagar, Bengaluru 560038" -> "Indiranagar,
// Bengaluru 560038": enough to judge distance, not enough to find the door.
function _coarseArea(address) {
  const parts = String(address || "").split(",").map((p) => p.trim()).filter(Boolean);
  if (parts.length <= 1) return "";
  return parts.slice(-Math.min(2, parts.length - 1)).join(", ");
}

function _splitPoolJob(collection, docId, full) {
  const spec = _POOL_JOB_SPECS[collection];
  if (!spec || full[spec.providerField]) return { doc: full, contact: null };
  const contact = { collection, docId, patientName: full.patientName || "", createdAt: FieldValue.serverTimestamp() };
  const doc = { ...full, contactWithheld: true };
  for (const f of spec.hidden) {
    contact[f] = full[f] ?? null;
    doc[f] = typeof full[f] === "number" ? null : "";
  }
  doc[spec.areaField] = _coarseArea(full[spec.areaField]);
  for (const f of spec.roundLatLng || []) {
    if (typeof full[f] === "number") doc[f] = Math.round(full[f] * 100) / 100; // ~1 km
  }
  doc.patientName = String(full.patientName || "Patient").trim().split(/\s+/)[0] || "Patient";
  return { doc, contact };
}

async function _setPoolJob(db, ref, collection, full) {
  const { doc, contact } = _splitPoolJob(collection, ref.id, full);
  // Contact first, so it always exists by the time anyone can claim the job.
  if (contact) await db.collection("job_contacts").doc(`${collection}__${ref.id}`).set(contact);
  await ref.set(doc);
}

function _batchSetPoolJob(batch, db, ref, collection, full) {
  const { doc, contact } = _splitPoolJob(collection, ref.id, full);
  if (contact) batch.set(db.collection("job_contacts").doc(`${collection}__${ref.id}`), contact);
  batch.set(ref, doc);
}

// Called at the top of each job collection's update trigger. The write it
// makes re-fires that trigger once with no status/claim change, which every
// mirror there already treats as a no-op.
async function _releasePoolJobContact(db, collection, docId, before, after) {
  const spec = _POOL_JOB_SPECS[collection];
  if (!spec || !after.contactWithheld) return;
  const contactRef = db.collection("job_contacts").doc(`${collection}__${docId}`);
  try {
    if (!before[spec.providerField] && after[spec.providerField]) {
      const snap = await contactRef.get();
      if (!snap.exists) return;
      const c = snap.data();
      const update = { contactWithheld: false, patientName: c.patientName || after.patientName };
      for (const f of spec.hidden) update[f] = c[f] ?? null;
      await db.collection(collection).doc(docId).update(update);
      await contactRef.delete();
    } else if (spec.terminal.includes(after.status)) {
      await contactRef.delete(); // never claimed — nobody will ever need it
    }
  } catch (err) {
    console.error(`[job_contacts] ${collection}/${docId}:`, err.message);
    throw err; // retried: a claimed job must not stay without contact details
  }
}

// ── Declining an OPEN (unclaimed) pool job ───────────────────────────────
// A partner declining a job nobody has claimed only hides it for themselves:
// the app adds their uid to `declinedBy` and nothing else (firestore.rules'
// `declinedBy` branch), so the shared doc stays 'pending' for every other
// partner and the patient still sees 'pending' (no status change is mirrored).
// Only when EVERY currently active partner of that role has declined is the
// job failed with `failFields` (the same terminal state the hourly stale
// cleanup uses, so the existing mirror + auto-refund path runs). Otherwise it
// just waits for someone to claim it or for the stale cleanup to expire it.
// Declining a PINNED (directly assigned) booking is unchanged: the app rejects
// it outright (status change), which refunds.
async function _failPoolJobIfAllDeclined(db, collection, profileCollection, docId, before, after, failFields) {
  const spec = _POOL_JOB_SPECS[collection];
  if (!spec || after[spec.providerField] || after.status !== "pending") return;
  const declined = Array.isArray(after.declinedBy) ? after.declinedBy : [];
  if (declined.length === 0 || declined.length === (Array.isArray(before.declinedBy) ? before.declinedBy.length : 0)) return;

  const activeSnap = await db.collection(profileCollection).where("status", "==", "active").select().get();
  if (activeSnap.empty) return;
  const declinedSet = new Set(declined);
  if (!activeSnap.docs.every((d) => declinedSet.has(d.id))) return;

  const ref = db.collection(collection).doc(docId);
  const failed = await db.runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data();
    if (!cur || cur[spec.providerField] || cur.status !== "pending") return false;
    tx.update(ref, { ...failFields, updatedAt: FieldValue.serverTimestamp() });
    return true;
  });
  if (failed) console.log(`[pool_decline] ${collection}/${docId} declined by every active ${profileCollection} -> ${failFields.status}`);
}

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
  _emitLog(severity, payload);
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
        if (labSnap.data().acceptingBookings === false) {
          // The lab paused new bookings (Zomato-style closed switch).
          await _rejectPinnedProviderNotAccepting(
            db, "service_requests", requestId, data, labSnap.data().name, "lab");
          return;
        }
        pinnedLabId = details.sourceLabId;
      } else {
        _logLab("WARNING", "source_lab_inactive_falling_back_to_pool", {
          requestId, sourceLabId: details.sourceLabId,
        });
      }
    }

    await _setPoolJob(db, bookingRef, "diagnostic_bookings", {
      sourceRequestId: requestId,
      type: data.type,
      testName: details.testName || data.serviceName || "Diagnostic Test",
      // Server-stamped `amount` first; client serviceDetails.price only as a
      // last-resort display fallback when nothing was stamped.
      price: data.amount ?? details.price ?? 0,
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
    const providerId = await db.runTransaction(async (tx) => {
      const bookingSnap = await tx.get(bookingRef);
      if (!bookingSnap.exists) return null;
      const currentStatus = bookingSnap.data().status;
      if (["completed", "cancelled", "rejected", "expired"].includes(currentStatus)) {
        _logLab("INFO", "cancel_mirror_skipped_terminal", { requestId, currentStatus });
        return null;
      }
      tx.update(bookingRef, { status: "cancelled", cancelledBy: "patient", updatedAt: FieldValue.serverTimestamp() });
      return bookingSnap.data().labId || null;
    });
    _logLab("INFO", "diagnostic_booking_cancelled_by_patient", { requestId });
    await _notifyProviderOfPatientCancel(db, providerId, { serviceType: "diagnostics", bookingId: requestId, what: "lab test booking" });
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
    await _releasePoolJobContact(db, "diagnostic_bookings", bookingId, before, after);
    await _failPoolJobIfAllDeclined(db, "diagnostic_bookings", "lab_profiles", bookingId, before, after, { status: "expired" });

    const statusChanged = before.status !== after.status;
    await _autoRefundOnProviderFailure(db, before, after, ["rejected", "expired", "cancelled"], "service_requests",
      after.sourceRequestId || bookingId, "The lab declined or could not take this booking");
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
//   service_requests[equipment] create -> NO LONGER mirrored here: equipment is
//                                       vendor-only (equipment_orders). The
//                                       pharmacy_orders equipment mirrors below
//                                       remain only so legacy in-flight pool
//                                       orders created before that change finish.
//   pharmacy_orders (pharmacy updates) -> orders (status only, medicine)
//                                       -> service_requests (status only, equipment)
// ══════════════════════════════════════════════════════════════════════════

const _PHARMACY_STALE_PENDING_HOURS = 24;

function _logPharmacy(severity, event, data = {}) {
  const payload = { severity, module: "pharmacy", event, ...data };
  _emitLog(severity, payload);
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
        if (pharmacySnap.data().acceptingOrders === false) {
          // The pharmacy paused new orders (Zomato-style closed switch).
          await _rejectPinnedProviderNotAccepting(
            db, "orders", orderId, data, pharmacySnap.data().name, "pharmacy");
          return;
        }
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
    _batchSetPoolJob(batch, db, pharmacyOrderRef, "pharmacy_orders", {
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

// ── 2) Route new equipment service_requests to their equipment vendor ──────
// Equipment is vendor-only (owner decision): an order must be pinned to an
// active equipment_profiles vendor via details.sourceVendorId. There is no
// pharmacy-pool fallback any more — a request without a valid vendor is
// cancelled by "system" and refunded (see _rejectEquipmentVendorRequired).
exports.onEquipmentServiceRequestCreated = onDocumentCreated(
  "service_requests/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (data.type !== "equipment") return;

    const db = getFirestore();
    const requestId = event.params.requestId;

    const details = data.serviceDetails || {};
    const amount = data.amount ?? details.purchasePrice ?? details.pricePerDay ?? 0;

    if (await _routeEquipmentRequestToVendor(db, requestId, data, details, amount)) return;

    await _rejectEquipmentVendorRequired(db, requestId, data);
  }
);

// Once the pharmacy accepts a prescription it is frozen for both sides —
// same definition as _orderPrescriptionLocked in firestore.rules and
// isPrescriptionLocked in both apps.
const _PRESCRIPTION_LOCKED_STATUSES = ["verified", "packed", "out_for_delivery", "delivered", "cancelled"];
function _pharmacyPrescriptionLocked(po) {
  return po.prescriptionVerified === true || _PRESCRIPTION_LOCKED_STATUSES.includes(po.status);
}

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

    // Runs as a transaction so a pharmacist verifying at the same moment
    // can't slip between the lock check and the mirror write.
    //  - already in sync (the pharmacy's own copy mirrored onto `orders`, or
    //    our own revert below) -> nothing to do, and no verdict reset;
    //  - prescription already accepted -> refuse: the patient's write landed
    //    in the gap before the lock reached `orders` (firestore.rules only
    //    see `orders`), so put the accepted file back;
    //  - otherwise mirror, and a fresh upload restarts verification.
    const outcome = await db.runTransaction(async (tx) => {
      const snap = await tx.get(pharmacyOrderRef);
      const po = snap.data();
      if ((after.prescriptionUrl ?? null) === (po.prescriptionUrl ?? null)) return "in_sync";
      if (_pharmacyPrescriptionLocked(po)) return { locked: po };
      tx.update(pharmacyOrderRef, {
        prescriptionUrl: after.prescriptionUrl ?? null,
        prescriptionFileType: after.prescriptionFileType ?? null,
        prescriptionUploadedAt: after.prescriptionUploadedAt ?? FieldValue.serverTimestamp(),
        prescriptionSource: after.prescriptionUrl ? "patient" : null,
        prescriptionVerified: null,
        prescriptionRejectedReason: null,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return "mirrored";
    });

    if (outcome === "in_sync") return;
    if (outcome.locked) {
      const po = outcome.locked;
      await db.collection("orders").doc(orderId).update({
        prescriptionUrl: po.prescriptionUrl ?? null,
        prescriptionFileType: po.prescriptionFileType ?? null,
        prescriptionUploadedAt: po.prescriptionUploadedAt ?? null,
        prescriptionAttachedBy: po.prescriptionUrl ? (po.prescriptionSource === "pharmacy" ? "pharmacy" : "patient") : null,
        prescriptionVerified: po.prescriptionVerified ?? null,
        prescriptionRejectedReason: po.prescriptionRejectedReason ?? null,
      });
      _logPharmacy("WARNING", "prescription_change_refused_locked", { orderId, status: po.status });
      return;
    }
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
async function _mirrorPharmacyCancellation(db, orderId, { medicine = false } = {}) {
  const pharmacyOrderRef = db.collection("pharmacy_orders").doc(orderId);
  const { refusedStatus, pharmacyId } = await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(pharmacyOrderRef);
    if (!orderSnap.exists) return {};
    const currentStatus = orderSnap.data().status;
    if (["delivered", "cancelled"].includes(currentStatus)) {
      _logPharmacy("INFO", "cancel_mirror_skipped_terminal", { orderId, currentStatus });
      return {};
    }
    // Medicine orders are only cancellable until packed (firestore.rules
    // enforces that on `orders`, but `orders` can lag the pharmacy by a
    // mirror hop). If the pharmacy packed first, the cancel loses.
    if (medicine && ["packed", "out_for_delivery"].includes(currentStatus)) return { refusedStatus: currentStatus };
    tx.update(pharmacyOrderRef, { status: "cancelled", cancelledBy: "patient", updatedAt: FieldValue.serverTimestamp() });
    return { pharmacyId: orderSnap.data().pharmacyId || null };
  });
  if (refusedStatus) {
    await db.collection("orders").doc(orderId).update({
      status: _PHARMACY_TO_ORDER_STATUS[refusedStatus],
      cancelReason: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    _logPharmacy("WARNING", "patient_cancel_refused_already_packed", { orderId, refusedStatus });
    return;
  }
  _logPharmacy("INFO", "pharmacy_order_cancelled_by_patient", { orderId });
  await _notifyProviderOfPatientCancel(db, pharmacyId, {
    serviceType: medicine ? "medicine" : "equipment", bookingId: orderId, what: "order",
  });
}

exports.onMedicineOrderCancelledByPatient = onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status) return;
    if (after.status !== "cancelled") return;
    await _mirrorPharmacyCancellation(getFirestore(), event.params.orderId, { medicine: true });
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
    await _releasePoolJobContact(db, "pharmacy_orders", orderId, before, after);
    await _failPoolJobIfAllDeclined(db, "pharmacy_orders", "pharmacy_profiles", orderId, before, after, { status: "cancelled" });

    const statusChanged = before.status !== after.status;
    const deliveryPersonChanged = before.deliveryPersonName !== after.deliveryPersonName;
    const prescriptionDecisionChanged = before.prescriptionVerified !== after.prescriptionVerified;
    const isMedicine = after.sourceCollection === "orders";
    await _autoRefundOnProviderFailure(db, before, after, ["cancelled"],
      after.sourceCollection || "orders", after.sourceId || orderId, "The pharmacy declined or cancelled this order");

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

    // ── Pharmacy-attached prescription copy (medicine orders only) ────────
    // uploadPrescriptionPhoto marks its write with prescriptionSource:
    // 'pharmacy'; patient uploads mirrored in by onOrderPrescriptionUploaded
    // carry 'patient' and are skipped here, so this never echoes. The
    // resulting `orders` write re-fires onOrderPrescriptionUploaded, which
    // sees both copies in sync and does nothing.
    if (isMedicine && after.prescriptionSource === "pharmacy" &&
        before.prescriptionUrl !== after.prescriptionUrl) {
      await db.collection(after.sourceCollection).doc(after.sourceId || orderId).update({
        prescriptionUrl: after.prescriptionUrl ?? null,
        prescriptionFileType: after.prescriptionFileType ?? null,
        prescriptionUploadedAt: after.prescriptionUploadedAt ?? FieldValue.serverTimestamp(),
        prescriptionAttachedBy: "pharmacy",
        updatedAt: FieldValue.serverTimestamp(),
      }).then(
        () => _logPharmacy("INFO", "pharmacy_prescription_mirrored_to_order", { orderId }),
        (err) => {
          _logPharmacy("ERROR", "pharmacy_prescription_mirror_failed", { orderId, error: err.message });
          mirrorError = err;
        },
      );
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
// ── Medical Equipment vendor module ─────────────────────────────────────────
//
// "Hotel / menu" model, same as Pharmacy and Lab:
//   - A vendor self-registers (equipment_profiles/{uid}, status 'pending').
//   - Admin approves it (status 'active').
//   - The vendor manages its own menu at equipment_profiles/{uid}/items/{id}
//     (price, stock, Available / Sold out). Nobody else reads that directly.
//   - These triggers publish it for patients:
//       items  -> services/eqi_{vendorId}_{itemId}   (type 'equipment')
//       vendor -> equipment_vendors/{vendorId}
//     which are the two collections the patient app ALREADY browses
//     (vendor list -> that vendor's menu), so it needs no new reads.
//   - A patient booking (service_requests, type 'equipment', with
//     serviceDetails.sourceVendorId) is pinned to that vendor in
//     equipment_orders, which the vendor works through
//     pending -> accepted -> out_for_delivery -> delivered (-> returned).
//   - Stock is held when the vendor accepts (client-side transaction sets
//     stockHeld) and released here when an order is cancelled / rejected /
//     returned, so the menu's "left in stock" is always live.
// ══════════════════════════════════════════════════════════════════════════

function _logEquipment(severity, event, data = {}) {
  const payload = { severity, module: "equipment", event, ...data };
  _emitLog(severity, payload);
}

const _EQUIPMENT_STALE_PENDING_HOURS = 12;

function _equipmentServiceRef(db, vendorId, itemId) {
  return db.collection("services").doc(`eqi_${vendorId}_${itemId}`);
}

// What a patient sees on the vendor's menu. The doc is always published
// (`isEnabled`) while the vendor is active so a sold-out item stays visible as
// "Sold out" rather than silently vanishing; `isAvailable` is what gates
// booking, and folds in the vendor's own open/closed switch.
function _equipmentServiceDoc(item, vendorId, itemId, vendor) {
  const stock = Number(item.stock ?? 0);
  const offersRent = item.offersRent !== false && Number(item.rentPricePerDay ?? 0) > 0;
  const offersBuy = item.offersBuy === true && Number(item.buyPrice ?? 0) > 0;
  const available = item.isAvailable !== false && stock > 0 && vendor.acceptingOrders !== false;
  return {
    type: "equipment",
    name: item.name || "",
    description: item.description || "",
    imageUrl: item.imageUrl || "",
    category: item.category || "",
    price: offersRent ? Number(item.rentPricePerDay) : 0,
    purchasePrice: offersBuy ? Number(item.buyPrice) : 0,
    deposit: Number(item.deposit ?? 0),
    stock,
    isEnabled: true,
    isAvailable: available,
    sourceVendorId: vendorId,
    sourceItemId: itemId,
    vendorName: vendor.name || "",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function _equipmentVendorDoc(vendor) {
  return {
    name: vendor.name || "Equipment Vendor",
    city: vendor.city || "",
    address: vendor.address || "",
    phone: vendor.phone || "",
    lat: vendor.latitude ?? null,
    lng: vendor.longitude ?? null,
    photoUrl: vendor.photoUrl || "",
    rating: vendor.rating ?? 0,
    totalReviews: vendor.totalReviews ?? 0,
    deliveryAvailable: vendor.deliveryAvailable !== false,
    categories: Array.isArray(vendor.categoriesOffered) ? vendor.categoriesOffered : [],
    acceptingOrders: vendor.acceptingOrders !== false,
    isEnabled: true,
    source: "partner",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

exports.onEquipmentItemWrite = onDocumentWritten(
  "equipment_profiles/{vendorId}/items/{itemId}",
  async (event) => {
    const { vendorId, itemId } = event.params;
    const db = getFirestore();
    const ref = _equipmentServiceRef(db, vendorId, itemId);

    const after = event.data.after;
    if (!after.exists) {
      await ref.delete().catch(() => {});
      _logEquipment("INFO", "item_mirror_deleted", { vendorId, itemId });
      return;
    }

    const vendorSnap = await db.collection("equipment_profiles").doc(vendorId).get();
    const vendor = vendorSnap.exists ? vendorSnap.data() : null;
    if (!vendor || vendor.status !== "active") {
      // Pending / suspended vendors keep their private menu but stay out of
      // the patient catalogue until (re)approved — the status sweep below
      // publishes every existing item on that transition.
      await ref.delete().catch(() => {});
      return;
    }

    await ref.set(_equipmentServiceDoc(after.data(), vendorId, itemId, vendor), { merge: true });
    _logEquipment("INFO", "item_mirror_synced", { vendorId, itemId });
  }
);

// Vendor-level changes: approval / suspension, the shop open-closed switch,
// and profile edits (name, location, photo) all need to reach the patient
// side. Items are re-swept only when something they embed actually changed.
exports.onEquipmentProfileWriteForVisibility = onDocumentUpdated(
  "equipment_profiles/{vendorId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    const vendorId = event.params.vendorId;
    const db = getFirestore();
    const vendorRef = db.collection("equipment_vendors").doc(vendorId);

    if (after.status !== "active") {
      if (before.status === "active") {
        await vendorRef.delete().catch(() => {});
        await _sweepEquipmentItems(db, vendorId, after, false);
      }
      return;
    }

    // The profile doc also changes for reasons patients never see (fcmToken,
    // pendingChanges, document verification) — don't rewrite the published
    // vendor doc for those.
    const visible = (v) => { const d = _equipmentVendorDoc(v); delete d.updatedAt; return JSON.stringify(d); };
    if (before.status === "active" && visible(before) === visible(after)) return;

    await vendorRef.set(_equipmentVendorDoc(after), { merge: true });

    const becameActive = before.status !== "active";
    const embeddedChanged =
      before.acceptingOrders !== after.acceptingOrders || before.name !== after.name;
    if (becameActive || embeddedChanged) {
      await _sweepEquipmentItems(db, vendorId, after, true);
    }
  }
);

async function _sweepEquipmentItems(db, vendorId, vendor, publish) {
  const itemsSnap = await db.collection("equipment_profiles").doc(vendorId).collection("items").get();
  if (itemsSnap.empty) return;
  const batchSize = 400; // Firestore batch write limit is 500.
  for (let i = 0; i < itemsSnap.docs.length; i += batchSize) {
    const batch = db.batch();
    for (const doc of itemsSnap.docs.slice(i, i + batchSize)) {
      const ref = _equipmentServiceRef(db, vendorId, doc.id);
      if (publish) {
        batch.set(ref, _equipmentServiceDoc(doc.data(), vendorId, doc.id, vendor), { merge: true });
      } else {
        batch.delete(ref);
      }
    }
    await batch.commit();
  }
  _logEquipment("INFO", publish ? "items_bulk_synced" : "items_bulk_hidden", { vendorId, count: itemsSnap.size });
}

exports.onEquipmentProfileApproved = onDocumentUpdated("equipment_profiles/{uid}", async (event) => {
  await _notifyPartnerApproved(
    getFirestore(), getMessaging(), "equipment", event.params.uid,
    event.data.before.data(), event.data.after.data(),
  );
});

// Called from onEquipmentServiceRequestCreated. Returns true when the request
// was handled here (pinned to an active partner vendor), false when it has no
// valid vendor: the caller then rejects + refunds it (no pharmacy-pool fallback).
async function _routeEquipmentRequestToVendor(db, requestId, data, details, amount) {
  const vendorId = details.sourceVendorId;
  if (!vendorId || !details.sourceItemId) return false;

  const vendorSnap = await db.collection("equipment_profiles").doc(String(vendorId)).get();
  if (!vendorSnap.exists || vendorSnap.data().status !== "active") {
    _logEquipment("INFO", "vendor_not_an_active_partner_rejecting", { requestId, vendorId });
    return false;
  }
  const vendor = vendorSnap.data();

  const orderRef = db.collection("equipment_orders").doc(requestId);
  if ((await orderRef.get()).exists) {
    _logEquipment("INFO", "equipment_order_create_skipped_existing", { requestId });
    return true;
  }

  // A shop that paused orders is rejected exactly like the pharmacy / lab
  // case (system cancel + auto-refund + one patient message) instead of
  // creating an order only to reject it.
  if (vendor.acceptingOrders === false) {
    await _rejectPinnedProviderNotAccepting(db, "service_requests", requestId, data, vendor.name, "vendor");
    _logEquipment("WARNING", "equipment_order_rejected_vendor_not_accepting", { requestId, vendorId });
    return true;
  }

  const quantity = Math.max(1, Number(details.quantity) || 1);

  // The patient's app already hides sold-out items, but two patients can book
  // the last unit at once (or the vendor can close up between browse and pay).
  // Such an order is created and immediately rejected, which runs the normal
  // status path: patient notified, payment auto-refunded.
  let unavailableReason = null;
  if (details.sourceItemId) {
    const itemSnap = await db.collection("equipment_profiles").doc(String(vendorId))
      .collection("items").doc(String(details.sourceItemId)).get();
    if (!itemSnap.exists) {
      unavailableReason = "This item is no longer on the menu.";
    } else if (itemSnap.data().isAvailable === false || Number(itemSnap.data().stock ?? 0) < quantity) {
      unavailableReason = "This item just sold out.";
    }
  }

  await orderRef.set({
    sourceCollection: "service_requests",
    sourceId: requestId,
    orderType: "equipment",
    vendorId: String(vendorId),
    vendorName: vendor.name || "",
    status: "pending",
    patientId: data.patientId,
    patientName: data.patientName || "Patient",
    patientPhone: data.patientPhone || "",
    deliveryAddress: data.address || "",
    itemId: details.sourceItemId || null,
    itemName: details.equipmentName || data.serviceName || "Medical Equipment",
    mode: details.mode === "rent" ? "rent" : "buy",
    rentalDays: Number(details.rentalDays) || 0,
    pricePerDay: Number(details.pricePerDay) || 0,
    quantity,
    deposit: Number(details.deposit) || 0,
    totalAmount: amount,
    preferredDate: data.preferredDate || "",
    preferredTime: data.preferredTime || "",
    notes: data.notes || "",
    paymentId: data.paymentId || null,
    stockHeld: false,
    createdAt: data.createdAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  _logEquipment("INFO", "equipment_order_created", { orderId: requestId, vendorId });

  if (unavailableReason) {
    await orderRef.update({
      status: "rejected", cancelledBy: "system", cancelReason: unavailableReason,
      updatedAt: FieldValue.serverTimestamp(),
    });
    _logEquipment("WARNING", "equipment_order_auto_rejected", { orderId: requestId, vendorId, reason: unavailableReason });
    return true;
  }

  await _sendProviderNotification(db, getMessaging(), String(vendorId), {
    title: "New Equipment Order",
    body: `${quantity} × ${details.equipmentName || data.serviceName || "equipment"} (${details.mode === "rent" ? "rent" : "buy"}) — tap to accept.`,
    type: "new_equipment_order", serviceType: "equipment", bookingId: requestId,
  });
  return true;
}

// Vendor status -> the service_requests vocabulary the patient app already
// understands (see onServiceRequestStatusChange's `equipment` map above).
const _EQUIPMENT_TO_SERVICE_REQUEST_STATUS = {
  accepted:         "accepted",
  out_for_delivery: "in_progress",
  rejected:         "rejected",
  cancelled:        "cancelled",
  returned:         "completed",
};

exports.onEquipmentOrderStatusChange = onDocumentUpdated(
  "equipment_orders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status) return;
    const orderId = event.params.orderId;
    const db = getFirestore();

    await _autoRefundOnProviderFailure(db, before, after, ["rejected", "cancelled"],
      "service_requests", after.sourceId || orderId, "The vendor declined or cancelled this equipment order");

    // Remembered and rethrown at the end so a failed mirror never skips the
    // stock release / ledger below, yet the invocation still fails (retries)
    // instead of reporting a false success.
    let firstError = null;
    const remember = (err) => { firstError = firstError || err; };

    // ── Mirror onto the patient's service_request ─────────────────────────
    // A buy order is finished the moment it is delivered; a rental stays
    // 'in_progress' until it is returned.
    const mapped = after.status === "delivered" && after.mode === "buy"
      ? "completed"
      : _EQUIPMENT_TO_SERVICE_REQUEST_STATUS[after.status];
    if (mapped) {
      try {
        const sourceRef = db.collection(after.sourceCollection || "service_requests").doc(after.sourceId || orderId);
        const current = await sourceRef.get();
        if (current.exists && current.data().status !== mapped) {
          await sourceRef.update({ status: mapped, updatedAt: FieldValue.serverTimestamp() });
        }
      } catch (err) {
        _logEquipment("ERROR", "mirror_to_source_failed", { orderId, error: err.message });
        remember(err);
      }
    }

    // A rental that just arrived keeps the same patient-facing status
    // ('in_progress') it had while out for delivery, so say so explicitly.
    if (after.status === "delivered" && after.mode === "rent" && after.patientId) {
      await _sendPatientNotification(db, getMessaging(), after.patientId, {
        title: "Equipment Delivered",
        body: `${after.itemName || "Your equipment"} has been delivered. Keep it safe — the vendor will arrange pickup when your rental ends.`,
        type: "equipment_delivered", serviceType: "equipment", bookingId: orderId, actionType: "open_service",
      });
    }

    // ── Release held stock when the unit is not leaving for good ──────────
    if (["cancelled", "rejected", "returned"].includes(after.status) && after.stockHeld === true) {
      try {
        await db.runTransaction(async (tx) => {
          const orderRef = db.collection("equipment_orders").doc(orderId);
          const orderSnap = await tx.get(orderRef);
          if (!orderSnap.exists || orderSnap.data().stockHeld !== true) return; // already released
          const itemId = orderSnap.data().itemId;
          let itemRef = null;
          let itemSnap = null;
          if (itemId) {
            itemRef = db.collection("equipment_profiles").doc(after.vendorId).collection("items").doc(itemId);
            itemSnap = await tx.get(itemRef);
          }
          if (itemSnap && itemSnap.exists) {
            tx.update(itemRef, { stock: FieldValue.increment(Math.max(1, Number(orderSnap.data().quantity) || 1)) });
          }
          tx.update(orderRef, { stockHeld: false });
        });
        _logEquipment("INFO", "stock_released", { orderId, status: after.status });
      } catch (err) {
        _logEquipment("ERROR", "stock_release_failed", { orderId, error: err.message });
        remember(err);
      }
    }

    // ── Earnings: credited once, when the equipment is in the patient's hands ──
    if (after.status === "delivered" && before.status !== "delivered") {
      try {
        await _transitionPaymentToEligible(db, {
          sourceCollection: after.sourceCollection || "service_requests",
          sourceId: after.sourceId || orderId,
          providerId: after.vendorId,
          serviceType: "equipment",
        });
        const ledgerRef = db.collection("equipment_transactions").doc(orderId);
        await db.runTransaction(async (tx) => {
          if ((await tx.get(ledgerRef)).exists) return;
          tx.set(ledgerRef, {
            vendorId: after.vendorId,
            orderId,
            type: "earning",
            amount: after.totalAmount ?? 0,
            status: "credited",
            mode: after.mode,
            itemName: after.itemName || "",
            patientName: after.patientName || "Patient",
            createdAt: FieldValue.serverTimestamp(),
          });
        });
      } catch (err) {
        _logEquipment("ERROR", "earnings_credit_failed", { orderId, error: err.message });
        remember(err);
      }
    }

    if (firstError) throw firstError;
  }
);

// Patient cancels their own equipment request. Allowed until the vendor has
// dispatched it; after that the cancel loses and the request is put back.
exports.onEquipmentRequestCancelledByPatient = onDocumentUpdated(
  "service_requests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (after.type !== "equipment") return;
    if (before.status === after.status || after.status !== "cancelled") return;
    const requestId = event.params.requestId;
    const db = getFirestore();
    const orderRef = db.collection("equipment_orders").doc(requestId);

    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(orderRef);
      if (!snap.exists) return {};
      const o = snap.data();
      if (["cancelled", "rejected", "returned"].includes(o.status)) return {};
      if (["out_for_delivery", "delivered"].includes(o.status)) return { refused: o.status };
      tx.update(orderRef, { status: "cancelled", cancelledBy: "patient", updatedAt: FieldValue.serverTimestamp() });
      return { vendorId: o.vendorId };
    });

    if (result.refused) {
      await db.collection("service_requests").doc(requestId).update({
        status: "in_progress", updatedAt: FieldValue.serverTimestamp(),
      });
      _logEquipment("WARNING", "patient_cancel_refused_already_dispatched", { requestId, status: result.refused });
      return;
    }
    if (result.vendorId) {
      _logEquipment("INFO", "equipment_order_cancelled_by_patient", { requestId });
      await _notifyProviderOfPatientCancel(db, result.vendorId, {
        serviceType: "equipment", bookingId: requestId, what: "order",
      });
    }
  }
);

// ── Ambulance live-trip feed cleanup ─────────────────────────────────────────
// `ambulance_live/{requestId}` (firestore.rules) holds the driver's GPS only for
// the duration of a trip. Delete it the moment the request leaves the active
// states, so the patient's last-known driver position doesn't outlive the trip.
exports.onAmbulanceRequestEndedCleanupLive = onDocumentUpdated(
  "ambulance_requests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (before.status === after.status) return;
    if (!["completed", "cancelled"].includes(after.status)) return;
    await getFirestore().collection("ambulance_live").doc(event.params.requestId).delete().catch(() => {});
  }
);

// A vendor that never answers shouldn't leave a paid patient waiting: after
// the window the order is cancelled and the status trigger refunds it.
exports.cleanupStaleEquipmentOrders = onSchedule({ schedule: "every 60 minutes", timeZone: "UTC" }, async () => {
  const db = getFirestore();
  const cutoff = Timestamp.fromDate(new Date(Date.now() - _EQUIPMENT_STALE_PENDING_HOURS * 60 * 60 * 1000));
  const staleSnap = await db.collection("equipment_orders")
    .where("status", "==", "pending")
    .where("createdAt", "<", cutoff)
    .limit(200)
    .get();
  if (staleSnap.empty) {
    _logEquipment("INFO", "stale_cleanup_none_found");
    return;
  }
  const { updated, skipped } = await _expireStaleDocs(staleSnap.docs, {
    status: "cancelled", cancelledBy: "system",
    cancelReason: "The vendor did not respond in time.",
    updatedAt: FieldValue.serverTimestamp(),
  });
  _logEquipment("INFO", "stale_cleanup_cancelled", { count: updated, skippedConcurrentlyModified: skipped });
});

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
  _emitLog(severity, payload);
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
// `requestedTypeKey` ('basic'|'als'|'icu'): only drivers whose vehicleTypeKey
// equals it are candidates; null/undefined (legacy request) => any driver.
const AmbH = require("./ambulance_match_helpers");
async function _findNearestOnlineAmbulance(db, lat, lng, excludeIds = [], requestedTypeKey = null) {
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
    if (!AmbH.driverMatchesRequestedType(doc.data(), requestedTypeKey)) continue;
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

// ambulance_profiles carries the driver's name as `driverName` (there is no
// `name` field), so _providerDisplayName cannot resolve it. The patient app
// shows `service_requests.assignedToName`, falling back to the raw uid.
async function _ambulanceDisplayName(db, id) {
  if (!id) return null;
  try {
    const snap = await db.collection("ambulance_profiles").doc(id).get();
    const d = snap.exists ? snap.data() : null;
    return (d && (d.driverName || d.name)) || null;
  } catch {
    return null;
  }
}

// ── Range-based ambulance fare ──────────────────────────────────────────────
// Bookings carry a rate range (serviceDetails.fareMin/fareMax, from
// app_config/ambulance_rates at booking time) and are CHARGED the max
// (`amount`). The final fare is the matched driver's own
// `ambulance_profiles.ratePerTrip` clamped into that range (range min when the
// driver hasn't set one). Legacy bookings without a range return null and keep
// the old `fare` behaviour untouched.
function _ambulanceFareRange(details) {
  const min = Number(details?.fareMin);
  const max = Number(details?.fareMax);
  if (!Number.isFinite(min) || !Number.isFinite(max) || min < 0 || max < min) return null;
  return { min, max };
}

// RATE LOCK: when `lockedRate` (ambulance_requests.lockedRate, snapshotted when
// the driver accepted / was matched) is a valid number it is used instead of the
// driver's CURRENT ratePerTrip, so a later rate change never affects a trip that
// was already accepted. Legacy requests without a lock fall back to the live rate.
async function _ambulanceFinalFare(db, ambulanceId, range, lockedRate = null) {
  if (!range || !ambulanceId) return null;
  const locked = (lockedRate === null || lockedRate === undefined || lockedRate === "") ? NaN : Number(lockedRate);
  if (Number.isFinite(locked) && locked >= 0) {
    return _round2(Math.min(range.max, Math.max(range.min, locked)));
  }
  let rate = NaN;
  try {
    const snap = await db.collection("ambulance_profiles").doc(ambulanceId).get();
    rate = Number(snap.exists ? snap.get("ratePerTrip") : NaN);
  } catch (_) { /* fall back to range min */ }
  if (!Number.isFinite(rate) || rate < 0) rate = range.min;
  return _round2(Math.min(range.max, Math.max(range.min, rate)));
}

// Records the final fare on the customer's service_request. The customer was
// charged `amount` (== range max); the gap is `fareDifference`. Only a booking
// with a real payment (paymentId) is flagged `refundDifferencePending` - the
// refund machinery (_refundPayment) is full-refund only, so the partial
// refund of the difference is NOT automated here (needs an owner/finance
// decision). Test bookings (no paymentId) just carry fareFinal, which the test
// credit reads.
async function _recordAmbulanceFinalFare(db, serviceRequestId, finalFare, { completed = false, ambulanceId = null, lockedRate = null, lock = false } = {}) {
  const ref = db.collection("service_requests").doc(serviceRequestId);
  const snap = await ref.get();
  if (!snap.exists) return { deferLedger: false };
  const d = snap.data();

  // PAY-AFTER-TRIP (real mode): the booking carried no up-front charge. On
  // completion the final fare is re-resolved against the SERVER rate range
  // (app_config/ambulance_rates, not the client-written fareMin/fareMax), the
  // platform fee is added and the booking goes to 'payment_due'. Only the
  // pay_after_trip -> payment_due edge writes these, so redeliveries are no-ops.
  if (completed && d.paymentStatus === "pay_after_trip") {
    const serverRange = await _ambulanceServerRange(db, d.serviceDetails);
    let fare = finalFare;
    if (serverRange && ambulanceId) {
      // Prefer the rate locked at accept (passed in, else the service_request's
      // lockedFare) over the driver's current ratePerTrip.
      const f = await _ambulanceFinalFare(db, ambulanceId, serverRange,
        lockedRate !== null && lockedRate !== undefined ? lockedRate : d.lockedFare);
      if (f !== null) fare = f;
    }
    if (Number.isFinite(fare) && fare > 0) {
      const feeCfg = await db.collection("app_config").doc("platform_fee").get();
      const platformFee = PriceH.platformFeeFor(feeCfg.exists ? feeCfg.data() : null, "ambulance");
      const amountDue = _round2(fare + platformFee);
      await ref.update({
        fareFinal: fare,
        fareDifference: 0,
        platformFee,
        amountDue,
        paymentStatus: "payment_due",
        paymentDueAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (d.patientId) {
        await _sendPatientNotification(db, getMessaging(), d.patientId, {
          title: "Trip completed",
          body: `Trip completed. Please pay ₹${amountDue.toFixed(0)}`,
          type: "ambulance_payment_due", serviceType: "ambulance", bookingId: serviceRequestId,
          actionType: "open_trip_payment", extraData: { amountDue },
        });
      }
      return { deferLedger: true };
    }
    _logAmbulance("ERROR", "pay_after_trip_no_fare", { requestId: serviceRequestId });
    return { deferLedger: true };
  }

  const charged = Number(d.amount);
  const update = { fareFinal: finalFare };
  if (lock) update.lockedFare = finalFare; // rate lock snapshot (set at accept / match, not at completion)
  if (Number.isFinite(charged)) {
    const diff = _round2(Math.max(0, charged - finalFare));
    update.fareDifference = diff;
    if (completed && d.paymentId && diff > 0) update.refundDifferencePending = true;
  }
  const changed = Object.keys(update).some((k) => d[k] !== update[k]);
  if (changed) await ref.update(update);
  // Already awaiting payment (a redelivered completion): keep the partner
  // ledger deferred until captureTripPayment writes it.
  return { deferLedger: d.paymentStatus === "payment_due" };
}

// Server-side rate range for a vehicle type (admin-set app_config/ambulance_rates),
// so the pay-after-trip amount never depends on the client-written fareMin/fareMax.
// Falls back to the booking's own range only when the config is unusable.
async function _ambulanceServerRange(db, details) {
  const raw = String(details?.ambulanceType || details?.ambulanceTypeKey || "").trim().toLowerCase();
  const key = raw === "basic" ? "basic"
    : (raw === "advanced life support" || raw === "als") ? "als"
      : (raw === "icu ambulance" || raw === "icu") ? "icu" : null;
  try {
    if (key) {
      const cfg = await db.collection("app_config").doc("ambulance_rates").get();
      const r = cfg.exists ? cfg.get("types")?.[key] : null;
      const min = r ? PriceH.parseRupees(r.min) : null;
      const max = r ? PriceH.parseRupees(r.max) : null;
      if (min !== null && max !== null && max >= min) return { min, max };
    }
  } catch (_) { /* fall through to the booking's range */ }
  return _ambulanceFareRange(details);
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

    // Server-side unpaid-trip block: a patient with a completed ambulance trip
    // still 'payment_due' may not book another (the app checks too, but a
    // modified client could skip it). The new booking is pay_after_trip with no
    // payment taken, so it is cancelled by 'system' with NO refund call and no
    // pool job is created.
    if (data.patientId && data.paymentStatus !== "payment_due") {
      try {
        const unpaid = await db.collection("service_requests")
          .where("patientId", "==", data.patientId)
          .where("type", "==", "ambulance")
          .where("paymentStatus", "==", "payment_due")
          .limit(3)
          .get();
        const prev = unpaid.docs.find((u) => u.id !== requestId);
        if (prev) {
          await snap.ref.update({
            status: "cancelled",
            cancelledBy: "system",
            cancelReason: "previous_trip_unpaid",
            updatedAt: FieldValue.serverTimestamp(),
          });
          await _sendPatientNotification(db, getMessaging(), data.patientId, {
            title: "Payment pending",
            body: "Please pay for your previous ambulance trip first",
            type: "ambulance_previous_trip_unpaid", serviceType: "ambulance", bookingId: prev.id,
            actionType: "open_trip_payment",
          }).catch(() => {});
          _logAmbulance("WARNING", "booking_blocked_previous_trip_unpaid", { requestId, patientId: data.patientId });
          return;
        }
      } catch (err) {
        _logAmbulance("WARNING", "unpaid_trip_check_failed", { requestId, error: err.message });
      }
    }

    // Nearest-driver matching: the patient's pickup fix (see PreciseAddress.
    // toBookingMap() in the Flutter app) travels through as
    // serviceDetails.locationData.{lat,lng}. Pin the request straight to the
    // nearest online ambulance instead of dropping it in the open pool — a
    // stale-assignment sweep (reassignStaleAmbulanceAssignments) un-pins it
    // back to the pool if that driver doesn't respond in time.
    // TYPE-AWARE: only drivers whose vehicleTypeKey equals the requested type
    // are candidates (legacy requests without a type match any driver).
    const pickupLat = details.locationData?.lat;
    const pickupLng = details.locationData?.lng;
    const requestedTypeKey = AmbH.requestedAmbulanceTypeKey(details);
    const matchedAmbulanceId = await _findNearestOnlineAmbulance(db, pickupLat, pickupLng, [], requestedTypeKey);
    // Admin-set server range (app_config/ambulance_rates), not the client-written fareMin/fareMax.
    const fareRange = await _ambulanceServerRange(db, details);
    // Pinned straight to a driver: show that driver's own rate (clamped into
    // the range) as the fare instead of the charged max.
    const matchedFare = matchedAmbulanceId
      ? await _ambulanceFinalFare(db, matchedAmbulanceId, fareRange) : null;

    await _setPoolJob(db, requestRef, "ambulance_requests", {
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
      // Pay-after-trip bookings carry amount 0 (nothing charged up front), so
      // an unclaimed job shows the range minimum until a driver's own rate applies.
      fare: matchedFare ?? (fareRange && !(Number(data.amount) > 0) ? fareRange.min : (data.amount ?? 0)),
      ...(fareRange ? { fareMin: fareRange.min, fareMax: fareRange.max } : {}),
      // Rate lock (provisional while pinned; re-locked when the driver accepts).
      ...(matchedFare !== null ? { lockedRate: matchedFare, lockedRateAmbulanceId: matchedAmbulanceId } : {}),
      emergencyType: _ambulanceEmergencyType(details.ambulanceType),
      // Requested vehicle type: only drivers with this vehicleTypeKey may be
      // matched / claim it (null for legacy bookings => any driver).
      ambulanceTypeKey: requestedTypeKey,
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
      const matchedName = await _ambulanceDisplayName(db, matchedAmbulanceId);
      await db.collection("service_requests").doc(requestId).update({
        assignedTo: matchedAmbulanceId,
        ...(matchedName ? { assignedToName: matchedName } : {}),
      }).catch((err) => {
        _logAmbulance("WARNING", "initial_assignedTo_mirror_failed", { requestId, error: err.message });
      });
    }

    if (matchedFare !== null) {
      await _recordAmbulanceFinalFare(db, requestId, matchedFare, { lock: true }).catch((err) =>
        _logAmbulance("WARNING", "provisional_fare_record_failed", { requestId, error: err.message }));
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

// ── 1a) A matched driver tapped Decline ──────────────────────────────────────
// The partner app flags `declineRequested` instead of cancelling (see
// AmbulanceRequestService.reject). Treated exactly like a timeout, just
// immediate: hand the request to the next-nearest online driver who hasn't
// been tried or declined. Only when nobody is left is it cancelled — which
// the status mirror shows the patient as declined, and which refunds them
// (_autoRefundOnProviderFailure).
async function _redispatchDeclinedAmbulance(db, requestId) {
  const ref = db.collection("ambulance_requests").doc(requestId);
  const snap = await ref.get();
  const d = snap.data();
  if (!d || d.status !== "pending" || !d.declineRequested) return;

  const decliner = d.ambulanceId || null;
  const declinedBy = [...new Set([...(d.declinedBy || []), decliner].filter(Boolean))];
  const tried = [...new Set([...(d.matchAttempts || []), ...declinedBy])];
  const next = await _findNearestOnlineAmbulance(db, d.pickupLat, d.pickupLng, tried,
    AmbH.normalizeAmbulanceTypeKey(d.ambulanceTypeKey));

  try {
    if (next) {
      await ref.update({
        ambulanceId: next,
        matchAttempts: [...new Set([...(d.matchAttempts || []), next])],
        declinedBy,
        declineRequested: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { lastUpdateTime: snap.updateTime });
      await _sendProviderNotification(db, getMessaging(), next, {
        title: "🚑 New Ambulance Request",
        body: "A new ambulance request needs your response now.",
        type: "new_ambulance_request", serviceType: "ambulance", bookingId: requestId,
      });
      _logAmbulance("INFO", "declined_request_reassigned", { requestId, decliner, next });
    } else {
      await ref.update({
        status: "cancelled",
        cancelReason: "No ambulance available nearby",
        declinedBy,
        declineRequested: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { lastUpdateTime: snap.updateTime });
      _logAmbulance("WARNING", "declined_request_no_driver_left", { requestId, decliner });
    }
  } catch {
    _logAmbulance("INFO", "declined_request_changed_concurrently", { requestId });
  }
}

// ── 1b) Reassign a matched-but-unanswered request ────────────────────────────
// A request pinned to the nearest driver above still needs that driver to
// actually tap Accept. If they don't within the timeout — asleep, busy,
// phone face-down — the patient must not be stuck waiting on one driver
// forever. Runs every minute (an emergency queue can't wait an hour like
// Lab/Pharmacy's stale cleanup does): tries the next-nearest online driver,
// excluding everyone already tried on this request, and only falls back to
// the fully-open pool once no more online candidates exist.
const _AMBULANCE_MATCH_TIMEOUT_SECONDS = 45;

// If NO ambulance has accepted a request this many minutes after it was
// created, the admin is alerted ONCE (admin_alerts + push, type
// 'ambulance_unaccepted'; guarded by `adminAlertedAt` on the request doc).
// Owner-tunable. The 2-hour auto-cancel (_AMBULANCE_STALE_PENDING_HOURS) is
// unchanged.
const _AMBULANCE_UNACCEPTED_ALERT_MINUTES = 10;

// Owner-customisable via app_config/ambulance_settings.unacceptedAlertMinutes
// (1..240, Director-edited in the admin panel). Falls back to the constant above
// when missing/invalid. `cache` is a per-invocation holder ({}), so one sweep
// reads the config once.
async function _ambulanceAlertMinutes(db, cache = {}) {
  if (cache.minutes !== undefined) return cache.minutes;
  let minutes = _AMBULANCE_UNACCEPTED_ALERT_MINUTES;
  try {
    const snap = await db.collection("app_config").doc("ambulance_settings").get();
    const v = snap.exists ? Number(snap.get("unacceptedAlertMinutes")) : NaN;
    if (Number.isFinite(v) && v >= 1 && v <= 240) minutes = v;
  } catch (_) { /* keep the default */ }
  cache.minutes = minutes;
  return minutes;
}

// Idempotent: claims `adminAlertedAt` in a transaction (without touching
// `updatedAt`, which the reassign sweep uses as its staleness clock) and only
// the invocation that wins the claim sends the alert. Admin SDK write, so
// firestore.rules are not involved.
async function _alertAdminIfAmbulanceUnaccepted(db, doc, data, cache = {}) {
  if (data.status !== "pending" || data.adminAlertedAt) return false;
  const createdAt = data.createdAt?.toDate?.();
  const alertMinutes = await _ambulanceAlertMinutes(db, cache);
  if (!createdAt || Date.now() - createdAt.getTime() < alertMinutes * 60 * 1000) return false;
  const claimed = await db.runTransaction(async (tx) => {
    const fresh = await tx.get(doc.ref);
    if (!fresh.exists || fresh.get("status") !== "pending" || fresh.get("adminAlertedAt")) return false;
    tx.update(doc.ref, { adminAlertedAt: FieldValue.serverTimestamp() });
    return true;
  });
  if (!claimed) return false;
  await _sendAdminAlert(db, getMessaging(), {
    title: "Ambulance Request Not Accepted",
    body: `No ${AmbH.normalizeAmbulanceTypeKey(data.ambulanceTypeKey)
      ? `${AmbH.ambulanceTypeLabel(AmbH.normalizeAmbulanceTypeKey(data.ambulanceTypeKey))} ` : ""}ambulance has accepted request ${doc.id} for ${alertMinutes}+ minutes. Please arrange one manually.`,
    type: "ambulance_unaccepted",
    extraData: { requestId: doc.id, patientId: data.patientId || "" },
  }).catch(() => {});
  return true;
}

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

    const alertCache = {};
    for (const doc of pendingSnap.docs) {
      const data = doc.data();
      await _alertAdminIfAmbulanceUnaccepted(db, doc, data, alertCache).catch((err) =>
        _logAmbulance("WARNING", "unaccepted_alert_failed", { requestId: doc.id, error: err.message }));
      if (!data.ambulanceId) continue; // already open-pool — nothing to reassign.
      const updatedAt = data.updatedAt?.toDate?.() ?? data.createdAt?.toDate?.() ?? new Date(0);
      if (updatedAt > cutoff.toDate()) continue; // matched recently — not stale yet.

      const tried = Array.isArray(data.matchAttempts) ? data.matchAttempts : [];
      const excluded = [...new Set([...tried, ...(data.declinedBy || [])])];
      const next = await _findNearestOnlineAmbulance(db, data.pickupLat, data.pickupLng, excluded,
        AmbH.normalizeAmbulanceTypeKey(data.ambulanceTypeKey));

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

// ── Unpaid ambulance trips (real payments only) ─────────────────────────────
// A completed pay-after-trip booking sits at paymentStatus 'payment_due' until
// captureTripPayment settles it. Reminders go out ~2h and ~24h after
// `paymentDueAt` (stamped in `paymentRemindersSent` so they never repeat).
async function _sendTripPaymentReminder(db, docSnap, tier) {
  const d = docSnap.data();
  const patientId = d.patientId || d.userId;
  if (!patientId) return false;
  const due = Number(d.amountDue) || 0;
  await _sendPatientNotification(db, getMessaging(), patientId, {
    title: tier === "h24" ? "Ambulance payment overdue" : "Ambulance payment reminder",
    body: tier === "h24"
      ? `Your ambulance trip payment of ₹${due.toFixed(0)} is overdue. Please pay now to book again.`
      : `Please pay ₹${due.toFixed(0)} for your completed ambulance trip.`,
    type: "ambulance_payment_reminder", serviceType: "ambulance", bookingId: docSnap.id,
    actionType: "open_trip_payment", extraData: { amountDue: due },
  });
  return true;
}

exports.remindUnpaidAmbulanceTrips = onSchedule(
  { schedule: "every 60 minutes", timeZone: "UTC" },
  async () => {
    const db = getFirestore();
    const snap = await db.collection("service_requests")
      .where("type", "==", "ambulance")
      .where("paymentStatus", "==", "payment_due")
      .limit(500)
      .get();
    let sent = 0;
    for (const doc of snap.docs) {
      const d = doc.data();
      const dueAt = d.paymentDueAt?.toDate?.();
      if (!dueAt) continue;
      const hours = (Date.now() - dueAt.getTime()) / 3600000;
      const marks = d.paymentRemindersSent || {};
      let tier = null;
      if (hours >= 24 && !marks.h24) tier = "h24";
      else if (hours >= 2 && !marks.h2 && !marks.h24) tier = "h2";
      if (!tier) continue;
      try {
        // Stamp first (an unsent reminder is better than a repeated one); a
        // missed 2h tier is covered by the 24h stamp when the sweep was down.
        await doc.ref.update({
          [`paymentRemindersSent.${tier}`]: FieldValue.serverTimestamp(),
          ...(tier === "h24" ? { "paymentRemindersSent.h2": marks.h2 || FieldValue.serverTimestamp() } : {}),
        });
        if (await _sendTripPaymentReminder(db, doc, tier)) sent++;
      } catch (err) {
        _logAmbulance("WARNING", "trip_reminder_failed", { requestId: doc.id, error: err.message });
      }
    }
    _logAmbulance("INFO", "unpaid_trip_reminder_sweep", { scanned: snap.size, sent });
  }
);

// Admin: push a manual reminder for one unpaid trip (Director / Finance).
exports.sendTripPaymentReminder = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  const admin = await _assertAdmin(db, uid);
  const role = admin.get("role") || "director";
  if (!["director", "finance"].includes(role)) {
    throw new HttpsError("permission-denied", "Director or Finance access required.");
  }
  const requestId = request.data?.requestId;
  if (typeof requestId !== "string" || !requestId.trim()) {
    throw new HttpsError("invalid-argument", "requestId is required.");
  }
  _safeId(requestId, "requestId");
  const snap = await db.collection("service_requests").doc(requestId).get();
  if (!snap.exists || snap.get("type") !== "ambulance" || snap.get("paymentStatus") !== "payment_due") {
    throw new HttpsError("failed-precondition", "This trip is not awaiting payment.");
  }
  await _sendTripPaymentReminder(db, snap, "h24");
  await snap.ref.update({ lastManualReminderAt: FieldValue.serverTimestamp() });
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "sendTripPaymentReminder", targetType: "service_requests", targetId: requestId,
    before: null, after: { amountDue: snap.get("amountDue") ?? null },
  }));
  return { success: true };
});

// Admin (Director only): give up on an unpaid trip. Moves it out of
// 'payment_due' (-> 'written_off'), which also lifts the patient's booking block.
exports.markTripWrittenOff = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  const db = getFirestore();
  const admin = await _assertAdmin(db, uid);
  if ((admin.get("role") || "director") !== "director") {
    throw new HttpsError("permission-denied", "Director access required.");
  }
  const { requestId, reason } = request.data || {};
  if (typeof requestId !== "string" || !requestId.trim()) {
    throw new HttpsError("invalid-argument", "requestId is required.");
  }
  _safeId(requestId, "requestId");
  const ref = db.collection("service_requests").doc(requestId);
  // The driver still earns the trip fare: the platform pays it (a synthetic,
  // already-'eligible' payment so the normal settlement queue batches it, plus a
  // platform 'writeoff_expense' ledger debit). The customer's debt is forgiven.
  const writeOffPaymentId = _ledgerId(`writeoff:${requestId.trim()}`);
  const paymentRef = db.collection("payments").doc(writeOffPaymentId);
  const out = await db.runTransaction(async (tx) => {
    // ── Reads ──────────────────────────────────────────────────────────
    const s = await tx.get(ref);
    if (!s.exists || s.get("type") !== "ambulance" || s.get("paymentStatus") !== "payment_due") {
      throw new HttpsError("failed-precondition", "This trip is not awaiting payment.");
    }
    const providerId = s.get("assignedTo") || s.get("ambulanceId") || null;
    const fareFinal = _round2(Number(s.get("fareFinal")));
    const payDriver = !!providerId && fareFinal > 0;
    const existingPay = payDriver ? await tx.get(paymentRef) : null;
    const walletRef = payDriver ? db.collection("provider_wallets").doc(providerId) : null;
    const walletSnap = walletRef ? await tx.get(walletRef) : null;
    const creditNow = payDriver && !existingPay.exists;

    // ── Writes ─────────────────────────────────────────────────────────
    const update = {
      paymentStatus: "written_off",
      writtenOffAt: FieldValue.serverTimestamp(),
      writtenOffBy: uid,
      writeOffReason: typeof reason === "string" ? reason.slice(0, 300) : "",
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (payDriver) update.writeOffPaymentId = writeOffPaymentId;
    tx.update(ref, update);

    if (creditNow) {
      tx.set(paymentRef, {
        paymentId: writeOffPaymentId, patientId: null, providerId, serviceType: "ambulance",
        bookingRef: { collection: "service_requests", id: requestId.trim() },
        originalAmount: fareFinal, discount: 0, couponCode: null,
        paidAmount: 0, walletPortionAmount: 0,
        commissionBase: fareFinal, baseAmount: fareFinal, platformFee: 0, commission: 0,
        providerAmount: fareFinal, commissionFinal: true,
        paymentMethod: "platform_writeoff", razorpayPaymentId: null,
        isWriteOff: true, writtenOffPatientId: s.get("patientId") ?? null,
        status: "completed",
        settlementStatus: "eligible", settlementId: null,
        createdAt: FieldValue.serverTimestamp(),
        completedAt: FieldValue.serverTimestamp(),
        eligibleAt: FieldValue.serverTimestamp(),
      });
      const pendingBefore = walletSnap.exists ? Number(walletSnap.get("pendingEarnings")) || 0 : 0;
      tx.set(walletRef, {
        providerId, serviceType: "ambulance",
        pendingEarnings: _round2(pendingBefore + fareFinal),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid: providerId, walletType: "provider", type: "credit", amount: fareFinal,
        category: "settlement_pending", title: "Earnings (written-off trip, paid by platform)",
        description: "ambulance", source: `payment:${writeOffPaymentId}:eligible`, balanceAfter: null,
      }));
      tx.set(db.collection("wallet_ledger").doc(), _ledgerDoc({
        uid: "platform", walletType: "platform", type: "debit", amount: fareFinal,
        category: "writeoff_expense", title: "Written-off ambulance trip (driver paid by platform)",
        description: `service_requests/${requestId.trim()}`, source: `payment:${writeOffPaymentId}:writeoff_expense`,
        balanceAfter: null,
      }));
    }
    return {
      before: { paymentStatus: "payment_due", amountDue: s.get("amountDue") ?? null, patientId: s.get("patientId") ?? null },
      providerId: creditNow ? providerId : null, fareFinal, creditNow,
      patientName: s.get("patientName") || "Patient",
    };
  });

  if (out.creditNow) {
    // Legacy partner earnings ledger (deferred at completion until payment):
    // written once here instead of by captureTripPayment, which now refuses
    // because the trip is no longer 'payment_due'. create() never duplicates.
    try {
      await db.collection("ambulance_transactions").doc(requestId.trim()).create({
        ambulanceId: out.providerId, requestId: requestId.trim(), type: "earning",
        amount: out.fareFinal, status: "credited", patientName: out.patientName,
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (err) {
      if (err.code !== 6 && !/already exists/i.test(String(err.message))) {
        _logSettlement("WARNING", "writeoff_ledger_write_failed", { requestId, error: err.message });
      }
    }
    _sendProviderNotification(db, getMessaging(), out.providerId, {
      title: "New Earnings", body: "A completed booking is now pending settlement.",
      type: "new_earnings", serviceType: "ambulance",
    }).catch((e) => console.warn(JSON.stringify({ severity: "WARNING", event: "earnings_notification_failed", providerId: out.providerId, error: e && e.message })));
  }
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: uid, action: "markTripWrittenOff", targetType: "service_requests", targetId: requestId,
    before: out.before,
    after: { paymentStatus: "written_off", reason: reason || "", driverPaidFromPlatform: out.creditNow ? out.fareFinal : 0 },
  }));
  return { success: true };
});

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
    const providerId = await db.runTransaction(async (tx) => {
      const reqSnap = await tx.get(requestRef);
      if (!reqSnap.exists) return null;
      const currentStatus = reqSnap.data().status;
      if (["completed", "cancelled"].includes(currentStatus)) {
        _logAmbulance("INFO", "cancel_mirror_skipped_terminal", { requestId, currentStatus });
        return null;
      }
      tx.update(requestRef, { status: "cancelled", cancelledBy: "patient", updatedAt: FieldValue.serverTimestamp() });
      return reqSnap.data().ambulanceId || null;
    });
    _logAmbulance("INFO", "ambulance_request_cancelled_by_patient", { requestId });
    await _notifyProviderOfPatientCancel(db, providerId, { serviceType: "ambulance", bookingId: requestId, what: "ambulance request" });
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
    await _releasePoolJobContact(db, "ambulance_requests", requestId, before, after);

    if (!before.declineRequested && after.declineRequested) {
      await _redispatchDeclinedAmbulance(db, requestId);
      return;
    }
    // TYPE-AWARE CLAIM GUARD: a driver whose vehicleTypeKey differs from the
    // requested type may not hold this request (rules cannot cross-read the
    // driver profile, so it is enforced here). Revert to the open pool,
    // remember the driver in declinedBy, and tell them.
    const requestedKeyForClaim = AmbH.normalizeAmbulanceTypeKey(after.ambulanceTypeKey);
    if (requestedKeyForClaim && after.ambulanceId &&
        (before.ambulanceId !== after.ambulanceId || (before.status === "pending" && after.status === "accepted")) &&
        !["completed", "cancelled"].includes(after.status)) {
      try {
        const prof = await db.collection("ambulance_profiles").doc(after.ambulanceId).get();
        if (!AmbH.driverMatchesRequestedType(prof.exists ? prof.data() : null, requestedKeyForClaim)) {
          const badDriver = after.ambulanceId;
          await event.data.after.ref.update({
            ambulanceId: null,
            status: "pending",
            declinedBy: FieldValue.arrayUnion(badDriver),
            lockedRate: FieldValue.delete(),
            lockedRateAmbulanceId: FieldValue.delete(),
            updatedAt: FieldValue.serverTimestamp(),
          });
          await _sendProviderNotification(db, getMessaging(), badDriver, {
            title: "Request not for your vehicle type",
            body: `This request needs a ${AmbH.ambulanceTypeLabel(requestedKeyForClaim)} ambulance, so it was returned to the pool.`,
            type: "ambulance_type_mismatch", serviceType: "ambulance", bookingId: requestId,
          }).catch(() => {});
          _logAmbulance("WARNING", "claim_rejected_type_mismatch", { requestId, driver: badDriver, requestedKeyForClaim });
          return; // the revert write re-triggers this function and mirrors the un-assign.
        }
      } catch (err) {
        _logAmbulance("WARNING", "claim_type_check_failed", { requestId, error: err.message });
      }
    }

    const statusChanged = before.status !== after.status;
    await _autoRefundOnProviderFailure(db, before, after, ["cancelled"], "service_requests",
      after.sourceRequestId || requestId, "No ambulance could take this request");
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
      if (claimChanged && after.ambulanceId) {
        update.assignedTo = after.ambulanceId;
        const driverName = await _ambulanceDisplayName(db, after.ambulanceId);
        if (driverName) update.assignedToName = driverName;
      } else if (claimChanged && before.ambulanceId && !after.ambulanceId &&
                 !["completed", "cancelled"].includes(after.status)) {
        // The matched driver timed out and nobody else is online: the request
        // is back in the open pool, so the patient's live-tracking screen must
        // not keep pointing at the previous driver.
        update.assignedTo = FieldValue.delete();
        update.assignedToName = FieldValue.delete();
      }

      if (Object.keys(update).length > 1) {
        const serviceRequestRef = db.collection("service_requests").doc(after.sourceRequestId || requestId);
        // Skip the write entirely if everything we'd set already matches —
        // a redelivered event becomes a no-op read instead of a redundant
        // write (and a redundant duplicate patient notification).
        const current = await serviceRequestRef.get();
        const currentData = current.exists ? current.data() : null;
        const alreadyApplied = !!currentData &&
          (!update.status || currentData.status === update.status) &&
          (!update.assignedTo || currentData.assignedTo === update.assignedTo) &&
          (!update.assignedToName || currentData.assignedToName === update.assignedToName);

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

    // ── Claim / re-match: the fare becomes the new driver's own rate ────────
    // (range-based bookings only; clamped into [fareMin, fareMax], range min
    // when unset). Provisional until completion re-resolves it below.
    // RATE LOCK: the driver's rate is snapshotted (lockedRate / lockedFare) when
    // the request is claimed, re-matched to a new driver, OR accepted by the
    // pinned driver (pending -> accepted keeps the same ambulanceId, so it is
    // not a claimChanged edge). Completion uses the lock, never the live rate.
    const acceptEdge = statusChanged && before.status === "pending" && after.status === "accepted";
    if ((claimChanged || acceptEdge) && after.ambulanceId && !["completed", "cancelled"].includes(after.status)) {
      try {
        const srId = after.sourceRequestId || requestId;
        // Prefer the server rate range over the client-written fareMin/fareMax.
        const sr = await db.collection("service_requests").doc(srId).get();
        const range = (await _ambulanceServerRange(db, sr.exists ? sr.get("serviceDetails") : null)) ||
          _ambulanceFareRange({ fareMin: after.fareMin, fareMax: after.fareMax });
        const claimFare = await _ambulanceFinalFare(db, after.ambulanceId, range); // live rate -> becomes the lock
        if (claimFare !== null) {
          const lockUpdate = {};
          if (after.fare !== claimFare) lockUpdate.fare = claimFare;
          if (after.lockedRate !== claimFare) lockUpdate.lockedRate = claimFare;
          if (after.lockedRateAmbulanceId !== after.ambulanceId) lockUpdate.lockedRateAmbulanceId = after.ambulanceId;
          if (Object.keys(lockUpdate).length) await event.data.after.ref.update(lockUpdate);
          await _recordAmbulanceFinalFare(db, srId, claimFare, { lock: true });
        }
      } catch (err) {
        _logAmbulance("WARNING", "claim_fare_update_failed", { requestId, error: err.message });
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
      let fare = after.fare ?? 0;
      // Pay-after-trip bookings: the partner's legacy ledger credit is
      // deferred until the customer's payment is captured (captureTripPayment
      // writes it) so an unpaid trip never shows as credited earnings.
      let deferLedger = false;

      // Range-based booking: the earning is the matched driver's own rate
      // clamped into [fareMin, fareMax] (range min when unset), NOT the
      // charged max. Recorded on the service_request BEFORE the settlement /
      // test-credit hop below so that hop sees `fareFinal`.
      try {
        const srId = after.sourceRequestId || requestId;
        // Prefer the server rate range over the client-written fareMin/fareMax.
        const sr = await db.collection("service_requests").doc(srId).get();
        const range = (await _ambulanceServerRange(db, sr.exists ? sr.get("serviceDetails") : null)) ||
          _ambulanceFareRange({ fareMin: after.fareMin, fareMax: after.fareMax });
        // Use the rate locked at accept (only if it was locked for THIS driver);
        // legacy requests without a lock fall back to the live rate.
        const lockedRate = (after.lockedRateAmbulanceId === after.ambulanceId && Number.isFinite(Number(after.lockedRate)))
          ? Number(after.lockedRate) : null;
        const finalFare = await _ambulanceFinalFare(db, after.ambulanceId, range, lockedRate);
        if (finalFare !== null) {
          fare = finalFare;
          const rec = await _recordAmbulanceFinalFare(db, srId, finalFare, { completed: true, ambulanceId: after.ambulanceId, lockedRate });
          deferLedger = !!(rec && rec.deferLedger);
        }
      } catch (err) {
        _logAmbulance("ERROR", "final_fare_resolve_failed", { requestId, error: err.message });
      }

      const written = await db.runTransaction(async (tx) => {
        const existingTrip = await tx.get(tripRef);
        const existingTx   = await tx.get(ledgerRef);
        if (existingTrip.exists && (existingTx.exists || deferLedger)) return false;

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
        if (!existingTx.exists && !deferLedger) {
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

  // Backstop for the minute sweep: alert on anything that is about to be
  // auto-cancelled without the admin ever having been told.
  const alertCache = {};
  for (const doc of staleSnap.docs) {
    await _alertAdminIfAmbulanceUnaccepted(db, doc, doc.data(), alertCache).catch(() => {});
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

// Care Assistant jobs are escort/errand work, not clinical care, so they get
// their own starter checklist.
const _CARE_ASSISTANT_DEFAULT_TASKS = [
  { title: "Meet the patient",           subtitle: "Confirm identity and the plan for the day" },
  { title: "Accompany / run the errand", subtitle: "Hospital escort, report collection or medicine pickup" },
  { title: "Keep the family updated",    subtitle: "Share progress with the patient's family" },
  { title: "Hand over safely",           subtitle: "Make sure the patient is home or settled" },
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
  _emitLog(severity, payload);
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

    const isCareAssistant = data.type === "care_assistant";
    // care_assistant_screen.dart books one of 4 duration tiers (no shiftHours).
    const careDurationMinutes = { hourly: 60, halfDay: 240, fullDay: 480, multiDay: 480 };
    const shiftHours = Number(details.shiftHours);
    const durationMinutes = isCareAssistant
      ? (careDurationMinutes[details.duration] || 60)
      : (Number.isFinite(shiftHours) && shiftHours > 0 ? Math.round(shiftHours * 60) : 60);

    // A visit booked from a specific caregiver's own profile card (see
    // caregivers_screen.dart's `sourceCaregiverId`, or care_assistant_screen.dart's
    // `assistantId` — same pin, two screens, never unified into one field name)
    // pins straight to them instead of dropping into the unclaimed pool — same
    // reasoning as Lab's `sourceLabId` handling. Falls back to the pool if that
    // caregiver is no longer active by the time the patient checks out.
    const sourcePartnerId = details.sourceCaregiverId || details.assistantId || null;
    let pinnedCaregiverId = null;
    if (sourcePartnerId) {
      const caregiverSnap = await db.collection("caregiver_profiles").doc(sourcePartnerId).get();
      if (caregiverSnap.exists && caregiverSnap.data().status === "active" &&
          // A care-assistant booking may only pin to a care assistant, and a
          // nurse booking only to a nurse.
          (_caregiverServiceType(caregiverSnap.data()) === "care_assistant") === isCareAssistant) {
        pinnedCaregiverId = sourcePartnerId;
      } else {
        _logCaregiver("WARNING", "source_caregiver_inactive_falling_back_to_pool", {
          requestId, sourceCaregiverId: sourcePartnerId,
        });
      }
    }

    const batch = db.batch();
    _batchSetPoolJob(batch, db, visitRef, "caregiver_visits", {
      sourceRequestId: requestId,
      sourceType: data.type,
      type: isCareAssistant ? "assistance" : _caregiverCareType(details.specialty || details.shiftType || data.serviceName),
      serviceDetails: details,
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
    (isCareAssistant ? _CARE_ASSISTANT_DEFAULT_TASKS : _CAREGIVER_DEFAULT_TASKS).forEach((task, i) => {
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
      const pinnedName = await _providerDisplayName(db, "caregiver_profiles", pinnedCaregiverId);
      await db.collection("service_requests").doc(requestId).update({
        assignedTo: pinnedCaregiverId,
        ...(pinnedName ? { assignedToName: pinnedName } : {}),
      }).catch((err) => {
        _logCaregiver("WARNING", "initial_assignedTo_mirror_failed", { requestId, error: err.message });
      });
    }

    _logCaregiver("INFO", "caregiver_visit_created", { requestId, sourceType: data.type });

    if (pinnedCaregiverId) {
      await _sendProviderNotification(db, getMessaging(), pinnedCaregiverId, {
        title: isCareAssistant ? "New Care Request" : "New Visit Request",
        body: isCareAssistant
          ? `${(data.patientName || "A patient").split(" ")[0]} requested you. Open the app to accept.`
          : `${(data.patientName || "A patient").split(" ")[0]} requested a ${data.serviceName || "nurse"} visit with you. Open the app to accept.`,
        type: "new_caregiver_visit", serviceType: "caregiver", bookingId: requestId,
      });
    } else {
      await _broadcastNewJobToActiveProviders(db, getMessaging(), {
        profileCollection: "caregiver_profiles",
        title: isCareAssistant ? "New Care Assistant Request" : "New Visit Request Available",
        body: isCareAssistant
          ? "A patient needs a care assistant. Open the app to accept."
          : `A new ${data.serviceName || "nurse"} visit request is available to claim.`,
        type: "new_caregiver_visit", serviceType: "caregiver", bookingId: requestId,
        // Only the matching role hears about it.
        profileFilter: (d) => (_caregiverServiceType(d.data()) === "care_assistant") === isCareAssistant,
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

    const providerId = await db.runTransaction(async (tx) => {
      const visitSnap = await tx.get(visitRef);
      if (!visitSnap.exists) return null;
      const currentStatus = visitSnap.data().status;
      if (["completed", "cancelled", "missed"].includes(currentStatus)) {
        _logCaregiver("INFO", "cancel_mirror_skipped_terminal", { requestId, currentStatus });
        return null;
      }
      tx.update(visitRef, { status: "cancelled", cancelledBy: "patient", updatedAt: FieldValue.serverTimestamp() });
      return visitSnap.data().caregiverId || null;
    });
    _logCaregiver("INFO", "caregiver_visit_cancelled_by_patient", { requestId });
    await _notifyProviderOfPatientCancel(db, providerId, { serviceType: "caregiver", bookingId: requestId, what: "nurse visit" });
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
    await _releasePoolJobContact(db, "caregiver_visits", visitId, before, after);

    const statusChanged = before.status !== after.status;
    const isCareAssistant = after.sourceType === "care_assistant";
    await _autoRefundOnProviderFailure(db, before, after, ["cancelled", "missed"], "service_requests",
      after.sourceRequestId || visitId,
      isCareAssistant ? "The care assistant cancelled or missed this job" : "The nurse cancelled or missed this visit");
    const claimChanged = before.caregiverId !== after.caregiverId;
    // A care assistant explicitly accepting (acceptedAt stamped) is what moves
    // the patient's booking pending -> accepted.
    const acceptedNow = !before.acceptedAt && !!after.acceptedAt;

    // A pinned assistant declined: the job went back to the open pool, so the
    // patient's booking is unassigned again and the other assistants hear
    // about it (excluding everyone who already declined).
    if (claimChanged && before.caregiverId && !after.caregiverId && after.status === "scheduled") {
      // The job was born pinned, so it carries the patient's full phone and
      // address. Back in the open pool it must be withheld again like any
      // other unclaimed job (the details return to it when someone accepts).
      if (!after.contactWithheld) {
        const { doc, contact } = _splitPoolJob("caregiver_visits", visitId, { ...after, caregiverId: null });
        if (contact) {
          await db.collection("job_contacts").doc(`caregiver_visits__${visitId}`).set(contact);
          await db.collection("caregiver_visits").doc(visitId).update({
            contactWithheld: true,
            patientPhone: doc.patientPhone,
            address: doc.address,
            patientName: doc.patientName,
          });
        }
      }
      // Provider cancelled a visit they had ALREADY accepted (not yet started):
      // acceptedAt was cleared in the same write. The patient's booking goes
      // back to 'pending' (it was 'accepted') and they are told we are finding
      // another provider. No refund: the original payment stays on the booking
      // and carries over to whoever takes the job next.
      const cancelledAfterAccept = !!before.acceptedAt && !after.acceptedAt;
      const requestRef = db.collection("service_requests").doc(after.sourceRequestId || visitId);
      const unassign = {
        assignedTo: FieldValue.delete(),
        assignedToName: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (cancelledAfterAccept) {
        const reqSnap = await requestRef.get().catch(() => null);
        if (reqSnap && reqSnap.exists && reqSnap.data().status === "accepted") {
          unassign.status = "pending";
          // Lets the patient app show "<Role> cancelled. We're finding another"
          // with a Cancel option; a patient cancel from this 'pending' state is
          // refunded in full by _applyCancelRefundPolicy (preAccept).
          unassign.providerReleasedAt = FieldValue.serverTimestamp();
          unassign.providerReleasedRole = isCareAssistant ? "care_assistant" : "nurse";
          unassign.providerReleasedNote = "provider_cancelled";
        }
      }
      await requestRef.update(unassign)
        .catch((err) => _logCaregiver("WARNING", "unassign_mirror_failed", { visitId, error: err.message }));
      if (cancelledAfterAccept && after.patientId) {
        await _sendPatientNotification(db, getMessaging(), after.patientId, {
          title: isCareAssistant ? "Care Assistant Unavailable" : "Nurse Unavailable",
          body: `Your ${isCareAssistant ? "care assistant" : "nurse"} had to cancel. We are finding another for you — no action needed.`,
          type: "caregiver_provider_cancelled",
          serviceType: "caregiver",
          bookingId: after.sourceRequestId || visitId,
          actionType: "open_service",
          extraData: { status: "pending" },
        }).catch((err) => _logCaregiver("WARNING", "provider_cancel_patient_notify_failed", { visitId, error: err.message }));
        _logCaregiver("INFO", "caregiver_visit_released_after_accept", { visitId, providerId: before.caregiverId });
      }
      await _broadcastNewJobToActiveProviders(db, getMessaging(), {
        profileCollection: "caregiver_profiles",
        title: isCareAssistant ? "New Care Assistant Request" : "New Visit Request Available",
        body: isCareAssistant
          ? "A patient needs a care assistant. Open the app to accept."
          : "A nurse visit request is available to claim. Open the app to accept.",
        type: "new_caregiver_visit", serviceType: "caregiver", bookingId: visitId,
        profileFilter: (d) => (_caregiverServiceType(d.data()) === "care_assistant") === isCareAssistant,
        excludeIds: after.declinedBy || [],
      });
    }

    // Remembered and rethrown at the end (see the Lab mirror) so a mirror
    // failure never skips the ledger credit below.
    let mirrorError = null;

    if (statusChanged || claimChanged || acceptedNow) {
      const update = { updatedAt: FieldValue.serverTimestamp() };

      const mappedStatus = _CAREGIVER_TO_SERVICE_REQUEST_STATUS[after.status];
      if (statusChanged && mappedStatus) update.status = mappedStatus;
      if ((claimChanged || acceptedNow) && after.caregiverId) {
        update.assignedTo = after.caregiverId;
        // A new provider took the job: drop the "provider cancelled" banner.
        update.providerReleasedAt = FieldValue.delete();
        update.providerReleasedRole = FieldValue.delete();
        update.providerReleasedNote = FieldValue.delete();
        // Human-readable name so the patient app can show who accepted.
        const providerName = await _providerDisplayName(db, "caregiver_profiles", after.caregiverId);
        if (providerName) update.assignedToName = providerName;
      }

      if (Object.keys(update).length > 1) {
        const serviceRequestRef = db.collection("service_requests").doc(after.sourceRequestId || visitId);
        const current = await serviceRequestRef.get();
        const currentData = current.exists ? current.data() : null;

        // Claiming a visit doesn't change its own status (a claimed visit is
        // still 'scheduled' until check-in), but the patient should still see
        // it move from 'pending' to 'accepted' with a caregiver attached.
        // Gated on the *current* patient-side status: a re-assignment after
        // check-in must never drag 'in_progress' backwards to 'accepted'.
        if (update.assignedTo && !update.status && currentData?.status === "pending" &&
            // A pinned care-assistant job must wait for their explicit Accept.
            // (A pinned nurse job also waits: it is born pinned, so no claim
            // edge fires and only the acceptedAt stamp reaches here. A nurse
            // claiming from the open pool, incl. legacy builds that claim
            // without acceptedAt, is still accepted immediately.)
            (!isCareAssistant || after.acceptedAt)) {
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
        // Care assistants can carry their own commission rule; the settlement
        // helpers fall back to the 'caregiver' rule until one is configured.
        serviceType: isCareAssistant ? "care_assistant" : "caregiver",
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
// `caregivers_screen.dart` and `care_assistant_screen.dart` (mednu) each
// browse their own top-level collection (`caregivers` / `care_assistants`)
// that, before this, nothing ever wrote — approval only sent a push
// notification. Mirrors `caregiver_profiles/{uid}` into whichever listing
// collection matches the partner's own `serviceType` choice at registration
// (same doc id, 1:1 — no subcollection involved, unlike Lab/Pharmacy's
// per-item inventory) whenever the profile is active, so a real
// registered-and-approved partner actually shows up to patients, and
// disappears again if suspended. A partner only ever has ONE listing doc at a
// time — if `serviceType` changes, the stale copy in the other collection is
// deleted in the same write.
//
// `type` (Nurse/Maid/...) is approximated from the first entry in
// `specialties` for `caregivers` listings, since there's no dedicated role
// field — same as before this comment was updated.
const _CAREGIVER_LISTING_COLLECTIONS = { caregiver: "caregivers", care_assistant: "care_assistants" };

function _caregiverServiceType(profile) {
  return profile.serviceType === "care_assistant" ? "care_assistant" : "caregiver";
}

function _caregiverListingDoc(profile, existingCreatedAt) {
  const specialties = Array.isArray(profile.specialties) ? profile.specialties : [];
  const hourlyRate = profile.hourlyRate ?? 0;
  const shared = {
    name: profile.name || "Nurse",
    photoUrl: profile.photoUrl || "",
    gender: profile.gender || "",
    experience: `${profile.experienceYears ?? 0} yrs`,
    rating: profile.rating ?? 0,
    // Patient-side screens already read `location` (a pre-existing field name
    // distinct from `city` used by the other verticals) — matching it here
    // rather than introducing a second name.
    location: profile.city || "",
    ...(profile.lat != null && profile.lng != null
      ? { lat: profile.lat, lng: profile.lng }
      : {}),
    isVerified: profile.documentsVerified === true,
    isActive: true,
    createdAt: existingCreatedAt || FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (_caregiverServiceType(profile) === "care_assistant") {
    // care_assistant_screen.dart's 4 duration tiers have no dedicated rate
    // fields on the shared registration form (just one `hourlyRate`), so the
    // longer tiers are derived from it — same lossy-but-functional approach
    // the shift-rate fields below already use for the Caregiver listing.
    return {
      ...shared,
      specialty: specialties.length > 0 ? specialties.join(", ") : "Home & Hospital Assistance",
      bio: profile.bio || "",
      languages: Array.isArray(profile.languages) ? profile.languages : [],
      rateHourly: hourlyRate,
      // Dedicated tiers when the assistant set them, else derived from hourly.
      rateHalfDay: profile.rateHalfDay ?? Math.round(hourlyRate * 4),
      rateFullDay: profile.rateFullDay ?? Math.round(hourlyRate * 8),
      rateMultiDay: profile.rateMultiDay ?? Math.round(hourlyRate * 8),
    };
  }

  return {
    ...shared,
    type: specialties.length > 0 ? specialties[0] : "Nurse",
    specialty: specialties.length > 0 ? specialties.join(", ") : "Home Care",
    ratePerDay: Math.round(hourlyRate * 8),
    ratePerHour: hourlyRate,
    ratePer12Hr: Math.round(hourlyRate * 12),
  };
}

exports.onCaregiverProfileWriteForVisibility = onDocumentWritten(
  "caregiver_profiles/{caregiverId}",
  async (event) => {
    const caregiverId = event.params.caregiverId;
    const db = getFirestore();

    const after = event.data.after;
    if (!after.exists) {
      await Promise.all(
        Object.values(_CAREGIVER_LISTING_COLLECTIONS)
          .map((col) => db.collection(col).doc(caregiverId).delete().catch(() => {})),
      );
      _logCaregiver("INFO", "listing_mirror_deleted", { caregiverId });
      return;
    }

    const profile = after.data();
    const targetCollection = _CAREGIVER_LISTING_COLLECTIONS[_caregiverServiceType(profile)];
    const staleCollection = Object.values(_CAREGIVER_LISTING_COLLECTIONS)
      .find((col) => col !== targetCollection);
    const listingRef = db.collection(targetCollection).doc(caregiverId);

    // Always clear any listing left behind in the other collection — covers
    // both a serviceType switch and (below) a pending/suspended profile.
    await db.collection(staleCollection).doc(caregiverId).delete().catch(() => {});

    if (profile.status !== "active") {
      // Pending/suspended partners stay out of the patient list until
      // (re)approved. `isActive` is redundant with the doc simply not
      // existing, but keeping the field lets the patient query stay a plain
      // `where('isActive', '==', true)` if this ever needs to become a
      // sweep-based mirror (subcollection-style) instead of 1:1 later.
      await listingRef.delete().catch(() => {});
      return;
    }

    const existing = await listingRef.get();
    await listingRef.set(
      _caregiverListingDoc(profile, existing.exists ? existing.data().createdAt : null),
      { merge: true },
    );
    _logCaregiver("INFO", "listing_mirror_synced", { caregiverId, targetCollection });
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
  _emitLog(severity, payload);
}
function _logCounselling(severity, event, data = {}) {
  const payload = { severity, module: "counselling", event, ...data };
  _emitLog(severity, payload);
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
    price: data.amount ?? details.price ?? 0,
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
    await _setPoolJob(db, sessionRef, "physio_sessions", sessionDoc);

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
      // Skipped when the slot index already cancelled this booking (lost a
      // slot race) so a late 'accepted' can't resurrect it.
      await db.runTransaction(async (tx) => {
        const cur = await tx.get(snap.ref);
        if (cur.exists && cur.data().status === "cancelled") return;
        tx.update(snap.ref, {
          status: "accepted",
          assignedTo: sessionDoc.physiotherapistId,
          ...(providerName ? { assignedToName: providerName } : {}),
          updatedAt: FieldValue.serverTimestamp(),
        });
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

    const providerId = await db.runTransaction(async (tx) => {
      const sessionSnap = await tx.get(sessionRef);
      if (!sessionSnap.exists) return null;
      const currentStatus = sessionSnap.data().status;
      if (["completed", "cancelled", "expired"].includes(currentStatus)) {
        _logPhysio("INFO", "cancel_mirror_skipped_terminal", { requestId, currentStatus });
        return null;
      }
      tx.update(sessionRef, { status: "cancelled", cancelledBy: "patient", updatedAt: FieldValue.serverTimestamp() });
      return sessionSnap.data().physiotherapistId || null;
    });
    _logPhysio("INFO", "physio_session_cancelled_by_patient", { requestId });
    await _notifyProviderOfPatientCancel(db, providerId, { serviceType: "physiotherapy", bookingId: requestId, what: "physiotherapy session" });
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
    await _releasePoolJobContact(db, "physio_sessions", sessionId, before, after);

    const statusChanged = before.status !== after.status;
    await _autoRefundOnProviderFailure(db, before, after, ["cancelled", "expired"], "service_requests",
      after.sourceRequestId || sessionId, "The physiotherapist declined or could not take this session");
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
    await _setPoolJob(db, sessionRef, "counselling_sessions", sessionDoc);

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
      // Skipped when the slot index already cancelled this booking (lost a
      // slot race) so a late 'accepted' can't resurrect it.
      await db.runTransaction(async (tx) => {
        const cur = await tx.get(snap.ref);
        if (cur.exists && cur.data().status === "cancelled") return;
        tx.update(snap.ref, {
          status: "accepted",
          assignedTo: sessionDoc.counsellorId,
          ...(providerName ? { assignedToName: providerName } : {}),
          updatedAt: FieldValue.serverTimestamp(),
        });
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

    const providerId = await db.runTransaction(async (tx) => {
      const sessionSnap = await tx.get(sessionRef);
      if (!sessionSnap.exists) return null;
      const currentStatus = sessionSnap.data().status;
      if (["completed", "cancelled", "expired"].includes(currentStatus)) {
        _logCounselling("INFO", "cancel_mirror_skipped_terminal", { requestId, currentStatus });
        return null;
      }
      tx.update(sessionRef, { status: "cancelled", cancelledBy: "patient", updatedAt: FieldValue.serverTimestamp() });
      return sessionSnap.data().counsellorId || null;
    });
    _logCounselling("INFO", "counselling_session_cancelled_by_patient", { requestId });
    await _notifyProviderOfPatientCancel(db, providerId, { serviceType: "counselling", bookingId: requestId, what: "counselling session" });
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
    await _releasePoolJobContact(db, "counselling_sessions", sessionId, before, after);

    const statusChanged = before.status !== after.status;
    await _autoRefundOnProviderFailure(db, before, after, ["cancelled", "expired"], "service_requests",
      after.sourceRequestId || sessionId, "The counsellor declined or could not take this session");
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
// Weekly schedule -> the shape the patient app's NutritionistModel reads.
// `availability` (written straight by the dietician's Availability screen,
// same shape as doctors/{uid}.availability) is
//   { slotDuration, schedule: { Mon: {enabled,start:"HH:MM",end:"HH:MM"}, ... },
//     blockedSlots: { "yyyy-MM-dd": ["09:00 AM", ...] }, clinicName, clinicAddress }
// and slot labels are zero-padded "HH:MM AM" — identical to the doctor flow.
const _NUTRITION_DAYS = [
  ["Mon", "Monday"], ["Tue", "Tuesday"], ["Wed", "Wednesday"], ["Thu", "Thursday"],
  ["Fri", "Friday"], ["Sat", "Saturday"], ["Sun", "Sunday"],
];

function _nutritionSlotLabel(mins) {
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  const period = h < 12 ? "AM" : "PM";
  const dh = h === 0 ? 12 : (h > 12 ? h - 12 : h);
  return `${String(dh).padStart(2, "0")}:${String(m).padStart(2, "0")} ${period}`;
}

function _nutritionDaySlots(dayCfg, slotDuration) {
  if (!dayCfg || dayCfg.enabled !== true) return [];
  const dur = Number(slotDuration) >= 5 ? Number(slotDuration) : 30;
  const [sh, sm] = String(dayCfg.start || "09:00").split(":").map(Number);
  const [eh, em] = String(dayCfg.end || "17:00").split(":").map(Number);
  if ([sh, sm, eh, em].some((n) => Number.isNaN(n))) return [];
  const startMins = sh * 60 + sm;
  const endMins = eh * 60 + em;
  const out = [];
  for (let m = startMins; m + dur <= endMins; m += dur) out.push(_nutritionSlotLabel(m));
  return out;
}

function _nutritionAvailabilityMirror(profile) {
  const avail = profile.availability;
  const mirror = {
    isOnlineAvailable: profile.isOnlineAvailable !== false,
    isInPersonAvailable: profile.isInPersonAvailable === true,
    clinicName: (avail && avail.clinicName) || "",
    clinicAddress: (avail && avail.clinicAddress) || "",
    availableDays: [],
    slots: {},
    blockedSlots: {},
    slotDuration: 30,
    // false => the dietician never published a schedule: the patient app keeps
    // its legacy default slots instead of showing "not available" every day.
    scheduleConfigured: false,
  };
  if (!avail || typeof avail.schedule !== "object" || avail.schedule === null) return mirror;
  mirror.scheduleConfigured = true;
  mirror.slotDuration = Number(avail.slotDuration) >= 5 ? Number(avail.slotDuration) : 30;
  for (const [short, full] of _NUTRITION_DAYS) {
    const daySlots = _nutritionDaySlots(avail.schedule[short], mirror.slotDuration);
    if (daySlots.length) {
      mirror.slots[full] = daySlots;
      mirror.availableDays.push(full);
    }
  }
  // Only upcoming blocked dates are useful to patients; keeps the doc small.
  const todayKey = new Date().toISOString().slice(0, 10);
  const blocked = avail.blockedSlots;
  if (blocked && typeof blocked === "object") {
    for (const [date, list] of Object.entries(blocked)) {
      if (date >= todayKey && Array.isArray(list) && list.length) mirror.blockedSlots[date] = list.map(String);
    }
  }
  return mirror;
}

// True when `timeSlot` on `date` is a real, unblocked slot of the dietician's
// published schedule. No schedule published => legacy default slots, allow.
function _nutritionSlotAllowed(profile, date, timeSlot) {
  const avail = profile && profile.availability;
  if (!avail || typeof avail.schedule !== "object" || avail.schedule === null) return true;
  const d = new Date(`${date}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return false;
  const short = _NUTRITION_DAYS[(d.getUTCDay() + 6) % 7][0];
  const slots = _nutritionDaySlots(avail.schedule[short], avail.slotDuration);
  if (!slots.includes(timeSlot)) return false;
  const blocked = avail.blockedSlots && avail.blockedSlots[date];
  return !(Array.isArray(blocked) && blocked.includes(timeSlot));
}

function _nutritionistListingDoc(profile, existingCreatedAt) {
  return {
    name: profile.name || "Nutritionist",
    photoUrl: profile.photoUrl || "",
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
    // Every approved dietician stays listed and bookable; `isOnline` mirrors
    // the partner's online/offline toggle so the patient app can badge it.
    isAvailable: true,
    isOnline: profile.isOnline === true,
    languages: profile.languages || [],
    expertiseAreas: [],
    // isOnlineAvailable / isInPersonAvailable / clinicName / clinicAddress /
    // availableDays / slots / blockedSlots / slotDuration / scheduleConfigured
    ..._nutritionAvailabilityMirror(profile),
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
    const listing = _nutritionistListingDoc(profile, existing.exists ? existing.data().createdAt : null);
    // mergeFields (not a plain merge) so `slots`/`blockedSlots` are REPLACED:
    // a plain merge deep-merges maps and would keep a day the dietician has
    // since switched off.
    await listingRef.set(listing, { mergeFields: Object.keys(listing) });
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

// ── Public "taken slot" index for nutrition appointments ─────────────────────
// The booking screen used to query nutrition_appointments by nutritionistId to
// grey out taken slots, but a patient is (rightly) not allowed to read other
// patients' appointments, so that query was always permission-denied and every
// slot looked free. `nutrition_slots/{nutritionistId}_{date}_{time}` holds only
// nutritionistId/date/time and is server-written (firestore.rules: read-only
// for signed-in users). A slot is held while the appointment is
// pending/confirmed/in_progress.
function _nutritionSlotOf(appt) {
  if (!appt || !["pending", "confirmed", "in_progress"].includes(appt.status)) return null;
  if (!appt.nutritionistId || !appt.date || !appt.timeSlot) return null;
  return {
    key: _slotKey(appt.nutritionistId, appt.date, appt.timeSlot),
    nutritionistId: appt.nutritionistId, date: appt.date, timeSlot: appt.timeSlot,
  };
}

exports.onNutritionAppointmentWrittenForSlots = onDocumentWritten(
  "nutrition_appointments/{appointmentId}",
  async (event) => {
    const db = getFirestore();
    const appointmentId = event.params.appointmentId;
    const prev = _nutritionSlotOf(event.data.before?.exists ? event.data.before.data() : null);
    const next = _nutritionSlotOf(event.data.after?.exists ? event.data.after.data() : null);
    if (prev && next && prev.key === next.key) return;
    const beforeData = event.data.before?.exists ? event.data.before.data() : null;
    const afterData = event.data.after?.exists ? event.data.after.data() : null;
    if (next) {
      // Claim the new slot in one transaction (first to commit wins). Every
      // booking path (direct write, capturePayment, reschedule) ends in a
      // nutrition_appointments write, so this is the single place a slot is
      // granted — same pattern as onAppointmentWrittenForSlots.
      const slotRef = db.collection("nutrition_slots").doc(next.key);
      let conflict = await db.runTransaction(async (tx) => {
        const slotSnap = await tx.get(slotRef);
        const holderId = slotSnap.exists ? slotSnap.data().appointmentId : null;
        if (holderId && holderId !== appointmentId) {
          const holder = await tx.get(db.collection("nutrition_appointments").doc(holderId));
          if (holder.exists && _nutritionSlotOf(holder.data())?.key === next.key) return "taken";
        }
        tx.set(slotRef, {
          nutritionistId: next.nutritionistId, date: next.date, timeSlot: next.timeSlot,
          appointmentId, updatedAt: FieldValue.serverTimestamp(),
        });
        return null;
      });
      // A reschedule target must also be a real, unblocked slot of the
      // dietician's published schedule (clients already filter this; the rules
      // cannot read another doc cheaply, so it is enforced here).
      if (!conflict && prev) {
        const prof = await db.collection("nutritionist_profiles").doc(next.nutritionistId).get();
        if (prof.exists && !_nutritionSlotAllowed(prof.data(), next.date, next.timeSlot)) {
          conflict = "unavailable";
          const mine = await slotRef.get();
          if (mine.exists && mine.data().appointmentId === appointmentId) await slotRef.delete();
        }
      }
      if (conflict) {
        await _resolveNutritionSlotConflict(db, appointmentId, beforeData, afterData, prev, conflict);
        return; // keep `prev` held: a rejected reschedule goes straight back to it
      }
    }
    if (prev) {
      const ref = db.collection("nutrition_slots").doc(prev.key);
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (snap.exists && snap.data().appointmentId === appointmentId) tx.delete(ref);
      });
    }
  }
);

// Losing side of a nutrition slot race. A reschedule into a taken/unavailable
// slot is put back on its original date/time; a brand-new booking is
// cancelled (cancelReason 'slot_taken') and auto-refunded if it was paid.
async function _resolveNutritionSlotConflict(db, appointmentId, beforeData, afterData, prev, reason) {
  const ref = db.collection("nutrition_appointments").doc(appointmentId);
  const isReschedule = !!prev;
  if (isReschedule) {
    await ref.update({
      date: beforeData.date,
      timeSlot: beforeData.timeSlot,
      slotConflictAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } else {
    await ref.update({
      status: "cancelled",
      cancelledBy: "system",
      cancelReason: "slot_taken",
      slotConflictAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (afterData.subscriptionId) {
      // Prepaid plan: the credit returns to the customer instead of refunding the whole plan.
      await _returnPlanCredit(db, appointmentId, afterData, "system");
    } else {
      await _autoRefundBooking(db, "nutrition_appointments", appointmentId,
        "Slot was booked by another patient at the same moment");
    }
  }
  console.log(JSON.stringify({
    module: "nutrition_slots", event: isReschedule ? "reschedule_reverted" : "booking_cancelled_slot_taken",
    reason, appointmentId, nutritionistId: afterData.nutritionistId, date: afterData.date, timeSlot: afterData.timeSlot,
  }));
  const taken = reason === "taken" ? "was just booked by someone else" : "is not available";
  const msgNew = `${afterData.timeSlot} on ${afterData.date} ${taken}. Please pick another slot.`;
  const msgKept = `${afterData.timeSlot} on ${afterData.date} ${taken}. The appointment stays at ${beforeData.timeSlot} on ${beforeData.date}.`;
  // Tell whoever made the change (the other side never saw it succeed).
  if (isReschedule && afterData.rescheduledBy === "provider") {
    if (afterData.nutritionistId) {
      await _sendProviderNotification(db, getMessaging(), afterData.nutritionistId, {
        title: "Reschedule Not Possible", body: msgKept,
        type: "nutrition_reschedule_conflict", serviceType: "nutrition", bookingId: appointmentId,
      });
    }
    return;
  }
  if (!afterData.userId) return;
  await _sendPatientNotification(db, getMessaging(), afterData.userId, {
    title: isReschedule ? "Reschedule Not Possible" : "Slot No Longer Available",
    body: isReschedule ? msgKept : msgNew,
    type: isReschedule ? "nutrition_reschedule_conflict" : "nutrition_slot_conflict",
    serviceType: "nutrition", bookingId: appointmentId, actionType: "open_service",
  });
}

// Reschedule push to the other party. Keyed on `rescheduledAt` changing (the
// slot-conflict revert does not touch it, so a bounced reschedule is silent
// here and only the conflict notification above is sent).
exports.onNutritionAppointmentRescheduled = onDocumentUpdated(
  "nutrition_appointments/{appointmentId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    const tb = before.rescheduledAt?.toMillis?.() ?? null;
    const ta = after.rescheduledAt?.toMillis?.() ?? null;
    if (ta === null || ta === tb) return;
    if (before.date === after.date && before.timeSlot === after.timeSlot) return;
    if (!["pending", "confirmed"].includes(after.status)) return;
    const db = getFirestore();
    const messaging = getMessaging();
    const appointmentId = event.params.appointmentId;
    const when = `${after.date || ""} at ${after.timeSlot || ""}`.trim();
    if (after.rescheduledBy === "provider") {
      if (!after.userId) return;
      await _sendPatientNotification(db, messaging, after.userId, {
        title: "Appointment Rescheduled",
        body: `${after.nutritionistName || "Your dietician"} moved your appointment to ${when}.`,
        type: "nutrition_rescheduled", serviceType: "nutrition", bookingId: appointmentId,
        actionType: "open_service", extraData: { status: after.status },
      });
    } else if (after.nutritionistId) {
      await _sendProviderNotification(db, messaging, after.nutritionistId, {
        title: "Appointment Rescheduled",
        body: `${after.userName || "A patient"} moved their appointment to ${when}.`,
        type: "nutrition_rescheduled", serviceType: "nutrition", bookingId: appointmentId,
      });
    }
  }
);

// ── Nutrition status -> patient push ─────────────────────────────────────────
// Patients read nutrition_appointments directly (no mirror), so the screen is
// already live; this adds the push every other vertical sends. A cancel also
// tells the nutritionist, since either side may have made it.
exports.onNutritionAppointmentStatusChange = onDocumentUpdated(
  "nutrition_appointments/{appointmentId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status) return;
    // Slot-race loser: _resolveNutritionSlotConflict sends the one message that explains it.
    if (after.status === "cancelled" && after.cancelReason === "slot_taken") return;
    const db = getFirestore();
    const messaging = getMessaging();
    const appointmentId = event.params.appointmentId;
    const who = after.nutritionistName || "Your nutritionist";
    const when = (after.date ? ` on ${after.date}` : "") + (after.timeSlot ? ` at ${after.timeSlot}` : "");
    const messages = {
      confirmed:   ["Appointment Confirmed", `${who} confirmed your appointment${when}.`],
      in_progress: ["Session Started", `${who} has started your session.`],
      completed:   ["Session Completed", `Your session with ${who} is complete. Tap to rate it.`],
      cancelled:   ["Appointment Cancelled", `Your nutrition appointment${when} was cancelled.`],
    };
    const msg = messages[after.status];
    if (msg && after.userId) {
      await _sendPatientNotification(db, messaging, after.userId, {
        title: msg[0], body: msg[1], type: `nutrition_${after.status}`,
        serviceType: "nutrition", bookingId: appointmentId, actionType: "open_service",
        extraData: { status: after.status },
      });
    }
    if (after.status === "cancelled" && after.subscriptionId) {
      // Plan consultation: the credit goes back to the customer (no money moves;
      // the whole-plan refund is cancelWeightLossPlan's job).
      await _returnPlanCredit(db, appointmentId, after, after.cancelledBy === "patient" ? "patient" : "provider");
    } else if (after.status === "cancelled" && after.cancelledBy === "provider") {
      await _autoRefundBooking(db, "nutrition_appointments", appointmentId, "The nutritionist cancelled this appointment");
    }
    if (after.status === "cancelled" && after.cancelledBy !== "provider" && after.nutritionistId) {
      await _sendProviderNotification(db, messaging, after.nutritionistId, {
        title: "Appointment Cancelled",
        body: `${after.userName || "A patient"}'s appointment${when} was cancelled.`,
        type: "nutrition_cancelled", serviceType: "nutrition", bookingId: appointmentId,
      });
    }
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

    // Prepaid plan consultation: releases ONE per-consultation share of the
    // plan payment (never the whole payment, never twice).
    if (after.subscriptionId) {
      await _completePlanConsultation(getFirestore(), event.params.appointmentId, after);
      return;
    }

    await _transitionPaymentToEligible(getFirestore(), {
      sourceCollection: "nutrition_appointments",
      sourceId: event.params.appointmentId,
      providerId: after.nutritionistId,
      serviceType: "nutrition",
    });
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// Prepaid weight-loss plan (nutrition subscription)
// ───────────────────────────────────────────────────────────────────────────────
// nutrition_subscriptions/{id} (server-write only; patient + assigned dietician read):
//   { patientId, patientName, patientPhone, nutritionistId, nutritionistName,
//     nutritionistSpecialization, planType:'weight_loss', planId, planTitle, months,
//     monthlyPrice, baseTotal, platformFee, paymentId|null, paymentMode:'paid'|'not_required',
//     startDate, endsAtDate ('yyyy-MM-dd', IST), startedAt, endsAt, status:
//     'active'|'cancelling'|'cancelled'|'completed',
//     consultations:[{ index, windowStart, windowEnd, status:'available'|'booked'|
//       'completed'|'lapsed'|'cancelled', appointmentId?, startReminded?, endReminded? }] }
// Purchase = capturePayment (consultation #1 is the purchase booking, 'booked').
// Months 2..N = bookPlanConsultation (no payment, paymentStatus 'plan_prepaid').
// Payout = one child `payments` doc per COMPLETED consultation (_completePlanConsultation).
// ═══════════════════════════════════════════════════════════════════════════════

function _slotStartMinutes(label) {
  const m = /^(\d{2}):(\d{2}) (AM|PM)$/.exec(String(label || ""));
  if (!m) return null;
  let h = Number(m[1]) % 12;
  if (m[3] === "PM") h += 12;
  return h * 60 + Number(m[2]);
}

function _istNowMinutes(now = new Date()) {
  const t = new Date(now.getTime() + 330 * 60 * 1000);
  return t.getUTCHours() * 60 + t.getUTCMinutes();
}

const _PLAN_TERMINAL = ["completed", "lapsed", "cancelled"];

// A booked plan consultation was cancelled (by the customer, the dietician or a
// slot conflict): the credit goes back to 'available'. For dietician/system
// causes the window is extended to at least 14 days out so the customer is not
// penalised. No money moves. A no-op unless the subscription is 'active' and the
// credit is still 'booked' against THIS appointment (idempotent on redelivery).
async function _returnPlanCredit(db, appointmentId, appt, by) {
  const subRef = db.collection("nutrition_subscriptions").doc(appt.subscriptionId);
  let result = null;
  try {
    result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(subRef);
      if (!snap.exists) return null;
      const sub = snap.data();
      if (sub.status !== "active") return null;
      const credits = (sub.consultations || []).map((c) => ({ ...c }));
      const c = credits.find((x) => x.index === Number(appt.planIndex));
      if (!c || c.status !== "booked" || c.appointmentId !== appointmentId) return null;
      c.status = "available";
      delete c.appointmentId;
      if (by !== "patient") {
        const floor = PlanH.addDaysKey(PlanH.istDateKey(), 14);
        if (c.windowEnd < floor) c.windowEnd = floor;
        delete c.endReminded;
      }
      tx.update(subRef, { consultations: credits, updatedAt: FieldValue.serverTimestamp() });
      return { index: c.index, windowEnd: c.windowEnd };
    });
  } catch (err) {
    _logSettlement("ERROR", "plan_credit_return_failed", { appointmentId, error: err.message });
    throw err;
  }
  if (result && by === "provider" && appt.userId) {
    await _sendPatientNotification(db, getMessaging(), appt.userId, {
      title: "Consultation Credit Restored",
      body: `${appt.nutritionistName || "Your dietician"} could not make your session. Your month ${result.index} consultation is available again until ${result.windowEnd}.`,
      type: "nutrition_plan_credit_returned", serviceType: "nutrition",
      bookingId: `${appt.subscriptionId}-${result.index}`, actionType: "open_service",
    }).catch(() => {});
  }
}

// Completion of a plan consultation: mark the credit completed and release this
// consultation's share of the dietician's earnings EXACTLY ONCE (the child
// payments doc / test ledger id is deterministic per subscriptionId:planIndex and
// the credit flips to 'completed' in the same transaction).
async function _completePlanConsultation(db, appointmentId, appt) {
  const subRef = db.collection("nutrition_subscriptions").doc(appt.subscriptionId);
  const index = Number(appt.planIndex);
  let credited = false;
  let providerId = appt.nutritionistId;
  let share = 0;
  try {
    credited = await db.runTransaction(async (tx) => {
      const subSnap = await tx.get(subRef);
      if (!subSnap.exists) {
        _logSettlement("WARNING", "plan_completion_no_subscription", { appointmentId, subscriptionId: appt.subscriptionId });
        return false;
      }
      const sub = subSnap.data();
      providerId = sub.nutritionistId || providerId;
      const credits = (sub.consultations || []).map((c) => ({ ...c }));
      const c = credits.find((x) => x.index === index);
      if (!c || c.status === "completed") return false; // replay: already released
      if (c.appointmentId && c.appointmentId !== appointmentId) return false;

      const paid = !!sub.paymentId;
      let doCredit = false;
      let paymentSnap = null, childRef = null, childSnap = null, walletRef = null, walletSnap = null, ledgerRef = null;
      if (paid) {
        const paymentRef = db.collection("payments").doc(sub.paymentId);
        paymentSnap = await tx.get(paymentRef);
        childRef = db.collection("payments").doc(_ledgerId(`planshare:${subRef.id}:${index}`));
        childSnap = await tx.get(childRef);
        walletRef = db.collection("provider_wallets").doc(providerId);
        walletSnap = await tx.get(walletRef);
        ledgerRef = db.collection("wallet_ledger").doc(_ledgerId(`plan:${subRef.id}:${index}`));
        const pd = paymentSnap.exists ? paymentSnap.data() : null;
        if (pd && pd.status !== "refunded" && !childSnap.exists) {
          share = PlanH.splitPayout(Number(pd.providerAmount) || 0, sub.months)[index - 1] || 0;
          doCredit = share > 0;
        }
      } else {
        // Test mode (paymentStatus 'not_required'): same per-consultation share,
        // gated by the existing test-credit switches (flag + 7-day expiry + requirePayment off).
        share = PlanH.splitPayout(Number(sub.baseTotal) || 0, sub.months)[index - 1] || 0;
        if (share > 0) {
          doCredit = await _creditTestEarningsTx(db, tx, {
            sourceSnap: { data: () => ({ amount: share }) },
            sourceCollection: "nutrition_subscriptions", sourceId: `${subRef.id}:${index}`,
            providerId, serviceType: "nutrition",
          });
        }
      }

      if (paid && doCredit) {
        const pd = paymentSnap.data();
        tx.set(childRef, {
          paymentId: childRef.id, parentPaymentId: sub.paymentId, planSubscriptionId: subRef.id, planIndex: index,
          patientId: pd.patientId, providerId, serviceType: "nutrition",
          bookingRef: { collection: "nutrition_appointments", id: appointmentId },
          originalAmount: 0, discount: 0, couponCode: null, paidAmount: 0, walletPortionAmount: 0,
          commissionBase: share, baseAmount: share, platformFee: 0, commission: 0, providerAmount: share,
          commissionFinal: true, paymentMethod: "plan_share", razorpayPaymentId: null,
          status: "completed", settlementStatus: "eligible", settlementId: null,
          createdAt: FieldValue.serverTimestamp(), completedAt: FieldValue.serverTimestamp(),
          eligibleAt: FieldValue.serverTimestamp(),
        });
        const pendingBefore = walletSnap.exists ? Number(walletSnap.get("pendingEarnings")) || 0 : 0;
        tx.set(walletRef, {
          providerId, serviceType: "nutrition",
          pendingEarnings: _round2(pendingBefore + share), updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        tx.set(ledgerRef, _ledgerDoc({
          uid: providerId, walletType: "provider", type: "credit", amount: share,
          category: "settlement_pending", title: "Earnings Pending Settlement",
          description: `nutrition plan · consultation ${index}/${sub.months}`,
          source: `plan:${subRef.id}:${index}`, balanceAfter: null,
        }));
      }

      c.status = "completed";
      c.completedAt = Timestamp.now();
      const allDone = credits.every((x) => _PLAN_TERMINAL.includes(x.status));
      tx.update(subRef, {
        consultations: credits,
        ...(allDone && sub.status === "active" ? { status: "completed", completedAt: FieldValue.serverTimestamp() } : {}),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return doCredit;
    });
  } catch (err) {
    _logSettlement("ERROR", "plan_completion_failed", { appointmentId, subscriptionId: appt.subscriptionId, error: err.message });
    throw err;
  }
  if (credited) {
    _sendProviderNotification(db, getMessaging(), providerId, {
      title: "New Earnings", body: "A completed plan consultation is now pending settlement.",
      type: "new_earnings", serviceType: "nutrition",
    }).catch((e) => console.warn(JSON.stringify({ severity: "WARNING", event: "earnings_notification_failed", providerId: providerId, error: e && e.message })));
  }
}

// Test mode (requirePayment OFF): the patient app writes the plan booking
// directly with paymentStatus 'not_required'. Build the same subscription from
// the trusted diet_plans price so later months and the per-consultation test
// credit work identically. Rules deny client creates when requirePayment is ON.
exports.onNutritionPlanTestBookingCreated = onDocumentCreated(
  "nutrition_appointments/{appointmentId}",
  async (event) => {
    const d = event.data && event.data.data();
    if (!d || !PlanH.isPlanBooking(d) || d.subscriptionId || d.paymentId || d.paymentStatus !== "not_required") return;
    const uid = d.userId || d.patientId;
    if (!uid) return;
    const db = getFirestore();
    const appointmentId = event.params.appointmentId;
    let plan;
    try {
      plan = await _resolveWeightLossPlan(db, d);
    } catch (err) {
      _logSettlement("WARNING", "plan_test_booking_unresolved", { appointmentId, error: err.message });
      return;
    }
    const subRef = db.collection("nutrition_subscriptions").doc(_ledgerId(`plansub:test:${appointmentId}`));
    const apptRef = db.collection("nutrition_appointments").doc(appointmentId);
    await db.runTransaction(async (tx) => {
      const s = await tx.get(subRef);
      if (s.exists) return;
      const sub = _buildPlanSubscription({
        plan, bd: d, uid, paymentId: null, platformFee: Number(d.platformFee) || 0,
        firstAppointmentId: appointmentId, mode: "not_required",
      });
      tx.set(subRef, { ...sub.doc, startedAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp() });
      tx.update(apptRef, {
        subscriptionId: subRef.id, planIndex: 1, planId: plan.planId,
        planMonths: plan.months, planConsultations: plan.months, updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }
);

// Books one monthly consultation of a prepaid plan. No payment: the credit was
// paid for at purchase. Validated like a normal nutrition booking (real, unblocked
// slot of the dietician's schedule; not taken; not in the past); the slot trigger
// still arbitrates races and returns the credit if it loses.
// Request: { subscriptionId, date 'yyyy-MM-dd', timeSlot 'hh:mm AM', consultationType
//   'online'|'in_person', idempotencyKey, planIndex?, notes?, healthGoal? }
exports.bookPlanConsultation = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");
  const {
    subscriptionId, date, timeSlot, consultationType, idempotencyKey, planIndex, notes, healthGoal,
  } = request.data || {};
  if (typeof subscriptionId !== "string" || !subscriptionId.trim() || subscriptionId.includes("/") || subscriptionId.length > 300) {
    throw new HttpsError("invalid-argument", "subscriptionId is required.");
  }
  _safeId(subscriptionId, "subscriptionId");
  if (typeof date !== "string" || !PlanH.parseKey(date)) throw new HttpsError("invalid-argument", "Pick a valid date.");
  const slotMin = _slotStartMinutes(timeSlot);
  if (slotMin === null) throw new HttpsError("invalid-argument", "Pick a valid time slot.");
  if (!["online", "in_person"].includes(consultationType)) throw new HttpsError("invalid-argument", "Pick online or in-person.");
  if (typeof idempotencyKey !== "string" || !idempotencyKey.trim() || idempotencyKey.length > 200) {
    throw new HttpsError("invalid-argument", "idempotencyKey is required.");
  }
  const wanted = planIndex === undefined || planIndex === null ? null : Number(planIndex);
  if (wanted !== null && !(Number.isInteger(wanted) && wanted >= 1 && wanted <= 6)) {
    throw new HttpsError("invalid-argument", "Invalid consultation.");
  }
  const db = getFirestore();
  const subRef = db.collection("nutrition_subscriptions").doc(subscriptionId.trim());
  const bookingRef = db.collection("nutrition_appointments").doc(_ledgerId(`planbook:${uid}:${idempotencyKey.trim()}`));

  const existing = await bookingRef.get();
  if (existing.exists) {
    if (existing.get("userId") !== uid) throw new HttpsError("permission-denied", "Not allowed.");
    return { bookingId: bookingRef.id, planIndex: existing.get("planIndex") || null, alreadyBooked: true };
  }
  const subSnap = await subRef.get();
  if (!subSnap.exists || subSnap.get("patientId") !== uid) throw new HttpsError("not-found", "Plan not found.");
  const sub = subSnap.data();
  if (sub.status !== "active") throw new HttpsError("failed-precondition", "This plan is no longer active.");

  const today = PlanH.istDateKey();
  if (date < today || (date === today && slotMin <= _istNowMinutes())) {
    throw new HttpsError("failed-precondition", "That time has already passed. Please pick a later slot.");
  }
  const credit = PlanH.pickCredit(sub.consultations, date, wanted);
  if (!credit) {
    throw new HttpsError("failed-precondition",
      "No unused consultation covers that date. Pick a date inside a month of your plan that is still available.");
  }
  const nid = sub.nutritionistId;
  const profSnap = await db.collection("nutritionist_profiles").doc(nid).get();
  if (profSnap.exists) {
    const prof = profSnap.data();
    if (!_nutritionSlotAllowed(prof, date, timeSlot)) {
      throw new HttpsError("failed-precondition", "That time is not available with your dietician. Please pick another slot.");
    }
    if (consultationType === "online" && prof.isOnlineAvailable === false) {
      throw new HttpsError("failed-precondition", "Online consultations are not available with this dietician.");
    }
    if (consultationType === "in_person" && prof.isInPersonAvailable !== true) {
      throw new HttpsError("failed-precondition", "In-person visits are not available with this dietician.");
    }
  }
  const slotSnap = await db.collection("nutrition_slots").doc(_slotKey(nid, date, timeSlot)).get();
  if (slotSnap.exists) {
    const holderId = slotSnap.get("appointmentId");
    const holder = holderId ? await db.collection("nutrition_appointments").doc(holderId).get() : null;
    if (holder && holder.exists && _nutritionSlotOf(holder.data())?.key === _slotKey(nid, date, timeSlot)) {
      throw new HttpsError("already-exists", "That slot was just booked. Please pick another time.");
    }
  }

  const outcome = await db.runTransaction(async (tx) => {
    const b = await tx.get(bookingRef);
    if (b.exists) return { already: true, planIndex: b.get("planIndex") || null };
    const s = await tx.get(subRef);
    const cur = s.data();
    if (!s.exists || cur.status !== "active") throw new HttpsError("failed-precondition", "This plan is no longer active.");
    const credits = (cur.consultations || []).map((c) => ({ ...c }));
    const pick = PlanH.pickCredit(credits, date, wanted);
    if (!pick) throw new HttpsError("failed-precondition", "That month's consultation was already used.");
    const c = credits.find((x) => x.index === pick.index);
    c.status = "booked";
    c.appointmentId = bookingRef.id;
    tx.update(subRef, { consultations: credits, updatedAt: FieldValue.serverTimestamp() });
    tx.set(bookingRef, {
      userId: uid, patientId: uid,
      userName: cur.patientName || "Patient", userPhone: cur.patientPhone || "",
      nutritionistId: nid, nutritionistName: cur.nutritionistName || "",
      nutritionistSpecialization: cur.nutritionistSpecialization || "",
      consultationType, date, timeSlot, status: "pending",
      notes: typeof notes === "string" ? notes.trim().slice(0, 1000) : "",
      healthGoal: typeof healthGoal === "string" && healthGoal.trim() ? healthGoal.trim().slice(0, 80) : "Weight Loss",
      fee: 0, paymentStatus: "plan_prepaid",
      planType: PlanH.PLAN_TYPE, planMonths: cur.months, planConsultations: cur.months,
      planId: cur.planId, planIndex: pick.index, subscriptionId: subRef.id,
      // Display-only (partner app earnings label); the payout itself is computed server-side.
      planMonthlyPrice: Number(cur.monthlyPrice) || 0, planBaseTotal: Number(cur.baseTotal) || 0,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    return { already: false, planIndex: pick.index };
  });
  _logSettlement("INFO", "plan_consultation_booked", { uid, subscriptionId: subRef.id, bookingId: bookingRef.id, planIndex: outcome.planIndex });
  return { bookingId: bookingRef.id, planIndex: outcome.planIndex, alreadyBooked: outcome.already };
});

// Customer cancels the whole plan.
//  - NO consultation completed yet: the plan BASE is refunded through
//    _refundPayment (partial: wallet/gateway legs prorated); the platform fee is
//    NON-REFUNDABLE (client decision). Booked sessions are cancelled.
//  - >= 1 completed: no automatic refund. If app_config/nutrition_plans.refundUnused
//    is true the unused (not booked) credits' base share is recorded on the
//    subscription (unusedRefundDue) and an admin alert is raised for a manual refund.
//    Booked sessions stay and are honoured.
exports.cancelWeightLossPlan = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");
  const { subscriptionId, reason } = request.data || {};
  if (typeof subscriptionId !== "string" || !subscriptionId.trim() || subscriptionId.includes("/")) {
    throw new HttpsError("invalid-argument", "subscriptionId is required.");
  }
  _safeId(subscriptionId, "subscriptionId");
  const db = getFirestore();
  const subRef = db.collection("nutrition_subscriptions").doc(subscriptionId.trim());
  const note = typeof reason === "string" ? reason.trim().slice(0, 300) : "";

  // Claim ('cancelling') so two taps / retries cannot refund twice.
  const sub = await db.runTransaction(async (tx) => {
    const s = await tx.get(subRef);
    if (!s.exists || s.get("patientId") !== uid) throw new HttpsError("not-found", "Plan not found.");
    if (s.get("status") !== "active") throw new HttpsError("failed-precondition", "This plan is already closed.");
    tx.update(subRef, { status: "cancelling", updatedAt: FieldValue.serverTimestamp() });
    return s.data();
  });
  const revert = () => _guardedWrite("plan_revert_write_failed", { subscriptionId: subRef.id },
    () => subRef.update({ status: "active", updatedAt: FieldValue.serverTimestamp() }), {
      title: "Plan Stuck Cancelling", body: `Plan ${subRef.id} could not be restored to active after a failed cancel. Check it manually.`,
      type: "plan_revert_write_failed", extraData: { subscriptionId: subRef.id },
    });
  let refundDone = false;
  let refundedAmt = 0;

  try {
    const credits = (sub.consultations || []).map((c) => ({ ...c }));
    const anyCompleted = credits.some((c) => c.status === "completed");
    const cfg = await _nutritionPlanConfig(db);
    let refunded = 0;
    let unusedRefundDue = 0;
    const bookedIds = credits.filter((c) => c.status === "booked" && c.appointmentId).map((c) => c.appointmentId);

    if (!anyCompleted) {
      const appts = await Promise.all(bookedIds.map((id) => db.collection("nutrition_appointments").doc(id).get()));
      if (appts.some((a) => a.exists && a.get("status") === "in_progress")) {
        throw new HttpsError("failed-precondition", "A session is in progress. You can cancel the plan once it ends.");
      }
      if (sub.paymentId) {
        const pSnap = await db.collection("payments").doc(sub.paymentId).get();
        const amount = PlanH.planRefundAmount({
          baseTotal: sub.baseTotal, platformFee: sub.platformFee, paidAmount: pSnap.exists ? pSnap.get("paidAmount") : 0,
        });
        if (amount > 0) {
          await _refundPayment(db, sub.paymentId, note || "Weight-loss plan cancelled by the customer", uid, {
            refundAmount: amount, nonRefundableFee: Number(sub.platformFee) || 0,
          });
          refunded = amount;
          refundDone = true;
          refundedAmt = amount;
        }
      }
      for (const a of appts) {
        if (a.exists && ["pending", "confirmed"].includes(a.get("status"))) {
          await a.ref.update({
            status: "cancelled", cancelledBy: "system", cancelReason: "plan_cancelled",
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      }
      credits.forEach((c) => { if (!_PLAN_TERMINAL.includes(c.status)) { c.status = "cancelled"; delete c.appointmentId; } });
    } else {
      if (cfg.refundUnused && sub.paymentId) {
        const pSnap = await db.collection("payments").doc(sub.paymentId).get();
        const total = Math.min(Number(sub.baseTotal) || 0, pSnap.exists ? Number(pSnap.get("providerAmount")) || 0 : 0);
        unusedRefundDue = PlanH.unusedShare(PlanH.splitPayout(total, sub.months), credits, ["available"]);
      }
      credits.forEach((c) => { if (c.status === "available") c.status = "cancelled"; });
      if (unusedRefundDue > 0) {
        _sendAdminAlert(db, getMessaging(), {
          title: "Plan Refund Due",
          body: `A weight-loss plan (${subRef.id}) was cancelled after a completed consultation. Unused credits worth ₹${unusedRefundDue.toFixed(0)} are due as a manual refund.`,
          type: "plan_unused_refund_due", extraData: { subscriptionId: subRef.id, paymentId: sub.paymentId || "" },
        }).catch(() => {});
      }
    }

    await subRef.update({
      status: "cancelled", consultations: credits, cancelledBy: "patient", cancelReason: note || "customer_cancelled",
      cancelledAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      refundedAmount: refunded, ...(unusedRefundDue > 0 ? { unusedRefundDue } : {}),
    });
    _logSettlement("INFO", "plan_cancelled", { uid, subscriptionId: subRef.id, refunded, anyCompleted, unusedRefundDue });
    return { success: true, refunded, nonRefundableFee: anyCompleted ? 0 : (Number(sub.platformFee) || 0), unusedRefundDue };
  } catch (err) {
    if (refundDone) {
      // Money already went back: never hand the plan back. Close it and report.
      _logSettlement("ERROR", "plan_cancel_post_refund_failed", { subscriptionId: subRef.id, error: err.message });
      await _guardedWrite("plan_close_after_refund_failed", { subscriptionId: subRef.id },
        () => subRef.set({ status: "cancelled", cancelledBy: "patient", cancelledAt: FieldValue.serverTimestamp() }, { merge: true }), {
          title: "Plan Not Closed After Refund", body: `Plan ${subRef.id} was refunded but could not be marked cancelled. Close it manually.`,
          type: "plan_close_after_refund_failed", extraData: { subscriptionId: subRef.id },
        });
      return { success: true, refunded: refundedAmt, nonRefundableFee: Number(sub.platformFee) || 0, unusedRefundDue: 0 };
    }
    // Nothing was refunded: hand the plan back to the customer.
    const cur = await subRef.get();
    if (cur.exists && cur.get("status") === "cancelling") await revert();
    if (err instanceof HttpsError) throw err;
    _logSettlement("ERROR", "plan_cancel_failed", { subscriptionId: subRef.id, error: err.message });
    throw new HttpsError("internal", "Could not cancel the plan. Please try again or contact support.");
  }
});

// Daily 09:00 IST: window-start / last-3-days reminders (stamped per credit, so
// each is sent once) and the lapse of unused credits past their window.
// Lapse policy (app_config/nutrition_plans.lapsePolicy): 'forfeit' (default and
// client-confirmed) = no refund and no dietician payout; 'refund_to_wallet' =
// the unused credit's base share is credited to the customer's wallet.
exports.processNutritionPlans = onSchedule(
  { schedule: "every day 09:00", timeZone: "Asia/Kolkata" },
  async () => {
    const db = getFirestore();
    const messaging = getMessaging();
    const today = PlanH.istDateKey();
    const cfg = await _nutritionPlanConfig(db);
    const subs = await db.collection("nutrition_subscriptions").where("status", "==", "active").limit(500).get();
    let sent = 0, lapsed = 0;
    for (const doc of subs.docs) {
      try {
        const notes = await db.runTransaction(async (tx) => {
          const snap = await tx.get(doc.ref);
          if (!snap.exists || snap.get("status") !== "active") return [];
          const sub = snap.data();
          const credits = (sub.consultations || []).map((c) => ({ ...c }));
          const toLapse = credits.filter((c) => c.status === "available" && c.windowEnd < today);
          const walletPlan = cfg.lapsePolicy === "refund_to_wallet" && !!sub.paymentId && toLapse.length > 0;
          let paySnap = null, userSnap = null;
          const ledgerSnaps = [];
          if (walletPlan) {
            paySnap = await tx.get(db.collection("payments").doc(sub.paymentId));
            userSnap = await tx.get(db.collection("users").doc(sub.patientId));
            for (const c of toLapse) {
              ledgerSnaps.push(await tx.get(db.collection("wallet_ledger").doc(_ledgerId(`plan_lapse:${snap.id}:${c.index}`))));
            }
          }
          const out = [];
          let walletBalance = walletPlan ? _walletBalanceOf(userSnap, "walletBalance") : 0;
          const shares = walletPlan && paySnap.exists && paySnap.get("status") !== "refunded"
            ? PlanH.splitPayout(Math.min(Number(sub.baseTotal) || 0, Number(paySnap.get("providerAmount")) || 0), sub.months)
            : null;
          toLapse.forEach((c, i) => {
            c.status = "lapsed";
            c.lapsedAt = Timestamp.now();
            let credit = 0;
            if (shares && !ledgerSnaps[i].exists) {
              credit = shares[c.index - 1] || 0;
              if (credit > 0) {
                walletBalance = _round2(walletBalance + credit);
                const userRef = db.collection("users").doc(sub.patientId);
                tx.set(userRef, { walletBalance }, { merge: true });
                tx.set(userRef.collection("transactions").doc(), _legacyTxDoc({
                  title: "Plan consultation refund", amount: credit, type: "credit", category: "refund", walletType: "main",
                }));
                tx.set(db.collection("wallet_ledger").doc(_ledgerId(`plan_lapse:${snap.id}:${c.index}`)), _ledgerDoc({
                  uid: sub.patientId, walletType: "main", type: "credit", amount: credit,
                  category: "refund", title: "Unused plan consultation",
                  description: `month ${c.index} of ${sub.months}`, source: `plan_lapse:${snap.id}:${c.index}`, balanceAfter: walletBalance,
                }));
              }
            }
            out.push({
              title: "Consultation Expired",
              body: credit > 0
                ? `Your month ${c.index} consultation expired unused. ₹${credit.toFixed(0)} was added to your wallet.`
                : `Your month ${c.index} consultation expired unused. Unused consultations are not refunded.`,
              type: "nutrition_plan_lapsed", key: `${snap.id}-l${c.index}`,
            });
          });
          for (const c of credits) {
            if (c.status !== "available" || c.windowStart > today || c.windowEnd < today) continue;
            const lastMonth = c.index === sub.months;
            const expiry = lastMonth ? ` Unused consultations expire on ${sub.endsAtDate} and are not refunded.` : "";
            if (today >= PlanH.addDaysKey(c.windowEnd, -3) && !c.endReminded) {
              c.endReminded = true;
              c.startReminded = true;
              out.push({
                title: "Consultation Ending Soon",
                body: `Your month ${c.index} consultation with ${sub.nutritionistName || "your dietician"} must be booked by ${c.windowEnd}.${expiry}`,
                type: "nutrition_plan_ending", key: `${snap.id}-e${c.index}`,
              });
            } else if (c.index > 1 && !c.startReminded) {
              c.startReminded = true;
              out.push({
                title: "Time for Your Monthly Consultation",
                body: `Your month ${c.index} consultation is ready to book (until ${c.windowEnd}).${expiry}`,
                type: "nutrition_plan_start", key: `${snap.id}-s${c.index}`,
              });
            }
          }
          if (!out.length && !toLapse.length) return [];
          const allDone = credits.every((x) => _PLAN_TERMINAL.includes(x.status));
          tx.update(doc.ref, {
            consultations: credits, ...(allDone ? { status: "completed", completedAt: FieldValue.serverTimestamp() } : {}),
            updatedAt: FieldValue.serverTimestamp(),
          });
          lapsed += toLapse.length;
          return out.map((n) => ({ ...n, patientId: sub.patientId }));
        });
        for (const n of notes) {
          await _sendPatientNotification(db, messaging, n.patientId, {
            title: n.title, body: n.body, type: n.type, serviceType: "nutrition",
            bookingId: n.key, actionType: "open_service",
          }).catch(() => {});
          sent++;
        }
      } catch (err) {
        _logSettlement("ERROR", "plan_scheduler_sub_failed", { subscriptionId: doc.id, error: err.message });
      }
    }
    _logSettlement("INFO", "plan_scheduler_run", { subscriptions: subs.size, notifications: sent, lapsed, policy: cfg.lapsePolicy });
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

    // The patient may cancel a booked/checked-in OP visit (firestore.rules);
    // the billing desk's list updates live, but staff should also be pushed.
    if (after.status === "cancelled" && after.hospitalId) {
      try {
        await _notifyHospitalStaff(getFirestore(), getMessaging(), after.hospitalId, {
          title: "OP Appointment Cancelled",
          body: `${after.patientName || "A patient"} cancelled their OP appointment${after.date ? ` for ${after.date}` : ""}.`,
          type: "hospital_appointment_cancelled",
          bookingId: appointmentId,
        });
      } catch (err) {
        console.error("Hospital cancel push failed:", err.message);
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
// ── Physio / Counselling availability (slot publishing) ─────────────────────
// Partners write `availability: {slotDuration, schedule, blockedSlots}` on their
// own profile doc — exactly the shape `doctors/{uid}.availability` uses (see
// mednu_doctor availability_screen.dart). It is mirrored onto the public
// listing doc (`physiotherapists`/`counsellors`) together with `availableDays`
// (enabled weekday names) and `slots` ({Mon: ['09:00 AM', ...]}, labels
// zero-padded 'HH:MM AM', blocked-by-date slots NOT applied there — those are
// date-specific and live in `availability.blockedSlots`).
const _THERAPY_WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

function _slotLabel(totalMins) {
  const h = Math.floor(totalMins / 60);
  const m = totalMins % 60;
  const period = h < 12 ? "AM" : "PM";
  const dh = h === 0 ? 12 : (h > 12 ? h - 12 : h);
  return `${String(dh).padStart(2, "0")}:${String(m).padStart(2, "0")} ${period}`;
}

function _therapyAvailabilityOf(profile) {
  const avail = profile && profile.availability;
  if (!avail || typeof avail !== "object") return null;
  const schedule = avail.schedule;
  if (!schedule || typeof schedule !== "object") return null;
  const slotDuration = Number(avail.slotDuration) > 0 ? Number(avail.slotDuration) : 30;
  const slots = {};
  const days = [];
  for (const day of _THERAPY_WEEKDAYS) {
    const ds = schedule[day];
    if (!ds || ds.enabled !== true) continue;
    const sp = String(ds.start || "09:00").split(":").map(Number);
    const ep = String(ds.end || "17:00").split(":").map(Number);
    if (sp.length < 2 || ep.length < 2 || sp.some(isNaN) || ep.some(isNaN)) continue;
    const start = sp[0] * 60 + sp[1];
    const end = ep[0] * 60 + ep[1];
    const list = [];
    for (let m = start; m + slotDuration <= end; m += slotDuration) list.push(_slotLabel(m));
    if (!list.length) continue;
    days.push(day);
    slots[day] = list;
  }
  return { availability: avail, availableDays: days, slots };
}

// `set(..., {merge:true})` deep-merges maps, so a removed blockedSlots date
// would linger on the listing; availability is therefore written with
// `update` (which replaces the field wholesale) and only when it changed.
async function _syncTherapyListingAvailability(listingRef, profile, existingListing) {
  const next = _therapyAvailabilityOf(profile);
  const prevJson = JSON.stringify(existingListing && existingListing.availability || null);
  const nextJson = JSON.stringify(next ? next.availability : null);
  if (prevJson === nextJson) return;
  await listingRef.update(next
    ? { availability: next.availability, availableDays: next.availableDays, slots: next.slots }
    : { availability: FieldValue.delete(), availableDays: [], slots: {} });
}

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
    onlineRate: profile.onlineRate ?? 0,
    clinicRate: profile.clinicRate ?? 0,
    homeRate: profile.homeRate ?? 0,
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
    await _syncTherapyListingAvailability(listingRef, profile, existing.exists ? existing.data() : null);
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
    await _syncTherapyListingAvailability(listingRef, profile, existing.exists ? existing.data() : null);
  }
);
// ══════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════
// ── Physio / Counselling: public slot index + reschedule mirror ─────────────
// `physio_slots` / `counselling_slots` /{providerId}_{yyyy-MM-dd}_{HH-MM-AM}
// hold only providerId/date/time (+ owning sessionId): the patient booking
// picker reads them to grey out taken slots without being able to read other
// patients' sessions. Server-written only (firestore.rules). A slot is held
// while the session is pending/accepted/in_progress with a provider assigned.
// Slots are only enforced for providers who have published availability, so a
// provider on the free-text fallback never has a booking cancelled by it.
const _THERAPY_SLOT_CFG = {
  physio_sessions: {
    sessions: "physio_sessions", slots: "physio_slots", providerField: "physiotherapistId",
    profiles: "physiotherapist_profiles", serviceType: "physiotherapy", noun: "physiotherapy session",
  },
  counselling_sessions: {
    sessions: "counselling_sessions", slots: "counselling_slots", providerField: "counsellorId",
    profiles: "counsellor_profiles", serviceType: "counselling", noun: "counselling session",
  },
};

// Patient app writes 'd/M/yyyy' (ServiceBookingSheet); partner/web may write
// 'yyyy-MM-dd'. Both normalise to ISO so one slot has exactly one key.
function _therapyDateIso(raw) {
  const s = String(raw || "").trim();
  let y; let mo; let d;
  let m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
  if (m) { y = +m[1]; mo = +m[2]; d = +m[3]; } else {
    m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
    if (!m) return null;
    d = +m[1]; mo = +m[2]; y = +m[3];
  }
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return `${y}-${String(mo).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

// '10:00 AM' / '9:00 am' / '14:30' (also with U+202F before AM/PM) -> '10:00 AM'.
function _therapyTimeLabel(raw) {
  const s = String(raw || "").replace(/[  ]/g, " ").trim();
  const m = s.match(/^(\d{1,2}):(\d{2})\s*([AaPp][Mm])?$/);
  if (!m) return null;
  let h = +m[1];
  const min = +m[2];
  if (min > 59) return null;
  if (m[3]) {
    const pm = m[3].toUpperCase() === "PM";
    if (h < 1 || h > 12) return null;
    if (pm && h !== 12) h += 12;
    if (!pm && h === 12) h = 0;
  } else if (h > 23) return null;
  return _slotLabel(h * 60 + min);
}

function _therapySlotOf(s, cfg) {
  if (!s || !["pending", "accepted", "in_progress"].includes(s.status)) return null;
  const providerId = s[cfg.providerField];
  if (!providerId) return null;
  const date = _therapyDateIso(s.preferredDate);
  const time = _therapyTimeLabel(s.preferredTime);
  if (!date || !time) return null;
  return { key: _slotKey(providerId, date, time), providerId, date, time };
}

async function _therapySlotHandler(event, cfg) {
  const db = getFirestore();
  const sessionId = event.params.sessionId;
  const beforeData = event.data.before?.exists ? event.data.before.data() : null;
  const afterData = event.data.after?.exists ? event.data.after.data() : null;
  const prev = _therapySlotOf(beforeData, cfg);
  const next = _therapySlotOf(afterData, cfg);
  if (prev && next && prev.key === next.key) return;

  if (next) {
    const prof = await db.collection(cfg.profiles).doc(next.providerId).get();
    const published = prof.exists && !!_therapyAvailabilityOf(prof.data());
    if (published) {
      const slotRef = db.collection(cfg.slots).doc(next.key);
      const conflict = await db.runTransaction(async (tx) => {
        const slotSnap = await tx.get(slotRef);
        const holderId = slotSnap.exists ? slotSnap.data().sessionId : null;
        if (holderId && holderId !== sessionId) {
          const holder = await tx.get(db.collection(cfg.sessions).doc(holderId));
          if (holder.exists && _therapySlotOf(holder.data(), cfg)?.key === next.key) return true;
        }
        tx.set(slotRef, {
          providerId: next.providerId, date: next.date, time: next.time, sessionId,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return false;
      });
      if (conflict) {
        if (prev) await _therapyRevertReschedule(db, cfg, sessionId, beforeData, afterData);
        else if (!beforeData) await _therapyCancelSlotLoser(db, cfg, sessionId, afterData);
        // else: a pool job claimed by a provider whose slot is already taken —
        // left alone (no slot held) rather than cancelling a confirmed job.
        return;
      }
    }
  }

  if (prev) {
    const ref = db.collection(cfg.slots).doc(prev.key);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists && snap.data().sessionId === sessionId) tx.delete(ref);
    });
  }
}

// Loser of a brand-new booking race: cancelled by the system; the status
// mirror then cancels the service request and auto-refunds a paid booking.
async function _therapyCancelSlotLoser(db, cfg, sessionId, afterData) {
  await db.collection(cfg.sessions).doc(sessionId).update({
    status: "cancelled", cancelledBy: "system", cancelReason: "slot_taken",
    slotConflictAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });
  console.log(JSON.stringify({ module: cfg.slots, event: "booking_cancelled_slot_taken", sessionId }));
  if (!afterData.patientId) return;
  await _sendPatientNotification(db, getMessaging(), afterData.patientId, {
    title: "Slot Just Taken",
    body: `Someone booked ${afterData.preferredTime} on ${afterData.preferredDate} a moment before you. Please pick another time${afterData.paymentId ? " — your payment is being refunded" : ""}.`,
    type: `${cfg.serviceType}_slot_taken`, serviceType: cfg.serviceType, bookingId: sessionId, actionType: "open_service",
  }).catch(() => {});
}

// A reschedule into a taken slot goes back to the original date/time.
async function _therapyRevertReschedule(db, cfg, sessionId, beforeData, afterData) {
  await db.collection(cfg.sessions).doc(sessionId).update({
    preferredDate: beforeData.preferredDate || "",
    preferredTime: beforeData.preferredTime || "",
    rescheduledAt: beforeData.rescheduledAt ?? FieldValue.delete(),
    rescheduledBy: beforeData.rescheduledBy ?? FieldValue.delete(),
    slotConflictAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  console.log(JSON.stringify({ module: cfg.slots, event: "reschedule_reverted", sessionId }));
  const opts = {
    title: "Reschedule Not Possible",
    body: `${afterData.preferredTime} on ${afterData.preferredDate} was just booked by someone else. The ${cfg.noun} stays at ${beforeData.preferredTime} on ${beforeData.preferredDate}.`,
    type: `${cfg.serviceType}_reschedule_conflict`, serviceType: cfg.serviceType, bookingId: sessionId,
  };
  if (afterData.rescheduledBy === "provider") {
    await _sendProviderNotification(db, getMessaging(), afterData[cfg.providerField], opts).catch(() => {});
  } else if (afterData.patientId) {
    await _sendPatientNotification(db, getMessaging(), afterData.patientId, { ...opts, actionType: "open_service" }).catch(() => {});
  }
}

exports.onPhysioSessionWrittenForSlots = onDocumentWritten(
  "physio_sessions/{sessionId}",
  (event) => _therapySlotHandler(event, _THERAPY_SLOT_CFG.physio_sessions),
);
exports.onCounsellingSessionWrittenForSlots = onDocumentWritten(
  "counselling_sessions/{sessionId}",
  (event) => _therapySlotHandler(event, _THERAPY_SLOT_CFG.counselling_sessions),
);

// Patient reschedule: service_requests -> session (the rules only let a patient
// touch preferredDate/preferredTime/rescheduledAt/rescheduledBy on a
// pending/accepted request). If the session has already started the request is
// put back to the session's values.
exports.onTherapyServiceRequestRescheduled = onDocumentUpdated(
  "service_requests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (after.type !== "physiotherapy" && after.type !== "counselling") return;
    if (before.preferredDate === after.preferredDate && before.preferredTime === after.preferredTime) return;
    if (after.rescheduledBy !== "patient") return;

    const cfg = after.type === "physiotherapy" ? _THERAPY_SLOT_CFG.physio_sessions : _THERAPY_SLOT_CFG.counselling_sessions;
    const db = getFirestore();
    const requestId = event.params.requestId;
    const sessionRef = db.collection(cfg.sessions).doc(requestId);

    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(sessionRef);
      if (!snap.exists) return null;
      const s = snap.data();
      if (!["pending", "accepted"].includes(s.status)) return { revert: s };
      if (s.preferredDate === after.preferredDate && s.preferredTime === after.preferredTime) return null;
      tx.update(sessionRef, {
        preferredDate: after.preferredDate || "", preferredTime: after.preferredTime || "",
        rescheduledAt: after.rescheduledAt || FieldValue.serverTimestamp(), rescheduledBy: "patient",
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { providerId: s[cfg.providerField] || null };
    });
    if (!result) return;
    if (result.revert) {
      await event.data.after.ref.update({
        preferredDate: result.revert.preferredDate || "", preferredTime: result.revert.preferredTime || "",
        rescheduledAt: FieldValue.delete(), rescheduledBy: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }
    if (result.providerId) {
      await _sendProviderNotification(db, getMessaging(), result.providerId, {
        title: "Session Rescheduled",
        body: `${after.patientName || "A patient"} moved their ${cfg.noun} to ${after.preferredDate} at ${after.preferredTime}.`,
        type: `${cfg.serviceType}_rescheduled`, serviceType: cfg.serviceType, bookingId: requestId,
      }).catch(() => {});
    }
  }
);

// Provider reschedule (and conflict reverts): session -> service_requests, then
// tell the patient. Idempotent: does nothing when the request already matches.
async function _therapySessionRescheduleMirror(event, cfg) {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.preferredDate === after.preferredDate && before.preferredTime === after.preferredTime) return;
  const db = getFirestore();
  const sessionId = event.params.sessionId;
  const requestRef = db.collection("service_requests").doc(after.sourceRequestId || sessionId);

  const mirrored = await db.runTransaction(async (tx) => {
    const snap = await tx.get(requestRef);
    if (!snap.exists) return false;
    const r = snap.data();
    if (r.preferredDate === after.preferredDate && r.preferredTime === after.preferredTime) return false;
    tx.update(requestRef, {
      preferredDate: after.preferredDate || "", preferredTime: after.preferredTime || "",
      rescheduledAt: after.rescheduledAt ?? FieldValue.delete(),
      rescheduledBy: after.rescheduledBy ?? FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  const conflictRevert = String(after.slotConflictAt?.toMillis?.() || "") !== String(before.slotConflictAt?.toMillis?.() || "");
  if (mirrored && after.rescheduledBy === "provider" && !conflictRevert && after.patientId) {
    await _sendPatientNotification(db, getMessaging(), after.patientId, {
      title: "Session Rescheduled",
      body: `Your provider moved your ${cfg.noun} to ${after.preferredDate} at ${after.preferredTime}.`,
      type: `${cfg.serviceType}_rescheduled`, serviceType: cfg.serviceType, bookingId: sessionId, actionType: "open_service",
    }).catch(() => {});
  }
}
exports.onPhysioSessionRescheduled = onDocumentUpdated(
  "physio_sessions/{sessionId}",
  (event) => _therapySessionRescheduleMirror(event, _THERAPY_SLOT_CFG.physio_sessions),
);
exports.onCounsellingSessionRescheduled = onDocumentUpdated(
  "counselling_sessions/{sessionId}",
  (event) => _therapySessionRescheduleMirror(event, _THERAPY_SLOT_CFG.counselling_sessions),
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

  // Freshest token across doctors/{uid} + all role profiles (falls back to the
  // profile's own token if the lookup finds nothing).
  let tokenCandidates = [];
  try { tokenCandidates = await _providerTokenCandidates(db, uid); } catch (_) {}
  if (!tokenCandidates.length && after.fcmToken) {
    tokenCandidates = [{ token: after.fcmToken, ms: 0, order: 0, refs: [db.collection(`${role}_profiles`).doc(uid)] }];
  }
  if (!tokenCandidates.length) {
    console.log(`No fcmToken for ${role} partner ${uid} — approval push skipped`);
    return;
  }

  try {
    await _sendToProviderCandidates(messaging, tokenCandidates, {
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
    }, `${role} partner ${uid}`);
    console.log(`Approval push attempted → ${role} partner ${uid}`);
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

// Copies the location a hospital billing-desk applicant picked at
// registration (hospital_profiles/{uid}.latitude/longitude) onto the shared
// `hospitals/{hospitalId}` catalog entry once a Director approves the
// account — firestore.rules only allows admin writes to `hospitals`, so the
// client can never do this itself. Runs on every status change rather than
// once, so a later re-approval (or an admin editing the linked hospital)
// still gets the latest coordinates picked at registration.
exports.onHospitalProfileApproved = onDocumentUpdated("hospital_profiles/{uid}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === after.status) return;
  if (after.status !== "active") return;

  const hospitalId = after.hospitalId;
  const lat = after.latitude;
  const lng = after.longitude;
  if (!hospitalId || typeof lat !== "number" || typeof lng !== "number") return;

  await getFirestore().collection("hospitals").doc(hospitalId).set(
    { latitude: lat, longitude: lng },
    { merge: true },
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

// Sends the freshly generated join link straight to the guest's WhatsApp
// (the number the account holder entered when booking for them). Best-effort:
// returns false instead of throwing, so a WhatsApp problem (template not yet
// approved, bad number, network) never stops the share-sheet link from being
// returned. notifyOnce is send-once-per-key, so a previous *failed* attempt is
// cleared first, otherwise it could never be retried once templates exist.
const waConfig = require("./whatsapp/config");
async function _sendGuestLinkOnWhatsApp({ appointmentId, exp, appt, guestPhone, deepLink }) {
  try {
    const { notifyOnce, guestRecipient, formatWhen, parseApptDateTime, cleanName } = require("./whatsapp/notify");
    const recipient = guestRecipient(guestPhone, appt.patientName);
    if (!recipient) return false;

    const dedupeKey = `guest_link:${appointmentId}:${exp}`;
    const logRef = getFirestore().collection("whatsapp_logs").doc(dedupeKey);
    const prev = await logRef.get();
    if (prev.exists && prev.data().status === "failed") await logRef.delete();

    const when = formatWhen(parseApptDateTime(appt.date, appt.time)) ||
      `${appt.date || ""} ${appt.time || ""}`.trim();
    const result = await notifyOnce(
      dedupeKey,
      recipient,
      "mednu_guest_join_link",
      [recipient.firstName, cleanName(appt.doctorName) || "your doctor", when, deepLink],
      appointmentId,
    );
    return !!result?.ok;
  } catch (e) {
    console.warn(`[createGuestJoinLink] WhatsApp send failed for ${appointmentId}: ${e?.message || e}`);
    return false;
  }
}

// Request data: { appointmentId: string }
// Response:     { deepLink: string, whatsappSent: boolean }
// App Check decision: ENFORCED. Called only from the signed-in patient app
// (App Check present). Also rate limited per appointment and per user.
exports.createGuestJoinLink = onCall({ enforceAppCheck: true, secrets: ["GUEST_LINK_SECRET", waConfig.WHATSAPP_TOKEN] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const { appointmentId } = request.data || {};
  if (typeof appointmentId !== "string" || !appointmentId.trim()) {
    throw new HttpsError("invalid-argument", "appointmentId is required.");
  }
  _safeId(appointmentId, "appointmentId");
  await _rateLimit(getFirestore(), `createGuestJoinLink:appt:${appointmentId.trim()}`, 5, 3600);
  await _rateLimit(getFirestore(), `createGuestJoinLink:uid:${uid}`, 20, 3600);

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
  const deepLink = `https://mednu-web.web.app/join.html?a=${appointmentId}&t=${token}&exp=${exp}`;
  const whatsappSent = await _sendGuestLinkOnWhatsApp({ appointmentId, exp, appt, guestPhone, deepLink });
  return { deepLink, whatsappSent };
});

// Request data: { appointmentId: string, token: string, exp: number }
// Response:     { customToken, doctorName, doctorSpecialty, date, time, consultationId }
// App Check decision: NOT enforced. Called by unauthenticated guests on the web
// page (mednu_web has no App Check), so enforcing would break guests. Protected
// by the HMAC token plus a per-client-IP rate limit.
exports.redeemGuestJoinLink = onCall({ secrets: ["GUEST_LINK_SECRET"] }, async (request) => {
  const { appointmentId, token, exp } = request.data || {};
  if (
    typeof appointmentId !== "string" || !appointmentId.trim() ||
    typeof token !== "string" || !token.trim() ||
    typeof exp !== "number"
  ) {
    throw new HttpsError("invalid-argument", "Invalid join link.");
  }
  _safeId(appointmentId, "appointmentId");
  const clientIp = request.rawRequest && request.rawRequest.ip;
  const ipKey = clientIp ? crypto.createHash("sha256").update(String(clientIp)).digest("hex") : "global";
  await _rateLimit(getFirestore(), `redeemGuestJoinLink:${ipKey}`, 20, 3600);

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

// App Check decision: NOT enforced. Called by both apps AND by guests on the web
// join page (mednu_web has no App Check); enforcing would lock guests out.
// Access is gated by the consultation participant / guest-claim check below,
// plus a rate limit per uid (or per guest appointment claim).
exports.generateAgoraToken = onCall({ secrets: ["AGORA_APP_CERTIFICATE"] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");

  const { channelName } = request.data || {};
  if (typeof channelName !== "string" || !channelName.trim()) {
    throw new HttpsError("invalid-argument", "channelName is required.");
  }
  const consultationId = _safeId(channelName, "channelName");
  const guestClaim = request.auth?.token?.guestAppointmentId;
  await _rateLimit(getFirestore(), guestClaim ? `generateAgoraToken:guest:${guestClaim}` : `generateAgoraToken:uid:${uid}`, 60, 3600);

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

// ── Account deletion (Play User Data policy / DPDP erasure) ──────────────────
// Apps file deletion_requests/{uid}; a Director reviews them in the admin
// panel, which calls processAccountDeletion. Approve erases personal data
// keyed by the user's uid (profile docs + subcollections, storage folders,
// Auth account). Transactional/legal records (appointments, consultations,
// payments, settlements, wallet ledger, audit logs) are deliberately KEPT,
// as the privacy policy states.
const _DELETION_UID_DOC_COLLECTIONS = [
  "users", "patient_notifications", "health_records", "period_tracker", "water_tracker",
  "pregnancy", "health_data", "emergency_contacts", "doctor_notifications",
  "provider_notifications", "doctor_status", "patients",
  "doctors", "lab_profiles", "pharmacy_profiles", "equipment_profiles", "equipment_vendors",
  "ambulance_profiles", "caregiver_profiles",
  "physiotherapist_profiles", "counsellor_profiles", "nutritionist_profiles", "hospital_profiles",
  "physiotherapists", "counsellors", "nutritionists", "caregivers", "care_assistants", "ambulances",
];
const _DELETION_STORAGE_PREFIXES = [
  "users", "doctors", "labs", "pharmacies", "ambulances", "caregivers",
  "physiotherapists", "counsellors", "nutritionists", "hospitals",
  ..._DELETION_UID_DOC_COLLECTIONS,
];

// App Check decision: NOT enforced yet. Called from the admin panel, which does
// not have App Check; the Director-only role check below is the gate.
exports.processAccountDeletion = onCall({ timeoutSeconds: 300 }, async (request) => {
  const adminUid = request.auth?.uid;
  const db = getFirestore();
  const adminSnap = await _assertAdmin(db, adminUid);
  if ((adminSnap.data().role || "director") !== "director") {
    throw new HttpsError("permission-denied", "Only a Director can process account deletions.");
  }
  const { uid, action, reason } = request.data || {};
  if (typeof uid !== "string" || !uid.trim() || uid.includes("/")) {
    throw new HttpsError("invalid-argument", "uid is required.");
  }
  if (!["approve", "reject"].includes(action)) {
    throw new HttpsError("invalid-argument", "action must be approve or reject.");
  }
  if (uid === adminUid) throw new HttpsError("failed-precondition", "You cannot delete your own admin account.");

  const reqRef = db.collection("deletion_requests").doc(uid);
  const reqSnap = await reqRef.get();
  if (!reqSnap.exists) throw new HttpsError("not-found", "Deletion request not found.");
  const prevStatus = reqSnap.data().status;
  if (!["pending", "failed"].includes(prevStatus)) {
    throw new HttpsError("failed-precondition", `Request is already ${prevStatus}.`);
  }

  if (action === "reject") {
    await reqRef.update({
      status: "rejected", reason: String(reason || "").slice(0, 500),
      processedBy: adminUid, processedAt: FieldValue.serverTimestamp(),
    });
    await db.collection("audit_logs").add(_auditLogDoc({
      actorId: adminUid, action: "rejectAccountDeletion", targetType: "deletion_requests", targetId: uid,
      before: { status: prevStatus }, after: { status: "rejected" },
    }));
    return { success: true, status: "rejected" };
  }

  // Never erase another admin through this path.
  if ((await db.collection("admins").doc(uid).get()).exists) {
    throw new HttpsError("failed-precondition", "This account is an admin account.");
  }

  await reqRef.update({ status: "processing", processedBy: adminUid });
  const errors = [];
  const attempt = async (label, fn) => {
    try { await fn(); } catch (e) { errors.push(`${label}: ${e.message}`); }
  };

  for (const col of _DELETION_UID_DOC_COLLECTIONS) {
    await attempt(`firestore:${col}`, () => db.recursiveDelete(db.collection(col).doc(uid)));
  }
  const { getStorage } = require("firebase-admin/storage");
  const bucket = getStorage().bucket("mednu-healthcare-app.firebasestorage.app");
  for (const prefix of new Set(_DELETION_STORAGE_PREFIXES)) {
    await attempt(`storage:${prefix}`, () => bucket.deleteFiles({ prefix: `${prefix}/${uid}/`, force: true }));
  }
  await attempt("auth", async () => {
    try { await getAuth().deleteUser(uid); }
    catch (e) { if (e.code !== "auth/user-not-found") throw e; }
  });

  const status = errors.length ? "failed" : "completed";
  await reqRef.update({
    status, processedBy: adminUid, processedAt: FieldValue.serverTimestamp(),
    errors: errors.slice(0, 20),
  });
  await db.collection("audit_logs").add(_auditLogDoc({
    actorId: adminUid, action: "approveAccountDeletion", targetType: "deletion_requests", targetId: uid,
    before: { status: prevStatus }, after: { status, errorCount: errors.length },
  }));
  if (errors.length) {
    throw new HttpsError("internal", `Deletion incomplete (${errors.length} errors). Details are on the request; retry to resume.`);
  }
  return { success: true, status };
});

// ── WhatsApp Cloud API notifications ─────────────────────────────────────
// See functions/whatsapp/ — a self-contained module (config, templates,
// Graph API client, dedupe-safe sender, Firestore triggers, reminder
// scheduler, inbound webhook). Does NOT call initializeApp() itself; it
// reuses the app already initialized at the top of this file via
// getFirestore()/getApp(). Exported functions:
//   onAppointmentWritten, onOrderWritten, onLabServiceRequestWritten,
//   onPaymentWritten, onSettlementWritten (Firestore triggers)
//   sendAppointmentReminders (every-10-minutes scheduler)
//   waWebhook (inbound webhook — GET verification + POST statuses/messages)
const waTriggers = require("./whatsapp/triggers");
const waReminders = require("./whatsapp/reminders");
const waWebhookModule = require("./whatsapp/webhook");

exports.onAppointmentWritten = waTriggers.onAppointmentWritten;
exports.onPrescriptionCreated = waTriggers.onPrescriptionCreated;
exports.onOrderWritten = waTriggers.onOrderWritten;
exports.onLabServiceRequestWritten = waTriggers.onLabServiceRequestWritten;
exports.onPaymentWritten = waTriggers.onPaymentWritten;
exports.onSettlementWritten = waTriggers.onSettlementWritten;
exports.sendAppointmentReminders = waReminders.sendAppointmentReminders;
exports.waWebhook = waWebhookModule.waWebhook;

// Test-only access to internal money helpers (functions/test). Inert unless
// MEDNU_TEST=1, so production behaviour is unchanged.
if (process.env.MEDNU_TEST === "1") {
  module.exports.__testing = {
    _refundPayment, _creditTestEarningsTx, _transitionPaymentToEligible, _computeProviderSplit,
    _completePlanConsultation, _createSettlementForProvider, _runSettlementQueueOnce,
    _ledgerId, _ledgerDoc, _round2, _rateLimit, _safeId,
  };
}
