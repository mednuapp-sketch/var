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
/// app books from / pays into, and what `hospital_bill_payments.hospitalId`
/// is filtered by). `createProfile` takes that catalog entry from the
/// registration form's own hospital picker (`PartnerRoleRegisterScreen`),
/// falling back to a best-effort phone-number match only if the caller
/// didn't pass one. Either way a Director must still confirm (or pick the
/// right one, if nothing came through) before Approve runs — see
/// `hospital_profiles`' update rule in firestore.rules, which blocks the
/// owner from ever setting `hospitalId`/`hospitalName`/`status` themselves.
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
  ///
  /// [hospitalId]/[hospitalName] come from the registration form's own
  /// hospital picker (the applicant selects their hospital directly from the
  /// catalog) — the phone-number auto-match is only a fallback for the rare
  /// case that selection didn't happen, so a Director reviewing this
  /// application in mednu-admin still has *something* to confirm rather than
  /// an empty "no match found" state.
  static Future<void> createProfile({
    required String uid,
    required String contactName,
    required String phone,
    String? hospitalId,
    String? hospitalName,
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    var linkedId = hospitalId;
    var linkedName = hospitalName;
    if (linkedId == null) {
      final match = await _findCatalogMatch(phone);
      linkedId = match?.id;
      linkedName = match?.data()['name'] as String?;
    }

    await _db.collection('hospital_profiles').doc(uid).set({
      'uid': uid,
      'contactName': contactName,
      'phone': phone,
      'hospitalId': linkedId,
      'hospitalName': linkedName,
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
