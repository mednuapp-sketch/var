import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Mirrors `CaregiverProfileService` for the Nutritionist role: a thin
/// static-method wrapper around `nutritionist_profiles/{uid}`. A nutritionist
/// partner is the same signed-in account as any other role, just with an
/// additional profile document — whose approval is what
/// `onNutritionistProfileWriteForVisibility` (functions/index.js) mirrors
/// into the patient-facing `nutritionists/{uid}` catalogue entry.
class NutritionistProfileService {
  NutritionistProfileService._();

  static final _db = FirebaseFirestore.instance;

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(String uid) =>
      _db.collection('nutritionist_profiles').doc(uid).snapshots();

  static Future<void> createProfile({
    required String uid,
    required String name,
    String qualification = '',
    String specialization = '',
    int experienceYears = 0,
    num consultationFee = 0,
    String bio = '',
    String city = '',
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    await _db.collection('nutritionist_profiles').doc(uid).set({
      'uid': uid,
      'name': name,
      'qualification': qualification,
      'specialization': specialization,
      'experienceYears': experienceYears,
      'consultationFee': consultationFee,
      'bio': bio,
      'city': city,
      'documentsVerified': false,
      'status': 'pending',
      'isVerified': false,
      'rating': 0.0,
      'reviewCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
  }

  /// `status`/`isVerified`/`rating`/`reviewCount` are rejected by
  /// `firestore.rules` for a self-update — a partner can't self-approve or
  /// inflate its own stats.
  static Future<void> updateProfile(String uid, Map<String, dynamic> data) =>
      _db.collection('nutritionist_profiles').doc(uid).set(data, SetOptions(merge: true));
}
