import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// All Firestore access for the Nutrition module lives here — screens never
/// touch `FirebaseFirestore` directly. Unlike every other partner module,
/// this reads/writes `nutrition_appointments` directly: there is no Cloud
/// Function mirror and no claim/transaction dance, because
/// `nutritionistId` is already fixed at booking time (the patient picks a
/// specific nutritionist up front). `firestore.rules` restricts a
/// nutritionist's update to exactly `status`/`updatedAt`/`providerNotes`.
class NutritionAppointmentService {
  NutritionAppointmentService._();

  static final _db = FirebaseFirestore.instance;

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>> get _appointments =>
      _db.collection('nutrition_appointments');

  static Stream<QuerySnapshot<Map<String, dynamic>>> myAppointmentsStream(String nutritionistId) {
    return _appointments.where('nutritionistId', isEqualTo: nutritionistId).snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> appointmentStream(String id) =>
      _appointments.doc(id).snapshots();

  static Future<void> updateStatus(String id, String status) {
    return _appointments.doc(id).update({
      'status': status,
      // Marks a nutritionist-side cancel so the patient is auto-refunded
      // (onNutritionAppointmentStatusChange); patient cancels never set it.
      if (status == 'cancelled') 'cancelledBy': 'provider',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setProviderNotes(String id, String notes) {
    return _appointments.doc(id).update({
      'providerNotes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Slot labels already held on [date] by other appointments of this
  /// dietician (server-maintained `nutrition_slots` index; readable by any
  /// signed-in user).
  static Future<Set<String>> takenSlots(String nutritionistId, String date,
      {String? exceptAppointmentId}) async {
    final snap = await _db
        .collection('nutrition_slots')
        .where('nutritionistId', isEqualTo: nutritionistId)
        .where('date', isEqualTo: date)
        .get();
    return snap.docs
        .where((d) => d.data()['appointmentId'] != exceptAppointmentId)
        .map((d) => (d.data()['timeSlot'] as String?) ?? '')
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  /// Provider-proposed move of a pending/confirmed appointment. Only these
  /// keys may change (firestore.rules `_validNutritionReschedule`); status and
  /// the weight-loss plan fields are untouched. The slot-index trigger frees
  /// the old slot / takes the new one, reverts a taken/off-schedule target and
  /// notifies the patient.
  static Future<void> reschedule(String id, String date, String timeSlot) {
    return _appointments.doc(id).update({
      'date': date,
      'timeSlot': timeSlot,
      'rescheduledAt': FieldValue.serverTimestamp(),
      'rescheduledBy': 'provider',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
