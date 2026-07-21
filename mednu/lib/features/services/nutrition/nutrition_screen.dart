import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mednu/core/constants/app_colors.dart';
import 'package:mednu/core/constants/app_text_styles.dart';
import 'package:mednu/core/router/app_router.dart';
import 'package:mednu/core/utils/r.dart';
import 'package:mednu/core/widgets/ux_widgets.dart';
import 'models/diet_plan_model.dart';
import 'providers/nutrition_provider.dart';

const List<Map<String, dynamic>> _fallbackPlans = [
  {
    'title': 'Weight Loss Plan',
    'desc': 'Customized diet to lose weight healthily',
    'iconKey': 'monitor_weight',
    'colorKey': 'green',
    'price': '₹999/month',
  },
  {
    'title': 'Diabetes Diet',
    'desc': 'Manage blood sugar with right nutrition',
    'iconKey': 'bloodtype',
    'colorKey': 'red',
    'price': '₹1,200/month',
  },
  {
    'title': 'Heart Healthy Diet',
    'desc': 'Reduce cholesterol and heart risk',
    'iconKey': 'favorite',
    'colorKey': 'pink',
    'price': '₹1,100/month',
  },
  {
    'title': 'Pregnancy Nutrition',
    'desc': 'Balanced diet for mother & baby',
    'iconKey': 'pregnant_woman',
    'colorKey': 'purple',
    'price': '₹1,500/month',
  },
  {
    'title': 'Sports Nutrition',
    'desc': 'Optimize performance & recovery',
    'iconKey': 'fitness_center',
    'colorKey': 'blue',
    'price': '₹800/month',
  },
];

class NutritionScreen extends ConsumerWidget {
  const NutritionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dietPlansAsync = ref.watch(dietPlansStreamProvider);
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _NutritionSliverAppBar(screenWidth: size.width),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  R.p(context, 16), R.p(context, 20), R.p(context, 16), R.p(context, 32)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BmiBanner(onTap: () => context.push(AppRoutes.nutritionBmi)),
                  SizedBox(height: R.h(context, 24)),
                  const _SectionHeader(
                    title: 'Diet Plans',
                    subtitle: 'Choose a plan tailored for you',
                  ),
                  SizedBox(height: R.h(context, 14)),
                  dietPlansAsync.when(
                    loading: () => const _PlanListSkeleton(),
                    error: (_, __) => _PlansList(
                      plans: null,
                      onEnroll: () => context.push(AppRoutes.nutritionNutritionists),
                    ),
                    data: (plans) => _PlansList(
                      plans: plans.isEmpty ? null : plans,
                      onEnroll: () => context.push(AppRoutes.nutritionNutritionists),
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
}

// ─── App Bar ─────────────────────────────────────────────────────────────────

class _NutritionSliverAppBar extends StatelessWidget {
  final double screenWidth;
  const _NutritionSliverAppBar({required this.screenWidth});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: R.h(context, 190),
      backgroundColor: AppColors.primary,
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
                top: -20,
                right: -20,
                child: Container(
                  width: R.w(context, 140),
                  height: R.w(context, 140),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Positioned(
                bottom: 10,
                right: 60,
                child: Container(
                  width: R.w(context, 70),
                  height: R.w(context, 70),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
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
                          padding: EdgeInsets.fromLTRB(
                              R.p(context, 20), R.p(context, 52), R.p(context, 20), R.p(context, 20)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: EdgeInsets.all(R.p(context, 10)),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(R.r(context, 14)),
                                ),
                                child: Icon(Icons.restaurant_rounded, color: Colors.white, size: R.w(context, 26)),
                              ),
                              SizedBox(height: R.h(context, 10)),
                              const Text('Nutrition & Diet', style: AppTextStyles.onPrimaryH2),
                              SizedBox(height: R.h(context, 2)),
                              const Text(
                                'Expert dietitian consultations & plans',
                                style: AppTextStyles.onPrimaryBody,
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

// ─── BMI Banner ──────────────────────────────────────────────────────────────

class _BmiBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _BmiBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: R.p(context, 18), vertical: R.p(context, 16)),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(R.r(context, 18)),
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.calculate_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Calculate Your BMI',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Know your ideal weight range instantly',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Check',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.h3.copyWith(color: context.appTextPrimary)),
        const SizedBox(height: 2),
        Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
      ],
    );
  }
}

// ─── Plans List ───────────────────────────────────────────────────────────────

class _PlansList extends StatelessWidget {
  final List<DietPlanModel>? plans;
  final VoidCallback onEnroll;
  const _PlansList({required this.plans, required this.onEnroll});

  @override
  Widget build(BuildContext context) {
    if (plans != null) {
      return Column(
        children: plans!
            .map((p) => _PlanCard(
                  title: p.title,
                  desc: p.description,
                  icon: DietPlanModel.iconFromKey(p.iconKey),
                  color: DietPlanModel.colorFromKey(p.colorKey),
                  price: p.price,
                  onEnroll: onEnroll,
                ))
            .toList(),
      );
    }
    return Column(
      children: _fallbackPlans
          .map((p) => _PlanCard(
                title: p['title'] as String,
                desc: p['desc'] as String,
                icon: DietPlanModel.iconFromKey(p['iconKey'] as String),
                color: DietPlanModel.colorFromKey(p['colorKey'] as String),
                price: p['price'] as String,
                onEnroll: onEnroll,
              ))
          .toList(),
    );
  }
}

// ─── Plan Card ────────────────────────────────────────────────────────────────

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
      margin: EdgeInsets.only(bottom: R.h(context, 12)),
      padding: EdgeInsets.all(R.p(context, 16)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 18)),
        border: Border.all(color: context.appBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: R.w(context, 50),
            height: R.w(context, 50),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(R.r(context, 14)),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (price.isNotEmpty)
                      Text(
                        price,
                        style: AppTextStyles.labelMedium.copyWith(color: color),
                      ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onEnroll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Enroll',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Skeleton ─────────────────────────────────────────────────────────────────

class _PlanListSkeleton extends StatelessWidget {
  const _PlanListSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Column(
        children: List.generate(
          4,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 92,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
    );
  }
}
