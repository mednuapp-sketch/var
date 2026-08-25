import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../../core/widgets/ux_widgets.dart';

class PatientDetailScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

  const PatientDetailScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _callPatient(BuildContext context, String resolvedName, String photoUrl) {
    final uid = DoctorAuthService.currentUid;
    if (uid == null || widget.patientId.isEmpty) return;
    context.push(
      AppRoutes.outgoingCall,
      extra: {
        'patientId': widget.patientId,
        'patientName': resolvedName,
        'patientPhotoUrl': photoUrl,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.patientId.isNotEmpty
          ? FirebaseFirestore.instance
              .collection('users')
              .doc(widget.patientId)
              .snapshots()
          : const Stream.empty(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() ?? {};
        final name = userData['name'] as String? ?? widget.patientName;
        final patientPhotoUrl = userData['photoUrl'] as String? ?? '';
        final dob = userData['dob'] as String? ?? '';
        final gender = userData['gender'] as String? ?? '';

        int? age;
        if (dob.isNotEmpty) {
          try {
            final dt = DateTime.parse(dob);
            age = DateTime.now().year - dt.year;
          } catch (_) {}
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              // ── Gradient header ──────────────────────────────────────
              Container(
                decoration:
                    const BoxDecoration(gradient: AppColors.primaryGradient),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      // Top app-bar row
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white),
                            onPressed: () => context.safeBack(),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.receipt_long_rounded,
                                color: Colors.white),
                            tooltip: 'Write Prescription',
                            onPressed: () => context.push(
                              AppRoutes.prescription,
                              extra: {
                                'patientId': widget.patientId,
                                'patientName': name,
                                'allowOffline': true,
                              },
                            ),
                          ),
                        ],
                      ),
                      // Avatar + name + chips
                      const SizedBox(height: 4),
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 2.5),
                        ),
                        child: Center(
                          child: name.isNotEmpty
                              ? Text(
                                  name
                                      .trim()
                                      .split(' ')
                                      .take(2)
                                      .map((w) =>
                                          w.isNotEmpty ? w[0].toUpperCase() : '')
                                      .join(),
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1,
                                  ),
                                )
                              : const Icon(Icons.person_rounded,
                                  size: 38, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (age != null)
                            _HeaderChip(
                                icon: Icons.cake_rounded, label: '$age yrs'),
                          if (age != null && gender.isNotEmpty)
                            const SizedBox(width: 8),
                          if (gender.isNotEmpty)
                            _HeaderChip(
                                icon: gender.toLowerCase() == 'female'
                                    ? Icons.female_rounded
                                    : Icons.male_rounded,
                                label: gender),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Tab bar
                      TabBar(
                        controller: _tab,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white60,
                        indicatorColor: Colors.white,
                        indicatorWeight: 3,
                        labelStyle: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                        unselectedLabelStyle: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w400),
                        tabs: const [
                          Tab(text: 'Overview'),
                          Tab(text: 'History'),
                          Tab(text: 'Prescriptions'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // ── Tab content fills remaining space ─────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _buildOverview(userData),
                    _buildHistory(uid),
                    _buildPrescriptions(name),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Call Patient button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _callPatient(context, name, patientPhotoUrl),
                      icon: const Icon(Icons.video_call_rounded, size: 18),
                      label: const Text('Call Now'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(
                            color: AppColors.primary, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        textStyle: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Write Prescription button
                  Expanded(
                    child: GradientButton(
                      label: 'Prescribe',
                      icon: Icons.receipt_long_rounded,
                      height: 50,
                      onTap: () => context.push(
                        AppRoutes.prescription,
                        extra: {
                          'patientId': widget.patientId,
                          'patientName': name,
                          'allowOffline': true,
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverview(Map<String, dynamic> userData) {
    final isPremium = userData['isPremium'] as bool? ?? false;
    final familyList = (userData['familyMembers'] as List?) ?? [];
    final familyCount = familyList.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        // Patient summary card
        const _SectionTitle('Patient Summary'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Row(
            children: [
              _SummaryTile(
                icon: Icons.verified_rounded,
                color: isPremium ? AppColors.warning : AppColors.secondary,
                label: 'Status',
                value: isPremium ? 'Premium' : 'Standard',
              ),
              _verticalDivider(),
              _SummaryTile(
                icon: Icons.family_restroom_rounded,
                color: AppColors.primary,
                label: 'Family',
                value: '$familyCount member${familyCount == 1 ? '' : 's'}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Family members section
        if (familyList.isNotEmpty) ...[
          const _SectionTitle('Family Members'),
          const SizedBox(height: 10),
          ...familyList.map<Widget>((m) {
            final member = m as Map<String, dynamic>;
            final mName = member['name'] as String? ?? 'Member';
            final relation = member['relation'] as String? ?? '';
            final mAge = member['age']?.toString() ?? '';
            return PremiumCard(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              radius: 16,
              child: Row(children: [
                AppAvatar(name: mName, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(mName, style: AppTextStyles.labelMedium),
                        if (relation.isNotEmpty || mAge.isNotEmpty)
                          Text(
                            [
                              if (relation.isNotEmpty) relation,
                              if (mAge.isNotEmpty) '$mAge yrs'
                            ].join(' • '),
                            style: AppTextStyles.caption,
                          ),
                      ]),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    relation.isNotEmpty ? relation : 'Member',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ]),
            );
          }),
          const SizedBox(height: 20),
        ],

        // Vitals section
        const _SectionTitle('Vitals'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha:0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha:0.15)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.monitor_heart_rounded,
                    color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Vitals Recorded',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Vitals will appear here once the patient submits them through the MedNU app.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistory(String doctorUid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.patientId.isNotEmpty
          ? FirebaseFirestore.instance
              .collection('appointments')
              .where('doctorId', isEqualTo: doctorUid)
              .where('patientId', isEqualTo: widget.patientId)
              .snapshots()
          : const Stream.empty(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return ListView(physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(vertical: 8),
            children: List.generate(5, (_) => const SkeletonListTile()));
        }
        final docs = snap.data?.docs ?? [];
        docs.sort((a, b) {
          final aDate = a.data()['date'] as String? ?? '';
          final bDate = b.data()['date'] as String? ?? '';
          return bDate.compareTo(aDate);
        });

        if (docs.isEmpty) {
          return const AppEmptyState(
            icon: Icons.history_rounded,
            title: 'No History Yet',
            message: 'Consultations with this patient will appear here.',
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            const _SectionTitle('Consultation History'),
            const SizedBox(height: 10),
            ...docs.map((doc) {
              final d = doc.data();
              final dateStr = d['date'] as String? ?? '';
              final time = d['time'] as String? ?? '';
              final type = d['consultationType'] as String? ?? 'Consultation';
              final status = d['status'] as String? ?? '';
              String displayDate = dateStr;
              try {
                displayDate =
                    DateFormat('d MMM yyyy').format(DateTime.parse(dateStr));
              } catch (_) {}

              Color statusColor = AppColors.primary;
              if (status == 'completed') statusColor = AppColors.success;
              if (status == 'cancelled') statusColor = AppColors.error;

              return PremiumCard(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                radius: 16,
                child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.15),
                          AppColors.secondary.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      type.toLowerCase().contains('video')
                          ? Icons.video_call_rounded
                          : Icons.medical_services_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$type Consultation',
                              style: AppTextStyles.labelLarge),
                          const SizedBox(height: 2),
                          Text('$displayDate  •  $time',
                              style: AppTextStyles.bodySmall),
                        ]),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.isEmpty
                          ? '—'
                          : status[0].toUpperCase() + status.substring(1),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ]),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildPrescriptions(String patientName) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.patientId.isNotEmpty
          ? FirebaseFirestore.instance
              .collection('prescriptions')
              .where('patientId', isEqualTo: widget.patientId)
              .orderBy('createdAt', descending: true)
              .limit(20)
              .snapshots()
          : const Stream.empty(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return ListView(physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(vertical: 8),
            children: List.generate(5, (_) => const SkeletonListTile()));
        }
        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return AppEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No Prescriptions',
            message: 'Prescriptions you write for this patient will appear here.',
            actionLabel: 'Write Prescription',
            onAction: () => context.push(
              AppRoutes.prescription,
              extra: {
                'patientId': widget.patientId,
                'patientName': widget.patientName,
                'allowOffline': true,
              },
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            const _SectionTitle('Prescriptions Written'),
            const SizedBox(height: 10),
            ...docs.map((doc) {
              final d = doc.data();
              final diagnosis =
                  d['diagnosis'] as String? ?? 'Diagnosis not specified';
              final medicines = (d['medicines'] as List?)?.length ?? 0;
              final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
              String dateStr = '';
              if (createdAt != null) {
                dateStr = DateFormat('d MMM yyyy').format(createdAt);
              }
              return PremiumCard(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                radius: 16,
                child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.secondary.withValues(alpha: 0.15),
                          AppColors.primary.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: AppColors.secondary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(diagnosis,
                              style: AppTextStyles.labelLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            '$medicines medicine${medicines == 1 ? '' : 's'}${dateStr.isNotEmpty ? '  •  $dateStr' : ''}',
                            style: AppTextStyles.bodySmall,
                          ),
                        ]),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textHint),
                ]),
              );
            }),
          ],
        );
      },
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  Widget _verticalDivider() => Container(
        width: 1,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: AppColors.divider,
      );
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeaderChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha:0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ]),
      );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 3,
            height: 18,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      );
}

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _SummaryTile(
      {required this.icon,
      required this.color,
      required this.label,
      required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  )),
              Text(value,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
            ]),
          ),
        ]),
      );
}

