import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart'
    show FirebaseAuthPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Current user stream
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Real-time profile doc for whoever is currently signed in. Null while
/// signed out. This is the single source of truth the router uses to decide
/// between /register and /dashboard — see [hasCompletedProfile].
final authProfileProvider =
    StreamProvider<DocumentSnapshot<Map<String, dynamic>>?>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
});

/// Accept docs that have isProfileCompleted OR have a non-empty name + phone
/// (covers older mobile-registered users before the flag was added).
bool hasCompletedProfile(DocumentSnapshot<Map<String, dynamic>>? doc) {
  if (doc == null || !doc.exists) return false;
  final data = doc.data() ?? {};
  final name = (data['name'] as String?) ?? '';
  return (data['isProfileCompleted'] == true) ||
      (name.isNotEmpty &&
          ((data['phone'] as String?) ?? (data['phoneNumber'] as String?) ?? '')
              .isNotEmpty);
}

/// Maps a FirebaseAuthException's machine-readable `code` to copy a patient
/// can actually act on, instead of showing Firebase's own developer-facing
/// `e.message` (e.g. "[invalid-verification-code] The SMS verification code
/// used to create the phone auth credential is invalid...") directly in the
/// UI. Mirrors the mapping mednu_doctor's OTP screen already uses.
String _friendlyAuthError(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-verification-code':
    case 'invalid-code':
      return 'Incorrect OTP. Please check and try again.';
    case 'session-expired':
    case 'code-expired':
      return 'OTP expired. Please request a new one.';
    case 'too-many-requests':
      return 'Too many attempts. Please wait a moment and try again.';
    case 'invalid-phone-number':
      return 'Please enter a valid 10-digit mobile number.';
    case 'quota-exceeded':
      return 'SMS limit reached. Please try again in a while.';
    case 'network-request-failed':
      return 'Network error. Please check your connection and try again.';
    default:
      return 'Something went wrong. Please try again.';
  }
}

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
            error: _friendlyAuthError(e),
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
      state = state.copyWith(loading: false, error: _friendlyAuthError(e));
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Something went wrong. Please try again.');
    }
  }

  Future<void> verifyOtp(String otp) async {
    if (_pendingConfirmation == null) {
      state = state.copyWith(error: 'Session lost. Please request a new OTP.');
      return;
    }
    state = state.copyWith(loading: true);
    try {
      await _pendingConfirmation!.confirm(otp);

      // Where this lands (/register vs /dashboard) is decided by the router
      // in real time off authProfileProvider's live Firestore listener, not
      // here — a one-shot check here would race the authStateChanges event
      // that confirm() just triggered and could beat this read to the punch.
      state = state.copyWith(step: AuthStep.done, loading: false);
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(loading: false, error: _friendlyAuthError(e));
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Something went wrong. Please try again.');
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
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = currentUser?.uid;
    if (uid == null) {
      state = state.copyWith(error: 'Session lost. Please verify your number again.');
      return;
    }
    // Read the verified phone straight from the Auth user rather than the
    // notifier's local `state.phone`, which is empty if this uid reached
    // /register via a page reload instead of the in-tab OTP flow.
    final verifiedPhone = currentUser?.phoneNumber ?? '+91${state.phone}';
    final localPhone = verifiedPhone.startsWith('+91')
        ? verifiedPhone.substring(3)
        : verifiedPhone;
    state = state.copyWith(loading: true);
    try {
      final db = FirebaseFirestore.instance;
      final now = FieldValue.serverTimestamp();
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        // 'phone' matches the mobile app's field name & format
        'phone': verifiedPhone,
        // 'phoneNumber' kept for web-side backwards compat
        'phoneNumber': localPhone,
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
      state = state.copyWith(
          loading: false,
          error: 'Could not save your profile. Please check your connection and try again.');
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
