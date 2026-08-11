import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/ux_widgets.dart';
import '../widgets/shared_state_widgets.dart';
import 'currency_formatter.dart';
import 'wallet_providers.dart';

/// Compact wallet balance card for the dashboard. Reads from
/// [walletSummaryProvider] (currently backed by the same
/// `appointments.fee` aggregation the earnings screen already uses — see
/// `wallet_repository.dart`) so this never touches or duplicates the
/// earnings screen's own calculation, it's a second, smaller view over the
/// same numbers.
class SharedWalletSummaryCard extends ConsumerWidget {
  final VoidCallback? onTap;
  const SharedWalletSummaryCard({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(walletSummaryProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: summaryAsync.when(
        loading: () => const CardLoadingState(itemCount: 1, cardHeight: 108),
        error: (_, __) => const PremiumCard(
          child: NetworkErrorState(),
        ),
        data: (summary) => TapScale(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: AppColors.earningGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        CurrencyFormatter.format(summary.balance, currency: summary.currency),
                        style: AppTextStyles.onPrimaryH2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text('Wallet balance', style: AppTextStyles.onPrimaryBody),
                      if (summary.pendingAmount > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${CurrencyFormatter.format(summary.pendingAmount, currency: summary.currency)} pending',
                          style: AppTextStyles.onPrimaryBody.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_right_rounded, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
