import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/screens/partner_role_select_screen.dart';
import '../models/app_role.dart';
import '../providers/role_providers.dart';
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
class SharedSettingsScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(roleEngineProvider);
    final canAddService = AppRole.values.any(
      (r) => r != AppRole.admin && r != AppRole.doctor && !engine.roles.contains(r),
    );
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
                if (canAddService)
                  SharedSettingsSection(
                    data: SettingsSectionData(
                      title: 'Services',
                      items: [
                        SettingsItemData(
                          icon: Icons.add_circle_outline_rounded,
                          title: 'Add another service',
                          subtitle: 'Offer an additional service from this account',
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PartnerRoleSelectScreen(existingRoles: engine.roles.toSet()),
                          )),
                        ),
                      ],
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
