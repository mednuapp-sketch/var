import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../providers/physio_providers.dart';

/// Earnings — hero total + recent completed sessions, backed by the real
/// `physio_transactions` ledger via `walletSummaryProvider`
/// (shared_core/wallet). Same shape as the Caregiver module's Earnings
/// screen but without the weekly bar chart, for a leaner "minimal" module.
class PhysioEarningsScreen extends ConsumerWidget {
  const PhysioEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(walletSummaryProvider);
    final history = ref.watch(physioSessionHistoryProvider);
    final completedCount = history.where((s) => s.status.name == 'completed').length;

    return SharedAppShell(
      currentRoute: AppRoutes.physioEarnings,
      title: 'Earnings',
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const AppErrorState(message: 'Could not load earnings.'),
        data: (data) => ListView(
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
                  const Text('Total Earnings', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text('₹${data.balance.toInt()}', style: AppTextStyles.onPrimaryH2.copyWith(fontSize: 30)),
                  const SizedBox(height: 4),
                  Text('$completedCount sessions completed', style: AppTextStyles.onPrimaryBody),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Recent Transactions', style: AppTextStyles.h4),
            const SizedBox(height: 10),
            if (data.transactions.isEmpty)
              const AppEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No earnings yet',
                message: 'Completed sessions will show up here.',
              )
            else
              ...data.transactions.take(20).map((t) => PremiumCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.accessibility_new_rounded, color: AppColors.success, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title, style: AppTextStyles.labelMedium, overflow: TextOverflow.ellipsis),
                              Text(t.subtitle, style: AppTextStyles.caption),
                            ],
                          ),
                        ),
                        Text('+${CurrencyFormatter.format(t.amount)}', style: AppTextStyles.labelLarge.copyWith(color: AppColors.success)),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
