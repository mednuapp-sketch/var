import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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

  /// `status`/`isVerified` are deliberately fixed here — see
  /// firestore.rules' `physiotherapist_profiles` create rule, which rejects
  /// a self-registration attempting to set either to their "verified" values.
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

    await _db.collection('physiotherapist_profiles').doc(uid).set({
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
  /// rejected by `firestore.rules` for a self-update.
  static Future<void> updateProfile(String uid, Map<String, dynamic> data) =>
      _db.collection('physiotherapist_profiles').doc(uid).set(data, SetOptions(merge: true));
}
