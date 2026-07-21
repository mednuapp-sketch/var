import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/pregnancy_models.dart';
import '../providers/pregnancy_provider.dart';

// --- Timing constants --------------------------------------------------------

const _kTimingOptions = ['Morning', 'Afternoon', 'Evening', 'Night', 'With meals'];

const _kFrequencyOptions = [
  'Once daily',
  'Twice daily',
  'Thrice daily',
  'Every 6 hours',
  'Every 8 hours',
  'Weekly',
  'As needed',
];

const _kTypeOptions = ['medicine', 'vitamin', 'supplement', 'injection'];

// --- Screen ------------------------------------------------------------------

class PregnancyMedicinesScreen extends ConsumerStatefulWidget {
  const PregnancyMedicinesScreen({super.key});

  @override
  ConsumerState<PregnancyMedicinesScreen> createState() =>
      _PregnancyMedicinesScreenState();
}

class _PregnancyMedicinesScreenState
    extends ConsumerState<PregnancyMedicinesScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // -- helpers ----------------------------------------------------------------

  Color _typeColor(String type) {
    switch (type) {
      case 'vitamin':
        return const Color(0xFFFFA726);
      case 'supplement':
        return const Color(0xFF26C6DA);
      case 'injection':
        return const Color(0xFFAB47BC);
      default:
        return const Color(0xFF66BB6A);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'vitamin':
        return Icons.emoji_food_beverage_rounded;
      case 'supplement':
        return Icons.science_rounded;
      case 'injection':
        return Icons.vaccines_rounded;
      default:
        return Icons.medication_rounded;
    }
  }

  String _typeLabel(String type) =>
      type[0].toUpperCase() + type.substring(1);

  bool _isNearingEnd(PregnancyMedicine m) {
    if (m.endDate == null) return false;
    final daysLeft = m.endDate!.difference(DateTime.now()).inDays;
    return daysLeft >= 0 && daysLeft <= 7;
  }

  bool _isExpired(PregnancyMedicine m) {
    if (m.endDate == null) return false;
    return m.endDate!.isBefore(DateTime.now());
  }

  // -- delete -----------------------------------------------------------------

  Future<void> _deleteMedicine(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Medicine'),
        content: Text('Remove "$name" from your list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(pregnancyProvider.notifier).deleteMedicine(id);
    }
  }

  // -- add / edit sheet -------------------------------------------------------

  void _showAddSheet({PregnancyMedicine? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddMedicineSheet(
        existing: existing,
        onSave: (medicine) async {
          final ok = await ref
              .read(pregnancyProvider.notifier)
              .addMedicine(medicine);
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          if (!ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to save. Please try again.')),
            );
          }
        },
      ),
    );
  }

  // -- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F8),
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.appTextPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'My Medicines',
          style: TextStyle(fontFamily: 'Poppins', 
            color: context.appTextPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: AppColors.primary),
            tooltip: 'Add medicine',
            onPressed: () => _showAddSheet(),
          ),
        ],
      ),
      body: ref.watch(pregnancyMedicinesStreamProvider).when(
        loading: () => _buildSkeleton(),
        error: (e, _) => const AppErrorState(),
        data: (meds) => FadeTransition(
          opacity: _fadeCtrl,
          child: meds.isEmpty
              ? _buildEmpty()
              : _buildContent(meds),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Add Medicine',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // -- skeleton ---------------------------------------------------------------

  Widget _buildSkeleton() => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
    children: [
      const _SummaryCardSkeleton(),
      const SizedBox(height: 16),
      ...List.generate(
        4,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: _MedicineCardSkeleton(),
        ),
      ),
    ],
  );

  // -- empty state ------------------------------------------------------------

  Widget _buildEmpty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF66BB6A).withValues(alpha: 0.15),
                  const Color(0xFF66BB6A).withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.medication_rounded,
              size: 42,
              color: Color(0xFF66BB6A),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No medicines added yet',
            style: TextStyle(fontFamily: 'Poppins', 
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: context.appTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add your prescribed medicines,\nvitamins, and supplements.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', 
              color: context.appTextHint,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () => _showAddSheet(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Medicine'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );

  // -- main content -----------------------------------------------------------

  Widget _buildContent(List<PregnancyMedicine> meds) {
    final today = _buildTodaySection(meds);
    final grouped = _groupByType(meds);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        _buildSummaryCard(meds),
        const SizedBox(height: 16),
        if (today.isNotEmpty) ...[
          _buildTodaySectionWidget(today),
          const SizedBox(height: 16),
        ],
        for (final type in _kTypeOptions)
          if ((grouped[type] ?? []).isNotEmpty) ...[
            _buildTypeSection(type, grouped[type]!),
            const SizedBox(height: 4),
          ],
      ],
    );
  }

  // -- Today's schedule -------------------------------------------------------

  List<PregnancyMedicine> _buildTodaySection(List<PregnancyMedicine> meds) {
    final now = DateTime.now();
    return meds.where((m) {
      if (!m.isActive) return false;
      if (m.endDate != null && m.endDate!.isBefore(now)) return false;
      return true;
    }).toList();
  }

  Widget _buildTodaySectionWidget(List<PregnancyMedicine> todayMeds) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.today_rounded,
                  color: AppColors.primary, size: 16),
            ),
            const SizedBox(width: 8),
            Text(
              "Today's Schedule",
              style: TextStyle(fontFamily: 'Poppins', 
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${todayMeds.length}',
                style: TextStyle(fontFamily: 'Poppins', 
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: todayMeds.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _buildTodayChip(todayMeds[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildTodayChip(PregnancyMedicine m) {
    final color = _typeColor(m.type);
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(_typeIcon(m.type), color: color, size: 14),
              ),
              const Spacer(),
              if (_isNearingEnd(m))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6F00).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Refill',
                    style: TextStyle(
                        fontSize: 8,
                        color: Color(0xFFFF6F00),
                        fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            m.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Poppins', 
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: context.appTextPrimary,
            ),
          ),
          Text(
            m.dosage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Poppins', 
              fontSize: 10,
              color: context.appTextHint,
            ),
          ),
          if (m.reminderTime != null)
            Row(
              children: [
                Icon(Icons.alarm_rounded, size: 10, color: color),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    m.reminderTime!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: color),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // -- summary card -----------------------------------------------------------

  Widget _buildSummaryCard(List<PregnancyMedicine> meds) {
    final active = meds.where((m) => m.isActive && !_isExpired(m)).length;
    final refill = meds.where(_isNearingEnd).length;
    final types = <String, int>{};
    for (final m in meds) {
      types[m.type] = (types[m.type] ?? 0) + 1;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B1FA2), Color(0xFFC2185B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.medical_services_rounded,
                  color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(
                'Active Prescriptions',
                style: TextStyle(fontFamily: 'Poppins', 
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (refill > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        '$refill refill${refill > 1 ? 's' : ''} soon',
                        style: TextStyle(fontFamily: 'Poppins', 
                          color: Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$active items',
            style: TextStyle(fontFamily: 'Poppins', 
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: _kTypeOptions
                .where((t) => (types[t] ?? 0) > 0)
                .map((t) => Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${types[t]}',
                            style: TextStyle(fontFamily: 'Poppins', 
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            _typeLabel(t),
                            style: TextStyle(fontFamily: 'Poppins', 
                              color: Colors.white60,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  // -- type grouped section ---------------------------------------------------

  Map<String, List<PregnancyMedicine>> _groupByType(
      List<PregnancyMedicine> meds) {
    final map = <String, List<PregnancyMedicine>>{};
    for (final m in meds) {
      map.putIfAbsent(m.type, () => []).add(m);
    }
    return map;
  }

  Widget _buildTypeSection(String type, List<PregnancyMedicine> meds) {
    final color = _typeColor(type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(_typeIcon(type), color: color, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                _typeLabel(type) + 's',
                style: TextStyle(fontFamily: 'Poppins', 
                  fontWeight: FontWeight.w700,
                  color: context.appTextPrimary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${meds.length}',
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        ...meds.map((m) => _buildMedicineCard(m, color)),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildMedicineCard(PregnancyMedicine m, Color color) {
    final nearingEnd = _isNearingEnd(m);
    final expired = _isExpired(m);
    final daysLeft = m.endDate != null
        ? m.endDate!.difference(DateTime.now()).inDays
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: nearingEnd
              ? const Color(0xFFFF6F00).withValues(alpha: 0.3)
              : expired
                  ? Colors.red.withValues(alpha: 0.2)
                  : color.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(_typeIcon(m.type), color: color, size: 22),
                ),
                const SizedBox(width: 12),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              m.name,
                              style: TextStyle(fontFamily: 'Poppins', 
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: context.appTextPrimary,
                              ),
                            ),
                          ),
                          if (nearingEnd)
                            _badge(
                              icon: Icons.refresh_rounded,
                              label: daysLeft == 0
                                  ? 'Last day'
                                  : '$daysLeft day${daysLeft == 1 ? '' : 's'} left',
                              bgColor: const Color(0xFFFF6F00).withValues(alpha: 0.1),
                              textColor: const Color(0xFFFF6F00),
                            )
                          else if (expired)
                            _badge(
                              icon: Icons.block_rounded,
                              label: 'Expired',
                              bgColor: Colors.red.withValues(alpha: 0.08),
                              textColor: Colors.red,
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        m.dosage,
                        style: TextStyle(fontFamily: 'Poppins', 
                          fontSize: 12,
                          color: context.appTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _chip(
                            icon: Icons.repeat_rounded,
                            label: m.frequency,
                            color: color,
                          ),
                          if (m.reminderTime != null)
                            _chip(
                              icon: Icons.alarm_rounded,
                              label: m.reminderTime!,
                              color: const Color(0xFFFFA726),
                            ),
                          if (m.prescribedBy != null)
                            _chip(
                              icon: Icons.person_rounded,
                              label: 'Dr. ${m.prescribedBy}',
                              color: const Color(0xFF7B1FA2),
                            ),
                        ],
                      ),
                      if (m.instructions != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 12,
                                color: context.appTextHint),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                m.instructions!,
                                style: TextStyle(fontFamily: 'Poppins', 
                                  fontSize: 11,
                                  color: context.appTextSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (m.endDate != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 10,
                                color: context.appTextHint),
                            const SizedBox(width: 4),
                            Text(
                              'Until ${DateFormat('dd MMM yyyy').format(m.endDate!)}',
                              style: TextStyle(fontFamily: 'Poppins', 
                                fontSize: 10,
                                color: context.appTextHint,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Action row
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F4F8),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _showAddSheet(existing: m),
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                      foregroundColor: color,
                      textStyle:
                          TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                Container(width: 1, height: 28, color: context.appBorder),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _deleteMedicine(m.id, m.name),
                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                    label: const Text('Remove'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      textStyle:
                          TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );

  Widget _badge({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color textColor,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: textColor),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                  fontSize: 9, color: textColor, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

// --- Add / Edit Medicine Bottom Sheet -----------------------------------------

class _AddMedicineSheet extends ConsumerStatefulWidget {
  final PregnancyMedicine? existing;
  final Future<void> Function(PregnancyMedicine) onSave;

  const _AddMedicineSheet({required this.onSave, this.existing});

  @override
  ConsumerState<_AddMedicineSheet> createState() => _AddMedicineSheetState();
}

class _AddMedicineSheetState extends ConsumerState<_AddMedicineSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _dosageCtrl;
  late final TextEditingController _instructionsCtrl;
  late final TextEditingController _prescribedByCtrl;

  String _selectedFrequency = _kFrequencyOptions[0];
  String _selectedType = 'medicine';
  final Set<String> _selectedTimings = {};
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _reminderEnabled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _dosageCtrl = TextEditingController(text: e?.dosage ?? '');
    _instructionsCtrl = TextEditingController(text: e?.instructions ?? '');
    _prescribedByCtrl = TextEditingController(text: e?.prescribedBy ?? '');
    if (e != null) {
      _selectedFrequency = e.frequency;
      _selectedType = e.type;
      _startDate = e.startDate;
      _endDate = e.endDate;
      _reminderEnabled = e.reminderTime != null;
      if (e.reminderTime != null) {
        _selectedTimings.add(e.reminderTime!);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    _instructionsCtrl.dispose();
    _prescribedByCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : (_endDate ?? now),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = ref.read(pregnancyProvider).profile?.patientId ?? '';
    setState(() => _saving = true);
    final medicine = PregnancyMedicine(
      id: widget.existing?.id ?? '',
      patientId: uid,
      name: _nameCtrl.text.trim(),
      dosage: _dosageCtrl.text.trim(),
      frequency: _selectedFrequency,
      type: _selectedType,
      startDate: _startDate,
      endDate: _endDate,
      reminderTime:
          _reminderEnabled && _selectedTimings.isNotEmpty
              ? _selectedTimings.join(', ')
              : null,
      instructions: _instructionsCtrl.text.trim().isEmpty
          ? null
          : _instructionsCtrl.text.trim(),
      prescribedBy: _prescribedByCtrl.text.trim().isEmpty
          ? null
          : _prescribedByCtrl.text.trim(),
      isActive: true,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    await widget.onSave(medicine);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.appBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.medication_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.existing == null
                        ? 'Add Medicine'
                        : 'Edit Medicine',
                    style: TextStyle(fontFamily: 'Poppins', 
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      _label('Medicine / Supplement Name *'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: _inputDeco(
                          hint: 'e.g. Folic Acid, Iron Tablet',
                          icon: Icons.medication_rounded,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Name is required'
                                : null,
                      ),
                      const SizedBox(height: 14),

                      // Type
                      _label('Type'),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _kTypeOptions.map((t) {
                            final sel = _selectedType == t;
                            final color = _typeColorStatic(t);
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedType = t),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: sel
                                        ? color
                                        : color.withValues(alpha: 0.08),
                                    borderRadius:
                                        BorderRadius.circular(20),
                                    border: Border.all(
                                      color: sel
                                          ? color
                                          : color.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _typeIconStatic(t),
                                        size: 14,
                                        color: sel
                                            ? Colors.white
                                            : color,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        _typeLabelStatic(t),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: sel
                                              ? Colors.white
                                              : color,
                                          fontWeight:
                                              FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Dosage
                      _label('Dosage *'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _dosageCtrl,
                        decoration: _inputDeco(
                          hint: 'e.g. 400 mcg, 1 tablet, 5 ml',
                          icon: Icons.scale_rounded,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Dosage is required'
                                : null,
                      ),
                      const SizedBox(height: 14),

                      // Frequency
                      _label('Frequency'),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F4F8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.appBorder),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 2),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedFrequency,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            items: _kFrequencyOptions
                                .map((f) => DropdownMenuItem(
                                      value: f,
                                      child: Text(f,
                                          style: TextStyle(fontFamily: 'Poppins', 
                                              fontSize: 13)),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(
                                    () => _selectedFrequency = v);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Timing chips
                      Row(
                        children: [
                          _label('Timing'),
                          const SizedBox(width: 8),
                          Text(
                            '(select all that apply)',
                            style: TextStyle(fontFamily: 'Poppins', 
                              fontSize: 11,
                              color: context.appTextHint,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _kTimingOptions.map((t) {
                          final sel = _selectedTimings.contains(t);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (sel) {
                                _selectedTimings.remove(t);
                              } else {
                                _selectedTimings.add(t);
                              }
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: sel
                                    ? AppColors.primary
                                    : AppColors.primary
                                        .withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: sel
                                      ? AppColors.primary
                                      : AppColors.primary
                                          .withValues(alpha: 0.2),
                                ),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(fontFamily: 'Poppins', 
                                  fontSize: 12,
                                  color: sel
                                      ? Colors.white
                                      : AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),

                      // Dates
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _label('Start Date'),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => _pickDate(true),
                                  child: _dateField(
                                    DateFormat('dd MMM yyyy')
                                        .format(_startDate),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _label('End Date'),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => _pickDate(false),
                                  child: _dateField(
                                    _endDate != null
                                        ? DateFormat('dd MMM yyyy')
                                            .format(_endDate!)
                                        : 'Optional',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Reminder toggle
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F4F8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.appBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.notifications_rounded,
                                color: AppColors.primary, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Enable Reminders',
                                style: TextStyle(fontFamily: 'Poppins', 
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                              ),
                            ),
                            Switch(
                              value: _reminderEnabled,
                              onChanged: (v) =>
                                  setState(() => _reminderEnabled = v),
                              activeColor: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Instructions
                      _label('Instructions (optional)'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _instructionsCtrl,
                        maxLines: 2,
                        decoration: _inputDeco(
                          hint: 'e.g. Take with water, after meals',
                          icon: Icons.info_outline_rounded,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Prescribed by
                      _label('Prescribed by (optional)'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _prescribedByCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: _inputDeco(
                          hint: 'Doctor\'s name',
                          icon: Icons.person_rounded,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
            // Save button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: TextStyle(fontFamily: 'Poppins', 
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(widget.existing == null
                          ? 'Add Medicine'
                          : 'Save Changes'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: TextStyle(fontFamily: 'Poppins', 
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: context.appTextSecondary,
        ),
      );

  Widget _dateField(String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F4F8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.appBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                size: 14, color: context.appTextHint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value,
                style: TextStyle(fontFamily: 'Poppins', 
                  fontSize: 12,
                  color: value == 'Optional'
                      ? context.appTextHint
                      : context.appTextPrimary,
                ),
              ),
            ),
          ],
        ),
      );

  InputDecoration _inputDeco({required String hint, required IconData icon}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontFamily: 'Poppins', 
            fontSize: 13, color: context.appTextHint),
        prefixIcon: Icon(icon, size: 18, color: context.appTextHint),
        filled: true,
        fillColor: const Color(0xFFF7F4F8),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.appBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.appBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      );

  // Static helpers for sheet (no access to instance methods)
  static Color _typeColorStatic(String type) {
    switch (type) {
      case 'vitamin':
        return const Color(0xFFFFA726);
      case 'supplement':
        return const Color(0xFF26C6DA);
      case 'injection':
        return const Color(0xFFAB47BC);
      default:
        return const Color(0xFF66BB6A);
    }
  }

  static IconData _typeIconStatic(String type) {
    switch (type) {
      case 'vitamin':
        return Icons.emoji_food_beverage_rounded;
      case 'supplement':
        return Icons.science_rounded;
      case 'injection':
        return Icons.vaccines_rounded;
      default:
        return Icons.medication_rounded;
    }
  }

  static String _typeLabelStatic(String type) =>
      type[0].toUpperCase() + type.substring(1);
}

// --- Skeleton Widgets ---------------------------------------------------------

class _SummaryCardSkeleton extends StatelessWidget {
  const _SummaryCardSkeleton();

  @override
  Widget build(BuildContext context) => AppShimmer(
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: context.appBorder,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      );
}

class _MedicineCardSkeleton extends StatelessWidget {
  const _MedicineCardSkeleton();

  @override
  Widget build(BuildContext context) => AppShimmer(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(color: Color(0x0A000000), blurRadius: 6)
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBox(width: 44, height: 44, radius: 11),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                            width: double.infinity,
                            height: 14,
                            radius: 4),
                        SizedBox(height: 6),
                        SkeletonBox(width: 140, height: 11, radius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const SkeletonBox(width: 72, height: 26, radius: 13),
                ],
              ),
              const SizedBox(height: 10),
              const Row(
                children: [
                  SkeletonBox(width: 80, height: 20, radius: 10),
                  SizedBox(width: 6),
                  SkeletonBox(width: 100, height: 20, radius: 10),
                ],
              ),
            ],
          ),
        ),
      );
}
