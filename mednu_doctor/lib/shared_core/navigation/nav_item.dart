import 'package:flutter/material.dart';

/// A single destination in a role's navigation menu (bottom nav, drawer, or
/// tablet side rail). Pure data — no widget/route-builder logic lives here,
/// so this can be generated once per role and rendered by whichever shell
/// component is on screen.
@immutable
class NavItem {
  final String label;
  final IconData icon;
  final IconData? activeIcon;

  /// A `go_router` path, typically one of the existing `AppRoutes` constants
  /// in `core/router/app_router.dart`. Kept as a plain string here (rather
  /// than importing `AppRoutes` into this generic model) so this file has no
  /// dependency on any particular role's route table.
  final String route;

  const NavItem({
    required this.label,
    required this.icon,
    required this.route,
    this.activeIcon,
  });
}
