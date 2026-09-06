import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/distance.dart';
import '../../../../core/widgets/ux_widgets.dart';
import '../../../home/providers/location_provider.dart';
import '../models/physiotherapist_model.dart';
import '../services/physiotherapist_service.dart';

// ── Physiotherapy theme (matches the partner app's profile gradient) ──────────
const _kTeal      = Color(0xFF00838F);
const _kTealDark  = Color(0xFF006064);
const _kTealBg    = Color(0xFFE0F7FA);

class PhysiotherapistListScreen extends ConsumerStatefulWidget {
  const PhysiotherapistListScreen({super.key});

  @override
  ConsumerState<PhysiotherapistListScreen> createState() => _PhysiotherapistListScreenState();
}

class _PhysiotherapistListScreenState extends ConsumerState<PhysiotherapistListScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedSpecialty = 'All';
  final Set<String> _selectedLanguages = {};

  static const _specialties = [
    'All',
    'Sports Injury',
    'Back & Neck Pain',
    'Post-Surgery Rehab',
    'Neuro Rehab',
    'Joint Pain',
    'Pediatric Physio',
    'Geriatric Care',
  ];

  // Kept in sync with the language list offered at physiotherapist
  // registration/profile-edit in mednu_doctor.
  static const _allLanguages = [
    'English', 'Telugu', 'Hindi', 'Tamil', 'Kannada',
    'Malayalam', 'Marathi', 'Bengali',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Find Physiotherapist', style: AppTextStyles.h3),
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
          Container(
            color: context.appSurface,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              style: AppTextStyles.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Search by name, specialty, city...',
                hintStyle: AppTextStyles.bodyMedium.copyWith(color: context.appTextHint),
                prefixIcon: Icon(Icons.search_rounded, color: context.appTextHint, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, color: context.appTextHint, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
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
          ),
          // ── Specialty chips ───────────────────────────────
          _ChipRow(
            options: _specialties,
            isSelected: (s) => s == _selectedSpecialty,
            onTap: (s) => setState(() => _selectedSpecialty = s),
            activeColor: _kTeal,
          ),
          // ── Language chips (multi-select) ─────────────────
          _ChipRow(
            options: _allLanguages,
            isSelected: (lang) => _selectedLanguages.contains(lang),
            onTap: (lang) => setState(() {
              _selectedLanguages.contains(lang)
                  ? _selectedLanguages.remove(lang)
                  : _selectedLanguages.add(lang);
            }),
            activeColor: _kTeal,
            showCheck: true,
          ),
          const SizedBox(height: 6),
          // ── Results ───────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<PhysiotherapistModel>>(
              stream: PhysiotherapistService.physiotherapistsStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return ListView(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: List.generate(
                      5,
                      (_) => const Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: _PhysiotherapistCardSkeleton(),
                      ),
                    ),
                  );
                }
                if (snap.hasError) return const AppErrorState();

                final list = snap.data ?? const [];
                final filtered = list.where((p) {
                  final matchesQuery = _searchQuery.isEmpty ||
                      p.name.toLowerCase().contains(_searchQuery) ||
                      p.city.toLowerCase().contains(_searchQuery) ||
                      p.specialties.any((s) => s.toLowerCase().contains(_searchQuery));
                  final matchesSpecialty = _selectedSpecialty == 'All' ||
                      p.specialties.any((s) => s.toLowerCase().contains(_selectedSpecialty.toLowerCase()));
                  // Physiotherapists registered before language selection
                  // existed have an empty `languages` list — treat them as
                  // English-speaking, matching the default selection they'd
                  // see on that step.
                  final pLanguages = p.languages.isEmpty ? const ['English'] : p.languages;
                  final matchesLanguage = _selectedLanguages.isEmpty ||
                      _selectedLanguages.any(pLanguages.contains);
                  return matchesQuery && matchesSpecialty && matchesLanguage;
                }).toList();

                // Real distance sort/filter, same 15km convention already
                // used by pharmacy/diagnostics/doctors — falls back to
                // showing everyone unsorted when the patient has no
                // location set, or a physiotherapist has none on file.
                final myLoc = ref.watch(locationProvider);
                List<(PhysiotherapistModel, double?)> withDistance = filtered
                    .map((p) => (
                          p,
                          (myLoc.lat != null && myLoc.lng != null && p.clinicLat != null && p.clinicLng != null)
                              ? distanceKm(myLoc.lat!, myLoc.lng!, p.clinicLat!, p.clinicLng!)
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
                  itemBuilder: (ctx, i) => _PhysiotherapistCard(
                    physiotherapist: withDistance[i].$1,
                    distanceKm: withDistance[i].$2,
                    onTap: () => context.push(
                      AppRoutes.physioTherapistProfile.replaceFirst(':id', withDistance[i].$1.id),
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

// ── Generic chip row (single or multi-select) ─────────────────────────────────

class _ChipRow extends StatelessWidget {
  final List<String> options;
  final bool Function(String) isSelected;
  final ValueChanged<String> onTap;
  final Color activeColor;
  final bool showCheck;

  const _ChipRow({
    required this.options,
    required this.isSelected,
    required this.onTap,
    required this.activeColor,
    this.showCheck = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.appSurface,
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final option = options[i];
          final selected = isSelected(option);
          return GestureDetector(
            onTap: () => onTap(option),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected
                    ? (showCheck ? activeColor.withValues(alpha: 0.1) : activeColor)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? activeColor : context.appBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (selected && showCheck) ...[
                  Icon(Icons.check_rounded, size: 13, color: activeColor),
                  const SizedBox(width: 4),
                ],
                Text(
                  option,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? (showCheck ? activeColor : Colors.white)
                        : context.appTextSecondary,
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

// ── Physiotherapist card ────────────────────────────────────────────────────

class _PhysiotherapistCard extends StatelessWidget {
  final PhysiotherapistModel physiotherapist;
  final double? distanceKm;
  final VoidCallback onTap;

  const _PhysiotherapistCard({required this.physiotherapist, this.distanceKm, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = physiotherapist;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(name: p.name, photoUrl: p.photoUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      if (p.certifications.isNotEmpty)
                        Text(
                          p.certifications.join(', '),
                          style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (p.specialties.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          p.specialties.join(' · '),
                          style: AppTextStyles.bodySmall.copyWith(color: _kTeal, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(children: [
                        RatingBarIndicator(
                          rating: p.rating,
                          itemBuilder: (ctx, _) => const Icon(Icons.star_rounded, color: Color(0xFFF9A825)),
                          itemCount: 5,
                          itemSize: 14,
                          unratedColor: const Color(0xFFF9A825).withValues(alpha: 0.25),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          p.totalSessions > 0 ? '${p.rating.toStringAsFixed(1)} (${p.totalSessions})' : 'New',
                          style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoChip(icon: Icons.work_history_rounded, label: '${p.experienceYears} yrs exp', color: context.appTextSecondary),
                _InfoChip(
                  icon: Icons.location_on_rounded,
                  label: distanceKm != null
                      ? '${distanceKm!.toStringAsFixed(1)} km away'
                      : p.city.isNotEmpty
                          ? p.city
                          : 'Home visits',
                  color: context.appTextSecondary,
                ),
                if (p.languages.isNotEmpty)
                  _InfoChip(icon: Icons.translate_rounded, label: p.languages.join(', '), color: _kTeal, bgColor: _kTealBg),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Session Rate', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
                    Text('₹${p.hourlyRate.toInt()}', style: AppTextStyles.h4.copyWith(color: _kTeal)),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Book Now',
                        style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13)),
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
        gradient: LinearGradient(colors: [_kTeal, _kTealDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'P',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? bgColor;

  const _InfoChip({required this.icon, required this.label, required this.color, this.bgColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: bgColor != null ? BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)) : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

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
              decoration: const BoxDecoration(color: _kTealBg, shape: BoxShape.circle),
              child: const Icon(Icons.search_off_rounded, size: 48, color: _kTeal),
            ),
            const SizedBox(height: 20),
            Text(
              query.isNotEmpty ? 'No results for "$query"' : 'No physiotherapists available',
              style: AppTextStyles.labelLarge.copyWith(color: context.appTextPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              query.isNotEmpty ? 'Try a different search term or filter' : 'Physiotherapists will appear here once added',
              style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PhysiotherapistCardSkeleton extends StatelessWidget {
  const _PhysiotherapistCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 2))],
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
                      SkeletonBox(width: double.infinity, height: 14, radius: 6),
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
