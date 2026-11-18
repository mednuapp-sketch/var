import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Razorpay publishable key (safe to ship — the secret lives only in Cloud
/// Functions config, which is what actually verifies every payment).
///
/// Single source of truth so swapping the test key for a live key before
/// launch only has to happen in one place. Overridable via
/// --dart-define=RAZORPAY_KEY_ID=rzp_live_... so the live-key swap doesn't
/// require a code change — the test key stays the default since, unlike a
/// real secret, a Razorpay key *id* is meant to be public.
const kRazorpayKeyId = String.fromEnvironment(
  'RAZORPAY_KEY_ID',
  defaultValue: 'rzp_test_T1Z9EVjv8paYQ2',
);

/// Single switch for whether booking a doctor/service/cart actually has to go
/// through a real Razorpay charge before the booking is created.
///
/// While `false`, `PaymentScreen` skips Razorpay entirely and confirms the
/// booking straight away (same booking doc shape, same collection, same
/// `status`/`assignedTo` fields a paid booking gets — see
/// `_skipPaymentForTesting` in payment_screen.dart) so it shows up in
/// MedNU Doctor/Service exactly like a paid one, just tagged
/// `paymentStatus: 'not_required'` with no `paymentId`, so the settlement
/// engine (which only ever acts on a real `paymentId`) never touches it.
///
/// Flip this to `true` (and set `kRazorpayKeyId` to a live key) once the app
/// is ready to actually collect money.
const bool kRequirePayment = false;

/// Runtime accessor for the real-payments switch. Source of truth is the
/// Firestore doc `app_config/payments` = { requirePayment: bool, updatedAt,
/// updatedBy } (Director-only write from the admin panel), so go-live needs no
/// app release. [kRequirePayment] is only the fallback while the doc has not
/// loaded yet / is missing / unreadable (rules require sign-in to read it).
///
/// Use [PaymentConfig.requirePayment] (synchronous, last known value) in
/// handlers and [requirePaymentProvider] in build methods.
class PaymentConfig {
  PaymentConfig._();

  static bool? _remote;
  static final StreamController<bool> _controller =
      StreamController<bool>.broadcast();
  static StreamSubscription<User?>? _authSub;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  /// Remote value when known, else the compile-time fallback.
  static bool get requirePayment => _remote ?? kRequirePayment;

  /// Emits the effective value each time it changes.
  static Stream<bool> get changes => _controller.stream;

  /// Idempotent; call once at app start.
  static void start() {
    if (_authSub != null) return;
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _docSub?.cancel();
      _docSub = null;
      if (user == null) return; // keep the last known value
      _docSub = FirebaseFirestore.instance
          .collection('app_config')
          .doc('payments')
          .snapshots()
          .listen((snap) {
        final data = snap.data();
        final v = data == null ? null : data['requirePayment'];
        _set(v is bool ? v : null);
      }, onError: (_) {
        // Unreadable: keep the cached value (or the compile-time fallback).
      });
    });
  }

  static void _set(bool? value) {
    final before = requirePayment;
    _remote = value;
    if (before != requirePayment && !_controller.isClosed) {
      _controller.add(requirePayment);
    }
  }
}

/// Reactive view of [PaymentConfig.requirePayment] for widgets.
final requirePaymentProvider = StreamProvider<bool>((ref) async* {
  yield PaymentConfig.requirePayment;
  yield* PaymentConfig.changes;
});

/// Flat OP registration fee charged when a patient books an in-person OP
/// appointment directly with a MedNU-registered hospital (as opposed to an
/// individual doctor) — see hospital_appointment_booking_screen.dart. A
/// single easily-adjustable constant since there's no per-hospital fee
/// config yet.
const int kHospitalOpFee = 99;
