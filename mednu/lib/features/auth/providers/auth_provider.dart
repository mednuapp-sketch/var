import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../referral/referral_service.dart';

// ── MPIN hash: SHA-256(uid:mpin:MEDNU_V1) ────────────────────────────────────
// Per-user salt (uid) prevents rainbow-table attacks.
// Never stored in plain text anywhere.
String _hashMpin(String mpin, String uid) {
  final bytes = utf8.encode('$uid:$mpin:MEDNU_V1');
  return sha256.convert(bytes).toString();
}

// ── Referral code generator ───────────────────────────────────────────────────
String generateReferralCode(String name, String uid) {
  final letters = name.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  final prefix = letters.length >= 3
      ? letters.substring(0, 3)
      : letters.padRight(3, 'M');
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  var hash = uid.hashCode.abs();
  final suffix = StringBuffer();
  for (int i = 0; i < 5; i++) {
    suffix.write(chars[hash % chars.length]);
    hash = (hash ~/ chars.length) + uid.codeUnitAt(i % uid.length);
  }
  return '$prefix$suffix';
}

// ── Auth State ────────────────────────────────────────────────────────────────
class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;
  final String? verificationId;
  final int loginAttempts;
  final DateTime? lockedUntil;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.verificationId,
    this.loginAttempts = 0,
    this.lockedUntil,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    String? verificationId,
    int? loginAttempts,
    DateTime? lockedUntil,
  }) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        verificationId: verificationId ?? this.verificationId,
        loginAttempts: loginAttempts ?? this.loginAttempts,
        lockedUntil: lockedUntil ?? this.lockedUntil,
      );
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<AuthState> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _sec = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // In-flight OTP state
  PhoneAuthCredential? _autoVerifiedCredential;
  int? _resendToken;

  // Lock policy
  static const _maxAttempts = 5;
  static const _lockMinutes = 15;

  AuthNotifier() : super(const AuthState()) {
    _auth.authStateChanges().listen((user) {
      state = state.copyWith(user: user);
    });
  }

  // ── Check if current authenticated user has a Firestore profile ──────────
  // Called AFTER OTP verification when request.auth is populated.
  // Returns true = existing user → show MPIN
  // 'new'     → no doc OR incomplete profile → go to registration
  // 'hasMpin' → complete profile + mpinHash → go to MPIN screen
  // 'noMpin'  → complete profile but no mpinHash → go to create MPIN
  Future<String> checkUserStatus() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 'new';
    try {
      final doc = await _db
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      if (!doc.exists) return 'new';
      final data = doc.data() ?? {};

      // Required fields from completeRegistration — if any missing, re-register
      final hasProfile =
          (data['name'] as String?)?.isNotEmpty == true &&
          (data['phone'] as String?)?.isNotEmpty == true &&
          (data['gender'] as String?)?.isNotEmpty == true &&
          (data['dob'] as String?)?.isNotEmpty == true;

      if (!hasProfile) return 'new';
      return (data['mpinHash'] as String?) != null ? 'hasMpin' : 'noMpin';
    } catch (_) {
      return 'new';
    }
  }

  // ── Send OTP ──────────────────────────────────────────────────────────────
  Future<void> sendOtp(String phone, {bool isResend = false}) async {
    _autoVerifiedCredential = null;
    state = state.copyWith(isLoading: true, error: null);

    final completer = Completer<void>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      forceResendingToken: isResend ? _resendToken : null,

      verificationCompleted: (PhoneAuthCredential credential) {
        _autoVerifiedCredential = credential;
        state = state.copyWith(isLoading: false);
        if (!completer.isCompleted) completer.complete();
      },

      verificationFailed: (FirebaseAuthException e) {
        debugPrint('🔴 OTP error → ${e.code}: ${e.message}');
        final msg = _friendlyError(e.code);
        state = state.copyWith(isLoading: false, error: msg);
        if (!completer.isCompleted) completer.completeError(Exception(msg));
      },

      codeSent: (String verificationId, int? resendToken) {
        _resendToken = resendToken;
        state = state.copyWith(
            isLoading: false, verificationId: verificationId);
        if (!completer.isCompleted) completer.complete();
      },

      codeAutoRetrievalTimeout: (String verificationId) {
        state = state.copyWith(verificationId: verificationId);
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  // ── Verify OTP → Firebase sign-in ────────────────────────────────────────
  Future<void> verifyOtp(String otp) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      PhoneAuthCredential credential;
      if (_autoVerifiedCredential != null) {
        credential = _autoVerifiedCredential!;
        _autoVerifiedCredential = null;
      } else {
        final vid = state.verificationId;
        if (vid == null) {
          throw Exception(
              'OTP session expired. Please request a new code.');
        }
        credential = PhoneAuthProvider.credential(
            verificationId: vid, smsCode: otp);
      }
      await _auth.signInWithCredential(credential);
      state = state.copyWith(isLoading: false);
    } on FirebaseAuthException catch (e) {
      debugPrint('🔴 Firebase Auth Error → ${e.code}: ${e.message}');
      final msg = _friendlyError(e.code);
      state = state.copyWith(isLoading: false, error: msg);
      throw Exception(msg);
    } catch (e) {
      debugPrint('🔴 OTP verify error → $e');
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(isLoading: false, error: msg);
      rethrow;
    }
  }

  // ── Complete Registration (new user, after OTP) ───────────────────────────
  // Creates 5 Firestore collections atomically. MPIN is set separately.
  Future<void> completeRegistration({
    required String name,
    required String phone,
    required String dob,
    required String gender,
    String? email,
    String? city,
    String? bloodGroup,
    String? referralCode,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Session expired. Please sign in again.');

      final uid = user.uid;
      final myReferralCode = generateReferralCode(name, uid);
      String? fcmToken;
      try { fcmToken = await FirebaseMessaging.instance.getToken(); } catch (_) {}

      final batch = _db.batch();
      final now = FieldValue.serverTimestamp();

      batch.set(_db.collection('users').doc(uid), {
        'uid':                uid,
        'name':               name,
        'phone':              phone,
        'email':              email ?? '',
        'photoUrl':           '',
        'isPhoneVerified':    true,
        'isProfileCompleted': true,
        'gender':             gender,
        'dob':                dob,
        if (city != null && city.isNotEmpty) 'city': city,
        if (bloodGroup != null && bloodGroup.isNotEmpty) 'bloodGroup': bloodGroup,
        'role':               'patient',
        'status':             'active',
        'createdAt':          now,
        'updatedAt':          now,
        'lastLogin':          now,
        'familyMembers':      [],
        'isPremium':          false,
        'walletBalance':      0.0,
        'referralCode':       myReferralCode,
        'referralPoints':     0,
        'rewardPoints':       0,
        'loginAttempts':      0,
        if (fcmToken != null) 'fcmToken': fcmToken,
        // mpinHash is written by createMpin() — kept separate so the batch
        // succeeds even if the user closes the app before setting MPIN.
      });

      batch.set(_db.collection('wallet').doc(uid), {
        'uid': uid, 'balance': 0.0, 'currency': 'INR',
        'createdAt': now, 'updatedAt': now,
      });

      batch.set(_db.collection('patient_profiles').doc(uid), {
        'uid': uid, 'phone': phone, 'name': name, 'dob': dob, 'gender': gender,
        'email': email ?? '',
        if (city != null) 'city': city,
        if (bloodGroup != null) 'bloodGroup': bloodGroup,
        'photoUrl': '', 'isActive': true, 'createdAt': now, 'updatedAt': now,
      });

      batch.set(_db.collection('notifications').doc(uid), {
        'uid': uid, 'unreadCount': 0, 'createdAt': now, 'updatedAt': now,
      });

      batch.set(_db.collection('reward_history').doc(uid), {
        'uid': uid, 'totalPoints': 0, 'createdAt': now, 'updatedAt': now,
      });

      await batch.commit();

      if (referralCode != null && referralCode.trim().isNotEmpty) {
        await ReferralService().applyReferralCode(
          referralCode: referralCode.trim(), newUserId: uid);
      }

      await _sec.write(key: 'last_phone', value: phone);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  // ── Create / Reset MPIN ───────────────────────────────────────────────────
  Future<void> createMpin(String mpin) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Not authenticated.');

      final mpinHash = _hashMpin(mpin, uid);
      await _db.collection('users').doc(uid).update({
        'mpinHash':      mpinHash,
        'mpinCreatedAt': FieldValue.serverTimestamp(),
        'updatedAt':     FieldValue.serverTimestamp(),
        'loginAttempts': 0,
        'lockedUntil':   FieldValue.delete(),
      });

      state = state.copyWith(isLoading: false, loginAttempts: 0, lockedUntil: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  // ── Verify MPIN ───────────────────────────────────────────────────────────
  // Returns true if correct, false otherwise.
  // Handles lockout logic and FCM refresh on success.
  Future<bool> verifyMpin(String mpin) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Session expired. Please sign in again.');

      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data() ?? {};

      // ── Lockout check ────────────────────────────────────────────────────
      final lockedUntilTs = data['lockedUntil'];
      if (lockedUntilTs != null) {
        final lockedUntil = (lockedUntilTs as Timestamp).toDate();
        if (DateTime.now().isBefore(lockedUntil)) {
          final remaining = lockedUntil.difference(DateTime.now()).inMinutes + 1;
          state = state.copyWith(
            isLoading: false,
            lockedUntil: lockedUntil,
            error: 'Account locked. Try again in $remaining minute(s).',
          );
          return false;
        }
        // Lock expired — clear it
        await _db.collection('users').doc(uid).update({
          'lockedUntil': FieldValue.delete(), 'loginAttempts': 0,
        });
      }

      final storedHash = data['mpinHash'] as String?;
      final attempts = (data['loginAttempts'] as int?) ?? 0;

      if (storedHash == null) {
        state = state.copyWith(
            isLoading: false, error: 'MPIN not set. Please create one.');
        return false;
      }

      final inputHash = _hashMpin(mpin, uid);

      if (inputHash == storedHash) {
        // ── Correct MPIN ──────────────────────────────────────────────────
        String? fcmToken;
        try { fcmToken = await FirebaseMessaging.instance.getToken(); } catch (_) {}
        await _db.collection('users').doc(uid).update({
          'loginAttempts': 0,
          'lockedUntil':   FieldValue.delete(),
          'lastLogin':     FieldValue.serverTimestamp(),
          if (fcmToken != null) 'fcmToken': fcmToken,
        });
        _auditLogin(uid, success: true);
        state = state.copyWith(
            isLoading: false, loginAttempts: 0, lockedUntil: null);
        return true;
      } else {
        // ── Wrong MPIN ────────────────────────────────────────────────────
        final newAttempts = attempts + 1;
        _auditLogin(uid, success: false);

        if (newAttempts >= _maxAttempts) {
          final lockUntil =
              DateTime.now().add(const Duration(minutes: _lockMinutes));
          await _db.collection('users').doc(uid).update({
            'loginAttempts': newAttempts,
            'lockedUntil':   Timestamp.fromDate(lockUntil),
          });
          state = state.copyWith(
            isLoading: false,
            loginAttempts: newAttempts,
            lockedUntil: lockUntil,
            error:
                'Too many attempts. Account locked for $_lockMinutes minutes.',
          );
        } else {
          await _db
              .collection('users')
              .doc(uid)
              .update({'loginAttempts': newAttempts});
          final remaining = _maxAttempts - newAttempts;
          state = state.copyWith(
            isLoading: false,
            loginAttempts: newAttempts,
            error: 'Incorrect MPIN. $remaining attempt(s) left.',
          );
        }
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    await _auth.signOut();
    await _sec.delete(key: 'mpin_set');
    state = const AuthState();
  }

  // ── Saved phone (for pre-filling phone entry after logout) ────────────────
  Future<String?> getLastPhone() => _sec.read(key: 'last_phone');

  // ── Update profile fields ─────────────────────────────────────────────────
  Future<void> updateProfile({
    required String name,
    required String email,
    required String dob,
    required String gender,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Session expired. Please sign in again.');
      await _db.collection('users').doc(uid).update({
        'name': name, 'email': email, 'dob': dob, 'gender': gender,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  // ── Update photo URL ──────────────────────────────────────────────────────
  Future<void> updatePhotoUrl(String photoUrl) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Session expired. Please sign in again.');
      await _db
          .collection('users')
          .doc(uid)
          .update({'photoUrl': photoUrl});
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // ── Family members ────────────────────────────────────────────────────────
  Future<void> addFamilyMember(Map<String, dynamic> member) async {
    try {
      final docRef = _db.collection('users').doc(_uid);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        final current = _parseFamilyList(snap.data()?['familyMembers']);
        current.add({
          ...member,
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
        });
        tx.set(docRef, {'familyMembers': current}, SetOptions(merge: true));
      });
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> removeFamilyMember(Map<String, dynamic> member) async {
    try {
      final docRef = _db.collection('users').doc(_uid);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        final current = _parseFamilyList(snap.data()?['familyMembers']);
        current.removeWhere((m) => member['id'] != null
            ? m['id'] == member['id']
            : m['name'] == member['name'] && m['relation'] == member['relation']);
        tx.set(docRef, {'familyMembers': current}, SetOptions(merge: true));
      });
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> updateFamilyMember(
    Map<String, dynamic> oldMember,
    Map<String, dynamic> newMember,
  ) async {
    try {
      final docRef = _db.collection('users').doc(_uid);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        final current = _parseFamilyList(snap.data()?['familyMembers']);
        final idx = current.indexWhere((m) => oldMember['id'] != null
            ? m['id'] == oldMember['id']
            : m['name'] == oldMember['name'] &&
                m['relation'] == oldMember['relation']);
        if (idx != -1) {
          current[idx] = {
            ...newMember,
            'id': oldMember['id'] ??
                DateTime.now().millisecondsSinceEpoch.toString(),
          };
        }
        tx.set(docRef, {'familyMembers': current}, SetOptions(merge: true));
      });
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String get _uid {
    final uid = _auth.currentUser?.uid ?? state.user?.uid;
    if (uid == null || uid.isEmpty) throw Exception('User not authenticated');
    return uid;
  }

  List<Map<String, dynamic>> _parseFamilyList(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  void _auditLogin(String uid, {required bool success}) {
    _db
        .collection('login_audit')
        .doc(uid)
        .collection('events')
        .add({
      'success':   success,
      'method':    'mpin',
      'timestamp': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 365))),
    }).ignore();
  }

  String _friendlyError(String code) => switch (code) {
        'invalid-phone-number' =>
          'Invalid phone number. Please check and try again.',
        'too-many-requests' =>
          'Too many attempts. Please wait a while and try again.',
        'invalid-verification-code' =>
          'Incorrect OTP. Please check and try again.',
        'session-expired'        => 'OTP expired. Please request a new one.',
        'quota-exceeded'         => 'SMS quota exceeded. Please try again later.',
        'network-request-failed' => 'No internet connection. Please check and try again.',
        'missing-client-identifier' ||
        'missing-app-credential'    =>
          'Verification service unavailable. Please try again.',
        _ => 'Error ($code). Please try again.',
      };
}

// ── Providers ─────────────────────────────────────────────────────────────────
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);

final currentUserProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final userDocProvider = StreamProvider.family<Map<String, dynamic>?, String>(
  (ref, uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((s) => s.data());
  },
);

final familyMembersProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, uid) {
  if (uid.isEmpty) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((s) {
    final data = s.data();
    if (data == null) return <Map<String, dynamic>>[];
    final raw = data['familyMembers'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  });
});
