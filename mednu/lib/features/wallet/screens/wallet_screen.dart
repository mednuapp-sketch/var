import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mednu/core/constants/app_colors.dart';
import 'package:mednu/core/constants/app_text_styles.dart';
import 'package:mednu/core/utils/r.dart';
import 'package:mednu/core/widgets/ux_widgets.dart';
import 'package:mednu/features/referral/referral_provider.dart';
import 'package:mednu/features/referral/referral_service.dart';
import 'package:mednu/features/wallet/wallet_provider.dart';
import 'package:mednu/features/wallet/wallet_service.dart';

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
    final balanceAsync      = ref.watch(walletBalanceProvider);
    final mednuMoneyAsync   = ref.watch(mednuMoneyBalanceProvider);
    final pointsAsync       = ref.watch(walletReferralPointsProvider);
    final txAsync           = ref.watch(walletTransactionsProvider);
    final configAsync       = ref.watch(referralConfigProvider);
    final screenWidth       = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Header ─────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: R.h(context, 240),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: R.w(context, 20)),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.help_outline_rounded, color: Colors.white70, size: R.w(context, 22)),
                onPressed: () => _showHelpSheet(context),
              ),
              SizedBox(width: R.w(context, 4)),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _HeaderCard(
                balanceAsync: balanceAsync,
                mednuMoneyAsync: mednuMoneyAsync,
                onAddMoney: () => _showAddMoneySheet(context, ref),
                screenWidth: screenWidth,
              ),
            ),
          ),

          // ── Body ───────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 16), R.p(context, 16), 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // MedNU Money card
                  _MednuMoneyCard(mednuMoneyAsync: mednuMoneyAsync),
                  SizedBox(height: R.h(context, 14)),

                  // Referral points banner
                  _ReferralBanner(
                    pointsAsync: pointsAsync,
                    configAsync: configAsync,
                  ),
                  SizedBox(height: R.h(context, 20)),

                  // Quick actions row
                  _QuickActions(
                    onAddMoney: () => _showAddMoneySheet(context, ref),
                    onTransfer: () => _showTransferSheet(context, ref),
                    onStatement: () => _showStatementSheet(context, ref),
                  ),
                  SizedBox(height: R.h(context, 14)),

                  // Refunds section
                  _RefundsSection(
                    txAsync: txAsync,
                    onViewAll: () => _showRefundsSheet(context, ref),
                  ),
                  SizedBox(height: R.h(context, 24)),

                  // Transaction history header
                  Row(
                    children: [
                      Text('Transaction History', style: AppTextStyles.h4),
                      const Spacer(),
                      txAsync.maybeWhen(
                        data: (list) => list.isNotEmpty
                            ? Text('${list.length} entries',
                                style: AppTextStyles.caption.copyWith(color: context.appTextSecondary))
                            : const SizedBox.shrink(),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  SizedBox(height: R.h(context, 12)),
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
                padding: EdgeInsets.fromLTRB(R.p(context, 16), 0, R.p(context, 16), R.p(context, 32)),
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

  void _showRefundsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RefundsSheet(
        txAsync: ref.read(walletTransactionsProvider),
      ),
    );
  }

  void _showHelpSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.all(R.p(ctx, 24)),
        decoration: BoxDecoration(
          color: ctx.appSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.r(ctx, 28))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wallet Help', style: AppTextStyles.h3),
            SizedBox(height: R.h(ctx, 16)),
            _HelpItem(Icons.add_circle_outline_rounded, 'Add Money',
                'Add funds using UPI, card, or net banking. Reflects instantly.'),
            _HelpItem(Icons.security_rounded, 'Secure',
                'All transactions use atomic writes. No double deductions ever.'),
            _HelpItem(Icons.replay_rounded, 'Refunds',
                'Refunds are credited automatically within 24 hours.'),
            _HelpItem(Icons.support_agent_rounded, 'Support',
                'Contact support@mednu.in for any wallet issues.'),
            SizedBox(height: R.h(ctx, 8)),
          ],
        ),
      ),
    );
  }
}

// ── Header Card ───────────────────────────────────────────
class _HeaderCard extends StatelessWidget {
  final AsyncValue<double> balanceAsync;
  final AsyncValue<double> mednuMoneyAsync;
  final VoidCallback onAddMoney;
  final double screenWidth;

  const _HeaderCard({
    required this.balanceAsync,
    required this.mednuMoneyAsync,
    required this.onAddMoney,
    required this.screenWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
          padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 56), R.p(context, 20), R.p(context, 16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wallet icon + label
              Row(
                children: [
                  Container(
                    width: R.w(context, 40), height: R.h(context, 40),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(R.r(context, 12)),
                    ),
                    child: Icon(Icons.account_balance_wallet_rounded,
                        color: Colors.white, size: R.w(context, 22)),
                  ),
                  SizedBox(width: R.w(context, 10)),
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
                              color: Colors.white.withValues(alpha: 0.5))),
                    ],
                  ),
                ],
              ),
              SizedBox(height: R.h(context, 10)),

              // Main wallet balance
              balanceAsync.when(
                loading: () => AppShimmer(
                  child: Container(
                    width: R.w(context, 180), height: R.h(context, 40),
                    decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(R.r(context, 8)),
                    ),
                  ),
                ),
                error: (_, __) => const Text('₹—',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 34,
                        fontWeight: FontWeight.w800, color: Colors.white)),
                data: (balance) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '₹${NumberFormat('#,##,##0.00').format(balance)}',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 36,
                        fontWeight: FontWeight.w800, color: Colors.white,
                        letterSpacing: -1),
                  ),
                ),
              ),
              SizedBox(height: R.h(context, 12)),

              // MedNU Money pill
              mednuMoneyAsync.maybeWhen(
                data: (mm) => Container(
                  padding: EdgeInsets.symmetric(horizontal: R.p(context, 12), vertical: R.p(context, 7)),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(R.r(context, 24)),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stars_rounded,
                          color: Colors.amber, size: R.w(context, 15)),
                      SizedBox(width: R.w(context, 6)),
                      Text(
                        'MedNU Money  ₹${NumberFormat('#,##,##0.00').format(mm)}',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── MedNU Money Card ──────────────────────────────────────
class _MednuMoneyCard extends StatelessWidget {
  final AsyncValue<double> mednuMoneyAsync;
  const _MednuMoneyCard({required this.mednuMoneyAsync});

  @override
  Widget build(BuildContext context) {
    final balance = mednuMoneyAsync.valueOrNull ?? 0.0;
    return Container(
      padding: EdgeInsets.all(R.p(context, 16)),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(R.r(context, 18)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6A1B9A).withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: R.w(context, 38), height: R.h(context, 38),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(R.r(context, 10)),
                ),
                child: Icon(Icons.stars_rounded,
                    color: Colors.amber, size: R.w(context, 20)),
              ),
              SizedBox(width: R.w(context, 10)),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MedNU Money',
                        style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                    Text('Bonus credits for MedNU bookings only',
                        style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 10,
                            color: Colors.white70)),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: R.p(context, 8), vertical: R.p(context, 4)),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(R.r(context, 8)),
                ),
                child: const Text('Non-withdrawable',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 9,
                        fontWeight: FontWeight.w600, color: Colors.white70)),
              ),
            ],
          ),
          SizedBox(height: R.h(context, 14)),
          mednuMoneyAsync.when(
            loading: () => AppShimmer(
              child: Container(
                width: R.w(context, 140), height: R.h(context, 32),
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(R.r(context, 6)),
                ),
              ),
            ),
            error: (_, __) => const Text('₹—',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 28,
                    fontWeight: FontWeight.w800, color: Colors.white)),
            data: (mm) => Text(
              '₹${NumberFormat('#,##,##0.00').format(mm)}',
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 28,
                  fontWeight: FontWeight.w800, color: Colors.white,
                  letterSpacing: -0.5),
            ),
          ),
          SizedBox(height: R.h(context, 10)),
          Row(
            children: [
              Expanded(
                child: _MednuMoneyBullet(Icons.check_circle_outline_rounded,
                    'Use for consultations & bookings'),
              ),
              SizedBox(width: R.w(context, 12)),
              Expanded(
                child: _MednuMoneyBullet(
                    Icons.block_rounded, 'Cannot transfer or withdraw'),
              ),
            ],
          ),
          if (balance > 0) ...[
            SizedBox(height: R.h(context, 10)),
            Container(
              padding: EdgeInsets.symmetric(horizontal: R.p(context, 10), vertical: R.p(context, 6)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(R.r(context, 10)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.white70, size: R.w(context, 14)),
                  SizedBox(width: R.w(context, 6)),
                  Text(
                    'Apply at checkout to save ₹${NumberFormat('#,##,##0').format(balance)}',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 11,
                        color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MednuMoneyBullet extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MednuMoneyBullet(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: R.w(context, 12), color: Colors.white60),
        SizedBox(width: R.w(context, 4)),
        Flexible(
          child: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 10, color: Colors.white70)),
        ),
      ],
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
        padding: EdgeInsets.all(R.p(context, 14)),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha:0.08),
          borderRadius: BorderRadius.circular(R.r(context, 16)),
          border: Border.all(color: Colors.amber.withValues(alpha:0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: R.w(context, 40), height: R.h(context, 40),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha:0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.stars_rounded, color: Colors.amber, size: R.w(context, 22)),
            ),
            SizedBox(width: R.w(context, 12)),
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
                        .copyWith(color: context.appTextSecondary),
                  ),
                ],
              ),
            ),
            SizedBox(width: R.w(context, 8)),
            ElevatedButton(
              onPressed: () => _showReferralSheet(context, ref, config),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                minimumSize: const Size(68, 34),
                padding: EdgeInsets.symmetric(horizontal: R.p(context, 12)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.r(context, 10))),
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
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.r(context, 28))),
      ),
      padding: EdgeInsets.fromLTRB(
          R.p(context, 24), R.p(context, 20), R.p(context, 24), MediaQuery.of(context).viewInsets.bottom + R.p(context, 32)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: R.w(context, 40), height: R.h(context, 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(R.r(context, 2)),
            ),
          ),
          SizedBox(height: R.h(context, 20)),

          // Icon
          Container(
            width: R.w(context, 64), height: R.h(context, 64),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha:0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.card_giftcard_rounded,
                color: Colors.amber, size: R.w(context, 32)),
          ),
          SizedBox(height: R.h(context, 12)),

          Text(config.campaignTitle,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 20)),
          SizedBox(height: R.h(context, 6)),
          Text(
            config.campaignMessage,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium
                .copyWith(color: context.appTextSecondary),
          ),
          SizedBox(height: R.h(context, 20)),

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
                SizedBox(width: R.w(context, 12)),
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
            SizedBox(height: R.h(context, 20)),
          ],

          // Referral code box
          Text('Your Referral Code',
              style: AppTextStyles.labelMedium
                  .copyWith(color: context.appTextSecondary)),
          SizedBox(height: R.h(context, 8)),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: referralCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Referral code copied!')),
              );
            },
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: R.p(context, 14), horizontal: R.p(context, 20)),
              decoration: BoxDecoration(
                color: context.appBackground,
                borderRadius: BorderRadius.circular(R.r(context, 14)),
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
                  Icon(Icons.copy_rounded,
                      color: AppColors.primary, size: R.w(context, 20)),
                ],
              ),
            ),
          ),
          SizedBox(height: R.h(context, 20)),

          // Share button
          SizedBox(
            width: double.infinity,
            height: R.h(context, 52),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share with Friends'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.r(context, 14))),
                elevation: 0,
              ),
              onPressed: () {
                final msg = '${config.campaignMessage}\n\n'
                    'Use my referral code: *$referralCode*\n'
                    'Download MedNU and get ${config.referredRewardFormatted} in your wallet!';
                Share.share(msg, subject: config.campaignTitle);
              },
            ),
          ),

          // Expiry notice
          if (config.offerExpiryDate != null) ...[
            SizedBox(height: R.h(context, 12)),
            Text(
              'Offer valid till ${DateFormat('d MMM yyyy').format(config.offerExpiryDate!)}',
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.appTextSecondary),
            ),
          ],

          SizedBox(height: R.h(context, 8)),
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
      padding: EdgeInsets.symmetric(vertical: R.p(context, 14), horizontal: R.p(context, 12)),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.07),
        borderRadius: BorderRadius.circular(R.r(context, 14)),
        border: Border.all(color: color.withValues(alpha:0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: R.w(context, 22)),
          SizedBox(height: R.h(context, 6)),
          Text(amount,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: color)),
          Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.appTextSecondary)),
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
        SizedBox(width: R.w(context, 12)),
        Expanded(child: _ActionButton(
          icon: Icons.send_rounded,
          label: 'Transfer',
          gradient: AppColors.primaryGradient,
          onTap: onTransfer,
        )),
        SizedBox(width: R.w(context, 12)),
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
      color: context.appSurface,
      borderRadius: BorderRadius.circular(R.r(context, 16)),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.r(context, 16)),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: R.p(context, 14)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.r(context, 16)),
            border: Border.all(color: context.appBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: R.w(context, 42), height: R.h(context, 42),
                decoration: BoxDecoration(
                  gradient: gradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: R.w(context, 20)),
              ),
              SizedBox(height: R.h(context, 8)),
              Text(label,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: context.appTextPrimary),
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
      margin: EdgeInsets.only(bottom: R.p(context, 10)),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(R.r(context, 16)),
        border: Border.all(color: context.appBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: R.p(context, 14), vertical: R.p(context, 6)),
        leading: Container(
          width: R.w(context, 44), height: R.h(context, 44),
          decoration: BoxDecoration(
            color: tx.color.withValues(alpha:0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(tx.icon, color: tx.color, size: R.w(context, 20)),
        ),
        title: Text(tx.title,
            style: AppTextStyles.labelLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(
          tx.formattedDate,
          style: AppTextStyles.bodySmall
              .copyWith(color: context.appTextSecondary),
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SkeletonBox(width: double.infinity, height: 72, radius: 16),
    );
  }
}

// ── Empty state ───────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: R.p(context, 48), horizontal: R.p(context, 32)),
      child: Column(
        children: [
          Container(
            width: R.w(context, 80), height: R.h(context, 80),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long_rounded,
                size: R.w(context, 38), color: AppColors.primary.withValues(alpha:0.6)),
          ),
          SizedBox(height: R.h(context, 16)),
          Text('No Transactions Yet',
              style: AppTextStyles.h4
                  .copyWith(color: context.appTextSecondary)),
          SizedBox(height: R.h(context, 8)),
          Text(
            'Your transaction history will\nappear here once you start using the wallet.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: context.appTextHint),
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
      padding: EdgeInsets.symmetric(vertical: R.p(context, 48), horizontal: R.p(context, 32)),
      child: Column(
        children: [
          Container(
            width: R.w(context, 80), height: R.h(context, 80),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha:0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.wifi_off_rounded,
                size: R.w(context, 38), color: AppColors.error.withValues(alpha:0.7)),
          ),
          SizedBox(height: R.h(context, 16)),
          Text('Couldn\'t Load Transactions',
              style: AppTextStyles.h4
                  .copyWith(color: context.appTextSecondary)),
          SizedBox(height: R.h(context, 8)),
          Text(
            'Check your internet connection and try again.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: context.appTextHint),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: R.h(context, 20)),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: Icon(Icons.refresh_rounded, size: R.w(context, 18)),
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
      padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 20), R.p(context, 20), R.p(context, 20) + bottom),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.r(context, 28))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: R.w(context, 40), height: R.h(context, 4),
              decoration: BoxDecoration(
                color: context.appBorder,
                borderRadius: BorderRadius.circular(R.r(context, 2)),
              ),
            ),
          ),
          SizedBox(height: R.h(context, 20)),

          Text('Add Money to Wallet', style: AppTextStyles.h3),
          SizedBox(height: R.h(context, 6)),
          Text('Amount will be credited instantly',
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.appTextSecondary)),
          SizedBox(height: R.h(context, 20)),

          // Amount input
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
            ],
            autofocus: true,
            style: AppTextStyles.h2.copyWith(color: context.appTextPrimary),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle:
                  AppTextStyles.h2.copyWith(color: context.appTextSecondary),
              hintText: '0.00',
              hintStyle:
                  AppTextStyles.h2.copyWith(color: context.appTextHint),
              filled: true,
              fillColor: context.appBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.r(context, 16)),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.r(context, 16)),
                borderSide: BorderSide(
                    color: AppColors.primary.withValues(alpha:0.4), width: 2),
              ),
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          SizedBox(height: R.h(context, 16)),

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
                    EdgeInsets.symmetric(horizontal: R.p(context, 14), vertical: R.p(context, 8)),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.06),
                  borderRadius: BorderRadius.circular(R.r(context, 24)),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha:0.2)),
                ),
                child: Text('₹$a',
                    style: AppTextStyles.labelMedium
                        .copyWith(color: AppColors.primary)),
              ),
            )).toList(),
          ),
          SizedBox(height: R.h(context, 24)),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? SizedBox(
                      width: R.w(context, 20), height: R.h(context, 20),
                      child: const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Add Money'),
            ),
          ),
          SizedBox(height: R.h(context, 4)),
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
      padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 20), R.p(context, 20), R.p(context, 20) + bottom),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.r(context, 28))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: R.w(context, 40), height: R.h(context, 4),
              decoration: BoxDecoration(
                color: context.appBorder,
                borderRadius: BorderRadius.circular(R.r(context, 2)),
              ),
            ),
          ),
          SizedBox(height: R.h(context, 20)),
          Text('Transfer Money', style: AppTextStyles.h3),
          SizedBox(height: R.h(context, 4)),
          Text('Send wallet balance to another MedNU user',
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.appTextSecondary)),
          SizedBox(height: R.h(context, 20)),

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
              fillColor: context.appBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.r(context, 14)),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.r(context, 14)),
                borderSide: BorderSide(
                    color: AppColors.primary.withValues(alpha:0.4), width: 2),
              ),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          SizedBox(height: R.h(context, 14)),

          // Amount field
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
            ],
            style: AppTextStyles.h3.copyWith(color: context.appTextPrimary),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '₹ ',
              filled: true,
              fillColor: context.appBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.r(context, 14)),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.r(context, 14)),
                borderSide: BorderSide(
                    color: AppColors.primary.withValues(alpha:0.4), width: 2),
              ),
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          SizedBox(height: R.h(context, 12)),

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
                padding: EdgeInsets.symmetric(horizontal: R.p(context, 14), vertical: R.p(context, 8)),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.06),
                  borderRadius: BorderRadius.circular(R.r(context, 24)),
                  border: Border.all(color: AppColors.primary.withValues(alpha:0.2)),
                ),
                child: Text('₹$a',
                    style: AppTextStyles.labelMedium
                        .copyWith(color: AppColors.primary)),
              ),
            )).toList(),
          ),
          SizedBox(height: R.h(context, 24)),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: Icon(Icons.send_rounded, size: R.w(context, 18)),
              label: _loading
                  ? SizedBox(
                      width: R.w(context, 20), height: R.h(context, 20),
                      child: const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Transfer Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.r(context, 14))),
                elevation: 0,
              ),
              onPressed: _loading ? null : _submit,
            ),
          ),
          SizedBox(height: R.h(context, 4)),
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
    final buf = StringBuffer('MedNU Wallet Statement\n');
    buf.writeln('Generated: ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}');
    buf.writeln('─' * 32);
    for (final t in txs) {
      buf.writeln(
          '${t.formattedDate}  ${t.title.padRight(22)} ${t.formattedAmount}');
    }
    Share.share(buf.toString(), subject: 'MedNU Wallet Statement');
  }

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(walletTransactionsProvider);
    final maxH = MediaQuery.of(context).size.height * 0.82;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.r(context, 28))),
      ),
      child: Column(
        children: [
          // Handle
          SizedBox(height: R.h(context, 12)),
          Container(
            width: R.w(context, 40), height: R.h(context, 4),
            decoration: BoxDecoration(
              color: context.appBorder,
              borderRadius: BorderRadius.circular(R.r(context, 2)),
            ),
          ),
          SizedBox(height: R.h(context, 16)),

          // Header
          Padding(
            padding: EdgeInsets.symmetric(horizontal: R.p(context, 20)),
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
          SizedBox(height: R.h(context, 8)),

          // Filter tabs
          Padding(
            padding: EdgeInsets.symmetric(horizontal: R.p(context, 20)),
            child: Row(
              children: [
                _FilterChip(label: 'All', selected: _filter == 0,
                    onTap: () => setState(() => _filter = 0)),
                SizedBox(width: R.w(context, 8)),
                _FilterChip(label: 'Credits', selected: _filter == 1,
                    onTap: () => setState(() => _filter = 1)),
                SizedBox(width: R.w(context, 8)),
                _FilterChip(label: 'Debits', selected: _filter == 2,
                    onTap: () => setState(() => _filter = 2)),
              ],
            ),
          ),
          SizedBox(height: R.h(context, 12)),
          const Divider(height: 1),

          // List
          Expanded(
            child: txAsync.when(
              loading: () => ListView.builder(
                padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 8), R.p(context, 16), R.p(context, 24)),
                itemCount: 6,
                itemBuilder: (_, __) => Padding(
                  padding: EdgeInsets.only(bottom: R.p(context, 10)),
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
                  padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 8), R.p(context, 16), R.p(context, 24)),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => SizedBox(height: R.h(context, 8)),
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
        padding: EdgeInsets.symmetric(horizontal: R.p(context, 16), vertical: R.p(context, 8)),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.primary.withValues(alpha:0.07),
          borderRadius: BorderRadius.circular(R.r(context, 24)),
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

// ── Refunds Section ──────────────────────────────────────
class _RefundsSection extends StatelessWidget {
  final AsyncValue<List<WalletTransaction>> txAsync;
  final VoidCallback onViewAll;
  const _RefundsSection({required this.txAsync, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    final refunds = txAsync.valueOrNull
            ?.where((t) => t.category == 'refund')
            .toList() ??
        [];
    final total = refunds.fold<double>(
        0, (sum, t) => sum + (t.isCredit ? t.amount : -t.amount));
    final isLoading = txAsync.isLoading;

    return GestureDetector(
      onTap: onViewAll,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: R.p(context, 16), vertical: R.p(context, 14)),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(R.r(context, 16)),
          border: Border.all(color: context.appBorder),
        ),
        child: Row(
          children: [
            Container(
              width: R.w(context, 42),
              height: R.h(context, 42),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(R.r(context, 12)),
              ),
              child: Icon(Icons.replay_rounded,
                  color: const Color(0xFF1565C0), size: R.w(context, 22)),
            ),
            SizedBox(width: R.w(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Refunds',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                  SizedBox(height: R.h(context, 2)),
                  isLoading
                      ? Text('Loading...',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: context.appTextSecondary))
                      : Text(
                          refunds.isEmpty
                              ? 'No refunds yet'
                              : '${refunds.length} refund${refunds.length == 1 ? '' : 's'} · ₹${NumberFormat('#,##,##0.00').format(total)} credited',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: context.appTextSecondary),
                        ),
                ],
              ),
            ),
            if (!isLoading && refunds.isNotEmpty)
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: R.p(context, 8), vertical: R.p(context, 3)),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(R.r(context, 20)),
                ),
                child: Text(
                  '${refunds.length}',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ),
            SizedBox(width: R.w(context, 8)),
            Icon(Icons.arrow_forward_ios_rounded,
                size: R.w(context, 14), color: context.appTextHint),
          ],
        ),
      ),
    );
  }
}

// ── Refunds Sheet ─────────────────────────────────────────
class _RefundsSheet extends StatelessWidget {
  final AsyncValue<List<WalletTransaction>> txAsync;
  const _RefundsSheet({required this.txAsync});

  @override
  Widget build(BuildContext context) {
    final refunds =
        txAsync.valueOrNull?.where((t) => t.category == 'refund').toList() ??
            [];
    final maxH = MediaQuery.of(context).size.height * 0.75;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.r(context, 28))),
      ),
      child: Column(
        children: [
          SizedBox(height: R.h(context, 12)),
          Container(
            width: R.w(context, 40),
            height: R.h(context, 4),
            decoration: BoxDecoration(
              color: context.appBorder,
              borderRadius: BorderRadius.circular(R.r(context, 2)),
            ),
          ),
          SizedBox(height: R.h(context, 16)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: R.p(context, 20)),
            child: Row(
              children: [
                Container(
                  width: R.w(context, 38),
                  height: R.h(context, 38),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(R.r(context, 10)),
                  ),
                  child: Icon(Icons.replay_rounded,
                      color: const Color(0xFF1565C0), size: R.w(context, 20)),
                ),
                SizedBox(width: R.w(context, 10)),
                Text('My Refunds', style: AppTextStyles.h3),
                const Spacer(),
                if (refunds.isNotEmpty)
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: R.p(context, 10), vertical: R.p(context, 4)),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(R.r(context, 20)),
                    ),
                    child: Text(
                      '${refunds.length}',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: R.h(context, 12)),
          const Divider(height: 1),
          Expanded(
            child: refunds.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(R.p(context, 40)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: R.w(context, 72),
                            height: R.h(context, 72),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE3F2FD),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.replay_rounded,
                                size: R.w(context, 34), color: const Color(0xFF1565C0)),
                          ),
                          SizedBox(height: R.h(context, 16)),
                          Text('No Refunds Yet',
                              style: AppTextStyles.h4
                                  .copyWith(color: context.appTextSecondary)),
                          SizedBox(height: R.h(context, 8)),
                          Text(
                            'Refunds from cancelled bookings\nwill appear here.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: context.appTextHint),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 12), R.p(context, 16), R.p(context, 24)),
                    itemCount: refunds.length,
                    separatorBuilder: (_, __) => SizedBox(height: R.h(context, 8)),
                    itemBuilder: (_, i) => _TransactionCard(tx: refunds[i]),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 12), R.p(context, 16), R.p(context, 20)),
            child: SizedBox(
              width: double.infinity,
              height: R.h(context, 48),
              child: OutlinedButton.icon(
                icon: Icon(Icons.support_agent_rounded, size: R.w(context, 18)),
                label: const Text('Contact MedNU Support'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  side: const BorderSide(color: Color(0xFF1565C0)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(R.r(context, 12))),
                  textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                onPressed: () async {
                  final uri = Uri.parse(
                      'https://wa.me/919999999999?text=Hi%20MedNu%20Support%2C%20I%20have%20a%20query%20about%20my%20refund.');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ),
          ),
        ],
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
      padding: EdgeInsets.only(bottom: R.p(context, 16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: R.w(context, 36), height: R.h(context, 36),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(R.r(context, 10)),
            ),
            child: Icon(icon, color: AppColors.primary, size: R.w(context, 18)),
          ),
          SizedBox(width: R.w(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelLarge),
                SizedBox(height: R.h(context, 2)),
                Text(desc,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: context.appTextSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
