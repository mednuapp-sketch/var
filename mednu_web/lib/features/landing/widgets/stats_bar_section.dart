import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

class StatsBarSection extends StatelessWidget {
  const StatsBarSection({super.key});

  static const List<Map<String, dynamic>> _stats = [
    {
      'icon': Icons.shield_rounded,
      'title': 'Verified Doctors',
      'subtitle': '1000+ qualified & experienced doctors',
    },
    {
      'icon': Icons.lock_rounded,
      'title': 'Secure & Private',
      'subtitle': 'Your data is 100% safe and confidential',
    },
    {
      'icon': Icons.favorite_rounded,
      'title': 'Affordable Care',
      'subtitle': 'Quality healthcare that fits your budget',
    },
    {
      'icon': Icons.support_agent_rounded,
      'title': '24/7 Support',
      'subtitle': "We're here for you round the clock",
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: isMobile ? 28 : 40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: Responsive.maxContentWidth(context)),
          child: isMobile ? _MobileStats() : _DesktopStats(),
        ),
      ),
    );
  }
}

class _DesktopStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const stats = StatsBarSection._stats;
    return IntrinsicHeight(
      child: Row(
        children: [
          for (int i = 0; i < stats.length; i++) ...[
            Expanded(child: _StatPillar(stat: stats[i])),
            if (i < stats.length - 1)
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: const Color(0xFFF0F0F0),
              ),
          ],
        ],
      ),
    );
  }
}

class _MobileStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.55,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      children: StatsBarSection._stats
          .map((s) => _StatPillar(stat: s))
          .toList(),
    );
  }
}

class _StatPillar extends StatelessWidget {
  final Map<String, dynamic> stat;
  const _StatPillar({required this.stat});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 6 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: isMobile ? 40 : 52,
            height: isMobile ? 40 : 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              stat['icon'] as IconData,
              size: isMobile ? 20 : 26,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  stat['title'] as String,
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 12.5 : 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  stat['subtitle'] as String,
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 10.5 : 12,
                    color: const Color(0xFF9E9E9E),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
