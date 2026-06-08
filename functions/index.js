/* eslint-disable max-len */
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

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
