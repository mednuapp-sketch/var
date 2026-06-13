import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../referral/referral_service.dart';

// Unique referral code: up to 3 letters from name + 5 chars derived from UID hash.
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

// ── Auth State ──────────────────────────────────────────────────────────────
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

// ── Auth Notifier ───────────────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<AuthState> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  AuthNotifier() : super(const AuthState()) {
    _auth.authStateChanges().listen((user) {
      state = state.copyWith(user: user);
    });
  }

  // ── Google Sign-In (primary auth method) ────────────────────────────────
  // Returns true if new user (no Firestore doc exists) → route to signup.
  // Returns false if existing user → route to home.
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        state = state.copyWith(isLoading: false);
        throw Exception('Sign-in was cancelled');
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await _auth.signInWithCredential(credential);
      final uid = result.user!.uid;

      // Check Firestore — authoritative source for whether this user has completed
      // registration. Firebase's isNewUser flag is per-device and unreliable.
      final doc = await _db.collection('users').doc(uid).get();
      final isNew = !doc.exists;

      if (!isNew) {
        await _db.collection('users').doc(uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
        await _saveUid(uid);
      }

      state = state.copyWith(isLoading: false, user: result.user);
      return isNew;
    } on FirebaseAuthException catch (e) {
      final msg = _friendlyError(e.code);
      state = state.copyWith(isLoading: false, error: msg);
      throw Exception(msg);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(isLoading: false, error: msg);
      rethrow;
    }
  }

  // ── Send OTP ─────────────────────────────────────────────────────────────
  // Used during new-user registration to verify phone ownership.
  Future<void> sendOtp(String phoneNumber) async {
    state = state.copyWith(isLoading: true, error: null);
    final completer = Completer<void>();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android auto-detection — completer resolves; user skips manual entry.
        state = state.copyWith(isLoading: false);
        if (!completer.isCompleted) completer.complete();
      },
      verificationFailed: (FirebaseAuthException e) {
        final msg = _friendlyError(e.code);
        state = state.copyWith(isLoading: false, error: msg);
        if (!completer.isCompleted) completer.completeError(Exception(msg));
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

  // ── Verify OTP + Register (atomic) ────────────────────────────────────────
  // Links the verified phone to the existing Google account, then creates the
  // Firestore user document. Called once, at the end of the signup flow.
  Future<void> verifyPhoneAndRegister({
    required String otp,
    required String name,
    required String phone,
    required String dob,
    required String gender,
    String? referralCode,
  }) async {
    final vid = state.verificationId;
    if (vid == null) {
      state = state.copyWith(
        isLoading: false,
        error: 'Session expired. Please request a new OTP.',
      );
      throw Exception('Session expired. Please request a new OTP.');
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      final phoneCredential = PhoneAuthProvider.credential(
        verificationId: vid,
        smsCode: otp,
      );

      // Link the verified phone number to the existing Google Firebase account.
      try {
        await _auth.currentUser!.linkWithCredential(phoneCredential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'credential-already-in-use') {
          state = state.copyWith(
            isLoading: false,
            error: 'This phone number is already linked to another MedNU account.',
          );
          throw Exception(
              'This phone number is already linked to another MedNU account.');
        }
        // provider-already-linked → phone already on this account → safe to proceed.
        if (e.code != 'provider-already-linked') {
          final msg = _friendlyError(e.code);
          state = state.copyWith(isLoading: false, error: msg);
          throw Exception(msg);
        }
      }

      // Create Firestore user document (idempotent via set, not update).
      final user = _auth.currentUser!;
      final uid = user.uid;
      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'googleEmail': user.email ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'phoneNumber': phone,
        'phone': phone,
        'phoneVerified': true,
        'gender': gender,
        'dob': dob,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
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
      if (state.isLoading) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
      rethrow;
    }
  }

  // ── Update profile ────────────────────────────────────────────────────────
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
      final uid = _auth.currentUser!.uid;
      await _db.collection('users').doc(uid).update({'photoUrl': photoUrl});
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  // ── Family members ────────────────────────────────────────────────────────
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
            : m['name'] == member['name'] &&
                m['relation'] == member['relation']);
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

  // ── Sign out ─────────────────────────────────────────────────────────────
  // Only clears local session. Never deletes Firestore data.
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('uid');
    state = const AuthState();
  }

  // ── Private helpers ───────────────────────────────────────────────────────
  String get _uid {
    final uid = _auth.currentUser?.uid ?? state.user?.uid;
    if (uid == null || uid.isEmpty) throw Exception('User not authenticated');
    return uid;
  }

  String _friendlyError(String code) => switch (code) {
        'sign_in_canceled' => 'Sign-in was cancelled',
        'network-request-failed' =>
          'No internet connection. Please try again.',
        'too-many-requests' =>
          'Too many attempts. Please wait and try again.',
        'invalid-phone-number' =>
          'Invalid phone number. Please check and try again.',
        'invalid-verification-code' =>
          'Incorrect OTP. Please check and try again.',
        'session-expired' => 'OTP expired. Please request a new one.',
        'quota-exceeded' => 'SMS quota exceeded. Please try again later.',
        'credential-already-in-use' =>
          'This phone is already linked to another account.',
        'operation-not-allowed' =>
          'This sign-in method is not enabled.',
        _ => 'Something went wrong. Please try again.',
      };

  Future<void> _saveUid(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uid', uid);
  }
}

// ── Providers ──────────────────────────────────────────────────────────────
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
