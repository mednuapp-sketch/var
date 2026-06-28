import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

enum AuthStep { phone, otp, register, done }

class AuthState {
  final AuthStep step;
  final String phone;
  final bool loading;
  final String? error;

  const AuthState({
    this.step = AuthStep.phone,
    this.phone = '',
    this.loading = false,
    this.error,
  });

  AuthState copyWith({
    AuthStep? step,
    String? phone,
    bool? loading,
    String? error,
  }) =>
      AuthState(
        step: step ?? this.step,
        phone: phone ?? this.phone,
        loading: loading ?? this.loading,
        error: error,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  final _functions = FirebaseFunctions.instance;

  Future<void> sendOtp(String phone) async {
    state = state.copyWith(loading: true, phone: phone, error: null);
    try {
      await _functions.httpsCallable('msg91SendOtp').call({
        'phone': '+91$phone',
      });
      state = state.copyWith(step: AuthStep.otp, loading: false);
    } on FirebaseFunctionsException catch (e) {
      state = state.copyWith(loading: false, error: e.message ?? 'Failed to send OTP.');
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> verifyOtp(String otp) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final result = await _functions.httpsCallable('msg91VerifyOtp').call({
        'phone': '+91${state.phone}',
        'otp': otp,
      });

      final customToken = result.data['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) {
        throw Exception('Verification failed. Please try again.');
      }

      final cred = await FirebaseAuth.instance.signInWithCustomToken(customToken);
      final uid = cred.user?.uid;

      bool hasProfile = false;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          final data = doc.data() ?? {};
          final name = (data['name'] as String?) ?? '';
          hasProfile = (data['isProfileCompleted'] == true) ||
              (name.isNotEmpty &&
                  ((data['phone'] as String?) ?? (data['phoneNumber'] as String?) ?? '').isNotEmpty);
        }
      }

      state = state.copyWith(
        step: hasProfile ? AuthStep.done : AuthStep.register,
        loading: false,
      );
    } on FirebaseFunctionsException catch (e) {
      state = state.copyWith(loading: false, error: e.message ?? 'Incorrect OTP. Please try again.');
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> completeRegistration({
    required String name,
    String? email,
    String? dob,
    String? gender,
    String? city,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      state = state.copyWith(error: 'Session lost. Please verify your number again.');
      return;
    }
    state = state.copyWith(loading: true);
    try {
      final db = FirebaseFirestore.instance;
      final now = FieldValue.serverTimestamp();
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'phone': '+91${state.phone}',
        'phoneNumber': state.phone,
        'email': email ?? '',
        if (dob != null) 'dob': dob,
        if (gender != null) 'gender': gender,
        if (city != null) 'city': city,
        'photoUrl': '',
        'isPhoneVerified': true,
        'isProfileCompleted': true,
        'role': 'patient',
        'status': 'active',
        'familyMembers': [],
        'walletBalance': 0.0,
        'isPremium': false,
        'referralPoints': 0,
        'rewardPoints': 0,
        'loginAttempts': 0,
        'createdAt': now,
        'updatedAt': now,
      });
      await db.collection('wallet').doc(uid).set({
        'uid': uid,
        'balance': 0.0,
        'currency': 'INR',
        'createdAt': now,
        'updatedAt': now,
      });
      state = state.copyWith(step: AuthStep.done, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void goBack() {
    state = AuthState(phone: state.phone);
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    state = const AuthState();
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
