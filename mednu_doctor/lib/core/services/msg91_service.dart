import 'package:cloud_functions/cloud_functions.dart';

class Msg91Service {
  static final _functions = FirebaseFunctions.instance;

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

  static Future<void> resendOtp(String phone) async {
    try {
      final result = await _functions
          .httpsCallable('msg91ResendOtp')
          .call({'phone': phone});
      if (result.data['success'] != true) {
        throw Exception('Failed to resend OTP. Please try again.');
      }
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Failed to resend OTP. Please try again.');
    }
  }

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
