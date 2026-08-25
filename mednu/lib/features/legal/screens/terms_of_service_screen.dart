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
              title: 'Acceptance of Terms',
              body: 'By downloading, installing, or using the MedNU application ("App"), you '
                  'agree to be legally bound by these Terms of Service ("Terms"). If you do not '
                  'agree to these Terms, do not use the App.\n\n'
                  'These Terms constitute a legally binding agreement between you and MedNU '
                  'Healthcare Services Private Limited ("Company", "we", "us", "our").',
            ),

            const _TermsSection(
              number: 2,
              title: 'Description of Services',
              body: 'MedNU provides a digital healthcare facilitation platform that includes:\n\n'
                  '• Telemedicine — video and chat consultations with licensed doctors\n'
                  '• Appointment booking with hospitals and independent practitioners\n'
                  '• Health tracking — vitals, water intake, period tracker, and more\n'
                  '• Prescription management and digital health records\n'
                  '• Emergency service coordination and ambulance assistance\n\n'
                  'MedNU acts as an intermediary and is not itself a healthcare provider. All '
                  'medical services are rendered by independent, licensed professionals.',
            ),

            const _TermsSection(
              number: 3,
              title: 'User Accounts & Responsibilities',
              body: 'To access MedNU you must:\n\n'
                  '• Be at least 18 years of age (or have parental consent)\n'
                  '• Provide accurate, complete, and up-to-date registration information\n'
                  '• Maintain the confidentiality of your account credentials and MPIN\n'
                  '• Immediately notify us of any unauthorised use of your account\n\n'
                  'You agree not to:\n\n'
                  '• Use the App for any unlawful purpose\n'
                  '• Upload false, misleading, or harmful content\n'
                  '• Attempt to circumvent the App\'s security features\n'
                  '• Harass, abuse, or threaten healthcare providers or staff',
            ),

            const _TermsSection(
              number: 4,
              title: 'Medical Disclaimer',
              body: 'MedNU is NOT a substitute for professional medical advice, diagnosis, or '
                  'treatment. The App facilitates access to licensed healthcare providers but '
                  'does not itself provide medical care.\n\n'
                  'In a medical emergency, seek immediate help from your nearest hospital '
                  'or emergency services. Do not rely on this App '
                  'as a primary response to any life-threatening situation.\n\n'
                  'Always follow the advice of your qualified healthcare provider. Never '
                  'disregard professional medical advice or delay seeking it because of '
                  'something you read or did in MedNU.',
            ),

            const _TermsSection(
              number: 5,
              title: 'Payment Terms & Refunds',
              body: 'All payments are processed securely via Razorpay. By making a payment '
                  'you agree to Razorpay\'s Terms of Service.\n\n'
                  'Refund Policy:\n'
                  '• Cancelled appointments (>24 hours notice) — full refund within 5–7 business days\n'
                  '• Cancelled appointments (<24 hours notice) — 50% refund\n'
                  '• Completed consultations — non-refundable\n'
                  '• Technical failures attributable to MedNU — full refund\n\n'
                  'Wallet credits are non-transferable and expire after 12 months of account inactivity.',
            ),

            const _TermsSection(
              number: 6,
              title: 'Cancellation Policy',
              body: 'You may cancel a booked appointment free of charge up to 24 hours '
                  'before the scheduled time. Cancellations made within 24 hours of the '
                  'appointment will be eligible for a 50% refund only.\n\n'
                  'Doctors and healthcare providers retain the right to cancel appointments '
                  'in exceptional circumstances. In such cases, a full refund will be issued '
                  'automatically within 3 business days.',
            ),

            const _TermsSection(
              number: 7,
              title: 'Intellectual Property',
              body: 'All content, design, trademarks, logos, source code, and intellectual '
                  'property within MedNU belong to MedNU Healthcare Services Private Limited '
                  'or its licensors.\n\n'
                  'You may not reproduce, distribute, modify, or create derivative works '
                  'from any part of the App without our prior written permission. Unauthorised '
                  'use may result in account termination and legal action.',
            ),

            const _TermsSection(
              number: 8,
              title: 'Limitation of Liability',
              body: 'To the maximum extent permitted by applicable law, MedNU shall not be '
                  'liable for any indirect, incidental, special, consequential, or punitive '
                  'damages — including loss of profits, data, goodwill, or health outcomes — '
                  'arising out of or in connection with:\n\n'
                  '• Your use of or reliance on the App or its content\n'
                  '• Actions or advice of any healthcare provider on the platform\n'
                  '• Delays, errors, or outages in the technology infrastructure\n'
                  '• Unauthorised access to or alteration of your data',
            ),

            const _TermsSection(
              number: 9,
              title: 'Privacy',
              body: 'Your use of MedNU is also governed by our Privacy Policy, which is '
                  'incorporated into these Terms by reference. Please review it to understand '
                  'our data collection, use, and protection practices.\n\n'
                  'By using the App, you consent to the collection and use of your information '
                  'as described in the Privacy Policy.',
            ),

            const _TermsSection(
              number: 10,
              title: 'Governing Law',
              body: 'These Terms shall be governed by and construed in accordance with the '
                  'laws of India. Any disputes arising under or in connection with these Terms '
                  'shall be subject to the exclusive jurisdiction of the courts in Bengaluru, '
                  'Karnataka, India.',
            ),

            const _TermsSection(
              number: 11,
              title: 'Contact Information',
              body: 'For questions, concerns, or notices regarding these Terms:\n\n'
                  'MedNU Healthcare Services Private Limited\n'
                  'Email: legal@mednu.in\n'
                  'India',
              isLast: true,
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
