/* eslint-disable max-len */
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");
const Razorpay = require("razorpay");
const crypto = require("crypto");

initializeApp();

// ── Incoming Consultation Alert ──────────────────────────────────────────────
//
// Fires when a patient creates a new consultation document.
// Reads the assigned doctor's FCM token and sends a high-priority call
// notification so the doctor is alerted even when the app is killed.
exports.onNewConsultation = onDocumentCreated(
  "consultations/{consultationId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (data.status !== "pending") return;

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
    const consultationId = event.params.consultationId;
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

    // Get patient's FCM token.
    let fcmToken = null;
    const userDoc = await db.collection("users").doc(patientId).get();
    if (userDoc.exists) fcmToken = userDoc.data().fcmToken || null;

    if (!fcmToken) return;

    const message = {
      token: fcmToken,
      data: {
        type: "review_prompt",
        appointmentId,
        doctorId: after.doctorId || "",
        doctorName,
      },
      android: {
        priority: "normal",
        notification: {
          channelId: "default",
          title: `How was your visit with ${doctorName}?`,
          body: "Share your experience to help other patients.",
        },
      },
      apns: {
        headers: { "apns-priority": "5" },
        payload: {
          aps: {
            alert: {
              title: `How was your visit with ${doctorName}?`,
              body: "Share your experience to help other patients.",
            },
            sound: "default",
          },
        },
      },
    };

    try {
      await getMessaging().send(message);
      console.log(`Review prompt sent to patient ${patientId} for appt ${appointmentId}`);
    } catch (err) {
      console.error("Review prompt FCM failed:", err);
    }
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

    let title = "";
    let body = "";

    if (after.status === "ongoing") {
      title = "Doctor accepted your request";
      body = `${after.doctorName || "Your doctor"} is joining the call now.`;
    } else if (after.status === "declined") {
      title = "Request declined";
      body = `${after.doctorName || "The doctor"} is unavailable right now. Please try again.`;
    } else if (after.status === "missed") {
      title = "No answer";
      body = "The doctor did not respond. Please try again or schedule an appointment.";
    } else if (after.status === "completed" || after.status === "ended") {
      title = "Consultation completed";
      body = `Your session with ${after.doctorName || "the doctor"} has ended.`;
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
    const doctorsSnap = await db.collection("doctors")
      .where("status", "==", "active")
      .get();

    const tokens = [];
    const doctorIds = [];
    doctorsSnap.forEach((doc) => {
      const token = doc.data().fcmToken;
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
// Fires on every status transition in the appointments collection.
// Handles: booked, accepted/confirmed, rejected, rescheduled, started,
//          prescription_uploaded, completed, cancelled.
exports.onAppointmentStatusChange = onDocumentUpdated(
  "appointments/{appointmentId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status) return;

    const patientId = after.patientId;
    if (!patientId) return;

    const db        = getFirestore();
    const messaging = getMessaging();
    const apptId    = event.params.appointmentId;
    const doctorName = after.doctorName || "your doctor";
    const doctorId   = after.doctorId   || "";

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
        title = "Appointment Booked";
        body  = formattedDt
          ? `Your appointment with Dr. ${doctorName} has been booked for ${formattedDt}.`
          : `Your appointment with Dr. ${doctorName} has been successfully booked.`;
        type  = "appointment_booked";
        break;
      case "confirmed":
      case "accepted":
        title = "Appointment Confirmed";
        body  = formattedDt
          ? `Your appointment with Dr. ${doctorName} is confirmed for ${formattedDt}.`
          : `Dr. ${doctorName} accepted your appointment.`;
        type  = "appointment_accepted";
        break;
      case "rejected":
      case "declined":
        title = "Appointment Rejected";
        body  = `Your appointment with Dr. ${doctorName} was not accepted. Please book another slot.`;
        type  = "appointment_rejected";
        break;
      case "rescheduled":
        title = "Appointment Rescheduled";
        body  = formattedDt
          ? `Your appointment with Dr. ${doctorName} has been rescheduled to ${formattedDt}.`
          : `Your appointment with Dr. ${doctorName} has been rescheduled.`;
        type  = "appointment_rescheduled";
        break;
      case "started":
      case "call_started":
        title = "Doctor is Calling You";
        body  = `Dr. ${doctorName} is calling you now. Tap to join.`;
        type  = "doctor_started_call";
        actionType = "open_call";
        break;
      case "prescription_uploaded":
        title = "Prescription Ready";
        body  = `Your prescription from Dr. ${doctorName} is ready. Tap to view.`;
        type  = "prescription_uploaded";
        actionType = "open_prescription";
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

    // Format checkup date if available.
    let formattedDate = "";
    const rawDate = after.checkupDate || after.scheduledAt || after.date || null;
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

    if (target === "specific_user" && targetUserId) {
      const userDoc = await db.collection("users").doc(targetUserId).get();
      if (userDoc.exists) {
        const t = userDoc.data().fcmToken;
        if (t) tokens.push(t);
      }
    }

    if (!tokens.length) {
      console.log(`Broadcast ${event.params.broadcastId}: no FCM tokens — in-app only.`);
      return;
    }

    // ── Build FCM message ────────────────────────────────────────────────────
    const fcmData = { type: String(type || "general"), actionType: "open_notifications" };
    if (link) fcmData.link = String(link);

    let successCount = 0;
    let failCount    = 0;

    // Send in 500-token chunks (FCM sendEachForMulticast limit).
    for (let i = 0; i < tokens.length; i += 500) {
      const chunk = tokens.slice(i, i + 500);
      const msg = {
        tokens: chunk,
        data:   fcmData,
        android: {
          priority: "high",
          notification: {
            channelId:             "mednu_default_channel",
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
        console.error(`Broadcast chunk ${Math.floor(i / 500) + 1} FCM error:`, err);
      }
    }

    // ── Mark broadcast as pushed ─────────────────────────────────────────────
    try {
      await snap.ref.update({
        fcmSentAt:       FieldValue.serverTimestamp(),
        fcmTokenCount:   tokens.length,
        fcmSuccessCount: successCount,
        fcmFailCount:    failCount,
      });
    } catch (_) {}

    console.log(
      `Broadcast ${event.params.broadcastId}: FCM ${successCount}/${tokens.length} sent, ${failCount} failed.`
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
      labId: null,
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
      pharmacyId: null,
      status: "pending",
      requiresPrescription,
      prescriptionUrl: null,
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
        name: item.name || "Item",
        brand: item.brand || "",
        price: item.price ?? 0,
        count: item.count ?? 1,
        subtotal: (item.price ?? 0) * (item.count ?? 1),
      });
    });
    await batch.commit();

    _logPharmacy("INFO", "pharmacy_order_created", { orderId, orderType: "medicine", items: items.length, requiresPrescription });
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

    await requestRef.set({
      sourceRequestId: requestId,
      type: "ambulance",
      status: "pending",
      patientId: data.patientId,
      patientName: data.patientName || "Patient",
      patientPhone: data.patientPhone || "",
      pickupAddress: data.address || "",
      dropAddress: details.dropAddress || "",
      distanceKm: details.distanceKm ?? 0,
      etaMinutes: details.etaMinutes ?? 0,
      fare: data.amount ?? details.fare ?? 0,
      emergencyType: _ambulanceEmergencyType(details.ambulanceType),
      ambulanceId: null,
      requestedAt: data.createdAt || FieldValue.serverTimestamp(),
      createdAt: data.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    _logAmbulance("INFO", "ambulance_request_created", { requestId });
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

    const batch = db.batch();
    batch.set(visitRef, {
      sourceRequestId: requestId,
      sourceType: data.type,
      type: _caregiverCareType(details.specialty || details.shiftType || data.serviceName),
      status: "scheduled",
      patientId: data.patientId,
      patientName: data.patientName || "Patient",
      patientAge: 0,
      address: data.address || "",
      scheduledAt: _caregiverScheduledAt(data),
      durationMinutes,
      fare: data.amount ?? 0,
      photoUrls: [],
      caregiverId: null,
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
    _logCaregiver("INFO", "caregiver_visit_created", { requestId, sourceType: data.type });
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
const _WATER_SPAN_MINUTES = 13 * 60; // matches _reminderSpanMinutes client-side
const _WATER_TICK_MINUTES = 15;      // matches this function's own schedule below

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
    const startMinutes = (w.reminderStartHour ?? 8) * 60 + (w.reminderStartMinute ?? 0);

    // Which slot (if any) falls inside this tick's window?
    let matchedSlot = null;
    for (let offset = 0; offset <= _WATER_SPAN_MINUTES; offset += intervalMinutes) {
      const slotMinute = startMinutes + offset;
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
