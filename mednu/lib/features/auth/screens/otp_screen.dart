import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../providers/auth_provider.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final bool isExistingUser;
  final Map<String, dynamic>? signupData;

  const OtpScreen({
    super.key,
    required this.phone,
    this.isExistingUser = false,
    this.signupData,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _verified = false;
  int _secondsLeft = 60;
  int _attemptsLeft = 3;
  Timer? _timer;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) {
        t.cancel();
      } else if (mounted) {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6 || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      await ref.read(authProvider.notifier).verifyOtp(otp);
      if (!mounted) return;

      setState(() {
        _verified = true;
        _isLoading = false;
      });
      HapticFeedback.mediumImpact();

      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      final hasProfile =
          await ref.read(authProvider.notifier).hasCompleteProfile();
      if (!mounted) return;
      if (hasProfile) {
        context.go(AppRoutes.home);
      } else {
        context.go(AppRoutes.termsAccept, extra: {'phone': widget.phone});
      }
    } catch (e) {
      if (!mounted) return;
      _attemptsLeft--;
      final msg = e.toString().replaceFirst('Exception: ', '');
      HapticFeedback.heavyImpact();
      setState(() {
        _isLoading = false;
        _errorText = _attemptsLeft > 0
            ? '$msg ($_attemptsLeft attempt${_attemptsLeft == 1 ? '' : 's'} left)'
            : msg;
      });
      _otpController.clear();
      if (_attemptsLeft <= 0) {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) context.go(AppRoutes.login);
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_secondsLeft > 0) return;
    setState(() {
      _isLoading = true;
      _attemptsLeft = 3;
      _errorText = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .sendOtp(widget.phone, isResend: true);
      if (!mounted) return;
      _startTimer();
      _otpController.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('OTP resent successfully'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _errorText = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 6 boxes + 5 default 8dp separators must fit inside the 24dp page
    // padding: a fixed 52dp box overflowed every phone narrower than ~400dp.
    final pinWidth = ((MediaQuery.sizeOf(context).width - 48 - 40) / 6)
        .clamp(38.0, 52.0);
    final defaultPinTheme = PinTheme(
      width: pinWidth,
      height: 56,
      textStyle: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
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
              onPressed: () => context.safeBack())),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minHeight: constraints.maxHeight -
                      MediaQuery.of(context).padding.top),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    Container(
                        width: 80,
                        height: 80,
                        decoration: const BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            shape: BoxShape.circle),
                        child: Icon(
                            _verified ? Icons.check_rounded : Icons.sms_rounded,
                            color: Colors.white,
                            size: 40)),
                    const SizedBox(height: 24),
                    const Text('OTP Verification', style: AppTextStyles.h3),
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
                      enabled: !_isLoading && !_verified,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      hapticFeedbackType: HapticFeedbackType.lightImpact,
                      onChanged: (_) {
                        if (_errorText != null) {
                          setState(() => _errorText = null);
                        }
                      },
                      onCompleted: (_) => _verifyOtp(),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(_errorText!,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.error)),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading || _verified ? null : _verifyOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.primary.withValues(alpha: 0.7),
                          disabledForegroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          textStyle: AppTextStyles.button
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5))
                            : Text(_verified ? 'Verified' : 'Verify & Continue'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _secondsLeft > 0
                        ? Text('Resend OTP in $_secondsLeft seconds',
                            style: AppTextStyles.bodySmall)
                        : TextButton(
                            onPressed: _isLoading ? null : _resendOtp,
                            child: const Text('Resend OTP'),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
