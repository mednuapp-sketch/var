import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/ux_widgets.dart';
import '../widgets/shared_state_widgets.dart';
import 'currency_formatter.dart';
import 'payout_widgets.dart';
import 'wallet_providers.dart';

/// Shown once on every partner earnings/wallet surface.
const String kEarningsFeeNote =
    'You receive the full service price. The platform fee is paid by the customer.';

/// Subtle caption for earnings screens that do not use
/// [SharedWalletSummaryCard] (which already carries the note).
class EarningsFeeNote extends StatelessWidget {
  const EarningsFeeNote({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.info_outline_rounded,
                  size: 13, color: AppColors.textHint),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(kEarningsFeeNote,
                  style: AppTextStyles.caption.copyWith(height: 1.35)),
            ),
          ],
        ),
      );
}

/// Compact wallet balance card for the dashboard. Reads from
/// [walletSummaryProvider] — role-aware (see `wallet_providers.dart`):
/// doctor/lab/pharmacy/ambulance/caregiver get real, live settlement-engine
/// figures (`provider_wallets`/`wallet_ledger`, functions/index.js), other
/// roles keep their own aggregation. Needs no changes when that backing
/// changes since it only ever reads the shared [WalletSummary] shape.
class SharedWalletSummaryCard extends ConsumerWidget {
  final VoidCallback? onTap;
  /// Side inset; pass 0 when the parent list already pads its children.
  final double horizontalPadding;
  /// Shows the payout request / payout account actions under the balance.
  final bool showPayoutActions;
  const SharedWalletSummaryCard({
    super.key,
    this.onTap,
    this.horizontalPadding = 16,
    this.showPayoutActions = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(walletSummaryProvider);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: summaryAsync.when(
        loading: () => const CardLoadingState(itemCount: 1, cardHeight: 108),
        error: (_, __) => const PremiumCard(
          child: NetworkErrorState(),
        ),
        data: (summary) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TapScale(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(
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
            const SizedBox(height: 10),
            Text(
              kEarningsFeeNote,
              style: AppTextStyles.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
                height: 1.35,
              ),
            ),
              ],
            ),
          ),
        ),
            if (showPayoutActions) ...[
              const SizedBox(height: 10),
              PayoutActionsPanel(pending: summary.pendingAmount),
            ],
          ],
        ),
      ),
    );
  }
}
