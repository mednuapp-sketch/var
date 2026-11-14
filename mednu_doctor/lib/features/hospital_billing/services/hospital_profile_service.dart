import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../shared_core/services/pending_profile_edit_service.dart';

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
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 5));
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
      // Typed by the applicant (no catalog picker) — admin links it to a
      // `hospitals` entry on approval.
      'requestedHospitalName': contactName,
      if (address != null && address.isNotEmpty) 'address': address,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
      // Picked on the registration form's map picker — copied onto the
      // shared `hospitals/{hospitalId}` catalog entry by
      // onHospitalProfileApproved once a Director approves this account, so
      // the patient app can show real distance without calling Google
      // Places for every hospital in the catalog.
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
  }

  /// `status`/`hospitalId`/`hospitalName` are rejected by firestore.rules for
  /// a self-update — only `contactName`/`phone`-shaped edits reach Firestore.
  ///
  /// Once [currentStatus] is 'active' the edit is diverted into
  /// `pendingChanges` for admin review (firestore.rules) instead of touching
  /// the live fields — see [PendingProfileEditService]. [pending] is the
  /// already-submitted snapshot, merged in so a later edit doesn't drop an
  /// earlier one that's still awaiting review.
  static Future<void> updateContactInfo(
    String uid, {
    required String contactName,
    required String phone,
    required String currentStatus,
    Map<String, dynamic> pending = const {},
  }) =>
      PendingProfileEditService.apply(
        ref: _db.collection('hospital_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: {
          if (currentStatus == 'active') ...pending,
          'contactName': contactName,
          'phone': phone,
        },
      );

  /// Used by [HospitalProfileScreen]'s avatar upload/remove flow. Once
  /// [currentStatus] is 'active' the new photo goes to review, not live —
  /// see [updateContactInfo].
  static Future<void> updatePhotoUrl(
    String uid,
    String photoUrl, {
    required String currentStatus,
    Map<String, dynamic> pending = const {},
  }) =>
      PendingProfileEditService.apply(
        ref: _db.collection('hospital_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: {
          if (currentStatus == 'active') ...pending,
          'photoUrl': photoUrl,
        },
      );
}
