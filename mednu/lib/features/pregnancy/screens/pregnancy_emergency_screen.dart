import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/pregnancy_provider.dart';

class PregnancyEmergencyScreen extends ConsumerStatefulWidget {
  const PregnancyEmergencyScreen({super.key});

  @override
  ConsumerState<PregnancyEmergencyScreen> createState() =>
      _PregnancyEmergencyScreenState();
}

class _PregnancyEmergencyScreenState
    extends ConsumerState<PregnancyEmergencyScreen> {
  bool _reporting = false;

  final List<Map<String, dynamic>> _emergencyTypes = [
    {
      'type': 'bleeding',
      'title': 'Vaginal Bleeding',
      'description': 'Any vaginal bleeding during pregnancy',
      'severity': 'critical',
      'icon': Icons.warning_rounded,
      'color': const Color(0xFFB71C1C),
      'bg': const Color(0xFFFFEBEE),
    },
    {
      'type': 'high_bp',
      'title': 'High Blood Pressure',
      'description': 'Severe headache, vision changes, facial swelling',
      'severity': 'critical',
      'icon': Icons.monitor_heart_rounded,
      'color': const Color(0xFFE53935),
      'bg': const Color(0xFFFFEBEE),
    },
    {
      'type': 'pain',
      'title': 'Severe Abdominal Pain',
      'description': 'Intense or persistent abdominal cramping',
      'severity': 'critical',
      'icon': Icons.sick_rounded,
      'color': const Color(0xFFE65100),
      'bg': const Color(0xFFFFF3E0),
    },
    {
      'type': 'no_movement',
      'title': 'No Baby Movement',
      'description': 'Decreased or no fetal movement after 20 weeks',
      'severity': 'high',
      'icon': Icons.child_care_rounded,
      'color': const Color(0xFFFF6F00),
      'bg': const Color(0xFFFFF3E0),
    },
    {
      'type': 'water_broke',
      'title': 'Water Broke',
      'description': 'Fluid leaking or gushing from vagina',
      'severity': 'high',
      'icon': Icons.water_drop_rounded,
      'color': const Color(0xFF1565C0),
      'bg': const Color(0xFFE3F2FD),
    },
    {
      'type': 'preterm_labor',
      'title': 'Preterm Labor Signs',
      'description': 'Regular contractions before 37 weeks',
      'severity': 'high',
      'icon': Icons.timer_rounded,
      'color': const Color(0xFF7B1FA2),
      'bg': const Color(0xFFF3E5F5),
    },
    {
      'type': 'fever',
      'title': 'High Fever',
      'description': 'Temperature above 38°C with chills',
      'severity': 'high',
      'icon': Icons.thermostat_rounded,
      'color': const Color(0xFFEF5350),
      'bg': const Color(0xFFFFEBEE),
    },
    {
      'type': 'other',
      'title': 'Other Emergency',
      'description': 'Any other urgent concern needing immediate attention',
      'severity': 'medium',
      'icon': Icons.crisis_alert_rounded,
      'color': const Color(0xFF616161),
      'bg': const Color(0xFFF5F5F5),
    },
  ];

  Future<void> _reportEmergency(Map<String, dynamic> emergencyType) async {
    final profile = ref.read(pregnancyProvider).profile;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (profile == null || uid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(emergencyType['icon'] as IconData,
                color: emergencyType['color'] as Color),
            const SizedBox(width: 8),
            Expanded(child: Text(emergencyType['title'] as String)),
          ],
        ),
        content: const Text(
            'This will alert your assigned doctor and MedNu medical team immediately. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB71C1C)),
            child: const Text('Report Emergency', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    setState(() => _reporting = true);

    try {
      // Get patient name from Firestore
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final patientName = userDoc.data()?['name'] as String? ?? 'Patient';

      final ok = await ref.read(pregnancyProvider.notifier).reportEmergency(
        type: emergencyType['type'] as String,
        severity: emergencyType['severity'] as String,
        message:
            '${emergencyType['title']}: ${emergencyType['description']}. Patient: $patientName. Week ${profile.currentWeek}.',
        patientName: patientName,
      );

      if (!mounted) return;
      if (ok) {
        _showSuccessSheet(emergencyType);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send alert. Please call emergency directly.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send alert. Please call emergency directly.')),
        );
      }
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  void _showSuccessSheet(Map<String, dynamic> type) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFB71C1C).withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFFB71C1C), size: 36),
            ),
            const SizedBox(height: 16),
            const Text('Emergency Alert Sent',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'Your doctor and MedNu team have been notified. They will contact you shortly.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textHint, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: const [
                  Icon(Icons.phone_rounded, color: Color(0xFFB71C1C)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('If condition worsens, call 112 or go to nearest hospital immediately.',
                        style: TextStyle(fontSize: 12, color: Color(0xFFB71C1C), height: 1.5)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text('Emergency Reporting',
            style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Warning banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.emergency_rounded, color: Colors.white, size: 32),
                      const SizedBox(height: 8),
                      const Text('Maternity Emergency Reporting',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      const Text(
                        'Select the type of emergency. Your doctor will be alerted immediately.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha:0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 6),
                            Text('For immediate danger, call 112',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Select Emergency Type',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _emergencyTypes.length,
                  itemBuilder: (context, i) => _emergencyCard(_emergencyTypes[i]),
                ),
                const SizedBox(height: 20),
                // Signs to watch
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 8)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_rounded, color: Color(0xFF7B1FA2), size: 18),
                          SizedBox(width: 8),
                          Text('Warning Signs Guide',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF7B1FA2))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...[
                        'Severe headache that doesn\'t go away',
                        'Blurred vision or seeing spots',
                        'Swelling of face, hands, or feet',
                        'Fever above 38°C',
                        'Painful urination or reduced urination',
                        'Chest pain or shortness of breath',
                        'Decreased baby movements',
                        'Vaginal bleeding or unusual discharge',
                      ].map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          const Icon(Icons.circle, size: 6, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(s, style: const TextStyle(fontSize: 12, height: 1.4))),
                        ]),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
          if (_reporting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Sending emergency alert...',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emergencyCard(Map<String, dynamic> e) {
    final color = e['color'] as Color;
    final bg = e['bg'] as Color;
    return GestureDetector(
      onTap: () => _reportEmergency(e),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha:0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(e['icon'] as IconData, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              e['title'] as String,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              e['severity'] as String == 'critical' ? '⚠️ CRITICAL' : '⚡ HIGH',
              style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
