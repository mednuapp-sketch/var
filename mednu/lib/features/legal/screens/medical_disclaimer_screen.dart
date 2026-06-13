import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// Shown once on first launch. Users must accept before using the app.
/// Acceptance is recorded in SharedPreferences so it never shows again.
class MedicalDisclaimerScreen extends StatefulWidget {
  final VoidCallback onAccepted;
  const MedicalDisclaimerScreen({super.key, required this.onAccepted});

  static const _prefKey = 'mednu_disclaimer_accepted_v1';

  static Future<bool> hasAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> markAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  @override
  State<MedicalDisclaimerScreen> createState() => _MedicalDisclaimerScreenState();
}

class _MedicalDisclaimerScreenState extends State<MedicalDisclaimerScreen> {
  bool _hasScrolledToBottom = false;
  bool _isAccepting = false;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.atEdge &&
        _scrollController.position.pixels != 0) {
      if (!_hasScrolledToBottom) {
        setState(() => _hasScrolledToBottom = true);
      }
    }
  }

  Future<void> _accept() async {
    setState(() => _isAccepting = true);
    await MedicalDisclaimerScreen.markAccepted();
    widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha:0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.medical_information_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Medical Disclaimer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please read carefully before using MedNU',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha:0.85),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // ── Scrollable content ───────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Section(
                      icon: Icons.info_outline_rounded,
                      color: AppColors.info,
                      title: 'Not a Substitute for Professional Medical Advice',
                      body:
                          'MedNU is a healthcare facilitation platform designed to help you connect with licensed medical professionals and manage your health information. The content, tools, and services provided in this app are for informational purposes only.\n\n'
                          'MedNU does NOT provide medical diagnoses, prescriptions, or treatment plans. Nothing in this app should be construed as professional medical advice. Always consult a qualified, licensed healthcare provider for any medical condition, symptoms, or health concerns.',
                    ),
                    _Section(
                      icon: Icons.emergency_rounded,
                      color: AppColors.error,
                      title: 'Emergency Situations',
                      body:
                          'MedNU is NOT an emergency medical service. In case of a medical emergency, call your local emergency number (112 in India) or proceed to the nearest hospital immediately.\n\n'
                          'The ambulance and emergency features in MedNU are supplementary services and must not be relied upon as a primary response to life-threatening situations.',
                    ),
                    _Section(
                      icon: Icons.lock_outline_rounded,
                      color: AppColors.accent,
                      title: 'Your Health Data & Privacy',
                      body:
                          'MedNU collects and processes personal health information to facilitate consultations and health management. Your data is stored securely and is handled in accordance with our Privacy Policy.\n\n'
                          'By using this app you consent to the collection, storage, and processing of your health data as described in our Privacy Policy. You may request deletion of your account and data at any time from Settings.',
                    ),
                    _Section(
                      icon: Icons.verified_user_outlined,
                      color: AppColors.secondary,
                      title: 'Doctor Verification',
                      body:
                          'All doctors on the MedNU platform are required to submit valid medical registration credentials. While MedNU makes reasonable efforts to verify these credentials, we do not guarantee the accuracy, completeness, or currency of each doctor\'s qualifications.\n\n'
                          'You are encouraged to independently verify a doctor\'s credentials before initiating any consultation.',
                    ),
                    _Section(
                      icon: Icons.gavel_rounded,
                      color: AppColors.warning,
                      title: 'Limitation of Liability',
                      body:
                          'MedNU Healthcare Services Private Limited, its officers, employees, and partners shall not be liable for any direct, indirect, incidental, or consequential damages arising from:\n\n'
                          '• Use of or reliance on information within the app\n'
                          '• Actions or advice of any healthcare provider found on the platform\n'
                          '• Delays, errors, or failures in the technology infrastructure\n'
                          '• Any outcome of a medical consultation facilitated through MedNU',
                    ),
                    _Section(
                      icon: Icons.medication_outlined,
                      color: AppColors.primary,
                      title: 'Medication & Treatment',
                      body:
                          'Never start, stop, or change medication or treatment based solely on information from this app. Prescription medications can only be recommended by a licensed healthcare provider after proper evaluation.\n\n'
                          'If a doctor prescribes medication through a MedNU consultation, that prescription is the professional opinion of the individual doctor and not a recommendation from MedNU.',
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha:0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary.withValues(alpha:0.2)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded,
                              color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'By tapping "I Agree", you confirm that you have read and understood this disclaimer and agree to use MedNU in accordance with these terms.',
                              style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),

            // ── Accept button ────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_hasScrolledToBottom)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Scroll to read the full disclaimer',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textHint),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isAccepting ? null : _accept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isAccepting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Text(
                              'I Understand & Agree',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Poppins',
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _Section({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: AppTextStyles.labelLarge
                        .copyWith(color: AppColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(body,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary, height: 1.6)),
          const Divider(height: 24),
        ],
      ),
    );
  }
}
