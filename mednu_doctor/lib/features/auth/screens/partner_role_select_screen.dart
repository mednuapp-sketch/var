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
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.heroBannerGradient,
          ),
        ),
      ),
      body: SafeArea(
        child: roles.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 48),
                      const SizedBox(height: 14),
                      Text(
                        'Your account already offers every partner service.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium,
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isAddingToExistingAccount
                          ? 'Pick another service to offer'
                          : 'How will you use MedNU?',
                      style: AppTextStyles.h3,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isAddingToExistingAccount
                          ? 'Your existing services stay exactly as they are. '
                              'The new one is reviewed by our team before it goes live.'
                          : 'Pick the service you are registering. Your application is '
                              'reviewed by our team before your account goes live.',
                      style: AppTextStyles.bodyMedium,
                    ),
                    const SizedBox(height: 22),
                    // A static 2-column grid, not GridView — this screen's
                    // body is already a SingleChildScrollView, and a nested
                    // scrollable grid inside an outer scrollable installs a
                    // competing drag recognizer that stalls the outer scroll
                    // (see project notes on this recurring bug class).
                    for (var i = 0; i < roles.length; i += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
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
                              child: i + 1 < roles.length
                                  ? _RoleCard(
                                      role: roles[i + 1],
                                      onTap: () => _onRoleTap(context, roles[i + 1]),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (!_isAddingToExistingAccount)
                      Text(
                        'You can only pick one service now. Additional services can be '
                        'added to your account later from Settings.',
                        style: AppTextStyles.caption,
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// A premium, gradient icon card — the same visual language as the
/// dashboard's `GradientStatCard` (this app's established "this is a
/// serious, branded surface" treatment), reused here so the very first
/// screen a partner ever sees already looks like the rest of the app
/// instead of a plain settings-style list.
class _RoleCard extends StatelessWidget {
  final AppRole role;
  final VoidCallback onTap;

  const _RoleCard({required this.role, required this.onTap});

  /// A darker second gradient stop, computed from the role's own accent
  /// colour rather than hand-picked per role — a new [AppRole] never needs
  /// a matching gradient added here by hand.
  Color _deepen(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.16).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final color = role.accentColor;
    return TapScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 14, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, _deepen(color)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.32),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(role.icon, color: Colors.white, size: 24),
                ),
                Icon(Icons.arrow_forward_rounded,
                    color: Colors.white.withValues(alpha: 0.8), size: 18),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              role.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelLarge.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
