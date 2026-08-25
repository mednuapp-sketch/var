import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import 'nav_item.dart';

/// Tablet/web-width side navigation rail, driven by the same [NavItem] list
/// used to render the mobile bottom nav — one source of truth for the menu
/// shape across form factors.
class AdaptiveSideRail extends StatelessWidget {
  final List<NavItem> items;
  final String currentRoute;
  final ValueChanged<NavItem> onSelect;
  final Widget? header;
  final Widget? footer;

  const AdaptiveSideRail({
    super.key,
    required this.items,
    required this.currentRoute,
    required this.onSelect,
    this.header,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final selectedIndex = items.indexWhere((i) => i.route == currentRoute);

    return Container(
      width: 220,
      color: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            if (header != null) header!,
            Expanded(
              child: NavigationRail(
                extended: true,
                minExtendedWidth: 220,
                backgroundColor: AppColors.surface,
                selectedIndex: selectedIndex < 0 ? null : selectedIndex,
                onDestinationSelected: (i) => onSelect(items[i]),
                selectedIconTheme: const IconThemeData(color: AppColors.primary),
                selectedLabelTextStyle: const TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
                unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
                unselectedLabelTextStyle: const TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.textSecondary,
                ),
                destinations: [
                  for (final item in items)
                    NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.activeIcon ?? item.icon),
                      label: Text(item.label),
                    ),
                ],
              ),
            ),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}

/// Convenience navigator: pushes [item.route] via `go_router` unless it's
/// already the current location.
void navigateToNavItem(BuildContext context, NavItem item, String currentRoute) {
  if (item.route == currentRoute) return;
  context.go(item.route);
}
