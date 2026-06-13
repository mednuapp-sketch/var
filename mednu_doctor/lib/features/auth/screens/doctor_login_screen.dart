import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/doctor_auth_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';

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
                                  color: Colors.white.withValues(alpha:0.2),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                      color: Colors.white.withValues(alpha:0.3)),
                                ),
                                child: const Icon(Icons.medical_services_rounded,
                                    color: Colors.white, size: 32),
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
                              Row(children: [
                                _TrustBadge(
                                    icon: Icons.verified_user_rounded,
                                    label: 'Verified'),
                                const SizedBox(width: 10),
                                _TrustBadge(
                                    icon: Icons.lock_rounded, label: 'Secure'),
                                const SizedBox(width: 10),
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
                            Text('Welcome Back, Doctor!',
                                style: AppTextStyles.h3),
                            const SizedBox(height: 4),
                            Text('Sign in to manage your consultations',
                                style: AppTextStyles.bodyMedium
                                    .copyWith(color: AppColors.textSecondary)),
                            const SizedBox(height: 28),

                            // ── Phone field ──────────────────────────────
                            Text('Mobile Number', style: AppTextStyles.labelLarge),
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
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed:
                                    _isLoading ? null : () => _sendOTP(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  textStyle: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5))
                                    : const Text('Send OTP'),
                              ),
                            ),
                            const SizedBox(height: 22),

                            // ── Register link ────────────────────────────
                            Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('New to MedNU Doctor? ',
                                      style: AppTextStyles.bodyMedium),
                                  GestureDetector(
                                    onTap: () =>
                                        context.push(AppRoutes.register),
                                    child: Text(
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

    await DoctorAuthService.sendOTP(
      phone: '+91${_phoneController.text}',
      onCodeSent: (verificationId) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        context.push(AppRoutes.otp, extra: {
          'phone': '+91${_phoneController.text}',
          'verificationId': verificationId,
          'isLogin': true,
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      },
      onAutoVerified: (_) async {
        // Firebase auto-verified the number (common on Android for previously
        // used numbers). The user is already signed in — skip the OTP screen.
        final uid = DoctorAuthService.currentUid;
        if (uid == null || !mounted) return;
        setState(() => _isLoading = false);
        try {
          final exists = await DoctorAuthService.profileExists(uid);
          if (!mounted) return;
          if (!exists) {
            context.go(AppRoutes.register);
            return;
          }
          final profile = await DoctorAuthService.getProfile(uid);
          if (!mounted) return;
          final status = profile?['status'] as String?;
          context.go(status == 'active' ? AppRoutes.dashboard : AppRoutes.verificationPending);
        } catch (_) {
          if (!mounted) return;
          context.go(AppRoutes.verificationPending);
        }
      },
    );
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
