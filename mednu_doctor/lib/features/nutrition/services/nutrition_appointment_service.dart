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
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setProviderNotes(String id, String notes) {
    return _appointments.doc(id).update({
      'providerNotes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
