import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../shared_core/services/pending_profile_edit_service.dart';

/// Mirrors `CaregiverProfileService` for the Counsellor role: a thin
/// static-method wrapper around `counsellor_profiles/{uid}`. Note the
/// collection name matches `AppRole.counsellor.firestoreValue +
/// '_profiles'` exactly — the router's `_AuthChangeNotifier` derives it
/// generically from that, so the name isn't a free choice.
class CounsellingProfileService {
  CounsellingProfileService._();

  static final _db = FirebaseFirestore.instance;

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static Future<bool> profileExists(String uid) async {
    final doc = await _db.collection('counsellor_profiles').doc(uid).get();
    return doc.exists;
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(String uid) =>
      _db.collection('counsellor_profiles').doc(uid).snapshots();

  /// `status`/`isVerified` are deliberately fixed here — see
  /// firestore.rules' `counsellor_profiles` create rule, which rejects a
  /// self-registration attempting to set either to their "verified" values.
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
      fcmToken = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 5));
    } catch (_) {}

    await _db.collection('counsellor_profiles').doc(uid).set({
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
      'totalSessions': 0,
      'experienceYears': experienceYears,
      'createdAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
  }

  /// `status`/`isVerified`/`rating`/`totalReviews`/`totalSessions` are
  /// rejected by `firestore.rules` for a self-update. Once `currentStatus`
  /// is 'active', this doesn't touch the live fields at all — see
  /// [PendingProfileEditService].
  static Future<void> updateProfile(String uid, Map<String, dynamic> data, {required String currentStatus}) =>
      PendingProfileEditService.apply(
        ref: _db.collection('counsellor_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: data,
      );

  /// Persists the Storage download URL for `counsellor_profiles/{uid}/profile.jpg`
  /// (or clears it when [photoUrl] is empty, after a removal).
  static Future<void> updatePhotoUrl(String uid, String photoUrl, {required String currentStatus}) =>
      PendingProfileEditService.apply(
        ref: _db.collection('counsellor_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: {'photoUrl': photoUrl},
      );
}
