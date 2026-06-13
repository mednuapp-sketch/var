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
import '../../auth/providers/auth_provider.dart';
import '../referral_provider.dart';
import '../referral_service.dart';

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync  = ref.watch(referralConfigProvider);
    final statsAsync   = ref.watch(referralStatsProvider);
    final historyAsync = ref.watch(referralHistoryProvider);
    final uid          = FirebaseAuth.instance.currentUser?.uid ?? '';
    // Read code from Firestore user doc so it always reflects the stored value
    final userDocAsync = ref.watch(userDocProvider(uid));
    final referralCode = userDocAsync.valueOrNull?['referralCode'] as String?
        ?? (uid.isNotEmpty ? uid.substring(0, 8).toUpperCase() : '—');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Hero header ─────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 260,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _HeroHeader(
                config: configAsync.valueOrNull ?? const ReferralConfig(),
                referralCode: referralCode,
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Stats row ──────────────────────────────
                _StatsRow(statsAsync: statsAsync),

                // ── Reward card ────────────────────────────
                _RewardCard(configAsync: configAsync),

                // ── Referral code card ─────────────────────
                _ReferralCodeCard(
                  referralCode: referralCode,
                  config: configAsync.valueOrNull ?? const ReferralConfig(),
                ),

                // ── How it works ───────────────────────────
                _HowItWorks(configAsync: configAsync),

                // ── History header ─────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.history_rounded,
                            size: 15, color: AppColors.accent),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Referral History',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                      const Spacer(),
                      historyAsync.maybeWhen(
                        data: (list) => list.isNotEmpty
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha:0.08),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text('${list.length} total',
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w600)),
                              )
                            : const SizedBox.shrink(),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),

                // ── History list ───────────────────────────
                historyAsync.when(
                  loading: () => Column(
                    children: List.generate(
                        3, (_) => const _ReferralShimmer()),
                  ),
                  error: (e, _) => _ErrorState(
                    onRetry: () => ref.invalidate(referralHistoryProvider),
                  ),
                  data: (list) => list.isEmpty
                      ? const _EmptyHistory()
                      : Column(
                          children: list
                              .map((r) => _ReferralCard(record: r))
                              .toList(),
                        ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),

      // ── Floating share CTA ─────────────────────────────
      bottomNavigationBar: _ShareBar(
        referralCode: referralCode,
        config: configAsync.valueOrNull ?? const ReferralConfig(),
      ),
    );
  }
}

// ── Hero Header ───────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  final ReferralConfig config;
  final String referralCode;
  const _HeroHeader({required this.config, required this.referralCode});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Stack(
        children: [
          Positioned(
            top: -50, right: -50,
            child: Container(
              width: 180, height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha:0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 0, left: -30,
            child: Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha:0.05),
              ),
            ),
          ),
          SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 56, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.card_giftcard_rounded,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 5),
                    Text('Referral Program',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                config.campaignTitle,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2),
              ),
              const SizedBox(height: 6),
              Text(
                config.campaignMessage,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Colors.white70),
              ),
              if (config.offerExpiryDate != null && !config.isExpired) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.timer_outlined,
                      color: Colors.amber, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Offer ends ${DateFormat('d MMM yyyy').format(config.offerExpiryDate!)}',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Colors.amber,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
              ],
            ],
          ),
        ),
          ),
        ],
      ),
    );
  }
}

// ── Stats Row ─────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final AsyncValue<Map<String, dynamic>> statsAsync;
  const _StatsRow({required this.statsAsync});

  @override
  Widget build(BuildContext context) {
    final stats = statsAsync.valueOrNull ??
        {'total': 0, 'rewarded': 0, 'pending': 0, 'earned': 0.0};
    final isLoading = statsAsync is AsyncLoading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
              child: _StatCard(
            label: 'Total Referrals',
            value: isLoading ? '—' : '${stats['total']}',
            icon: Icons.people_alt_rounded,
            color: AppColors.primary,
          )),
          const SizedBox(width: 10),
          Expanded(
              child: _StatCard(
            label: 'Successful',
            value: isLoading ? '—' : '${stats['rewarded']}',
            icon: Icons.check_circle_rounded,
            color: AppColors.success,
          )),
          const SizedBox(width: 10),
          Expanded(
              child: _StatCard(
            label: 'Total Earned',
            value: isLoading
                ? '—'
                : '₹${NumberFormat('#,##0').format(stats['earned'])}',
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.accent,
          )),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha:0.03),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Reward Card ───────────────────────────────────────────
class _RewardCard extends StatelessWidget {
  final AsyncValue<ReferralConfig> configAsync;
  const _RewardCard({required this.configAsync});

  @override
  Widget build(BuildContext context) {
    final config = configAsync.valueOrNull ?? const ReferralConfig();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha:0.08),
              AppColors.secondary.withValues(alpha:0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha:0.15)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You Earn', style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary)),
                  Text(config.referrerRewardFormatted,
                      style: AppTextStyles.display
                          .copyWith(color: AppColors.primary)),
                  const SizedBox(height: 2),
                  Text('per successful referral',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            Container(
              width: 1, height: 60,
              color: AppColors.primary.withValues(alpha:0.15),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Friend Gets', style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
                    Text(config.referredRewardFormatted,
                        style: AppTextStyles.display
                            .copyWith(color: AppColors.accent)),
                    const SizedBox(height: 2),
                    Text('on joining MedNU',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Referral Code Card ─────────────────────────────────────
class _ReferralCodeCard extends StatelessWidget {
  final String referralCode;
  final ReferralConfig config;
  const _ReferralCodeCard(
      {required this.referralCode, required this.config});

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: referralCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Referral code copied!'),
        backgroundColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _share() {
    Share.share(
      'Join MedNU — India\'s smarter healthcare app! Use my referral code $referralCode '
      'to get ${config.referredRewardFormatted} in your wallet when you sign up. '
      'Download now: https://mednu.in',
      subject: 'Join MedNU with my referral code',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha:0.03),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your Referral Code', style: AppTextStyles.labelLarge),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha:0.25),
                          width: 1.5),
                    ),
                    child: Text(
                      referralCode,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: 4),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _CodeButton(
                  icon: Icons.copy_rounded,
                  label: 'Copy',
                  color: AppColors.primary,
                  onTap: () => _copyCode(context),
                ),
                const SizedBox(width: 8),
                _CodeButton(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  color: AppColors.secondary,
                  onTap: _share,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _CodeButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha:0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(label,
                  style: AppTextStyles.labelSmall.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── How It Works ──────────────────────────────────────────
class _HowItWorks extends StatelessWidget {
  final AsyncValue<ReferralConfig> configAsync;
  const _HowItWorks({required this.configAsync});

  @override
  Widget build(BuildContext context) {
    final config = configAsync.valueOrNull ?? const ReferralConfig();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.info_outline_rounded,
                  size: 15, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            const Text(
              'How It Works',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ]),
          const SizedBox(height: 14),
          _Step(
            number: '1',
            title: 'Share Your Code',
            desc: 'Send your referral code to friends and family.',
            icon: Icons.share_rounded,
            color: AppColors.primary,
          ),
          _Step(
            number: '2',
            title: 'Friend Signs Up',
            desc:
                'Your friend downloads MedNU and enters your code during registration.',
            icon: Icons.person_add_rounded,
            color: AppColors.secondary,
          ),
          _Step(
            number: '3',
            title: 'Both Earn Rewards',
            desc:
                'You get ${config.referrerRewardFormatted} and your friend gets ${config.referredRewardFormatted} — instantly credited to your wallets.',
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.accent,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number, title, desc;
  final IconData icon;
  final Color color;
  final bool isLast;
  const _Step({
    required this.number,
    required this.title,
    required this.desc,
    required this.icon,
    required this.color,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            if (!isLast)
              Container(
                width: 2, height: 36,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha:0.3), color.withValues(alpha:0.05)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelLarge),
                const SizedBox(height: 3),
                Text(desc,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
                SizedBox(height: isLast ? 0 : 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Referral History Card ─────────────────────────────────
class _ReferralCard extends StatelessWidget {
  final ReferralRecord record;
  const _ReferralCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final isRewarded = record.isRewarded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha:0.03),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: (isRewarded ? AppColors.success : AppColors.warning)
                  .withValues(alpha:0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isRewarded
                  ? Icons.check_circle_rounded
                  : Icons.schedule_rounded,
              color: isRewarded ? AppColors.success : AppColors.warning,
              size: 22,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'Referral #${record.id.substring(0, 6).toUpperCase()}',
                  style: AppTextStyles.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isRewarded ? AppColors.success : AppColors.warning)
                      .withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isRewarded ? 'Rewarded' : 'Pending',
                  style: AppTextStyles.labelSmall.copyWith(
                      color: isRewarded
                          ? AppColors.success
                          : AppColors.warning),
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 3),
              Text(
                DateFormat('d MMM yyyy').format(record.createdAt),
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              if (isRewarded)
                Text(
                  '+₹${record.referrerRewardAmount.toStringAsFixed(0)} credited to wallet',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.success),
                )
              else
                Text(
                  'Reward on ${record.triggerCondition.replaceAll('_', ' ')}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.warning),
                ),
            ],
          ),
          isThreeLine: true,
        ),
      ),
    );
  }
}

// ── Empty / Error / Shimmer ───────────────────────────────
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 32),
      child: Column(
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.people_alt_outlined,
                size: 34, color: AppColors.primary.withValues(alpha:0.5)),
          ),
          const SizedBox(height: 14),
          Text('No Referrals Yet',
              style:
                  AppTextStyles.h4.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text(
            'Share your code and start earning\nwhen friends join MedNU.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textHint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 32),
      child: Column(
        children: [
          Icon(Icons.wifi_off_rounded,
              size: 48, color: AppColors.error.withValues(alpha:0.5)),
          const SizedBox(height: 12),
          Text('Couldn\'t load history',
              style:
                  AppTextStyles.h4.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
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

class _ReferralShimmer extends StatelessWidget {
  const _ReferralShimmer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Shimmer.fromColors(
        baseColor: const Color(0xFFEEEEEE),
        highlightColor: const Color(0xFFFAFAFA),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ── Bottom Share Bar ──────────────────────────────────────
class _ShareBar extends StatelessWidget {
  final String referralCode;
  final ReferralConfig config;
  const _ShareBar({required this.referralCode, required this.config});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha:0.05),
              blurRadius: 12,
              offset: const Offset(0, -4))
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha:0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: () {
              Share.share(
                'Join MedNU — India\'s smarter healthcare app! Use my referral code $referralCode '
                'to get ${config.referredRewardFormatted} in your wallet when you sign up. '
                'Download now: https://mednu.in',
                subject: 'Join MedNU with my referral code',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.share_rounded, size: 20),
            label: Text('Share Code & Earn ${config.referrerRewardFormatted}'),
          ),
        ),
      ),
    );
  }
}
