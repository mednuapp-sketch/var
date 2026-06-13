import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import 'models/diet_plan_model.dart';
import 'providers/nutrition_provider.dart';

// Hardcoded fallback plans shown when Firestore has no diet plans yet
const List<Map<String, dynamic>> _fallbackPlans = [
  {'title': 'Weight Loss Plan', 'desc': 'Customized diet to lose weight healthily', 'iconKey': 'monitor_weight', 'colorKey': 'green', 'price': '₹999/month'},
  {'title': 'Diabetes Diet', 'desc': 'Manage blood sugar with right nutrition', 'iconKey': 'bloodtype', 'colorKey': 'red', 'price': '₹1200/month'},
  {'title': 'Heart Healthy Diet', 'desc': 'Reduce cholesterol and heart risk', 'iconKey': 'favorite', 'colorKey': 'pink', 'price': '₹1100/month'},
  {'title': 'Pregnancy Nutrition', 'desc': 'Balanced diet for mother & baby', 'iconKey': 'pregnant_woman', 'colorKey': 'purple', 'price': '₹1500/month'},
  {'title': 'Sports Nutrition', 'desc': 'Optimize performance & recovery', 'iconKey': 'fitness_center', 'colorKey': 'blue', 'price': '₹800/month'},
];

class NutritionScreen extends ConsumerWidget {
  const NutritionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dietPlansAsync = ref.watch(dietPlansStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true, expandedHeight: 160,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => context.pop()),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF33691E), Color(0xFF9CCC65)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 50, 20, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.restaurant_rounded, color: Colors.white, size: 36),
                  const SizedBox(height: 8),
                  Text('Nutrition & Diet', style: AppTextStyles.onPrimaryH2),
                  Text('Expert dietitian consultations & plans', style: AppTextStyles.onPrimaryBody),
                ]))),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // BMI banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF33691E), Color(0xFF9CCC65)]), borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const Icon(Icons.calculate_rounded, color: Colors.white, size: 36),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Calculate Your BMI', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15)),
                      Text('Know your ideal weight range', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
                    ])),
                    ElevatedButton(onPressed: () => context.push(AppRoutes.nutritionBmi), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF33691E), minimumSize: const Size(70, 34)), child: const Text('Check', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                  ]),
                ),
                const SizedBox(height: 20),
                Text('Diet Plans', style: AppTextStyles.h4),
                const SizedBox(height: 12),
                // Load from Firestore; fall back to hardcoded list
                dietPlansAsync.when(
                  loading: () => _buildPlansList(context, null),
                  error: (_, __) => _buildPlansList(context, null),
                  data: (plans) => _buildPlansList(context, plans.isEmpty ? null : plans),
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlansList(BuildContext context, List<DietPlanModel>? firestorePlans) {
    if (firestorePlans != null) {
      return Column(
        children: firestorePlans.map((plan) => _PlanCard(
          title: plan.title,
          desc: plan.description,
          icon: DietPlanModel.iconFromKey(plan.iconKey),
          color: DietPlanModel.colorFromKey(plan.colorKey),
          price: plan.price,
          onEnroll: () => context.push(AppRoutes.nutritionNutritionists),
        )).toList(),
      );
    }
    // Fallback to hardcoded plans
    return Column(
      children: _fallbackPlans.map((plan) => _PlanCard(
        title: plan['title'] as String,
        desc: plan['desc'] as String,
        icon: DietPlanModel.iconFromKey(plan['iconKey'] as String),
        color: DietPlanModel.colorFromKey(plan['colorKey'] as String),
        price: plan['price'] as String,
        onEnroll: () => context.push(AppRoutes.nutritionNutritionists),
      )).toList(),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String desc;
  final IconData icon;
  final Color color;
  final String price;
  final VoidCallback onEnroll;

  const _PlanCard({
    required this.title,
    required this.desc,
    required this.icon,
    required this.color,
    required this.price,
    required this.onEnroll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 26)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTextStyles.labelLarge),
          Text(desc, style: AppTextStyles.bodySmall),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (price.isNotEmpty) Text(price, style: AppTextStyles.labelMedium.copyWith(color: color)),
          const SizedBox(height: 4),
          GestureDetector(onTap: onEnroll, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF33691E), Color(0xFF9CCC65)]), borderRadius: BorderRadius.circular(8)), child: const Text('Enroll', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)))),
        ]),
      ]),
    );
  }
}