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
  final _searchCtrl = TextEditingController();

  void _onSearchChanged(String v) {
    setState(() => _search = v);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _debouncedSearch = v);
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _search = '';
      _debouncedSearch = '';
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          GradientSliverAppBar(
            headerIcon: Icons.people_rounded,
            title: 'My Patients',
            subtitle: 'All consultation history',
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
              return _buildSkeleton();
            }
            if (snap.hasError) {
              return AppErrorState(onRetry: () => setState(() {}));
            }

            final docs = snap.data?.docs ?? [];
            final Map<String, _PatientSummary> seen = {};

            for (final doc in docs) {
              final d = doc.data();
              final rawPid = (d['patientId'] as String? ?? '').trim();
              final pid = rawPid.isNotEmpty ? rawPid : doc.id;
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
                  lastVisitDate:
                      isNewer ? dateStr : existing.lastVisitDate,
                  lastCondition:
                      isNewer ? condition : existing.lastCondition,
                );
              }
            }

            var patients = seen.values.toList()
              ..sort((a, b) => b.lastVisitDate.compareTo(a.lastVisitDate));

            if (_debouncedSearch.isNotEmpty) {
              final q = _debouncedSearch.toLowerCase();
              patients = patients
                  .where((p) => p.name.toLowerCase().contains(q))
                  .toList();
            }

            final totalVisits =
                patients.fold(0, (s, p) => s + p.visitCount);

            return Column(children: [
              // ── Stats Banner ───────────────────────────────
              FadeInSlide(
                child: _StatsBanner(
                  totalPatients: seen.values.length,
                  totalVisits: docs.length,
                  repeatPatients: seen.values
                      .where((p) => p.visitCount > 1)
                      .length,
                ),
              ),

              // ── Search Bar ────────────────────────────────
              FadeInSlide(
                delay: const Duration(milliseconds: 60),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search by patient name...',
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.textHint),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: AppColors.textHint, size: 18),
                              onPressed: _clearSearch,
                            )
                          : null,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Count Row ─────────────────────────────────
              FadeInSlide(
                delay: const Duration(milliseconds: 80),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Text(
                      '${patients.length} Patient${patients.length == 1 ? '' : 's'}',
                      style: AppTextStyles.h4,
                    ),
                    const Spacer(),
                    InfoChip(
                      icon: Icons.repeat_rounded,
                      label: '$totalVisits total visits',
                      color: AppColors.secondary,
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // ── List ──────────────────────────────────────
              if (patients.isEmpty)
                Expanded(
                  child: AppEmptyState(
                    icon: Icons.people_outline_rounded,
                    title: _debouncedSearch.isNotEmpty
                        ? 'No results found'
                        : 'No Patients Yet',
                    message: _debouncedSearch.isNotEmpty
                        ? 'No patients match "$_debouncedSearch".'
                        : 'Your patient list appears once you complete appointments.',
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    itemCount: patients.length,
                    itemBuilder: (_, i) {
                      final p = patients[i];
                      String displayDate = p.lastVisitDate;
                      try {
                        final dt = DateTime.parse(p.lastVisitDate);
                        const months = [
                          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
                        ];
                        displayDate =
                            '${dt.day} ${months[dt.month - 1]} ${dt.year}';
                      } catch (_) {}

                      return FadeInSlide(
                        delay: Duration(milliseconds: i * 35),
                        child: _PatientCard(
                          patient: p,
                          displayDate: displayDate,
                          onTap: () => context.push(
                            AppRoutes.patientDetail,
                            extra: {
                              'patientId': p.patientId,
                              'patientName': p.name,
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return Column(children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SkeletonBox(width: double.infinity, height: 80, radius: 16),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SkeletonBox(width: double.infinity, height: 52, radius: 14),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(children: [
          SkeletonBox(width: 120, height: 14, radius: 7),
          Spacer(),
          SkeletonBox(width: 90, height: 12, radius: 6),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 6,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SkeletonCard(height: 76),
          ),
        ),
      ),
    ]);
  }
}

// ──────────────────────────────────────────────────────────────
// Stats Banner
// ──────────────────────────────────────────────────────────────

class _StatsBanner extends StatelessWidget {
  final int totalPatients;
  final int totalVisits;
  final int repeatPatients;

  const _StatsBanner({
    required this.totalPatients,
    required this.totalVisits,
    required this.repeatPatients,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(children: [
        _StatItem(
          value: '$totalPatients',
          label: 'Patients',
          icon: Icons.people_rounded,
        ),
        _Divider(),
        _StatItem(
          value: '$totalVisits',
          label: 'Consultations',
          icon: Icons.video_call_rounded,
        ),
        _Divider(),
        _StatItem(
          value: repeatPatients > 0 ? '$repeatPatients' : '—',
          label: 'Returning',
          icon: Icons.repeat_rounded,
        ),
      ]),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  const _StatItem(
      {required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: Colors.white60,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 40,
        color: Colors.white.withValues(alpha: 0.2),
      );
}

// ──────────────────────────────────────────────────────────────
// Patient Card
// ──────────────────────────────────────────────────────────────

class _PatientCard extends StatelessWidget {
  final _PatientSummary patient;
  final String displayDate;
  final VoidCallback onTap;

  const _PatientCard({
    required this.patient,
    required this.displayDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      radius: 16,
      onTap: onTap,
      child: Row(children: [
        AppAvatar(name: patient.name, size: 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(patient.name, style: AppTextStyles.labelLarge),
              const SizedBox(height: 2),
              Text(
                patient.lastCondition,
                style: AppTextStyles.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 11, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text(
                  'Last visit: $displayDate',
                  style: AppTextStyles.caption,
                ),
              ]),
            ],
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${patient.visitCount} visit${patient.visitCount == 1 ? '' : 's'}',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textHint, size: 18),
        ]),
      ]),
    );
  }
}
