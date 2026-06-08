import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/router/app_router.dart';
import '../providers/nutrition_provider.dart';
import '../models/nutritionist_model.dart';
import '../models/nutrition_appointment_model.dart';
import '../models/nutrition_goal_model.dart';

class NutritionHomeScreen extends ConsumerWidget {
  const NutritionHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nutritionists = ref.watch(nutritionistsStreamProvider);
    final appointments = ref.watch(nutritionAppointmentsProvider);
    final todayCals = ref.watch(todayCaloriesProvider);
    final goal = ref.watch(activeNutritionGoalProvider);
    final waterGlasses = ref.watch(waterGlassesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _QuickStatsRow(todayCals: todayCals, goal: goal, waterGlasses: waterGlasses),
                  const SizedBox(height: 20),
                  _FindNutritionistBanner(onTap: () => context.push(AppRoutes.nutritionNutritionists)),
                  const SizedBox(height: 20),
                  _DashboardCard(
                    onDashboard: () => context.push(AppRoutes.nutritionDashboard),
                    onMeals: () => context.push(AppRoutes.nutritionMeals),
                    onGoals: () => context.push(AppRoutes.nutritionGoals),
                    onBmi: () => context.push(AppRoutes.nutritionBmi),
                  ),
                  const SizedBox(height: 20),
                  _UpcomingAppointments(appointments: appointments),
                  const SizedBox(height: 20),
                  Text('Featured Nutritionists', style: AppTextStyles.h4),
                  const SizedBox(height: 12),
                  _FeaturedNutritionists(
                    nutritionists: nutritionists,
                    onViewAll: () => context.push(AppRoutes.nutritionNutritionists),
                    onTap: (id) => context.push(AppRoutes.nutritionNutritionistProfile.replaceFirst(':id', id)),
                  ),
                  const SizedBox(height: 20),
                  _HealthGoalsSection(onTap: () => context.push(AppRoutes.nutritionGoals)),
                  const SizedBox(height: 32),
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
      expandedHeight: 170,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => context.pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2E7D32), Color(0xFF81C784)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.restaurant_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Nutrition & Diet', style: AppTextStyles.onPrimaryH2),
                          Text('Expert dietitian consultations & plans', style: AppTextStyles.onPrimaryBody),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickStatsRow extends StatelessWidget {
  final AsyncValue<double> todayCals;
  final AsyncValue<NutritionGoalModel?> goal;
  final AsyncValue<int> waterGlasses;

  const _QuickStatsRow({
    required this.todayCals,
    required this.goal,
    required this.waterGlasses,
  });

  @override
  Widget build(BuildContext context) {
    final cals = todayCals.valueOrNull ?? 0.0;
    final goalModel = goal.valueOrNull;
    final targetCals = goalModel?.targetCalories ?? 2000.0;
    final targetWater = goalModel?.targetWaterLiters ?? 2.5;
    final glasses = waterGlasses.valueOrNull ?? 0;
    final consumedWater = glasses * 0.25;

    return Row(
      children: [
        Expanded(child: _StatCard(
          icon: Icons.local_fire_department_rounded,
          iconColor: const Color(0xFFE65100),
          label: 'Calories Today',
          value: '${cals.toInt()} kcal',
          subtitle: 'of ${targetCals.toInt()} target',
          gradient: const LinearGradient(colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)]),
        )),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(
          icon: Icons.water_drop_rounded,
          iconColor: const Color(0xFF1565C0),
          label: 'Water Today',
          value: '${consumedWater.toStringAsFixed(1)} L',
          subtitle: 'of ${targetWater.toStringAsFixed(1)}L goal',
          gradient: const LinearGradient(colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)]),
        )),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String subtitle;
  final LinearGradient gradient;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 8),
          Text(value, style: AppTextStyles.h4),
          Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
          Text(subtitle, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textHint)),
        ],
      ),
    );
  }
}

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
          gradient: const LinearGradient(
            colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: const Color(0xFF2E7D32).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Find a Nutritionist', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white)),
                  const SizedBox(height: 4),
                  const Text('Book personalised diet consultations\nwith certified dietitians', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70, height: 1.4)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: const Text('Browse Now', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                  ),
                ],
              ),
            ),
            const Icon(Icons.person_search_rounded, color: Colors.white, size: 64),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final VoidCallback onDashboard;
  final VoidCallback onMeals;
  final VoidCallback onGoals;
  final VoidCallback onBmi;

  const _DashboardCard({
    required this.onDashboard,
    required this.onMeals,
    required this.onGoals,
    required this.onBmi,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: AppColors.shadow.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Nutrition Hub', style: AppTextStyles.h4),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _HubButton(icon: Icons.dashboard_rounded, label: 'Dashboard', color: const Color(0xFF2E7D32), onTap: onDashboard)),
              const SizedBox(width: 10),
              Expanded(child: _HubButton(icon: Icons.restaurant_menu_rounded, label: 'Track Meals', color: const Color(0xFFE65100), onTap: onMeals)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _HubButton(icon: Icons.flag_rounded, label: 'My Goals', color: const Color(0xFF7B1FA2), onTap: onGoals)),
              const SizedBox(width: 10),
              Expanded(child: _HubButton(icon: Icons.calculate_rounded, label: 'BMI Check', color: const Color(0xFF1565C0), onTap: onBmi)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HubButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _HubButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

class _UpcomingAppointments extends StatelessWidget {
  final AsyncValue<List<NutritionAppointmentModel>> appointments;
  const _UpcomingAppointments({required this.appointments});

  @override
  Widget build(BuildContext context) {
    return appointments.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        final upcoming = list
            .where((a) => a.status == 'pending' || a.status == 'confirmed')
            .take(2)
            .toList();
        if (upcoming.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upcoming Consultations', style: AppTextStyles.h4),
            const SizedBox(height: 10),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.person_rounded, color: Color(0xFF2E7D32), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appointment.nutritionistName, style: AppTextStyles.labelLarge),
                Text('${appointment.date}  •  ${appointment.timeSlot}', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                Text(appointment.consultationType == 'online' ? 'Online Consultation' : 'In-Person', style: AppTextStyles.bodySmall.copyWith(color: const Color(0xFF2E7D32))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: appointment.status == 'confirmed' ? const Color(0xFF2E7D32).withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              appointment.statusLabel,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: appointment.status == 'confirmed' ? const Color(0xFF2E7D32) : Colors.orange),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedNutritionists extends StatelessWidget {
  final AsyncValue<List<NutritionistModel>> nutritionists;
  final VoidCallback onViewAll;
  final void Function(String id) onTap;

  const _FeaturedNutritionists({required this.nutritionists, required this.onViewAll, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return nutritionists.when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      error: (e, _) => Center(child: Text('Failed to load nutritionists', style: AppTextStyles.bodySmall)),
      data: (list) {
        if (list.isEmpty) {
          return _EmptyNutritionists(onAdd: onViewAll);
        }
        return Column(
          children: [
            ...list.take(3).map((n) => _NutritionistCard(nutritionist: n, onTap: () => onTap(n.id))),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: onViewAll,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF2E7D32)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('View All Nutritionists', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyNutritionists extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyNutritionists({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.person_search_rounded, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('No Nutritionists Yet', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('Nutritionists will appear here once added by admin', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint), textAlign: TextAlign.center),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: AppColors.shadow.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: nutritionist.photoUrl.isNotEmpty
                  ? Image.network(nutritionist.photoUrl, width: 56, height: 56, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _AvatarFallback(name: nutritionist.name))
                  : _AvatarFallback(name: nutritionist.name),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nutritionist.name, style: AppTextStyles.labelLarge),
                  Text('${nutritionist.qualification} • ${nutritionist.specialization}', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFF9A825), size: 14),
                      const SizedBox(width: 2),
                      Text(nutritionist.rating.toStringAsFixed(1), style: AppTextStyles.labelSmall),
                      Text(' (${nutritionist.reviewCount})', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
                      const SizedBox(width: 8),
                      const Icon(Icons.work_rounded, color: AppColors.textHint, size: 12),
                      const SizedBox(width: 2),
                      Text('${nutritionist.experienceYears}y exp', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${nutritionist.consultationFee.toInt()}', style: AppTextStyles.labelMedium.copyWith(color: const Color(0xFF2E7D32))),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Book', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
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
        color: const Color(0xFF2E7D32).withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'N',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32)),
      ),
    );
  }
}

class _HealthGoalsSection extends StatelessWidget {
  final VoidCallback onTap;
  const _HealthGoalsSection({required this.onTap});

  static const _goals = [
    {'label': 'Weight Loss', 'icon': Icons.monitor_weight_rounded, 'color': Color(0xFF2E7D32)},
    {'label': 'Diabetes Diet', 'icon': Icons.bloodtype_rounded, 'color': Color(0xFFB71C1C)},
    {'label': 'Heart Healthy', 'icon': Icons.favorite_rounded, 'color': Color(0xFFC2185B)},
    {'label': 'Pregnancy', 'icon': Icons.pregnant_woman_rounded, 'color': Color(0xFF7B1FA2)},
    {'label': 'Sports Nutrition', 'icon': Icons.fitness_center_rounded, 'color': Color(0xFF1565C0)},
    {'label': 'PCOS Diet', 'icon': Icons.spa_rounded, 'color': Color(0xFF00897B)},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Health Goals', style: AppTextStyles.h4),
            GestureDetector(
              onTap: onTap,
              child: Text('Set Goal', style: AppTextStyles.labelSmall.copyWith(color: const Color(0xFF2E7D32))),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _goals.map((g) {
            final color = g['color'] as Color;
            return GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(g['icon'] as IconData, color: color, size: 16),
                    const SizedBox(width: 6),
                    Text(g['label'] as String, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
