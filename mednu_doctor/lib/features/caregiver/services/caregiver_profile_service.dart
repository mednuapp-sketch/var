import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Mirrors `LabProfileService` for the Caregiver role: a thin static-method
/// wrapper around `caregiver_profiles/{uid}`. A caregiver partner is the
/// same signed-in account as any other role, just with an additional profile
/// document — whose existence is what `firestore.rules`'
/// `isCaregiverPartner()` checks to decide who may read unclaimed visits.
class CaregiverProfileService {
  CaregiverProfileService._();

  static final _db = FirebaseFirestore.instance;

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static Future<bool> profileExists(String uid) async {
    final doc = await _db.collection('caregiver_profiles').doc(uid).get();
    return doc.exists;
  }

  static Future<Map<String, dynamic>?> getProfile(String uid) async {
    final doc = await _db.collection('caregiver_profiles').doc(uid).get();
    return doc.data();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(String uid) =>
      _db.collection('caregiver_profiles').doc(uid).snapshots();

  static Future<void> createProfile({
    required String uid,
    required String name,
    String photoUrl = '',
    List<String> certifications = const [],
    List<String> specialties = const [],
    num hourlyRate = 0,
    int experienceYears = 0,
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    await _db.collection('caregiver_profiles').doc(uid).set({
      'uid': uid,
      'name': name,
      'photoUrl': photoUrl,
      'certifications': certifications,
      'specialties': specialties,
      'hourlyRate': hourlyRate,
      'documentsVerified': false,
      'status': 'pending',
      'isVerified': false,
      'rating': 0.0,
      'totalReviews': 0,
      'totalVisits': 0,
      'experienceYears': experienceYears,
      'createdAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
  }

  /// `status`/`isVerified`/`rating`/`totalReviews`/`totalVisits` are rejected
  /// by `firestore.rules` for a self-update — a partner can't self-approve or
  /// inflate its own stats.
  static Future<void> updateProfile(String uid, Map<String, dynamic> data) =>
      _db.collection('caregiver_profiles').doc(uid).set(data, SetOptions(merge: true));
}
