import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../auth/providers/auth_provider.dart';
import '../referral_provider.dart';
import '../referral_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ReferralScreen
// ─────────────────────────────────────────────────────────────────────────────

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync  = ref.watch(referralConfigProvider);
    final statsAsync   = ref.watch(referralStatsProvider);
    final historyAsync = ref.watch(referralHistoryProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final userDocAsync = ref.watch(userDocProvider(uid));
    final referralCode = userDocAsync.valueOrNull?['referralCode'] as String? ??
        (uid.isNotEmpty ? uid.substring(0, 8).toUpperCase() : '—');
    final config      = configAsync.valueOrNull ?? const ReferralConfig();
    final referralLink = 'https://mednu.in/join?ref=$referralCode';

    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Gradient hero app bar ──────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: R.h(context, 190),
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: Colors.white.withValues(alpha: 0.15),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => context.pop(),
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _HeroHeader(
                  config: config, referralCode: referralCode),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Earnings summary row ──────────────────────────
                _EarningsSummary(statsAsync: statsAsync),

                // ── Reward banner ─────────────────────────────────
                _RewardBanner(config: config),

                // ── Code + QR card ────────────────────────────────
                _CodeAndQRCard(
                  referralCode: referralCode,
                  referralLink: referralLink,
                  config: config,
                ),

                // ── Social share row ──────────────────────────────
                _SocialShareRow(
                    referralCode: referralCode,
                    referralLink: referralLink,
                    config: config),

                // ── How it works ──────────────────────────────────
                _HowItWorks(config: config),

                // ── Milestone progress ────────────────────────────
                _MilestoneSection(statsAsync: statsAsync),

                // ── History header ────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.history_rounded,
                            size: 15, color: AppColors.accent),
                      ),
                      const SizedBox(width: 8),
                      Text('Referral History',
                          style: AppTextStyles.h4
                              .copyWith(color: AppColors.accent)),
                      const Spacer(),
                      historyAsync.maybeWhen(
                        data: (list) => list.isNotEmpty
                            ? _CountChip(
                                label: '${list.length} total',
                                color: AppColors.accent)
                            : const SizedBox.shrink(),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),

                // ── History list ──────────────────────────────────
                historyAsync.when(
                  loading: () => Column(
                    children: List.generate(
                        3, (_) => const _ReferralShimmer()),
                  ),
                  error: (e, _) => _ErrorState(
                    onRetry: () =>
                        ref.invalidate(referralHistoryProvider),
                  ),
                  data: (list) => list.isEmpty
                      ? const _EmptyHistory()
                      : Column(
                          children: list
                              .map((r) => _ReferralCard(record: r))
                              .toList(),
                        ),
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ],
      ),

      // ── Floating share bar ────────────────────────────────────
      bottomNavigationBar: _ShareBar(
        referralCode: referralCode,
        referralLink: referralLink,
        config: config,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hero Header
// ─────────────────────────────────────────────────────────────────────────────

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
            top: -40, right: -40,
            child: Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 0, left: -20,
            child: Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            top: 60, right: 20,
            child: _ConfettiDots(),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
              padding: EdgeInsets.fromLTRB(
                  R.p(context, 20), R.p(context, 48), R.p(context, 20), R.p(context, 16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.card_giftcard_rounded,
                            color: Colors.white, size: 13),
                        SizedBox(width: 5),
                        Text('Referral Program',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            )),
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
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    config.campaignMessage,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                  if (config.offerExpiryDate != null &&
                      !config.isExpired) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined,
                            color: Colors.amber, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Offer ends ${DateFormat('d MMM yyyy').format(config.offerExpiryDate!)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Colors.amber,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
                    ),
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

/// Decorative confetti dots — simple colored circles, no package needed.
class _ConfettiDots extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          const _Dot(color: Colors.amber, size: 8),
          const SizedBox(width: 10),
          const _Dot(color: Colors.white38, size: 5),
          const SizedBox(width: 14),
          _Dot(color: Colors.pinkAccent.shade100, size: 7),
        ]),
        const SizedBox(height: 8),
        const Row(children: [
          _Dot(color: Colors.white24, size: 5),
          SizedBox(width: 18),
          _Dot(color: Colors.amber, size: 6),
          SizedBox(width: 8),
          _Dot(color: Colors.white38, size: 8),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const SizedBox(width: 8),
          _Dot(color: Colors.pinkAccent.shade100, size: 5),
          const SizedBox(width: 12),
          const _Dot(color: Colors.amber, size: 7),
        ]),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final double size;
  const _Dot({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Earnings Summary Row (Total Earned / Pending / This Month)
// ─────────────────────────────────────────────────────────────────────────────

class _EarningsSummary extends StatelessWidget {
  final AsyncValue<Map<String, dynamic>> statsAsync;
  const _EarningsSummary({required this.statsAsync});

  @override
  Widget build(BuildContext context) {
    final stats = statsAsync.valueOrNull ??
        {'total': 0, 'rewarded': 0, 'pending': 0, 'earned': 0.0, 'thisMonth': 0.0};
    final isLoading = statsAsync is AsyncLoading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'Total Earned',
              value: isLoading
                  ? '—'
                  : '₹${NumberFormat('#,##0').format(stats['earned'] ?? 0)}',
              icon: Icons.account_balance_wallet_rounded,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: 'Pending',
              value: isLoading
                  ? '—'
                  : '${stats['pending'] ?? 0}',
              icon: Icons.schedule_rounded,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: 'This Month',
              value: isLoading
                  ? '—'
                  : '₹${NumberFormat('#,##0').format(stats['thisMonth'] ?? 0)}',
              icon: Icons.calendar_month_rounded,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: AppTextStyles.h3.copyWith(color: context.appTextPrimary)),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.bodySmall
                .copyWith(color: context.appTextSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reward Banner
// ─────────────────────────────────────────────────────────────────────────────

class _RewardBanner extends StatelessWidget {
  final ReferralConfig config;
  const _RewardBanner({required this.config});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.08),
              AppColors.secondary.withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You Earn',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: context.appTextSecondary)),
                  Text(config.referrerRewardFormatted,
                      style: AppTextStyles.display
                          .copyWith(color: AppColors.primary)),
                  const SizedBox(height: 2),
                  Text('per successful referral',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: context.appTextSecondary)),
                ],
              ),
            ),
            Container(
                width: 1, height: 60,
                color: AppColors.primary.withValues(alpha: 0.15)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Friend Gets',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: context.appTextSecondary)),
                    Text(config.referredRewardFormatted,
                        style: AppTextStyles.display
                            .copyWith(color: AppColors.accent)),
                    const SizedBox(height: 2),
                    Text('on joining MedNU',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: context.appTextSecondary)),
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

// ─────────────────────────────────────────────────────────────────────────────
//  Code + QR Card
// ─────────────────────────────────────────────────────────────────────────────

class _CodeAndQRCard extends StatelessWidget {
  final String referralCode, referralLink;
  final ReferralConfig config;
  const _CodeAndQRCard({
    required this.referralCode,
    required this.referralLink,
    required this.config,
  });

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: referralCode));
    _snack(context, 'Referral code copied!');
  }

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: referralLink));
    _snack(context, 'Referral link copied!');
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
      backgroundColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your Referral Code', style: AppTextStyles.h4),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: code + buttons
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Code display box
                      GestureDetector(
                        onTap: () => _copyCode(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: context.appBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.primary
                                  .withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                referralCode,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                  letterSpacing: 5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text('Tap to copy',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 10,
                                    color: context.appTextHint,
                                  )),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.copy_rounded,
                              label: 'Copy Code',
                              color: AppColors.primary,
                              onTap: () => _copyCode(context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.link_rounded,
                              label: 'Copy Link',
                              color: AppColors.secondary,
                              onTap: () => _copyLink(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Right: QR code
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: referralLink,
                        version: QrVersions.auto,
                        size: 100,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppColors.primary,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Scan QR',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          color: context.appTextHint,
                        )),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Social Share Row (WhatsApp / Telegram / SMS / Copy Link)
// ─────────────────────────────────────────────────────────────────────────────

class _SocialShareRow extends StatelessWidget {
  final String referralCode, referralLink;
  final ReferralConfig config;
  const _SocialShareRow({
    required this.referralCode,
    required this.referralLink,
    required this.config,
  });

  String get _shareText =>
      'Join MedNU — India\'s smarter healthcare app! 🏥\n'
      'Use my referral code *$referralCode* to get '
      '${config.referredRewardFormatted} when you sign up.\n'
      'Download: $referralLink';

  void _share() => Share.share(_shareText,
      subject: 'Join MedNU with my referral code');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share via', style: AppTextStyles.labelLarge),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SocialBtn(
                  label: 'WhatsApp',
                  icon: Icons.chat_rounded,
                  color: const Color(0xFF25D366),
                  onTap: _share,
                ),
                _SocialBtn(
                  label: 'Telegram',
                  icon: Icons.send_rounded,
                  color: const Color(0xFF229ED9),
                  onTap: _share,
                ),
                _SocialBtn(
                  label: 'SMS',
                  icon: Icons.sms_rounded,
                  color: const Color(0xFF1565C0),
                  onTap: _share,
                ),
                _SocialBtn(
                  label: 'More',
                  icon: Icons.share_rounded,
                  color: AppColors.primary,
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

class _SocialBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SocialBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                  color: color.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: context.appTextSecondary,
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  How It Works
// ─────────────────────────────────────────────────────────────────────────────

class _HowItWorks extends StatelessWidget {
  final ReferralConfig config;
  const _HowItWorks({required this.config});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.info_outline_rounded,
                    size: 15, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
              Text('How It Works',
                  style: AppTextStyles.h4
                      .copyWith(color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 14),
          const _StepRow(
            number: '1',
            title: 'Share Your Code',
            desc: 'Send your referral code or QR to friends and family.',
            icon: Icons.share_rounded,
            color: AppColors.primary,
          ),
          const _StepRow(
            number: '2',
            title: 'Friend Signs Up',
            desc:
                'Your friend downloads MedNU and enters your code at registration.',
            icon: Icons.person_add_rounded,
            color: AppColors.secondary,
          ),
          _StepRow(
            number: '3',
            title: 'Both Earn Rewards',
            desc:
                'You get ${config.referrerRewardFormatted} and your friend gets '
                '${config.referredRewardFormatted} — instantly in your wallets.',
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.accent,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String number, title, desc;
  final IconData icon;
  final Color color;
  final bool isLast;
  const _StepRow({
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
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: color.withValues(alpha: 0.25), width: 2),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            if (!isLast)
              Container(
                width: 2, height: 38,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.3),
                      color.withValues(alpha: 0.05),
                    ],
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
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelLarge),
                const SizedBox(height: 3),
                Text(desc,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: context.appTextSecondary)),
                SizedBox(height: isLast ? 0 : 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Milestone Progress Section
// ─────────────────────────────────────────────────────────────────────────────

class _MilestoneSection extends StatelessWidget {
  final AsyncValue<Map<String, dynamic>> statsAsync;
  const _MilestoneSection({required this.statsAsync});

  static const _milestones = [5, 10, 25, 50];

  @override
  Widget build(BuildContext context) {
    final stats = statsAsync.valueOrNull ?? {'rewarded': 0};
    final rewarded   = stats['rewarded'] as int? ?? 0;
    int nextMilestone = _milestones.firstWhere(
      (m) => m > rewarded,
      orElse: () => _milestones.last,
    );
    final progress  = (rewarded / nextMilestone).clamp(0.0, 1.0);
    final remaining = (nextMilestone - rewarded).clamp(0, nextMilestone);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accent.withValues(alpha: 0.08),
              AppColors.accent.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.emoji_events_rounded,
                      color: AppColors.accent, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Milestone Progress',
                          style: AppTextStyles.labelLarge.copyWith(
                              color: context.appTextPrimary)),
                      Text(
                        rewarded >= nextMilestone
                            ? 'Milestone reached! Keep going'
                            : '$remaining more referrals to reach $nextMilestone',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: context.appTextSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$rewarded / $nextMilestone',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      )),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor:
                    AppColors.accent.withValues(alpha: 0.15),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _milestones.map((m) {
                final reached = rewarded >= m;
                return Column(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: reached
                            ? AppColors.accent
                            : AppColors.accent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: reached
                              ? AppColors.accent
                              : AppColors.accent.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        reached
                            ? Icons.check_rounded
                            : Icons.emoji_events_rounded,
                        color: reached
                            ? Colors.white
                            : AppColors.accent.withValues(alpha: 0.5),
                        size: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('$m',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: reached
                              ? AppColors.accent
                              : context.appTextHint,
                        )),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Referral Card (history item)
// ─────────────────────────────────────────────────────────────────────────────

class _ReferralCard extends StatelessWidget {
  final ReferralRecord record;
  const _ReferralCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final isRewarded  = record.isRewarded;
    final statusColor = isRewarded ? AppColors.success : AppColors.warning;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isRewarded
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Referral #${record.id.substring(0, 6).toUpperCase()}',
                            style: AppTextStyles.labelLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isRewarded ? 'Rewarded' : 'Pending',
                            style: AppTextStyles.labelSmall
                                .copyWith(color: statusColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('d MMM yyyy').format(record.createdAt),
                      style: AppTextStyles.bodySmall
                          .copyWith(color: context.appTextSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isRewarded
                          ? '+₹${record.referrerRewardAmount.toStringAsFixed(0)} credited to wallet'
                          : 'Reward on ${record.triggerCondition.replaceAll('_', ' ')}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isRewarded
                            ? AppColors.success
                            : AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Empty / Error / Shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.people_alt_outlined,
                  size: 36,
                  color: AppColors.primary.withValues(alpha: 0.45)),
            ),
            const SizedBox(height: 16),
            Text('No Referrals Yet',
                style: AppTextStyles.h4
                    .copyWith(color: context.appTextSecondary)),
            const SizedBox(height: 8),
            Text(
              'Share your code and start earning\nwhen friends join MedNU.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: context.appTextHint,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
              size: 48, color: AppColors.error.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('Couldn\'t load history',
              style:
                  AppTextStyles.h4.copyWith(color: context.appTextSecondary)),
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
      child: AppShimmer(
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Count chip helper
// ─────────────────────────────────────────────────────────────────────────────

class _CountChip extends StatelessWidget {
  final String label;
  final Color color;
  const _CountChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: AppTextStyles.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bottom Share Bar
// ─────────────────────────────────────────────────────────────────────────────

class _ShareBar extends StatelessWidget {
  final String referralCode, referralLink;
  final ReferralConfig config;
  const _ShareBar({
    required this.referralCode,
    required this.referralLink,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      decoration: BoxDecoration(
        color: context.appSurface,
        border: Border(top: BorderSide(color: context.appDivider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: () {
              Share.share(
                'Join MedNU — India\'s smarter healthcare app!\n'
                'Use my referral code $referralCode to get '
                '${config.referredRewardFormatted} in your wallet.\n'
                'Download now: $referralLink',
                subject: 'Join MedNU with my referral code',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.share_rounded, size: 20),
            label: Text(
              'Share & Earn ${config.referrerRewardFormatted}',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
