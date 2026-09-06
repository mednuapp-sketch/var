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

/// Flat OP registration fee charged when a patient books an in-person OP
/// appointment directly with a MedNU-registered hospital (as opposed to an
/// individual doctor) — see hospital_appointment_booking_screen.dart. A
/// single easily-adjustable constant since there's no per-hospital fee
/// config yet.
const int kHospitalOpFee = 99;
