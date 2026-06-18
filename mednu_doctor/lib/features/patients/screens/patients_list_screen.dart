import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';

class _PatientSummary {
  final String patientId;
  final String name;
  final int visitCount;
  final String lastVisitDate;
  final String lastCondition;

  const _PatientSummary({
    required this.patientId,
    required this.name,
    required this.visitCount,
    required this.lastVisitDate,
    required this.lastCondition,
  });
}

class PatientsListScreen extends StatefulWidget {
  const PatientsListScreen({super.key});
  @override
  State<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends State<PatientsListScreen> {
  String _search = '';
  String _debouncedSearch = '';
  Timer? _searchDebounce;

  static const _avatarColors = [
    Color(0xFFC2185B),
    Color(0xFF7B1FA2),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFFE65100),
    Color(0xFF00695C),
    Color(0xFF6A1B9A),
    Color(0xFF0277BD),
  ];

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      if (mounted) setState(() => _debouncedSearch = v);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  // Safe: guards against empty string → no codeUnitAt(0) crash
  Color _colorFor(String name) {
    if (name.isEmpty) return _avatarColors[0];
    return _avatarColors[name.codeUnitAt(0) % _avatarColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: 130,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -20,
                      right: -20,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha:0.06),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha:0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.people_rounded,
                                  color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'My Patients',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'All your consultation history',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: uid.isNotEmpty
            ? FirebaseFirestore.instance
                .collection('appointments')
                .where('doctorId', isEqualTo: uid)
                .orderBy('createdAt', descending: true)
                .limit(500)
                .snapshots()
            : const Stream.empty(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _buildSkeletonLoader();
          }
          if (snap.hasError) {
            debugPrint('[MyPatients] Firestore error: ${snap.error}');
            return AppErrorState(
              onRetry: () => setState(() {}),
            );
          }

          final docs = snap.data?.docs ?? [];

          final Map<String, _PatientSummary> seen = {};
          for (final doc in docs) {
            final d = doc.data();

            // Safely extract patientId — never trust Firestore field blindly
            final rawPid = (d['patientId'] as String? ?? '').trim();
            final pid = rawPid.isNotEmpty ? rawPid : doc.id;

            // Safely extract name — coalesce null AND empty string
            final rawName = (d['patientName'] as String? ?? '').trim();
            final name = rawName.isNotEmpty ? rawName : 'Patient';

            final condition =
                (d['consultationType'] as String? ?? '').trim().isNotEmpty
                    ? d['consultationType'] as String
                    : 'Consultation';
            final dateStr = d['date'] as String? ?? '';

            if (!seen.containsKey(pid)) {
              seen[pid] = _PatientSummary(
                patientId: pid,
                name: name,
                visitCount: 1,
                lastVisitDate: dateStr,
                lastCondition: condition,
              );
            } else {
              final existing = seen[pid]!;
              final isNewer = dateStr.compareTo(existing.lastVisitDate) > 0;
              seen[pid] = _PatientSummary(
                patientId: pid,
                name: name,
                visitCount: existing.visitCount + 1,
                lastVisitDate: isNewer ? dateStr : existing.lastVisitDate,
                lastCondition: isNewer ? condition : existing.lastCondition,
              );
            }
          }

          var patients = seen.values.toList()
            ..sort((a, b) => b.lastVisitDate.compareTo(a.lastVisitDate));

          if (_debouncedSearch.isNotEmpty) {
            final q = _debouncedSearch.toLowerCase();
            patients =
                patients.where((p) => p.name.toLowerCase().contains(q)).toList();
          }

          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search patients...',
                  prefixIcon:
                      Icon(Icons.search_rounded, color: AppColors.textHint),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                Text(
                  '${patients.length} Patient${patients.length == 1 ? '' : 's'}',
                  style: AppTextStyles.h4,
                ),
                const Spacer(),
                Text(
                  'Total Visits: ${patients.fold(0, (s, p) => s + p.visitCount)}',
                  style: AppTextStyles.bodySmall,
                ),
              ]),
            ),
            if (patients.isEmpty)
              Expanded(
                child: AppEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No Patients Yet',
                  message: 'Your patient list will appear here once you complete appointments.',
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: patients.length,
                  itemBuilder: (_, i) {
                    // Safe index — we know i < patients.length from itemCount
                    final p = patients[i];
                    final color = _colorFor(p.name);
                    String displayDate = p.lastVisitDate;
                    try {
                      final dt = DateTime.parse(p.lastVisitDate);
                      const months = [
                        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
                      ];
                      displayDate =
                          '${dt.day} ${months[dt.month - 1]} ${dt.year}';
                    } catch (_) {}

                    return FadeInSlide(
                      delay: Duration(milliseconds: i * 35),
                      child: TapScale(
                      onTap: () => context.push(
                        AppRoutes.patientDetail,
                        extra: {
                          'patientId': p.patientId,
                          'patientName': p.name,
                        },
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.divider),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha:0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha:0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                p.name.isNotEmpty
                                    ? p.name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name, style: AppTextStyles.labelLarge),
                                  Text(p.lastCondition,
                                      style: AppTextStyles.bodySmall),
                                  Text('Last visit: $displayDate',
                                      style: AppTextStyles.caption),
                                ]),
                          ),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha:0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${p.visitCount} visit${p.visitCount == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Icon(Icons.chevron_right_rounded,
                                    color: AppColors.textHint, size: 18),
                              ]),
                        ]),
                      ),
                    ));
                  },
                ),
              ),
          ]);
        },
      ),
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return Column(children: [
      const Padding(
        padding: EdgeInsets.all(16),
        child: SkeletonBox(width: double.infinity, height: 52, radius: 14),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          SkeletonBox(width: 100, height: 14, radius: 7),
          Spacer(),
          SkeletonBox(width: 80, height: 12, radius: 6),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 6,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SkeletonListTile(),
          ),
        ),
      ),
    ]);
  }

  // _buildEmptyState and _buildErrorState removed — replaced by AppEmptyState/AppErrorState
}
