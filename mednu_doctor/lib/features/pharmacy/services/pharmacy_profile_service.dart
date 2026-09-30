import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../shared_core/services/pending_profile_edit_service.dart';

/// Mirrors the structure of `LabProfileService`: a thin static-method
/// wrapper around `pharmacy_profiles/{uid}`. Never touches Firebase Auth or
/// any other role's profile collection.
class PharmacyProfileService {
  PharmacyProfileService._();

  static final _db = FirebaseFirestore.instance;

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static Future<bool> profileExists(String uid) async {
    final doc = await _db.collection('pharmacy_profiles').doc(uid).get();
    return doc.exists;
  }

  static Future<Map<String, dynamic>?> getProfile(String uid) async {
    final doc = await _db.collection('pharmacy_profiles').doc(uid).get();
    return doc.data();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(String uid) =>
      _db.collection('pharmacy_profiles').doc(uid).snapshots();

  static Future<void> createProfile({
    required String uid,
    required String name,
    required String licenseNumber,
    required String address,
    required String phone,
    String email = '',
    bool deliveryAvailable = true,
    List<String> categoriesOffered = const [],
    double? latitude,
    double? longitude,
    String city = '',
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 5));
    } catch (_) {}

    await _db.collection('pharmacy_profiles').doc(uid).set({
      'uid': uid,
      'name': name,
      'licenseNumber': licenseNumber,
      'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'city': city,
      'phone': phone,
      'email': email,
      'deliveryAvailable': deliveryAvailable,
      'categoriesOffered': categoriesOffered,
      'isVerified': false,
      'status': 'pending',
      'photoUrl': '',
      'rating': 0.0,
      'totalReviews': 0,
      'acceptingOrders': true,
      'createdAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
  }

  /// Once `currentStatus` is 'active', this doesn't touch the live fields
  /// at all — see [PendingProfileEditService]. Not for `acceptingOrders`;
  /// use [updateAcceptingOrders] for that (it must stay instant, not go
  /// through review — see its own doc comment).
  static Future<void> updateProfile(String uid, Map<String, dynamic> data, {required String currentStatus}) =>
      PendingProfileEditService.apply(
        ref: _db.collection('pharmacy_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: data,
      );

  static Future<void> updatePhotoUrl(String uid, String url, {required String currentStatus}) =>
      PendingProfileEditService.apply(
        ref: _db.collection('pharmacy_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: {'photoUrl': url},
      );

  /// Sets `acceptingOrders` — the pharmacy's own "Accepting New Orders"
  /// availability toggle. Deliberately bypasses [PendingProfileEditService]
  /// and writes directly: this is real-time operational state, not a
  /// profile detail, and firestore.rules exempts it from the pending-review
  /// requirement for exactly that reason (mirrors `LabProfileService.
  /// updateAcceptingBookings`).
  static Future<void> updateAcceptingOrders(String uid, bool value) =>
      _db.collection('pharmacy_profiles').doc(uid).update({'acceptingOrders': value});
}
