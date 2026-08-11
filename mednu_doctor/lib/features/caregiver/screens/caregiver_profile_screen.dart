import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../../core/services/feedback_service.dart';
import '../models/caregiver_profile.dart';
import '../providers/caregiver_providers.dart';
import '../services/caregiver_profile_service.dart';

/// Caregiver identity — a hero avatar/rating card plus certification and
/// specialty chips, mirroring the Ambulance module's Vehicle Profile shape
/// (hero + fact cards + chip groups) applied to a person instead of a
/// vehicle.
///
/// This screen is also the module's only profile *write* path: creating
/// `caregiver_profiles/{uid}` here is what makes `firestore.rules`'
/// `isCaregiverPartner()` start returning true, i.e. what lets this account
/// see unclaimed visits at all. There is no separate onboarding screen for
/// this role, so the edit action lives on the screen that already displays
/// exactly these fields.
class CaregiverProfileScreen extends ConsumerWidget {
  const CaregiverProfileScreen({super.key});

  Future<void> _edit(BuildContext context, CaregiverProfile current) async {
    final uid = CaregiverProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }

    final name = TextEditingController(
        text: current.name == 'Complete your profile' ? '' : current.name);
    final certifications = TextEditingController(text: current.certifications.join(', '));
    final specialties = TextEditingController(text: current.specialties.join(', '));
    final hourlyRate =
        TextEditingController(text: current.hourlyRate == 0 ? '' : '${current.hourlyRate}');
    final experienceYears = TextEditingController(
        text: current.experienceYears == 0 ? '' : '${current.experienceYears}');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Caregiver Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
              TextField(
                controller: certifications,
                decoration: const InputDecoration(
                  labelText: 'Certifications',
                  hintText: 'Comma separated',
                ),
              ),
              TextField(
                controller: specialties,
                decoration: const InputDecoration(
                  labelText: 'Specialties',
                  hintText: 'Comma separated',
                ),
              ),
              TextField(
                controller: hourlyRate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Hourly rate (₹)'),
              ),
              TextField(
                controller: experienceYears,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Years of experience'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;

    List<String> split(TextEditingController c) =>
        c.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final rate = num.tryParse(hourlyRate.text.trim()) ?? 0;
    final years = int.tryParse(experienceYears.text.trim()) ?? 0;

    try {
      final exists = await CaregiverProfileService.profileExists(uid);
      if (exists) {
        // A self-update can't touch status/isVerified/rating/totalVisits —
        // firestore.rules rejects those keys, so they're deliberately absent.
        await CaregiverProfileService.updateProfile(uid, {
          'name': name.text.trim(),
          'certifications': split(certifications),
          'specialties': split(specialties),
          'hourlyRate': rate,
          'experienceYears': years,
        });
      } else {
        await CaregiverProfileService.createProfile(
          uid: uid,
          name: name.text.trim(),
          certifications: split(certifications),
          specialties: split(specialties),
          hourlyRate: rate,
          experienceYears: years,
        );
      }
      if (context.mounted) FeedbackService.showSuccess(context, 'Profile saved');
    } catch (_) {
      if (context.mounted) {
        FeedbackService.showError(context, "Couldn't save your profile. Please try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(caregiverProfileProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.caregiverProfile,
      title: 'Caregiver Profile',
      extraActions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
          onPressed: () => _edit(context, profile),
          tooltip: 'Edit profile',
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
          onPressed: () => context.push(AppRoutes.caregiverSettings),
          tooltip: 'Settings',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF00695C), Color(0xFF004D40)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Column(
              children: [
                SharedProfileAvatar(name: profile.name, size: 76, isVerified: profile.documentsVerified),
                const SizedBox(height: 14),
                Text(profile.name, style: const TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                Text('${profile.experienceYears} years of experience', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _HeroStat(label: 'Rating', value: profile.rating.toStringAsFixed(1), icon: Icons.star_rounded),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Visits', value: '${profile.totalVisits}', icon: Icons.event_note_rounded),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Rate/hr', value: '₹${profile.hourlyRate}', icon: Icons.currency_rupee_rounded),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Certifications', style: AppTextStyles.labelMedium),
                    const Spacer(),
                    if (profile.documentsVerified) const StatusBadge(label: 'Verified', color: AppColors.success, icon: Icons.verified_rounded),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: profile.certifications
                      .map((c) => InfoChip(icon: Icons.workspace_premium_outlined, label: c, color: AppColors.secondary))
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Specialties', style: AppTextStyles.labelMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: profile.specialties
                      .map((s) => InfoChip(icon: Icons.favorite_border_rounded, label: s, color: AppColors.accent))
                      .toList(),
                ),
              ],
            ),
          ),
          if (CaregiverProfileService.currentUid != null) ...[
            const SizedBox(height: 16),
            PartnerDocumentsSection(
              role: 'caregiver',
              uid: CaregiverProfileService.currentUid!,
              documents: profile.documents,
              documentVerification: profile.documentVerification,
            ),
          ],
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
        Text(value, style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white60)),
      ],
    );
  }
}
