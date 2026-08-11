import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';

class PregnancyPatientsScreen extends StatefulWidget {
  const PregnancyPatientsScreen({super.key});

  @override
  State<PregnancyPatientsScreen> createState() =>
      _PregnancyPatientsScreenState();
}

class _PregnancyPatientsScreenState extends State<PregnancyPatientsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('Maternity Patients',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, fontFamily: 'Poppins')),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 13),
          tabs: const [
            Tab(text: 'My Patients'),
            Tab(text: 'Alerts'),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search patients...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                filled: true,
                fillColor: const Color(0xFFF7F4F8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildPatientsList(uid),
                _buildAlertsList(uid),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientsList(String doctorId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('pregnancy_profiles')
          .where('assignedDoctorId', isEqualTo: doctorId)
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return ListView(physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(16),
            children: List.generate(5, (_) => const Padding(padding: EdgeInsets.only(bottom: 12), child: SkeletonListTile())));
        }
        final docs = snap.data?.docs ?? [];
        final filtered = docs.where((d) {
          if (_search.isEmpty) return true;
          final data = d.data() as Map<String, dynamic>;
          final name = (data['patientName'] as String? ?? '').toLowerCase();
          return name.contains(_search);
        }).toList();

        if (filtered.isEmpty) {
          return _emptyState('No maternity patients assigned', 'Patients will appear here when assigned by admin');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filtered.length,
          itemBuilder: (context, i) {
            final d = filtered[i].data() as Map<String, dynamic>;
            return _patientCard(d, filtered[i].id);
          },
        );
      },
    );
  }

  Widget _patientCard(Map<String, dynamic> d, String profileId) {
    final lmpDate = (d['lmpDate'] as Timestamp?)?.toDate() ?? DateTime.now();
    final days = DateTime.now().difference(lmpDate).inDays;
    final week = (days / 7).floor().clamp(1, 42);
    final isHighRisk = d['isHighRisk'] as bool? ?? false;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.pregnancyPatientDetail, extra: {
        'profileId': profileId,
        'patientId': d['patientId'] as String? ?? '',
        'patientName': d['patientName'] as String? ?? 'Patient',
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isHighRisk ? const Color(0xFFEF5350).withValues(alpha:0.3) : AppColors.border,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 8)],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  ((d['patientName'] as String?) ?? '').isNotEmpty ? (d['patientName'] as String)[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        d['patientName'] as String? ?? 'Patient',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    if (isHighRisk)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('HIGH RISK',
                            style: TextStyle(fontSize: 9, color: Color(0xFFB71C1C), fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    _infoChip(Icons.pregnant_woman_rounded, 'Week $week', const Color(0xFFC2185B)),
                    const SizedBox(width: 6),
                    _infoChip(Icons.calendar_today_rounded,
                        'Due ${DateFormat('dd MMM').format((d['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now())}',
                        const Color(0xFF7B1FA2)),
                  ]),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsList(String doctorId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('pregnancy_alerts')
          .where('assignedDoctorId', isEqualTo: doctorId)
          .where('isResolved', isEqualTo: false)
          .orderBy('reportedAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return ListView(physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(16),
            children: List.generate(4, (_) => const Padding(padding: EdgeInsets.only(bottom: 12), child: SkeletonCard(height: 80))));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyState('No active alerts', 'Patient emergency alerts will appear here');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            return _alertCard(d, docs[i].id);
          },
        );
      },
    );
  }

  Widget _alertCard(Map<String, dynamic> d, String alertId) {
    final severity = d['severity'] as String? ?? 'medium';
    final color = severity == 'critical'
        ? const Color(0xFFB71C1C)
        : severity == 'high'
            ? const Color(0xFFE65100)
            : const Color(0xFFFFA726);
    final reportedAt = (d['reportedAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha:0.3)),
        boxShadow: [BoxShadow(color: color.withValues(alpha:0.08), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.crisis_alert_rounded, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(d['patientName'] as String? ?? 'Patient',
                    style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(severity.toUpperCase(),
                    style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(d['message'] as String? ?? '',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 12, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(DateFormat('dd MMM, hh:mm a').format(reportedAt),
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              const Spacer(),
              GestureDetector(
                onTap: () => _resolveAlert(alertId),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF66BB6A).withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF66BB6A).withValues(alpha:0.3)),
                  ),
                  child: const Text('Resolve',
                      style: TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _resolveAlert(String alertId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await FirebaseFirestore.instance
        .collection('pregnancy_alerts')
        .doc(alertId)
        .update({
      'isResolved': true,
      'resolvedBy': uid,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert resolved'), backgroundColor: Color(0xFF2E7D32)),
      );
    }
  }

  Widget _infoChip(IconData icon, String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
    ],
  );

  Widget _emptyState(String title, String subtitle) => AppEmptyState(
    icon: Icons.pregnant_woman_rounded,
    title: title,
    message: subtitle,
    iconColor: AppColors.primary,
  );
}
