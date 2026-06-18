import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
class ReferralsPage extends StatelessWidget {
  const ReferralsPage({super.key});

  static const _referralHistory = [
    {'name': 'Rahul Verma', 'date': 'Jun 5, 2026', 'status': 'Joined', 'earned': '₹100', 'avatar': 'RV'},
    {'name': 'Priya Singh', 'date': 'May 20, 2026', 'status': 'Joined', 'earned': '₹100', 'avatar': 'PS'},
    {'name': 'Anil Kumar', 'date': 'May 10, 2026', 'status': 'Joined', 'earned': '₹100', 'avatar': 'AK'},
    {'name': 'Sunita Devi', 'date': 'Apr 28, 2026', 'status': 'Pending', 'earned': '₹0', 'avatar': 'SD'},
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Referrals', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text('Invite friends and earn rewards', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        _ReferralCard(),
        const SizedBox(height: 20),
        isMobile
            ? Column(children: [_StatCard(value: '4', label: 'Total Referrals', emoji: '👥'),
                const SizedBox(height: 12),
                _StatCard(value: '₹300', label: 'Total Earned', emoji: '💰'),
                const SizedBox(height: 12),
                _StatCard(value: '3', label: 'Successful', emoji: '✅'),
              ])
            : Row(children: [
                Expanded(child: _StatCard(value: '4', label: 'Total Referrals', emoji: '👥')),
                const SizedBox(width: 16),
                Expanded(child: _StatCard(value: '₹300', label: 'Total Earned', emoji: '💰')),
                const SizedBox(width: 16),
                Expanded(child: _StatCard(value: '3', label: 'Successful', emoji: '✅')),
              ]),
        const SizedBox(height: 24),
        _ReferralHistoryList(history: _referralHistory),
      ]),
    );
  }
}

class _ReferralCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your Referral Code', style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 8),
            Text('MEDNU2026', style: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 4)),
          ])),
          const Text('🎁', style: TextStyle(fontSize: 48)),
        ]),
        const SizedBox(height: 16),
        Text(
          'Share your code and earn ₹100 for every friend who joins MedNu!',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70, height: 1.5),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.copy_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text('Copy Code', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {},
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
                    Text('Share Link', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          Text(label, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
        ]),
      ]),
    );
  }
}

class _ReferralHistoryList extends StatelessWidget {
  final List<Map<String, String>> history;
  const _ReferralHistoryList({required this.history});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Text('Referral History', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ]),
        ),
        const Divider(height: 1),
        ...history.asMap().entries.map((entry) => Column(children: [
          _HistoryRow(item: entry.value),
          if (entry.key < history.length - 1) const Divider(height: 1, indent: 68),
        ])),
      ]),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Map<String, String> item;
  const _HistoryRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final joined = item['status'] == 'Joined';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
          child: Center(child: Text(item['avatar']!, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item['name']!, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          Text(item['date']!, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: (joined ? AppColors.success : AppColors.warning).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(item['status']!, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: joined ? AppColors.success : AppColors.warning)),
          ),
          const SizedBox(height: 4),
          Text(item['earned']!, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: joined ? AppColors.success : AppColors.textHint)),
        ]),
      ]),
    );
  }
}
