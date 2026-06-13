import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Terms of Service'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.gavel_rounded, color: Colors.white, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Terms of Service',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        Text(
                          'Last updated: May 2025',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha:0.75),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _Section(
              title: '1. Acceptance of Terms',
              body: 'By downloading, installing, or using the MedNU application ("App"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, do not use the App.\n\nThese Terms constitute a legally binding agreement between you and MedNU Healthcare Services Private Limited ("Company", "we", "us").',
            ),
            _Section(
              title: '2. Eligibility',
              body: '• You must be at least 18 years of age to use MedNU independently\n'
                  '• You must have the legal capacity to enter into binding contracts\n'
                  '• You must provide accurate and complete registration information\n'
                  '• One person may not maintain multiple accounts\n'
                  '• Corporate or institutional accounts require separate agreements',
            ),
            _Section(
              title: '3. Services Provided',
              body: 'MedNU provides a healthcare facilitation platform including:\n\n'
                  '• Online doctor consultations (video and chat)\n'
                  '• Appointment booking with healthcare providers\n'
                  '• Medicine delivery coordination\n'
                  '• Diagnostic test booking\n'
                  '• Health tracking and records management\n'
                  '• Emergency service coordination\n\n'
                  'MedNU acts as an intermediary and is not itself a healthcare provider. All medical services are provided by independent, licensed practitioners.',
            ),
            _Section(
              title: '4. User Responsibilities',
              body: 'You agree to:\n\n'
                  '• Provide accurate health information to healthcare providers\n'
                  '• Use the App only for lawful purposes\n'
                  '• Not share your account credentials with others\n'
                  '• Not attempt to circumvent the App\'s security features\n'
                  '• Not upload false, misleading, or harmful content\n'
                  '• Treat healthcare providers with respect and professionalism\n'
                  '• Attend booked appointments or cancel with adequate notice',
            ),
            _Section(
              title: '5. Payments & Refunds',
              body: 'All payments are processed securely via Razorpay. By making a payment, you agree to Razorpay\'s Terms of Service.\n\n'
                  'Refund Policy:\n'
                  '• Cancelled appointments (>2 hours notice): Full refund within 5–7 business days\n'
                  '• Cancelled appointments (<2 hours notice): 50% refund\n'
                  '• Completed consultations: Non-refundable\n'
                  '• Technical failures: Full refund\n\n'
                  'Wallet credits are non-transferable and expire after 12 months of account inactivity.',
            ),
            _Section(
              title: '6. Healthcare Disclaimer',
              body: 'MedNU does not provide medical advice, diagnosis, or treatment. The platform facilitates access to licensed healthcare providers.\n\n'
                  'In case of a medical emergency, call 112 immediately. Do not rely on this app for emergency medical services.',
            ),
            _Section(
              title: '7. Intellectual Property',
              body: 'All content, trademarks, logos, and intellectual property in MedNU belong to MedNU Healthcare Services Private Limited. You may not reproduce, distribute, or create derivative works without written permission.',
            ),
            _Section(
              title: '8. Account Termination',
              body: 'We reserve the right to suspend or terminate accounts that:\n\n'
                  '• Violate these Terms\n'
                  '• Engage in fraudulent activity\n'
                  '• Harass or abuse healthcare providers\n'
                  '• Misuse platform features\n\n'
                  'You may delete your account at any time from Profile → Settings → Account → Delete Account.',
            ),
            _Section(
              title: '9. Limitation of Liability',
              body: 'To the maximum extent permitted by applicable law, MedNU shall not be liable for any indirect, incidental, special, consequential, or punitive damages, including loss of profits, data, or goodwill, arising out of or in connection with these Terms or your use of the App.',
            ),
            _Section(
              title: '10. Governing Law',
              body: 'These Terms shall be governed by the laws of India. Any disputes shall be subject to the exclusive jurisdiction of the courts in Hyderabad, Telangana, India.',
            ),
            _Section(
              title: '11. Changes to Terms',
              body: 'We may modify these Terms at any time. Continued use of the App after changes constitutes acceptance. For significant changes, we will provide 30 days\' notice via push notification or email.',
            ),
            _Section(
              title: '12. Contact',
              body: 'For questions about these Terms:\n\nMedNU Healthcare Services Private Limited\nEmail: legal@mednuhealthcare.in',
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTextStyles.labelLarge
                  .copyWith(color: AppColors.primary, fontSize: 15)),
          const SizedBox(height: 8),
          Text(body,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary, height: 1.65)),
          const Divider(height: 28),
        ],
      ),
    );
  }
}
