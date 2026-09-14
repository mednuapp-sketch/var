import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/r.dart';
import '../../core/router/app_router.dart';
import '../navigation/adaptive_side_rail.dart';
import '../navigation/nav_item.dart';
import '../navigation/role_menu.dart';
import '../models/app_role.dart';
import '../notifications/shared_notification_providers.dart';
import '../providers/current_user_provider.dart';
import '../providers/role_providers.dart';
import 'profile_avatar.dart';
import 'role_badge.dart';
import 'role_switcher_sheet.dart';

/// Reusable, role-aware app shell for future partner modules.
///
/// This is net-new: `DashboardScreen` (the current Doctor app shell) is
/// untouched and keeps rendering exactly as before. [SharedAppShell] is
/// scaffolding for Prompt 3+ to build on — a module opts into it by wrapping
/// its own body, it doesn't replace anything today.
///
/// Adapts between a phone layout (top bar + bottom nav) and a
/// tablet/web layout (top bar + side rail) using [R.isTablet].
class SharedAppShell extends ConsumerWidget {
  final Widget body;
  final String currentRoute;
  final String title;
  final List<Widget>? extraActions;
  final Widget? floatingActionButton;

  /// Set to `false` when [body] already owns its own bottom
  /// navigation/tab-switching (e.g. the Doctor dashboard's `IndexedStack`
  /// tabs) — the shell then contributes only the top app bar (role badge,
  /// notification bell, profile avatar) and leaves navigation entirely to
  /// the caller, so there is never a second, conflicting nav surface.
  final bool showBottomNav;

  const SharedAppShell({
    super.key,
    required this.body,
    required this.currentRoute,
    required this.title,
    this.extraActions,
    this.floatingActionButton,
    this.showBottomNav = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(roleEngineProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final unread = ref.watch(sharedUnreadCountProvider);
    final items = showBottomNav ? buildMenuForRole(engine.activeRole) : const <NavItem>[];
    final isTablet = R.isTablet(context);

    final appBar = _ShellAppBar(
      title: title,
      role: engine.activeRole,
      canSwitchRoles: engine.canSwitchRoles,
      unreadCount: unread,
      userName: user?.name ?? '',
      photoUrl: user?.photoUrl,
      isVerified: user?.isVerified ?? false,
      extraActions: extraActions,
    );

    if (isTablet && items.isNotEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        body: Row(
          children: [
            AdaptiveSideRail(
              items: items,
              currentRoute: currentRoute,
              onSelect: (item) => navigateToNavItem(context, item, currentRoute),
            ),
            const VerticalDivider(width: 1, color: AppColors.divider),
            Expanded(
              child: SafeArea(top: false, child: body),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: appBar,
      resizeToAvoidBottomInset: true,
      floatingActionButton: floatingActionButton,
      // Only wrap in a bottom-safe-area when the shell itself owns the
      // bottom nav below `body`. When `showBottomNav` is false, `body` is
      // expected to manage its own safe areas (e.g. the Doctor dashboard's
      // own Scaffold + bottom nav already does) — an extra SafeArea here
      // would double up the bottom inset and leave a visible gap under it.
      body: showBottomNav ? SafeArea(top: false, child: body) : body,
      bottomNavigationBar: items.isEmpty
          ? null
          : _ShellBottomNav(
              items: items,
              currentRoute: currentRoute,
              onSelect: (item) => navigateToNavItem(context, item, currentRoute),
            ),
    );
  }
}

/// The profile screen each role's avatar tap should open. Doctor is the only
/// role with a dedicated *edit* screen ([AppRoutes.editProfile]) — every
/// other role edits in place on its own profile screen, so the avatar must
/// route there instead of falling through to the Doctor screen.
String _profileRouteForRole(AppRole role) {
  switch (role) {
    case AppRole.doctor:
      return AppRoutes.editProfile;
    case AppRole.lab:
      return AppRoutes.labProfile;
    case AppRole.pharmacy:
      return AppRoutes.pharmacyProfile;
    case AppRole.ambulance:
      return AppRoutes.ambulanceVehicleProfile;
    case AppRole.caregiver:
      return AppRoutes.caregiverProfile;
    case AppRole.physiotherapist:
      return AppRoutes.physioProfile;
    case AppRole.counsellor:
      return AppRoutes.counsellingProfile;
    case AppRole.nutritionist:
      return AppRoutes.nutritionProfile;
    case AppRole.hospital:
      // No dedicated profile screen for this role (see role_menu.dart) — the
      // avatar just routes to Payments, one of its nav destinations.
      return AppRoutes.hospitalPayments;
    case AppRole.admin:
      return AppRoutes.editProfile;
  }
}

class _ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final AppRole role;
  final bool canSwitchRoles;
  final int unreadCount;
  final String userName;
  final String? photoUrl;
  final bool isVerified;
  final List<Widget>? extraActions;

  const _ShellAppBar({
    required this.title,
    required this.role,
    required this.canSwitchRoles,
    required this.unreadCount,
    required this.userName,
    required this.photoUrl,
    required this.isVerified,
    required this.extraActions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 16,
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              style: AppTextStyles.h4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (canSwitchRoles) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => showRoleSwitcherSheet(context),
              child: RoleBadge(role: role),
            ),
          ],
        ],
      ),
      actions: [
        ...?extraActions,
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: AppColors.textPrimary),
              onPressed: () => context.go(AppRoutes.notifications),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        GestureDetector(
          onTap: () => context.go(_profileRouteForRole(role)),
          child: Padding(
            padding: const EdgeInsets.only(right: 16, left: 4),
            child: SharedProfileAvatar(
              name: userName,
              photoUrl: photoUrl,
              size: 34,
              isVerified: isVerified,
            ),
          ),
        ),
      ],
    );
  }
}

class _ShellBottomNav extends StatelessWidget {
  final List<NavItem> items;
  final String currentRoute;
  final ValueChanged<NavItem> onSelect;

  const _ShellBottomNav({
    required this.items,
    required this.currentRoute,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final selectedIndex = items.indexWhere((i) => i.route == currentRoute);
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++)
              Expanded(
                child: _BottomNavIcon(
                  item: items[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelect(items[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavIcon extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _BottomNavIcon({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? (item.activeIcon ?? item.icon) : item.icon, color: color, size: 23),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
