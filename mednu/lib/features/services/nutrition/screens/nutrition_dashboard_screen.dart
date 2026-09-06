import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mednu/core/constants/app_colors.dart';
import 'package:mednu/core/constants/app_text_styles.dart';
import 'package:mednu/core/router/app_router.dart';
import 'package:mednu/core/widgets/ux_widgets.dart';
import 'package:mednu/core/utils/r.dart';
import '../models/meal_log_model.dart';
import '../models/nutrition_goal_model.dart';
import '../models/nutrition_appointment_model.dart';
import '../providers/nutrition_provider.dart';

class NutritionDashboardScreen extends ConsumerWidget {
  const NutritionDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals        = ref.watch(mealLogsProvider);
    final goal         = ref.watch(activeNutritionGoalProvider);
    final appointments = ref.watch(nutritionAppointmentsProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _DashboardAppBar(onAddMeal: () => context.push(AppRoutes.nutritionMeals)),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 16), R.p(context, 16), R.p(context, 40)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AnimatedCalorieRingCard(meals: meals, goal: goal),
                  SizedBox(height: R.h(context, 16)),
                  _MacrosCard(meals: meals, goal: goal),
                  SizedBox(height: R.h(context, 16)),
                  _WaterCard(goal: goal),
                  SizedBox(height: R.h(context, 20)),
                  _TodayMealsSection(meals: meals),
                  SizedBox(height: R.h(context, 20)),
                  _UpcomingConsultationsSection(appointments: appointments),
                  SizedBox(height: R.h(context, 20)),
                  _ActiveGoalCard(goal: goal),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── App Bar ──────────────────────────────────────────────────────────────────

class _DashboardAppBar extends StatelessWidget {
  final VoidCallback onAddMeal;
  const _DashboardAppBar({required this.onAddMeal});

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEEE, MMM d').format(DateTime.now());
    return SliverAppBar(
      pinned: true,
      expandedHeight: R.h(context, 140),
      backgroundColor: const Color(0xFF33691E), // matches nutritionGrad's dark stop so the collapsed bar doesn't jump to an unrelated color
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        onPressed: () => context.pop(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 22),
          tooltip: 'Add Meal',
          onPressed: onAddMeal,
        ),
        SizedBox(width: R.p(context, 4)),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Container(
          decoration: const BoxDecoration(gradient: AppColors.nutritionGrad),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        R.p(context, 20), R.p(context, 52),
                        R.p(context, 20), R.p(context, 16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Nutrition Dashboard', style: AppTextStyles.onPrimaryH2),
                          SizedBox(height: R.h(context, 2)),
                          Text(today, style: AppTextStyles.onPrimaryBody),
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
  }
}

// ─── Animated Calorie Ring Card ───────────────────────────────────────────────

class _AnimatedCalorieRingCard extends StatefulWidget {
  final AsyncValue<List<MealLogModel>> meals;
  final AsyncValue<NutritionGoalModel?> goal;

  const _AnimatedCalorieRingCard({required this.meals, required this.goal});

  @override
  State<_AnimatedCalorieRingCard> createState() => _AnimatedCalorieRingCardState();
}

class _AnimatedCalorieRingCardState extends State<_AnimatedCalorieRingCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_AnimatedCalorieRingCard old) {
    super.didUpdateWidget(old);
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final consumed  = widget.meals.valueOrNull?.fold<double>(0, (s, m) => s + m.calories) ?? 0;
    final target    = widget.goal.valueOrNull?.targetCalories ?? 2000;
    final progress  = (consumed / target).clamp(0.0, 1.0);
    final remaining = (target - consumed).clamp(0.0, double.infinity);
    final isOver    = consumed > target;

    return Container(
      padding: EdgeInsets.all(R.p(context, 20)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Ring chart
              AnimatedBuilder(
                animation: _anim,
                builder: (_, __) => SizedBox(
                  width: R.w(context, 120),
                  height: R.h(context, 120),
                  child: CustomPaint(
                    painter: _CalorieRingPainter(
                      progress: progress * _anim.value,
                      isOver: isOver,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${consumed.toInt()}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: isOver ? AppColors.error : AppColors.accent,
                              height: 1,
                            ),
                          ),
                          Text(
                            'kcal',
                            style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: R.p(context, 20)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Calories Today', style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
                    SizedBox(height: R.h(context, 12)),
                    _CalRow(label: 'Consumed', value: '${consumed.toInt()} kcal', color: AppColors.accent),
                    SizedBox(height: R.h(context, 6)),
                    _CalRow(
                      label: isOver ? 'Over by' : 'Remaining',
                      value: '${remaining.toInt()} kcal',
                      color: isOver ? AppColors.error : const Color(0xFFF9A825),
                    ),
                    SizedBox(height: R.h(context, 6)),
                    _CalRow(label: 'Target', value: '${target.toInt()} kcal', color: context.appTextSecondary),
                    SizedBox(height: R.h(context, 10)),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(R.r(context, 5)),
                      child: AnimatedBuilder(
                        animation: _anim,
                        builder: (_, __) => LinearProgressIndicator(
                          value: progress * _anim.value,
                          minHeight: 7,
                          backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                          color: isOver ? AppColors.error : AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalorieRingPainter extends CustomPainter {
  final double progress;
  final bool isOver;
  const _CalorieRingPainter({required this.progress, required this.isOver});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 10;
    const strokeWidth = 12.0;

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = AppColors.accent.withValues(alpha: 0.12)
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = isOver ? AppColors.error : AppColors.accent
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_CalorieRingPainter old) => old.progress != progress || old.isOver != isOver;
}

class _CalRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _CalRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
        Text(value, style: AppTextStyles.labelSmall.copyWith(color: color)),
      ],
    );
  }
}

// ─── Macros Card ─────────────────────────────────────────────────────────────

class _MacrosCard extends StatelessWidget {
  final AsyncValue<List<MealLogModel>> meals;
  final AsyncValue<NutritionGoalModel?> goal;

  const _MacrosCard({required this.meals, required this.goal});

  @override
  Widget build(BuildContext context) {
    final logs     = meals.valueOrNull ?? [];
    final protein  = logs.fold<double>(0, (s, m) => s + m.protein);
    final carbs    = logs.fold<double>(0, (s, m) => s + m.carbs);
    final fat      = logs.fold<double>(0, (s, m) => s + m.fat);
    final tProtein = goal.valueOrNull?.targetProtein ?? 50;
    final tCarbs   = goal.valueOrNull?.targetCarbs ?? 250;
    final tFat     = goal.valueOrNull?.targetFat ?? 65;

    return Container(
      padding: EdgeInsets.all(R.p(context, 18)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Macronutrients', style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
          SizedBox(height: R.h(context, 16)),
          Row(
            children: [
              Expanded(child: _MacroColumn(label: 'Protein', value: protein, target: tProtein, color: AppColors.info)),
              SizedBox(width: R.p(context, 12)),
              Expanded(child: _MacroColumn(label: 'Carbs', value: carbs, target: tCarbs, color: const Color(0xFFE65100))),
              SizedBox(width: R.p(context, 12)),
              Expanded(child: _MacroColumn(label: 'Fat', value: fat, target: tFat, color: AppColors.secondary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroColumn extends StatelessWidget {
  final String label;
  final double value;
  final double target;
  final Color color;

  const _MacroColumn({required this.label, required this.value, required this.target, required this.color});

  @override
  Widget build(BuildContext context) {
    final progress = target > 0 ? (value / target).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: EdgeInsets.all(R.p(context, 12)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(R.r(context, 14)),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Text('${value.toInt()}g', style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          SizedBox(height: R.h(context, 4)),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.r(context, 4)),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: color.withValues(alpha: 0.12),
              color: color,
              minHeight: 5,
            ),
          ),
          SizedBox(height: R.h(context, 5)),
          Text(label, style: AppTextStyles.labelSmall.copyWith(color: context.appTextSecondary)),
          Text('of ${target.toInt()}g', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
        ],
      ),
    );
  }
}

// ─── Water Card ───────────────────────────────────────────────────────────────

class _WaterCard extends ConsumerWidget {
  final AsyncValue<NutritionGoalModel?> goal;
  const _WaterCard({required this.goal});

  static const double _glassSize = 0.25;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target    = goal.valueOrNull?.targetWaterLiters ?? 2.5;
    final maxGlasses = (target / _glassSize).ceil().clamp(1, 12);
    final glasses   = ref.watch(waterGlassesProvider).valueOrNull ?? 0;
    final consumed  = glasses * _glassSize;
    final progress  = (consumed / target).clamp(0.0, 1.0);

    void setGlasses(int value) {
      final clamped = value.clamp(0, maxGlasses);
      ref.read(waterUpdateProvider.notifier).setGlasses(clamped);
    }

    return Container(
      padding: EdgeInsets.all(R.p(context, 18)),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)]),
        borderRadius: BorderRadius.circular(R.r(context, 20)),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.18)),
        boxShadow: [BoxShadow(color: AppColors.info.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(R.p(context, 8)),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.r(context, 10)),
                ),
                child: const Icon(Icons.water_drop_rounded, color: AppColors.info, size: 18),
              ),
              SizedBox(width: R.p(context, 10)),
              Text('Water Intake', style: AppTextStyles.h4.copyWith(color: AppColors.info)),
              const Spacer(),
              Text(
                '${consumed.toStringAsFixed(1)} / ${target.toStringAsFixed(1)} L',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.info),
              ),
            ],
          ),
          SizedBox(height: R.h(context, 14)),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.r(context, 6)),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.6),
              color: AppColors.info,
              minHeight: 9,
            ),
          ),
          SizedBox(height: R.h(context, 14)),
          Row(
            children: [
              Flexible(
                child: Wrap(
                  spacing: R.p(context, 5),
                  runSpacing: R.p(context, 4),
                  children: List.generate(
                    maxGlasses.clamp(0, 10),
                    (i) => GestureDetector(
                      onTap: () => setGlasses(i + 1),
                      child: Icon(
                        Icons.water_drop_rounded,
                        size: 22,
                        color: i < glasses ? AppColors.info : AppColors.info.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: R.p(context, 10)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WaterBtn(icon: Icons.remove_rounded, onTap: () => setGlasses(glasses - 1)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: R.p(context, 10)),
                    child: Text(
                      '$glasses',
                      style: AppTextStyles.h3.copyWith(color: AppColors.info),
                    ),
                  ),
                  _WaterBtn(icon: Icons.add_rounded, onTap: () => setGlasses(glasses + 1)),
                ],
              ),
            ],
          ),
          SizedBox(height: R.h(context, 4)),
          Text('1 glass = 250 ml', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _WaterBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _WaterBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(R.p(context, 5)),
        decoration: const BoxDecoration(color: AppColors.info, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}

// ─── Today's Meals ────────────────────────────────────────────────────────────

class _TodayMealsSection extends StatelessWidget {
  final AsyncValue<List<MealLogModel>> meals;
  const _TodayMealsSection({required this.meals});

  static const _mealOrder = ['breakfast', 'lunch', 'dinner', 'snack'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Today's Meals", style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
            GestureDetector(
              onTap: () => context.push(AppRoutes.nutritionMeals),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, size: 14, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Text('Add Meal', style: AppTextStyles.labelSmall.copyWith(color: AppColors.accent)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        meals.when(
          loading: () => AppShimmer(
            child: Column(
              children: List.generate(
                2,
                (_) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  height: 76,
                  decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ),
          error: (_, __) => const _EmptyMeals(),
          data: (list) {
            if (list.isEmpty) return const _EmptyMeals();
            final grouped = <String, List<MealLogModel>>{};
            for (final m in list) {
              grouped.putIfAbsent(m.mealType, () => []).add(m);
            }
            return Column(
              children: _mealOrder
                  .where((type) => grouped.containsKey(type))
                  .map((type) => _MealGroup(type: type, logs: grouped[type]!))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _EmptyMeals extends StatelessWidget {
  const _EmptyMeals();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        children: [
          Icon(Icons.restaurant_menu_rounded, size: 44, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text('No meals logged today', style: AppTextStyles.labelLarge.copyWith(color: context.appTextSecondary)),
          const SizedBox(height: 4),
          Text('Tap "Add Meal" to start tracking', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
        ],
      ),
    );
  }
}

class _MealGroup extends StatelessWidget {
  final String type;
  final List<MealLogModel> logs;

  const _MealGroup({required this.type, required this.logs});

  static const _colors = {
    'breakfast': Color(0xFFF9A825),
    'lunch': AppColors.accent,
    'dinner': AppColors.info,
    'snack': AppColors.secondary,
  };
  static const _icons = {
    'breakfast': Icons.wb_sunny_rounded,
    'lunch': Icons.wb_cloudy_rounded,
    'dinner': Icons.nightlight_rounded,
    'snack': Icons.cookie_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[type] ?? AppColors.textSecondary;
    final icon  = _icons[type] ?? Icons.restaurant_rounded;
    final total = logs.fold<double>(0, (s, m) => s + m.calories);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 10),
                Text(
                  MealLogModel.mealTypeLabel(type),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: color),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '${total.toInt()} kcal',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: color.withValues(alpha: 0.1)),
          ...logs.map(
            (m) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(m.foodName, style: AppTextStyles.bodyMedium.copyWith(color: context.appTextPrimary))),
                  Text('${m.calories.toInt()} kcal', style: AppTextStyles.labelSmall.copyWith(color: context.appTextSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Upcoming Consultations ───────────────────────────────────────────────────

class _UpcomingConsultationsSection extends StatelessWidget {
  final AsyncValue<List<NutritionAppointmentModel>> appointments;
  const _UpcomingConsultationsSection({required this.appointments});

  @override
  Widget build(BuildContext context) {
    return appointments.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, __) => const SizedBox.shrink(),
      data: (list) {
        final upcoming = list.where((a) => a.status == 'pending' || a.status == 'confirmed').take(2).toList();
        if (upcoming.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upcoming Consultations', style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
            const SizedBox(height: 12),
            ...upcoming.map((a) => _ConsultationTile(appt: a)),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }
}

class _ConsultationTile extends StatelessWidget {
  final NutritionAppointmentModel appt;
  const _ConsultationTile({required this.appt});

  @override
  Widget build(BuildContext context) {
    final isConfirmed = appt.status == 'confirmed';
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
            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.calendar_today_rounded, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appt.nutritionistName, style: AppTextStyles.labelLarge),
                Text(
                  '${appt.date}  •  ${appt.timeSlot}',
                  style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
            child: Text(
              appt.statusLabel,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: statusColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Active Goal Card ─────────────────────────────────────────────────────────

class _ActiveGoalCard extends StatelessWidget {
  final AsyncValue<NutritionGoalModel?> goal;
  const _ActiveGoalCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    return goal.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, __) => const SizedBox.shrink(),
      data: (g) {
        if (g == null) {
          return GestureDetector(
            onTap: () => context.push(AppRoutes.nutritionGoals),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.appSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.appBorder),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.flag_rounded, color: AppColors.secondary, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No Active Goal', style: AppTextStyles.labelLarge.copyWith(color: context.appTextPrimary)),
                        const SizedBox(height: 2),
                        Text('Set a nutrition goal to track progress', style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, size: 14, color: context.appTextHint),
                ],
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3D1D36), Color(0xFFA36BAC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: AppColors.secondary.withValues(alpha: 0.30), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.flag_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Active Goal', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                NutritionGoalModel.goalLabel(g.goalType),
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              if (g.targetWeight > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Target: ${g.targetWeight} kg  •  Current: ${g.currentWeight} kg',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  _GoalStat(label: 'Calories', value: '${g.targetCalories.toInt()} kcal'),
                  const SizedBox(width: 16),
                  _GoalStat(label: 'Protein', value: '${g.targetProtein.toInt()}g'),
                  const SizedBox(width: 16),
                  _GoalStat(label: 'Water', value: '${g.targetWaterLiters}L'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GoalStat extends StatelessWidget {
  final String label;
  final String value;
  const _GoalStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: Colors.white60)),
      ],
    );
  }
}
