import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../providers/counselling_providers.dart';

/// Earnings — hero total + recent completed sessions, backed by the real
/// `counselling_transactions` ledger via `walletSummaryProvider`
/// (shared_core/wallet). Mirrors the Physiotherapy module's Earnings screen.
class CounsellingEarningsScreen extends ConsumerWidget {
  const CounsellingEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(walletSummaryProvider);
    final history = ref.watch(counsellingSessionHistoryProvider);
    final weeklySeries = ref.watch(weeklyCounsellingEarningsProvider);
    final completedCount = history.where((s) => s.status.name == 'completed').length;

    return SharedAppShell(
      currentRoute: AppRoutes.counsellingEarnings,
      title: 'Earnings',
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const AppErrorState(message: 'Could not load earnings.'),
        data: (data) {
          // Today/week/month breakdown computed client-side from the live
          // transaction list — mirrors Hospital's Earnings screen, which does
          // the same aggregation over `walletSummaryProvider.transactions`.
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final weekStart = today.subtract(Duration(days: now.weekday - 1));
          final monthStart = DateTime(now.year, now.month, 1);

          num todayEarnings = 0;
          num weekEarnings = 0;
          num monthEarnings = 0;
          int monthCount = 0;
          for (final t in data.transactions) {
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
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _EarnStat('₹${todayEarnings.toInt()}', 'Today'),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _EarnStat('₹${weekEarnings.toInt()}', 'This Week'),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _EarnStat('₹${monthEarnings.toInt()}', 'This Month'),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              _QuickEarnCard('Avg/Transaction', '₹$avgPerTransaction', Icons.bar_chart_rounded, const Color(0xFF1565C0)),
              const SizedBox(width: 12),
              _QuickEarnCard('Pending', '₹${data.pendingAmount.toInt()}', Icons.hourglass_bottom_rounded, AppColors.warning),
            ]),
            const SizedBox(height: 16),
            _WeeklyTrendCard(series: weeklySeries),
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
                          child: const Icon(Icons.psychology_rounded, color: AppColors.success, size: 20),
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
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
    Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Colors.white70)),
  ]);
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        Text(label, textAlign: TextAlign.center, style: AppTextStyles.caption, maxLines: 2),
      ]),
    ),
  );
}

/// Compact Mon–Sun bar chart sourced from `weeklyCounsellingEarningsProvider`
/// (7-bucket series derived from the live completed-session stream). Bars
/// are height-ratio only, capped to a fixed row height, so no overflow risk
/// regardless of earnings magnitude.
class _WeeklyTrendCard extends StatelessWidget {
  final List<double> series;
  const _WeeklyTrendCard({required this.series});

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final maxValue = series.isEmpty ? 0.0 : series.reduce((a, b) => a > b ? a : b);
    final todayIndex = DateTime.now().weekday - 1;

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This Week', style: AppTextStyles.labelMedium),
          const SizedBox(height: 14),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(series.length, (i) {
                final value = series[i];
                final ratio = maxValue > 0 ? (value / maxValue).clamp(0.06, 1.0) : 0.06;
                final isToday = i == todayIndex;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: ratio,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isToday ? AppColors.primary : AppColors.primary.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _dayLabels[i],
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                            color: isToday ? AppColors.primary : AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
