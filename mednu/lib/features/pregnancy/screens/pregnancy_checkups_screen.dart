import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../models/pregnancy_models.dart';
import '../providers/pregnancy_provider.dart';
import '../data/pregnancy_week_data.dart';
import '../../../core/widgets/ux_widgets.dart';

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
        backgroundColor: context.appBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.appTextPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Checkups & Appointments',
              style: TextStyle(
                  color: context.appTextPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
            Text(
              'Track all your prenatal visits',
              style: TextStyle(
                  color: context.appTextHint.withValues(alpha: 0.8),
                  fontSize: 11),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border:
                  Border(bottom: BorderSide(color: context.appBorder, width: 1)),
            ),
            child: TabBar(
              controller: _tab,
              labelColor: AppColors.primary,
              unselectedLabelColor: context.appTextHint,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(
                  child: Text('My Checkups',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Tab(
                  child: Text('Standard Schedule',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _MyCheckupsTab(),
          _buildStandardScheduleTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCheckupDialog(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_rounded),
        label:
            const Text('Add Checkup', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ── Standard schedule tab ─────────────────────────────────────────────────

  Widget _buildStandardScheduleTab() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF3E5F5), Color(0xFFFCE4EC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF7B1FA2).withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B1FA2).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calendar_month_rounded,
                        color: Color(0xFF7B1FA2), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Standard pregnancy checkup schedule. Your doctor may adjust this based on your individual needs.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4A148C),
                          height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Recommended Visits',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: context.appTextPrimary),
            ),
            const SizedBox(height: 10),
            ...kStandardCheckups
                .map((c) => _standardCheckupTile(c)),
          ],
        ),
      );

  Widget _standardCheckupTile(Map<String, String> c) {
    final typeColor = _typeColorByStr(c['type'] ?? 'routine');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_typeIcon(c['type'] ?? 'routine'),
                color: typeColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c['title'] ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Week ${c['week']}',
                  style: TextStyle(
                      fontSize: 11, color: context.appTextHint),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              (c['type'] ?? '').toUpperCase().replaceAll('_', ' '),
              style: TextStyle(
                  fontSize: 9,
                  color: typeColor,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Add checkup dialog ────────────────────────────────────────────────────

  Future<void> _showAddCheckupDialog(BuildContext context) async {
    final profile = ref.read(pregnancyProvider).profile;
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please set up your pregnancy profile first.')),
      );
      return;
    }

    DateTime? date;
    String type = 'routine';
    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final outerMessenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appBackground,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.9,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: context.appBorder,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.medical_services_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Add Checkup',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Checkup Title *',
                    hintText: 'e.g. First trimester scan',
                    filled: true,
                    fillColor: const Color(0xFFF7F4F8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.appBorder)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.appBorder)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 2)),
                  ),
                ),
                const SizedBox(height: 10),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Type',
                    filled: true,
                    fillColor: const Color(0xFFF7F4F8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.appBorder)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.appBorder)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: type,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                            value: 'routine', child: Text('Routine Visit')),
                        DropdownMenuItem(
                            value: 'ultrasound',
                            child: Text('Ultrasound')),
                        DropdownMenuItem(
                            value: 'blood_test',
                            child: Text('Blood Test')),
                        DropdownMenuItem(
                            value: 'scan', child: Text('Scan')),
                        DropdownMenuItem(
                            value: 'vaccination',
                            child: Text('Vaccination')),
                      ],
                      onChanged: (v) => setModal(() => type = v!),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate:
                          DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 300)),
                      builder: (context, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                              primary: AppColors.primary),
                        ),
                        child: child!,
                      ),
                    );
                    if (d != null && ctx.mounted) {
                      setModal(() => date = d);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 15),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F4F8),
                      border: Border.all(
                          color: date != null
                              ? AppColors.primary
                              : context.appBorder,
                          width: date != null ? 2 : 1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 18,
                            color: date != null
                                ? AppColors.primary
                                : context.appTextHint),
                        const SizedBox(width: 10),
                        Text(
                          date != null
                              ? DateFormat('dd MMM yyyy').format(date!)
                              : 'Select Date *',
                          style: TextStyle(
                            fontSize: 14,
                            color: date != null
                                ? context.appTextPrimary
                                : context.appTextHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'Clinic name, doctor, etc.',
                    filled: true,
                    fillColor: const Color(0xFFF7F4F8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.appBorder)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.appBorder)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 2)),
                  ),
                ),
                const SizedBox(height: 18),
                _AddCheckupButton(
                  titleCtrl: titleCtrl,
                  notesCtrl: notesCtrl,
                  getDate: () => date,
                  getType: () => type,
                  profile: profile,
                  onDone: (ok) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    outerMessenger.showSnackBar(SnackBar(
                      content: Text(ok
                          ? 'Checkup added successfully'
                          : 'Failed to add checkup'),
                      backgroundColor: ok
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFEF5350),
                    ));
                  },
                ),
                ],
              ),
            ),
          );
        },
      ),
    );

    titleCtrl.dispose();
    notesCtrl.dispose();
  }

  // ── Color / icon helpers ──────────────────────────────────────────────────

  IconData _typeIcon(String type) {
    switch (type) {
      case 'ultrasound':
        return Icons.image_search_rounded;
      case 'blood_test':
        return Icons.biotech_rounded;
      case 'scan':
        return Icons.radar_rounded;
      case 'vaccination':
        return Icons.vaccines_rounded;
      default:
        return Icons.medical_services_rounded;
    }
  }

  Color _typeColorByStr(String type) {
    switch (type) {
      case 'ultrasound':
        return const Color(0xFF7B1FA2);
      case 'blood_test':
        return const Color(0xFFEF5350);
      case 'scan':
        return const Color(0xFF00ACC1);
      case 'vaccination':
        return const Color(0xFF43A047);
      default:
        return const Color(0xFF1976D2);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Checkups Tab — extracted widget to avoid stale context in callbacks
// ─────────────────────────────────────────────────────────────────────────────

class _MyCheckupsTab extends ConsumerWidget {
  const _MyCheckupsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkups = ref.watch(pregnancyCheckupsStreamProvider);
    return checkups.when(
      loading: () => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: List.generate(5, (_) => const _CheckupCardSkeleton()),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF5350).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_off_rounded,
                    size: 36, color: Color(0xFFEF5350)),
              ),
              const SizedBox(height: 16),
              const Text('Could not load checkups',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                'Check your internet connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appTextHint, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(pregnancyCheckupsStreamProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
      data: (list) {
        if (list.isEmpty) return const _CheckupsEmptyState();
        final upcoming = list.where((c) => c.status == 'upcoming').toList();
        final completed = list.where((c) => c.status == 'completed').toList();
        final missed = list.where((c) => c.status == 'missed').toList();
        final cancelled = list.where((c) => c.status == 'cancelled').toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // Stats row
            _StatsRow(total: list.length, upcoming: upcoming.length, completed: completed.length),
            const SizedBox(height: 16),
            if (upcoming.isNotEmpty) ...[
              _SectionHeader(
                  label: 'Upcoming',
                  color: const Color(0xFF1976D2),
                  icon: Icons.upcoming_rounded,
                  count: upcoming.length),
              const SizedBox(height: 8),
              ...upcoming.map((c) => _CheckupCard(checkup: c)),
              const SizedBox(height: 16),
            ],
            if (completed.isNotEmpty) ...[
              _SectionHeader(
                  label: 'Completed',
                  color: const Color(0xFF2E7D32),
                  icon: Icons.check_circle_rounded,
                  count: completed.length),
              const SizedBox(height: 8),
              ...completed.map((c) => _CheckupCard(checkup: c)),
              const SizedBox(height: 16),
            ],
            if (missed.isNotEmpty) ...[
              _SectionHeader(
                  label: 'Missed',
                  color: const Color(0xFFEF5350),
                  icon: Icons.cancel_rounded,
                  count: missed.length),
              const SizedBox(height: 8),
              ...missed.map((c) => _CheckupCard(checkup: c)),
              const SizedBox(height: 16),
            ],
            if (cancelled.isNotEmpty) ...[
              _SectionHeader(
                  label: 'Cancelled',
                  color: const Color(0xFF757575),
                  icon: Icons.block_rounded,
                  count: cancelled.length),
              const SizedBox(height: 8),
              ...cancelled.map((c) => _CheckupCard(checkup: c)),
            ],
          ],
        );
      },
    );
  }
}

// ─── Stats Row ───────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int total, upcoming, completed;
  const _StatsRow(
      {required this.total, required this.upcoming, required this.completed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B1FA2), Color(0xFFC2185B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _stat('$total', 'Total'),
          _divider(),
          _stat('$upcoming', 'Upcoming'),
          _divider(),
          _stat('$completed', 'Completed'),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11)),
          ],
        ),
      );

  Widget _divider() => Container(
        width: 1,
        height: 36,
        color: Colors.white.withValues(alpha: 0.25),
        margin: const EdgeInsets.symmetric(horizontal: 4),
      );
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final int count;
  const _SectionHeader(
      {required this.label,
      required this.color,
      required this.icon,
      required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: color, fontSize: 13)),
        const SizedBox(width: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count',
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ─── Checkup Card ─────────────────────────────────────────────────────────────

class _CheckupCard extends ConsumerWidget {
  final PregnancyCheckup checkup;
  const _CheckupCard({required this.checkup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = checkup;
    final statusColor = _statusColor(c.status);
    final isUpcoming = c.status == 'upcoming';

    return Dismissible(
      key: Key(c.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEF5350),
          borderRadius: BorderRadius.circular(14),
        ),
        child:
            const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Delete Checkup',
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: Text('Remove "${c.title}"? This cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: Color(0xFFEF5350))),
            ),
          ],
        ),
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final ok =
            await ref.read(pregnancyProvider.notifier).deleteCheckup(c.id);
        messenger.showSnackBar(SnackBar(
          content: Text(ok ? 'Checkup deleted' : 'Failed to delete checkup'),
          backgroundColor:
              ok ? const Color(0xFF2E7D32) : const Color(0xFFEF5350),
        ));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: statusColor.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_typeIcon(c.type),
                        color: statusColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.title,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: context.appTextPrimary)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 11, color: context.appTextHint),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('dd MMM yyyy')
                                  .format(c.scheduledDate),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: context.appTextHint),
                            ),
                            const SizedBox(width: 10),
                            Icon(Icons.pregnant_woman_rounded,
                                size: 11, color: context.appTextHint),
                            const SizedBox(width: 3),
                            Text('Week ${c.pregnancyWeek}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: context.appTextHint)),
                          ],
                        ),
                        if (c.notes != null && c.notes!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            c.notes!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: context.appTextSecondary,
                                height: 1.4),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          c.status.toUpperCase(),
                          style: TextStyle(
                              fontSize: 9,
                              color: statusColor,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isUpcoming)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F4F8),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(14)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(14)),
                    onTap: () => _confirmComplete(context, ref, c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              size: 15,
                              color:
                                  const Color(0xFF2E7D32).withValues(alpha: 0.8)),
                          const SizedBox(width: 6),
                          Text('Mark as Completed',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2E7D32)
                                      .withValues(alpha: 0.85))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmComplete(
      BuildContext context, WidgetRef ref, PregnancyCheckup c) async {
    final ctrl = TextEditingController();
    String? notes;
    try {
      notes = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Mark as Completed',
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            decoration: InputDecoration(
              hintText: 'Add notes (optional)',
              filled: true,
              fillColor: const Color(0xFFF7F4F8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.appBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.appBorder)),
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (notes == null) return;
    final ok = await ref
        .read(pregnancyProvider.notifier)
        .markCheckupComplete(c.id,
            notes: notes.isEmpty ? null : notes);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(ok ? 'Checkup marked as completed' : 'Failed to update'),
        backgroundColor:
            ok ? const Color(0xFF2E7D32) : const Color(0xFFEF5350),
      ));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'missed':
        return const Color(0xFFEF5350);
      case 'cancelled':
        return const Color(0xFF757575);
      default:
        return const Color(0xFF1976D2);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'ultrasound':
        return Icons.image_search_rounded;
      case 'blood_test':
        return Icons.biotech_rounded;
      case 'scan':
        return Icons.radar_rounded;
      case 'vaccination':
        return Icons.vaccines_rounded;
      default:
        return Icons.medical_services_rounded;
    }
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _CheckupsEmptyState extends StatelessWidget {
  const _CheckupsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE3F2FD), Color(0xFFEDE7F6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.calendar_month_rounded,
                  size: 48, color: Color(0xFF1976D2)),
            ),
            const SizedBox(height: 20),
            Text(
              'No Checkups Yet',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: context.appTextPrimary),
            ),
            const SizedBox(height: 10),
            Text(
              'Schedule your first prenatal appointment.\nYour doctor may also add checkups for you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.appTextHint, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Text('💡', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Regular checkups help monitor your baby\'s growth and keep you both healthy.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4A148C),
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add Checkup Button (extracted to own ConsumerStatefulWidget) ─────────────

class _AddCheckupButton extends ConsumerStatefulWidget {
  final TextEditingController titleCtrl;
  final TextEditingController notesCtrl;
  final DateTime? Function() getDate;
  final String Function() getType;
  final PregnancyProfile profile;
  final void Function(bool ok) onDone;

  const _AddCheckupButton({
    required this.titleCtrl,
    required this.notesCtrl,
    required this.getDate,
    required this.getType,
    required this.profile,
    required this.onDone,
  });

  @override
  ConsumerState<_AddCheckupButton> createState() =>
      _AddCheckupButtonState();
}

class _AddCheckupButtonState extends ConsumerState<_AddCheckupButton> {
  bool _submitting = false;

  Future<void> _submit() async {
    final title = widget.titleCtrl.text.trim();
    final date = widget.getDate();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a checkup title.')));
      return;
    }
    if (date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a date.')));
      return;
    }
    setState(() => _submitting = true);
    final checkup = PregnancyCheckup(
      id: '',
      patientId: widget.profile.patientId,
      type: widget.getType(),
      title: title,
      scheduledDate: date,
      status: 'upcoming',
      notes:
          widget.notesCtrl.text.trim().isEmpty ? null : widget.notesCtrl.text.trim(),
      pregnancyWeek: widget.profile.currentWeek,
      createdAt: DateTime.now(),
    );
    final ok =
        await ref.read(pregnancyProvider.notifier).addCheckup(checkup);
    if (mounted) setState(() => _submitting = false);
    widget.onDone(ok);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _submitting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Text('Add Checkup',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }
}

// ─── Skeleton ─────────────────────────────────────────────────────────────────

class _CheckupCardSkeleton extends StatelessWidget {
  const _CheckupCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8)
        ],
      ),
      child: const AppShimmer(
        child: Row(children: [
          SkeletonBox(width: 48, height: 48, radius: 12),
          SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                SkeletonBox(width: double.infinity, height: 14, radius: 4),
                SizedBox(height: 6),
                SkeletonBox(width: 200, height: 11, radius: 4),
                SizedBox(height: 6),
                SkeletonBox(width: 150, height: 11, radius: 4),
              ])),
          SizedBox(width: 10),
          SkeletonBox(width: 68, height: 24, radius: 12),
        ]),
      ),
    );
  }
}
