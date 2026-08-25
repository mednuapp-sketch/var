import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/feedback_service.dart';
import '../models/app_role.dart';
import '../navigation/role_menu.dart';
import '../providers/role_providers.dart';
import '../../features/auth/screens/partner_role_select_screen.dart';

/// Opens the production-grade role switcher bottom sheet.
///
/// Safe to call even for single-role accounts — it simply has nothing to
/// switch to, so callers should gate the trigger UI on
/// `roleEngineProvider.canSwitchRoles` rather than relying on this function
/// to no-op silently.
Future<void> showRoleSwitcherSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _RoleSwitcherSheet(),
  );
}

class _RoleSwitcherSheet extends ConsumerWidget {
  const _RoleSwitcherSheet();

  Future<void> _switchTo(
    BuildContext context,
    WidgetRef ref,
    AppRole role,
    AppRole current,
  ) async {
    if (role == current) {
      Navigator.of(context).pop();
      return;
    }
    if (ref.read(criticalOperationInProgressProvider)) {
      FeedbackService.show(
        context,
        'Finish your current call or task before switching roles.',
        type: FeedbackType.warning,
      );
      return;
    }

    ref.read(roleSwitchInProgressProvider.notifier).state = true;
    try {
      await ref.read(activeRoleProvider.notifier).switchTo(role);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      // Land on the new role's home destination — a role switch is a
      // context switch, not just a state flip, so the UI should actually
      // take the user there rather than leaving them on a screen that
      // belongs to the role they just left.
      final destination = buildMenuForRole(role);
      if (destination.isNotEmpty) context.go(destination.first.route);
    } finally {
      ref.read(roleSwitchInProgressProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(roleEngineProvider);
    final switching = ref.watch(roleSwitchInProgressProvider);

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const Text('Switch role', style: AppTextStyles.h3),
            const SizedBox(height: 4),
            const Text(
              'Your account, all your services in one place.',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 18),
            AbsorbPointer(
              absorbing: switching,
              child: AnimatedOpacity(
                opacity: switching ? 0.5 : 1,
                duration: const Duration(milliseconds: 150),
                child: Column(
                  children: [
                    for (final role in engine.roles)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RoleTile(
                          role: role,
                          selected: role == engine.activeRole,
                          onTap: () =>
                              _switchTo(context, ref, role, engine.activeRole),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (switching) ...[
              const SizedBox(height: 6),
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ],
            if (AppRole.values.any((r) =>
                r != AppRole.admin &&
                r != AppRole.doctor &&
                !engine.roles.contains(r))) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: switching
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PartnerRoleSelectScreen(
                            existingRoles: engine.roles.toSet(),
                          ),
                        ));
                      },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.divider,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.add_circle_outline_rounded,
                          color: AppColors.primary, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('Add another service',
                            style: AppTextStyles.labelLarge),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: AppColors.textHint, size: 20),
                    ],
                  ),
                ),
              ),
            ] else if (!engine.canSwitchRoles) ...[
              const SizedBox(height: 4),
              const Text(
                'More partner services will unlock here as your account is verified for them.',
                style: AppTextStyles.caption,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final AppRole role;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = role.accentColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : AppColors.divider,
            width: selected ? 1.4 : 1,
          ),
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
            if (selected)
              Icon(Icons.check_circle_rounded, color: color, size: 22),
          ],
        ),
      ),
    );
  }
}
