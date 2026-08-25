import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/ambulance_request.dart';
import '../providers/ambulance_providers.dart';
import '../widgets/weekly_earnings_chart.dart';

/// Earnings — reuses the Shared Core wallet layer's presentation
/// conventions (the same "hero total + transaction list" shape as Lab/
/// Pharmacy Earnings) but is backed by the module's own mock providers,
/// not `walletSummaryProvider`, since there's no `ambulance_transactions`
/// ledger yet. Adds a weekly bar chart (`fl_chart`, already a dependency)
/// so this screen isn't just another list of rows.
class AmbulanceEarningsScreen extends ConsumerWidget {
  const AmbulanceEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekly = ref.watch(weeklyEarningsProvider);
    final trips = ref.watch(tripHistoryProvider);
    final total = weekly.fold<double>(0, (s, v) => s + v);

    return SharedAppShell(
      currentRoute: AppRoutes.ambulanceEarnings,
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
                Text('${trips.length} trips completed', style: AppTextStyles.onPrimaryBody),
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
          const Text('Recent Trips', style: AppTextStyles.h4),
          const SizedBox(height: 10),
          ...trips.take(5).map((t) => PremiumCard(
                margin: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: t.type.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Icon(t.type.icon, color: t.type.color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.patientName, style: AppTextStyles.labelMedium),
                          Text(t.type.label, style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                    Text('+${CurrencyFormatter.format(t.fare)}', style: AppTextStyles.labelLarge.copyWith(color: AppColors.success)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
