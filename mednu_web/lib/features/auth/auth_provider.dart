import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    show FirebaseAuthPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Current user stream
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

// Stored outside Riverpod state — web session object that can't be copied
ConfirmationResult? _pendingConfirmation;

// Auth notifier state
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

  Future<void> sendOtp(String phone) async {
    state = state.copyWith(loading: true, phone: phone);
    _pendingConfirmation = null; // clear any stale session

    try {
      final auth = FirebaseAuth.instance;
      final verifier = RecaptchaVerifier(
        auth: FirebaseAuthPlatform.instanceFor(
          app: auth.app,
          pluginConstants: auth.pluginConstants,
        ),
        onError: (FirebaseAuthException e) {
          state = state.copyWith(
            loading: false,
            error: 'reCAPTCHA error [${e.code}]: ${e.message}',
          );
        },
        onExpired: () {
          state = state.copyWith(
            loading: false,
            error: 'reCAPTCHA expired. Please try again.',
          );
        },
      );

      _pendingConfirmation = await FirebaseAuth.instance.signInWithPhoneNumber(
        '+91$phone',
        verifier,
      );

      state = state.copyWith(step: AuthStep.otp, loading: false);
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(loading: false, error: '[${e.code}] ${e.message}');
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> verifyOtp(String otp) async {
    if (_pendingConfirmation == null) {
      state = state.copyWith(error: 'Session lost. Please request a new OTP.');
      return;
    }
    state = state.copyWith(loading: true);
    try {
      final cred = await _pendingConfirmation!.confirm(otp);
      final uid = cred.user?.uid;

      // Check whether this UID already has a complete profile in Firestore.
      // Mobile app sets isProfileCompleted=true; web registration does too.
      // If either flag is missing or doc doesn't exist → send to registration.
      bool hasProfile = false;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          final data = doc.data() ?? {};
          final name = (data['name'] as String?) ?? '';
          // Accept docs that have isProfileCompleted OR have a non-empty name
          // (covers older mobile-registered users before the flag was added).
          hasProfile = (data['isProfileCompleted'] == true) ||
              (name.isNotEmpty &&
                  ((data['phone'] as String?) ?? (data['phoneNumber'] as String?) ?? '').isNotEmpty);
        }
      }

      state = state.copyWith(
        step: hasProfile ? AuthStep.done : AuthStep.register,
        loading: false,
      );
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        loading: false,
        error: '[${e.code}] ${e.message ?? 'Verification failed'}',
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Creates the user's Firestore profile after OTP verification for a
  /// brand-new number, then advances to the dashboard.
  Future<void> completeRegistration({
    required String name,
    String? email,
    String? dob,
    String? gender,
    String? city,
    String? bloodGroup,
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
        // 'phone' matches the mobile app's field name & format
        'phone': '+91${state.phone}',
        // 'phoneNumber' kept for web-side backwards compat
        'phoneNumber': state.phone,
        'email': email ?? '',
        if (dob != null) 'dob': dob,
        if (gender != null) 'gender': gender,
        if (city != null) 'city': city,
        if (bloodGroup != null) 'bloodGroup': bloodGroup,
        'photoUrl': '',
        'isPhoneVerified': true,
        'isProfileCompleted': true,
        'role': 'patient',
        'status': 'active',
        'familyMembers': [],
        'walletBalance': 0.0,
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
    _pendingConfirmation = null;
    state = AuthState(phone: state.phone);
  }

  Future<void> signOut() async {
    _pendingConfirmation = null;
    await FirebaseAuth.instance.signOut();
    state = const AuthState();
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
