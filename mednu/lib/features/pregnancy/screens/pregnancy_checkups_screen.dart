import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../models/pregnancy_models.dart';
import '../providers/pregnancy_provider.dart';
import '../data/pregnancy_week_data.dart';

class PregnancyCheckupsScreen extends ConsumerStatefulWidget {
  const PregnancyCheckupsScreen({super.key});

  @override
  ConsumerState<PregnancyCheckupsScreen> createState() =>
      _PregnancyCheckupsScreenState();
}

class _PregnancyCheckupsScreenState
    extends ConsumerState<PregnancyCheckupsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

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
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text('Checkups & Appointments',
            style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w700, fontSize: 16)),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [Tab(text: 'Upcoming'), Tab(text: 'Standard Schedule')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildUpcomingTab(),
          _buildStandardScheduleTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCheckupDialog(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Checkup', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildUpcomingTab() {
    return Consumer(builder: (context, ref, _) {
      final checkups = ref.watch(pregnancyCheckupsStreamProvider);
      return checkups.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return _emptyState();
          }
          final grouped = _groupByStatus(list);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if ((grouped['upcoming'] ?? []).isNotEmpty) ...[
                _groupHeader('Upcoming', const Color(0xFF42A5F5), Icons.upcoming_rounded),
                ...grouped['upcoming']!.map((c) => _checkupCard(context, c)),
                const SizedBox(height: 12),
              ],
              if ((grouped['completed'] ?? []).isNotEmpty) ...[
                _groupHeader('Completed', const Color(0xFF66BB6A), Icons.check_circle_rounded),
                ...grouped['completed']!.map((c) => _checkupCard(context, c)),
                const SizedBox(height: 12),
              ],
              if ((grouped['missed'] ?? []).isNotEmpty) ...[
                _groupHeader('Missed', const Color(0xFFEF5350), Icons.cancel_rounded),
                ...grouped['missed']!.map((c) => _checkupCard(context, c)),
              ],
              const SizedBox(height: 80),
            ],
          );
        },
      );
    });
  }

  Map<String, List<PregnancyCheckup>> _groupByStatus(List<PregnancyCheckup> list) {
    final Map<String, List<PregnancyCheckup>> grouped = {};
    for (final c in list) {
      grouped.putIfAbsent(c.status, () => []).add(c);
    }
    return grouped;
  }

  Widget _groupHeader(String title, Color color, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13)),
      ],
    ),
  );

  Widget _checkupCard(BuildContext context, PregnancyCheckup c) {
    final statusColor = _statusColor(c.status);
    final isUpcoming = c.status == 'upcoming';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_typeIcon(c.type), color: statusColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 12, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(DateFormat('dd MMM yyyy').format(c.scheduledDate),
                        style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                    const SizedBox(width: 8),
                    Icon(Icons.pregnant_woman_rounded, size: 12, color: AppColors.textHint),
                    const SizedBox(width: 2),
                    Text('Week ${c.pregnancyWeek}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
                  ],
                ),
                if (c.notes != null && c.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(c.notes!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_statusLabel(c.status),
                    style: TextStyle(fontSize: 9, color: statusColor, fontWeight: FontWeight.w700)),
              ),
              if (isUpcoming) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => ref.read(pregnancyProvider.notifier).markCheckupComplete(c.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF66BB6A).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Done',
                        style: TextStyle(fontSize: 9, color: Color(0xFF2E7D32), fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStandardScheduleTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF7B1FA2).withOpacity(0.2)),
        ),
        child: Row(
          children: const [
            Text('📋', style: TextStyle(fontSize: 20)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Standard pregnancy checkup schedule. Your doctor may customize this based on your needs.',
                style: TextStyle(fontSize: 12, color: Color(0xFF4A148C), height: 1.5),
              ),
            ),
          ],
        ),
      ),
      ...kStandardCheckups.map((c) => _standardCheckupTile(c)),
      const SizedBox(height: 80),
    ],
  );

  Widget _standardCheckupTile(Map<String, String> c) {
    final typeColor = _typeColorByStr(c['type'] ?? 'routine');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_typeIcon(c['type'] ?? 'routine'), color: typeColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('Week ${c['week']}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text((c['type'] ?? '').toUpperCase().replaceAll('_', ' '),
                style: TextStyle(fontSize: 9, color: typeColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF42A5F5).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.calendar_month_rounded, size: 40, color: Color(0xFF42A5F5)),
          ),
          const SizedBox(height: 16),
          const Text('No checkups yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Your doctor will schedule checkups, or you can add one below.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textHint, fontSize: 13)),
        ],
      ),
    ),
  );

  Future<void> _showAddCheckupDialog(BuildContext context) async {
    final profile = ref.read(pregnancyProvider).profile;
    if (profile == null) return;
    DateTime? date;
    String type = 'routine';
    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(child: Text('Add Checkup',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Checkup Title *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                items: ['routine', 'ultrasound', 'blood_test', 'scan', 'vaccination']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' ').toUpperCase())))
                    .toList(),
                onChanged: (v) => setModal(() => type = v!),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 300)));
                  if (d != null) setModal(() => date = d);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(date != null ? DateFormat('dd MMM yyyy').format(date!) : 'Select Date *',
                          style: TextStyle(color: date != null ? AppColors.textPrimary : AppColors.textHint)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (titleCtrl.text.isEmpty || date == null) return;
                    final checkup = PregnancyCheckup(
                      id: '',
                      patientId: profile.patientId,
                      type: type,
                      title: titleCtrl.text.trim(),
                      scheduledDate: date!,
                      status: 'upcoming',
                      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                      pregnancyWeek: profile.currentWeek,
                      createdAt: DateTime.now(),
                    );
                    await ref.read(pregnancyProvider.notifier).addCheckup(checkup);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Add Checkup', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    titleCtrl.dispose();
    notesCtrl.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed': return const Color(0xFF66BB6A);
      case 'missed': return const Color(0xFFEF5350);
      case 'cancelled': return const Color(0xFF757575);
      default: return const Color(0xFF42A5F5);
    }
  }

  String _statusLabel(String status) => status.toUpperCase();

  IconData _typeIcon(String type) {
    switch (type) {
      case 'ultrasound': return Icons.image_search_rounded;
      case 'blood_test': return Icons.biotech_rounded;
      case 'scan': return Icons.radar_rounded;
      case 'vaccination': return Icons.vaccines_rounded;
      default: return Icons.medical_services_rounded;
    }
  }

  Color _typeColorByStr(String type) {
    switch (type) {
      case 'ultrasound': return const Color(0xFF7B1FA2);
      case 'blood_test': return const Color(0xFFEF5350);
      case 'scan': return const Color(0xFF26C6DA);
      case 'vaccination': return const Color(0xFF66BB6A);
      default: return const Color(0xFF42A5F5);
    }
  }
}
