import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/r.dart';
import '../providers/nutrition_provider.dart';
import '../models/nutritionist_model.dart';
import '../../../../core/widgets/ux_widgets.dart';

// ── Nutrition theme constants ─────────────────────────────────────────────────
const _kGreen   = Color(0xFF2E7D32);
const _kGreenBg = Color(0xFFF1F8F1);
const _kGradient   = LinearGradient(
  colors: [Color(0xFF1B5E20), Color(0xFF4CAF50)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class NutritionistProfileScreen extends ConsumerWidget {
  final String nutritionistId;
  const NutritionistProfileScreen(
      {super.key, required this.nutritionistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nutritionistAsync =
        ref.watch(nutritionistDetailProvider(nutritionistId));

    return nutritionistAsync.when(
      loading: () => _LoadingScaffold(),
      error: (e, _) => _ErrorScaffold(onBack: () => context.pop()),
      data: (nutritionist) {
        if (nutritionist == null) {
          return _NotFoundScaffold(onBack: () => context.pop());
        }
        return _ProfileScaffold(nutritionist: nutritionist);
      },
    );
  }
}

// ── Loading scaffold ──────────────────────────────────────────────────────────

class _LoadingScaffold extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: R.h(context, 280),
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: _kGradient),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: AppShimmer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: double.infinity, height: 88, radius: 16),
                    SizedBox(height: 16),
                    SkeletonBox(width: double.infinity, height: 120, radius: 16),
                    SizedBox(height: 16),
                    SkeletonBox(width: double.infinity, height: 80, radius: 16),
                    SizedBox(height: 16),
                    SkeletonBox(width: double.infinity, height: 160, radius: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error scaffold ────────────────────────────────────────────────────────────

class _ErrorScaffold extends StatelessWidget {
  final VoidCallback onBack;
  const _ErrorScaffold({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: onBack,
        ),
        title: const Text('Nutritionist Profile', style: AppTextStyles.h3),
        backgroundColor: context.appSurface,
        foregroundColor: context.appTextPrimary,
        elevation: 0,
      ),
      backgroundColor: context.appBackground,
      body: const AppErrorState(),
    );
  }
}

// ── Not-found scaffold ────────────────────────────────────────────────────────

class _NotFoundScaffold extends StatelessWidget {
  final VoidCallback onBack;
  const _NotFoundScaffold({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: onBack,
        ),
        title: const Text('Not Found', style: AppTextStyles.h3),
        backgroundColor: context.appSurface,
        foregroundColor: context.appTextPrimary,
        elevation: 0,
      ),
      body: Center(
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
                child: const Icon(Icons.person_off_rounded,
                    size: 48, color: _kGreen),
              ),
              const SizedBox(height: 20),
              Text(
                'Nutritionist not found',
                style: AppTextStyles.labelLarge
                    .copyWith(color: context.appTextPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'This profile may have been removed or is unavailable.',
                style: AppTextStyles.bodySmall
                    .copyWith(color: context.appTextSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onBack,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Go Back',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Main profile scaffold ─────────────────────────────────────────────────────

class _ProfileScaffold extends StatelessWidget {
  final NutritionistModel nutritionist;
  const _ProfileScaffold({required this.nutritionist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Hero sliver app bar ─────────────────────
          _HeroSliverAppBar(nutritionist: nutritionist),

          // ── Body content ────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats row
                  _StatsRow(nutritionist: nutritionist),
                  const SizedBox(height: 16),

                  // About section
                  _SectionCard(
                    title: 'About',
                    icon: Icons.person_rounded,
                    child: Text(
                      nutritionist.bio.isNotEmpty
                          ? nutritionist.bio
                          : 'Certified nutrition expert helping patients achieve their dietary and wellness goals through evidence-based nutrition science.',
                      style: AppTextStyles.bodyMedium.copyWith(
                          color: context.appTextSecondary, height: 1.6),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Expertise areas
                  if (nutritionist.expertiseAreas.isNotEmpty) ...[
                    _SectionCard(
                      title: 'Areas of Expertise',
                      icon: Icons.psychology_rounded,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: nutritionist.expertiseAreas
                            .map((e) => _GreenChip(label: e))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Rating & reviews
                  _RatingCard(nutritionist: nutritionist),
                  const SizedBox(height: 16),

                  // Languages
                  if (nutritionist.languages.isNotEmpty) ...[
                    _SectionCard(
                      title: 'Languages',
                      icon: Icons.language_rounded,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: nutritionist.languages
                            .map((l) => _GreenChip(
                                label: l,
                                color: AppColors.info,
                                bgColor: const Color(0xFFE3F2FD)))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Consultation card + CTA
                  _ConsultationCard(nutritionist: nutritionist),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Sticky bottom book button ────────────────────────
      bottomNavigationBar: _BookingBottomBar(nutritionist: nutritionist),
    );
  }
}

// ── Hero sliver app bar ───────────────────────────────────────────────────────

class _HeroSliverAppBar extends StatelessWidget {
  final NutritionistModel nutritionist;
  const _HeroSliverAppBar({required this.nutritionist});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: R.h(context, 260),
      backgroundColor: const Color(0xFF1B5E20),
      surfaceTintColor: Colors.transparent,
      leading: GestureDetector(
        onTap: () => context.pop(),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 18),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Gradient background
            Container(
              decoration: const BoxDecoration(gradient: _kGradient),
            ),
            // Decorative circles
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              right: 20,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            // Profile info overlay
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Photo
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: nutritionist.photoUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: nutritionist.photoUrl,
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  _BigAvatarFallback(name: nutritionist.name),
                              errorWidget: (_, __, ___) =>
                                  _BigAvatarFallback(name: nutritionist.name),
                            )
                          : _BigAvatarFallback(name: nutritionist.name),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Name & details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          nutritionist.name,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          nutritionist.qualification,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          nutritionist.specialization,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 6),
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
                              unratedColor: Colors.white24,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${nutritionist.rating.toStringAsFixed(1)} · ${nutritionist.reviewCount} reviews',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
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
    );
  }
}

class _BigAvatarFallback extends StatelessWidget {
  final String name;
  const _BigAvatarFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      color: Colors.white.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'N',
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final NutritionistModel nutritionist;
  const _StatsRow({required this.nutritionist});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
              value: '${nutritionist.experienceYears}+',
              label: 'Years Exp',
              icon: Icons.work_rounded),
          _VerticalDivider(),
          _StatItem(
              value: '${nutritionist.reviewCount}+',
              label: 'Patients',
              icon: Icons.people_rounded),
          _VerticalDivider(),
          _StatItem(
              value: nutritionist.rating.toStringAsFixed(1),
              label: 'Rating',
              icon: Icons.star_rounded),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  const _StatItem(
      {required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _kGreen, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: AppTextStyles.h3.copyWith(color: _kGreen)),
        const SizedBox(height: 2),
        Text(label,
            style: AppTextStyles.bodySmall
                .copyWith(color: context.appTextSecondary)),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 44,
      color: context.appBorder,
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _kGreenBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _kGreen, size: 16),
              ),
              const SizedBox(width: 10),
              Text(title, style: AppTextStyles.h4),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Rating card ───────────────────────────────────────────────────────────────

class _RatingCard extends StatelessWidget {
  final NutritionistModel nutritionist;
  const _RatingCard({required this.nutritionist});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.star_rounded,
                    color: Color(0xFFF9A825), size: 16),
              ),
              const SizedBox(width: 10),
              const Text('Ratings & Reviews', style: AppTextStyles.h4),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Column(
                children: [
                  Text(
                    nutritionist.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: _kGreen,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  RatingBarIndicator(
                    rating: nutritionist.rating,
                    itemBuilder: (ctx, _) => const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFF9A825),
                    ),
                    itemCount: 5,
                    itemSize: 16,
                    unratedColor: const Color(0xFFF9A825)
                        .withValues(alpha: 0.25),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${nutritionist.reviewCount} reviews',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: context.appTextSecondary),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [5, 4, 3, 2, 1].map((star) {
                    // Simulated distribution
                    final pct = switch (star) {
                      5 => 0.6,
                      4 => 0.25,
                      3 => 0.1,
                      2 => 0.03,
                      _ => 0.02,
                    };
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Text('$star',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: context.appTextSecondary)),
                          const SizedBox(width: 4),
                          const Icon(Icons.star_rounded,
                              size: 10, color: Color(0xFFF9A825)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: const Color(0xFFF5F5F5),
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                        Color(0xFFF9A825)),
                                minHeight: 6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Consultation card ─────────────────────────────────────────────────────────

class _ConsultationCard extends StatelessWidget {
  final NutritionistModel nutritionist;
  const _ConsultationCard({required this.nutritionist});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _kGreenBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.event_available_rounded,
                    color: _kGreen, size: 16),
              ),
              const SizedBox(width: 10),
              const Text('Consultation', style: AppTextStyles.h4),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fee per session',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: context.appTextHint)),
                    Text(
                      '₹${nutritionist.consultationFee.toInt()}',
                      style: AppTextStyles.h2.copyWith(color: _kGreen),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (nutritionist.isOnlineAvailable)
                      const _ModeRow(icon: Icons.videocam_rounded, label: 'Online'),
                    if (nutritionist.isInPersonAvailable) ...[
                      const SizedBox(height: 6),
                      _ModeRow(
                        icon: Icons.location_on_rounded,
                        label: nutritionist.clinicName.isNotEmpty
                            ? nutritionist.clinicName
                            : 'In-Person',
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ModeRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _kGreenBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _kGreen),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: _kGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Booking bottom bar ────────────────────────────────────────────────────────

class _BookingBottomBar extends StatelessWidget {
  final NutritionistModel nutritionist;
  const _BookingBottomBar({required this.nutritionist});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
      decoration: BoxDecoration(
        color: context.appSurface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -3),
          )
        ],
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Fee',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: context.appTextHint)),
              Text(
                '₹${nutritionist.consultationFee.toInt()}',
                style: AppTextStyles.h3.copyWith(color: _kGreen),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
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
              label: const Text(
                'Book Appointment',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chip ──────────────────────────────────────────────────────────────────────

class _GreenChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;

  const _GreenChip({
    required this.label,
    this.color = _kGreen,
    this.bgColor = _kGreenBg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
