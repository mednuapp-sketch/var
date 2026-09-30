import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../shared_core/services/pending_profile_edit_service.dart';

/// Mirrors `CaregiverProfileService` for the Physiotherapist role: a thin
/// static-method wrapper around `physiotherapist_profiles/{uid}`. Note the
/// collection name matches `AppRole.physiotherapist.firestoreValue +
/// '_profiles'` exactly — the router's `_AuthChangeNotifier` derives it
/// generically from that, so the name isn't a free choice.
class PhysioProfileService {
  PhysioProfileService._();

  static final _db = FirebaseFirestore.instance;

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static Future<bool> profileExists(String uid) async {
    final doc = await _db.collection('physiotherapist_profiles').doc(uid).get();
    return doc.exists;
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(String uid) =>
      _db.collection('physiotherapist_profiles').doc(uid).snapshots();

  /// The single number older display spots (dashboard stat, patient list
  /// card) still read as `hourlyRate` — the cheapest of whichever modes are
  /// actually offered (a 0 rate means "not offered", so it's excluded
  /// rather than winning the min() trivially). 0 if nothing is offered yet.
  static num _startingFrom(num onlineRate, num clinicRate, num homeRate) {
    final offered = [onlineRate, clinicRate, homeRate].where((r) => r > 0);
    return offered.isEmpty ? 0 : offered.reduce((a, b) => a < b ? a : b);
  }

  /// `status`/`isVerified` are deliberately fixed here — see
  /// firestore.rules' `physiotherapist_profiles` create rule, which rejects
  /// a self-registration attempting to set either to their "verified" values.
  static Future<void> createProfile({
    required String uid,
    required String name,
    String photoUrl = '',
    List<String> certifications = const [],
    List<String> specialties = const [],
    num onlineRate = 0,
    num clinicRate = 0,
    num homeRate = 0,
    int experienceYears = 0,
    String city = '',
    double? clinicLat,
    double? clinicLng,
    List<String> languages = const [],
    String phone = '',
    String email = '',
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 5));
    } catch (_) {}

    await _db.collection('physiotherapist_profiles').doc(uid).set({
      'uid': uid,
      'name': name,
      'phone': phone,
      'email': email,
      'photoUrl': photoUrl,
      'certifications': certifications,
      'specialties': specialties,
      'onlineRate': onlineRate,
      'clinicRate': clinicRate,
      'homeRate': homeRate,
      'hourlyRate': _startingFrom(onlineRate, clinicRate, homeRate),
      'city': city,
      if (clinicLat != null && clinicLng != null) 'clinicLat': clinicLat,
      if (clinicLat != null && clinicLng != null) 'clinicLng': clinicLng,
      'languages': languages,
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
        ref: _db.collection('physiotherapist_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: data,
      );

  static Future<void> updatePhotoUrl(String uid, String photoUrl, {required String currentStatus}) =>
      PendingProfileEditService.apply(
        ref: _db.collection('physiotherapist_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: {'photoUrl': photoUrl},
      );
}
