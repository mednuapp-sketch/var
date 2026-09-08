import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/ux_widgets.dart';
import '../models/counsellor_model.dart';
import '../services/counsellor_service.dart';

// ── Counselling theme (matches the patient app's Counselling screen header) ──
const _kPlum     = Color(0xFF633058);
const _kPlumDark = Color(0xFF3D1D36);
const _kPlumBg   = Color(0xFFF3E5F5);

class CounsellorListScreen extends StatefulWidget {
  const CounsellorListScreen({super.key});

  @override
  State<CounsellorListScreen> createState() => _CounsellorListScreenState();
}

class _CounsellorListScreenState extends State<CounsellorListScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedSpecialty = 'All';

  static const _specialties = [
    'All',
    'Depression & Anxiety',
    'Stress Management',
    'Relationship Therapy',
    'Child & Teen Therapy',
    'Addiction Recovery',
    'Grief Therapy',
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
        title: const Text('Find a Counsellor', style: AppTextStyles.h3),
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
                hintText: 'Search by name or specialty...',
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
          ),
          const SizedBox(height: 6),
          // ── Results ───────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<CounsellorModel>>(
              stream: CounsellorService.counsellorsStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return ListView(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: List.generate(
                      5,
                      (_) => const Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: _CounsellorCardSkeleton(),
                      ),
                    ),
                  );
                }
                if (snap.hasError) return const AppErrorState();

                final list = snap.data ?? const [];
                final filtered = list.where((c) {
                  final matchesQuery = _searchQuery.isEmpty ||
                      c.name.toLowerCase().contains(_searchQuery) ||
                      c.specialties.any((s) => s.toLowerCase().contains(_searchQuery));
                  final matchesSpecialty = _selectedSpecialty == 'All' ||
                      c.specialties.any((s) => s.toLowerCase().contains(_selectedSpecialty.toLowerCase()));
                  return matchesQuery && matchesSpecialty;
                }).toList()
                  // Online-first: a counsellor actively online right now can
                  // respond immediately, so surface them ahead of ones who
                  // are approved but not currently reachable.
                  ..sort((a, b) => (b.isCurrentlyOnline ? 1 : 0).compareTo(a.isCurrentlyOnline ? 1 : 0));

                if (filtered.isEmpty) {
                  return _EmptyState(query: _searchQuery);
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (ctx, i) => _CounsellorCard(
                    counsellor: filtered[i],
                    onTap: () => context.push(
                      AppRoutes.counsellingCounsellorProfile.replaceFirst(':id', filtered[i].id),
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

// ── Specialty chip row ──────────────────────────────────────────────────────

class _ChipRow extends StatelessWidget {
  final List<String> options;
  final bool Function(String) isSelected;
  final ValueChanged<String> onTap;

  const _ChipRow({required this.options, required this.isSelected, required this.onTap});

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
                color: selected ? _kPlum : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? _kPlum : context.appBorder),
              ),
              child: Text(
                option,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : context.appTextSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Counsellor card ─────────────────────────────────────────────────────────

class _CounsellorCard extends StatelessWidget {
  final CounsellorModel counsellor;
  final VoidCallback onTap;

  const _CounsellorCard({required this.counsellor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = counsellor;
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
                _Avatar(name: c.name, photoUrl: c.photoUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(c.name, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (c.isCurrentlyOnline) ...[
                          const SizedBox(width: 6),
                          const _OnlineBadge(),
                        ],
                      ]),
                      const SizedBox(height: 2),
                      if (c.certifications.isNotEmpty)
                        Text(
                          c.certifications.join(', '),
                          style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (c.specialties.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          c.specialties.join(' · '),
                          style: AppTextStyles.bodySmall.copyWith(color: _kPlum, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(children: [
                        RatingBarIndicator(
                          rating: c.rating,
                          itemBuilder: (ctx, _) => const Icon(Icons.star_rounded, color: Color(0xFFF9A825)),
                          itemCount: 5,
                          itemSize: 14,
                          unratedColor: const Color(0xFFF9A825).withValues(alpha: 0.25),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          c.totalSessions > 0 ? '${c.rating.toStringAsFixed(1)} (${c.totalSessions})' : 'New',
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
                _InfoChip(icon: Icons.work_history_rounded, label: '${c.experienceYears} yrs exp', color: context.appTextSecondary),
                _InfoChip(icon: Icons.videocam_rounded, label: 'Video/Chat session', color: _kPlum, bgColor: _kPlumBg),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Session Rate', style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint)),
                    Text('₹${c.hourlyRate.toInt()}', style: AppTextStyles.h4.copyWith(color: _kPlum)),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPlum,
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
        gradient: LinearGradient(colors: [_kPlum, _kPlumDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'C',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

class _OnlineBadge extends StatelessWidget {
  const _OnlineBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6, height: 6,
          decoration: const BoxDecoration(color: Color(0xFF2E7D32), shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        const Text('Online now',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
      ]),
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
              decoration: const BoxDecoration(color: _kPlumBg, shape: BoxShape.circle),
              child: const Icon(Icons.search_off_rounded, size: 48, color: _kPlum),
            ),
            const SizedBox(height: 20),
            Text(
              query.isNotEmpty ? 'No results for "$query"' : 'No counsellors available',
              style: AppTextStyles.labelLarge.copyWith(color: context.appTextPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              query.isNotEmpty ? 'Try a different search term or filter' : 'Counsellors will appear here once added',
              style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CounsellorCardSkeleton extends StatelessWidget {
  const _CounsellorCardSkeleton();

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
