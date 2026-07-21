import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/pregnancy_models.dart';
import '../providers/pregnancy_provider.dart';
import '../data/pregnancy_week_data.dart';
import '../../../core/utils/r.dart';

class PregnancyDashboardScreen extends ConsumerStatefulWidget {
  const PregnancyDashboardScreen({super.key});

  @override
  ConsumerState<PregnancyDashboardScreen> createState() =>
      _PregnancyDashboardScreenState();
}

class _PregnancyDashboardScreenState
    extends ConsumerState<PregnancyDashboardScreen>
    with TickerProviderStateMixin {
  late final AnimationController _heroAnim;
  late final Animation<double> _heroFade;

  @override
  void initState() {
    super.initState();
    _heroAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _heroFade = CurvedAnimation(parent: _heroAnim, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pregnancyProvider.notifier).refresh();
      _heroAnim.forward();
    });
  }

  @override
  void dispose() {
    _heroAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pregnancyProvider);
    if (state.isLoading) return _buildShimmer();
    if (!state.hasProfile) return _buildNoProfile();

    return Scaffold(
      backgroundColor: context.appBackground,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => ref.read(pregnancyProvider.notifier).refresh(),
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(state.profile!),
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _heroFade,
                child: Column(
                  children: [
                    _buildHeroWeekCard(state.profile!),
                    _buildBabySizeCard(state.profile!),
                    _buildQuickActions(),
                    _buildWeightSummaryCard(state),
                    _buildWeeklyDevCard(state.profile!),
                    _buildUpcomingCheckups(state.checkups),
                    _buildMedicinesCard(state.medicines),
                    if (state.doctorNotes.isNotEmpty) _buildDoctorNotes(state.doctorNotes),
                    if (state.recentLogs.isNotEmpty) _buildRecentLogs(state.recentLogs),
                    SizedBox(height: R.h(context, 100)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.pregnancyJournal),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.edit_note_rounded),
        label: Text('Log Today', style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
      ),
    );
  }

  // ── Shimmer Loading ────────────────────────────────────────────────────────

  Widget _buildShimmer() => Scaffold(
    backgroundColor: context.appBackground,
    body: AppShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            const SkeletonBox(width: double.infinity, height: 220, radius: 0),
            SizedBox(height: R.h(context, 12)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: R.p(context, 16)),
              child: Column(
                children: [
                  const SkeletonBox(width: double.infinity, height: 120, radius: 20),
                  SizedBox(height: R.h(context, 12)),
                  const SkeletonBox(width: double.infinity, height: 100, radius: 20),
                  SizedBox(height: R.h(context, 12)),
                  Row(children: [
                    for (int i = 0; i < 4; i++) ...[
                      Expanded(child: SkeletonBox(width: double.infinity, height: 80, radius: 14)),
                      if (i < 3) SizedBox(width: R.w(context, 10)),
                    ],
                  ]),
                  SizedBox(height: R.h(context, 12)),
                  const SkeletonBox(width: double.infinity, height: 130, radius: 20),
                  SizedBox(height: R.h(context, 12)),
                  const SkeletonBox(width: double.infinity, height: 160, radius: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ── No Profile ─────────────────────────────────────────────────────────────

  Widget _buildNoProfile() => Scaffold(
    backgroundColor: context.appBackground,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
        onPressed: () => context.pop(),
      ),
      title: Text('Pregnancy Care',
          style: AppTextStyles.h3.copyWith(color: context.appTextPrimary)),
    ),
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(R.p(context, 32)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: R.w(context, 120),
              height: R.w(context, 120),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFFF8BBD9), Color(0xFFE1BEE7)]),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('🤰', style: TextStyle(fontSize: 52))),
            ),
            SizedBox(height: R.h(context, 28)),
            Text('Start Your Journey',
                style: AppTextStyles.display.copyWith(color: context.appTextPrimary)),
            SizedBox(height: R.h(context, 10)),
            Text(
              'Create your pregnancy profile to get personalized care, weekly updates, and expert guidance.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(color: context.appTextSecondary),
            ),
            SizedBox(height: R.h(context, 36)),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.pregnancyGrad,
                borderRadius: BorderRadius.circular(R.r(context, 14)),
                boxShadow: [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 14, offset: const Offset(0, 5))],
              ),
              child: ElevatedButton(
                onPressed: () => context.push(AppRoutes.pregnancyOnboarding),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.symmetric(horizontal: R.p(context, 40), vertical: R.p(context, 16)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 14))),
                ),
                child: Text('Create Pregnancy Profile', style: AppTextStyles.button),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ── Sliver App Bar ─────────────────────────────────────────────────────────

  SliverAppBar _buildSliverAppBar(PregnancyProfile profile) => SliverAppBar(
    expandedHeight: R.h(context, 210),
    pinned: true,
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
      onPressed: () => context.pop(),
    ),
    actions: [
      IconButton(
        icon: const Icon(Icons.notifications_outlined, color: Colors.white),
        onPressed: () => context.push(AppRoutes.notifications),
      ),
    ],
    flexibleSpace: FlexibleSpaceBar(
      background: Container(
        decoration: const BoxDecoration(gradient: AppColors.pregnancyGrad),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                reverse: true,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
            padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 56), R.p(context, 20), R.p(context, 20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('My Pregnancy',
                    style: AppTextStyles.onPrimaryBody),
                SizedBox(height: R.h(context, 4)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Week ${profile.currentWeek}',
                              style: AppTextStyles.display.copyWith(
                                  color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                          Text(profile.trimesterLabel,
                              style: AppTextStyles.onPrimaryBody),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: R.p(context, 14), vertical: R.p(context, 7)),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(R.r(context, 20)),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '${profile.daysUntilDue} days left',
                            style: AppTextStyles.labelMedium.copyWith(color: Colors.white),
                          ),
                        ),
                        SizedBox(height: R.h(context, 6)),
                        Text(
                          'Due ${DateFormat('dd MMM yyyy').format(profile.dueDate)}',
                          style: AppTextStyles.onPrimaryBody,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  // ── Hero Week Progress Card ────────────────────────────────────────────────

  Widget _buildHeroWeekCard(PregnancyProfile profile) {
    final progress = profile.currentWeek / 40;
    return Container(
      margin: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 16), R.p(context, 16), R.p(context, 8)),
      padding: EdgeInsets.all(R.p(context, 18)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 20)),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 15, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _statPill('Week', '${profile.currentWeek}/40', AppColors.primary, Icons.calendar_month_rounded),
              SizedBox(width: R.w(context, 10)),
              _statPill('Trimester', '${profile.currentTrimester}rd', AppColors.secondary, Icons.timeline_rounded),
              SizedBox(width: R.w(context, 10)),
              _statPill('Days Left', '${profile.daysUntilDue}', AppColors.primaryLight, Icons.favorite_rounded),
            ],
          ),
          SizedBox(height: R.h(context, 16)),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.r(context, 8)),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: context.appBorder,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              minHeight: 10,
            ),
          ),
          SizedBox(height: R.h(context, 8)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Week 1', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
              Text('${(progress * 100).toInt()}% of journey complete',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
              Text('Week 40', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
            ],
          ),
          if (profile.isHighRisk) ...[
            SizedBox(height: R.h(context, 12)),
            Container(
              padding: EdgeInsets.symmetric(horizontal: R.p(context, 12), vertical: R.p(context, 8)),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(R.r(context, 10)),
                border: Border.all(color: const Color(0xFFFFC107).withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: const Color(0xFFE65100), size: R.w(context, 16)),
                  SizedBox(width: R.w(context, 8)),
                  Expanded(
                    child: Text('High-risk pregnancy — follow up with your doctor regularly.',
                        style: AppTextStyles.bodySmall.copyWith(
                            color: const Color(0xFFE65100), fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statPill(String label, String value, Color color, IconData icon) => Expanded(
    child: Container(
      padding: EdgeInsets.symmetric(vertical: R.p(context, 12)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.r(context, 12)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: R.w(context, 18)),
          SizedBox(height: R.h(context, 4)),
          Text(value, style: AppTextStyles.labelLarge.copyWith(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
          Text(label, style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
        ],
      ),
    ),
  );

  // ── Baby Size Card ─────────────────────────────────────────────────────────

  Widget _buildBabySizeCard(PregnancyProfile profile) {
    final data = getWeekData(profile.currentWeek);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: R.p(context, 16), vertical: R.p(context, 8)),
      padding: EdgeInsets.all(R.p(context, 18)),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B1FA2), Color(0xFFC2185B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(R.r(context, 20)),
        boxShadow: [BoxShadow(color: AppColors.secondary.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your Baby This Week',
                    style: AppTextStyles.onPrimaryBody),
                SizedBox(height: R.h(context, 6)),
                Text(data.babySizeComparison,
                    style: AppTextStyles.h2.copyWith(color: Colors.white, fontSize: 22)),
                Text('${data.babyLength} · ${data.babyWeight}',
                    style: AppTextStyles.onPrimaryBody),
                SizedBox(height: R.h(context, 10)),
                Text(data.development,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(color: Colors.white, height: 1.5)),
                SizedBox(height: R.h(context, 12)),
                GestureDetector(
                  onTap: () => context.push(AppRoutes.pregnancyWeekly),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: R.p(context, 14), vertical: R.p(context, 8)),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(R.r(context, 20)),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('View week guide',
                            style: AppTextStyles.bodySmall.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                        SizedBox(width: R.w(context, 4)),
                        Icon(Icons.arrow_forward_rounded, color: Colors.white, size: R.w(context, 14)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: R.w(context, 16)),
          Container(
            width: R.w(context, 80),
            height: R.w(context, 80),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
            ),
            child: Center(child: Text(_fruitEmoji(profile.currentWeek), style: const TextStyle(fontSize: 40))),
          ),
        ],
      ),
    );
  }

  // ── Quick Actions ──────────────────────────────────────────────────────────

  Widget _buildQuickActions() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Access', style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
        const SizedBox(height: 12),
        staticGrid(
          crossAxisCount: 4,
          aspectRatio: 0.85,
          children: [
            _quickTile(Icons.medical_services_rounded, 'Medicines', const Color(0xFF66BB6A), AppRoutes.pregnancyMedicines),
            _quickTile(Icons.calendar_month_rounded, 'Checkups', const Color(0xFF42A5F5), AppRoutes.pregnancyCheckups),
            _quickTile(Icons.restaurant_rounded, 'Nutrition', const Color(0xFFFFA726), AppRoutes.pregnancyNutrition),
            _quickTile(Icons.crisis_alert_rounded, 'Emergency', const Color(0xFFEF5350), AppRoutes.pregnancyEmergency),
            _quickTile(Icons.monitor_weight_rounded, 'Weight', AppColors.secondary, AppRoutes.pregnancyWeight),
            _quickTile(Icons.auto_graph_rounded, 'Weekly', AppColors.primary, AppRoutes.pregnancyWeekly),
            _quickTile(Icons.book_rounded, 'Journal', const Color(0xFF26C6DA), AppRoutes.pregnancyJournal),
            _quickTile(Icons.medical_information_rounded, 'Profile', const Color(0xFFAB47BC), AppRoutes.pregnancyOnboarding),
          ],
        ),
      ],
    ),
  );

  Widget _quickTile(IconData icon, String label, Color color, String route) =>
      GestureDetector(
        onTap: () => context.push(route),
        child: Container(
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 7),
              Text(label,
                  style: AppTextStyles.labelSmall.copyWith(color: context.appTextPrimary),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  // ── Weight Summary ─────────────────────────────────────────────────────────

  Widget _buildWeightSummaryCard(PregnancyState state) {
    final profile = state.profile!;
    final startWeight = profile.weightKg;
    final currentWeight = state.currentWeightKg;
    final gain = state.weightGainKg;
    final (minGain, maxGain) = profile.recommendedWeightGain;
    final hasLogs = state.weightLogs.isNotEmpty;
    final lastLog = state.latestWeightLog;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.pregnancyWeight),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.monitor_weight_rounded, color: AppColors.secondary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('Weight Tracker',
                    style: AppTextStyles.h4.copyWith(color: context.appTextPrimary))),
                Icon(Icons.arrow_forward_ios_rounded, size: 13, color: context.appTextHint),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _weightChip('Start', '${startWeight.toStringAsFixed(1)} kg', AppColors.secondary),
                const SizedBox(width: 8),
                _weightChip('Current', hasLogs ? '${currentWeight.toStringAsFixed(1)} kg' : '— kg', AppColors.primary),
                const SizedBox(width: 8),
                _weightChip(
                  'Gained',
                  gain > 0 ? '+${gain.toStringAsFixed(1)} kg' : '0.0 kg',
                  gain > maxGain ? AppColors.error : AppColors.success,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: context.appTextHint),
                const SizedBox(width: 5),
                Text(
                  'Recommended: ${minGain.toStringAsFixed(1)}–${maxGain.toStringAsFixed(1)} kg',
                  style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
                ),
                const Spacer(),
                if (lastLog != null)
                  Text(
                    'Updated ${DateFormat('dd MMM').format(lastLog.loggedAt)}',
                    style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _weightChip(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: AppTextStyles.labelLarge.copyWith(color: color, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
        ],
      ),
    ),
  );

  // ── Weekly Dev Card ────────────────────────────────────────────────────────

  Widget _buildWeeklyDevCard(PregnancyProfile profile) {
    final data = getWeekData(profile.currentWeek);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tips_and_updates_rounded, color: Color(0xFFFFA726), size: 18),
              const SizedBox(width: 8),
              Text('Tip of the Day', style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDE7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFC107).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Text('💡', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(data.weeklyTip,
                      style: AppTextStyles.bodyMedium.copyWith(color: context.appTextPrimary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text('🌙', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(data.motherChanges,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondary, height: 1.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Upcoming Checkups ──────────────────────────────────────────────────────

  Widget _buildUpcomingCheckups(List<PregnancyCheckup> checkups) {
    final upcoming = checkups
        .where((c) => c.status == 'upcoming' && c.scheduledDate.isAfter(DateTime.now().subtract(const Duration(days: 1))))
        .take(3)
        .toList();

    return _sectionCard(
      title: 'Upcoming Checkups',
      icon: Icons.event_rounded,
      iconColor: const Color(0xFF42A5F5),
      onSeeAll: () => context.push(AppRoutes.pregnancyCheckups),
      child: upcoming.isEmpty
          ? _emptyState('No upcoming checkups', 'Your doctor will schedule them soon', Icons.event_available_rounded)
          : Column(children: upcoming.map(_checkupTile).toList()),
    );
  }

  Widget _checkupTile(PregnancyCheckup c) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.appBackground,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.appBorder),
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
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.title, style: AppTextStyles.labelLarge.copyWith(color: context.appTextPrimary)),
              Text(DateFormat('dd MMM yyyy').format(c.scheduledDate),
                  style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF42A5F5).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('Wk ${c.pregnancyWeek}',
              style: AppTextStyles.labelSmall.copyWith(color: const Color(0xFF1565C0))),
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

  // ── Medicines ──────────────────────────────────────────────────────────────

  Widget _buildMedicinesCard(List<PregnancyMedicine> medicines) {
    final active = medicines.where((m) => m.isActive).take(3).toList();
    return _sectionCard(
      title: 'My Medicines',
      icon: Icons.medication_rounded,
      iconColor: const Color(0xFF66BB6A),
      onSeeAll: () => context.push(AppRoutes.pregnancyMedicines),
      child: active.isEmpty
          ? _emptyState('No medicines listed', 'Your doctor will prescribe as needed', Icons.medication_outlined)
          : Column(children: active.map(_medicineTile).toList()),
    );
  }

  Widget _medicineTile(PregnancyMedicine m) {
    final color = _medTypeColor(m.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(_medIcon(m.type), color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name, style: AppTextStyles.labelLarge.copyWith(color: context.appTextPrimary)),
                Text('${m.dosage} · ${m.frequency}',
                    style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(m.type[0].toUpperCase() + m.type.substring(1),
                style: AppTextStyles.labelSmall.copyWith(color: color)),
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

  // ── Doctor Notes ───────────────────────────────────────────────────────────

  Widget _buildDoctorNotes(List<PregnancyDoctorNote> notes) => _sectionCard(
    title: "Doctor's Notes",
    icon: Icons.notes_rounded,
    iconColor: AppColors.secondary,
    child: Column(
      children: notes.take(2).map((n) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.secondary.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_rounded, size: 14, color: AppColors.secondary),
                const SizedBox(width: 5),
                Text('Dr. ${n.doctorName}',
                    style: AppTextStyles.labelMedium.copyWith(color: AppColors.secondary)),
                const Spacer(),
                Text(DateFormat('dd MMM').format(n.createdAt),
                    style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
              ],
            ),
            const SizedBox(height: 6),
            Text(n.content, style: AppTextStyles.bodySmall.copyWith(color: context.appTextPrimary, height: 1.5)),
            if (n.recommendation != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.tips_and_updates_rounded, size: 13, color: Color(0xFFFFA726)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(n.recommendation!,
                        style: AppTextStyles.bodySmall.copyWith(
                            color: const Color(0xFFE65100), fontStyle: FontStyle.italic)),
                  ),
                ],
              ),
            ],
          ],
        ),
      )).toList(),
    ),
  );

  // ── Recent Journal Logs ────────────────────────────────────────────────────

  Widget _buildRecentLogs(List<PregnancyWeeklyLog> logs) => _sectionCard(
    title: 'Recent Journal Entries',
    icon: Icons.book_rounded,
    iconColor: AppColors.primary,
    onSeeAll: () => context.push(AppRoutes.pregnancyJournal),
    child: Column(
      children: logs.take(3).map((l) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
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
                  Text('Week ${l.pregnancyWeek} · ${l.mood}',
                      style: AppTextStyles.labelMedium.copyWith(color: context.appTextPrimary)),
                  if (l.symptoms.isNotEmpty)
                    Text(l.symptoms.take(3).join(' · '),
                        style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
                ],
              ),
            ),
            Text(DateFormat('dd MMM').format(l.loggedAt),
                style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
          ],
        ),
      )).toList(),
    ),
  );

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _fruitEmoji(int week) {
    const emojis = {
      4: '🌱', 5: '🫘', 6: '🌿', 7: '🫐', 8: '🍓', 10: '🍋',
      12: '🍈', 14: '🥝', 16: '🥑', 18: '🫑', 20: '🍌', 22: '🌽',
      24: '🌽', 26: '🥬', 28: '🍆', 30: '🥥', 32: '🎃', 36: '🥗',
      38: '🥦', 40: '👶',
    };
    final keys = emojis.keys.toList()..sort();
    String emoji = '👶';
    for (final k in keys) { if (k <= week) emoji = emojis[k]!; }
    return emoji;
  }

  String _moodEmoji(String mood) {
    const map = {
      'Happy': '😊', 'Calm': '😌', 'Anxious': '😰', 'Excited': '🥰',
      'Tired': '😴', 'Irritable': '😤', 'Sad': '😢', 'Hopeful': '🌟',
      'Overwhelmed': '😵', 'Grateful': '🙏',
    };
    return map[mood] ?? '💗';
  }

  Widget _sectionCard({
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
          color: context.appSurface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 17),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: AppTextStyles.h4.copyWith(color: context.appTextPrimary))),
                if (onSeeAll != null)
                  GestureDetector(
                    onTap: onSeeAll,
                    child: Text('See all',
                        style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );

  Widget _emptyState(String title, String subtitle, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: context.appTextHint),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.bodyMedium.copyWith(color: context.appTextSecondary, fontWeight: FontWeight.w500)),
            Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
          ],
        ),
      ],
    ),
  );
}
