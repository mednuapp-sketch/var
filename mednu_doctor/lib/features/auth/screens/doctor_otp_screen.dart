import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import '../services/doctor_auth_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';

class DoctorOtpScreen extends StatefulWidget {
  final String phone;
  final String verificationId;
  final bool isLogin;

  const DoctorOtpScreen({
    super.key,
    required this.phone,
    required this.verificationId,
    this.isLogin = true,
  });

  @override
  State<DoctorOtpScreen> createState() => _DoctorOtpScreenState();
}

class _DoctorOtpScreenState extends State<DoctorOtpScreen> {
  final _otpController = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;
  int _resendSeconds = 60;
  String? _error;
  late String _verificationId;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _startTimer();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendSeconds--);
      return _resendSeconds > 0;
    });
  }

  Future<void> _resendOTP() async {
    setState(() {
      _isResending = true;
      _error = null;
      _otpController.clear();
    });
    await DoctorAuthService.sendOTP(
      phone: widget.phone,
      onCodeSent: (newVerificationId) {
        if (!mounted) return;
        setState(() {
          _verificationId = newVerificationId;
          _resendSeconds = 60;
          _isResending = false;
        });
        _startTimer();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('OTP resent successfully'),
          behavior: SnackBarBehavior.floating,
        ));
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isResending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 52,
      height: 56,
      textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary),
      decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => context.pop())),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.sms_rounded,
                      color: Colors.white, size: 40)),
              const SizedBox(height: 24),
              Text('OTP Verification', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Text('Enter the 6-digit OTP sent to\n${widget.phone}',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium),
              const SizedBox(height: 32),
              Pinput(
                controller: _otpController,
                length: 6,
                defaultPinTheme: defaultPinTheme,
                focusedPinTheme: defaultPinTheme.copyWith(
                    decoration: defaultPinTheme.decoration!.copyWith(
                        border: Border.all(
                            color: AppColors.primary, width: 2))),
                onCompleted: (pin) => _verifyOTP(pin),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        color: Colors.red,
                        fontFamily: 'Poppins',
                        fontSize: 13)),
              ],
              const SizedBox(height: 24),
              _isVerifying
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            _verifyOTP(_otpController.text),
                        child: const Text('Verify & Continue'),
                      ),
                    ),
              const SizedBox(height: 16),
              _isResending
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _resendSeconds > 0
                      ? Text('Resend OTP in $_resendSeconds seconds',
                          style: AppTextStyles.bodySmall)
                      : TextButton(
                          onPressed: _resendOTP,
                          child: const Text('Resend OTP'),
                        ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _verifyOTP(String pin) async {
    if (pin.length != 6) return;
    setState(() {
      _isVerifying = true;
      _error = null;
    });

    // Step 1: Verify OTP with Firebase Auth
    String uid;
    try {
      final credential = await DoctorAuthService.verifyOTP(
        verificationId: _verificationId,
        otp: pin,
      );
      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        if (!mounted) return;
        setState(() {
          _isVerifying = false;
          _error = 'Authentication failed. Please try again.';
        });
        return;
      }
      uid = firebaseUser.uid;
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      String errorText;
      if (msg.contains('session-expired') || msg.contains('expired')) {
        errorText = 'OTP expired. Please tap Resend OTP.';
      } else if (msg.contains('invalid-verification-code') || msg.contains('invalid-code')) {
        errorText = 'Incorrect OTP. Please check and try again.';
      } else if (msg.contains('too-many-requests')) {
        errorText = 'Too many attempts. Please wait a moment and try again.';
      } else {
        errorText = 'Verification failed. Please try again.';
      }
      setState(() {
        _isVerifying = false;
        _error = errorText;
      });
      return;
    }

    if (!mounted) return;

    // Step 2: Check profile existence
    if (widget.isLogin) {
      bool exists = false;
      try {
        exists = await DoctorAuthService.profileExists(uid);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isVerifying = false;
          _error = 'Could not connect to server. Please check your connection and try again.';
        });
        return;
      }
      if (!mounted) return;
      if (exists) {
        final profile = await DoctorAuthService.getProfile(uid);
        if (!mounted) return;
        final status = profile?['status'] as String?;
        if (status == 'active') {
          context.go(AppRoutes.dashboard);
        } else {
          // Pending admin approval or suspended — show status screen
          context.go(AppRoutes.verificationPending);
        }
      } else {
        // No profile found — guide to registration
        context.go(AppRoutes.register);
      }
    } else {
      context.go(AppRoutes.register);
    }
  }
}
