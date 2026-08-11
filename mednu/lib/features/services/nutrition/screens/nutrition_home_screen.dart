import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mednu/core/constants/app_colors.dart';
import 'package:mednu/core/constants/app_text_styles.dart';
import 'package:mednu/core/router/app_router.dart';
import 'package:mednu/core/widgets/ux_widgets.dart';
import 'package:mednu/core/utils/r.dart';
import '../models/nutritionist_model.dart';
import '../models/nutrition_appointment_model.dart';
import '../models/nutrition_goal_model.dart';
import '../providers/nutrition_provider.dart';

class NutritionHomeScreen extends ConsumerWidget {
  const NutritionHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nutritionists = ref.watch(nutritionistsStreamProvider);
    final appointments  = ref.watch(nutritionAppointmentsProvider);
    final todayCals     = ref.watch(todayCaloriesProvider);
    final goal          = ref.watch(activeNutritionGoalProvider);
    final waterGlasses  = ref.watch(waterGlassesProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 32)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: R.h(context, 20)),
                  _DailySummaryCard(
                    todayCals: todayCals,
                    goal: goal,
                    waterGlasses: waterGlasses,
                  ),
                  SizedBox(height: R.h(context, 20)),
                  _QuickActionsGrid(
                    onDashboard: () => context.push(AppRoutes.nutritionDashboard),
                    onMeals:     () => context.push(AppRoutes.nutritionMeals),
                    onGoals:     () => context.push(AppRoutes.nutritionGoals),
                    onBmi:       () => context.push(AppRoutes.nutritionBmi),
                  ),
                  SizedBox(height: R.h(context, 20)),
                  _FindNutritionistBanner(
                    onTap: () => context.push(AppRoutes.nutritionNutritionists),
                  ),
                  SizedBox(height: R.h(context, 20)),
                  _UpcomingAppointments(appointments: appointments),
                  SizedBox(height: R.h(context, 20)),
                  _HealthGoalsChips(
                    onTap: () => context.push(AppRoutes.nutritionGoals),
                  ),
                  SizedBox(height: R.h(context, 20)),
                  _FeaturedNutritionistsSection(
                    nutritionists: nutritionists,
                    onViewAll: () => context.push(AppRoutes.nutritionNutritionists),
                    onTap: (id) => context.push(
                      AppRoutes.nutritionNutritionistProfile.replaceFirst(':id', id),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: R.h(context, 170),
      backgroundColor: AppColors.accent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        onPressed: () => context.pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Container(
          decoration: const BoxDecoration(gradient: AppColors.nutritionGrad),
          child: Stack(
            children: [
              Positioned(
                top: -R.h(context, 30),
                right: -R.w(context, 30),
                child: Container(
                  width: R.w(context, 160),
                  height: R.h(context, 160),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 52), R.p(context, 20), R.p(context, 16)),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(R.p(context, 10)),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(R.r(context, 14)),
                                ),
                                child: Icon(Icons.restaurant_rounded, color: Colors.white, size: R.w(context, 26)),
                              ),
                              SizedBox(width: R.w(context, 14)),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Nutrition & Diet', style: AppTextStyles.onPrimaryH2),
                                    Text('Your daily wellness hub', style: AppTextStyles.onPrimaryBody),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
    );
  }
}

// ─── Daily Summary Card ───────────────────────────────────────────────────────

class _DailySummaryCard extends StatelessWidget {
  final AsyncValue<double> todayCals;
  final AsyncValue<NutritionGoalModel?> goal;
  final AsyncValue<int> waterGlasses;

  const _DailySummaryCard({
    required this.todayCals,
    required this.goal,
    required this.waterGlasses,
  });

  @override
  Widget build(BuildContext context) {
    final cals          = todayCals.valueOrNull ?? 0.0;
    final goalModel     = goal.valueOrNull;
    final targetCals    = goalModel?.targetCalories ?? 2000.0;
    final targetWater   = goalModel?.targetWaterLiters ?? 2.5;
    final glasses       = waterGlasses.valueOrNull ?? 0;
    final consumedWater = glasses * 0.25;
    final calorieProgress = (cals / targetCals).clamp(0.0, 1.0);
    final waterProgress   = (consumedWater / targetWater).clamp(0.0, 1.0);

    return Container(
      padding: EdgeInsets.all(R.p(context, 18)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 20)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today_rounded, color: AppColors.accent, size: 18),
              SizedBox(width: R.w(context, 6)),
              Text("Today's Summary", style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
            ],
          ),
          SizedBox(height: R.h(context, 16)),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: const Color(0xFFE65100),
                  bgColor: const Color(0xFFFFF3E0),
                  value: '${cals.toInt()}',
                  unit: 'kcal',
                  label: 'Calories',
                  subLabel: 'of ${targetCals.toInt()}',
                  progress: calorieProgress,
                  progressColor: const Color(0xFFE65100),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.water_drop_rounded,
                  iconColor: AppColors.info,
                  bgColor: const Color(0xFFE3F2FD),
                  value: consumedWater.toStringAsFixed(1),
                  unit: 'L',
                  label: 'Water',
                  subLabel: 'of ${targetWater.toStringAsFixed(1)}L',
                  progress: waterProgress,
                  progressColor: AppColors.info,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String value;
  final String unit;
  final String label;
  final String subLabel;
  final double progress;
  final Color progressColor;

  const _SummaryMetric({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.value,
    required this.unit,
    required this.label,
    required this.subLabel,
    required this.progress,
    required this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              text: value,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: iconColor),
              children: [
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w500, color: iconColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.labelSmall.copyWith(color: context.appTextPrimary)),
          Text(subLabel, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: progressColor.withValues(alpha: 0.15),
              color: progressColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick Actions Grid ───────────────────────────────────────────────────────

class _QuickActionsGrid extends StatelessWidget {
  final VoidCallback onDashboard;
  final VoidCallback onMeals;
  final VoidCallback onGoals;
  final VoidCallback onBmi;

  const _QuickActionsGrid({
    required this.onDashboard,
    required this.onMeals,
    required this.onGoals,
    required this.onBmi,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(Icons.dashboard_rounded, 'Dashboard', AppColors.accent),
      _QuickAction(Icons.restaurant_menu_rounded, 'Track Meals', const Color(0xFFE65100)),
      _QuickAction(Icons.flag_rounded, 'My Goals', AppColors.secondary),
      _QuickAction(Icons.calculate_rounded, 'BMI Check', AppColors.info),
    ];
    final callbacks = [onDashboard, onMeals, onGoals, onBmi];

    return staticGrid(
      crossAxisCount: 4,
      mainAxisSpacing: 0,
      crossAxisSpacing: 10,
      aspectRatio: 0.82,
      children: List.generate(actions.length,
          (i) => _QuickActionTile(action: actions[i], onTap: callbacks[i])),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  const _QuickAction(this.icon, this.label, this.color);
}

class _QuickActionTile extends StatelessWidget {
  final _QuickAction action;
  final VoidCallback onTap;
  const _QuickActionTile({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: action.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: action.color.withValues(alpha: 0.20)),
            ),
            child: Icon(action.icon, color: action.color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            action.label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: action.color,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Find Nutritionist Banner ─────────────────────────────────────────────────

class _FindNutritionistBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _FindNutritionistBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Find a Nutritionist',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Book personalised diet consultations\nwith certified dietitians',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      'Browse Now',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.person_search_rounded, color: Colors.white, size: 72),
          ],
        ),
      ),
    );
  }
}

// ─── Upcoming Appointments ────────────────────────────────────────────────────

class _UpcomingAppointments extends StatelessWidget {
  final AsyncValue<List<NutritionAppointmentModel>> appointments;
  const _UpcomingAppointments({required this.appointments});

  @override
  Widget build(BuildContext context) {
    return appointments.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, __) => const SizedBox.shrink(),
      data: (list) {
        final upcoming = list
            .where((a) => a.status == 'pending' || a.status == 'confirmed')
            .take(2)
            .toList();
        if (upcoming.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: 'Upcoming Consultations'),
            const SizedBox(height: 12),
            ...upcoming.map((a) => _AppointmentTile(appointment: a)),
          ],
        );
      },
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  final NutritionAppointmentModel appointment;
  const _AppointmentTile({required this.appointment});

  @override
  Widget build(BuildContext context) {
    final isConfirmed = appointment.status == 'confirmed';
    final statusColor = isConfirmed ? AppColors.success : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.18)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_rounded, color: AppColors.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appointment.nutritionistName, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(
                  '${appointment.date}  •  ${appointment.timeSlot}',
                  style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                ),
                Text(
                  appointment.consultationType == 'online' ? 'Online Consultation' : 'In-Person',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.accent, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              appointment.statusLabel,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: statusColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Health Goals Chips ───────────────────────────────────────────────────────

class _HealthGoalsChips extends StatelessWidget {
  final VoidCallback onTap;
  const _HealthGoalsChips({required this.onTap});

  static const _goals = [
    _GoalChip(Icons.monitor_weight_rounded, 'Weight Loss', AppColors.success),
    _GoalChip(Icons.bloodtype_rounded, 'Diabetes Diet', Color(0xFFB71C1C)),
    _GoalChip(Icons.favorite_rounded, 'Heart Healthy', AppColors.primary),
    _GoalChip(Icons.pregnant_woman_rounded, 'Pregnancy', AppColors.secondary),
    _GoalChip(Icons.fitness_center_rounded, 'Sports', AppColors.info),
    _GoalChip(Icons.spa_rounded, 'PCOS Diet', AppColors.accent),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _SectionTitle(title: 'Health Goals'),
            GestureDetector(
              onTap: onTap,
              child: Text(
                'Set Goal →',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.accent),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _goals.map((g) => _GoalChipWidget(chip: g, onTap: onTap)).toList(),
        ),
      ],
    );
  }
}

class _GoalChip {
  final IconData icon;
  final String label;
  final Color color;
  const _GoalChip(this.icon, this.label, this.color);
}

class _GoalChipWidget extends StatelessWidget {
  final _GoalChip chip;
  final VoidCallback onTap;
  const _GoalChipWidget({required this.chip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: chip.color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: chip.color.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(chip.icon, color: chip.color, size: 15),
            const SizedBox(width: 6),
            Text(
              chip.label,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: chip.color),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Featured Nutritionists ───────────────────────────────────────────────────

class _FeaturedNutritionistsSection extends StatelessWidget {
  final AsyncValue<List<NutritionistModel>> nutritionists;
  final VoidCallback onViewAll;
  final void Function(String id) onTap;

  const _FeaturedNutritionistsSection({
    required this.nutritionists,
    required this.onViewAll,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _SectionTitle(title: 'Featured Nutritionists'),
            GestureDetector(
              onTap: onViewAll,
              child: Text('View All →', style: AppTextStyles.labelSmall.copyWith(color: AppColors.accent)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        nutritionists.when(
          loading: () => const AppShimmer(
            child: Column(
              children: [
                _NutritionistCardSkeleton(),
                SizedBox(height: 12),
                _NutritionistCardSkeleton(),
                SizedBox(height: 12),
                _NutritionistCardSkeleton(),
              ],
            ),
          ),
          error: (_, __) => const AppErrorState(),
          data: (list) {
            if (list.isEmpty) {
              return _EmptyNutritionists(onAdd: onViewAll);
            }
            return Column(
              children: [
                ...list.take(3).map((n) => _NutritionistCard(
                      nutritionist: n,
                      onTap: () => onTap(n.id),
                    )),
                const SizedBox(height: 4),
                _ViewAllButton(onTap: onViewAll),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EmptyNutritionists extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyNutritionists({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        children: [
          Icon(Icons.person_search_rounded, size: 52, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('No Nutritionists Yet', style: AppTextStyles.labelLarge.copyWith(color: context.appTextSecondary)),
          const SizedBox(height: 4),
          Text(
            'Nutritionists will appear here\nonce added by admin',
            style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NutritionistCardSkeleton extends StatelessWidget {
  const _NutritionistCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(16)),
      child: const Row(
        children: [
          SkeletonBox(width: 56, height: 56, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: double.infinity, height: 13, radius: 6),
                SizedBox(height: 6),
                SkeletonBox(width: 150, height: 11, radius: 6),
                SizedBox(height: 6),
                SkeletonBox(width: 100, height: 11, radius: 6),
              ],
            ),
          ),
          SizedBox(width: 8),
          SkeletonBox(width: 58, height: 32, radius: 10),
        ],
      ),
    );
  }
}

class _NutritionistCard extends StatelessWidget {
  final NutritionistModel nutritionist;
  final VoidCallback onTap;

  const _NutritionistCard({required this.nutritionist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.appBorder),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: nutritionist.photoUrl.isNotEmpty
                  ? Image.network(
                      nutritionist.photoUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      cacheWidth: 168,
                      cacheHeight: 168,
                      errorBuilder: (_, __, ___) => _AvatarFallback(name: nutritionist.name),
                    )
                  : _AvatarFallback(name: nutritionist.name),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nutritionist.name, style: AppTextStyles.labelLarge),
                  Text(
                    '${nutritionist.qualification} • ${nutritionist.specialization}',
                    style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFF9A825), size: 14),
                      const SizedBox(width: 2),
                      Text(
                        nutritionist.rating.toStringAsFixed(1),
                        style: AppTextStyles.labelSmall.copyWith(color: context.appTextPrimary),
                      ),
                      Text(
                        ' (${nutritionist.reviewCount})',
                        style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.work_rounded, color: context.appTextHint, size: 11),
                      const SizedBox(width: 2),
                      Text(
                        '${nutritionist.experienceYears}y exp',
                        style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${nutritionist.consultationFee.toInt()}',
                  style: AppTextStyles.h4.copyWith(color: AppColors.accent),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.accent, Color(0xFF4DB6AC)]),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Text(
                    'Book',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String name;
  const _AvatarFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'N',
        style: AppTextStyles.h2.copyWith(color: AppColors.accent),
      ),
    );
  }
}

class _ViewAllButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewAllButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.accent),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'View All Nutritionists',
          style: AppTextStyles.labelLarge.copyWith(color: AppColors.accent),
        ),
      ),
    );
  }
}

// ─── Section Title ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: AppTextStyles.h4.copyWith(color: context.appTextPrimary));
  }
}
