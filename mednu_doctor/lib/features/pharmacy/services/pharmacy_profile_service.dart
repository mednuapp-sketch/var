import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    await _db.collection('pharmacy_profiles').doc(uid).set({
      'uid': uid,
      'name': name,
      'licenseNumber': licenseNumber,
      'address': address,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'phone': phone,
      'email': email,
      'deliveryAvailable': deliveryAvailable,
      'categoriesOffered': categoriesOffered,
      'isVerified': false,
      'status': 'pending',
      'photoUrl': '',
      'rating': 0.0,
      'totalReviews': 0,
      'createdAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
  }

  static Future<void> updateProfile(String uid, Map<String, dynamic> data) =>
      _db.collection('pharmacy_profiles').doc(uid).update(data);
}
