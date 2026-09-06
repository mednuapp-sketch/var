import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class DoctorAuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;
  static String? get currentUid => _auth.currentUser?.uid;

  // ── Phone Auth ─────────────────────────────────────────

  static Future<void> sendOTP({
    required String phone,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    void Function(PhoneAuthCredential)? onAutoVerified,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (credential) async {
        try {
          await _auth.signInWithCredential(credential);
          onAutoVerified?.call(credential);
        } catch (_) {}
      },
      verificationFailed: (e) =>
          onError(e.message ?? 'OTP sending failed. Try again.'),
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
      timeout: const Duration(seconds: 60),
    );
  }

  static Future<UserCredential> verifyOTP({
    required String verificationId,
    required String otp,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otp,
    );
    return _auth.signInWithCredential(credential);
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
    String email = '',
    String qualifications = '',
    String experience = '',
    String fee = '',
    String gender = 'Male',
    String registrationNumber = '',
    String clinicName = '',
    String clinicAddress = '',
    List<String> languages = const ['English'],
    double? clinicLat,
    double? clinicLng,
    String clinicCity = '',
    Map<String, String> documentUrls = const {},
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    await _db.collection('doctors').doc(uid).set({
      'uid': uid,
      'name': name,
      'phone': phone,
      'email': email,
      'specialty': specialty,
      'qualifications': qualifications,
      'experience': experience,
      'fee': fee,
      'gender': gender,
      'registrationNumber': registrationNumber,
      'clinicName': clinicName,
      'clinicAddress': clinicAddress,
      'languages': languages,
      if (clinicLat != null && clinicLng != null) 'clinicLat': clinicLat,
      if (clinicLat != null && clinicLng != null) 'clinicLng': clinicLng,
      'clinicCity': clinicCity,
      'isOnline': false,
      'isVerified': false,
      'status': 'pending',
      'rating': 0.0,
      'totalReviews': 0,
      'totalConsultations': 0,
      'documents': documentUrls,
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
