import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import '../../../core/router/app_router.dart';
import '../providers/auth_provider.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final bool isExistingUser;
  final String mode;
  final Map<String, dynamic>? signupData;

  const OtpScreen({
    super.key,
    required this.phone,
    this.isExistingUser = false,
    this.mode = '',
    this.signupData,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen>
    with TickerProviderStateMixin {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  int _secondsLeft = 60;
  int _attemptsLeft = 3;
  Timer? _timer;

  late AnimationController _entryCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _successCtrl;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;
  late Animation<double> _successScale;

  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _startTimer();

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));

    _fadeIn = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideUp = Tween(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _successScale = CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut);
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).verifyOtp(otp);
      if (!mounted) return;

      // Success animation
      setState(() { _verified = true; _isLoading = false; });
      _successCtrl.forward();
      HapticFeedback.mediumImpact();

      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      if (widget.mode == 'resetMpin') {
        context.go(AppRoutes.createMpin, extra: {'mode': 'reset'});
      } else {
        final status = await ref.read(authProvider.notifier).checkUserStatus();
        if (!mounted) return;
        if (status == 'hasMpin' || status == 'noMpin') {
          context.go(AppRoutes.home);
        } else {
          context.go(AppRoutes.register, extra: {'phone': widget.phone});
        }
      }
    } catch (e) {
      if (!mounted) return;
      _attemptsLeft--;
      final msg = e.toString().replaceFirst('Exception: ', '');
      HapticFeedback.heavyImpact();
      _showError(_attemptsLeft > 0
          ? '$msg ($_attemptsLeft attempt${_attemptsLeft == 1 ? '' : 's'} left)'
          : msg);
      setState(() => _isLoading = false);
      _otpController.clear();
      if (_attemptsLeft <= 0) {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) context.go(AppRoutes.login);
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_secondsLeft > 0) return;
    setState(() { _isLoading = true; _attemptsLeft = 3; });
    try {
      await ref.read(authProvider.notifier).sendOtp(widget.phone, isResend: true);
      if (!mounted) return;
      _startTimer();
      _otpController.clear();
      _showSuccess('OTP resent to ${widget.phone}');
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontFamily: 'Poppins')),
      backgroundColor: const Color(0xFFB00020),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    ));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontFamily: 'Poppins')),
      backgroundColor: const Color(0xFF2E7D32),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    ));
  }

  String _maskedPhone(String phone) {
    if (phone.length >= 10) {
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      final last4 = digits.substring(digits.length - 4);
      return '•••• •••• $last4';
    }
    return phone;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final defaultTheme = PinTheme(
      width: 54, height: 62,
      textStyle: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A0A2E),
        fontFamily: 'Poppins',
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0D5F0), width: 1.5),
        color: const Color(0xFFF8F4FF),
      ),
    );

    final focusedTheme = defaultTheme.copyWith(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7b2d6e), width: 2),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7b2d6e).withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
    );

    final submittedTheme = defaultTheme.copyWith(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7b2d6e).withValues(alpha: 0.5), width: 1.5),
        color: const Color(0xFFF0E8FA),
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0D0520),
      body: Stack(
        children: [
          // ── Background ───────────────────────────────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0D0520), Color(0xFF3B0F50), Color(0xFF7b2d6e)],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // ── Pulse orb ────────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Positioned(
              top: -size.width * 0.3,
              left: -size.width * 0.1,
              child: Container(
                width: size.width * 0.8,
                height: size.width * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFFA36BAC)
                        .withValues(alpha: 0.08 + _pulseCtrl.value * 0.06),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeIn,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Back button ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ),

                  // ── Hero icon ───────────────────────────────────────────
                  SizedBox(height: size.height * 0.04),
                  AnimatedBuilder(
                    animation: _successCtrl,
                    builder: (_, __) {
                      return ScaleTransition(
                        scale: _verified
                            ? _successScale
                            : const AlwaysStoppedAnimation(1.0),
                        child: AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (_, child) => Container(
                            width: 90, height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.08),
                              boxShadow: [
                                BoxShadow(
                                  color: (_verified
                                          ? const Color(0xFF4CAF50)
                                          : const Color(0xFFF2A8D8))
                                      .withValues(
                                          alpha: 0.15 + _pulseCtrl.value * 0.12),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Icon(
                              _verified
                                  ? Icons.verified_rounded
                                  : Icons.lock_open_rounded,
                              color: _verified
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFF2A8D8),
                              size: 44,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  SizedBox(height: size.height * 0.03),

                  // ── Title ───────────────────────────────────────────────
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _verified
                        ? const Text('Verified!',
                            key: ValueKey('verified'),
                            style: TextStyle(
                              color: Color(0xFF4CAF50),
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Poppins',
                            ))
                        : const Text('Enter OTP',
                            key: ValueKey('enter'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Poppins',
                            )),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Code sent to',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 14,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🇮🇳 ', style: TextStyle(fontSize: 14)),
                        Text(
                          _maskedPhone(widget.phone),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── White card ──────────────────────────────────────────
                  SizedBox(height: size.height * 0.04),
                  SlideTransition(
                    position: _slideUp,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(
                          24, 28, 24, 24 + MediaQuery.of(context).padding.bottom),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7b2d6e).withValues(alpha: 0.15),
                            blurRadius: 40,
                            offset: const Offset(0, -8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Drag handle
                          Container(
                            width: 36, height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E0E0),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── OTP input ─────────────────────────────────
                          Pinput(
                            controller: _otpController,
                            length: 6,
                            defaultPinTheme: defaultTheme,
                            focusedPinTheme: focusedTheme,
                            submittedPinTheme: submittedTheme,
                            enabled: !_isLoading && !_verified,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            hapticFeedbackType: HapticFeedbackType.lightImpact,
                            onCompleted: (_) => _verifyOtp(),
                          ),

                          const SizedBox(height: 28),

                          // ── Verify button ─────────────────────────────
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: double.infinity,
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: !_isLoading && !_verified
                                  ? const LinearGradient(
                                      colors: [Color(0xFFA36BAC), Color(0xFF7b2d6e)],
                                    )
                                  : _verified
                                      ? const LinearGradient(
                                          colors: [Color(0xFF388E3C), Color(0xFF4CAF50)],
                                        )
                                      : const LinearGradient(
                                          colors: [Color(0xFFCCCCCC), Color(0xFFCCCCCC)],
                                        ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_verified
                                          ? const Color(0xFF4CAF50)
                                          : const Color(0xFF7b2d6e))
                                      .withValues(alpha: 0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: _isLoading || _verified ? null : _verifyOtp,
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 24, height: 24,
                                          child: CircularProgressIndicator(
                                              color: Colors.white, strokeWidth: 2.5),
                                        )
                                      : _verified
                                          ? const Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.check_rounded,
                                                    color: Colors.white, size: 20),
                                                SizedBox(width: 8),
                                                Text('Verified',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.w700,
                                                      fontFamily: 'Poppins',
                                                      color: Colors.white,
                                                    )),
                                              ],
                                            )
                                          : const Text('Verify OTP',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                fontFamily: 'Poppins',
                                                color: Colors.white,
                                              )),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ── Resend timer ──────────────────────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Didn't receive the code? ",
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                              GestureDetector(
                                onTap: _secondsLeft == 0 && !_isLoading
                                    ? _resendOtp
                                    : null,
                                child: _secondsLeft > 0
                                    ? Text(
                                        'Resend in ${_secondsLeft}s',
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 13,
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )
                                    : const Text(
                                        'Resend',
                                        style: TextStyle(
                                          color: Color(0xFF7b2d6e),
                                          fontSize: 13,
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w700,
                                          decoration: TextDecoration.underline,
                                          decorationColor: Color(0xFF7b2d6e),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
