import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/screens/family_management_screen.dart';

// ═══════════════════════════════════════════════════════════
// DoctorConsultBanner
// ═══════════════════════════════════════════════════════════
class DoctorConsultBanner extends StatelessWidget {
  const DoctorConsultBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.consultation),
      child: Container(
        width: double.infinity,
        height: 176,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
          gradient: AppColors.primaryGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.38),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Large background circle top-right
            Positioned(
              right: -18, top: -25,
              child: Container(
                width: 130, height: 130,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: 75, bottom: -35,
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Doctor avatar section on the right
            Positioned(
              right: 0, top: 0, bottom: 0,
              child: SizedBox(
                width: 130,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow ring
                    Container(
                      width: 96, height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
                      ),
                    ),
                    // Doctor photo
                    ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: 'https://images.unsplash.com/photo-1612349317150-e413f6a5b16d?w=200&h=200&fit=crop&crop=face&q=80',
                        width: 82, height: 82,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 82, height: 82,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 38),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 82, height: 82,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 38),
                        ),
                      ),
                    ),
                    // "Online" badge top-right
                    Positioned(
                      top: 18, right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8)
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6, height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2E7D32),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Online',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Chat bubble bottom-left
                    Positioned(
                      bottom: 18, left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '💬 Ready',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Text content on the left
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 130, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Consult Top Doctors',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Video & chat with\nspecialists near you',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Colors.white70,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Quick Connect',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(Icons.arrow_forward_rounded, size: 12, color: AppColors.primary),
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

// ═══════════════════════════════════════════════════════════
// AiDoctorCard
// ═══════════════════════════════════════════════════════════
class AiDoctorCard extends StatelessWidget {
  const AiDoctorCard({super.key});

  static const _questions = ['Headache?', 'Fever?', 'Skin rash?', 'Cough?'];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.careAssistant),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3F1B7C), Color(0xFF7B1FA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4527A0).withOpacity(0.38),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -18, top: -22,
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: 55, bottom: -28,
              child: Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.psychology_alt_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'AI Doctor',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.22),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'BETA',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            'Available 24/7 · Instant answers',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Animated pulse dot
                    Container(
                      width: 10, height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF69FF47),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Describe your symptoms & get\nsmart health guidance instantly',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _questions.map((q) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Text(
                      q,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.14),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 13, color: Color(0xFF4527A0)),
                        SizedBox(width: 6),
                        Text(
                          'Ask AI Doctor',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4527A0),
                          ),
                        ),
                      ],
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

// ═══════════════════════════════════════════════════════════
// SpecialtiesSection
// ═══════════════════════════════════════════════════════════
class SpecialtiesSection extends StatelessWidget {
  const SpecialtiesSection({super.key});

  static const _specs = [
    _Spec('General',       Icons.medical_services_rounded,      Color(0xFF1565C0)),
    _Spec('Cardiology',    Icons.favorite_rounded,              Color(0xFFC62828)),
    _Spec('Dermatology',   Icons.face_retouching_natural,       Color(0xFFE65100)),
    _Spec('Gynaecology',   Icons.pregnant_woman,                Color(0xFFC2185B)),
    _Spec('Paediatrics',   Icons.child_care_rounded,            Color(0xFF6A1B9A)),
    _Spec('ENT',           Icons.hearing_rounded,               Color(0xFF00695C)),
    _Spec('Orthopaedics',  Icons.accessibility_new_rounded,     Color(0xFF283593)),
    _Spec('Neurology',     Icons.psychology_rounded,            Color(0xFF4A148C)),
    _Spec('Ophthalmology', Icons.visibility_rounded,            Color(0xFF2E7D32)),
    _Spec('Psychiatry',    Icons.self_improvement_rounded,      Color(0xFF00838F)),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Specialties', style: AppTextStyles.h4),
              TextButton(
                onPressed: () => context.push(AppRoutes.doctors),
                child: const Text('See All'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 104,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _specs.length,
            itemBuilder: (_, i) => _SpecChip(spec: _specs[i]),
          ),
        ),
      ],
    );
  }
}

class _Spec {
  final String label;
  final IconData icon;
  final Color color;
  const _Spec(this.label, this.icon, this.color);
}

class _SpecChip extends StatelessWidget {
  final _Spec spec;
  const _SpecChip({required this.spec});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => context.push('${AppRoutes.doctors}?specialty=${spec.label}'),
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: isDark
                    ? spec.color.withOpacity(0.15)
                    : spec.color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: spec.color.withOpacity(isDark ? 0.35 : 0.20),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: spec.color.withOpacity(isDark ? 0.25 : 0.12),
                    blurRadius: isDark ? 14 : 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(spec.icon, color: spec.color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              spec.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// FamilyRow
// ═══════════════════════════════════════════════════════════
class FamilyRow extends ConsumerWidget {
  const FamilyRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final uid = authState.user?.uid ?? '';
    final userDocAsync = uid.isNotEmpty
        ? ref.watch(userDocProvider(uid))
        : const AsyncValue<Map<String, dynamic>?>.data(null);
    final membersAsync = uid.isNotEmpty
        ? ref.watch(familyMembersProvider(uid))
        : const AsyncValue<List<Map<String, dynamic>>>.data([]);

    final userName = userDocAsync.valueOrNull?['name'] as String? ?? '';
    final selfInitial = userName.isNotEmpty ? userName[0].toUpperCase() : 'Y';
    final members = membersAsync.valueOrNull ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'MY FAMILY',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _FamilyMemberTile(
                member: _FamilyMember(
                  name: userName.isNotEmpty ? userName.split(' ').first : 'You',
                  initials: selfInitial,
                  isActive: true,
                ),
              ),
              ...members.map((m) {
                final name = m['name'] as String? ?? '';
                final relation = m['relation'] as String? ?? name.split(' ').first;
                final displayName = relation.isNotEmpty ? relation : name.split(' ').first;
                final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                return GestureDetector(
                  onTap: () => context.push(AppRoutes.familyMemberDetail, extra: m),
                  child: _FamilyMemberTile(
                    member: _FamilyMember(name: displayName, initials: initial),
                  ),
                );
              }),
              // Add button
              GestureDetector(
                onTap: () {
                  final currentUid = ref.read(authProvider).user?.uid
                      ?? FirebaseAuth.instance.currentUser?.uid
                      ?? '';
                  showAddFamilyMemberSheet(context, ref, currentUid);
                },
                child: Container(
                  width: 60,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary,
                            width: 1.5,
                            strokeAlign: BorderSide.strokeAlignOutside,
                          ),
                          color: AppColors.primary.withOpacity(0.06),
                        ),
                        child: const Icon(Icons.add_rounded, color: AppColors.primary, size: 26),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Add',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FamilyMember {
  final String name;
  final String initials;
  final bool isActive;
  const _FamilyMember({required this.name, required this.initials, this.isActive = false});
}

class _FamilyMemberTile extends StatelessWidget {
  final _FamilyMember member;
  const _FamilyMemberTile({required this.member});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: member.isActive
                      ? AppColors.primaryGradient
                      : const LinearGradient(
                          colors: [Color(0xFFE1BEE7), Color(0xFFF8BBD0)]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (member.isActive ? AppColors.primary : const Color(0xFFAB47BC))
                          .withOpacity(0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    member.initials,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: member.isActive ? Colors.white : AppColors.primary,
                    ),
                  ),
                ),
              ),
              // Active checkmark badge
              if (member.isActive)
                Positioned(
                  bottom: -1,
                  right: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 2,
                      ),
                    ),
                    child: const Icon(Icons.check_rounded, size: 10, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            member.isActive ? 'You' : member.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: member.isActive
                  ? AppColors.primary
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// NotificationStrip
// ═══════════════════════════════════════════════════════════
class NotificationStrip extends ConsumerStatefulWidget {
  const NotificationStrip({super.key});
  @override
  ConsumerState<NotificationStrip> createState() => _NotificationStripState();
}

class _NotificationStripState extends ConsumerState<NotificationStrip> {
  int _current = 0;
  bool _done = false;

  static const _periodStrip = _Strip(
    icon: Icons.favorite_rounded,
    color: Color(0xFFC2185B),
    bg: Color(0xFFFCE4EC),
    title: 'Period Tracker 🌸',
    sub: 'Next cycle expected in 5 days',
    ctaLabel: 'View',
    route: '/health/period',
  );

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authProvider).user?.uid ?? '';
    final userDoc = uid.isNotEmpty
        ? ref.watch(userDocProvider(uid))
        : const AsyncValue<Map<String, dynamic>?>.data(null);
    final isMale = (userDoc.valueOrNull?['gender'] as String? ?? '').toLowerCase() == 'male';

    final strips = [
      const _Strip(
        icon: Icons.water_drop_rounded,
        color: Color(0xFF1565C0),
        bg: Color(0xFFE3F2FD),
        title: 'Drink Water! 💧',
        sub: 'You haven\'t had water in 2 hours',
        ctaLabel: 'Mark Done',
        route: '/health/water',
      ),
      if (!isMale) _periodStrip,
      const _Strip(
        icon: Icons.lightbulb_rounded,
        color: Color(0xFFF57F17),
        bg: Color(0xFFFFF8E1),
        title: 'Health Tip 💡',
        sub: 'Walk 10 mins after every meal',
        ctaLabel: 'Learn More',
        route: '/education',
      ),
    ];

    final safeIndex = _current.clamp(0, strips.length - 1);

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if (d.primaryVelocity! < 0) {
          setState(() { _current = (safeIndex + 1) % strips.length; _done = false; });
        } else {
          setState(() { _current = (safeIndex - 1 + strips.length) % strips.length; _done = false; });
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _StripTile(
          strip: strips[safeIndex],
          onDone: () => setState(() => _done = true),
          key: ValueKey(safeIndex),
        ),
      ),
    );
  }
}

class _Strip {
  final IconData icon;
  final Color color;
  final Color bg;
  final String title;
  final String sub;
  final String ctaLabel;
  final String route;
  const _Strip({
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.sub,
    required this.ctaLabel,
    required this.route,
  });
}

class _StripTile extends StatelessWidget {
  final _Strip strip;
  final VoidCallback onDone;
  const _StripTile({required this.strip, required this.onDone, super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => context.push(strip.route),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? strip.color.withOpacity(0.12)
              : strip.bg,
          borderRadius: BorderRadius.circular(16),
          border: isDark
              ? Border.all(color: strip.color.withOpacity(0.25), width: 1)
              : Border(left: BorderSide(color: strip.color, width: 4)),
          boxShadow: isDark
              ? [BoxShadow(color: strip.color.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: strip.color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(strip.icon, color: strip.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strip.title,
                      style: AppTextStyles.labelLarge.copyWith(color: strip.color, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(strip.sub, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                if (strip.ctaLabel == 'Mark Done') {
                  onDone();
                } else {
                  context.push(strip.route);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: strip.color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  strip.ctaLabel,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// ServiceGrid  (centered scale carousel — circular)
// ═══════════════════════════════════════════════════════════
class ServiceGrid extends StatefulWidget {
  const ServiceGrid({super.key});
  @override
  State<ServiceGrid> createState() => _ServiceGridState();
}

class _ServiceGridState extends State<ServiceGrid> {
  late final PageController _controller;
  double _currentPage = 0;

  static const int _virtualCount = 12000;

  static final _services = [
    _Service('Emergency',   Icons.emergency_rounded,         AppColors.emergencyGrad,   AppRoutes.emergency,     null,      'Immediate 24/7 help for medical emergencies',  'Call Now'),
    _Service('Appointment', Icons.calendar_month_rounded,    AppColors.appointmentGrad, AppRoutes.appointment,   'FAST',    'Book with top specialists near you instantly',  'Book Slot'),
    _Service('Medicine',    Icons.medication_liquid_rounded, AppColors.medicineGrad,    AppRoutes.medicine,      '20% OFF', 'Order medicines delivered to your doorstep',    'Order Now'),
    _Service('Consult',     Icons.video_call_rounded,        AppColors.consultGrad,     AppRoutes.consultation,  null,      'Video & chat consultations with doctors',        'Connect'),
    _Service('Pregnancy',   Icons.pregnant_woman_rounded,    AppColors.pregnancyGrad,   AppRoutes.pregnancy,     'NEW',     'Track your pregnancy journey week by week',      'Track Now'),
    _Service('Diagnostics', Icons.science_rounded,           AppColors.diagnosticGrad,  AppRoutes.diagnostics,   null,      'Book lab tests & home sample collection',        'Book Test'),
    _Service('Care Assist', Icons.support_agent_rounded,     AppColors.careAssistGrad,  AppRoutes.careAssistant, null,      'AI-powered health assistant at your service',    'Try Now'),
    _Service('Ambulance',   Icons.local_shipping_rounded,    AppColors.ambulanceGrad,   AppRoutes.ambulance,     null,      'Emergency ambulance at your location',           'Call Now'),
    _Service('Physio',      Icons.fitness_center_rounded,    AppColors.physioGrad,      AppRoutes.physio,        null,      'Physiotherapy & rehabilitation at home',          'Book Now'),
    _Service('Nutrition',   Icons.restaurant_rounded,        AppColors.nutritionGrad,   AppRoutes.nutrition,     null,      'Personalised diet plans from nutritionists',      'Get Plan'),
    _Service('Therapy',     Icons.psychology_rounded,        AppColors.counselGrad,     AppRoutes.counselling,   null,      'Mental health support & therapy sessions',        'Book Now'),
    _Service('Equipment',   Icons.medical_services_rounded,  AppColors.equipmentGrad,   AppRoutes.equipment,     null,      'Rent or buy medical equipment online',            'Browse'),
    _Service('Caregivers',  Icons.elderly_rounded,           AppColors.caregiverGrad,   AppRoutes.caregivers,    null,      'Trained attendants & caregiver support',          'Hire Now'),
  ];

  int get _count => _services.length;
  int get _initialPage => (_virtualCount ~/ 2 ~/ _count) * _count;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.62, initialPage: _initialPage);
    _currentPage = _initialPage.toDouble();
    _controller.addListener(() {
      if (mounted) setState(() => _currentPage = _controller.page ?? _currentPage);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeReal = _currentPage.round() % _count;
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _controller,
            itemCount: _virtualCount,
            itemBuilder: (_, i) {
              final realIndex = i % _count;
              final dist = (_currentPage - i).abs().clamp(0.0, 1.0);
              final scale = 0.82 + 0.18 * (1 - dist);
              final isCenter = dist < 0.5;
              return Transform.scale(
                scale: scale,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: _ServiceCarouselCard(
                    service: _services[realIndex],
                    isCenter: isCenter,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_count, (i) {
            final active = activeReal == i;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 5,
              height: 5,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _Service {
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final String route;
  final String? badge;
  final String description;
  final String buttonLabel;
  const _Service(
    this.label, this.icon, this.gradient, this.route,
    this.badge, this.description, this.buttonLabel,
  );
}

class _ServiceCarouselCard extends StatelessWidget {
  final _Service service;
  final bool isCenter;
  const _ServiceCarouselCard({required this.service, required this.isCenter});

  @override
  Widget build(BuildContext context) {
    final baseColor = service.gradient.colors.first;

    return GestureDetector(
      onTap: () => context.push(service.route),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: service.gradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: isCenter
              ? [
                  BoxShadow(
                    color: baseColor.withOpacity(0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Decorative ECG-like line for Emergency
              if (service.label == 'Emergency')
                Positioned(
                  bottom: 50, left: 0, right: 0,
                  child: CustomPaint(
                    size: const Size(double.infinity, 30),
                    painter: _EcgLinePainter(),
                  ),
                ),
              Positioned(
                top: -20, right: -20,
                child: Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: isCenter ? 44 : 34,
                          height: isCenter ? 44 : 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            service.icon,
                            color: Colors.white,
                            size: isCenter ? 24 : 18,
                          ),
                        ),
                        const Spacer(),
                        if (service.badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.28),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              service.badge!,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      service.label,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isCenter ? 16 : 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    if (isCenter) ...[
                      const SizedBox(height: 3),
                      Text(
                        service.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          color: Colors.white70,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (service.label == 'Emergency' || service.label == 'Ambulance')
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(Icons.phone_rounded, size: 10, color: baseColor),
                                ),
                              Text(
                                service.buttonLabel,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: baseColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Simple ECG line painter for Emergency card
class _EcgLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    final w = size.width;
    final h = size.height;
    path.moveTo(0, h / 2);
    path.lineTo(w * 0.2, h / 2);
    path.lineTo(w * 0.28, h * 0.1);
    path.lineTo(w * 0.35, h * 0.9);
    path.lineTo(w * 0.42, h * 0.1);
    path.lineTo(w * 0.48, h / 2);
    path.lineTo(w, h / 2);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════
// UpcomingAppointmentCard
// ═══════════════════════════════════════════════════════════
class UpcomingAppointmentCard extends StatelessWidget {
  const UpcomingAppointmentCard({super.key});

  // Parses both ISO 'yyyy-MM-dd' and display 'EEE, d MMM yyyy' formats.
  DateTime? _parseDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    // Try ISO first (fast path, most appointments)
    try {
      return DateTime.parse(dateStr);
    } catch (_) {}
    // Fallback: display format stored by older consultation booking
    final formats = [
      DateFormat('EEE, d MMM yyyy'),
      DateFormat('EEE, dd MMM yyyy'),
      DateFormat('d MMM yyyy'),
    ];
    for (final fmt in formats) {
      try {
        return fmt.parse(dateStr);
      } catch (_) {}
    }
    return null;
  }

  String _formatDate(String dateStr) {
    final d = _parseDate(dateStr);
    if (d == null) return dateStr;
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    if (d.year == today.year && d.month == today.month && d.day == today.day) {
      return 'Today';
    } else if (d.year == tomorrow.year && d.month == tomorrow.month && d.day == tomorrow.day) {
      return 'Tomorrow';
    }
    return DateFormat('d MMM yyyy').format(d);
  }

  DateTime? _parseAppointmentDateTime(String dateStr, String timeStr) {
    final date = _parseDate(dateStr);
    if (date == null) return null;
    if (timeStr.isEmpty) return date;
    // Handle "HH:MM AM/PM" or "HH:MM" formats
    final cleaned = timeStr.trim().toUpperCase();
    final isPm = cleaned.endsWith('PM');
    final isAm = cleaned.endsWith('AM');
    final timePart =
        cleaned.replaceAll('AM', '').replaceAll('PM', '').trim();
    final parts = timePart.split(':');
    int hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    if (isPm && hour != 12) hour += 12;
    if (isAm && hour == 12) hour = 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return _buildEmpty(context);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('patientId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _buildSkeleton(context);
        }

        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day);

        // Keep only booked appointments whose date is today or in the future.
        // We intentionally match the Appointments screen behaviour: date-only
        // comparison so today's appointments stay visible all day regardless
        // of whether their scheduled time has already passed.
        final docs = (snap.data?.docs ?? []).where((d) {
          final data = d.data();
          if (data['status'] != 'booked') return false;
          final dateStr = data['date'] as String? ?? '';
          if (dateStr.isEmpty) return false;
          final parsed = _parseDate(dateStr);
          if (parsed == null) return false;
          final apptDate = DateTime(parsed.year, parsed.month, parsed.day);
          return !apptDate.isBefore(todayStart);
        }).toList();

        if (docs.isEmpty) {
          return _buildEmpty(context);
        }

        // Sort ascending by datetime, pick the nearest upcoming one
        docs.sort((a, b) {
          final aData = a.data();
          final bData = b.data();
          final aDt = _parseAppointmentDateTime(
                aData['date'] as String? ?? '',
                aData['time'] as String? ?? '') ??
              DateTime(9999);
          final bDt = _parseAppointmentDateTime(
                bData['date'] as String? ?? '',
                bData['time'] as String? ?? '') ??
              DateTime(9999);
          return aDt.compareTo(bDt);
        });

        final data = docs.first.data();
        final doctorName = data['doctorName'] as String? ?? 'Doctor';
        final specialty = data['doctorSpecialty'] as String? ?? '';
        final dateStr = data['date'] as String? ?? '';
        final time = data['time'] as String? ?? '';
        final type = data['consultationType'] as String? ?? 'Video';
        final displayDate = _formatDate(dateStr);
        final isVideo = type == 'Video';

        return _buildCard(
          context,
          doctorName: doctorName,
          specialty: specialty,
          displayDate: displayDate,
          time: time,
          isVideo: isVideo,
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String doctorName,
    required String specialty,
    required String displayDate,
    required String time,
    required bool isVideo,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Doctor avatar
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFF8BBD0), Color(0xFFE1BEE7)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.person_rounded,
                  color: AppColors.primary, size: 34),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doctorName, style: AppTextStyles.labelLarge),
                if (specialty.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(specialty, style: AppTextStyles.bodySmall),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    _InfoChip(
                      icon: Icons.calendar_today_outlined,
                      label: displayDate,
                      color: AppColors.primary,
                    ),
                    if (time.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _InfoChip(
                        icon: Icons.access_time_rounded,
                        label: time,
                        color: AppColors.secondary,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Action button
          GestureDetector(
            onTap: () => context.push(
                isVideo ? AppRoutes.consultation : AppRoutes.appointment),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVideo
                        ? Icons.videocam_rounded
                        : Icons.arrow_forward_ios_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isVideo ? 'Join' : 'View',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.doctors),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.calendar_today_outlined,
                  color: AppColors.primary, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No Upcoming Appointments',
                      style: AppTextStyles.labelLarge),
                  const SizedBox(height: 4),
                  Text('Book a consultation with a doctor',
                      style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Book',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    height: 14,
                    width: 120,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 8),
                Container(
                    height: 11,
                    width: 90,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 10),
                Container(
                    height: 24,
                    width: 150,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: AppTextStyles.caption.copyWith(
                  color: color, fontWeight: FontWeight.w700, fontSize: 10)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// HealthTipCard — Wide Story Cards
// ═══════════════════════════════════════════════════════════
class _HealthTip {
  final String category;
  final String title;
  final String sub;
  final IconData icon;
  final List<Color> gradient;

  const _HealthTip({
    required this.category,
    required this.title,
    required this.sub,
    required this.icon,
    required this.gradient,
  });
}

const _kHealthTips = [
  _HealthTip(
    category: 'Hydration',
    title: 'Stay Hydrated',
    sub: 'Drink 8 glasses daily to keep your body at peak performance.',
    icon: Icons.water_drop_rounded,
    gradient: [Color(0xFF1565C0), Color(0xFF1E88E5), Color(0xFF42A5F5)],
  ),
  _HealthTip(
    category: 'Fitness',
    title: 'Exercise Daily',
    sub: '30 minutes of movement boosts immunity and lifts your mood.',
    icon: Icons.directions_run_rounded,
    gradient: [Color(0xFF2E7D32), Color(0xFF43A047), Color(0xFF66BB6A)],
  ),
  _HealthTip(
    category: 'Sleep',
    title: 'Sleep Well',
    sub: '7–8 hours of quality sleep restores and repairs your body.',
    icon: Icons.bedtime_rounded,
    gradient: [Color(0xFF4A148C), Color(0xFF7B1FA2), Color(0xFFAB47BC)],
  ),
  _HealthTip(
    category: 'Nutrition',
    title: 'Eat Healthy',
    sub: 'Fresh fruits and veggies fuel your energy all day long.',
    icon: Icons.eco_rounded,
    gradient: [Color(0xFFE65100), Color(0xFFF57C00), Color(0xFFFF8A65)],
  ),
  _HealthTip(
    category: 'Mindfulness',
    title: 'Manage Stress',
    sub: '10 minutes of meditation a day reduces cortisol significantly.',
    icon: Icons.self_improvement_rounded,
    gradient: [Color(0xFF00695C), Color(0xFF00897B), Color(0xFF4DB6AC)],
  ),
  _HealthTip(
    category: 'Prevention',
    title: 'Regular Checkup',
    sub: 'Annual health screenings catch problems before they start.',
    icon: Icons.health_and_safety_rounded,
    gradient: [Color(0xFFB71C1C), Color(0xFFC62828), Color(0xFFEF5350)],
  ),
];

class HealthTipCard extends StatefulWidget {
  const HealthTipCard({super.key});

  @override
  State<HealthTipCard> createState() => _HealthTipCardState();
}

class _HealthTipCardState extends State<HealthTipCard> {
  final PageController _pageController = PageController(viewportFraction: 0.88);
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _currentPage) setState(() => _currentPage = page);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 136,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _kHealthTips.length,
            padEnds: false,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final tip = _kHealthTips[index];
              return Padding(
                padding: EdgeInsets.only(
                  left: index == 0 ? 20 : 6,
                  right: index == _kHealthTips.length - 1 ? 20 : 6,
                ),
                child: _StoryTipCard(tip: tip),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_kHealthTips.length, (i) {
            final isActive = i == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              width: isActive ? 20 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isActive
                    ? _kHealthTips[_currentPage].gradient.first
                    : const Color(0xFFCFD8DC),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _StoryTipCard extends StatelessWidget {
  final _HealthTip tip;
  const _StoryTipCard({required this.tip});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: tip.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: tip.gradient.first.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // decorative blob top-right
          Positioned(
            top: -28,
            right: -28,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -18,
            right: 50,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          // content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                // icon container
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
                  ),
                  child: Icon(tip.icon, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                // text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          tip.category.toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        tip.title,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        tip.sub,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.88),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
