import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../legal/screens/privacy_policy_screen.dart';
import '../../legal/screens/terms_of_service_screen.dart';
import '../providers/auth_provider.dart';

class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen>
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
    _phoneController.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      // See doctor_login_screen.dart for the rationale: freezing the layout
      // against the keyboard here (instead of letting Scaffold/MediaQuery
      // react to it) keeps the fractional-height hero/card from jumping the
      // moment the Mobile Number field is focused.
      resizeToAvoidBottomInset: false,
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
                        color: Colors.white.withValues(alpha: 0.06),
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
                        color: Colors.white.withValues(alpha: 0.06),
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
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  // Hero content — scrollable/centered so it can never
                  // pixel-overflow the fractional hero height on short
                  // screens or larger text scales.
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(28, 36, 28, 16),
                            child: FadeTransition(
                              opacity: _fadeIn,
                              child: SlideTransition(
                                position: _slideUp,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'MedNU',
                                      style: AppTextStyles.display
                                          .copyWith(color: Colors.white, height: 1.1),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Your Personal Health Companion',
                                      style: AppTextStyles.onPrimaryBody
                                          .copyWith(fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 28),
                                    // Trust badges — Wrap (not Row) so 3 pills
                                    // never horizontally overflow on narrow screens.
                                    const Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        _TrustBadge(
                                            icon: Icons.verified_user_rounded,
                                            label: 'Verified'),
                                        _TrustBadge(
                                            icon: Icons.lock_rounded, label: 'Secure'),
                                        _TrustBadge(
                                            icon: Icons.health_and_safety_rounded,
                                            label: 'HIPAA Safe'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
          // Bounded to the area below the hero (top: size.height * 0.4, same
          // as the curved white card above) so this scrollview's own
          // viewport clips its content there. A Positioned.fill + spacer
          // here would let the form scroll up over the fixed hero whenever
          // it's taller than the space below it — see doctor_login_screen.dart.
          Positioned(
            top: size.height * 0.4,
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  top: size.height * 0.04,
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: FadeTransition(
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
                              _isRegisterMode ? 'Join MedNU' : 'Welcome Back!',
                              style: AppTextStyles.h3,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isRegisterMode
                                  ? 'Verify your mobile number to create your account'
                                  : 'Sign in to manage your health',
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 28),

                            // ── Phone field ──────────────────────────────
                            const Text('Mobile Number', style: AppTextStyles.labelLarge),
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
                                    color: Colors.black.withValues(alpha: 0.04),
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
                                    Text('🇮🇳', style: TextStyle(fontSize: 20)),
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
                                    onSubmitted: (_) => _sendOTP(context),
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
                                onPressed: _isLoading ? null : () => _sendOTP(context),
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

                            // ── Privacy banner ────────────────────────────
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary.withValues(alpha: 0.06),
                                    AppColors.secondary.withValues(alpha: 0.04),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color:
                                        AppColors.primary.withValues(alpha: 0.15)),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.verified_rounded,
                                      color: AppColors.primary, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Your health data stays private & secure. Every sign-in is verified with a one-time password.',
                                    style: AppTextStyles.bodySmall
                                        .copyWith(color: AppColors.primary),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 20),

                            // ── Terms ──────────────────────────────────────
                            Center(
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                children: [
                                  Text(
                                    'By continuing, you agree to our ',
                                    style: AppTextStyles.bodySmall
                                        .copyWith(color: AppColors.textSecondary),
                                  ),
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const TermsOfServiceScreen()),
                                    ),
                                    child: Text(
                                      'Terms',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    ' & ',
                                    style: AppTextStyles.bodySmall
                                        .copyWith(color: AppColors.textSecondary),
                                  ),
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const PrivacyPolicyScreen()),
                                    ),
                                    child: Text(
                                      'Privacy Policy',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
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
              ),
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendOTP(BuildContext context) async {
    final phone = _phoneController.text.trim();
    if (phone.length != 10) {
      setState(() => _phoneError = 'Please enter a valid 10-digit mobile number.');
      return;
    }
    setState(() {
      _phoneError = null;
      _isLoading = true;
    });

    final fullPhone = '+91$phone';
    try {
      await ref.read(authProvider.notifier).sendOtp(fullPhone);
      if (!mounted) return;
      context.push(AppRoutes.otp, extra: {
        'phone': fullPhone,
        'isExistingUser': !_isRegisterMode,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
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
