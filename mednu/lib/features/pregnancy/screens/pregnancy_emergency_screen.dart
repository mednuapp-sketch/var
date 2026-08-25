import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_text_styles.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../providers/pregnancy_provider.dart';

// --- Data ---------------------------------------------------------------------

enum _Severity { red, orange, yellow }

class _WarnSign {
  final String text;
  final _Severity severity;
  const _WarnSign(this.text, this.severity);
}

const _kWarnSigns = [
  _WarnSign('Heavy vaginal bleeding', _Severity.red),
  _WarnSign('Severe abdominal pain or cramping', _Severity.red),
  _WarnSign('No fetal movement for more than 24 hours', _Severity.red),
  _WarnSign(
      'Signs of preeclampsia: severe headache, blurred vision, face/hand swelling',
      _Severity.red),
  _WarnSign('Sudden fluid gush (water breaking prematurely)', _Severity.red),
  _WarnSign('Chest pain or difficulty breathing', _Severity.red),
  _WarnSign('Mild spotting or light discharge', _Severity.orange),
  _WarnSign('Mild abdominal cramps or pressure', _Severity.orange),
  _WarnSign('Persistent headache not relieved by rest', _Severity.orange),
  _WarnSign('Fever above 38�C', _Severity.orange),
  _WarnSign('Reduced baby movements (still moving, just less)', _Severity.orange),
  _WarnSign('Light nausea and vomiting', _Severity.yellow),
  _WarnSign('Mild lower back pain', _Severity.yellow),
  _WarnSign('Leg swelling at end of day', _Severity.yellow),
  _WarnSign('Mild round ligament pain (sharp side aches)', _Severity.yellow),
];

const _kHospitalSigns = [
  'Heavy or bright red vaginal bleeding',
  'No baby movement for over 2 hours after kick counting',
  'Severe and worsening abdominal pain',
  'Water breaking or fluid leaking continuously',
  'Contractions every 5 minutes or less before 37 weeks',
  'Vision loss, seeing spots, or sudden severe headache',
  'Loss of consciousness or convulsions',
  'High fever with stiff neck or rash',
];

// --- Screen ------------------------------------------------------------------

class PregnancyEmergencyScreen extends ConsumerStatefulWidget {
  const PregnancyEmergencyScreen({super.key});

  @override
  ConsumerState<PregnancyEmergencyScreen> createState() =>
      _PregnancyEmergencyScreenState();
}

class _PregnancyEmergencyScreenState
    extends ConsumerState<PregnancyEmergencyScreen>
    with SingleTickerProviderStateMixin {
  bool _reporting = false;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // -- tel: launcher ----------------------------------------------------------

  Future<void> _call(String number) async {
    final uri = Uri.parse('tel:$number');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot launch call to $number'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to call $number'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // -- SOS report -------------------------------------------------------------

  Future<void> _triggerSOS() async {
    HapticFeedback.heavyImpact();
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.emergency_rounded, color: Colors.red, size: 24),
            SizedBox(width: 10),
            Text('Send SOS Alert?'),
          ],
        ),
        content: const Text(
          'This will immediately alert your assigned doctor and the MedNU medical team. Please only use this in a genuine emergency.\n\nFor life-threatening emergencies, seek immediate emergency medical help.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.emergency_rounded, size: 16),
            label: const Text('Send SOS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    setState(() => _reporting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final profile = ref.read(pregnancyProvider).profile;

      String patientName = 'Patient';
      if (uid != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          patientName = doc.data()?['name'] as String? ?? 'Patient';
        } catch (_) {}
      }

      final ok = await ref.read(pregnancyProvider.notifier).reportEmergency(
        type: 'sos',
        severity: 'critical',
        message:
            'SOS Emergency triggered. Patient: $patientName. Week ${profile?.currentWeek ?? '?'}.',
        patientName: patientName,
      );

      if (!mounted) return;
      if (ok) {
        _showSOSSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Alert could not be sent. Please seek emergency medical help immediately.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Alert failed. Please seek emergency medical help immediately.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  void _showSOSSuccess() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appBackground,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Colors.red, size: 36),
            ),
            const SizedBox(height: 16),
            const Text('SOS Alert Sent', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            Text(
              'Your doctor and the MedNU team have been alerted.\nThey will contact you shortly.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: context.appTextHint, height: 1.6),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone_rounded, color: Colors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'If condition worsens, go to your nearest hospital immediately.',
                      style: AppTextStyles.bodySmall.copyWith(color: Colors.red, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('OK', style: AppTextStyles.button),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(pregnancyProvider).profile;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.appTextPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Emergency', style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text('Emergency',
                    style: AppTextStyles.labelSmall.copyWith(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // -- SOS Button ----------------------------------------------
                _buildSOSButton(),
                const SizedBox(height: 20),

                // -- Quick Dial ----------------------------------------------
                _buildQuickDial(profile),
                const SizedBox(height: 20),

                // -- Warning Signs -------------------------------------------
                _buildWarningSigns(),
                const SizedBox(height: 20),

                // -- When to go to hospital ----------------------------------
                _buildHospitalCard(),
                const SizedBox(height: 20),

                // -- Emergency contacts --------------------------------------
                if (profile != null) ...[
                  _buildEmergencyContacts(profile),
                  const SizedBox(height: 20),
                ],

                // -- Disclaimer ----------------------------------------------
                _buildDisclaimer(),
              ],
            ),
          ),
          // Loading overlay
          if (_reporting)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text('Sending emergency alert...',
                        style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -- SOS Button -------------------------------------------------------------

  Widget _buildSOSButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text('Need immediate help?',
              style: AppTextStyles.bodyMedium.copyWith(color: context.appTextSecondary)),
          const SizedBox(height: 16),
          // Pulsing SOS button
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer pulse ring
                  Container(
                    width: 110 + (_pulseCtrl.value * 16),
                    height: 110 + (_pulseCtrl.value * 16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red
                          .withValues(alpha: 0.1 - _pulseCtrl.value * 0.08),
                    ),
                  ),
                  // Inner ring
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withValues(alpha: 0.15),
                    ),
                  ),
                  child!,
                ],
              );
            },
            child: GestureDetector(
              onTap: _triggerSOS,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEF5350), Color(0xFFB71C1C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.emergency_rounded,
                        color: Colors.white, size: 30),
                    Text('SOS',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        )),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Tap to alert your doctor & MedNU team',
              style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
          const SizedBox(height: 4),
          Text('For life-threatening emergencies, seek immediate help',
              style: AppTextStyles.labelSmall.copyWith(color: Colors.red)),
        ],
      ),
    );
  }

  // -- Quick Dial -------------------------------------------------------------

  Widget _buildQuickDial(dynamic profile) {
    final contacts = [
      const _DialContact(
        label: 'Women\nHelpline',
        number: '181',
        icon: Icons.support_agent_rounded,
        color: Color(0xFF6A1B9A),
        gradient: LinearGradient(
          colors: [Color(0xFFAB47BC), Color(0xFF6A1B9A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      _DialContact(
        label: 'My Doctor',
        number: profile?.emergencyContactPhone ?? '',
        icon: Icons.medical_services_rounded,
        color: AppColors.primary,
        gradient: AppColors.pregnancyGrad,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          icon: Icons.phone_in_talk_rounded,
          title: 'Quick Dial',
          color: const Color(0xFF1565C0),
        ),
        const SizedBox(height: 10),
        staticGrid(
          crossAxisCount: 2,
          aspectRatio: 2.2,
          children: contacts.map(_buildDialCard).toList(),
        ),
      ],
    );
  }

  Widget _buildDialCard(_DialContact c) {
    return GestureDetector(
      onTap: () => _call(c.number),
      child: Container(
        decoration: BoxDecoration(
          gradient: c.gradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: c.color.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(c.icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    c.label,
                    maxLines: 2,
                    style: const TextStyle(fontFamily: 'Poppins', 
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  Text(
                    c.number,
                    style: const TextStyle(fontFamily: 'Poppins', 
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.call_rounded, color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  // -- Warning Signs ----------------------------------------------------------

  Widget _buildWarningSigns() {
    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: _sectionHeader(
              icon: Icons.warning_rounded,
              title: 'Warning Signs',
              color: Colors.red,
            ),
          ),
          // Legend
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                _legend(const Color(0xFFB71C1C), 'Urgent'),
                const SizedBox(width: 14),
                _legend(const Color(0xFFE65100), 'Call doctor now'),
                const SizedBox(width: 14),
                _legend(const Color(0xFFF9A825), 'Monitor closely'),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._kWarnSigns.map((s) => _buildWarnSignTile(s)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildWarnSignTile(_WarnSign sign) {
    Color dotColor;
    Color bgColor;
    String severityLabel;

    switch (sign.severity) {
      case _Severity.red:
        dotColor = const Color(0xFFB71C1C);
        bgColor = const Color(0xFFFFEBEE);
        severityLabel = 'Urgent';
        break;
      case _Severity.orange:
        dotColor = const Color(0xFFE65100);
        bgColor = const Color(0xFFFFF3E0);
        severityLabel = 'Call doctor';
        break;
      case _Severity.yellow:
        dotColor = const Color(0xFFF9A825);
        bgColor = const Color(0xFFFFFDE7);
        severityLabel = 'Monitor';
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              sign.text,
              style: TextStyle(fontFamily: 'Poppins', 
                fontSize: 12,
                color: context.appTextPrimary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: dotColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              severityLabel,
              style: TextStyle(
                fontSize: 9,
                color: dotColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- When to go to hospital -------------------------------------------------

  Widget _buildHospitalCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.local_hospital_rounded,
            title: 'Go to Hospital Immediately if:',
            color: Colors.red,
          ),
          const SizedBox(height: 12),
          ..._kHospitalSigns.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.arrow_right_rounded,
                        color: Colors.red, size: 18),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      s,
                      style: TextStyle(fontFamily: 'Poppins', 
                        fontSize: 12,
                        color: context.appTextPrimary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- Emergency contacts -----------------------------------------------------

  Widget _buildEmergencyContacts(dynamic profile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.contacts_rounded,
            title: 'Emergency Contacts',
            color: AppColors.secondary,
          ),
          const SizedBox(height: 12),
          if (profile.emergencyContactName.isNotEmpty ||
              profile.emergencyContactPhone.isNotEmpty)
            _buildContactTile(
              label: profile.emergencyContactName.isEmpty
                  ? 'Emergency Contact'
                  : profile.emergencyContactName,
              number: profile.emergencyContactPhone,
              icon: Icons.person_rounded,
              color: AppColors.secondary,
            ),
          if (profile.assignedDoctorName != null &&
              profile.assignedDoctorName!.isNotEmpty)
            _buildContactTile(
              label: 'Dr. ${profile.assignedDoctorName}',
              number: profile.emergencyContactPhone,
              icon: Icons.medical_services_rounded,
              color: AppColors.primary,
            ),
        ],
      ),
    );
  }

  Widget _buildContactTile({
    required String label,
    required String number,
    required IconData icon,
    required Color color,
    bool alwaysShow = false,
  }) {
    if (!alwaysShow && number.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontFamily: 'Poppins', 
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: context.appTextPrimary,
                  ),
                ),
                Text(
                  number,
                  style: TextStyle(fontFamily: 'Poppins', 
                    fontSize: 12,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _call(number),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.call_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // -- Disclaimer -------------------------------------------------------------

  Widget _buildDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFFF6F00).withValues(alpha: 0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              color: Color(0xFFE65100), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This screen is for informational and alert purposes only. In a life-threatening emergency, always seek immediate emergency medical help and do not wait for a digital response.',
              style: TextStyle(fontFamily: 'Poppins', 
                fontSize: 11,
                color: Color(0xFFE65100),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- helpers ----------------------------------------------------------------

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) =>
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontFamily: 'Poppins', 
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: context.appTextPrimary,
              ),
            ),
          ),
        ],
      );

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontFamily: 'Poppins', 
                fontSize: 9, color: context.appTextSecondary),
          ),
        ],
      );
}

// --- Data model ---------------------------------------------------------------

class _DialContact {
  final String label;
  final String number;
  final IconData icon;
  final Color color;
  final Gradient gradient;

  const _DialContact({
    required this.label,
    required this.number,
    required this.icon,
    required this.color,
    required this.gradient,
  });
}
