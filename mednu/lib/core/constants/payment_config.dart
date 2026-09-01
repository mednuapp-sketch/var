/// Razorpay publishable key (safe to ship — the secret lives only in Cloud
/// Functions config, which is what actually verifies every payment).
///
/// Single source of truth so swapping the test key for a live key before
/// launch only has to happen in one place.
const kRazorpayKeyId = 'rzp_test_T1Z9EVjv8paYQ2';

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
