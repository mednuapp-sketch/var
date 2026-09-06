import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../legal/screens/terms_of_service_screen.dart';

/// Gate screen shown right after OTP verification for a new user, before
/// [RegisterScreen]. The user must accept the Terms of Service and Privacy
/// Policy here to proceed — the inline checkbox that used to live on the
/// Create Account form now lives here instead.
class TermsAcceptScreen extends StatefulWidget {
  final String phone;
  const TermsAcceptScreen({super.key, required this.phone});

  @override
  State<TermsAcceptScreen> createState() => _TermsAcceptScreenState();
}

class _TermsAcceptScreenState extends State<TermsAcceptScreen> {
  bool _accepted = false;

  void _continue() {
    if (!_accepted) return;
    context.go(AppRoutes.register, extra: {'phone': widget.phone});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBase,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.heroBannerGradient),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () =>
                            context.canPop() ? context.pop() : context.go(AppRoutes.login),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white, size: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Text('Terms & Conditions',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins',
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Icon(Icons.gavel_rounded,
                    color: Colors.white.withValues(alpha: 0.85), size: 48),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Before we create your account, please review and accept our '
                    'Terms of Service and Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                      fontFamily: 'Poppins',
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          20, 28, 20, MediaQuery.of(context).padding.bottom + 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const TermsOfServiceScreen()),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F4FF),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: AppColors.primary.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.description_outlined,
                                      color: AppColors.primary, size: 20),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text('Read full Terms of Service',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Poppins',
                                          color: Color(0xFF1A0A2E),
                                        )),
                                  ),
                                  const Icon(Icons.chevron_right_rounded,
                                      color: AppColors.primary, size: 20),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() => _accepted = !_accepted),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _accepted
                                    ? const Color(0xFFF0E8FA)
                                    : const Color(0xFFFAFAFA),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _accepted
                                      ? AppColors.primary.withValues(alpha: 0.5)
                                      : const Color(0xFFE0E0E0),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 22, height: 22,
                                    margin: const EdgeInsets.only(top: 1),
                                    decoration: BoxDecoration(
                                      color: _accepted
                                          ? AppColors.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _accepted
                                            ? AppColors.primary
                                            : const Color(0xFFBBBBBB),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: _accepted
                                        ? const Icon(Icons.check,
                                            color: Colors.white, size: 14)
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'I agree to the Terms of Service and Privacy Policy',
                                      style: TextStyle(
                                        color: Color(0xFF444444),
                                        fontSize: 13,
                                        fontFamily: 'Poppins',
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: _accepted
                                  ? AppColors.primaryGradient
                                  : const LinearGradient(
                                      colors: [Color(0xFFCCCCCC), Color(0xFFCCCCCC)],
                                    ),
                              boxShadow: _accepted
                                  ? [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.35),
                                        blurRadius: 14,
                                        offset: const Offset(0, 5),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: _accepted ? _continue : null,
                                child: const Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Accept & Continue',
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
        ],
      ),
    );
  }
}
