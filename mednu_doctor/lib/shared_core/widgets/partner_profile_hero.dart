import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// One stat shown in the hero's bottom row (icon, value, label).
class PartnerHeroStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const PartnerHeroStat({super.key, required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primaryLight, size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Colors.white60)),
      ],
    );
  }
}

/// Gradient header card shared by every partner role's profile screen:
/// tap-to-change avatar, name, a one-line subtitle and an optional stat row.
/// Role-specific content goes in the cards below it.
class PartnerProfileHero extends StatelessWidget {
  final Widget avatar;
  final String name;
  final String? subtitle;
  final List<PartnerHeroStat> stats;

  const PartnerProfileHero({
    super.key,
    required this.avatar,
    required this.name,
    this.subtitle,
    this.stats = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary, AppColors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          avatar,
          const SizedBox(height: 14),
          Text(
            name.isEmpty ? '—' : name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70),
            ),
          ],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) Container(width: 1, height: 30, color: Colors.white24),
                  stats[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
