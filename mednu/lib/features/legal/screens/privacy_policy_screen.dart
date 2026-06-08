import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
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
            // ── Header card ───────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.privacy_tip_rounded,
                      color: Colors.white, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MedNU Privacy Policy',
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
                            color: Colors.white.withOpacity(0.75),
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

            _PolicySection(
              title: '1. Information We Collect',
              body: 'We collect information you provide directly, including:\n\n'
                  '• Personal identification (name, phone number, email)\n'
                  '• Health and medical information (symptoms, records, prescriptions)\n'
                  '• Location data (for finding nearby doctors and hospitals)\n'
                  '• Payment information (processed securely via Razorpay)\n'
                  '• Device information (for app functionality and security)\n'
                  '• Usage data (screens visited, features used)',
            ),
            _PolicySection(
              title: '2. How We Use Your Information',
              body: 'Your information is used to:\n\n'
                  '• Facilitate medical consultations and appointments\n'
                  '• Connect you with qualified healthcare providers\n'
                  '• Send appointment reminders and health alerts\n'
                  '• Process payments for services\n'
                  '• Improve the app and develop new features\n'
                  '• Comply with legal and regulatory obligations',
            ),
            _PolicySection(
              title: '3. Data Sharing',
              body: 'We do NOT sell your personal data. We share data only with:\n\n'
                  '• Healthcare providers you choose to consult\n'
                  '• Payment processors (Razorpay) for transaction completion\n'
                  '• Firebase/Google (cloud infrastructure and analytics)\n'
                  '• Legal authorities when required by law\n\n'
                  'All third-party services we use are bound by their own privacy policies and data protection agreements.',
            ),
            _PolicySection(
              title: '4. Data Security',
              body: 'We implement industry-standard security measures:\n\n'
                  '• All data transmitted over HTTPS/TLS encryption\n'
                  '• Firebase Security Rules restrict unauthorized access\n'
                  '• Sensitive credentials stored using secure, encrypted storage\n'
                  '• Biometric authentication option for app access\n'
                  '• Regular security audits and access controls',
            ),
            _PolicySection(
              title: '5. Data Retention',
              body: 'We retain your data for as long as your account is active or as needed to provide services. Medical records may be retained for the legally required period (typically 7 years in India). Upon account deletion, your personal data is removed within 30 days, except where retention is required by law.',
            ),
            _PolicySection(
              title: '6. Your Rights',
              body: 'You have the right to:\n\n'
                  '• Access your personal data\n'
                  '• Correct inaccurate information\n'
                  '• Request deletion of your account and data\n'
                  '• Opt out of non-essential communications\n'
                  '• Export your health records\n\n'
                  'To exercise these rights, go to Profile → Settings → Account → Delete Account, or contact us at privacy@mednuhealthcare.in',
            ),
            _PolicySection(
              title: '7. Children\'s Privacy',
              body: 'MedNU is intended for users aged 18 and above. We do not knowingly collect data from children under 13. Family members (including minors) may be managed through a parent\'s account under the Family Management feature.',
            ),
            _PolicySection(
              title: '8. Cookies & Analytics',
              body: 'The MedNU app uses Firebase Analytics to understand how users interact with the app. This helps us improve the user experience. Analytics data is anonymized and aggregated. You can opt out of analytics from Settings → Privacy.',
            ),
            _PolicySection(
              title: '9. Changes to This Policy',
              body: 'We may update this Privacy Policy periodically. We will notify you of significant changes via push notification or in-app alert. Continued use of the app after changes constitutes acceptance of the updated policy.',
            ),
            _PolicySection(
              title: '10. Contact Us',
              body: 'For privacy-related queries or data requests:\n\n'
                  'MedNU Healthcare Services Private Limited\n'
                  'Email: privacy@mednuhealthcare.in\n'
                  'Address: India',
            ),
            const SizedBox(height: 20),
            Center(
              child: TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('mailto:privacy@mednuhealthcare.in'),
                ),
                icon: const Icon(Icons.email_outlined),
                label: const Text('Contact Privacy Team'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String body;
  const _PolicySection({required this.title, required this.body});

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
