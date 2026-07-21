import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../core/services/msg91_service.dart';

class DoctorAuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;
  static String? get currentUid => _auth.currentUser?.uid;

  // ── MSG91 OTP ──────────────────────────────────────────

  static Future<void> sendOTP(String phone) =>
      Msg91Service.sendOtp(phone);

  static Future<void> resendOTP(String phone) =>
      Msg91Service.resendOtp(phone);

  static Future<User?> verifyOTP(String phone, String otp) async {
    final customToken = await Msg91Service.verifyOtp(phone, otp);
    final credential = await _auth.signInWithCustomToken(customToken);
    return credential.user;
  }

  // ── Doctor Profile ─────────────────────────────────────

  static Future<bool> profileExists(String uid) async {
    final doc = await _db.collection('doctors').doc(uid).get();
    return doc.exists;
  }

  static Future<void> saveProfile({
    required String uid,
    required String name,
    required String phone,
    required String specialty,
    String type = 'doctor',
    String email = '',
    String qualifications = '',
    String experience = '',
    String fee = '',
    String gender = 'Male',
    String registrationNumber = '',
    Map<String, String> documentUrls = const {},
    String signatureUrl = '',
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    // The profile_photo document doubles as the initial avatar.
    // Later edits via updatePhotoUrl upload to doctors/{uid}/profile.jpg.
    final profilePhotoUrl = documentUrls['profile_photo'] ?? '';

    await _db.collection('doctors').doc(uid).set({
      'uid': uid,
      'name': name,
      'phone': phone,
      'email': email,
      'type': type,
      'specialty': specialty,
      'qualifications': qualifications,
      'experience': experience,
      'fee': fee,
      'gender': gender,
      'registrationNumber': registrationNumber,
      'photoUrl': profilePhotoUrl,
      'isOnline': false,
      'isVerified': false,
      'status': 'pending',
      'rating': 0.0,
      'totalReviews': 0,
      'totalConsultations': 0,
      'documents': documentUrls,
      'signatureUrl': signatureUrl,
      'declarationAccepted': true,
      'createdAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
  }

  static Future<Map<String, dynamic>?> getProfile(String uid) async {
    final doc = await _db.collection('doctors').doc(uid).get();
    return doc.data();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(
          String uid) =>
      _db.collection('doctors').doc(uid).snapshots();

  static Future<void> setOnlineStatus(String uid, bool isOnline) =>
      _db.collection('doctors').doc(uid).update({'isOnline': isOnline});

  static Future<void> updateLocation(
    String uid,
    double lat,
    double lng,
    String geohash,
  ) =>
      _db.collection('doctors').doc(uid).update({
        'location': GeoPoint(lat, lng),
        'geohash': geohash,
        'geohash5': geohash.length >= 5 ? geohash.substring(0, 5) : geohash,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });

  static Future<void> updatePhotoUrl(String uid, String photoUrl) =>
      _db.collection('doctors').doc(uid).update({'photoUrl': photoUrl});

  static Future<void> signOut() => _auth.signOut();
}
