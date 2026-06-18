import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../referral/referral_provider.dart';
import '../../referral/referral_service.dart';
import '../wallet_provider.dart';
import '../wallet_service.dart';

// ── Category display helpers ──────────────────────────────
extension _TxCategory on WalletTransaction {
  IconData get icon {
    switch (category) {
      case 'add_money':    return Icons.add_circle_outline_rounded;
      case 'refund':       return Icons.replay_rounded;
      case 'cashback':     return Icons.card_giftcard_rounded;
      case 'consultation': return Icons.videocam_rounded;
      case 'referral':     return Icons.people_alt_rounded;
      case 'adjustment':   return Icons.tune_rounded;
      default:             return isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
    }
  }

  Color get color {
    if (isCredit) return AppColors.success;
    return AppColors.error;
  }

  String get formattedAmount =>
      '${isCredit ? '+' : '-'}₹${NumberFormat('#,##,##0.00').format(amount)}';

  String get formattedDate =>
      DateFormat('d MMM yyyy, h:mm a').format(timestamp);
}

// ── Wallet Screen ─────────────────────────────────────────
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync  = ref.watch(walletBalanceProvider);
    final pointsAsync   = ref.watch(walletReferralPointsProvider);
    final txAsync       = ref.watch(walletTransactionsProvider);
    final configAsync   = ref.watch(referralConfigProvider);
    final screenWidth   = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Header ─────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 240,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline_rounded, color: Colors.white70, size: 22),
                onPressed: () => _showHelpSheet(context),
              ),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _HeaderCard(
                balanceAsync: balanceAsync,
                onAddMoney: () => _showAddMoneySheet(context, ref),
                screenWidth: screenWidth,
              ),
            ),
          ),

          // ── Body ───────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Referral points banner
                  _ReferralBanner(
                    pointsAsync: pointsAsync,
                    configAsync: configAsync,
                  ),
                  const SizedBox(height: 20),

                  // Quick actions row
                  _QuickActions(
                    onAddMoney: () => _showAddMoneySheet(context, ref),
                    onTransfer: () => _showTransferSheet(context, ref),
                    onStatement: () => _showStatementSheet(context, ref),
                  ),
                  const SizedBox(height: 24),

                  // Transaction history header
                  Row(
                    children: [
                      Text('Transaction History', style: AppTextStyles.h4),
                      const Spacer(),
                      txAsync.maybeWhen(
                        data: (list) => list.isNotEmpty
                            ? Text('${list.length} entries',
                                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary))
                            : const SizedBox.shrink(),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // ── Transaction list ───────────────────────────
          txAsync.when(
            loading: () => SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => const _TxShimmer(),
                childCount: 6,
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: _ErrorState(
                message: e.toString(),
                onRetry: () => ref.invalidate(walletTransactionsProvider),
              ),
            ),
            data: (transactions) {
              if (transactions.isEmpty) {
                return const SliverToBoxAdapter(child: _EmptyState());
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _TransactionCard(tx: transactions[i]),
                    childCount: transactions.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Add Money bottom sheet ──────────────────────────────
  void _showAddMoneySheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddMoneySheet(),
    );
  }

  void _showTransferSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TransferSheet(),
    );
  }

  void _showStatementSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _StatementSheet(),
    );
  }

  void _showHelpSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wallet Help', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            _HelpItem(Icons.add_circle_outline_rounded, 'Add Money',
                'Add funds using UPI, card, or net banking. Reflects instantly.'),
            _HelpItem(Icons.security_rounded, 'Secure',
                'All transactions use atomic writes. No double deductions ever.'),
            _HelpItem(Icons.replay_rounded, 'Refunds',
                'Refunds are credited automatically within 24 hours.'),
            _HelpItem(Icons.support_agent_rounded, 'Support',
                'Contact support@mednu.in for any wallet issues.'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Header Card ───────────────────────────────────────────
class _HeaderCard extends StatelessWidget {
  final AsyncValue<double> balanceAsync;
  final VoidCallback onAddMoney;
  final double screenWidth;

  const _HeaderCard({
    required this.balanceAsync,
    required this.onAddMoney,
    required this.screenWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wallet icon + label
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.account_balance_wallet_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('MedNU Wallet',
                          style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 13,
                              color: Colors.white70, fontWeight: FontWeight.w500)),
                      Text('Available Balance',
                          style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 11,
                              color: Colors.white.withValues(alpha:0.5))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Balance
              balanceAsync.when(
                loading: () => Shimmer.fromColors(
                  baseColor: Colors.white24,
                  highlightColor: Colors.white38,
                  child: Container(
                    width: 180, height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                error: (_, __) => const Text('₹—',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 36,
                        fontWeight: FontWeight.w800, color: Colors.white)),
                data: (balance) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '₹${NumberFormat('#,##,##0.00').format(balance)}',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 38,
                        fontWeight: FontWeight.w800, color: Colors.white,
                        letterSpacing: -1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Referral Banner ───────────────────────────────────────
class _ReferralBanner extends ConsumerWidget {
  final AsyncValue<int> pointsAsync;
  final AsyncValue<ReferralConfig> configAsync;

  const _ReferralBanner({
    required this.pointsAsync,
    required this.configAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = pointsAsync.valueOrNull ?? 0;
    final config = configAsync.valueOrNull ?? const ReferralConfig();

    if (!config.referralEnabled) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _showReferralSheet(context, ref, config),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha:0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.withValues(alpha:0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha:0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.stars_rounded, color: Colors.amber, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$points Referral Points',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        fontSize: 13, color: Colors.amber),
                  ),
                  Text(
                    config.rewardsEnabled
                        ? 'Earn ${config.referrerRewardFormatted} per referral'
                        : config.bannerText,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _showReferralSheet(context, ref, config),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                minimumSize: const Size(68, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('Share',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showReferralSheet(
      BuildContext context, WidgetRef ref, ReferralConfig config) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReferralSheet(config: config),
    );
  }
}

// ── Referral Sheet ────────────────────────────────────────
class _ReferralSheet extends ConsumerWidget {
  final ReferralConfig config;
  const _ReferralSheet({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final referralCode = uid.isNotEmpty ? uid.substring(0, 8).toUpperCase() : '—';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Icon
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha:0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.card_giftcard_rounded,
                color: Colors.amber, size: 32),
          ),
          const SizedBox(height: 12),

          Text(config.campaignTitle,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 20)),
          const SizedBox(height: 6),
          Text(
            config.campaignMessage,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),

          // Reward cards
          if (config.rewardsEnabled) ...[
            Row(
              children: [
                Expanded(
                  child: _RewardCard(
                    label: 'You earn',
                    amount: config.referrerRewardFormatted,
                    icon: Icons.emoji_events_rounded,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RewardCard(
                    label: 'Friend gets',
                    amount: config.referredRewardFormatted,
                    icon: Icons.person_add_rounded,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          // Referral code box
          Text('Your Referral Code',
              style: AppTextStyles.labelMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: referralCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Referral code copied!')),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha:0.3), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(referralCode,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          letterSpacing: 4)),
                  const Icon(Icons.copy_rounded,
                      color: AppColors.primary, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Share button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share with Friends'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: () {
                final msg = '${config.campaignMessage}\n\n'
                    'Use my referral code: *$referralCode*\n'
                    'Download MedNu and get ${config.referredRewardFormatted} in your wallet!';
                Share.share(msg, subject: config.campaignTitle);
              },
            ),
          ),

          // Expiry notice
          if (config.offerExpiryDate != null) ...[
            const SizedBox(height: 12),
            Text(
              'Offer valid till ${DateFormat('d MMM yyyy').format(config.offerExpiryDate!)}',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],

          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/referral');
            },
            child: Text(
              'View Referral Dashboard →',
              style: AppTextStyles.labelMedium
                  .copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  final String label;
  final String amount;
  final IconData icon;
  final Color color;
  const _RewardCard(
      {required this.label,
      required this.amount,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha:0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(amount,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: color)),
          Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ── Quick Actions ─────────────────────────────────────────
class _QuickActions extends StatelessWidget {
  final VoidCallback onAddMoney;
  final VoidCallback onTransfer;
  final VoidCallback onStatement;

  const _QuickActions({
    required this.onAddMoney,
    required this.onTransfer,
    required this.onStatement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _ActionButton(
          icon: Icons.add_rounded,
          label: 'Add Money',
          gradient: const LinearGradient(
              colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
          onTap: onAddMoney,
        )),
        const SizedBox(width: 12),
        Expanded(child: _ActionButton(
          icon: Icons.send_rounded,
          label: 'Transfer',
          gradient: AppColors.primaryGradient,
          onTap: onTransfer,
        )),
        const SizedBox(width: 12),
        Expanded(child: _ActionButton(
          icon: Icons.receipt_long_rounded,
          label: 'Statement',
          gradient: const LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF42A5F5)]),
          onTap: onStatement,
        )),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  gradient: gradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 8),
              Text(label,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textPrimary),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Transaction Card ──────────────────────────────────────
class _TransactionCard extends StatelessWidget {
  final WalletTransaction tx;
  const _TransactionCard({required this.tx});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: tx.color.withValues(alpha:0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(tx.icon, color: tx.color, size: 20),
        ),
        title: Text(tx.title,
            style: AppTextStyles.labelLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(
          tx.formattedDate,
          style: AppTextStyles.bodySmall
              .copyWith(color: AppColors.textSecondary),
        ),
        trailing: Text(
          tx.formattedAmount,
          style: AppTextStyles.labelLarge.copyWith(
            color: tx.color,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

// ── Shimmer placeholder ───────────────────────────────────
class _TxShimmer extends StatelessWidget {
  const _TxShimmer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Shimmer.fromColors(
        baseColor: const Color(0xFFEEEEEE),
        highlightColor: const Color(0xFFFAFAFA),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long_rounded,
                size: 38, color: AppColors.primary.withValues(alpha:0.6)),
          ),
          const SizedBox(height: 16),
          Text('No Transactions Yet',
              style: AppTextStyles.h4
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            'Your transaction history will\nappear here once you start using the wallet.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textHint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha:0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.wifi_off_rounded,
                size: 38, color: AppColors.error.withValues(alpha:0.7)),
          ),
          const SizedBox(height: 16),
          Text('Couldn\'t Load Transactions',
              style: AppTextStyles.h4
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            'Check your internet connection and try again.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textHint),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ── Add Money Sheet ───────────────────────────────────────
class _AddMoneySheet extends ConsumerStatefulWidget {
  const _AddMoneySheet();

  @override
  ConsumerState<_AddMoneySheet> createState() => _AddMoneySheetState();
}

class _AddMoneySheetState extends ConsumerState<_AddMoneySheet> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  final _quickAmounts = [100, 200, 500, 1000, 2000, 5000];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    final amount = double.tryParse(text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (amount > 50000) {
      setState(() => _error = 'Maximum ₹50,000 per transaction');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(walletServiceProvider).addMoney(amount);
      if (!mounted) return;
      // Capture ScaffoldMessenger and Navigator synchronously before pop
      // so we never reference context across an async gap.
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      nav.pop();
      _showSuccess(amount, messenger);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _showSuccess(double amount, ScaffoldMessengerState messenger) {
    messenger.showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '₹${amount.toStringAsFixed(0)} added to wallet successfully',
            style: const TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w600),
          ),
        ),
      ]),
      backgroundColor: const Color(0xFF2E7D32),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text('Add Money to Wallet', style: AppTextStyles.h3),
          const SizedBox(height: 6),
          Text('Amount will be credited instantly',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 20),

          // Amount input
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
            ],
            autofocus: true,
            style: AppTextStyles.h2.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle:
                  AppTextStyles.h2.copyWith(color: AppColors.textSecondary),
              hintText: '0.00',
              hintStyle:
                  AppTextStyles.h2.copyWith(color: AppColors.textHint),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                    color: AppColors.primary.withValues(alpha:0.4), width: 2),
              ),
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 16),

          // Quick amounts
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickAmounts.map((a) => GestureDetector(
              onTap: () {
                _controller.text = a.toString();
                setState(() => _error = null);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.06),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha:0.2)),
                ),
                child: Text('₹$a',
                    style: AppTextStyles.labelMedium
                        .copyWith(color: AppColors.primary)),
              ),
            )).toList(),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Add Money'),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ── Transfer Sheet ────────────────────────────────────────
class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet();

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  final _phoneCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  final _quickAmounts = [100, 200, 500, 1000];

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phoneCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (phone.isEmpty || phone.length < 10) {
      setState(() => _error = 'Enter a valid 10-digit phone number');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    final normalised = phone.startsWith('+') ? phone : '+91$phone';
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(walletServiceProvider).transferToUser(
            recipientPhone: normalised,
            amount: amount,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '₹${NumberFormat('#,##,##0.00').format(amount)} transferred successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Transfer Money', style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text('Send wallet balance to another MedNu user',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 20),

          // Phone number field
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 10,
            decoration: InputDecoration(
              labelText: 'Recipient Phone Number',
              prefixText: '+91 ',
              counterText: '',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                    color: AppColors.primary.withValues(alpha:0.4), width: 2),
              ),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 14),

          // Amount field
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
            ],
            style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '₹ ',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                    color: AppColors.primary.withValues(alpha:0.4), width: 2),
              ),
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),

          // Quick amounts
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickAmounts.map((a) => GestureDetector(
              onTap: () {
                _amountCtrl.text = a.toString();
                setState(() => _error = null);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.06),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.primary.withValues(alpha:0.2)),
                ),
                child: Text('₹$a',
                    style: AppTextStyles.labelMedium
                        .copyWith(color: AppColors.primary)),
              ),
            )).toList(),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.send_rounded, size: 18),
              label: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Transfer Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _loading ? null : _submit,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ── Statement Sheet ───────────────────────────────────────
class _StatementSheet extends ConsumerStatefulWidget {
  const _StatementSheet();

  @override
  ConsumerState<_StatementSheet> createState() => _StatementSheetState();
}

class _StatementSheetState extends ConsumerState<_StatementSheet> {
  int _filter = 0; // 0=All, 1=Credits, 2=Debits

  List<WalletTransaction> _filtered(List<WalletTransaction> all) {
    if (_filter == 1) return all.where((t) => t.isCredit).toList();
    if (_filter == 2) return all.where((t) => !t.isCredit).toList();
    return all;
  }

  void _share(List<WalletTransaction> txs) {
    final buf = StringBuffer('MedNu Wallet Statement\n');
    buf.writeln('Generated: ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}');
    buf.writeln('─' * 32);
    for (final t in txs) {
      buf.writeln(
          '${t.formattedDate}  ${t.title.padRight(22)} ${t.formattedAmount}');
    }
    Share.share(buf.toString(), subject: 'MedNu Wallet Statement');
  }

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(walletTransactionsProvider);
    final maxH = MediaQuery.of(context).size.height * 0.82;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: Text('Statement', style: AppTextStyles.h3)),
                txAsync.maybeWhen(
                  data: (list) => IconButton(
                    icon: const Icon(Icons.share_rounded),
                    color: AppColors.primary,
                    onPressed: () => _share(_filtered(list)),
                    tooltip: 'Share',
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Filter tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _FilterChip(label: 'All', selected: _filter == 0,
                    onTap: () => setState(() => _filter = 0)),
                const SizedBox(width: 8),
                _FilterChip(label: 'Credits', selected: _filter == 1,
                    onTap: () => setState(() => _filter = 1)),
                const SizedBox(width: 8),
                _FilterChip(label: 'Debits', selected: _filter == 2,
                    onTap: () => setState(() => _filter = 2)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),

          // List
          Expanded(
            child: txAsync.when(
              loading: () => ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: 6,
                itemBuilder: (_, __) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SkeletonBox(width: double.infinity, height: 70),
                ),
              ),
              error: (e, _) => AppErrorState(
                message: 'Unable to load transactions. Try again.',
                onRetry: () => ref.invalidate(walletTransactionsProvider),
              ),
              data: (all) {
                final list = _filtered(all);
                if (list.isEmpty) {
                  return AppEmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'No transactions yet',
                    message: 'Your transaction history will appear here once you start using your wallet.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => FadeInSlide(
                    delay: Duration(milliseconds: i * 30),
                    child: _TransactionCard(tx: list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.primary.withValues(alpha:0.07),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: selected ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

// ── Help item ─────────────────────────────────────────────
class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _HelpItem(this.icon, this.title, this.desc);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(desc,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
