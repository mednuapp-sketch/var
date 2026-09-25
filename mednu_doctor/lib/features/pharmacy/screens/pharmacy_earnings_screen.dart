import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';

/// Reuses the Shared Core wallet layer end-to-end — `walletSummaryProvider`
/// resolves to `PharmacyTransactionWalletRepository` automatically because
/// `activeRole == AppRole.pharmacy` (see `wallet_providers.dart`). Nothing
/// here is pharmacy-specific except the copy.
///
/// Today/week/month breakdown is computed client-side from the live
/// transaction list — mirrors `HospitalEarningsScreen`'s aggregation for the
/// Hospital Billing role, which does the same over its own wallet stream.
class PharmacyEarningsScreen extends ConsumerWidget {
  const PharmacyEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(walletSummaryProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.pharmacyEarnings,
      title: 'Earnings',
      body: summaryAsync.when(
        loading: () => const PageLoadingState(),
        error: (_, __) => const NetworkErrorState(),
        data: (summary) {
          if (summary.isEmpty) {
            return const AppEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No earnings yet',
              message: 'Delivered orders will credit your wallet here.',
            );
          }

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final weekStart = today.subtract(Duration(days: now.weekday - 1));
          final monthStart = DateTime(now.year, now.month, 1);

          num todayEarnings = 0;
          num weekEarnings = 0;
          num monthEarnings = 0;
          int monthCount = 0;
          for (final t in summary.transactions) {
            if (t.type != WalletTransactionType.credit) continue;
            if (!t.date.isBefore(monthStart)) {
              monthEarnings += t.amount;
              monthCount++;
              if (!t.date.isBefore(weekStart)) {
                weekEarnings += t.amount;
                if (!t.date.isBefore(today)) {
                  todayEarnings += t.amount;
                }
              }
            }
          }
          final avgPerTransaction = monthCount > 0 ? (monthEarnings / monthCount).round() : 0;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Earnings',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      CurrencyFormatter.format(summary.balance, currency: summary.currency),
                      style: AppTextStyles.onPrimaryH2.copyWith(fontSize: 30),
                    ),
                    const SizedBox(height: 4),
                    Text('${summary.transactions.length} transactions', style: AppTextStyles.onPrimaryBody),
                    if (summary.pendingAmount > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${CurrencyFormatter.format(summary.pendingAmount, currency: summary.currency)} pending',
                        style: AppTextStyles.onPrimaryBody,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _EarnStat(CurrencyFormatter.format(todayEarnings, currency: summary.currency), 'Today'),
                        Container(width: 1, height: 40, color: Colors.white24),
                        _EarnStat(CurrencyFormatter.format(weekEarnings, currency: summary.currency), 'This Week'),
                        Container(width: 1, height: 40, color: Colors.white24),
                        _EarnStat(CurrencyFormatter.format(monthEarnings, currency: summary.currency), 'This Month'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _QuickEarnCard(
                    'Avg/Transaction',
                    CurrencyFormatter.format(avgPerTransaction, currency: summary.currency),
                    Icons.bar_chart_rounded,
                    const Color(0xFF1565C0),
                  ),
                  const SizedBox(width: 12),
                  _QuickEarnCard(
                    'Pending',
                    CurrencyFormatter.format(summary.pendingAmount, currency: summary.currency),
                    Icons.hourglass_bottom_rounded,
                    AppColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Transaction History', style: AppTextStyles.h4),
              const SizedBox(height: 10),
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

class _EarnStat extends StatelessWidget {
  final String value, label;
  const _EarnStat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Colors.white70)),
        ],
      );
}

class _QuickEarnCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _QuickEarnCard(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w800, color: color),
                overflow: TextOverflow.ellipsis,
              ),
              Text(label, textAlign: TextAlign.center, style: AppTextStyles.caption, maxLines: 2),
            ],
          ),
        ),
      );
}
