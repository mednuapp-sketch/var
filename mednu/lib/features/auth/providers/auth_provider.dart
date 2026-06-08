import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../referral/referral_service.dart';

// Unique referral code: up to 3 letters from name + 5 chars derived from UID hash.
// UID is globally unique so the hash suffix guarantees no collisions.
// e.g. name="Akilesh", uid="abc123xyz" → "AKI2X9K4"
String generateReferralCode(String name, String uid) {
  final letters = name.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  final prefix = letters.length >= 3
      ? letters.substring(0, 3)
      : letters.padRight(3, 'M');

  // Derive 5 alphanumeric chars from UID's hashCode — deterministic per user
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  var hash = uid.hashCode.abs();
  final suffix = StringBuffer();
  for (int i = 0; i < 5; i++) {
    suffix.write(chars[hash % chars.length]);
    hash = (hash ~/ chars.length) + uid.codeUnitAt(i % uid.length);
  }

  return '$prefix$suffix';
}

// ── Auth State ──────────────────────────────────────────
class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;
  final String? verificationId;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.verificationId,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    String? verificationId,
  }) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        verificationId: verificationId ?? this.verificationId,
      );
}

// ── Auth Notifier ───────────────────────────────────────
class AuthNotifier extends StateNotifier<AuthState> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  AuthNotifier() : super(const AuthState()) {
    _auth.authStateChanges().listen((user) {
      state = state.copyWith(user: user);
    });
  }

  // ── Send OTP ──────────────────────────────────────────
  Future<void> sendOtp(String phoneNumber) async {
    state = state.copyWith(isLoading: true, error: null);
    final completer = Completer<void>();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
        if (!completer.isCompleted) completer.complete();
      },
      verificationFailed: (FirebaseAuthException e) {
        state = state.copyWith(isLoading: false, error: e.message);
        if (!completer.isCompleted) completer.completeError(Exception(e.message));
      },
      codeSent: (String verificationId, int? resendToken) {
        state = state.copyWith(isLoading: false, verificationId: verificationId);
        if (!completer.isCompleted) completer.complete();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        state = state.copyWith(verificationId: verificationId);
        if (!completer.isCompleted) completer.complete();
      },
    );
    await completer.future;
  }

  // ── Verify OTP ────────────────────────────────────────
  Future<bool> verifyOtp(String otp) async {
    final vid = state.verificationId;
    if (vid == null) {
      state = state.copyWith(isLoading: false, error: 'Session expired. Please request a new OTP.');
      throw Exception('Verification session expired. Please request a new OTP.');
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: vid,
        smsCode: otp,
      );
      final result = await _auth.signInWithCredential(credential);
      final isNew = result.additionalUserInfo?.isNewUser ?? false;
      if (!isNew) await _saveUid(result.user!.uid);
      state = state.copyWith(isLoading: false, user: result.user);
      return isNew;
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      throw Exception(e.message ?? 'OTP verification failed');
    }
  }

  // ── Google Sign-in ────────────────────────────────────
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw Exception('Google sign-in cancelled');
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await _auth.signInWithCredential(credential);
      final isNew = result.additionalUserInfo?.isNewUser ?? false;
      if (!isNew) await _saveUid(result.user!.uid);
      state = state.copyWith(isLoading: false, user: result.user);
      return isNew;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      throw Exception(e.toString());
    }
  }

  // ── Register ──────────────────────────────────────────
  Future<void> register({
    required String name,
    required String email,
    required String dob,
    required String gender,
    String? referralCode,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final uid = _auth.currentUser!.uid;
      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'email': email,
        'dob': dob,
        'gender': gender,
        'phone': _auth.currentUser!.phoneNumber ?? '',
        'photoUrl': _auth.currentUser!.photoURL ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'familyMembers': [],
        'isPremium': false,
        'walletBalance': 0.0,
        'referralCode': generateReferralCode(name, uid),
        'referralPoints': 0,
      });
      await _saveUid(uid);
      if (referralCode != null && referralCode.trim().isNotEmpty) {
        await ReferralService().applyReferralCode(
          referralCode: referralCode.trim(),
          newUserId: uid,
        );
      }
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      throw Exception(e.toString());
    }
  }

  // ── Update profile ────────────────────────────────────
  Future<void> updateProfile({
    required String name,
    required String email,
    required String dob,
    required String gender,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final uid = _auth.currentUser!.uid;
      await _db.collection('users').doc(uid).update({
        'name': name,
        'email': email,
        'dob': dob,
        'gender': gender,
      });
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  // ── Update photo URL ──────────────────────────────────
  Future<void> updatePhotoUrl(String photoUrl) async {
    try {
      final uid = _auth.currentUser!.uid;
      await _db.collection('users').doc(uid).update({'photoUrl': photoUrl});
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // ── Helpers ───────────────────────────────────────────
  String get _uid {
    final uid = _auth.currentUser?.uid ?? state.user?.uid;
    if (uid == null || uid.isEmpty) throw Exception('User not authenticated');
    return uid;
  }

  // ── Family members ────────────────────────────────────
  Future<void> addFamilyMember(Map<String, dynamic> member) async {
    try {
      final uid = _uid;
      final docRef = _db.collection('users').doc(uid);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        final current = List<Map<String, dynamic>>.from(
          ((snap.data()?['familyMembers'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map)),
        );
        current.add({
          ...member,
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
        });
        // set+merge creates the document if it doesn't exist yet
        tx.set(docRef, {'familyMembers': current}, SetOptions(merge: true));
      });
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> removeFamilyMember(Map<String, dynamic> member) async {
    try {
      final uid = _uid;
      final docRef = _db.collection('users').doc(uid);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        final current = List<Map<String, dynamic>>.from(
          ((snap.data()?['familyMembers'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map)),
        );
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
      final uid = _uid;
      final docRef = _db.collection('users').doc(uid);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        final current = List<Map<String, dynamic>>.from(
          ((snap.data()?['familyMembers'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map)),
        );
        final idx = current.indexWhere((m) => oldMember['id'] != null
            ? m['id'] == oldMember['id']
            : m['name'] == oldMember['name'] && m['relation'] == oldMember['relation']);
        if (idx != -1) {
          current[idx] = {
            ...newMember,
            'id': oldMember['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          };
        }
        tx.set(docRef, {'familyMembers': current}, SetOptions(merge: true));
      });
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // ── Sign out ──────────────────────────────────────────
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('uid');
    state = const AuthState();
  }

  Future<void> _saveUid(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uid', uid);
  }
}

// ── Providers ───────────────────────────────────────────
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
