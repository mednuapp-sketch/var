import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Mirrors `LabProfileService` for the Ambulance role: a thin static-method
/// wrapper around `ambulance_profiles/{uid}`. This never touches the
/// `doctors` collection or Firebase Auth itself — an ambulance partner is
/// the same signed-in account as any other role, just with an additional
/// profile document. That document's existence is also what
/// `firestore.rules`' `isAmbulancePartner()` checks to decide who may read
/// the shared, unclaimed dispatch queue.
class AmbulanceProfileService {
  AmbulanceProfileService._();

  static final _db = FirebaseFirestore.instance;

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static Future<bool> profileExists(String uid) async {
    final doc = await _db.collection('ambulance_profiles').doc(uid).get();
    return doc.exists;
  }

  static Future<Map<String, dynamic>?> getProfile(String uid) async {
    final doc = await _db.collection('ambulance_profiles').doc(uid).get();
    return doc.data();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(String uid) =>
      _db.collection('ambulance_profiles').doc(uid).snapshots();

  static Future<void> createProfile({
    required String uid,
    required String plateNumber,
    required String vehicleType,
    required String driverName,
    required String driverPhone,
    required String driverLicense,
    List<String> equipment = const [],
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    await _db.collection('ambulance_profiles').doc(uid).set({
      'uid': uid,
      'plateNumber': plateNumber,
      'vehicleType': vehicleType,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'driverLicense': driverLicense,
      'equipment': equipment,
      'documentsVerified': false,
      'status': 'pending',
      'isVerified': false,
      'rating': 0.0,
      'totalReviews': 0,
      'totalTrips': 0,
      'createdAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
  }

  /// `status`/`isVerified`/`rating`/`totalReviews`/`totalTrips` are rejected
  /// by `firestore.rules` for a self-update — a partner can't self-approve or
  /// inflate its own stats.
  static Future<void> updateProfile(String uid, Map<String, dynamic> data) =>
      _db.collection('ambulance_profiles').doc(uid).set(data, SetOptions(merge: true));
}
