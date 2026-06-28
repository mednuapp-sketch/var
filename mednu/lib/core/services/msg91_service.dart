import 'package:cloud_functions/cloud_functions.dart';

class Msg91Service {
  static final _functions = FirebaseFunctions.instance;

  /// Sends a 6-digit OTP to [phone] via MSG91.
  /// [phone] must be in E.164 format: +919876543210
  static Future<void> sendOtp(String phone) async {
    try {
      final result = await _functions
          .httpsCallable('msg91SendOtp')
          .call({'phone': phone});
      if (result.data['success'] != true) {
        throw Exception('Failed to send OTP. Please try again.');
      }
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Failed to send OTP. Please try again.');
    }
  }

  /// Verifies 4-digit [otp] for [phone] via MSG91 and returns a Firebase custom token.
  /// Call FirebaseAuth.signInWithCustomToken() with the returned token.
  static Future<String> verifyOtp(String phone, String otp) async {
    try {
      final result = await _functions
          .httpsCallable('msg91VerifyOtp')
          .call({'phone': phone, 'otp': otp});
      final token = result.data['customToken'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('Verification failed. Please try again.');
      }
      return token;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Incorrect OTP. Please check and try again.');
    }
  }
}
