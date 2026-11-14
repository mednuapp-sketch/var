import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mednu/core/constants/app_colors.dart';
import 'package:mednu/core/constants/app_text_styles.dart';
import 'package:mednu/core/router/app_router.dart';
import 'package:mednu/core/utils/r.dart';
import 'package:mednu/core/widgets/ux_widgets.dart';
import 'models/diet_plan_model.dart';
import 'models/weight_loss_plan.dart';
import 'providers/nutrition_provider.dart';

/// Weight-loss enrolment first asks for a 2 / 4 / 6-month duration (6 months
/// recommended); every other plan goes straight to choosing a dietician.
Future<void> _enroll(BuildContext context, String title, String price) async {
  if (!isWeightLossPlan(title)) {
    selectedWeightLossMonths.value = null;
    context.push(AppRoutes.nutritionNutritionists);
    return;
  }
  final months = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WeightLossDurationSheet(monthlyAmount: monthlyAmountFromPrice(price)),
  );
  if (months == null || !context.mounted) return;
  selectedWeightLossMonths.value = months;
  await context.push(AppRoutes.nutritionNutritionists);
  // The plan choice only lives for this dietician-picking flow; clear it when
  // the list is closed so a later unrelated booking is not tagged as a plan.
  selectedWeightLossMonths.value = null;
}

class _WeightLossDurationSheet extends StatefulWidget {
  final int? monthlyAmount;
  const _WeightLossDurationSheet({required this.monthlyAmount});

  @override
  State<_WeightLossDurationSheet> createState() => _WeightLossDurationSheetState();
}

class _WeightLossDurationSheetState extends State<_WeightLossDurationSheet> {
  int _selected = 6; // the recommended plan is pre-selected

  String _rupees(int v) {
    final s = v.toString();
    if (s.length <= 3) return '₹$s';
    final head = s.substring(0, s.length - 3);
    final grouped = head.replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+$)'), (m) => '${m[1]},');
    return '₹$grouped,${s.substring(s.length - 3)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.appBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Choose your plan duration',
                  style: AppTextStyles.h3.copyWith(color: context.appTextPrimary)),
              const SizedBox(height: 4),
              Text(
                'Each month includes one consultation with your dietician.',
                style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
              ),
              const SizedBox(height: 16),
              for (final option in weightLossPlanOptions) ...[
                _DurationTile(
                  option: option,
                  selected: _selected == option.months,
                  total: widget.monthlyAmount == null
                      ? null
                      : _rupees(widget.monthlyAmount! * option.months),
                  onTap: () => setState(() => _selected = option.months),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Continue with $_selected months',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationTile extends StatelessWidget {
  final WeightLossPlanOption option;
  final bool selected;
  final String? total;
  final VoidCallback onTap;
  const _DurationTile({
    required this.option,
    required this.selected,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : context.appBorder;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.06) : context.appSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: selected ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primary : context.appTextHint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${option.months} months',
                          style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
                      if (option.recommended)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Recommended',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${option.consultations} monthly consultations',
                    style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                  ),
                ],
              ),
            ),
            if (total != null)
              Text(total!,
                  style: AppTextStyles.labelMedium.copyWith(color: context.appTextPrimary)),
          ],
        ),
      ),
    );
  }
}

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
    'title': 'Pregnancy Diet',
    'desc': 'Balanced diet for mother & baby',
    'iconKey': 'pregnant_woman',
    'colorKey': 'purple',
    'price': '₹1,500/month',
  },
  {
    'title': 'Sports Diet',
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
                      onEnroll: (title, price) => _enroll(context, title, price),
                    ),
                    data: (plans) => _PlansList(
                      plans: plans.isEmpty ? null : plans,
                      onEnroll: (title, price) => _enroll(context, title, price),
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
    return const AppSliverHeader(
      icon: Icons.restaurant_rounded,
      title: 'Diet & Dietician',
      subtitle: 'Expert dietitian consultations & plans',
      color: AppColors.primary,
      gradient: AppColors.nutritionGrad,
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
  final void Function(String title, String price) onEnroll;
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
                  onEnroll: () => onEnroll(p.title, p.price),
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
                onEnroll: () => onEnroll(p['title'] as String, p['price'] as String),
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
