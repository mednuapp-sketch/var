import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/models/app_role.dart';
import 'partner_role_register_screen.dart';

/// First step of registration for a brand-new account: which partner service
/// is this account signing up as?
///
/// Before this screen existed, OTP verification for an account with no
/// `doctors/{uid}` document always routed straight to
/// [AppRoutes.register] — so every account in production was permanently a
/// Doctor. This screen is the branch point: Doctor keeps the exact existing
/// registration screen, every other role goes to the generic partner
/// registration form.
///
/// [AppRole.admin] is deliberately absent — an admin account is never
/// self-registerable from the partner app.
class PartnerRoleSelectScreen extends StatelessWidget {
  /// Non-empty when this screen is reached from an already-registered
  /// account adding a second service (via the role switcher sheet's "Add
  /// another service" action) rather than from OTP verification for a
  /// brand-new account. Roles already held — and Doctor, which needs its
  /// own full credential-verification flow, not this generic form — are
  /// filtered out of the list.
  final Set<AppRole> existingRoles;

  const PartnerRoleSelectScreen({super.key, this.existingRoles = const {}});

  bool get _isAddingToExistingAccount => existingRoles.isNotEmpty;

  /// The self-registerable roles, in the order they are offered.
  static const _allSelectableRoles = <AppRole>[
    AppRole.doctor,
    AppRole.lab,
    AppRole.pharmacy,
    AppRole.ambulance,
    AppRole.caregiver,
  ];

  List<AppRole> get _offeredRoles => _isAddingToExistingAccount
      ? _allSelectableRoles
          .where((r) => r != AppRole.doctor && !existingRoles.contains(r))
          .toList()
      : _allSelectableRoles;

  void _onRoleTap(BuildContext context, AppRole role) {
    if (role == AppRole.doctor) {
      // Byte-identical to the pre-existing behaviour of the OTP screen's
      // "profile doesn't exist" branch.
      context.go(AppRoutes.register);
    } else if (_isAddingToExistingAccount) {
      // Reached via Navigator.push from the role switcher sheet, not via
      // go_router — push the registration form the same way so "back"
      // returns to wherever the sheet was opened from.
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PartnerRoleRegisterScreen(role: role),
      ));
    } else {
      context.go(AppRoutes.partnerRoleRegister, extra: role);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = _offeredRoles;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _isAddingToExistingAccount ? 'Add a Service' : 'Join MedNU',
          style: AppTextStyles.h4.copyWith(color: Colors.white),
        ),
        automaticallyImplyLeading: _isAddingToExistingAccount,
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.heroBannerGradient,
          ),
        ),
      ),
      body: SafeArea(
        child: roles.isEmpty
            ? _EmptyState()
            : Stack(
                children: [
                  // Ambient depth — soft, low-alpha brand-colour washes fixed
                  // behind the scroll content. Cheap radial gradients rather
                  // than a real blur, so no BackdropFilter/repaint cost.
                  const Positioned(
                    top: -70,
                    right: -60,
                    child: _Blob(diameter: 240, color: AppColors.primarySoft),
                  ),
                  Positioned(
                    top: 210,
                    left: -70,
                    child: _Blob(
                      diameter: 170,
                      color: AppColors.accent.withValues(alpha: 0.10),
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FadeInSlide(
                          child: Text(
                            _isAddingToExistingAccount
                                ? 'ADD A SERVICE'
                                : 'GET STARTED',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: AppColors.accentText,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FadeInSlide(
                          delay: const Duration(milliseconds: 40),
                          child: Text(
                            _isAddingToExistingAccount
                                ? 'Pick another service to offer'
                                : 'How will you use MedNU?',
                            style: AppTextStyles.h2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FadeInSlide(
                          delay: const Duration(milliseconds: 80),
                          child: Text(
                            _isAddingToExistingAccount
                                ? 'Your existing services stay exactly as they are. '
                                    'The new one is reviewed by our team before it goes live.'
                                : 'Pick the service you are registering. Your application is '
                                    'reviewed by our team before your account goes live.',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 26),
                        // A static grid, not GridView — this screen's body is
                        // already a SingleChildScrollView, and a nested
                        // scrollable grid inside an outer scrollable installs
                        // a competing drag recognizer that stalls the outer
                        // scroll (see project notes on this recurring bug
                        // class). A trailing odd card spans full width as a
                        // single featured row instead of leaving a dangling
                        // half-empty row.
                        for (var i = 0; i < roles.length; i += 2)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: FadeInSlide(
                              delay: Duration(milliseconds: 120 + (i ~/ 2) * 70),
                              child: i + 1 < roles.length
                                  ? Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _RoleCard(
                                            role: roles[i],
                                            onTap: () => _onRoleTap(context, roles[i]),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: _RoleCard(
                                            role: roles[i + 1],
                                            onTap: () => _onRoleTap(context, roles[i + 1]),
                                          ),
                                        ),
                                      ],
                                    )
                                  : _RoleCard(
                                      role: roles[i],
                                      onTap: () => _onRoleTap(context, roles[i]),
                                      featured: true,
                                    ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        if (!_isAddingToExistingAccount)
                          FadeInSlide(
                            delay: const Duration(milliseconds: 260),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.info_outline_rounded,
                                      size: 17, color: AppColors.textSecondary),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'You can only pick one service now. Additional '
                                      'services can be added to your account later '
                                      'from Settings.',
                                      style: AppTextStyles.caption
                                          .copyWith(color: AppColors.textSecondary),
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
              ),
      ),
    );
  }
}

/// A soft, low-alpha radial glow used to give the otherwise flat background
/// a sense of depth — cheap (no ImageFilter blur) and purely decorative.
class _Blob extends StatelessWidget {
  final double diameter;
  final Color color;

  const _Blob({required this.diameter, required this.color});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.good, _deepen(AppColors.good)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.good.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: 20),
              const Text('You\'re all set', style: AppTextStyles.h3),
              const SizedBox(height: 6),
              Text(
                'Your account already offers every partner service.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
}

/// A darker second gradient stop, computed from a role's own accent colour
/// rather than hand-picked per role — a new [AppRole] never needs a
/// matching gradient added here by hand.
Color _deepen(Color c, [double amount = 0.16]) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

/// A lighter first gradient stop, same derivation as [_deepen] in reverse —
/// gives the card gradient a third stop so it reads as a considered surface
/// rather than a flat two-tone fill.
Color _lighten(Color c, [double amount = 0.08]) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

/// A premium, gradient icon card — the same visual language as the
/// dashboard's `GradientStatCard` (this app's established "this is a
/// serious, branded surface" treatment), reused here so the very first
/// screen a partner ever sees already looks like the rest of the app
/// instead of a plain settings-style list.
class _RoleCard extends StatelessWidget {
  final AppRole role;
  final VoidCallback onTap;

  /// True for a trailing odd card spanning the full grid width — laid out
  /// horizontally instead of stacked, so it reads as an intentional
  /// featured row rather than a half-empty last line.
  final bool featured;

  const _RoleCard({required this.role, required this.onTap, this.featured = false});

  @override
  Widget build(BuildContext context) {
    final color = role.accentColor;
    final gradient = LinearGradient(
      colors: [_lighten(color), color, _deepen(color, 0.18)],
      stops: const [0, 0.55, 1],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final decoration = BoxDecoration(
      gradient: gradient,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.35),
          blurRadius: 20,
          offset: const Offset(0, 10),
          spreadRadius: -4,
        ),
      ],
    );

    final iconBadge = Container(
      width: featured ? 52 : 46,
      height: featured ? 52 : 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Icon(role.icon, color: Colors.white, size: featured ? 26 : 23),
    );

    final arrowBadge = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 15),
    );

    final label = Text(
      role.label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.labelLarge.copyWith(
        fontSize: featured ? 16 : 15,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        height: 1.2,
      ),
    );

    final subtitle = Text(
      role.subtitle,
      maxLines: featured ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: Colors.white.withValues(alpha: 0.82),
      ),
    );

    return TapScale(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: decoration,
          child: Stack(
            children: [
              // A soft glossy highlight blob, the same restrained "premium
              // sheen" trick as the page's ambient background blobs, so the
              // card surface reads as glass rather than a flat fill.
              Positioned(
                right: -18,
                top: -26,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: featured
                    ? const EdgeInsets.fromLTRB(18, 16, 16, 16)
                    : const EdgeInsets.fromLTRB(16, 18, 14, 16),
                child: featured
                    ? Row(
                        children: [
                          iconBadge,
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                label,
                                const SizedBox(height: 3),
                                subtitle,
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          arrowBadge,
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [iconBadge, arrowBadge],
                          ),
                          const SizedBox(height: 16),
                          label,
                          const SizedBox(height: 3),
                          subtitle,
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
