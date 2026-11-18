import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/feedback_service.dart';
import '../../core/widgets/ux_widgets.dart';
import '../models/app_role.dart';
import '../providers/role_providers.dart';
import 'payout_data.dart';

/// Bank details a partner is paid to. One screen for every role
/// (route [AppRoutes.payoutAccount]). Payouts go only to a verified account.
class PayoutAccountScreen extends ConsumerStatefulWidget {
  const PayoutAccountScreen({super.key});

  @override
  ConsumerState<PayoutAccountScreen> createState() => _PayoutAccountScreenState();
}

class _PayoutAccountScreenState extends ConsumerState<PayoutAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _holder = TextEditingController();
  final _account = TextEditingController();
  final _confirm = TextEditingController();
  final _ifsc = TextEditingController();
  final _bank = TextEditingController();
  final _upi = TextEditingController();
  bool _saving = false;
  bool _editing = false;
  bool _prefilled = false;
  bool _hideAccount = true;

  @override
  void dispose() {
    for (final c in [_holder, _account, _confirm, _ifsc, _bank, _upi]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill(PayoutAccount a) {
    _holder.text = a.holderName;
    _account.text = a.accountNumber;
    _confirm.text = '';
    _ifsc.text = a.ifsc;
    _bank.text = a.bankName;
    _upi.text = a.upiId;
  }

  Future<void> _save(String providerId) async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final role = ref.read(roleEngineProvider).activeRole.documentRoleKey;
      await PayoutService.saveAccount(
        providerId: providerId,
        role: role,
        holderName: _holder.text,
        accountNumber: _account.text,
        ifsc: _ifsc.text,
        bankName: _bank.text,
        upiId: _upi.text,
      );
      if (!mounted) return;
      setState(() {
        _editing = false;
        _prefilled = false;
      });
      FeedbackService.showSuccess(context, 'Details submitted. We will verify them shortly.');
    } catch (_) {
      if (!mounted) return;
      FeedbackService.showError(context, 'Could not save your details. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final idAsync = ref.watch(payoutProviderIdProvider);
    final accAsync = ref.watch(payoutAccountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Payout account'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: idAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _Message(
            icon: Icons.cloud_off_rounded,
            text: 'Could not load your account. Check your connection and try again.',
            onRetry: () => ref.invalidate(payoutProviderIdProvider),
          ),
          data: (providerId) {
            if (providerId == null) {
              return const _Message(icon: Icons.lock_outline_rounded, text: 'Please sign in again.');
            }
            return accAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _Message(
                icon: Icons.cloud_off_rounded,
                text: 'Could not load your payout details. Please try again.',
                onRetry: () => ref.invalidate(payoutAccountProvider),
              ),
              data: (acc) {
                final showForm = acc == null || _editing;
                if (acc != null && _editing && !_prefilled) {
                  _prefill(acc);
                  _prefilled = true;
                }
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                          16, 16, 16, 24 + MediaQuery.of(context).viewInsets.bottom),
                      children: [
                        if (acc != null) _StatusCard(account: acc),
                        if (acc != null) const SizedBox(height: 12),
                        if (!showForm) ...[
                          _DetailsCard(
                            account: acc,
                            hidden: _hideAccount,
                            onToggle: () => setState(() => _hideAccount = !_hideAccount),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() => _editing = true),
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              label: const Text('Change details'),
                            ),
                          ),
                        ] else
                          _form(providerId, acc),
                        const SizedBox(height: 14),
                        const _InfoNote(),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  InputDecoration _dec(String label, {String? hint, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _form(String providerId, PayoutAccount? acc) {
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(acc == null ? 'Add bank details' : 'Update bank details', style: AppTextStyles.h4),
            const SizedBox(height: 14),
            TextFormField(
              controller: _holder,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: _dec('Account holder name'),
              validator: PayoutValidators.holderName,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _account,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(20)],
              decoration: _dec('Account number'),
              validator: PayoutValidators.accountNumber,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(20)],
              decoration: _dec('Confirm account number'),
              validator: (v) => PayoutValidators.confirmAccount(v, _account.text),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ifsc,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(11),
                _UpperCaseFormatter(),
              ],
              decoration: _dec('IFSC code', hint: 'HDFC0001234'),
              validator: PayoutValidators.ifsc,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bank,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: _dec('Bank name'),
              validator: PayoutValidators.bankName,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _upi,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              decoration: _dec('UPI id (optional)', hint: 'name@bank'),
              validator: PayoutValidators.upi,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (acc != null) ...[
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                  _editing = false;
                                  _prefilled = false;
                                }),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(providerId),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Submit for verification'),
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
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) =>
      next.copyWith(text: next.text.toUpperCase());
}

class _StatusCard extends StatelessWidget {
  final PayoutAccount account;
  const _StatusCard({required this.account});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final Color bg;
    late final IconData icon;
    late final String label;
    late final String sub;
    switch (account.status) {
      case PayoutAccountStatus.verified:
        color = AppColors.success;
        bg = AppColors.successBg;
        icon = Icons.verified_rounded;
        label = 'Verified';
        sub = 'Payouts will be sent to this account.';
        break;
      case PayoutAccountStatus.rejected:
        color = AppColors.error;
        bg = AppColors.errorBg;
        icon = Icons.error_outline_rounded;
        label = 'Rejected';
        final r = (account.rejectReason ?? '').trim();
        sub = r.isEmpty ? 'Please correct your details and submit again.' : r;
        break;
      case PayoutAccountStatus.pending:
        color = AppColors.warning;
        bg = AppColors.warningBg;
        icon = Icons.hourglass_top_rounded;
        label = 'Pending verification';
        sub = 'We are checking your details. This usually takes a short while.';
        break;
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.h4.copyWith(color: color)),
                const SizedBox(height: 2),
                Text(sub, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final PayoutAccount account;
  final bool hidden;
  final VoidCallback onToggle;
  const _DetailsCard({required this.account, required this.hidden, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 112, child: Text(k, style: AppTextStyles.bodySmall)),
              Expanded(
                child: Text(v.isEmpty ? '-' : v, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (trailing != null) trailing,
            ],
          ),
        );
    return PremiumCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          row('Account holder', account.holderName),
          row('Bank', account.bankName),
          row(
            'Account number',
            hidden ? account.maskedNumber : account.accountNumber,
            trailing: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 20, color: AppColors.textSecondary),
              ),
            ),
          ),
          row('IFSC', account.ifsc),
          row('UPI id', account.upiId),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote();

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 14, color: AppColors.textHint),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Changing details requires verification again; payouts go only to a verified account.',
              style: AppTextStyles.caption.copyWith(height: 1.4),
            ),
          ),
        ],
      );
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  const _Message({required this.icon, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center, style: AppTextStyles.body),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      );
}
