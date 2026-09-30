import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../shared_core/services/pending_profile_edit_service.dart';

/// Mirrors the structure of `DoctorAuthService` for the Lab & Diagnostics
/// role: a thin static-method wrapper around `lab_profiles/{uid}`. This
/// never touches the `doctors` collection or Firebase Auth itself — a Lab
/// partner is the same signed-in account as any other role, just with an
/// additional profile document.
class LabProfileService {
  LabProfileService._();

  static final _db = FirebaseFirestore.instance;

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static Future<bool> profileExists(String uid) async {
    final doc = await _db.collection('lab_profiles').doc(uid).get();
    return doc.exists;
  }

  static Future<Map<String, dynamic>?> getProfile(String uid) async {
    final doc = await _db.collection('lab_profiles').doc(uid).get();
    return doc.data();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(String uid) =>
      _db.collection('lab_profiles').doc(uid).snapshots();

  static Future<void> createProfile({
    required String uid,
    required String name,
    required String licenseNumber,
    required String address,
    required String phone,
    String email = '',
    List<String> servicesOffered = const [],
    double? latitude,
    double? longitude,
    String city = '',
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 5));
    } catch (_) {}

    await _db.collection('lab_profiles').doc(uid).set({
      'uid': uid,
      'name': name,
      'licenseNumber': licenseNumber,
      'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'city': city,
      'phone': phone,
      'email': email,
      'servicesOffered': servicesOffered,
      'isVerified': false,
      'status': 'pending',
      'photoUrl': '',
      'acceptingBookings': true,
      'rating': 0.0,
      'totalReviews': 0,
      'createdAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
  }

  /// Once `currentStatus` is 'active', this doesn't touch the live fields
  /// at all — see [PendingProfileEditService].
  static Future<void> updateProfile(String uid, Map<String, dynamic> data, {required String currentStatus}) =>
      PendingProfileEditService.apply(
        ref: _db.collection('lab_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: data,
      );

  /// Sets just `photoUrl` — used by the avatar upload/remove flow on
  /// [LabProfileScreen]. Once `currentStatus` is 'active', this doesn't
  /// touch the live `photoUrl` at all — see [PendingProfileEditService].
  static Future<void> updatePhotoUrl(String uid, String photoUrl, {required String currentStatus}) =>
      PendingProfileEditService.apply(
        ref: _db.collection('lab_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: {'photoUrl': photoUrl},
      );

  /// Sets `acceptingBookings` — the lab's own "Accepting New Bookings"
  /// availability toggle (order-fulfillment based, no location component).
  static Future<void> updateAcceptingBookings(String uid, bool value) =>
      _db.collection('lab_profiles').doc(uid).update({'acceptingBookings': value});
}
