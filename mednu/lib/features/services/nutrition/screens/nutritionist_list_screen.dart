import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/distance.dart';
import '../../../home/providers/location_provider.dart';
import '../providers/nutrition_provider.dart';
import '../models/nutritionist_model.dart';
import '../../../../core/widgets/ux_widgets.dart';

// ── Nutrition theme ─────────────────────────────────────────────────────────
const _kGreen       = Color(0xFF2E7D32);
const _kGreenLight  = Color(0xFF66BB6A);
const _kGreenBg     = Color(0xFFF1F8F1);

class NutritionistListScreen extends ConsumerStatefulWidget {
  const NutritionistListScreen({super.key});

  @override
  ConsumerState<NutritionistListScreen> createState() =>
      _NutritionistListScreenState();
}

class _NutritionistListScreenState
    extends ConsumerState<NutritionistListScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedLanguages = {};

  // Kept in sync with the language list offered at nutritionist
  // registration/profile-edit in mednu_doctor.
  static const _allLanguages = [
    'English', 'Telugu', 'Hindi', 'Tamil', 'Kannada',
    'Malayalam', 'Marathi', 'Bengali',
  ];

  static const _specialties = [
    'All',
    'Weight Loss',
    'Diabetes Diet',
    'Heart Healthy',
    'Pregnancy Nutrition',
    'Sports Nutrition',
    'PCOS Diet',
    'Child Nutrition',
    'Oncology Diet',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedSpecialty = ref.watch(nutritionistSpecialtyFilterProvider);
    final nutritionists     = ref.watch(nutritionistsStreamProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Find Dietician', style: AppTextStyles.h3),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: context.appSurface,
        foregroundColor: context.appTextPrimary,
        surfaceTintColor: context.appSurface,
      ),
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────
          _SearchBar(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          ),
          // ── Specialty chips ───────────────────────────────
          _SpecialtyFilter(
            specialties: _specialties,
            selected:    selectedSpecialty ?? 'All',
            onSelect: (s) =>
                ref.read(nutritionistSpecialtyFilterProvider.notifier).state =
                    s == 'All' ? null : s,
          ),
          // ── Language chips (multi-select) ─────────────────
          _LanguageFilter(
            languages: _allLanguages,
            selected: _selectedLanguages,
            onToggle: (lang) => setState(() {
              _selectedLanguages.contains(lang)
                  ? _selectedLanguages.remove(lang)
                  : _selectedLanguages.add(lang);
            }),
          ),
          // ── Results ───────────────────────────────────────
          Expanded(
            child: nutritionists.when(
              loading: () => ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: List.generate(
                  5,
                  (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: _NutritionistCardSkeleton(),
                  ),
                ),
              ),
              error: (e, _) => const AppErrorState(),
              data: (list) {
                final filtered = list.where((n) {
                  final matchesQuery = _searchQuery.isEmpty ||
                      n.name.toLowerCase().contains(_searchQuery) ||
                      n.specialization.toLowerCase().contains(_searchQuery) ||
                      n.qualification.toLowerCase().contains(_searchQuery) ||
                      n.city.toLowerCase().contains(_searchQuery);
                  final matchesSpecialty = selectedSpecialty == null ||
                      n.specialization
                          .toLowerCase()
                          .contains(selectedSpecialty.toLowerCase());
                  // Nutritionists registered before language selection
                  // existed have an empty `languages` list — treat them as
                  // English-speaking, matching the default selection they'd
                  // see on that step.
                  final nLanguages = n.languages.isEmpty ? const ['English'] : n.languages;
                  final matchesLanguage = _selectedLanguages.isEmpty ||
                      _selectedLanguages.any(nLanguages.contains);
                  return matchesQuery && matchesSpecialty && matchesLanguage;
                }).toList();

                // Real distance sort/filter, same 15km convention already
                // used by pharmacy/diagnostics/doctors/physiotherapists —
                // falls back to showing everyone unsorted when the patient
                // has no location set, or a nutritionist has none on file.
                final myLoc = ref.watch(locationProvider);
                List<(NutritionistModel, double?)> withDistance = filtered
                    .map((n) => (
                          n,
                          (myLoc.lat != null && myLoc.lng != null && n.lat != null && n.lng != null)
                              ? distanceKm(myLoc.lat!, myLoc.lng!, n.lat!, n.lng!)
                              : null,
                        ))
                    .toList();
                if (myLoc.lat != null && myLoc.lng != null) {
                  withDistance = withDistance.where((e) => e.$2 == null || e.$2! <= nearbyRadiusKm).toList()
                    ..sort((a, b) {
                      if (a.$2 == null && b.$2 == null) return 0;
                      if (a.$2 == null) return 1;
                      if (b.$2 == null) return -1;
                      return a.$2!.compareTo(b.$2!);
                    });
                }

                if (withDistance.isEmpty) {
                  return _EmptyState(query: _searchQuery);
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  physics: const BouncingScrollPhysics(),
                  itemCount: withDistance.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (ctx, i) => _NutritionistCard(
                    nutritionist: withDistance[i].$1,
                    distanceKm: withDistance[i].$2,
                    onTap: () => context.push(
                      AppRoutes.nutritionNutritionistProfile
                          .replaceFirst(':id', withDistance[i].$1.id),
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

// ── Search bar ───────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.appSurface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTextStyles.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Search by name, specialty, city...',
          hintStyle:
              AppTextStyles.bodyMedium.copyWith(color: context.appTextHint),
          prefixIcon: Icon(Icons.search_rounded,
              color: context.appTextHint, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded,
                      color: context.appTextHint, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: context.appBackground,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

// ── Specialty filter chips ────────────────────────────────────────────────────

class _SpecialtyFilter extends StatelessWidget {
  final List<String> specialties;
  final String selected;
  final ValueChanged<String> onSelect;

  const _SpecialtyFilter({
    required this.specialties,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.appSurface,
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        scrollDirection: Axis.horizontal,
        itemCount: specialties.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final s          = specialties[i];
          final isSelected = s == selected;
          return GestureDetector(
            onTap: () => onSelect(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected ? _kGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isSelected ? _kGreen : context.appBorder),
              ),
              child: Text(
                s,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : context.appTextSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Language filter chips (multi-select) ──────────────────────────────────────

class _LanguageFilter extends StatelessWidget {
  final List<String> languages;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _LanguageFilter({
    required this.languages,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.appSurface,
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        scrollDirection: Axis.horizontal,
        itemCount: languages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final lang = languages[i];
          final isSelected = selected.contains(lang);
          return GestureDetector(
            onTap: () => onToggle(lang),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected ? _kGreen.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isSelected ? _kGreen : context.appBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (isSelected) ...[
                  const Icon(Icons.check_rounded, size: 13, color: _kGreen),
                  const SizedBox(width: 4),
                ],
                Text(
                  lang,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? _kGreen : context.appTextSecondary,
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ── Nutritionist card ─────────────────────────────────────────────────────────

class _NutritionistCard extends StatelessWidget {
  final NutritionistModel nutritionist;
  final double? distanceKm;
  final VoidCallback onTap;

  const _NutritionistCard(
      {required this.nutritionist, this.distanceKm, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ─────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(
                    name: nutritionist.name,
                    photoUrl: nutritionist.photoUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              nutritionist.name,
                              style: AppTextStyles.labelLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (nutritionist.isAvailable)
                            _AvailabilityBadge(),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        nutritionist.qualification,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: context.appTextSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        nutritionist.specialization,
                        style: AppTextStyles.bodySmall.copyWith(
                            color: _kGreen,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Star rating
                      Row(
                        children: [
                          RatingBarIndicator(
                            rating: nutritionist.rating,
                            itemBuilder: (ctx, _) => const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFF9A825),
                            ),
                            itemCount: 5,
                            itemSize: 14,
                            unratedColor:
                                const Color(0xFFF9A825).withValues(alpha: 0.25),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${nutritionist.rating.toStringAsFixed(1)} (${nutritionist.reviewCount})',
                            style: AppTextStyles.bodySmall.copyWith(
                                color: context.appTextSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Info chips row ──────────────────────────
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoChip(
                  icon: Icons.work_history_rounded,
                  label: '${nutritionist.experienceYears} yrs exp',
                  color: context.appTextSecondary,
                ),
                _InfoChip(
                  icon: Icons.location_on_rounded,
                  label: distanceKm != null
                      ? '${distanceKm!.toStringAsFixed(1)} km away'
                      : nutritionist.city.isNotEmpty
                          ? nutritionist.city
                          : 'Online',
                  color: context.appTextSecondary,
                ),
                if (nutritionist.isOnlineAvailable)
                  const _InfoChip(
                    icon: Icons.videocam_rounded,
                    label: 'Online',
                    color: _kGreen,
                    bgColor: _kGreenBg,
                  ),
                if (nutritionist.isInPersonAvailable)
                  const _InfoChip(
                    icon: Icons.local_hospital_rounded,
                    label: 'In-Person',
                    color: AppColors.info,
                    bgColor: Color(0xFFE3F2FD),
                  ),
              ],
            ),

            // ── Expertise tags ──────────────────────────
            if (nutritionist.expertiseAreas.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: nutritionist.expertiseAreas.take(3).map((e) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kGreenBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      e,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: _kGreen,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            // ── Footer: fee + book CTA ──────────────────
            const SizedBox(height: 14),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Consultation Fee',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: context.appTextHint),
                    ),
                    Text(
                      '₹${nutritionist.consultationFee.toInt()}',
                      style: AppTextStyles.h4.copyWith(color: _kGreen),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Book Now',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Availability badge ────────────────────────────────────────────────────────

class _AvailabilityBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _kGreenBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: _kGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'Available',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _kGreen,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Avatar widget (cached_network_image) ─────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String name;
  final String photoUrl;

  const _Avatar({required this.name, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: photoUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: photoUrl,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              placeholder: (_, __) => _Fallback(name: name),
              errorWidget: (_, __, ___) => _Fallback(name: name),
            )
          : _Fallback(name: name),
    );
  }
}

class _Fallback extends StatelessWidget {
  final String name;
  const _Fallback({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kGreen, _kGreenLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'N',
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ── Info chip ─────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? bgColor;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
    this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: bgColor != null
          ? BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String query;
  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: _kGreenBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search_off_rounded,
                  size: 48, color: _kGreen),
            ),
            const SizedBox(height: 20),
            Text(
              query.isNotEmpty
                  ? 'No results for "$query"'
                  : 'No nutritionists available',
              style: AppTextStyles.labelLarge
                  .copyWith(color: context.appTextPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              query.isNotEmpty
                  ? 'Try a different search term or filter'
                  : 'Dieticians will appear here once added',
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.appTextSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton card ─────────────────────────────────────────────────────────────

class _NutritionistCardSkeleton extends StatelessWidget {
  const _NutritionistCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 2))
        ],
      ),
      child: const AppShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 72, height: 72, radius: 16),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(
                          width: double.infinity, height: 14, radius: 6),
                      SizedBox(height: 7),
                      SkeletonBox(width: 140, height: 11, radius: 6),
                      SizedBox(height: 7),
                      SkeletonBox(width: 100, height: 11, radius: 6),
                      SizedBox(height: 10),
                      SkeletonBox(width: 120, height: 12, radius: 6),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            Row(children: [
              SkeletonBox(width: 80, height: 24, radius: 6),
              SizedBox(width: 8),
              SkeletonBox(width: 70, height: 24, radius: 6),
            ]),
            SizedBox(height: 12),
            Row(children: [
              SkeletonBox(width: 70, height: 34, radius: 8),
              Spacer(),
              SkeletonBox(width: 100, height: 40, radius: 12),
            ]),
          ],
        ),
      ),
    );
  }
}
