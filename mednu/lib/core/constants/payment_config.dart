/// Razorpay publishable key (safe to ship — the secret lives only in Cloud
/// Functions config, which is what actually verifies every payment).
///
/// Single source of truth so swapping the test key for a live key before
/// launch only has to happen in one place.
const kRazorpayKeyId = 'rzp_test_T1Z9EVjv8paYQ2';
