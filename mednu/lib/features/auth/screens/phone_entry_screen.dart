import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../providers/auth_provider.dart';

class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen>
    with TickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _phoneFocus = FocusNode();
  bool _isLoading = false;
  bool _focused = false;
  double _btnScale = 1;

  late AnimationController _entryCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _floatCtrl;
  late AnimationController _shimmerCtrl;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _floatCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat(reverse: true);
    _shimmerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();

    _fadeIn = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideUp = Tween(begin: const Offset(0, 0.14), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _phoneFocus.addListener(() {
      if (mounted) setState(() => _focused = _phoneFocus.hasFocus);
    });

    _prefillPhone();
  }

  Future<void> _prefillPhone() async {
    final last = await ref.read(authProvider.notifier).getLastPhone();
    if (last != null && mounted) {
      final display = last.startsWith('+91') ? last.substring(3) : last;
      _phoneController.text = display;
    }
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _floatCtrl.dispose();
    _shimmerCtrl.dispose();
    _phoneController.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  String get _fullPhone => '+91${_phoneController.text.trim()}';
  bool get _isValid => _phoneController.text.trim().length == 10;

  Future<void> _continue() async {
    if (!_isValid) {
      HapticFeedback.heavyImpact();
      _showError('Please enter a valid 10-digit mobile number.');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);
    try {
      // Check Firestore phone_index — works on any device, no auth needed
      final hasMpin =
          await ref.read(authProvider.notifier).checkPhoneHasMpin(_fullPhone);
      if (!mounted) return;

      if (hasMpin) {
        // Existing user with MPIN — skip OTP, go directly to MPIN screen
        context.push(AppRoutes.mpin,
            extra: {'phone': _fullPhone, 'mode': 'login'});
      } else {
        // New user — standard OTP flow
        await ref.read(authProvider.notifier).sendOtp(_fullPhone);
        if (!mounted) return;
        context.push(AppRoutes.otp, extra: {
          'phone': _fullPhone,
          'isExistingUser': false,
        });
      }
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isSmall = size.height < 750;
    final isVerySmall = size.height < 620;
    final isDark = context.isDarkMode;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: const Color(0xFF0D0520),
        body: Stack(
          children: [
            // ── Deep gradient background ─────────────────────────────────────
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0D0520), Color(0xFF3B0F50), Color(0xFF7B1FA2)],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),

            // ── Ambient glow orbs ────────────────────────────────────────────
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) {
                final p = _pulseCtrl.value;
                return Stack(
                  children: [
                    Positioned(
                      top: -size.width * 0.2,
                      right: -size.width * 0.15,
                      child: Container(
                        width: size.width * 0.75,
                        height: size.width * 0.75,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            AppColors.primaryBright.withValues(alpha: 0.14 + p * 0.08),
                            Colors.transparent,
                          ]),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: size.height * 0.25,
                      left: -size.width * 0.2,
                      child: Container(
                        width: size.width * 0.6,
                        height: size.width * 0.6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            AppColors.secondaryLight.withValues(alpha: 0.12 + p * 0.05),
                            Colors.transparent,
                          ]),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            // ── Floating medical icons ────────────────────────────────────────
            AnimatedBuilder(
              animation: _floatCtrl,
              builder: (_, __) {
                final f = _floatCtrl.value;
                return Stack(
                  children: [
                    Positioned(
                      top: size.height * 0.10 + f * 12,
                      right: size.width * 0.08,
                      child: const _FloatingIcon(
                        icon: Icons.favorite_rounded,
                        color: Color(0xFFF2A8D8),
                        size: 22, opacity: 0.22,
                      ),
                    ),
                    Positioned(
                      top: size.height * 0.20 - f * 10,
                      left: size.width * 0.06,
                      child: const _FloatingIcon(
                        icon: Icons.medical_services_outlined,
                        color: Color(0xFFF2A8D8),
                        size: 18, opacity: 0.18,
                      ),
                    ),
                    Positioned(
                      top: size.height * 0.30 + f * 8,
                      right: size.width * 0.14,
                      child: const _FloatingIcon(
                        icon: Icons.shield_outlined,
                        color: Colors.white,
                        size: 16, opacity: 0.14,
                      ),
                    ),
                    Positioned(
                      top: size.height * 0.08 - f * 6,
                      left: size.width * 0.22,
                      child: const _FloatingIcon(
                        icon: Icons.local_hospital_outlined,
                        color: Color(0xFFF2A8D8),
                        size: 14, opacity: 0.15,
                      ),
                    ),
                  ],
                );
              },
            ),

            // ── Main content ─────────────────────────────────────────────────
            SafeArea(
              child: FadeTransition(
                opacity: _fadeIn,
                child: SlideTransition(
                  position: _slideUp,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Hero section ────────────────────────────────────────
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                                28, isVerySmall ? 14 : (isSmall ? 20 : 32), 28, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Logo badge
                                AnimatedBuilder(
                                  animation: _pulseCtrl,
                                  builder: (_, __) {
                                    final p = _pulseCtrl.value;
                                    final glowSize = isVerySmall ? 64.0 : (isSmall ? 76.0 : 88.0);
                                    final logoSize = isVerySmall ? 46.0 : (isSmall ? 54.0 : 64.0);
                                    return Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: glowSize, height: glowSize,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: RadialGradient(colors: [
                                              const Color(0xFFF2A8D8)
                                                  .withValues(alpha: 0.18 + p * 0.10),
                                              Colors.transparent,
                                            ]),
                                          ),
                                        ),
                                        Container(
                                          width: logoSize, height: logoSize,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(18),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.30 + p * 0.18),
                                                blurRadius: 22,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(18),
                                            child: Image.asset(
                                              'assets/icons/mednu_logo.png',
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),

                                SizedBox(height: isVerySmall ? 12 : (isSmall ? 16 : 24)),

                                Text(
                                  'Your health,\nalways protected.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isVerySmall ? 24 : (isSmall ? 27 : 30),
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'Poppins',
                                    height: 1.2,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                SizedBox(height: isVerySmall ? 6 : 10),
                                Text(
                                  'Sign in or create your account with\nyour mobile number.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: isVerySmall ? 13 : 15,
                                    fontFamily: 'Poppins',
                                    height: 1.4,
                                  ),
                                ),

                                SizedBox(height: isVerySmall ? 10 : (isSmall ? 14 : 20)),

                                // ── Social proof strip ───────────────────────
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, color: Color(0xFFFFC857), size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      '4.9',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.85),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 8),
                                      width: 3, height: 3,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.35),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Text(
                                      'Trusted by 50,000+ patients',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.55),
                                        fontSize: 12.5,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                  ],
                                ),

                                SizedBox(height: isVerySmall ? 12 : (isSmall ? 16 : 24)),

                                // ── Feature pills ────────────────────────────
                                const Wrap(
                                  spacing: 8, runSpacing: 8,
                                  children: [
                                    _FeaturePill(icon: Icons.verified_rounded, label: '100% Secure'),
                                    _FeaturePill(icon: Icons.lock_rounded, label: 'Private'),
                                    _FeaturePill(icon: Icons.health_and_safety_rounded, label: 'HIPAA'),
                                    _FeaturePill(icon: Icons.phone_android_rounded, label: 'OTP Verified'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ── Input card ───────────────────────────────────────────
                      AnimatedPadding(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        padding: EdgeInsets.only(bottom: bottom),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.fromLTRB(
                              24, 16, 24, 24 + MediaQuery.of(context).padding.bottom),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurface : Colors.white,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF3B0F50).withValues(alpha: 0.30),
                                blurRadius: 48,
                                offset: const Offset(0, -10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Drag handle
                              Center(
                                child: Container(
                                  width: 40, height: 4,
                                  margin: const EdgeInsets.only(bottom: 20),
                                  decoration: BoxDecoration(
                                    gradient: AppColors.heroBannerGradient,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),

                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Enter mobile number',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: isDark ? Colors.white : const Color(0xFF1A0A2E),
                                              fontFamily: 'Poppins',
                                            )),
                                        const SizedBox(height: 4),
                                        Text("Enter your registered mobile number",
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: context.appTextSecondary,
                                              fontFamily: 'Poppins',
                                            )),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 38, height: 38,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: const Icon(Icons.phone_iphone_rounded,
                                        color: AppColors.primary, size: 18),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // ── Phone field ──────────────────────────────
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkCard : const Color(0xFFF8F4FF),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _focused || _isValid
                                        ? AppColors.secondary
                                        : AppColors.secondary.withValues(alpha: 0.2),
                                    width: _focused || _isValid ? 1.5 : 1,
                                  ),
                                  boxShadow: _focused
                                      ? [
                                          BoxShadow(
                                            color: AppColors.secondary.withValues(alpha: 0.18),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 17),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? AppColors.darkCardElevated
                                            : const Color(0xFFEDE0F0),
                                        borderRadius: const BorderRadius.horizontal(
                                            left: Radius.circular(16)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('🇮🇳', style: TextStyle(fontSize: 18)),
                                          SizedBox(width: 6),
                                          Text('+91',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.secondary,
                                                fontFamily: 'Poppins',
                                              )),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 1, height: 26,
                                      color: AppColors.secondary.withValues(alpha: 0.15),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: _phoneController,
                                        focusNode: _phoneFocus,
                                        keyboardType: TextInputType.phone,
                                        maxLength: 10,
                                        autofocus: false,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(10),
                                        ],
                                        onChanged: (v) {
                                          setState(() {});
                                          if (v.length == 10) HapticFeedback.selectionClick();
                                        },
                                        onSubmitted: (_) => _continue(),
                                        decoration: InputDecoration(
                                          hintText: '98765 43210',
                                          hintStyle: TextStyle(
                                              color: context.appTextHint,
                                              fontFamily: 'Poppins',
                                              fontSize: 16),
                                          border: InputBorder.none,
                                          counterText: '',
                                          contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 17),
                                        ),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Poppins',
                                          color: isDark ? Colors.white : const Color(0xFF1A0A2E),
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ),
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 200),
                                      transitionBuilder: (child, anim) => ScaleTransition(
                                          scale: anim, child: child),
                                      child: _isValid
                                          ? const Padding(
                                              key: ValueKey('valid'),
                                              padding: EdgeInsets.only(right: 14),
                                              child: Icon(Icons.check_circle_rounded,
                                                  color: AppColors.secondary, size: 22),
                                            )
                                          : const SizedBox(key: ValueKey('empty')),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              // ── Continue button ──────────────────────────
                              GestureDetector(
                                onTapDown: (_) {
                                  if (_isValid && !_isLoading) setState(() => _btnScale = 0.97);
                                },
                                onTapUp: (_) => setState(() => _btnScale = 1),
                                onTapCancel: () => setState(() => _btnScale = 1),
                                onTap: _isLoading || !_isValid ? null : _continue,
                                child: AnimatedScale(
                                  scale: _btnScale,
                                  duration: const Duration(milliseconds: 120),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: double.infinity,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      gradient: _isValid && !_isLoading
                                          ? AppColors.heroBannerGradient
                                          : const LinearGradient(
                                              colors: [Color(0xFFCCCCCC), Color(0xFFCCCCCC)],
                                            ),
                                      boxShadow: _isValid && !_isLoading
                                          ? [
                                              BoxShadow(
                                                color: AppColors.primary.withValues(alpha: 0.4),
                                                blurRadius: 16,
                                                offset: const Offset(0, 6),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Stack(
                                        children: [
                                          if (_isValid && !_isLoading)
                                            AnimatedBuilder(
                                              animation: _shimmerCtrl,
                                              builder: (_, __) {
                                                final w = MediaQuery.of(context).size.width - 48;
                                                final x = (_shimmerCtrl.value * (w + 120)) - 60;
                                                return Positioned(
                                                  top: 0,
                                                  bottom: 0,
                                                  left: x,
                                                  child: Transform.rotate(
                                                    angle: -0.4,
                                                    child: Container(
                                                      width: 36,
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          colors: [
                                                            Colors.white.withValues(alpha: 0.0),
                                                            Colors.white.withValues(alpha: 0.22),
                                                            Colors.white.withValues(alpha: 0.0),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          Center(
                                            child: _isLoading
                                                ? const SizedBox(
                                                    width: 24, height: 24,
                                                    child: CircularProgressIndicator(
                                                        color: Colors.white, strokeWidth: 2.5),
                                                  )
                                                : const Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Text('Continue',
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.w700,
                                                            fontFamily: 'Poppins',
                                                            color: Colors.white,
                                                          )),
                                                      SizedBox(width: 8),
                                                      Icon(Icons.arrow_forward_rounded,
                                                          color: Colors.white, size: 18),
                                                    ],
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              Center(
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  children: [
                                    Icon(Icons.lock_outline_rounded,
                                        size: 12, color: context.appTextHint),
                                    const SizedBox(width: 4),
                                    Text(
                                      'By continuing, you agree to our ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.appTextHint,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => context.push(AppRoutes.termsOfService),
                                      child: Text(
                                        'Terms',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.secondary,
                                          decoration: TextDecoration.underline,
                                          decorationColor: AppColors.secondary.withValues(alpha: 0.4),
                                          fontFamily: 'Poppins',
                                        ),
                                      ),
                                    ),
                                    Text(
                                      ' & ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.appTextHint,
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => context.push(AppRoutes.privacyPolicy),
                                      child: Text(
                                        'Privacy Policy',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.secondary,
                                          decoration: TextDecoration.underline,
                                          decorationColor: AppColors.secondary.withValues(alpha: 0.4),
                                          fontFamily: 'Poppins',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
      ),
    );
  }
}

class _FloatingIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double opacity;
  const _FloatingIcon({required this.icon, required this.color,
      required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: opacity,
    child: Icon(icon, color: color, size: size),
  );
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFFF2A8D8)),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Poppins',
                )),
          ],
        ),
      ),
    ),
  );
}
