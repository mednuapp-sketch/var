import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/router/app_router.dart';
import '../providers/nutrition_provider.dart';
import '../models/nutritionist_model.dart';

class NutritionistProfileScreen extends ConsumerWidget {
  final String nutritionistId;
  const NutritionistProfileScreen({super.key, required this.nutritionistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nutritionistAsync = ref.watch(nutritionistDetailProvider(nutritionistId));

    return nutritionistAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
          title: const Text('Nutritionist Profile', style: AppTextStyles.h3),
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, size: 56, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text('Failed to load profile', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Text('Please check your connection and try again.', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
      data: (nutritionist) {
        if (nutritionist == null) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
              title: const Text('Not Found', style: AppTextStyles.h3),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
            ),
            backgroundColor: AppColors.background,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_off_rounded, size: 56, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text('Nutritionist not found', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Text('This profile may have been removed or is unavailable.', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => context.pop(),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Go Back', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: AppColors.background,
          body: _ProfileBody(nutritionist: nutritionist),
        );
      },
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final NutritionistModel nutritionist;
  const _ProfileBody({required this.nutritionist});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 240,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
            ),
            onPressed: () => context.pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF66BB6A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: nutritionist.photoUrl.isNotEmpty
                            ? Image.network(nutritionist.photoUrl, width: 90, height: 90, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _BigAvatar(name: nutritionist.name))
                            : _BigAvatar(name: nutritionist.name),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nutritionist.name, style: const TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                            Text(nutritionist.qualification, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white70)),
                            Text(nutritionist.specialization, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white60)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, color: Color(0xFFF9A825), size: 14),
                                const SizedBox(width: 4),
                                Text('${nutritionist.rating.toStringAsFixed(1)} (${nutritionist.reviewCount} reviews)', style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatsRow(nutritionist: nutritionist),
                const SizedBox(height: 20),
                _SectionCard(
                  title: 'About',
                  child: Text(nutritionist.bio.isNotEmpty ? nutritionist.bio : 'Certified nutrition expert helping patients achieve their dietary goals.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.6)),
                ),
                const SizedBox(height: 16),
                if (nutritionist.expertiseAreas.isNotEmpty)
                  _SectionCard(
                    title: 'Expertise Areas',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: nutritionist.expertiseAreas.map((e) => _Chip(label: e)).toList(),
                    ),
                  ),
                const SizedBox(height: 16),
                _ConsultationCard(nutritionist: nutritionist),
                const SizedBox(height: 16),
                if (nutritionist.languages.isNotEmpty)
                  _SectionCard(
                    title: 'Languages',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: nutritionist.languages.map((l) => _Chip(label: l, color: AppColors.info)).toList(),
                    ),
                  ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BigAvatar extends StatelessWidget {
  final String name;
  const _BigAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'N',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 36, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final NutritionistModel nutritionist;
  const _StatsRow({required this.nutritionist});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(value: '${nutritionist.experienceYears}+', label: 'Years Exp'),
          _Divider(),
          _Stat(value: '${nutritionist.reviewCount}+', label: 'Patients'),
          _Divider(),
          _Stat(value: nutritionist.rating.toStringAsFixed(1), label: 'Rating'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTextStyles.h3.copyWith(color: const Color(0xFF2E7D32))),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: AppColors.border);
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.h4),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ConsultationCard extends StatelessWidget {
  final NutritionistModel nutritionist;
  const _ConsultationCard({required this.nutritionist});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Consultation', style: AppTextStyles.h4),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fee per session', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
                    Text('₹${nutritionist.consultationFee.toInt()}', style: AppTextStyles.h3.copyWith(color: const Color(0xFF2E7D32))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (nutritionist.isOnlineAvailable)
                    Row(
                      children: [
                        const Icon(Icons.videocam_rounded, size: 14, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 4),
                        const Text('Online', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Color(0xFF2E7D32))),
                      ],
                    ),
                  if (nutritionist.isInPersonAvailable) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 4),
                        Text(nutritionist.clinicName.isNotEmpty ? nutritionist.clinicName : 'In-Person', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Color(0xFF2E7D32))),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push(
                AppRoutes.nutritionBookAppointment,
                extra: {
                  'nutritionistId': nutritionist.id,
                  'nutritionistName': nutritionist.name,
                  'nutritionistSpecialization': nutritionist.specialization,
                  'fee': nutritionist.consultationFee,
                  'slots': nutritionist.slots,
                  'isOnline': nutritionist.isOnlineAvailable,
                  'isInPerson': nutritionist.isInPersonAvailable,
                  'availableDays': nutritionist.availableDays,
                },
              ),
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: const Text('Book Appointment', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, this.color = const Color(0xFF2E7D32)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
