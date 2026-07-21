import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/operation_logger.dart';
import '../../auth/providers/auth_provider.dart';
import 'family_management_screen.dart';
import '../../../core/utils/r.dart';

class FamilyMemberDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> member;
  const FamilyMemberDetailScreen({super.key, required this.member});

  @override
  ConsumerState<FamilyMemberDetailScreen> createState() => _FamilyMemberDetailScreenState();
}

class _FamilyMemberDetailScreenState extends ConsumerState<FamilyMemberDetailScreen> {
  static const _avatarColors = [
    Color(0xFFC2185B), Color(0xFF7B1FA2), Color(0xFF1565C0),
    Color(0xFF2E7D32), Color(0xFF00695C), Color(0xFFE65100),
  ];

  Color _colorFor(String name) =>
      _avatarColors[name.isNotEmpty ? name.codeUnitAt(0) % _avatarColors.length : 0];

  // Live record counts
  StreamSubscription? _prescCountSub;
  StreamSubscription? _consultCountSub;
  StreamSubscription? _reportCountSub;
  int _prescCount = 0;
  int _consultCount = 0;
  int _reportCount = 0;
  bool _prescLoaded = false;
  bool _consultLoaded = false;
  bool _reportLoaded = false;
  bool get _countsLoaded => _prescLoaded && _consultLoaded && _reportLoaded;

  @override
  void initState() {
    super.initState();
    _subscribeRecordCounts();
  }

  void _subscribeRecordCounts() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final memberId = widget.member['id'] as String?;
    if (memberId == null) return;

    _prescCountSub = FirebaseFirestore.instance
        .collection('prescriptions')
        .where('patientId', isEqualTo: uid)
        .where('memberId', isEqualTo: memberId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _prescCount = snap.docs.length;
        _prescLoaded = true;
      });
    });

    _consultCountSub = FirebaseFirestore.instance
        .collection('consultations')
        .where('patientId', isEqualTo: uid)
        .where('memberId', isEqualTo: memberId)
        .where('status', isEqualTo: 'ended')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _consultCount = snap.docs.length;
        _consultLoaded = true;
      });
    });

    _reportCountSub = FirebaseFirestore.instance
        .collection('reports')
        .where('patientId', isEqualTo: uid)
        .where('memberId', isEqualTo: memberId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _reportCount = snap.docs.length;
        _reportLoaded = true;
      });
    });
  }

  @override
  void dispose() {
    _prescCountSub?.cancel();
    _consultCountSub?.cancel();
    _reportCountSub?.cancel();
    super.dispose();
  }

  void _openRecords(int tab) {
    context.push(AppRoutes.records, extra: {
      'memberId':   widget.member['id'] as String? ?? '',
      'memberName': widget.member['name'] as String? ?? '',
      'tab': tab,
    });
  }

  Future<void> _removeMember(BuildContext context, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(dialogCtx, 20))),
        title: const Text('Remove Member',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text('Remove $name from your family?',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Remove', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await ref.read(authProvider.notifier).removeFamilyMember(widget.member);
      OperationLogger.logSuccess(
        action: OpAction.familyMemberDeleted,
        message: 'Removed family member: $name',
      );
      if (context.mounted) context.pop();
    } catch (e) {
      OperationLogger.logError(
        action: OpAction.familyMemberDeleted,
        errorDetails: e.toString(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name     = widget.member['name']     as String? ?? '';
    final relation = widget.member['relation'] as String? ?? '';
    final age      = widget.member['age'];
    final gender   = widget.member['gender']   as String? ?? '';
    final phone    = widget.member['phone']    as String? ?? '';
    final color    = _colorFor(name);
    final initial  = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final uid      = ref.watch(authProvider).user?.uid ?? '';

    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: R.h(context, 210),
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: Colors.white),
                onPressed: () => showAddFamilyMemberSheet(context, ref, uid, existing: widget.member),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                tooltip: 'Remove Member',
                onPressed: () => _removeMember(context, name),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha:0.65)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(right: -30, top: -30,
                        child: Container(width: R.w(context, 140), height: R.h(context, 140),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.07), shape: BoxShape.circle))),
                    Positioned(left: -20, bottom: -20,
                        child: Container(width: R.w(context, 100), height: R.h(context, 100),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.05), shape: BoxShape.circle))),
                    SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: constraints.maxHeight),
                              child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40),
                          Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha:0.22),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: Center(child: Text(initial,
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 32,
                                    fontWeight: FontWeight.w700, color: Colors.white))),
                          ),
                          const SizedBox(height: 10),
                          Text(name, style: const TextStyle(fontFamily: 'Poppins', fontSize: 20,
                              fontWeight: FontWeight.w700, color: Colors.white)),
                          Text(relation, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white70)),
                        ],
                      ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Basic Info
                  _SectionCard(
                    title: 'Basic Information',
                    icon: Icons.person_rounded,
                    color: color,
                    child: Column(children: [
                      _InfoRow(icon: Icons.cake_rounded, label: 'Age',
                          value: age != null && age != 0 ? '$age years' : 'Not set'),
                      const Divider(height: 1, indent: 48),
                      _InfoRow(icon: Icons.wc_rounded, label: 'Gender',
                          value: gender.isNotEmpty ? gender : 'Not set'),
                      const Divider(height: 1, indent: 48),
                      _InfoRow(icon: Icons.phone_rounded, label: 'Phone',
                          value: phone.isNotEmpty ? phone : 'Not set'),
                    ]),
                  ),

                  const SizedBox(height: 20),

                  // Quick Actions
                  Text('Quick Actions', style: AppTextStyles.h4),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _ActionButton(
                      icon: Icons.calendar_month_rounded,
                      label: 'Book\nAppointment',
                      color: const Color(0xFF1565C0),
                      onTap: () => context.push(AppRoutes.appointment),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionButton(
                      icon: Icons.medication_rounded,
                      label: 'Order\nMedicine',
                      color: const Color(0xFF2E7D32),
                      onTap: () => context.push(AppRoutes.medicine),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionButton(
                      icon: Icons.science_rounded,
                      label: 'Book\nTest',
                      color: const Color(0xFF00695C),
                      onTap: () => context.push(AppRoutes.diagnostics),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionButton(
                      icon: Icons.video_call_rounded,
                      label: 'Video\nConsult',
                      color: AppColors.primary,
                      onTap: () => context.push(AppRoutes.consultation),
                    )),
                  ]),

                  const SizedBox(height: 20),

                  // Health Records
                  _SectionCard(
                    title: 'Health Records',
                    icon: Icons.folder_rounded,
                    color: const Color(0xFF2E7D32),
                    child: Column(children: [
                      _RecordTile(
                        icon: Icons.receipt_long_rounded,
                        label: 'Prescriptions',
                        sub: _countsLoaded
                            ? (_prescCount == 0 ? 'No prescriptions yet' : '$_prescCount prescription${_prescCount == 1 ? '' : 's'}')
                            : 'Loading...',
                        color: const Color(0xFFC2185B),
                        onTap: () => _openRecords(0),
                      ),
                      const Divider(height: 1, indent: 52),
                      _RecordTile(
                        icon: Icons.science_rounded,
                        label: 'Lab Reports',
                        sub: _countsLoaded
                            ? (_reportCount == 0 ? 'No reports yet' : '$_reportCount report${_reportCount == 1 ? '' : 's'}')
                            : 'Loading...',
                        color: const Color(0xFF0097A7),
                        onTap: () => _openRecords(1),
                      ),
                      const Divider(height: 1, indent: 52),
                      _RecordTile(
                        icon: Icons.video_call_rounded,
                        label: 'Consultations',
                        sub: _countsLoaded
                            ? (_consultCount == 0 ? 'No consultations yet' : '$_consultCount consultation${_consultCount == 1 ? '' : 's'}')
                            : 'Loading...',
                        color: AppColors.primary,
                        onTap: () => _openRecords(2),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 20),

                  // Health Status
                  _SectionCard(
                    title: 'Health Status',
                    icon: Icons.monitor_heart_rounded,
                    color: AppColors.primary,
                    child: Column(children: [
                      _StatusTile(
                        label: 'Last Checkup',
                        value: (widget.member['lastCheckup'] as String?)?.trim().isNotEmpty == true
                            ? widget.member['lastCheckup'] as String
                            : 'Not recorded',
                      ),
                      const Divider(height: 1, indent: 16),
                      _StatusTile(
                        label: 'Allergies',
                        value: (widget.member['allergies'] as String?)?.trim().isNotEmpty == true
                            ? widget.member['allergies'] as String
                            : 'None recorded',
                      ),
                      const Divider(height: 1, indent: 16),
                      _StatusTile(
                        label: 'Chronic Conditions',
                        value: (widget.member['chronicConditions'] as String?)?.trim().isNotEmpty == true
                            ? widget.member['chronicConditions'] as String
                            : 'None recorded',
                      ),
                    ]),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  const _SectionCard({required this.title, required this.icon, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: color.withValues(alpha:0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Text(title, style: AppTextStyles.h4),
        ]),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2))],
            border: Border.all(color: context.appBorder),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Icon(icon, size: 18, color: context.appTextHint),
        const SizedBox(width: 12),
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
        const Spacer(),
        Text(value, style: AppTextStyles.labelLarge.copyWith(
            color: valueColor ?? context.appTextPrimary)),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha:0.2)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                  fontWeight: FontWeight.w600, color: color, height: 1.2)),
        ]),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;
  const _RecordTile({required this.icon, required this.label, required this.sub,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppTextStyles.labelLarge),
            Text(sub, style: AppTextStyles.bodySmall),
          ])),
          Icon(Icons.chevron_right_rounded, color: context.appTextHint, size: 20),
        ]),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatusTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Expanded(child: Text(label,
            style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary))),
        Text(value,
            style: AppTextStyles.labelLarge.copyWith(color: context.appTextHint, fontSize: 12)),
      ]),
    );
  }
}
