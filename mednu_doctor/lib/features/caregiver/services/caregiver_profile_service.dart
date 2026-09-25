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
    String city = '',
    double? lat,
    double? lng,
    String phone = '',
    String email = '',
    String gender = '',
    String serviceType = 'caregiver',
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 5));
    } catch (_) {}

    await _db.collection('caregiver_profiles').doc(uid).set({
      'uid': uid,
      'name': name,
      'phone': phone,
      'email': email,
      'photoUrl': photoUrl,
      'certifications': certifications,
      'specialties': specialties,
      'hourlyRate': hourlyRate,
      'documentsVerified': false,
      'status': 'pending',
      'isVerified': false,
      'isOnDuty': false,
      'rating': 0.0,
      'totalReviews': 0,
      'totalVisits': 0,
      'experienceYears': experienceYears,
      'gender': gender,
      'serviceType': serviceType,
      'city': city,
      if (lat != null && lng != null) 'lat': lat,
      if (lat != null && lng != null) 'lng': lng,
      'createdAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
  }

  /// `status`/`isVerified`/`rating`/`totalReviews`/`totalVisits` are rejected
  /// by `firestore.rules` for a self-update — a partner can't self-approve or
  /// inflate its own stats.
  static Future<void> updateProfile(String uid, Map<String, dynamic> data) =>
      _db.collection('caregiver_profiles').doc(uid).set(data, SetOptions(merge: true));

  /// Persists the Dashboard's on-duty/availability toggle. Not in
  /// firestore.rules' protected-fields list for this collection, so a
  /// self-write is allowed. Read back live via `caregiverOnDutyProvider`,
  /// which watches the same [profileStream] this field lives on — so every
  /// screen reflects real server-side state instead of a local flag.
  static Future<void> updateOnDuty(String uid, bool value) =>
      _db.collection('caregiver_profiles').doc(uid).set({
        'isOnDuty': value,
      }, SetOptions(merge: true));

  /// `photoUrl` isn't in firestore.rules' protected-fields list for this
  /// collection either, so a self-write is allowed — same trust boundary as
  /// [updateOnDuty]/[updateProfile]. Used by [CaregiverProfileScreen]'s
  /// avatar upload/remove flow, mirroring `HospitalProfileService.
  /// updatePhotoUrl`.
  static Future<void> updatePhotoUrl(String uid, String photoUrl) =>
      _db.collection('caregiver_profiles').doc(uid).set({
        'photoUrl': photoUrl,
      }, SetOptions(merge: true));
}
