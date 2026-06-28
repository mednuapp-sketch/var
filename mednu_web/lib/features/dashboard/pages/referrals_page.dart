import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

class ReferralsPage extends StatelessWidget {
  const ReferralsPage({super.key});

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _userStream {
    if (_uid.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance.collection('users').doc(_uid).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _referralsStream {
    if (_uid.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('referrals')
        .where('referrerId', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Referrals',
            style: GoogleFonts.poppins(
                fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text('Invite friends and earn rewards',
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        _uid.isEmpty
            ? _emptyState()
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _userStream,
                builder: (context, userSnap) {
                  final userData = userSnap.data?.data() ?? {};
                  final referralCode =
                      userData['referralCode'] as String? ?? '—';
                  final referralPoints =
                      (userData['referralPoints'] as num?)?.toInt() ?? 0;

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _referralsStream,
                    builder: (context, refSnap) {
                      final docs = refSnap.data?.docs ?? [];
                      int total = docs.length;
                      int rewarded = 0;
                      double earned = 0.0;
                      for (final doc in docs) {
                        final d = doc.data();
                        if (d['status'] == 'rewarded') {
                          rewarded++;
                          earned +=
                              (d['referrerRewardAmount'] as num?)?.toDouble() ??
                                  0.0;
                        }
                      }

                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ReferralCard(code: referralCode),
                            const SizedBox(height: 20),
                            isMobile
                                ? Column(children: [
                                    _StatCard(
                                        value: '$total',
                                        label: 'Total Referrals',
                                        emoji: '👥'),
                                    const SizedBox(height: 12),
                                    _StatCard(
                                        value: '₹${earned.toStringAsFixed(0)}',
                                        label: 'Total Earned',
                                        emoji: '💰'),
                                    const SizedBox(height: 12),
                                    _StatCard(
                                        value: '$rewarded',
                                        label: 'Successful',
                                        emoji: '✅'),
                                    const SizedBox(height: 12),
                                    _StatCard(
                                        value: '$referralPoints',
                                        label: 'Reward Points',
                                        emoji: '⭐'),
                                  ])
                                : Row(children: [
                                    Expanded(
                                        child: _StatCard(
                                            value: '$total',
                                            label: 'Total Referrals',
                                            emoji: '👥')),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        child: _StatCard(
                                            value:
                                                '₹${earned.toStringAsFixed(0)}',
                                            label: 'Total Earned',
                                            emoji: '💰')),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        child: _StatCard(
                                            value: '$rewarded',
                                            label: 'Successful',
                                            emoji: '✅')),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        child: _StatCard(
                                            value: '$referralPoints',
                                            label: 'Reward Points',
                                            emoji: '⭐')),
                                  ]),
                            const SizedBox(height: 24),
                            _ReferralHistoryList(docs: docs),
                          ]);
                    },
                  );
                },
              ),
      ]),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🎁', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text('Sign in to view referrals',
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ]),
      ),
    );
  }
}

class _ReferralCard extends StatelessWidget {
  final String code;
  const _ReferralCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your Referral Code',
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 8),
              Text(code,
                  style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 3)),
            ]),
          ),
          const Text('🎁', style: TextStyle(fontSize: 48)),
        ]),
        const SizedBox(height: 12),
        Text(
          'Share your code and earn rewards for every friend who joins MedNu!',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70, height: 1.5),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: code == '—'
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Referral code copied!',
                              style: GoogleFonts.poppins(fontSize: 13)),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.copy_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text('Copy Code',
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: code == '—'
                  ? null
                  : () {
                      Clipboard.setData(
                          ClipboardData(text: 'Join MedNu with my referral code: $code'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Share link copied!',
                              style: GoogleFonts.poppins(fontSize: 13)),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.share_rounded, color: AppColors.primary, size: 16),
                    const SizedBox(width: 8),
                    Text('Share Link',
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final String emoji;
  const _StatCard({required this.value, required this.label, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          Text(label,
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
        ]),
      ]),
    );
  }
}

class _ReferralHistoryList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _ReferralHistoryList({required this.docs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Text('Referral History',
                style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ]),
        ),
        const Divider(height: 1),
        if (docs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text('No referrals yet. Share your code to get started!',
                  style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            ),
          )
        else
          ...docs.asMap().entries.map((entry) {
            final i = entry.key;
            final d = entry.value.data();
            return Column(children: [
              _HistoryRow(data: d),
              if (i < docs.length - 1) const Divider(height: 1, indent: 68),
            ]);
          }),
      ]),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _HistoryRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'pending';
    final isRewarded = status == 'rewarded';
    final earned = (data['referrerRewardAmount'] as num?)?.toDouble() ?? 0.0;
    final earnedStr = isRewarded ? '+₹${earned.toStringAsFixed(0)}' : '₹0';
    final createdAt = data['createdAt'];
    final dateStr =
        createdAt is Timestamp ? _formatTs(createdAt) : '';
    final referralCode = data['referralCode'] as String? ?? '';
    // Show initials from referral code as avatar placeholder
    final avatar = referralCode.length >= 2 ? referralCode.substring(0, 2) : '??';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
          child: Center(
            child: Text(avatar,
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Referral • $referralCode',
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text(dateStr,
                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: (isRewarded ? AppColors.success : AppColors.warning).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isRewarded ? 'Rewarded' : 'Pending',
              style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isRewarded ? AppColors.success : AppColors.warning),
            ),
          ),
          const SizedBox(height: 4),
          Text(earnedStr,
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isRewarded ? AppColors.success : AppColors.textHint)),
        ]),
      ]),
    );
  }
}

String _formatTs(Timestamp ts) {
  final d = ts.toDate();
  const months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${months[d.month]} ${d.year}';
}
