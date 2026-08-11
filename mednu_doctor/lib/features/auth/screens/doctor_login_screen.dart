import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/doctor_auth_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';

class DoctorLoginScreen extends StatefulWidget {
  const DoctorLoginScreen({super.key});
  @override
  State<DoctorLoginScreen> createState() => _DoctorLoginScreenState();
}

class _DoctorLoginScreenState extends State<DoctorLoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideUp = Tween(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── Gradient background top section ──────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.46,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  // Decorative circles
                  Positioned(
                    top: -40,
                    right: -40,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha:0.06),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 60,
                    right: 20,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha:0.06),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 40,
                    left: -30,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha:0.05),
                      ),
                    ),
                  ),
                  // Hero content
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 36, 28, 0),
                      child: FadeTransition(
                        opacity: _fadeIn,
                        child: SlideTransition(
                          position: _slideUp,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Logo
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.30),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
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
                              const SizedBox(height: 20),
                              const Text(
                                'MedNU Doctor',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Healthcare Professional Platform',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 28),
                              // Trust badges
                              const Row(children: [
                                _TrustBadge(
                                    icon: Icons.verified_user_rounded,
                                    label: 'Verified'),
                                SizedBox(width: 10),
                                _TrustBadge(
                                    icon: Icons.lock_rounded, label: 'Secure'),
                                SizedBox(width: 10),
                                _TrustBadge(
                                    icon: Icons.health_and_safety_rounded,
                                    label: 'HIPAA Safe'),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Curved white card ─────────────────────────────────────────────
          Positioned(
            top: size.height * 0.4,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
            ),
          ),

          // ── Form ──────────────────────────────────────────────────────────
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(height: size.height * 0.44),
                    FadeTransition(
                      opacity: _fadeIn,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Welcome Back, Doctor!',
                                style: AppTextStyles.h3),
                            const SizedBox(height: 4),
                            Text('Sign in to manage your consultations',
                                style: AppTextStyles.bodyMedium
                                    .copyWith(color: AppColors.textSecondary)),
                            const SizedBox(height: 28),

                            // ── Phone field ──────────────────────────────
                            const Text('Mobile Number', style: AppTextStyles.labelLarge),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha:0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 16),
                                  decoration: const BoxDecoration(
                                      border: Border(
                                          right: BorderSide(
                                              color: AppColors.border))),
                                  child: const Row(children: [
                                    Text('🇮🇳',
                                        style: TextStyle(fontSize: 20)),
                                    SizedBox(width: 6),
                                    Text('+91',
                                        style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14)),
                                  ]),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    maxLength: 10,
                                    style: AppTextStyles.bodyLarge,
                                    decoration: const InputDecoration(
                                      hintText: 'Enter your mobile number',
                                      border: InputBorder.none,
                                      counterText: '',
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 16),
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 28),

                            // ── Send OTP button ──────────────────────────
                            GradientButton(
                              label: 'Send OTP',
                              isLoading: _isLoading,
                              width: double.infinity,
                              height: 54,
                              onTap: _isLoading ? () {} : () => _sendOTP(context),
                            ),
                            const SizedBox(height: 22),

                            // ── Register link ────────────────────────────
                            Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('New to MedNU Doctor? ',
                                      style: AppTextStyles.bodyMedium),
                                  GestureDetector(
                                    onTap: () =>
                                        context.push(AppRoutes.register),
                                    child: const Text(
                                      'Register',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                        decoration: TextDecoration.underline,
                                        decorationColor: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ]),
                            const SizedBox(height: 24),

                            // ── Verified banner ──────────────────────────
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary.withValues(alpha:0.06),
                                    const Color(0xFF7B1FA2).withValues(alpha:0.04),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color:
                                        AppColors.primary.withValues(alpha:0.15)),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha:0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.verified_rounded,
                                      color: AppColors.primary, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Exclusively for verified medical professionals. Your credentials will be reviewed before activation.',
                                    style: AppTextStyles.bodySmall
                                        .copyWith(color: AppColors.primary),
                                  ),
                                ),
                              ]),
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

  Future<void> _sendOTP(BuildContext context) async {
    if (_phoneController.text.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid 10-digit number')));
      return;
    }
    setState(() => _isLoading = true);
    final phone = '+91${_phoneController.text}';
    try {
      await DoctorAuthService.sendOTP(phone);
      if (!mounted) return;
      context.push(AppRoutes.otp, extra: {'phone': phone, 'isLogin': true});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// ── Trust Badge ───────────────────────────────────────────────────────────────
class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TrustBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha:0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha:0.35)),
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
