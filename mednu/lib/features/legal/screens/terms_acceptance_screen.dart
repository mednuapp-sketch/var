import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

/// Terms & Conditions acceptance gate — shown once on first launch, before
/// the disclaimer/onboarding flow. The "I Accept" button stays disabled
/// until the acknowledgement checkbox is ticked (same gated pattern as
/// register_screen.dart's terms checkbox), and the screen cannot be
/// dismissed without accepting.
class TermsAcceptanceScreen extends StatefulWidget {
  const TermsAcceptanceScreen({super.key});

  @override
  State<TermsAcceptanceScreen> createState() => _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends State<TermsAcceptanceScreen> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.appBackground,
        appBar: AppBar(
          backgroundColor: context.appSurface,
          elevation: 0,
          scrolledUnderElevation: 1,
          surfaceTintColor: context.appSurface,
          automaticallyImplyLeading: false,
          title: Text(
            'Terms & Conditions',
            style: TextStyle(fontFamily: 'Poppins',
              color: context.appTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Intro banner ─────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.20),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.description_outlined,
                        color: AppColors.primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Before You Continue',
                            style: TextStyle(fontFamily: 'Poppins',
                              color: AppColors.primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Please review and accept our Terms & Conditions',
                            style: TextStyle(fontFamily: 'Poppins',
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── 1. About MedNU ─────────────────────────────────────
              const _TermsCard(
                accentColor: AppColors.info,
                icon: Icons.info_outline_rounded,
                title: 'About MedNU',
                body: 'MedNU is a technology platform that connects you with independent '
                    'doctors, diagnostic centres, and pharmacies. MedNU does not provide '
                    'medical treatment, diagnosis, or prescriptions directly.',
              ),

              const SizedBox(height: 12),

              // ── 2. Eligibility ─────────────────────────────────────
              const _TermsCard(
                accentColor: AppColors.accent,
                icon: Icons.badge_outlined,
                title: 'Eligibility',
                body: 'You must be at least 18 years old to register and use the '
                    "platform. If registering a minor, the parent or legal guardian is "
                    "responsible for the minor's use of the platform.",
              ),

              const SizedBox(height: 12),

              // ── 3. Telemedicine Consent ────────────────────────────
              const _TermsCard(
                accentColor: AppColors.primary,
                icon: Icons.videocam_outlined,
                title: 'Telemedicine Consent',
                body: 'By booking an online consultation, you consent to receive '
                    'healthcare services through video, audio, or chat as permitted under '
                    'applicable laws. Online consultations have limitations and may require '
                    'physical examination or further testing.',
              ),

              const SizedBox(height: 12),

              // ── 4. Emergency Disclaimer ────────────────────────────
              Card(
                elevation: 0,
                color: AppColors.error.withValues(alpha: 0.06),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.30),
                    width: 1.5,
                  ),
                ),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.emergency_rounded,
                              color: AppColors.error,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Emergency Disclaimer',
                              style: TextStyle(fontFamily: 'Poppins',
                                color: AppColors.error,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'MedNU is not an emergency medical service. For any medical '
                        'emergency or life-threatening condition, immediately contact '
                        'emergency services or visit the nearest hospital.',
                        style: TextStyle(fontFamily: 'Poppins',
                          color: context.appTextSecondary,
                          fontSize: 13,
                          height: 1.75,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── 5. Limitation of Liability ─────────────────────────
              const _TermsCard(
                accentColor: AppColors.warning,
                icon: Icons.gavel_rounded,
                title: 'Limitation of Liability',
                body: 'MedNU acts only as a facilitator platform and shall not be liable '
                    'for:\n\n'
                    '• Medical advice, diagnosis, treatment, or healthcare outcomes\n'
                    '• Acts, omissions, or misconduct of doctors, labs, or pharmacies\n'
                    '• Indirect, incidental, or consequential damages',
              ),

              const SizedBox(height: 12),

              // ── 6. Privacy & Health Data ───────────────────────────
              const _TermsCard(
                accentColor: AppColors.secondary,
                icon: Icons.shield_outlined,
                title: 'Privacy & Health Data',
                body: 'Your personal and health information is collected and shared with '
                    'relevant doctors, labs, and pharmacies solely to provide the services '
                    'you request, in line with our Privacy Policy and applicable law.',
              ),

              const SizedBox(height: 24),

              // ── Acknowledgement checkbox ───────────────────────────
              GestureDetector(
                onTap: () => setState(() => _accepted = !_accepted),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _accepted
                        ? AppColors.primary.withValues(alpha: 0.08)
                        : AppColors.primary.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _accepted
                          ? AppColors.primary.withValues(alpha: 0.35)
                          : AppColors.primary.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.only(top: 1),
                        decoration: BoxDecoration(
                          color: _accepted ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _accepted ? AppColors.primary : context.appBorder,
                            width: 1.5,
                          ),
                        ),
                        child: _accepted
                            ? const Icon(Icons.check, color: Colors.white, size: 14)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "I have read, understood, and agree to MedNU's Terms & "
                          'Conditions, including consent to telemedicine services and '
                          'processing of my health information.',
                          style: TextStyle(fontFamily: 'Poppins',
                            color: context.appTextSecondary,
                            fontSize: 12.5,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _accepted ? () => context.pop() : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.25),
                    disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'I Accept',
                    style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TermsCard extends StatelessWidget {
  final Color accentColor;
  final IconData icon;
  final String title;
  final String body;

  const _TermsCard({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: context.appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: accentColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: accentColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontFamily: 'Poppins',
                      color: context.appTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: TextStyle(fontFamily: 'Poppins',
                color: context.appTextSecondary,
                fontSize: 13,
                height: 1.75,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
