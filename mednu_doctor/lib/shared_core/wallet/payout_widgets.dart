import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/router/app_router.dart';
import '../../core/services/feedback_service.dart';
import '../../core/widgets/ux_widgets.dart';
import 'currency_formatter.dart';
import 'payout_data.dart';
import 'wallet_providers.dart';

/// "Request payout" button, payout-account link and recent requests.
/// Drop it under any wallet/earnings summary. When [pending] is null the
/// amount comes from [walletSummaryProvider].
class PayoutActionsPanel extends ConsumerStatefulWidget {
  final num? pending;
  final double horizontalPadding;
  const PayoutActionsPanel({super.key, this.pending, this.horizontalPadding = 0});

  @override
  ConsumerState<PayoutActionsPanel> createState() => _PayoutActionsPanelState();
}

class _PayoutActionsPanelState extends ConsumerState<PayoutActionsPanel> {
  bool _busy = false;

  Future<void> _request(PayoutAccount acc, num estimate) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _ConfirmSheet(account: acc, estimate: estimate),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final amount = await PayoutService.requestPayout();
      if (!mounted) return;
      FeedbackService.showSuccess(
        context,
        amount > 0
            ? 'Payout of ${CurrencyFormatter.format(amount)} requested.'
            : 'Payout requested.',
      );
    } catch (e) {
      if (!mounted) return;
      FeedbackService.showError(context, PayoutService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final num pending = widget.pending ??
        ref.watch(walletSummaryProvider).maybeWhen<num>(data: (s) => s.pendingAmount, orElse: () => 0);
    final acc = ref.watch(payoutAccountProvider);
    final cfg = ref.watch(payoutConfigProvider).maybeWhen(
          data: (c) => c,
          orElse: () => const PayoutConfig(),
        );
    final reqs = ref.watch(payoutRequestsProvider);
    final requests = reqs.maybeWhen(data: (l) => l, orElse: () => const <PayoutRequest>[]);
    final hasOpen = requests.any((r) => r.isOpen);
    final account = acc.valueOrNull;

    String? reason;
    if (acc.isLoading && account == null) {
      reason = null;
    } else if (account == null) {
      reason = 'Add payout details';
    } else if (account.status == PayoutAccountStatus.pending) {
      reason = 'Verification pending';
    } else if (account.status == PayoutAccountStatus.rejected) {
      reason = 'Payout details were rejected. Update them to continue.';
    } else if (!cfg.enabled) {
      reason = 'Payouts are paused right now';
    } else if (hasOpen) {
      reason = 'Payout requested';
    } else if (pending < cfg.minAmount) {
      reason = 'Minimum ${CurrencyFormatter.format(cfg.minAmount)}';
    }
    final enabled = reason == null && account != null && !acc.isLoading && !_busy;

    String statusText;
    Color statusColor;
    if (account == null) {
      statusText = acc.isLoading ? 'Loading...' : 'Not added';
      statusColor = AppColors.textSecondary;
    } else if (account.status == PayoutAccountStatus.verified) {
      statusText = '${account.bankName} ${account.maskedNumber}';
      statusColor = AppColors.success;
    } else if (account.status == PayoutAccountStatus.pending) {
      statusText = 'Pending verification';
      statusColor = AppColors.warning;
    } else {
      statusText = 'Rejected';
      statusColor = AppColors.error;
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
      child: PremiumCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: enabled ? () => _request(account, pending) : null,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.north_east_rounded, size: 18),
                label: const Text('Request payout'),
              ),
            ),
            if (reason != null) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(reason,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
              ),
            ],
            const SizedBox(height: 8),
            _LinkRow(
              icon: Icons.account_balance_rounded,
              title: 'Payout account',
              value: statusText,
              valueColor: statusColor,
              onTap: () => context.push(AppRoutes.payoutAccount),
            ),
            const Divider(height: 1, color: AppColors.divider),
            _LinkRow(
              icon: Icons.receipt_long_rounded,
              title: 'Payout requests',
              value: reqs.isLoading
                  ? 'Loading...'
                  : reqs.hasError
                      ? 'Could not load'
                      : requests.isEmpty
                          ? 'None yet'
                          : requests.first.statusLabel,
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
                builder: (_) => const _RequestsSheet(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;
  final VoidCallback onTap;
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 12),
              Text(title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(color: valueColor),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
            ],
          ),
        ),
      );
}

class _ConfirmSheet extends StatelessWidget {
  final PayoutAccount account;
  final num estimate;
  const _ConfirmSheet({required this.account, required this.estimate});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Request payout', style: AppTextStyles.h3),
              const SizedBox(height: 14),
              const Text('Amount (estimate)', style: AppTextStyles.bodySmall),
              const SizedBox(height: 2),
              Text(CurrencyFormatter.format(estimate), style: AppTextStyles.h2),
              const SizedBox(height: 14),
              const Text('Paid to', style: AppTextStyles.bodySmall),
              const SizedBox(height: 2),
              Text('${account.bankName}  ${account.maskedNumber}',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
              Text(account.holderName, style: AppTextStyles.bodySmall),
              const SizedBox(height: 14),
              Text(
                'The final amount is confirmed when you request. Recovery adjustments may apply.',
                style: AppTextStyles.bodySmall.copyWith(height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Confirm request'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _RequestsSheet extends ConsumerStatefulWidget {
  const _RequestsSheet();

  @override
  ConsumerState<_RequestsSheet> createState() => _RequestsSheetState();
}

class _RequestsSheetState extends ConsumerState<_RequestsSheet> {
  String? _cancelling;

  Future<void> _cancel(PayoutRequest r) async {
    final ok = await FeedbackService.confirm(
      context,
      title: 'Cancel this request?',
      message: 'Your earnings stay in your wallet and you can request a payout again later.',
      confirmLabel: 'Cancel request',
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _cancelling = r.id);
    try {
      await PayoutService.cancelRequest(r.id);
      if (!mounted) return;
      FeedbackService.showSuccess(context, 'Payout request cancelled.');
    } catch (e) {
      if (!mounted) return;
      FeedbackService.showError(context, PayoutService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _cancelling = null);
    }
  }

  Color _color(String s) {
    switch (s) {
      case 'paid':
        return AppColors.success;
      case 'rejected':
      case 'cancelled':
        return AppColors.error;
      case 'held':
      case 'pending':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reqs = ref.watch(payoutRequestsProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Payout requests', style: AppTextStyles.h3),
              const SizedBox(height: 12),
              Flexible(
                child: reqs.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Could not load your requests. Please try again.')),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No payout requests yet.')),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                      itemBuilder: (_, i) {
                        final r = list[i];
                        final c = _color(r.status);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(CurrencyFormatter.format(r.amount),
                                        style: AppTextStyles.h4),
                                    const SizedBox(height: 2),
                                    Text(
                                      r.requestedAt == null
                                          ? 'Requested'
                                          : 'Requested ${DateFormat('d MMM, h:mm a').format(r.requestedAt!)}',
                                      style: AppTextStyles.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: c.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(r.statusLabel,
                                    style: AppTextStyles.caption
                                        .copyWith(color: c, fontWeight: FontWeight.w700)),
                              ),
                              if (r.canCancel) ...[
                                const SizedBox(width: 4),
                                TextButton(
                                  onPressed: _cancelling != null ? null : () => _cancel(r),
                                  child: _cancelling == r.id
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Text('Cancel'),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
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
