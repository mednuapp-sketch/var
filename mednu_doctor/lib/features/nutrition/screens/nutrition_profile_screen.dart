import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../providers/nutrition_providers.dart';

/// Nutritionist identity — read-only, sourced from the admin-curated
/// `nutritionists/{uid}` catalogue entry the patient app's "choose a
/// nutritionist" screen also reads. Unlike every other partner module,
/// there is no self-onboarding/edit flow here: a nutritionist account is
/// fully provisioned by an admin (role grant + catalogue entry together),
/// so opening a write path here would let a partner edit the very catalogue
/// listing patients choose from with no review step. See the Phase A scope
/// note in firestore.rules for the full reasoning.
class NutritionProfileScreen extends ConsumerWidget {
  const NutritionProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(nutritionistCatalogueDocProvider).valueOrNull ?? const {};
    final name = profile['name'] as String? ?? 'Nutritionist';
    final specialization = profile['specialization'] as String? ?? '';
    final rating = ((profile['rating'] as num?) ?? 0).toDouble();
    final experienceYears = ((profile['experienceYears'] as num?) ?? 0).toInt();
    final bio = profile['bio'] as String? ?? '';

    return SharedAppShell(
      currentRoute: AppRoutes.nutritionProfile,
      title: 'Nutritionist Profile',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Column(
              children: [
                SharedProfileAvatar(name: name, size: 76, isVerified: true),
                const SizedBox(height: 14),
                Text(name, style: const TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                if (specialization.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(specialization, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _HeroStat(label: 'Rating', value: rating.toStringAsFixed(1), icon: Icons.star_rounded),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Experience', value: '$experienceYears yrs', icon: Icons.workspace_premium_outlined),
                  ],
                ),
              ],
            ),
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 16),
            PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('About', style: AppTextStyles.labelMedium),
                  const SizedBox(height: 10),
                  Text(bio, style: AppTextStyles.bodyMedium),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          const PremiumCard(
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your public profile is managed by the MedNu team. Contact support to update these details.',
                    style: AppTextStyles.bodySmall,
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

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _HeroStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.amberAccent, size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Colors.white60)),
      ],
    );
  }
}
