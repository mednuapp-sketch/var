import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Mirrors `PhysioProfileService` for the Hospital role: a thin static-method
/// wrapper around `hospital_profiles/{uid}`. Collection name matches
/// `AppRole.hospital.firestoreValue + '_profiles'` exactly — the router's
/// `_AuthChangeNotifier` derives it generically from that, so the name isn't
/// a free choice.
///
/// Unlike every other partner role, a hospital login isn't itself the
/// operational entity — it links back to an existing, separately admin-
/// curated `hospitals/{hospitalId}` catalog entry (the same one the patient
/// app books from / pays into). `createProfile` best-effort auto-matches
/// that catalog entry by the applicant's OTP-verified phone number so admin
/// only has to confirm rather than hunt for it, but a Director must always
/// confirm (or pick the right one, if no match was found) before Approve
/// runs — see `hospital_profiles`' update rule in firestore.rules, which
/// blocks the owner from ever setting `hospitalId`/`hospitalName`/`status`
/// themselves.
class HospitalProfileService {
  HospitalProfileService._();

  static final _db = FirebaseFirestore.instance;

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(String uid) =>
      _db.collection('hospital_profiles').doc(uid).snapshots();

  /// Looks for exactly one `hospitals` catalog entry whose `phone` matches
  /// [phone]. Returns null on zero or multiple matches — ambiguity is left
  /// for admin to resolve manually rather than guessed at here.
  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findCatalogMatch(
    String phone,
  ) async {
    if (phone.isEmpty) return null;
    final snap = await _db
        .collection('hospitals')
        .where('phone', isEqualTo: phone)
        .limit(2)
        .get();
    return snap.docs.length == 1 ? snap.docs.first : null;
  }

  /// `status` is always written as `'pending'` here — see firestore.rules'
  /// `hospital_profiles` create rule, which rejects any other value.
  static Future<void> createProfile({
    required String uid,
    required String contactName,
    required String phone,
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    final match = await _findCatalogMatch(phone);

    await _db.collection('hospital_profiles').doc(uid).set({
      'uid': uid,
      'contactName': contactName,
      'phone': phone,
      'hospitalId': match?.id,
      'hospitalName': match?.data()['name'] as String?,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
  }

  /// `status`/`hospitalId`/`hospitalName` are rejected by firestore.rules for
  /// a self-update — only `contactName`/`phone`-shaped edits reach Firestore.
  static Future<void> updateContactInfo(
    String uid, {
    required String contactName,
    required String phone,
  }) =>
      _db.collection('hospital_profiles').doc(uid).set({
        'contactName': contactName,
        'phone': phone,
      }, SetOptions(merge: true));
}
