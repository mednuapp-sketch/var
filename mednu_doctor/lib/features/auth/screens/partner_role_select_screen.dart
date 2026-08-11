import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../shared_core/models/app_role.dart';

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
  const PartnerRoleSelectScreen({super.key});

  /// The self-registerable roles, in the order they are offered.
  static const _selectableRoles = <AppRole>[
    AppRole.doctor,
    AppRole.lab,
    AppRole.pharmacy,
    AppRole.ambulance,
    AppRole.caregiver,
  ];

  void _onRoleTap(BuildContext context, AppRole role) {
    if (role == AppRole.doctor) {
      // Byte-identical to the pre-existing behaviour of the OTP screen's
      // "profile doesn't exist" branch.
      context.go(AppRoutes.register);
    } else {
      context.go(AppRoutes.partnerRoleRegister, extra: role);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Join MedNU',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How will you use MedNU?', style: AppTextStyles.h3),
              const SizedBox(height: 6),
              const Text(
                'Pick the service you are registering. Your application is '
                'reviewed by our team before your account goes live.',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 22),
              for (final role in _selectableRoles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RoleTile(
                    role: role,
                    onTap: () => _onRoleTap(context, role),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'You can only pick one service now. Additional services can be '
                'added to your account later by our team.',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Visual twin of `role_switcher_sheet.dart`'s `_RoleTile` — same card, icon
/// tile and label shape, so "choose a role" looks the same everywhere in the
/// app. Selection state is not modelled here: tapping navigates away.
class _RoleTile extends StatelessWidget {
  final AppRole role;
  final VoidCallback onTap;

  const _RoleTile({required this.role, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = role.accentColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(role.icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(role.label, style: AppTextStyles.labelLarge),
            ),
            Icon(Icons.chevron_right_rounded, color: color, size: 22),
          ],
        ),
      ),
    );
  }
}
