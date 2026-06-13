import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/router/app_router.dart';
import '../providers/nutrition_provider.dart';
import '../models/meal_log_model.dart';
import '../models/nutrition_goal_model.dart';
import '../../../../core/widgets/ux_widgets.dart';
import '../models/nutrition_appointment_model.dart';

class NutritionDashboardScreen extends ConsumerWidget {
  const NutritionDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(mealLogsProvider);
    final goal = ref.watch(activeNutritionGoalProvider);
    final appointments = ref.watch(nutritionAppointmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CalorieRingCard(meals: meals, goal: goal),
                  const SizedBox(height: 16),
                  _MacrosCard(meals: meals, goal: goal),
                  const SizedBox(height: 16),
                  _WaterCard(goal: goal),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Today's Meals", style: AppTextStyles.h4),
                      TextButton.icon(
                        onPressed: () => context.push(AppRoutes.nutritionMeals),
                        icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF2E7D32)),
                        label: const Text('Add Meal', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _MealsList(meals: meals),
                  const SizedBox(height: 20),
                  _UpcomingAppointmentsSection(appointments: appointments),
                  const SizedBox(height: 20),
                  _ActiveGoalCard(goal: goal),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    final today = DateFormat('EEEE, MMM d').format(DateTime.now());
    return SliverAppBar(
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => context.pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF66BB6A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Nutrition Dashboard', style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(today, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white70)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalorieRingCard extends StatelessWidget {
  final AsyncValue<List<MealLogModel>> meals;
  final AsyncValue<NutritionGoalModel?> goal;

  const _CalorieRingCard({required this.meals, required this.goal});

  @override
  Widget build(BuildContext context) {
    final consumed = meals.valueOrNull?.fold<double>(0, (s, m) => s + m.calories) ?? 0;
    final target = goal.valueOrNull?.targetCalories ?? 2000;
    final progress = (consumed / target).clamp(0.0, 1.0);
    final remaining = (target - consumed).clamp(0.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 10,
                  color: const Color(0xFFE8F5E9),
                ),
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 10,
                  backgroundColor: const Color(0xFFE8F5E9),
                  color: const Color(0xFF2E7D32),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${consumed.toInt()}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF2E7D32))),
                      const Text('kcal', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppColors.textHint)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Calories Today', style: AppTextStyles.h4),
                const SizedBox(height: 8),
                _CalRow(label: 'Consumed', value: '${consumed.toInt()} kcal', color: const Color(0xFF2E7D32)),
                const SizedBox(height: 4),
                _CalRow(label: 'Remaining', value: '${remaining.toInt()} kcal', color: const Color(0xFFF9A825)),
                const SizedBox(height: 4),
                _CalRow(label: 'Target', value: '${target.toInt()} kcal', color: AppColors.textSecondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        Text(value, style: AppTextStyles.labelSmall.copyWith(color: color)),
      ],
    );
  }
}

class _MacrosCard extends StatelessWidget {
  final AsyncValue<List<MealLogModel>> meals;
  final AsyncValue<NutritionGoalModel?> goal;

  const _MacrosCard({required this.meals, required this.goal});

  @override
  Widget build(BuildContext context) {
    final logs = meals.valueOrNull ?? [];
    final protein = logs.fold<double>(0, (s, m) => s + m.protein);
    final carbs = logs.fold<double>(0, (s, m) => s + m.carbs);
    final fat = logs.fold<double>(0, (s, m) => s + m.fat);
    final tProtein = goal.valueOrNull?.targetProtein ?? 50;
    final tCarbs = goal.valueOrNull?.targetCarbs ?? 250;
    final tFat = goal.valueOrNull?.targetFat ?? 65;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Macronutrients', style: AppTextStyles.h4),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _MacroBar(label: 'Protein', value: protein, target: tProtein, color: const Color(0xFF1565C0), unit: 'g')),
              const SizedBox(width: 12),
              Expanded(child: _MacroBar(label: 'Carbs', value: carbs, target: tCarbs, color: const Color(0xFFE65100), unit: 'g')),
              const SizedBox(width: 12),
              Expanded(child: _MacroBar(label: 'Fat', value: fat, target: tFat, color: const Color(0xFF7B1FA2), unit: 'g')),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  final String label;
  final double value;
  final double target;
  final Color color;
  final String unit;

  const _MacroBar({required this.label, required this.value, required this.target, required this.color, required this.unit});

  @override
  Widget build(BuildContext context) {
    final progress = target > 0 ? (value / target).clamp(0.0, 1.0) : 0.0;
    return Column(
      children: [
        Text('${value.toInt()}$unit', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: color.withValues(alpha:0.12),
            color: color,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        Text('of ${target.toInt()}$unit', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textHint)),
      ],
    );
  }
}

class _WaterCard extends ConsumerWidget {
  final AsyncValue<NutritionGoalModel?> goal;
  const _WaterCard({required this.goal});

  static const _glassSize = 0.25; // 250 ml = 0.25 L

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = goal.valueOrNull?.targetWaterLiters ?? 2.5;
    final maxGlasses = (target / _glassSize).ceil();
    final glasses = ref.watch(waterGlassesProvider).valueOrNull ?? 0;
    final consumed = glasses * _glassSize;
    final progress = (consumed / target).clamp(0.0, 1.0);

    void setGlasses(int value) {
      final clamped = value.clamp(0, maxGlasses);
      ref.read(waterUpdateProvider.notifier).setGlasses(clamped);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1565C0).withValues(alpha:0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop_rounded, color: Color(0xFF1565C0), size: 22),
              const SizedBox(width: 8),
              Text('Water Intake', style: AppTextStyles.h4.copyWith(color: const Color(0xFF1565C0))),
              const Spacer(),
              Text('${consumed.toStringAsFixed(1)}L / ${target.toStringAsFixed(1)}L',
                  style: AppTextStyles.labelMedium.copyWith(color: const Color(0xFF1565C0))),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha:0.6),
              color: const Color(0xFF1565C0),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: List.generate(maxGlasses.clamp(0, 10), (i) => GestureDetector(
                    onTap: () => setGlasses(i + 1),
                    child: Icon(
                      Icons.water_drop_rounded,
                      size: 22,
                      color: i < glasses
                          ? const Color(0xFF1565C0)
                          : const Color(0xFF1565C0).withValues(alpha:0.2),
                    ),
                  )),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CircleBtn(icon: Icons.remove_rounded, onTap: () => setGlasses(glasses - 1)),
                  const SizedBox(width: 8),
                  Text('$glasses glasses',
                      style: AppTextStyles.labelSmall.copyWith(color: const Color(0xFF1565C0))),
                  const SizedBox(width: 8),
                  _CircleBtn(icon: Icons.add_rounded, onTap: () => setGlasses(glasses + 1)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(color: Color(0xFF1565C0), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}

class _MealsList extends StatelessWidget {
  final AsyncValue<List<MealLogModel>> meals;
  const _MealsList({required this.meals});

  static const _mealOrder = ['breakfast', 'lunch', 'dinner', 'snack'];

  @override
  Widget build(BuildContext context) {
    return meals.when(
      loading: () => Column(children: List.generate(3, (_) => const SkeletonListTile())),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Icon(Icons.restaurant_menu_rounded, size: 36, color: Colors.grey[300]),
                const SizedBox(height: 8),
                Text('No meals logged today', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
              ],
            ),
          );
        }

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
    );
  }
}

class _MealGroup extends StatelessWidget {
  final String type;
  final List<MealLogModel> logs;

  const _MealGroup({required this.type, required this.logs});

  static const _colors = {
    'breakfast': Color(0xFFF9A825),
    'lunch': Color(0xFF2E7D32),
    'dinner': Color(0xFF1565C0),
    'snack': Color(0xFF7B1FA2),
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
    final icon = _icons[type] ?? Icons.restaurant_rounded;
    final total = logs.fold<double>(0, (s, m) => s + m.calories);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(MealLogModel.mealTypeLabel(type), style: AppTextStyles.labelMedium.copyWith(color: color)),
                const Spacer(),
                Text('${total.toInt()} kcal', style: AppTextStyles.labelSmall.copyWith(color: color)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...logs.map((m) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(m.foodName, style: AppTextStyles.bodySmall)),
                Text('${m.calories.toInt()} kcal', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _UpcomingAppointmentsSection extends StatelessWidget {
  final AsyncValue<List<NutritionAppointmentModel>> appointments;
  const _UpcomingAppointmentsSection({required this.appointments});

  @override
  Widget build(BuildContext context) {
    return appointments.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        final upcoming = list.where((a) => a.status == 'pending' || a.status == 'confirmed').take(2).toList();
        if (upcoming.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upcoming Consultations', style: AppTextStyles.h4),
            const SizedBox(height: 10),
            ...upcoming.map((a) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha:0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, color: Color(0xFF2E7D32), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.nutritionistName, style: AppTextStyles.labelMedium),
                        Text('${a.date}  •  ${a.timeSlot}', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: a.status == 'confirmed'
                          ? const Color(0xFF2E7D32).withValues(alpha:0.1)
                          : Colors.orange.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      a.statusLabel,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700,
                        color: a.status == 'confirmed' ? const Color(0xFF2E7D32) : Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
        );
      },
    );
  }
}

class _ActiveGoalCard extends StatelessWidget {
  final AsyncValue<NutritionGoalModel?> goal;
  const _ActiveGoalCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    return goal.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (g) {
        if (g == null) {
          return GestureDetector(
            onTap: () => context.push(AppRoutes.nutritionGoals),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag_rounded, color: Color(0xFF7B1FA2), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No Active Goal', style: AppTextStyles.labelLarge),
                        Text('Set a nutrition goal to track your progress', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textHint),
                ],
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF9C27B0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.flag_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text('Active Goal', style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
                ],
              ),
              const SizedBox(height: 8),
              Text(NutritionGoalModel.goalLabel(g.goalType), style: const TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              if (g.targetWeight > 0) ...[
                const SizedBox(height: 6),
                Text('Target: ${g.targetWeight} kg  •  Current: ${g.currentWeight} kg', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70)),
              ],
              const SizedBox(height: 10),
              Text('Daily Target: ${g.targetCalories.toInt()} kcal', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70)),
            ],
          ),
        );
      },
    );
  }
}
