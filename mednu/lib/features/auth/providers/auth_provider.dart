import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/services/msg91_service.dart';
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
  final int loginAttempts;
  final DateTime? lockedUntil;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.loginAttempts = 0,
    this.lockedUntil,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    int? loginAttempts,
    DateTime? lockedUntil,
  }) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
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

  // Phone stored between sendOtp() and verifyOtp() calls
  String? _pendingPhone;

  // Lock policy
  static const _maxAttempts = 5;
  static const _lockMinutes = 15;

  // Local MPIN cache keys (for MPIN-first login on same device)
  static const _localHashKey  = 'local_mpin_hash';
  static const _localUidKey   = 'local_mpin_uid';
  static const _localPhoneKey = 'local_mpin_phone';

  late final StreamSubscription<User?> _authSub;

  AuthNotifier() : super(const AuthState()) {
    _authSub = _auth.authStateChanges().listen((user) {
      state = state.copyWith(user: user);
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
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

  // ── Send OTP via MSG91 ────────────────────────────────────────────────────
  Future<void> sendOtp(String phone, {bool isResend = false}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      _pendingPhone = phone;
      await Msg91Service.sendOtp(phone);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      debugPrint('🔴 MSG91 sendOtp error → $e');
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(isLoading: false, error: msg);
      throw Exception(msg);
    }
  }

  // ── Verify OTP via MSG91 → Firebase custom token sign-in ─────────────────
  Future<void> verifyOtp(String otp) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final phone = _pendingPhone;
      if (phone == null) {
        throw Exception('OTP session expired. Please request a new code.');
      }
      final customToken = await Msg91Service.verifyOtp(phone, otp);
      await _auth.signInWithCustomToken(customToken);
      _pendingPhone = null;
      state = state.copyWith(isLoading: false);
    } catch (e) {
      debugPrint('🔴 MSG91 verifyOtp error → $e');
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(isLoading: false, error: msg);
      throw Exception(msg);
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
    String? referralCode,
    String? photoUrl,
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

      final photoUrlValue = photoUrl ?? '';

      batch.set(_db.collection('users').doc(uid), {
        'uid':                uid,
        'name':               name,
        'phone':              phone,
        'email':              email ?? '',
        'photoUrl':           photoUrlValue,
        'isPhoneVerified':    true,
        'isProfileCompleted': true,
        'gender':             gender,
        'dob':                dob,
        if (city != null && city.isNotEmpty) 'city': city,
        'role':               'patient',
        'status':             'active',
        'createdAt':          now,
        'updatedAt':          now,
        'lastLogin':          now,
        'familyMembers':      [],
        'isPremium':          false,
        'walletBalance':      0.0,
        'mednuMoneyBalance':  0.0,
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
        'photoUrl': photoUrlValue, 'isActive': true, 'createdAt': now, 'updatedAt': now,
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

      // Write to phone_index so any device can detect this user has MPIN.
      // Fire-and-forget: this is a secondary optimisation index — failure here
      // must not block MPIN creation (the hash is already stored on users/{uid}).
      final phone = _auth.currentUser?.phoneNumber ?? '';
      if (phone.isNotEmpty) {
        _db.collection('phone_index').doc(phone).set({
          'hasMpin':   true,
          'uid':       uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).ignore();
      }

      // Also cache locally for same-device instant verification (no network)
      await _sec.write(key: _localHashKey,  value: mpinHash);
      await _sec.write(key: _localUidKey,   value: uid);
      await _sec.write(key: _localPhoneKey, value: phone);

      state = state.copyWith(isLoading: false, loginAttempts: 0, lockedUntil: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  // ── Local MPIN helpers (MPIN-first login on same device) ─────────────────

  /// Returns the phone number that has a locally cached MPIN on this device.
  Future<String?> getLocalMpinPhone() => _sec.read(key: _localPhoneKey);

  /// Checks Firestore phone_index — works on ANY device, no auth required.
  Future<bool> checkPhoneHasMpin(String phone) async {
    try {
      final doc = await _db.collection('phone_index').doc(phone).get();
      return doc.exists && (doc.data()?['hasMpin'] == true);
    } catch (_) {
      return false;
    }
  }

  /// True if this device has a locally cached MPIN for [phone] (same-device fast path).
  Future<bool> hasLocalMpin(String phone) async {
    try {
      final storedPhone = await _sec.read(key: _localPhoneKey);
      final storedHash  = await _sec.read(key: _localHashKey);
      return storedPhone == phone && storedHash != null;
    } catch (_) {
      return false;
    }
  }

  /// Verifies MPIN without requiring an active Firebase Auth session.
  Future<bool> verifyMpinLocal(String mpin, String phone) async {
    try {
      final storedPhone = await _sec.read(key: _localPhoneKey);
      final storedHash  = await _sec.read(key: _localHashKey);
      final storedUid   = await _sec.read(key: _localUidKey);
      if (storedPhone != phone || storedHash == null || storedUid == null) {
        return false;
      }
      return _hashMpin(mpin, storedUid) == storedHash;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if there is an active Firebase Auth session.
  Future<bool> signInSilentlyIfPossible() async {
    return _auth.currentUser != null;
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
    await Future.wait([
      _sec.delete(key: 'mpin_set'),
      _sec.delete(key: _localHashKey),
      _sec.delete(key: _localUidKey),
      _sec.delete(key: _localPhoneKey),
    ]);
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
      // Write to both collections atomically so every reader sees the same URL.
      final batch = _db.batch();
      batch.update(_db.collection('users').doc(uid),            {'photoUrl': photoUrl});
      batch.update(_db.collection('patient_profiles').doc(uid), {'photoUrl': photoUrl});
      await batch.commit();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // ── Family members ────────────────────────────────────────────────────────
  Future<void> addFamilyMember(Map<String, dynamic> member) async {
    try {
      final docRef = _db.collection('users').doc(_uid);
      final snap = await docRef.get();
      final current = _parseFamilyList(snap.data()?['familyMembers']);
      if (current.length >= 4) {
        throw Exception('You can only add up to 4 family members.');
      }
      current.add({
        ...member,
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      await docRef.update({'familyMembers': current});
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> removeFamilyMember(Map<String, dynamic> member) async {
    try {
      final docRef = _db.collection('users').doc(_uid);
      final snap = await docRef.get();
      final current = _parseFamilyList(snap.data()?['familyMembers']);
      current.removeWhere((m) => member['id'] != null
          ? m['id'] == member['id']
          : m['name'] == member['name'] && m['relation'] == member['relation']);
      await docRef.update({'familyMembers': current});
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
      final snap = await docRef.get();
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
      await docRef.update({'familyMembers': current});
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
