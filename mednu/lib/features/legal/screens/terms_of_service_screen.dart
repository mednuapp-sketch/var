import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: context.appSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: context.appTextPrimary,
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Terms of Service',
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
            // ── Hero header card ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.gavel_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Terms of Service',
                          style: TextStyle(fontFamily: 'Poppins', 
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Last updated: January 1, 2025',
                          style: TextStyle(fontFamily: 'Poppins', 
                            color: Colors.white.withValues(alpha: 0.80),
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

            const SizedBox(height: 8),

            // ── Intro blurb ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Please read these Terms carefully before using MedNU. By using the app '
                'you agree to be bound by these Terms.',
                style: TextStyle(fontFamily: 'Poppins',
                  color: context.appTextSecondary,
                  fontSize: 13,
                  height: 1.7,
                ),
              ),
            ),

            // ── Terms sections ────────────────────────────────────
            const _TermsSection(
              number: 1,
              title: 'About MedNU',
              body: 'MedNU is a technology platform that connects patients with independent '
                  'doctors, diagnostic centres, pharmacies, and other healthcare service '
                  'providers. MedNU does not provide medical treatment, diagnosis, '
                  'prescriptions, or healthcare services directly.',
            ),

            const _TermsSection(
              number: 2,
              title: 'Eligibility',
              body: 'You must be at least 18 years old to register and use the Platform. If '
                  'registering a minor, the parent or legal guardian shall be responsible for '
                  'the minor\'s use of the Platform.',
            ),

            const _TermsSection(
              number: 3,
              title: 'User Responsibility',
              body: 'You agree to:\n\n'
                  '• Provide accurate and complete information.\n'
                  '• Maintain confidentiality of your login credentials and OTPs.\n'
                  '• Use the Platform only for lawful purposes.\n'
                  '• Provide correct medical history, reports, and health information.\n\n'
                  'You shall be solely responsible for any consequences arising from incorrect '
                  'or incomplete information provided by you.',
            ),

            const _TermsSection(
              number: 4,
              title: 'Telemedicine Consent',
              body: 'By booking an online consultation, you consent to receive healthcare '
                  'services through video, audio, or chat as permitted under applicable laws '
                  'and Telemedicine Practice Guidelines.\n\n'
                  'You understand that online consultations have limitations and may require '
                  'physical examination or further testing.',
            ),

            const _TermsSection(
              number: 5,
              title: 'Diagnostics and Pharmacy Services',
              body: 'Diagnostic tests and pharmacy services are provided by independent '
                  'partner laboratories and pharmacies. MedNU is not responsible for the '
                  'accuracy of test results, medicine availability, treatment outcomes, or '
                  'delays caused by such partners.',
            ),

            const _TermsSection(
              number: 6,
              title: 'Fees and Payments',
              body: 'All applicable charges will be displayed before booking or purchase. '
                  'Payments are processed through secure third-party payment gateways.\n\n'
                  'Refunds and cancellations shall be governed by the applicable Refund and '
                  'Cancellation Policy.',
            ),

            const _TermsSection(
              number: 7,
              title: 'Privacy and Health Data',
              body: 'Your personal and health information will be collected, stored, '
                  'processed, and shared with relevant healthcare providers, laboratories, '
                  'and pharmacies solely for providing requested services and in accordance '
                  'with applicable laws and our Privacy Policy.',
            ),

            const _TermsSection(
              number: 8,
              title: 'Emergency Disclaimer',
              body: 'MedNU is not an emergency medical service.\n\n'
                  'For any medical emergency or life-threatening condition, immediately '
                  'contact emergency services or visit the nearest hospital.',
            ),

            const _TermsSection(
              number: 9,
              title: 'Limitation of Liability',
              body: 'MedNU acts only as a facilitator platform.\n\n'
                  'To the maximum extent permitted by law, MedNU shall not be liable for:\n\n'
                  '• Medical advice, diagnosis, treatment, prescriptions, or healthcare '
                  'outcomes.\n'
                  '• Acts, omissions, negligence, or misconduct of doctors, laboratories, '
                  'pharmacies, or other service providers.\n'
                  '• Indirect, incidental, consequential, or special damages arising from use '
                  'of the Platform.',
            ),

            const _TermsSection(
              number: 10,
              title: 'Suspension of Account',
              body: 'MedNU reserves the right to suspend or terminate any account found to be '
                  'violating these Terms, providing false information, or misusing the '
                  'Platform.',
            ),

            const _TermsSection(
              number: 11,
              title: 'Intellectual Property',
              body: 'All trademarks, logos, software, content, and intellectual property '
                  'associated with MedNU remain the exclusive property of MedNU and may not '
                  'be copied or used without prior written permission.',
            ),

            const _TermsSection(
              number: 12,
              title: 'Governing Law',
              body: 'These Terms shall be governed by the laws of India and subject to the '
                  'exclusive jurisdiction of the courts at Visakhapatnam, Andhra Pradesh.',
            ),

            const _TermsSection(
              number: 13,
              title: 'Consent',
              body: 'By clicking "I Accept", registering an account, or using the Platform, '
                  'you confirm that:\n\n'
                  '• You have read and understood these Terms.\n'
                  '• You voluntarily agree to be legally bound by them.\n'
                  '• You consent to electronic communications and electronic records.\n'
                  '• You understand the nature and limitations of telemedicine and online '
                  'healthcare services.\n'
                  '• You agree to the collection and processing of your personal and health '
                  'information for providing services through the Platform.',
              isLast: true,
            ),

            const SizedBox(height: 16),

            // ── Final acceptance statement ─────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              decoration: BoxDecoration(
                color: context.appPrimarySoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: context.appPrimary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_rounded,
                    color: context.appPrimary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'I HAVE READ, UNDERSTOOD, AND AGREE TO THESE TERMS AND CONDITIONS.',
                      style: TextStyle(fontFamily: 'Poppins',
                        color: context.appTextPrimary,
                        fontSize: 13,
                        height: 1.6,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TermsSection extends StatelessWidget {
  final int number;
  final String title;
  final String body;
  final bool isLast;

  const _TermsSection({
    required this.number,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 0,
          color: context.appSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        number.toString().padLeft(2, '0'),
                        style: const TextStyle(fontFamily: 'Poppins', 
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(fontFamily: 'Poppins',
                          color: context.appTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
        ),
        if (!isLast) const SizedBox(height: 12),
      ],
    );
  }
}
