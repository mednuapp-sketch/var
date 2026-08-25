import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/visit.dart';
import '../providers/caregiver_providers.dart';
import '../widgets/weekly_earnings_chart.dart';

/// Earnings — hero total + weekly bar chart + recent completed visits,
/// backed by the module's own mock providers (no `caregiver_transactions`
/// ledger yet), same shape as the Ambulance module's Earnings screen but
/// in the caregiver teal/amber palette.
class CaregiverEarningsScreen extends ConsumerWidget {
  const CaregiverEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekly = ref.watch(weeklyCaregiverEarningsProvider);
    final history = ref.watch(visitHistoryProvider);
    final total = weekly.fold<double>(0, (s, v) => s + v);

    return SharedAppShell(
      currentRoute: AppRoutes.caregiverEarnings,
      title: 'Earnings',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.earningGradient,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This Week', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white70)),
                const SizedBox(height: 6),
                Text('₹${total.toInt()}', style: AppTextStyles.onPrimaryH2.copyWith(fontSize: 30)),
                const SizedBox(height: 4),
                Text('${history.length} visits completed', style: AppTextStyles.onPrimaryBody),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Weekly Breakdown', style: AppTextStyles.labelLarge),
                const SizedBox(height: 12),
                WeeklyEarningsChart(values: weekly),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Recent Visits', style: AppTextStyles.h4),
          const SizedBox(height: 10),
          ...history.take(5).map((v) => PremiumCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: v.type.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Icon(v.type.icon, color: v.type.color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.patientName, style: AppTextStyles.labelMedium),
                          Text(v.type.label, style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                    Text('+${CurrencyFormatter.format(v.fare)}', style: AppTextStyles.labelLarge.copyWith(color: AppColors.success)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
