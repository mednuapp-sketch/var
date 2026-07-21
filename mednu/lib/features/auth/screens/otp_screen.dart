import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import '../../../core/constants/app_colors.dart';
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
  bool _hasError = false;
  String _errorMessage = '';

  late AnimationController _entryCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _successCtrl;
  late AnimationController _shakeCtrl;
  late AnimationController _errorCardCtrl;

  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;
  late Animation<double> _successScale;
  late Animation<double> _shakeAnim;
  late Animation<double> _errorCardFade;
  late Animation<Offset> _errorCardSlide;

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
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _errorCardCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));

    _fadeIn = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideUp = Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _successScale =
        CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut);
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.linear));
    _errorCardFade =
        CurvedAnimation(parent: _errorCardCtrl, curve: Curves.easeOut);
    _errorCardSlide = Tween(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _errorCardCtrl, curve: Curves.easeOutCubic));
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
    _shakeCtrl.dispose();
    _errorCardCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 4) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    _errorCardCtrl.reverse();

    try {
      await ref.read(authProvider.notifier).verifyOtp(otp);
      if (!mounted) return;

      setState(() {
        _verified = true;
        _isLoading = false;
      });
      _successCtrl.forward();
      HapticFeedback.mediumImpact();

      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      if (widget.mode == 'resetMpin') {
        context.go(AppRoutes.createMpin, extra: {'mode': 'reset'});
      } else if (widget.mode == 'completeLogin') {
        context.go(AppRoutes.home);
      } else {
        final status = await ref.read(authProvider.notifier).checkUserStatus();
        if (!mounted) return;
        if (status == 'hasMpin') {
          context.go(AppRoutes.mpin,
              extra: {'phone': widget.phone, 'mode': 'login'});
        } else if (status == 'noMpin') {
          context.go(AppRoutes.createMpin, extra: {'mode': 'setup'});
        } else {
          context.go(AppRoutes.register, extra: {'phone': widget.phone});
        }
      }
    } catch (e) {
      if (!mounted) return;
      _attemptsLeft--;
      final msg = e.toString().replaceFirst('Exception: ', '');
      HapticFeedback.heavyImpact();

      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = _attemptsLeft > 0 ? msg : 'Too many attempts. Redirecting…';
      });

      _shakeCtrl.forward(from: 0);
      _errorCardCtrl.forward(from: 0);
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
      _hasError = false;
    });
    _errorCardCtrl.reverse();
    try {
      await ref.read(authProvider.notifier).sendOtp(widget.phone, isResend: true);
      if (!mounted) return;
      _startTimer();
      _otpController.clear();
      _showSuccess('OTP resent to ${widget.phone}');
    } catch (e) {
      if (!mounted) return;
      _showGenericError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showGenericError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.white, fontFamily: 'Poppins')),
      backgroundColor: const Color(0xFFB00020),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    ));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.white, fontFamily: 'Poppins')),
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

  Widget _buildErrorCard() {
    return FadeTransition(
      opacity: _errorCardFade,
      child: SlideTransition(
        position: _errorCardSlide,
        child: Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF416C), Color(0xFFD4145A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD4145A).withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon bubble
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.gpp_bad_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Incorrect OTP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                        )),
                    const SizedBox(height: 2),
                    Text(
                      _errorMessage,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 11.5,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ),
              ),
              // Attempts remaining badge
              if (_attemptsLeft > 0) ...[
                const SizedBox(width: 10),
                Column(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$_attemptsLeft',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'left',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 9,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = context.isDarkMode;

    final defaultTheme = PinTheme(
      width: 52, height: 60,
      textStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white : const Color(0xFF1A0A2E),
        fontFamily: 'Poppins',
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? AppColors.darkBorderMedium : const Color(0xFFE0D5F0),
            width: 1.5),
        color: isDark ? AppColors.darkCard : const Color(0xFFF8F4FF),
      ),
    );

    final focusedTheme = defaultTheme.copyWith(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7b2d6e), width: 2),
        color: isDark ? AppColors.darkCardElevated : Colors.white,
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
        border: Border.all(
          color: _hasError
              ? const Color(0xFFD4145A).withValues(alpha: 0.55)
              : const Color(0xFF7b2d6e).withValues(alpha: 0.5),
          width: 1.5,
        ),
        color: isDark
            ? (_hasError
                ? const Color(0xFFD4145A).withValues(alpha: 0.18)
                : const Color(0xFF7b2d6e).withValues(alpha: 0.18))
            : (_hasError
                ? const Color(0xFFFFF0F5)
                : const Color(0xFFF0E8FA)),
      ),
    );

    final errorPinTheme = defaultTheme.copyWith(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4145A), width: 2),
        color: isDark
            ? const Color(0xFFD4145A).withValues(alpha: 0.18)
            : const Color(0xFFFFF0F5),
      ),
    );

    final iconColor = _verified
        ? const Color(0xFF4CAF50)
        : _hasError
            ? const Color(0xFFFF416C)
            : const Color(0xFFF2A8D8);

    final keyboardBottom = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0520),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Background gradient ─────────────────────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0D0520),
                    Color(0xFF3B0F50),
                    Color(0xFF7b2d6e),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // ── Top-left orb ────────────────────────────────────────────────
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
                    const Color(0xFF9C27B0)
                        .withValues(alpha: 0.09 + _pulseCtrl.value * 0.07),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),

          // ── Bottom-right accent orb ─────────────────────────────────────
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Positioned(
              bottom: size.height * 0.18,
              right: -size.width * 0.25,
              child: Container(
                width: size.width * 0.65,
                height: size.width * 0.65,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFFE91E8C)
                        .withValues(alpha: 0.07 + _pulseCtrl.value * 0.05),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),

          // ── Decorative dots pattern ─────────────────────────────────────
          Positioned(
            top: size.height * 0.12,
            right: 24,
            child: Opacity(
              opacity: 0.15,
              child: Column(
                children: List.generate(
                  4,
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: List.generate(
                        4,
                        (col) => Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Container(
                            width: 3, height: 3,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeIn,
              child: Column(
                children: [
                  // ── Scrollable top content ──────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
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
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                              width: 1,
                            ),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ),

                  // ── Hero icon ───────────────────────────────────────────
                  SizedBox(height: size.height * 0.035),
                  AnimatedBuilder(
                    animation: Listenable.merge([_successCtrl, _pulseCtrl]),
                    builder: (_, __) => ScaleTransition(
                      scale: _verified
                          ? _successScale
                          : const AlwaysStoppedAnimation(1.0),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer pulse ring
                          Container(
                            width: 116, height: 116,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [
                                iconColor.withValues(
                                    alpha: 0.1 + _pulseCtrl.value * 0.09),
                                Colors.transparent,
                              ]),
                            ),
                          ),
                          // Inner icon container
                          Container(
                            width: 88, height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.08),
                              border: Border.all(
                                color: iconColor.withValues(alpha: 0.28),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: iconColor.withValues(
                                      alpha: 0.18 + _pulseCtrl.value * 0.1),
                                  blurRadius: 30,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              child: Icon(
                                _verified
                                    ? Icons.verified_rounded
                                    : _hasError
                                        ? Icons.gpp_bad_rounded
                                        : Icons.lock_open_rounded,
                                key: ValueKey(_verified
                                    ? 'v'
                                    : _hasError
                                        ? 'e'
                                        : 'n'),
                                color: iconColor,
                                size: 42,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: size.height * 0.022),

                  // ── Title ───────────────────────────────────────────────
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: _verified
                        ? const Text('Verified!',
                            key: ValueKey('v'),
                            style: TextStyle(
                              color: Color(0xFF4CAF50),
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Poppins',
                            ))
                        : _hasError
                            ? const Text('Try Again',
                                key: ValueKey('e'),
                                style: TextStyle(
                                  color: Color(0xFFFF7676),
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Poppins',
                                ))
                            : const Text('Enter OTP',
                                key: ValueKey('n'),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Poppins',
                                )),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Code sent to',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Phone pill
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🇮🇳 ', style: TextStyle(fontSize: 14)),
                        Text(
                          _maskedPhone(widget.phone),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),

                        ],
                      ),
                    ),
                  ),
                  // ── White card (pinned above keyboard) ─────────────────
                  AnimatedPadding(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.only(bottom: keyboardBottom),
                    child: SlideTransition(
                    position: _slideUp,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(
                          24,
                          24,
                          24,
                          20 + MediaQuery.of(context).padding.bottom),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(36)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7b2d6e).withValues(alpha: 0.18),
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
                              color: isDark
                                  ? AppColors.darkBorderMedium
                                  : const Color(0xFFE0E0E0),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 22),

                          // ── OTP input + shake ──────────────────────────
                          AnimatedBuilder(
                            animation: _shakeAnim,
                            builder: (_, child) {
                              final dx = math.sin(
                                      _shakeAnim.value * math.pi * 7) *
                                  9 *
                                  (1 - _shakeAnim.value);
                              return Transform.translate(
                                  offset: Offset(dx, 0), child: child);
                            },
                            child: Pinput(
                              controller: _otpController,
                              length: 4,
                              defaultPinTheme: defaultTheme,
                              focusedPinTheme: focusedTheme,
                              submittedPinTheme: submittedTheme,
                              errorPinTheme: errorPinTheme,
                              enabled: !_isLoading && !_verified,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              hapticFeedbackType:
                                  HapticFeedbackType.lightImpact,
                              onCompleted: (_) => _verifyOtp(),
                              onChanged: (_) {
                                if (_hasError) {
                                  setState(() => _hasError = false);
                                  _errorCardCtrl.reverse();
                                }
                              },
                            ),
                          ),

                          // ── Inline error card ──────────────────────────
                          if (_hasError) _buildErrorCard(),

                          const SizedBox(height: 18),

                          // ── Countdown timer row ────────────────────────
                          if (!_verified && _secondsLeft > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                      value: _secondsLeft / 60,
                                      strokeWidth: 2.2,
                                      backgroundColor: isDark
                                          ? AppColors.darkBorderMedium
                                          : const Color(0xFFEEE8F8),
                                      valueColor:
                                          const AlwaysStoppedAnimation(
                                              Color(0xFF7b2d6e)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'OTP expires in ${_secondsLeft}s',
                                    style: const TextStyle(
                                      color: Color(0xFF7b2d6e),
                                      fontSize: 12,
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // ── Verify button ──────────────────────────────
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: double.infinity,
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: _isLoading
                                  ? const LinearGradient(colors: [
                                      Color(0xFFCCCCCC),
                                      Color(0xFFCCCCCC)
                                    ])
                                  : _verified
                                      ? const LinearGradient(colors: [
                                          Color(0xFF388E3C),
                                          Color(0xFF4CAF50)
                                        ])
                                      : const LinearGradient(colors: [
                                          Color(0xFF9C27B0),
                                          Color(0xFF7b2d6e)
                                        ]),
                              boxShadow: [
                                BoxShadow(
                                  color: (_verified
                                          ? const Color(0xFF4CAF50)
                                          : const Color(0xFF7b2d6e))
                                      .withValues(alpha: 0.32),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: _isLoading || _verified
                                    ? null
                                    : _verifyOtp,
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 24, height: 24,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.5),
                                        )
                                      : _verified
                                          ? const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.check_rounded,
                                                    color: Colors.white,
                                                    size: 20),
                                                SizedBox(width: 8),
                                                Text('Verified',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
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

                          const SizedBox(height: 18),

                          // ── Resend timer ───────────────────────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Didn't receive the code? ",
                                style: TextStyle(
                                  color: context.appTextSecondary,
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
                                          color: context.appTextHint,
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
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
