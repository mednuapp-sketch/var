import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

/// Medical Disclaimer screen — standalone informational page accessible from
/// the Settings / Legal section. Not the first-launch gate.
class MedicalDisclaimerScreen extends StatelessWidget {
  const MedicalDisclaimerScreen({super.key});

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
          'Medical Disclaimer',
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
            // ── Warning header banner ─────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB300).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFE65100),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Important Medical Disclaimer',
                              style: TextStyle(fontFamily: 'Poppins', 
                                color: Color(0xFFBF360C),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Please read carefully before using MedNU',
                              style: TextStyle(fontFamily: 'Poppins', 
                                color: Color(0xFFE65100),
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── 1. Not a Substitute — red accent card ─────────────
            const _DisclaimerCard(
              accentColor: AppColors.error,
              icon: Icons.medical_services_outlined,
              title: 'Not a Substitute for Professional Medical Advice',
              body: 'MedNU is not a substitute for professional medical advice, diagnosis, '
                  'or treatment. The app facilitates access to licensed healthcare providers '
                  'but does not itself provide medical care or clinical opinions.\n\n'
                  'Always seek the advice of your physician or a qualified health professional '
                  'for any medical condition or health concern you may have.',
            ),

            const SizedBox(height: 12),

            // ── 2. Information Accuracy ───────────────────────────
            const _DisclaimerCard(
              accentColor: AppColors.info,
              icon: Icons.info_outline_rounded,
              title: 'Information Accuracy',
              body: 'Health content within MedNU is provided for general informational '
                  'purposes only. While we strive to keep information accurate and current, '
                  'medical knowledge evolves rapidly.\n\n'
                  'The content may not always reflect the most recent clinical guidelines, '
                  'research, or regulatory requirements. Do not make healthcare decisions '
                  'based solely on information found in this app.',
            ),

            const SizedBox(height: 12),

            // ── 3. Emergency Situations ───────────────────────────
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
                    // Header row
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
                            'Emergency Situations',
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
                      'If you have a medical emergency, seek immediate help from your '
                      'nearest hospital or emergency services. Do not use this app as a '
                      'primary response to a life-threatening situation.\n\n'
                      'The ambulance and emergency features in MedNU are supplementary '
                      'services only.',
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

            // ── 4. Consult Your Doctor ────────────────────────────
            const _DisclaimerCard(
              accentColor: AppColors.accent,
              icon: Icons.person_outlined,
              title: 'Consult Your Doctor',
              body: 'Never start, stop, or change medication or treatment based solely on '
                  'information from this app. Prescription medications can only be '
                  'recommended by a licensed healthcare provider after a proper evaluation.\n\n'
                  'Always consult a qualified healthcare professional before making any '
                  'decision related to your health, medical condition, or treatment.',
            ),

            const SizedBox(height: 12),

            // ── 5. Limitation of Liability ────────────────────────
            const _DisclaimerCard(
              accentColor: AppColors.warning,
              icon: Icons.gavel_rounded,
              title: 'Limitation of Liability',
              body: 'MedNU Healthcare Services Private Limited, its officers, employees, '
                  'and partners shall not be liable for any direct, indirect, incidental, '
                  'or consequential damages arising from:\n\n'
                  '• Use of or reliance on information within the app\n'
                  '• Actions or advice of any healthcare provider on the platform\n'
                  '• Delays, errors, or failures in the technology infrastructure\n'
                  '• Any outcome of a medical consultation facilitated through MedNU',
            ),

            const SizedBox(height: 24),

            // ── "I Have Read" acknowledgement button ─────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'By using MedNU you acknowledge that you have read and understood '
                      'this disclaimer and agree to use the app in accordance with its terms.',
                      style: TextStyle(fontFamily: 'Poppins',
                        color: context.appTextSecondary,
                        fontSize: 12,
                        height: 1.65,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => context.pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'I Have Read and Understand',
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DisclaimerCard extends StatelessWidget {
  final Color accentColor;
  final IconData icon;
  final String title;
  final String body;

  const _DisclaimerCard({
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
