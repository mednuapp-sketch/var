import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../shared_core/services/pending_profile_edit_service.dart';

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
    List<String> languages = const [],
    String phone = '',
    String email = '',
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 5));
    } catch (_) {}

    await _db.collection('nutritionist_profiles').doc(uid).set({
      'uid': uid,
      'name': name,
      'phone': phone,
      'email': email,
      'qualification': qualification,
      'specialization': specialization,
      'experienceYears': experienceYears,
      'consultationFee': consultationFee,
      'bio': bio,
      'city': city,
      'languages': languages,
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
  /// inflate its own stats. Once `currentStatus` is 'active', this doesn't
  /// touch the live fields at all — see [PendingProfileEditService].
  static Future<void> updateProfile(String uid, Map<String, dynamic> data, {required String currentStatus}) =>
      PendingProfileEditService.apply(
        ref: _db.collection('nutritionist_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: data,
      );

  /// Used by [NutritionProfileScreen]'s avatar upload/remove flow. Once
  /// `currentStatus` is 'active', this doesn't touch the live `photoUrl` at
  /// all — see [PendingProfileEditService].
  static Future<void> updatePhotoUrl(String uid, String photoUrl, {required String currentStatus}) =>
      PendingProfileEditService.apply(
        ref: _db.collection('nutritionist_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: {'photoUrl': photoUrl},
      );

  /// Remote/video-consult availability toggle — also not in the protected-
  /// fields list, so a self-write is always allowed regardless of
  /// approval `status`. Used by [NutritionDashboardScreen]'s availability
  /// card; read back live via `nutritionistProfileProvider`.
  static Future<void> setOnlineStatus(String uid, bool isOnline) =>
      _db.collection('nutritionist_profiles').doc(uid).set({
        'isOnline': isOnline,
      }, SetOptions(merge: true));

  /// Publishes the weekly schedule + consultation modes. Operational, so
  /// (like `doctors.availability`) it is written directly even once `active`
  /// — firestore.rules whitelists `availability`/`isOnlineAvailable`/
  /// `isInPersonAvailable` — and `onNutritionistProfileWriteForVisibility`
  /// re-mirrors it into the patient-facing `nutritionists/{uid}`.
  /// Dotted paths so `availability.blockedSlots` is never wiped.
  static Future<void> saveAvailability(
    String uid, {
    required int slotDuration,
    required Map<String, dynamic> schedule,
    required bool isOnlineAvailable,
    required bool isInPersonAvailable,
    required String clinicName,
    required String clinicAddress,
    required String currentStatus,
    required bool clinicChanged,
  }) async {
    final ref = _db.collection('nutritionist_profiles').doc(uid);
    final isActive = currentStatus == 'active';
    await ref.update({
      'availability.slotDuration': slotDuration,
      'availability.schedule': schedule,
      // Clinic details are patient-facing: once active they go through admin
      // review (below) instead of being written live.
      if (!isActive) 'availability.clinicName': clinicName,
      if (!isActive) 'availability.clinicAddress': clinicAddress,
      'availability.updatedAt': FieldValue.serverTimestamp(),
      'isOnlineAvailable': isOnlineAvailable,
      'isInPersonAvailable': isInPersonAvailable,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (isActive && clinicChanged) {
      // Nested map (not dotted keys); the admin approval deep-merges it into
      // `availability` so the schedule/blockedSlots are never overwritten.
      await PendingProfileEditService.apply(
        ref: ref,
        currentStatus: currentStatus,
        fields: {
          'availability': {'clinicName': clinicName, 'clinicAddress': clinicAddress},
        },
      );
    }
  }

  /// `blockedSlots`: `yyyy-MM-dd` -> slot labels the patient app must hide.
  static Future<void> saveBlockedSlots(String uid, Map<String, List<String>> blockedSlots) =>
      _db.collection('nutritionist_profiles').doc(uid).update({
        'availability.blockedSlots': blockedSlots,
        'availability.updatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
