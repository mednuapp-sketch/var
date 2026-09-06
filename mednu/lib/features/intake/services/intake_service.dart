import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Pre-consultation patient history — one doc per appointment, doc id ==
/// appointmentId (mirrors the `appointment_reviews/{appointmentId}` pattern
/// in review_service.dart). Filled by the patient after payment succeeds and
/// before the "Booking Confirmed" screen (see doctor_profile_screen.dart),
/// and streamed live into MedNU Doctor's appointment cards
/// (pre_consultation_summary_card.dart) so a submission shows up there
/// without the doctor needing to refresh.
class IntakeService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> submit({
    required String appointmentId,
    required String doctorId,
    required String doctorName,
    required Map<String, dynamic> data,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');
    if (appointmentId.trim().isEmpty) {
      throw Exception('Invalid appointment ID');
    }

    await _db.collection('patient_intake_forms').doc(appointmentId).set({
      ...data,
      'appointmentId': appointmentId,
      'patientId': uid,
      'doctorId': doctorId,
      'doctorName': doctorName,
      'submittedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> stream(
    String appointmentId,
  ) {
    if (appointmentId.trim().isEmpty) return const Stream.empty();
    return _db
        .collection('patient_intake_forms')
        .doc(appointmentId)
        .snapshots();
  }
}
