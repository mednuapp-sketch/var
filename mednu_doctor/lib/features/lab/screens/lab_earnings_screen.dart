import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';

/// Reuses the Shared Core wallet layer end-to-end — `walletSummaryProvider`
/// resolves to `LabTransactionWalletRepository` automatically because
/// `activeRole == AppRole.lab` (see `wallet_providers.dart`). Nothing here
/// is lab-specific except the copy.
class LabEarningsScreen extends ConsumerWidget {
  const LabEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(walletSummaryProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.labEarnings,
      title: 'Earnings',
      body: summaryAsync.when(
        loading: () => const PageLoadingState(),
        error: (_, __) => const NetworkErrorState(),
        data: (summary) {
          if (summary.isEmpty) {
            return const AppEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No earnings yet',
              message: 'Completed bookings will credit your wallet here.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GradientStatCard(
                value: CurrencyFormatter.format(summary.balance, currency: summary.currency),
                label: 'Total Earnings',
                icon: Icons.account_balance_wallet_rounded,
                colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Transaction History'),
              ...summary.transactions.map((t) => PremiumCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.arrow_downward_rounded, color: AppColors.success, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title, style: AppTextStyles.labelMedium, overflow: TextOverflow.ellipsis),
                              Text(DateFormat('d MMM, h:mm a').format(t.date), style: AppTextStyles.caption),
                            ],
                          ),
                        ),
                        Text(
                          '+${CurrencyFormatter.format(t.amount, currency: summary.currency)}',
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.success),
                        ),
                      ],
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}
