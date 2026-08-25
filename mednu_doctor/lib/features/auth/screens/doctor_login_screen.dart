import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../services/doctor_auth_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/validators.dart';
import '../../../shared_core/models/app_role.dart';
import '../../../shared_core/navigation/role_menu.dart';

class DoctorLoginScreen extends StatefulWidget {
  const DoctorLoginScreen({super.key});
  @override
  State<DoctorLoginScreen> createState() => _DoctorLoginScreenState();
}

class _DoctorLoginScreenState extends State<DoctorLoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _isRegisterMode = false;
  String? _phoneError;
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
      // The gradient hero + curved card below are sized as fractions of
      // MediaQuery's height (size.height * 0.4x). A Scaffold shrinks that
      // height to dodge the keyboard by default, so every one of those
      // fractional heights recomputes and the whole background visibly
      // resizes/jumps the moment the keyboard opens. Freezing that here and
      // letting the scroll view alone respond to the keyboard (via explicit
      // viewInsets padding below) keeps the background static instead.
      resizeToAvoidBottomInset: false,
      // Belt-and-suspenders on top of resizeToAvoidBottomInset: strip the
      // keyboard's viewInsets out of MediaQuery for this whole screen, so
      // no descendant — the ScrollView, the Positioned hero/card, anything
      // — can independently react to the keyboard opening. The Mobile
      // Number field is well above the fold already, so nothing here
      // actually needs the keyboard-inset scroll padding this removes.
      body: Builder(
        builder: (context) => MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: Stack(
        children: [
          // ── Gradient background top section ──────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.46,
            child: Container(
              decoration: const BoxDecoration(
                gradient: AppColors.heroBannerGradient,
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
                              Text(
                                'MedNU Service',
                                style: AppTextStyles.display.copyWith(color: Colors.white, height: 1.1),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Healthcare Professional Platform',
                                style: AppTextStyles.onPrimaryBody.copyWith(fontWeight: FontWeight.w500),
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
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
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
                            // ── Login / Register toggle ──────────────────
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(children: [
                                Expanded(
                                  child: _AuthModeTab(
                                    label: 'Login',
                                    selected: !_isRegisterMode,
                                    onTap: _isLoading
                                        ? null
                                        : () => setState(() => _isRegisterMode = false),
                                  ),
                                ),
                                Expanded(
                                  child: _AuthModeTab(
                                    label: 'Register',
                                    selected: _isRegisterMode,
                                    onTap: _isLoading
                                        ? null
                                        : () => setState(() => _isRegisterMode = true),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _isRegisterMode
                                  ? 'Join MedNU Service'
                                  : 'Welcome Back, MedNU Partner!',
                              style: AppTextStyles.h3,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isRegisterMode
                                  ? 'Verify your mobile number to register as a partner'
                                  : 'Sign in to manage your services',
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 28),

                            // ── Phone field ──────────────────────────────
                            Text('Mobile Number', style: AppTextStyles.labelLarge),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: _phoneError != null
                                        ? AppColors.error
                                        : AppColors.border),
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
                                    Text('+91', style: AppTextStyles.labelLarge),
                                  ]),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    maxLength: 10,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    style: AppTextStyles.bodyLarge,
                                    onChanged: (_) {
                                      if (_phoneError != null) setState(() => _phoneError = null);
                                    },
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
                            if (_phoneError != null) ...[
                              const SizedBox(height: 6),
                              Text(_phoneError!,
                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
                            ],
                            const SizedBox(height: 28),

                            // ── Send OTP button ──────────────────────────
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => _sendOTP(context, isLogin: !_isRegisterMode),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  textStyle: AppTextStyles.button.copyWith(fontWeight: FontWeight.w600),
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
                            const SizedBox(height: 24),

                            // ── Verified banner ──────────────────────────
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary.withValues(alpha:0.06),
                                    AppColors.secondary.withValues(alpha:0.04),
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
        ),
      ),
    );
  }

  Future<void> _sendOTP(BuildContext context, {bool isLogin = true}) async {
    final error = Validators.phone(_phoneController.text);
    if (error != null) {
      setState(() => _phoneError = error);
      return;
    }
    setState(() {
      _phoneError = null;
      _isLoading = true;
    });

    await DoctorAuthService.sendOTP(
      phone: '+91${_phoneController.text}',
      onCodeSent: (verificationId) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        context.push(AppRoutes.otp, extra: {
          'phone': '+91${_phoneController.text}',
          'verificationId': verificationId,
          'isLogin': isLogin,
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
          if (!mounted || !context.mounted) return;
          if (!exists) {
            // No base identity document yet — brand-new account, same branch
            // doctor_otp_screen.dart uses: pick a role before registering.
            context.go(AppRoutes.partnerRoleSelect);
            return;
          }
          final doctorSnap =
              await FirebaseFirestore.instance.collection('doctors').doc(uid).get();
          final roles = AppRoleX.listFrom(doctorSnap.data()?['roles']);
          final role = roles.first;

          // A non-doctor role's approval status lives on its own
          // `{role}_profiles/{uid}` doc, not on `doctors/{uid}` (which stays
          // 'pending' forever for those roles) — mirrors
          // verification_pending_screen.dart's _startListening().
          final statusSnap = role == AppRole.doctor
              ? doctorSnap
              : await FirebaseFirestore.instance
                  .collection('${role.firestoreValue}_profiles')
                  .doc(uid)
                  .get();
          if (!mounted || !context.mounted) return;
          final status = statusSnap.data()?['status'] as String?;
          if (status != 'active') {
            context.go(AppRoutes.verificationPending);
            return;
          }
          final destination = buildMenuForRole(role);
          context.go(destination.isNotEmpty ? destination.first.route : AppRoutes.dashboard);
        } catch (_) {
          if (!mounted || !context.mounted) return;
          context.go(AppRoutes.verificationPending);
        }
      },
    );
  }
}

// ── Login / Register tab ────────────────────────────────────────────────────
class _AuthModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _AuthModeTab({required this.label, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
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
            style: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
