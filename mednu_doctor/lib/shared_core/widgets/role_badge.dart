import 'package:flutter/material.dart';
import '../../core/widgets/ux_widgets.dart';
import '../models/app_role.dart';

/// Compact "you're viewing this app as {role}" indicator. Built on the
/// existing [StatusBadge] widget rather than a new pill implementation, so
/// it matches every other badge already in the app.
class RoleBadge extends StatelessWidget {
  final AppRole role;
  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) => StatusBadge(
        label: role.label,
        color: role.accentColor,
        icon: role.icon,
      );
}
