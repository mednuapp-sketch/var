import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../models/pregnancy_models.dart';
import '../providers/pregnancy_provider.dart';
import '../data/pregnancy_week_data.dart';
import '../../../core/widgets/ux_widgets.dart';

class PregnancyDashboardScreen extends ConsumerStatefulWidget {
  const PregnancyDashboardScreen({super.key});

  @override
  ConsumerState<PregnancyDashboardScreen> createState() =>
      _PregnancyDashboardScreenState();
}

class _PregnancyDashboardScreenState
    extends ConsumerState<PregnancyDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pregnancyProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pregnancyProvider);

    if (state.isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFF0F5),
        body: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const SizedBox(height: 60),
            const SkeletonBox(width: double.infinity, height: 180, radius: 24),
            const SizedBox(height: 16),
            const Row(children: [
              Expanded(child: SkeletonBox(width: double.infinity, height: 90, radius: 16)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(width: double.infinity, height: 90, radius: 16)),
            ]),
            const SizedBox(height: 16),
            ...List.generate(3, (_) => const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: SkeletonBox(width: double.infinity, height: 72, radius: 16),
            )),
          ]),
        ),
      );
    }

    if (!state.hasProfile) {
      return _buildNoProfile();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F5),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => ref.read(pregnancyProvider.notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            _buildAppBar(state.profile!),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _buildWeekCard(state.profile!),
                  _buildQuickActions(context),
                  _buildWeeklyDevCard(state.profile!),
                  _buildUpcomingCheckups(state.checkups),
                  _buildMedicinesCard(state.medicines),
                  _buildDoctorNotes(state.doctorNotes),
                  _buildRecentLogs(state.recentLogs),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.pregnancyJournal),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('Log Today', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildNoProfile() => Scaffold(
    backgroundColor: const Color(0xFFFFF0F5),
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF880E4F)),
        onPressed: () => context.pop(),
      ),
      title: const Text('Pregnancy Care',
          style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w700)),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFF8BBD9), Color(0xFFE1BEE7)]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.pregnant_woman_rounded, size: 52, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            const Text('Start Your Journey',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            const Text(
              'Create your pregnancy profile to get personalized care, weekly updates, and expert guidance.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF616161), height: 1.6),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => context.push(AppRoutes.pregnancyOnboarding),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Create Pregnancy Profile',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    ),
  );

  SliverAppBar _buildAppBar(PregnancyProfile profile) => SliverAppBar(
    expandedHeight: 180,
    pinned: true,
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
      onPressed: () => context.pop(),
    ),
    flexibleSpace: FlexibleSpaceBar(
      background: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('My Pregnancy', style: TextStyle(
                          color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('Week ${profile.currentWeek}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                      Text(profile.trimesterLabel,
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${profile.daysUntilDue} days to go',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Due ${DateFormat('dd MMM yyyy').format(profile.dueDate)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    actions: [
      IconButton(
        icon: const Icon(Icons.notifications_outlined),
        onPressed: () => context.push(AppRoutes.notifications),
      ),
    ],
  );

  Widget _buildWeekCard(PregnancyProfile profile) {
    final total = 40;
    final progress = profile.currentWeek / total;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _statChip(Icons.calendar_month_rounded, 'Week', '${profile.currentWeek}/40', const Color(0xFFC2185B)),
              const SizedBox(width: 10),
              _statChip(Icons.timeline_rounded, 'Trimester', profile.currentTrimester.toString(), const Color(0xFF7B1FA2)),
              const SizedBox(width: 10),
              _statChip(Icons.favorite_border_rounded, 'Days Left', '${profile.daysUntilDue}', const Color(0xFFE91E8C)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFFF5F5F5),
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Week 1', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
              Text('${(progress * 100).toInt()}% complete',
                  style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
              const Text('Week 40', style: TextStyle(fontSize: 10, color: AppColors.textHint)),
            ],
          ),
          if (profile.isHighRisk) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text('High-risk pregnancy — follow up with your doctor regularly.',
                        style: TextStyle(fontSize: 11, color: Color(0xFFE65100), fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
        ],
      ),
    ),
  );

  Widget _buildQuickActions(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(
      children: [
        _quickAction(context, Icons.medical_services_rounded, 'Medicines', AppRoutes.pregnancyMedicines, const Color(0xFF66BB6A)),
        const SizedBox(width: 8),
        _quickAction(context, Icons.calendar_month_rounded, 'Checkups', AppRoutes.pregnancyCheckups, const Color(0xFF42A5F5)),
        const SizedBox(width: 8),
        _quickAction(context, Icons.restaurant_rounded, 'Nutrition', AppRoutes.pregnancyNutrition, const Color(0xFFFFA726)),
        const SizedBox(width: 8),
        _quickAction(context, Icons.crisis_alert_rounded, 'Emergency', AppRoutes.pregnancyEmergency, const Color(0xFFEF5350)),
      ],
    ),
  );

  Widget _quickAction(BuildContext context, IconData icon, String label, String route, Color color) =>
      Expanded(
        child: GestureDetector(
          onTap: () => context.push(route),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
            ),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
          ),
        ),
      );

  Widget _buildWeeklyDevCard(PregnancyProfile profile) {
    final data = getWeekData(profile.currentWeek);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B1FA2), Color(0xFFC2185B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(AppRoutes.pregnancyWeekly),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.child_care_rounded, color: Colors.white70, size: 18),
                    const SizedBox(width: 6),
                    Text('Week ${profile.currentWeek} — Baby Development',
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 14),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data.babySizeComparison,
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                          Text('${data.babyLength} • ${data.babyWeight}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 8),
                          Text(data.development,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _fruitEmoji(profile.currentWeek),
                        style: const TextStyle(fontSize: 32),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fruitEmoji(int week) {
    const emojis = {
      4: '🌱', 5: '🫘', 6: '🌿', 7: '🫐', 8: '🍓', 10: '🍋',
      12: '🍈', 14: '🥝', 16: '🥑', 18: '🫑', 20: '🍌', 22: '🌽',
      24: '🌽', 26: '🥬', 28: '🍆', 30: '🥥', 32: '🎃', 36: '🥗',
      38: '🥦', 40: '🎃',
    };
    final keys = emojis.keys.toList()..sort();
    String emoji = '👶';
    for (final k in keys) {
      if (k <= week) emoji = emojis[k]!;
    }
    return emoji;
  }

  Widget _buildUpcomingCheckups(List<PregnancyCheckup> checkups) {
    final upcoming = checkups.where((c) =>
        c.status == 'upcoming' &&
        c.scheduledDate.isAfter(DateTime.now().subtract(const Duration(days: 1))))
        .take(3).toList();

    return _sectionContainer(
      title: 'Upcoming Checkups',
      icon: Icons.event_rounded,
      iconColor: const Color(0xFF42A5F5),
      onSeeAll: () => context.push(AppRoutes.pregnancyCheckups),
      child: upcoming.isEmpty
          ? _emptyState('No upcoming checkups', 'Your doctor will schedule them')
          : Column(
              children: upcoming.map((c) => _checkupTile(c)).toList(),
            ),
    );
  }

  Widget _checkupTile(PregnancyCheckup c) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F4F8),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF42A5F5).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_checkupIcon(c.type), color: const Color(0xFF42A5F5), size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(DateFormat('dd MMM yyyy').format(c.scheduledDate),
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF42A5F5).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('Week ${c.pregnancyWeek}',
              style: const TextStyle(fontSize: 10, color: Color(0xFF1565C0), fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  IconData _checkupIcon(String type) {
    switch (type) {
      case 'ultrasound': return Icons.image_search_rounded;
      case 'blood_test': return Icons.biotech_rounded;
      case 'scan': return Icons.radar_rounded;
      case 'vaccination': return Icons.vaccines_rounded;
      default: return Icons.medical_services_rounded;
    }
  }

  Widget _buildMedicinesCard(List<PregnancyMedicine> medicines) {
    final active = medicines.where((m) => m.isActive).take(3).toList();
    return _sectionContainer(
      title: 'My Medicines',
      icon: Icons.medication_rounded,
      iconColor: const Color(0xFF66BB6A),
      onSeeAll: () => context.push(AppRoutes.pregnancyMedicines),
      child: active.isEmpty
          ? _emptyState('No medicines yet', 'Your doctor will prescribe as needed')
          : Column(children: active.map((m) => _medicineTile(m)).toList()),
    );
  }

  Widget _medicineTile(PregnancyMedicine m) {
    final typeColor = _medTypeColor(m.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: typeColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(_medIcon(m.type), color: typeColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('${m.dosage} • ${m.frequency}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(m.type[0].toUpperCase() + m.type.substring(1),
                style: TextStyle(fontSize: 9, color: typeColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Color _medTypeColor(String type) {
    switch (type) {
      case 'vitamin': return const Color(0xFFFFA726);
      case 'supplement': return const Color(0xFF26C6DA);
      case 'injection': return const Color(0xFFAB47BC);
      default: return const Color(0xFF66BB6A);
    }
  }

  IconData _medIcon(String type) {
    switch (type) {
      case 'vitamin': return Icons.emoji_food_beverage_rounded;
      case 'supplement': return Icons.science_rounded;
      case 'injection': return Icons.vaccines_rounded;
      default: return Icons.medication_rounded;
    }
  }

  Widget _buildDoctorNotes(List<PregnancyDoctorNote> notes) {
    if (notes.isEmpty) return const SizedBox.shrink();
    return _sectionContainer(
      title: 'Doctor\'s Notes',
      icon: Icons.notes_rounded,
      iconColor: const Color(0xFF7B1FA2),
      child: Column(
        children: notes.take(2).map((n) => _doctorNoteTile(n)).toList(),
      ),
    );
  }

  Widget _doctorNoteTile(PregnancyDoctorNote n) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF3E5F5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF7B1FA2).withValues(alpha: 0.15)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.person_rounded, size: 14, color: Color(0xFF7B1FA2)),
            const SizedBox(width: 4),
            Text('Dr. ${n.doctorName}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7B1FA2))),
            const Spacer(),
            Text(DateFormat('dd MMM').format(n.createdAt),
                style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
          ],
        ),
        const SizedBox(height: 6),
        Text(n.content, style: const TextStyle(fontSize: 12, height: 1.5)),
        if (n.recommendation != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.tips_and_updates_rounded, size: 13, color: Color(0xFFFFA726)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(n.recommendation!,
                    style: const TextStyle(fontSize: 11, color: Color(0xFFE65100), fontStyle: FontStyle.italic)),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _buildRecentLogs(List<PregnancyWeeklyLog> logs) {
    if (logs.isEmpty) return const SizedBox.shrink();
    return _sectionContainer(
      title: 'Recent Journal Entries',
      icon: Icons.book_rounded,
      iconColor: const Color(0xFFC2185B),
      child: Column(
        children: logs.take(3).map((l) => _logTile(l)).toList(),
      ),
    );
  }

  Widget _logTile(PregnancyWeeklyLog l) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFCE4EC),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text(_moodEmoji(l.mood), style: const TextStyle(fontSize: 20))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Week ${l.pregnancyWeek} — ${l.mood}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              if (l.symptoms.isNotEmpty)
                Text(l.symptoms.take(3).join(' • '),
                    style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
            ],
          ),
        ),
        Text(DateFormat('dd MMM').format(l.loggedAt),
            style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
      ],
    ),
  );

  String _moodEmoji(String mood) {
    const map = {
      'Happy': '😊', 'Calm': '😌', 'Anxious': '😰', 'Excited': '🥰',
      'Tired': '😴', 'Irritable': '😤', 'Sad': '😢', 'Hopeful': '🌟',
      'Overwhelmed': '😵', 'Grateful': '🙏',
    };
    return map[mood] ?? '💗';
  }

  Widget _sectionContainer({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
    VoidCallback? onSeeAll,
  }) =>
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A2E))),
                ),
                if (onSeeAll != null)
                  GestureDetector(
                    onTap: onSeeAll,
                    child: const Text('See all',
                        style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _emptyState(String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textHint),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
          ],
        ),
      ],
    ),
  );
}
