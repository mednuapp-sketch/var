import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../models/pregnancy_models.dart';
import '../providers/pregnancy_provider.dart';
import '../../../core/widgets/ux_widgets.dart';

class PregnancyMedicinesScreen extends ConsumerWidget {
  const PregnancyMedicinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text('My Medicines',
            style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: ref.watch(pregnancyMedicinesStreamProvider).when(
        loading: () => ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: List.generate(5, (_) => const _MedicineCardSkeleton()),
        ),
        error: (e, _) => const AppErrorState(),
        data: (meds) {
          if (meds.isEmpty) {
            return _buildEmpty();
          }
          final grouped = _group(meds);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _summaryCard(meds),
              const SizedBox(height: 16),
              if ((grouped['medicine'] ?? []).isNotEmpty)
                _groupSection('Medicines', Icons.medication_rounded, const Color(0xFF66BB6A), grouped['medicine']!),
              if ((grouped['vitamin'] ?? []).isNotEmpty)
                _groupSection('Vitamins', Icons.emoji_food_beverage_rounded, const Color(0xFFFFA726), grouped['vitamin']!),
              if ((grouped['supplement'] ?? []).isNotEmpty)
                _groupSection('Supplements', Icons.science_rounded, const Color(0xFF26C6DA), grouped['supplement']!),
              if ((grouped['injection'] ?? []).isNotEmpty)
                _groupSection('Injections', Icons.vaccines_rounded, const Color(0xFFAB47BC), grouped['injection']!),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryCard(List<PregnancyMedicine> meds) {
    final types = <String, int>{};
    for (final m in meds) types[m.type] = (types[m.type] ?? 0) + 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF66BB6A), Color(0xFF388E3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Active Prescriptions',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('${meds.length} items',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(
            children: types.entries.map((e) => Expanded(
              child: Column(
                children: [
                  Text('${e.value}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(e.key[0].toUpperCase() + e.key.substring(1),
                      style: const TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _groupSection(String title, IconData icon, Color color, List<PregnancyMedicine> meds) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 14)),
          ]),
          const SizedBox(height: 8),
          ...meds.map((m) => _medicineCard(m, color)),
          const SizedBox(height: 16),
        ],
      );

  Widget _medicineCard(PregnancyMedicine m, Color color) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha:0.15)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 6)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_typeIcon(m.type), color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(m.dosage,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(m.frequency,
                  style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        if (m.instructions != null || m.reminderTime != null || m.prescribedBy != null) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (m.reminderTime != null)
                _pill(Icons.alarm_rounded, m.reminderTime!, const Color(0xFFFFA726)),
              if (m.prescribedBy != null)
                _pill(Icons.person_rounded, 'Dr. ${m.prescribedBy}', const Color(0xFF7B1FA2)),
              if (m.instructions != null)
                _pill(Icons.info_outline_rounded, m.instructions!, const Color(0xFF42A5F5)),
            ],
          ),
        ],
        if (m.endDate != null) ...[
          const SizedBox(height: 6),
          Text(
            'Until: ${DateFormat('dd MMM yyyy').format(m.endDate!)}',
            style: const TextStyle(fontSize: 10, color: AppColors.textHint),
          ),
        ],
      ],
    ),
  );

  Widget _pill(IconData icon, String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontSize: 11, color: color)),
    ],
  );

  Widget _buildEmpty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF66BB6A).withValues(alpha:0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.medication_rounded, size: 40, color: Color(0xFF66BB6A)),
          ),
          const SizedBox(height: 16),
          const Text('No medicines prescribed yet',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Your doctor will prescribe medicines and vitamins based on your needs.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textHint, fontSize: 13, height: 1.6)),
        ],
      ),
    ),
  );

  Map<String, List<PregnancyMedicine>> _group(List<PregnancyMedicine> list) {
    final Map<String, List<PregnancyMedicine>> grouped = {};
    for (final m in list) {
      grouped.putIfAbsent(m.type, () => []).add(m);
    }
    return grouped;
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'vitamin': return Icons.emoji_food_beverage_rounded;
      case 'supplement': return Icons.science_rounded;
      case 'injection': return Icons.vaccines_rounded;
      default: return Icons.medication_rounded;
    }
  }
}

class _MedicineCardSkeleton extends StatelessWidget {
  const _MedicineCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
      ),
      child: const AppShimmer(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SkeletonBox(width: 40, height: 40, radius: 10),
            SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SkeletonBox(width: double.infinity, height: 14, radius: 4),
              SizedBox(height: 5),
              SkeletonBox(width: 140, height: 11, radius: 4),
            ])),
            SizedBox(width: 8),
            SkeletonBox(width: 72, height: 26, radius: 13),
          ]),
          SizedBox(height: 10),
          Row(children: [
            SkeletonBox(width: 80, height: 18, radius: 6),
            SizedBox(width: 8),
            SkeletonBox(width: 100, height: 18, radius: 6),
          ]),
        ]),
      ),
    );
  }
}
