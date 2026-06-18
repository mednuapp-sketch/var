import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/doctor_review.dart';

class ReviewService {
  static final _db = FirebaseFirestore.instance;

  // Check whether the current patient can review a given appointment.
  // Returns the appointment data if eligible, null otherwise.
  static Future<Map<String, dynamic>?> checkEligibility({
    required String appointmentId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    // 1. Verify appointment exists, belongs to patient, and is completed.
    final apptSnap =
        await _db.collection('appointments').doc(appointmentId).get();
    if (!apptSnap.exists) return null;

    final appt = apptSnap.data();
    if (appt == null) return null;
    if (appt['patientId'] != uid) return null;
    if (appt['status'] != 'completed') return null;

    // 2. Ensure no review has already been submitted for this appointment.
    final reviewCheck =
        await _db.collection('appointment_reviews').doc(appointmentId).get();
    if (reviewCheck.exists && reviewCheck.data()?['reviewed'] == true) {
      return null; // Already reviewed
    }

    return appt;
  }

  // Submit a new verified review. Uses a transaction to prevent duplicates and
  // atomically update the doctor_rating_summary aggregate document.
  static Future<void> submitReview({
    required String appointmentId,
    required String doctorId,
    required double rating,
    required String reviewText,
    required ReviewCategories categories,
    required String consultationType,
  }) async {
    if (appointmentId.trim().isEmpty) throw Exception('Invalid appointment ID');
    if (doctorId.trim().isEmpty) throw Exception('Invalid doctor ID');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final patientName =
        user.displayName ?? user.phoneNumber ?? 'Patient';

    final summaryRef = _db.collection('doctor_rating_summary').doc(doctorId);

    await _db.runTransaction((tx) async {
      // Double-check eligibility inside transaction.
      final lockRef =
          _db.collection('appointment_reviews').doc(appointmentId);
      final lockSnap = await tx.get(lockRef);

      if (lockSnap.exists && lockSnap.data()?['reviewed'] == true) {
        throw Exception('already_reviewed');
      }

      // Read current rating summary to compute updated aggregate.
      final summarySnap = await tx.get(summaryRef);
      final sData = summarySnap.data() ?? {};
      final prevTotal = (sData['totalReviews'] as num?)?.toInt() ?? 0;
      final prevAvg   = (sData['averageRating'] as num?)?.toDouble() ?? 0.0;
      final newTotal  = prevTotal + 1;
      final newAvg    = ((prevAvg * prevTotal) + rating) / newTotal;

      // Build updated rating distribution (1–5 star counts).
      final rawDist = sData['ratingDistribution'] as Map<dynamic, dynamic>? ?? {};
      final dist = <String, int>{
        '1': (rawDist['1'] as num?)?.toInt() ?? 0,
        '2': (rawDist['2'] as num?)?.toInt() ?? 0,
        '3': (rawDist['3'] as num?)?.toInt() ?? 0,
        '4': (rawDist['4'] as num?)?.toInt() ?? 0,
        '5': (rawDist['5'] as num?)?.toInt() ?? 0,
      };
      final starKey = rating.round().clamp(1, 5).toString();
      dist[starKey] = (dist[starKey] ?? 0) + 1;

      // Create the review document.
      final reviewRef = _db.collection('doctor_reviews').doc();
      tx.set(reviewRef, DoctorReview(
        id: reviewRef.id,
        doctorId: doctorId,
        patientId: user.uid,
        patientName: patientName,
        appointmentId: appointmentId,
        sourceType: 'appointment',
        rating: rating,
        reviewText: reviewText,
        categories: categories,
        consultationType: consultationType,
        createdAt: DateTime.now(),
      ).toMap());

      // Mark appointment as reviewed to prevent duplicates.
      tx.set(lockRef, {
        'reviewed': true,
        'reviewId': reviewRef.id,
        'patientId': user.uid,
        'doctorId': doctorId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Atomically update the aggregate rating summary.
      tx.set(summaryRef, {
        'doctorId': doctorId,
        'totalReviews': newTotal,
        'averageRating': double.parse(newAvg.toStringAsFixed(2)),
        'ratingDistribution': dist,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Mirror rating onto the doctor profile for quick reads (patient list).
      final doctorRef = _db.collection('doctors').doc(doctorId);
      tx.update(doctorRef, {
        'rating':       double.parse(newAvg.toStringAsFixed(2)),
        'totalReviews': newTotal,
      });
    });
  }

  // Realtime stream of reviews for a doctor (non-flagged only).
  static Stream<List<DoctorReview>> reviewsStream(String doctorId,
      {int limit = 20}) {
    return _db
        .collection('doctor_reviews')
        .where('doctorId', isEqualTo: doctorId)
        .where('isFlagged', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => DoctorReview.fromDoc(d))
            .toList());
  }

  // Realtime stream of the aggregated rating summary for a doctor.
  static Stream<DoctorRatingSummary> ratingSummaryStream(String doctorId) {
    return _db
        .collection('doctor_rating_summary')
        .doc(doctorId)
        .snapshots()
        .map((snap) => snap.exists
            ? DoctorRatingSummary.fromDoc(snap)
            : DoctorRatingSummary.empty(doctorId));
  }

  // Check if a specific appointment has already been reviewed.
  static Future<bool> isReviewed(String appointmentId) async {
    final snap = await _db
        .collection('appointment_reviews')
        .doc(appointmentId)
        .get();
    return snap.exists && snap.data()?['reviewed'] == true;
  }
}
