import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import '../services/doctor_auth_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';

class DoctorOtpScreen extends StatefulWidget {
  final String phone;
  final bool isLogin;

  const DoctorOtpScreen({
    super.key,
    required this.phone,
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
  bool _timerActive = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timerActive = false;
    _otpController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timerActive = true;
    _resendSeconds = 60;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_timerActive) return false;
      setState(() => _resendSeconds--);
      return _resendSeconds > 0 && _timerActive;
    });
  }

  Future<void> _resendOTP() async {
    setState(() {
      _isResending = true;
      _error = null;
      _otpController.clear();
    });
    try {
      await DoctorAuthService.resendOTP(widget.phone);
      if (!mounted) return;
      _timerActive = false;
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('OTP resent successfully'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _verifyOTP(String pin) async {
    if (pin.length != 4) return;
    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      final user = await DoctorAuthService.verifyOTP(widget.phone, pin);
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isVerifying = false;
          _error = 'Authentication failed. Please try again.';
        });
        return;
      }

      if (!mounted) return;

      if (widget.isLogin) {
        final exists = await DoctorAuthService.profileExists(user.uid);
        if (!mounted) return;
        if (exists) {
          final profile = await DoctorAuthService.getProfile(user.uid);
          if (!mounted) return;
          final status = profile?['status'] as String?;
          if (status == 'active') {
            context.go(AppRoutes.dashboard);
          } else {
            context.go(AppRoutes.verificationPending);
          }
        } else {
          context.go(AppRoutes.register);
        }
      } else {
        context.go(AppRoutes.register);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isVerifying = false;
        _error = msg;
      });
    }
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.sms_rounded, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 24),
              Text('OTP Verification', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Text(
                'Enter the 4-digit OTP sent to\n${widget.phone}',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 36),
              Pinput(
                controller: _otpController,
                length: 4,
                defaultPinTheme: defaultPinTheme,
                focusedPinTheme: defaultPinTheme.copyWith(
                  decoration: defaultPinTheme.decoration!.copyWith(
                    border: Border.all(color: AppColors.primary, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                autofocus: true,
                keyboardType: TextInputType.number,
                onCompleted: (pin) => _verifyOTP(pin),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 28),
              GradientButton(
                label: 'Verify & Continue',
                isLoading: _isVerifying,
                width: double.infinity,
                height: 54,
                onTap: _isVerifying
                    ? () {}
                    : () => _verifyOTP(_otpController.text),
              ),
              const SizedBox(height: 20),
              _isResending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _resendSeconds > 0
                      ? Text(
                          'Resend OTP in $_resendSeconds seconds',
                          style: AppTextStyles.bodySmall,
                        )
                      : TextButton(
                          onPressed: _resendOTP,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                          ),
                          child: const Text(
                            'Resend OTP',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
            ],
          ),
        ),
      ),
    );
  }
}
