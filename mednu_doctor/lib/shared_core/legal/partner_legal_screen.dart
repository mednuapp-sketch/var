import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// In-app Terms of Service / Partner Privacy Policy, so partners never leave
/// the app to read them. Content mirrors the hosted pages
/// (mednu.in/terms, mednu.in/partner-privacy-policy).
class PartnerLegalScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String intro;
  final IconData icon;
  final List<_LegalSection> sections;

  const PartnerLegalScreen._({
    required this.title,
    required this.subtitle,
    required this.intro,
    required this.icon,
    required this.sections,
  });

  static Future<void> openTerms(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _terms),
      );

  static Future<void> openPrivacy(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _privacy),
      );

  static const _terms = PartnerLegalScreen._(
    title: 'Terms of Service',
    subtitle: 'Last updated: 1 January 2025',
    intro: 'Please read these Terms carefully before using MedNU. By using the app '
        'you agree to be bound by these Terms.',
    icon: Icons.gavel_rounded,
    sections: [
      _LegalSection('About MedNU',
          'MedNU is a technology platform that connects patients with independent doctors, diagnostic centres, pharmacies, and other healthcare service providers. MedNU does not provide medical treatment, diagnosis, prescriptions, or healthcare services directly.'),
      _LegalSection('Eligibility',
          "You must be at least 18 years old to register and use the Platform. If registering a minor, the parent or legal guardian shall be responsible for the minor's use of the Platform."),
      _LegalSection('User Responsibility',
          'You agree to:\n\n• Provide accurate and complete information.\n• Maintain confidentiality of your login credentials and OTPs.\n• Use the Platform only for lawful purposes.\n• Provide correct medical history, reports, and health information.\n\nYou shall be solely responsible for any consequences arising from incorrect or incomplete information provided by you.'),
      _LegalSection('Telemedicine Consent',
          'By booking an online consultation, you consent to receive healthcare services through video, audio, or chat as permitted under applicable laws and Telemedicine Practice Guidelines.\n\nYou understand that online consultations have limitations and may require physical examination or further testing.'),
      _LegalSection('Diagnostics and Pharmacy Services',
          'Diagnostic tests and pharmacy services are provided by independent partner laboratories and pharmacies. MedNU is not responsible for the accuracy of test results, medicine availability, treatment outcomes, or delays caused by such partners.'),
      _LegalSection('Fees and Payments',
          'All applicable charges will be displayed before booking or purchase. Payments are processed through secure third-party payment gateways.\n\nRefunds and cancellations shall be governed by the applicable Refund and Cancellation Policy.'),
      _LegalSection('Privacy and Health Data',
          'Your personal and health information will be collected, stored, processed, and shared with relevant healthcare providers, laboratories, and pharmacies solely for providing requested services and in accordance with applicable laws and our Privacy Policy.'),
      _LegalSection('Emergency Disclaimer',
          'MedNU is not an emergency medical service.\n\nFor any medical emergency or life-threatening condition, immediately contact emergency services or visit the nearest hospital.'),
      _LegalSection('Limitation of Liability',
          'MedNU acts only as a facilitator platform.\n\nTo the maximum extent permitted by law, MedNU shall not be liable for:\n\n• Medical advice, diagnosis, treatment, prescriptions, or healthcare outcomes.\n• Acts, omissions, negligence, or misconduct of doctors, laboratories, pharmacies, or other service providers.\n• Indirect, incidental, consequential, or special damages arising from use of the Platform.'),
      _LegalSection('Suspension of Account',
          'MedNU reserves the right to suspend or terminate any account found to be violating these Terms, providing false information, or misusing the Platform.'),
      _LegalSection('Intellectual Property',
          'All trademarks, logos, software, content, and intellectual property associated with MedNU remain the exclusive property of MedNU and may not be copied or used without prior written permission.'),
      _LegalSection('Governing Law',
          'These Terms shall be governed by the laws of India and subject to the exclusive jurisdiction of the courts at Visakhapatnam, Andhra Pradesh.'),
      _LegalSection('Consent',
          'By clicking "I Accept", registering an account, or using the Platform, you confirm that:\n\n• You have read and understood these Terms.\n• You voluntarily agree to be legally bound by them.\n• You consent to electronic communications and electronic records.\n• You understand the nature and limitations of telemedicine and online healthcare services.\n• You agree to the collection and processing of your personal and health information for providing services through the Platform.'),
    ],
  );

  static const _privacy = PartnerLegalScreen._(
    title: 'Partner Privacy Policy',
    subtitle: 'Last updated: 30 September 2026',
    intro: 'This policy explains how MedNu collects, uses, and protects information '
        'about you as a verified service partner, and sets out your obligations '
        'regarding the patient information you access while providing services '
        'through the platform.',
    icon: Icons.privacy_tip_outlined,
    sections: [
      _LegalSection('Information We Collect',
          'We collect the information you provide when registering as a partner, including your name, phone number, email address, professional registration or license number, qualification documents, and government-issued ID used for verification. We also collect your practice or service details, banking details for earnings payout, location data (with your permission) for dispatch and service delivery, device identifiers, and usage analytics.'),
      _LegalSection('How We Use Your Information',
          'Your information is used to verify your professional credentials and onboard you as a partner, connect you with patient bookings and requests, coordinate consultation, lab, pharmacy, ambulance, or nurse dispatch, calculate and disburse your earnings, send schedule and booking notifications, improve the app, and comply with legal and regulatory record-keeping obligations for healthcare providers. We do not sell your data to third parties.'),
      _LegalSection('Patient Data You Access',
          'As a doctor, lab, pharmacy, ambulance, or nurse partner, you will access patient health information — such as symptoms, history, prescriptions, and contact or location details — in the course of providing a specific booked service.\n\nYou may only use patient information for the purpose of the booking it was shared for, must keep it confidential, and must not store, export, or reuse it outside the platform except as required to deliver that service or by law.'),
      _LegalSection('Data Sharing & Disclosure',
          'We share the relevant booking and contact details with the patient you are matched with, and with payment and technology partners who help us operate the platform — all bound by confidentiality obligations. We may also disclose information when required by law or to verify your professional standing with the relevant regulatory body.'),
      _LegalSection('Data Security',
          'We implement industry-standard security measures including TLS encryption in transit, encrypted storage for sensitive and patient data, role-based access controls, and regular security audits. No method of transmission over the internet is 100% secure, but we strive to protect your data and the patient data you access using best practices.'),
      _LegalSection('Your Rights',
          'You have the right to access, correct, or delete your personal and professional information at any time, subject to our regulatory record-keeping obligations. You may also withdraw consent for non-essential data processing or request data portability. To exercise these rights, contact us at mednuapp@gmail.com.'),
      _LegalSection('Account Eligibility',
          'MedNu Partner accounts are only issued to verified, licensed healthcare professionals and service providers aged 18 or over. We do not knowingly register minors as partners.'),
      _LegalSection('Changes to This Policy',
          'We may update this Privacy Policy from time to time. When we do, we will revise the "Last Updated" date and notify you through the app or via email. Continued use of the MedNu Partner app after changes constitutes acceptance of the updated policy.'),
      _LegalSection('App Permissions',
          'The MedNu Partner app requests the following device permissions. We only use each for the purpose described, and each is requested only when the related feature is used.\n\n• Location — ambulance and on-site service dispatch, showing nearby bookings\n• Camera — uploading prescriptions, lab reports, and verification documents\n• Photos / storage — attaching medical documents and reports to bookings\n• Microphone — voice notes and audio during teleconsultations\n• Biometric — face/fingerprint app unlock, if you enable it\n• Notifications — new booking, schedule, and earnings alerts'),
      _LegalSection('WhatsApp Notifications',
          "If you turn on WhatsApp updates in the Partner app, we use your registered phone number to send you service messages on WhatsApp — new booking requests, cancellations, appointment reminders, and payout confirmations. These messages are sent through the WhatsApp Business Platform operated by Meta Platforms, which processes your phone number and the message content to deliver them.\n\nMessages to you contain only what is needed to act on a booking (such as the patient's name and appointment time) and never include patient medical records. If you tap a button in a message (for example to accept or decline a booking), we record that reply to act on it. We keep a log of messages sent so we can avoid duplicates and troubleshoot delivery.\n\nWhatsApp updates are optional. You can turn them off at any time in the Partner app's Settings, and we will stop sending them; you will still receive updates inside the app."),
      _LegalSection('Questions?',
          'If you have questions about this policy, reach out to us at mednuapp@gmail.com.'),
    ],
  );

  static const _font = 'Poppins';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: AppColors.surface,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          title,
          style: const TextStyle(
              fontFamily: _font, color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              itemCount: sections.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == 0) return _header();
                return _SectionCard(number: i, section: sections[i - 1]);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
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
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontFamily: _font, color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              fontFamily: _font, color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 16, 2, 4),
            child: Text(intro,
                style: const TextStyle(
                    fontFamily: _font, color: AppColors.textSecondary, fontSize: 13, height: 1.7)),
          ),
        ],
      );
}

class _LegalSection {
  final String title;
  final String body;
  const _LegalSection(this.title, this.body);
}

class _SectionCard extends StatelessWidget {
  final int number;
  final _LegalSection section;
  const _SectionCard({required this.number, required this.section});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(number.toString().padLeft(2, '0'),
                    style: const TextStyle(
                        fontFamily: 'Poppins', color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(section.title,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(section.body,
              style: const TextStyle(
                  fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 13, height: 1.75)),
        ],
      ),
    );
  }
}
