import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../location/models/precise_address.dart';
import '../../location/screens/map_location_picker_screen.dart';
import '../models/nutritionist_profile.dart';
import '../providers/nutrition_providers.dart';
import '../services/nutritionist_profile_service.dart';

/// Nutritionist identity — a hero avatar/rating card plus specialization
/// info, mirroring the Caregiver module's profile shape. This screen is also
/// the module's only profile *write* path: creating
/// `nutritionist_profiles/{uid}` here is what starts the admin-approval gate
/// (see `AppRouteRefreshListenable`) and, once approved, is what
/// `onNutritionistProfileWriteForVisibility` (functions/index.js) mirrors
/// into the patient-facing `nutritionists/{uid}` catalogue entry — before
/// that, a nutritionist simply isn't findable or bookable by patients.
class NutritionProfileScreen extends ConsumerWidget {
  const NutritionProfileScreen({super.key});

  static const _allLanguages = [
    'English', 'Telugu', 'Hindi', 'Tamil', 'Kannada',
    'Malayalam', 'Marathi', 'Bengali',
  ];

  Future<void> _edit(BuildContext context, NutritionistProfile current) async {
    final uid = NutritionistProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }

    final name = TextEditingController(
        text: current.name == 'Complete your profile' ? '' : current.name);
    final qualification = TextEditingController(text: current.qualification);
    final specialization = TextEditingController(text: current.specialization);
    final experienceYears = TextEditingController(
        text: current.experienceYears == 0 ? '' : '${current.experienceYears}');
    final consultationFee = TextEditingController(
        text: current.consultationFee == 0 ? '' : '${current.consultationFee}');
    var city = current.city;
    var lat = current.lat;
    var lng = current.lng;
    final bio = TextEditingController(text: current.bio);
    final selectedLanguages = <String>{
      ...current.languages.isEmpty ? const ['English'] : current.languages,
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Nutritionist Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
                TextField(controller: qualification, decoration: const InputDecoration(labelText: 'Qualification (e.g. RD, MSc Nutrition)')),
                TextField(controller: specialization, decoration: const InputDecoration(labelText: 'Specialization')),
                TextField(
                  controller: experienceYears,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Years of experience'),
                ),
                TextField(
                  controller: consultationFee,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Consultation fee (₹)'),
                ),
                InkWell(
                  onTap: () async {
                    final result = await Navigator.of(dialogContext).push<PreciseAddress>(
                      MaterialPageRoute(
                        builder: (_) => MapLocationPickerScreen(initialLat: lat, initialLng: lng),
                      ),
                    );
                    if (result == null) return;
                    setDialogState(() {
                      city = result.city ?? city;
                      lat = result.lat;
                      lng = result.lng;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Service Area',
                      prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.textSecondary),
                      suffixIcon: Icon(Icons.map_outlined, color: AppColors.primary),
                      helperText: 'Tap to pick the city/area you serve on the map',
                    ),
                    child: Text(
                      city.isEmpty ? 'Select on map' : city,
                      style: TextStyle(color: city.isEmpty ? AppColors.textHint : AppColors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bio,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'About you'),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Languages Spoken', style: AppTextStyles.labelMedium),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: NutritionProfileScreen._allLanguages.map((lang) => FilterChip(
                    label: Text(lang),
                    selected: selectedLanguages.contains(lang),
                    onSelected: (v) => setDialogState(() {
                      if (v) {
                        selectedLanguages.add(lang);
                      } else if (selectedLanguages.length > 1) {
                        selectedLanguages.remove(lang);
                      }
                    }),
                    selectedColor: AppColors.primary.withValues(alpha: 0.14),
                    checkmarkColor: AppColors.primary,
                  )).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    // Disposal is deferred until well after the dialog's own exit transition
    // finishes — disposing synchronously right after showDialog's Future
    // resolves is the documented dispose-race crash pattern elsewhere in this
    // codebase (the AlertDialog/TextFields are still mounted and mid-animation
    // at that exact point, not actually unmounted yet). The default Material
    // dialog transition is ~150ms; 400ms leaves comfortable margin.
    unawaited(Future.delayed(const Duration(milliseconds: 400), () {
      name.dispose();
      qualification.dispose();
      specialization.dispose();
      experienceYears.dispose();
      consultationFee.dispose();
      bio.dispose();
    }));

    if (saved != true) return;

    final fee = num.tryParse(consultationFee.text.trim()) ?? 0;
    final years = int.tryParse(experienceYears.text.trim()) ?? 0;

    try {
      await NutritionistProfileService.updateProfile(uid, {
        'name': name.text.trim(),
        'qualification': qualification.text.trim(),
        'specialization': specialization.text.trim(),
        'experienceYears': years,
        'consultationFee': fee,
        'city': city,
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
        'bio': bio.text.trim(),
        'languages': selectedLanguages.toList(),
      });
      if (context.mounted) FeedbackService.showSuccess(context, 'Profile saved');
    } catch (_) {
      if (context.mounted) {
        FeedbackService.showError(context, "Couldn't save your profile. Please try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(nutritionistProfileProvider).valueOrNull ?? NutritionistProfile.empty();

    return SharedAppShell(
      currentRoute: AppRoutes.nutritionProfile,
      title: 'Nutritionist Profile',
      extraActions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
          onPressed: () => _edit(context, profile),
          tooltip: 'Edit profile',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (profile.status == 'pending')
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: PremiumCard(
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, color: AppColors.warning),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your application is under review. Patients will be able to find and book you once approved.',
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                SharedProfileAvatar(name: profile.name, size: 76, isVerified: profile.documentsVerified),
                const SizedBox(height: 14),
                Text(profile.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                if (profile.specialization.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(profile.specialization, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _HeroStat(label: 'Rating', value: profile.rating.toStringAsFixed(1), icon: Icons.star_rounded),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Experience', value: '${profile.experienceYears} yrs', icon: Icons.workspace_premium_outlined),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Fee', value: '₹${profile.consultationFee}', icon: Icons.currency_rupee_rounded),
                  ],
                ),
              ],
            ),
          ),
          if (profile.qualification.isNotEmpty) ...[
            const SizedBox(height: 16),
            PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Qualification', style: AppTextStyles.labelMedium),
                      const Spacer(),
                      if (profile.documentsVerified)
                        const StatusBadge(label: 'Verified', color: AppColors.success, icon: Icons.verified_rounded),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(profile.qualification, style: AppTextStyles.bodyMedium),
                ],
              ),
            ),
          ],
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 16),
            PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('About', style: AppTextStyles.labelMedium),
                  const SizedBox(height: 10),
                  Text(profile.bio, style: AppTextStyles.bodyMedium),
                ],
              ),
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
        Text(value, style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Colors.white60)),
      ],
    );
  }
}
