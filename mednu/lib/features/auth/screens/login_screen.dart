import 'dart:math' show sin, pi;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../legal/screens/privacy_policy_screen.dart';
import '../../legal/screens/terms_of_service_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  bool _isLoading = false;

  // Entry animation
  late AnimationController _entryCtrl;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  // Ambient pulse on the logo glow
  late AnimationController _pulseCtrl;

  // Shimmer sweep across the card
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _fadeIn = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideUp = Tween(begin: const Offset(0, 0.14), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _googleSignIn() async {
    // Replaced by phone+MPIN auth — redirect to phone entry
    if (!mounted) return;
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmall = size.height < 680;

    return Scaffold(
      backgroundColor: const Color(0xFF1A0A2E),
      body: Stack(
        children: [
          // ── Full-bleed gradient background ───────────────────────────────
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF1A0A2E),
                    Color(0xFF5E1A4A),
                    Color(0xFF880E4F),
                  ],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          // ── Ambient glow orbs ─────────────────────────────────────────────
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) {
              final pulse = (sin(_pulseCtrl.value * pi) * 0.5 + 0.5);
              return Stack(
                children: [
                  Positioned(
                    top: -size.width * 0.3,
                    right: -size.width * 0.2,
                    child: Container(
                      width: size.width * 0.9,
                      height: size.width * 0.9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          const Color(0xFFC2185B)
                              .withValues(alpha:0.12 + pulse * 0.08),
                          Colors.transparent,
                        ]),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: size.height * 0.1,
                    left: -size.width * 0.25,
                    child: Container(
                      width: size.width * 0.75,
                      height: size.width * 0.75,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          const Color(0xFF7B1FA2)
                              .withValues(alpha:0.10 + pulse * 0.06),
                          Colors.transparent,
                        ]),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // ── Main scrollable content ───────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                height: size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: SlideTransition(
                    position: _slideUp,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          SizedBox(height: isSmall ? 32 : size.height * 0.09),

                          // ── Logo section ─────────────────────────────────
                          _LogoSection(pulseCtrl: _pulseCtrl),

                          SizedBox(height: isSmall ? 20 : 32),

                          // ── Headline ─────────────────────────────────────
                          const Text(
                            'Your Health.\nOur Priority.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.15,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Trusted by thousands of families\nfor complete healthcare management.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13.5,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withValues(alpha:0.62),
                              height: 1.55,
                            ),
                          ),

                          SizedBox(height: isSmall ? 20 : 36),

                          // ── Trust badges ─────────────────────────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _TrustBadge(
                                icon: Icons.verified_rounded,
                                label: 'Verified',
                              ),
                              const SizedBox(width: 12),
                              _TrustBadge(
                                icon: Icons.lock_rounded,
                                label: 'Secure',
                              ),
                              const SizedBox(width: 12),
                              _TrustBadge(
                                icon: Icons.health_and_safety_rounded,
                                label: 'HIPAA Safe',
                              ),
                            ],
                          ),

                          const Spacer(),

                          // ── White card ────────────────────────────────────
                          _AuthCard(
                            shimmerCtrl: _shimmerCtrl,
                            isLoading: _isLoading,
                            onGoogleSignIn: _googleSignIn,
                          ),

                          const SizedBox(height: 20),

                          // ── Terms ──────────────────────────────────────────
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              children: [
                                Text(
                                  'By continuing, you agree to our ',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11.5,
                                    color: Colors.white.withValues(alpha:0.45),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const TermsOfServiceScreen(),
                                    ),
                                  ),
                                  child: Text(
                                    'Terms',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(alpha:0.75),
                                      decoration: TextDecoration.underline,
                                      decorationColor:
                                          Colors.white.withValues(alpha:0.4),
                                    ),
                                  ),
                                ),
                                Text(
                                  ' & ',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11.5,
                                    color: Colors.white.withValues(alpha:0.45),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const PrivacyPolicyScreen(),
                                    ),
                                  ),
                                  child: Text(
                                    'Privacy Policy',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(alpha:0.75),
                                      decoration: TextDecoration.underline,
                                      decorationColor:
                                          Colors.white.withValues(alpha:0.4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: isSmall ? 8 : 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Logo Section ─────────────────────────────────────────────────────────────
class _LogoSection extends StatelessWidget {
  final AnimationController pulseCtrl;
  const _LogoSection({required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (_, __) {
        final pulse = sin(pulseCtrl.value * pi) * 0.5 + 0.5;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Soft glow ring
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFFF2A8D8)
                      .withValues(alpha:0.20 + pulse * 0.12),
                  Colors.transparent,
                ]),
              ),
            ),
            // Logo
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7B1FA2)
                        .withValues(alpha:0.35 + pulse * 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SvgPicture.asset(
                  'assets/icons/mednu_logo.svg',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Auth Card ─────────────────────────────────────────────────────────────────
class _AuthCard extends StatelessWidget {
  final AnimationController shimmerCtrl;
  final bool isLoading;
  final VoidCallback onGoogleSignIn;

  const _AuthCard({
    required this.shimmerCtrl,
    required this.isLoading,
    required this.onGoogleSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.22),
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.waving_hand_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome to MedNU',
                    style: AppTextStyles.h4.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sign in to access your health dashboard',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Continue with Google button
          _GoogleButton(
            isLoading: isLoading,
            shimmerCtrl: shimmerCtrl,
            onTap: onGoogleSignIn,
          ),

          const SizedBox(height: 18),

          // Feature row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: const [
              _FeaturePill(icon: Icons.calendar_month_rounded, label: 'Book Appointments'),
              _FeaturePill(icon: Icons.local_pharmacy_rounded, label: 'Medicine'),
              _FeaturePill(icon: Icons.favorite_rounded, label: 'Health Tracking'),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Google Sign-In Button ────────────────────────────────────────────────────
class _GoogleButton extends StatelessWidget {
  final bool isLoading;
  final AnimationController shimmerCtrl;
  final VoidCallback onTap;

  const _GoogleButton({
    required this.isLoading,
    required this.shimmerCtrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isLoading
                ? AppColors.border
                : const Color(0xFFDDE2E8),
            width: 1.5,
          ),
          boxShadow: isLoading
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Shimmer sweep
              if (!isLoading)
                AnimatedBuilder(
                  animation: shimmerCtrl,
                  builder: (_, __) {
                    final size = MediaQuery.of(context).size;
                    final x = (shimmerCtrl.value * (size.width + 120)) - 60;
                    return Positioned(
                      top: 0,
                      bottom: 0,
                      left: x,
                      child: Transform.rotate(
                        angle: -0.4,
                        child: Container(
                          width: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha:0.0),
                                Colors.white.withValues(alpha:0.5),
                                Colors.white.withValues(alpha:0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // Button content
              Center(
                child: isLoading
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              strokeWidth: 2.5,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Signing in…',
                            style: AppTextStyles.labelLarge.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/google_logo.svg',
                            width: 22,
                            height: 22,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Continue with Google',
                            style: AppTextStyles.labelLarge.copyWith(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Trust Badge ──────────────────────────────────────────────────────────────
class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TrustBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha:0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha:0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feature Pill ─────────────────────────────────────────────────────────────
class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha:0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 17),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
