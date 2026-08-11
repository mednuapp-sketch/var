import 'package:flutter/material.dart';
import '../../core/widgets/ux_widgets.dart';
import 'settings_models.dart';
import 'settings_widgets.dart';

/// Generic, composable settings screen shell.
///
/// This does **not** replace `features/settings/screens/settings_screen.dart`
/// — the existing `/settings` route and screen are untouched and remain the
/// live doctor settings UI. This is available for a future prompt to either
/// wire the Doctor module's existing sections into (for a cheap visual
/// refresh) or to give a new role (ambulance/pharmacy/lab/caregiver) its own
/// settings screen built from the same reusable tiles.
class SharedSettingsScreen extends StatelessWidget {
  final String title;
  final IconData headerIcon;
  final String? headerSubtitle;
  final List<SettingsSectionData> sections;

  const SharedSettingsScreen({
    super.key,
    required this.title,
    required this.sections,
    this.headerIcon = Icons.settings_rounded,
    this.headerSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          GradientSliverAppBar(
            headerIcon: headerIcon,
            title: title,
            subtitle: headerSubtitle,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                for (final section in sections) SharedSettingsSection(data: section),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
