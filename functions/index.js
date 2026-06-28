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

    if (!doctorId || typeof rating !== "number") return;

    const db = getFirestore();
    const summaryRef = db.collection("doctor_rating_summary").doc(doctorId);

    await db.runTransaction(async (tx) => {
      const summarySnap = await tx.get(summaryRef);

      if (!summarySnap.exists) {
        tx.set(summaryRef, {
          averageRating: rating,
          totalReviews: 1,
          ratingDistribution: { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, [Math.round(rating)]: 1 },
          lastUpdated: FieldValue.serverTimestamp(),
        });
      } else {
        const data = summarySnap.data();
        const oldTotal = data.totalReviews || 0;
        const oldAvg = data.averageRating || 0;
        const newTotal = oldTotal + 1;
        const newAvg = parseFloat(((oldAvg * oldTotal + rating) / newTotal).toFixed(2));
        const dist = data.ratingDistribution || { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
        const bucket = Math.round(rating).toString();
        dist[bucket] = (dist[bucket] || 0) + 1;

        tx.update(summaryRef, {
          averageRating: newAvg,
          totalReviews: newTotal,
          ratingDistribution: dist,
          lastUpdated: FieldValue.serverTimestamp(),
        });
      }

      // Also mirror rating onto the doctors document for query-time sorting.
      const doctorRef = db.collection("doctors").doc(doctorId);
      const summaryAfter = await tx.get(summaryRef);
      const newAvgMirrored = summaryAfter.exists
        ? summaryAfter.data().averageRating
        : rating;
      tx.update(doctorRef, {
        rating: newAvgMirrored,
        totalReviews: FieldValue.increment(1),
      });
    });

    console.log(`Rating summary updated for doctor ${doctorId}`);
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
      .get();

    if (staleSnap.empty) return;

    const batch = db.batch();
    staleSnap.forEach((doc) => {
      batch.update(doc.ref, {
        status: "missed",
        missedAt: FieldValue.serverTimestamp(),
        expiredBy: "auto_cleanup",
      });
    });
    await batch.commit();
    console.log(`Auto-expired ${staleSnap.size} stale pending consultation(s).`);
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
      lab: {
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

// ── Razorpay: Create Order ────────────────────────────────────────────────────
//
// Called from the Flutter app before opening the Razorpay checkout modal.
// Creates an order on Razorpay's servers and returns the order_id so the
// client can include it in the checkout options (required for Standard Checkout).
//
// Request data: { amount: number (paise), currency?: string, receipt?: string }
// Response:     { order_id: string, amount: number, currency: string }
exports.createRazorpayOrder = onCall({ enforceAppCheck: true }, async (request) => {
  const { amount, currency = "INR", receipt } = request.data || {};

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

  return { verified: true };
});

// ── MSG91: Send OTP ───────────────────────────────────────────────────────────
//
// Called from Flutter before showing the OTP screen.
// Sends a 6-digit OTP to the given phone via MSG91.
// Auth key and widget/template ID are stored in Cloud Function environment
// variables — never exposed to the client.
//
// Set via:
//   firebase functions:secrets:set MSG91_AUTH_KEY
//   firebase functions:config:set msg91.template_id="YOUR_TEMPLATE_ID"
// Or add to functions/.env:
//   MSG91_AUTH_KEY=your_auth_key
//   MSG91_TEMPLATE_ID=your_template_or_widget_id
//
// Request:  { phone: "+919876543210" }
// Response: { success: true }
exports.msg91SendOtp = onCall({ invoker: "public" }, async (request) => {
  const { phone } = request.data || {};

  if (!phone || !/^\+91\d{10}$/.test(phone)) {
    throw new HttpsError("invalid-argument", "Invalid phone number. Must be +91 followed by 10 digits.");
  }

  const authKey = process.env.MSG91_AUTH_KEY;
  const templateId = process.env.MSG91_TEMPLATE_ID;

  if (!authKey || !templateId) {
    console.error("MSG91 credentials not configured in environment.");
    throw new HttpsError("internal", "OTP service not configured.");
  }

  // MSG91 expects mobile without '+': 919876543210
  const mobile = phone.replace("+", "");

  try {
    const res = await fetch("https://control.msg91.com/api/v5/otp", {
      method: "POST",
      headers: {
        "authkey": authKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        template_id: templateId,
        mobile,
        otp_length: "4",
        otp_expiry: "10",
      }),
    });

    const data = await res.json();
    console.log("MSG91 sendOtp response:", JSON.stringify(data));

    if (data.type !== "success") {
      throw new HttpsError("internal", data.message || "Failed to send OTP. Please try again.");
    }

    return { success: true };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    console.error("MSG91 sendOtp error:", err);
    throw new HttpsError("internal", "Failed to send OTP. Please try again.");
  }
});

// ── MSG91: Verify OTP + Issue Firebase Custom Token ───────────────────────────
//
// Called from Flutter after the user enters the OTP.
// 1. Verifies the OTP with MSG91.
// 2. Finds or creates a Firebase Auth user by phone number.
// 3. Returns a Firebase custom token for signInWithCustomToken().
//
// Request:  { phone: "+919876543210", otp: "123456" }
// Response: { customToken: "<firebase-custom-token>" }
exports.msg91VerifyOtp = onCall({ invoker: "public" }, async (request) => {
  const { phone, otp } = request.data || {};

  if (!phone || !/^\+91\d{10}$/.test(phone)) {
    throw new HttpsError("invalid-argument", "Invalid phone number.");
  }
  if (!otp || !/^\d{4}$/.test(otp)) {
    throw new HttpsError("invalid-argument", "Invalid OTP format.");
  }

  const authKey = process.env.MSG91_AUTH_KEY;
  if (!authKey) {
    throw new HttpsError("internal", "OTP service not configured.");
  }

  const mobile = phone.replace("+", "");

  // ── Step 1: Verify OTP with MSG91 ─────────────────────────────────────────
  try {
    const res = await fetch(
      `https://control.msg91.com/api/v5/otp/verify?otp=${otp}&mobile=${mobile}`,
      {
        method: "GET",
        headers: { "authkey": authKey },
      }
    );

    const data = await res.json();
    console.log("MSG91 verifyOtp response:", JSON.stringify(data));

    if (data.type !== "success") {
      throw new HttpsError("unauthenticated", "Incorrect OTP. Please check and try again.");
    }
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    console.error("MSG91 verifyOtp error:", err);
    throw new HttpsError("internal", "OTP verification failed. Please try again.");
  }

  // ── Step 2: Find or create Firebase user by phone ─────────────────────────
  const auth = getAuth();
  let uid;

  try {
    const user = await auth.getUserByPhoneNumber(phone);
    uid = user.uid;
    console.log(`MSG91 auth: found existing Firebase user ${uid} for ${phone}`);
  } catch (err) {
    if (err.code === "auth/user-not-found") {
      const newUser = await auth.createUser({ phoneNumber: phone });
      uid = newUser.uid;
      console.log(`MSG91 auth: created new Firebase user ${uid} for ${phone}`);
    } else {
      console.error("Firebase getUserByPhoneNumber error:", err);
      throw new HttpsError("internal", "Authentication failed. Please try again.");
    }
  }

  // ── Step 3: Issue Firebase custom token ────────────────────────────────────
  const customToken = await auth.createCustomToken(uid);
  return { customToken };
});
