import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/router/app_router.dart';
import '../../../shared_core/shared_core.dart';

/// Reuses `SharedSettingsScreen` (Shared Core) the same way Pharmacy's
/// Settings screen does — every item is a genuinely working action, not a
/// placeholder row.
class AmbulanceSettingsScreen extends StatefulWidget {
  const AmbulanceSettingsScreen({super.key});

  @override
  State<AmbulanceSettingsScreen> createState() => _AmbulanceSettingsScreenState();
}

class _AmbulanceSettingsScreenState extends State<AmbulanceSettingsScreen> {
  bool _notifyNewRequests = true;
  bool _notifySoundAlert = true;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadVersion();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifyNewRequests = prefs.getBool('ambulance_notif_requests') ?? true;
      _notifySoundAlert = prefs.getBool('ambulance_notif_sound') ?? true;
    });
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _appVersion = '${info.version} (${info.buildNumber})');
  }

  Future<void> _setPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseAuth.instance.signOut();
    if (mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return SharedSettingsScreen(
      title: 'Settings',
      headerIcon: Icons.settings_rounded,
      sections: [
        SettingsSectionData(
          title: 'Notifications',
          items: [
            SettingsItemData(
              icon: Icons.notifications_active_outlined,
              title: 'New request alerts',
              subtitle: 'Get notified the instant a request comes in',
              trailing: SettingsItemTrailing.toggle,
              toggleValue: _notifyNewRequests,
              onToggle: (v) {
                setState(() => _notifyNewRequests = v);
                _setPref('ambulance_notif_requests', v);
              },
            ),
            SettingsItemData(
              icon: Icons.volume_up_outlined,
              title: 'Sound alert',
              subtitle: 'Play a siren tone for emergency requests',
              trailing: SettingsItemTrailing.toggle,
              toggleValue: _notifySoundAlert,
              onToggle: (v) {
                setState(() => _notifySoundAlert = v);
                _setPref('ambulance_notif_sound', v);
              },
            ),
          ],
        ),
        SettingsSectionData(
          title: 'About',
          items: [
            SettingsItemData(
              icon: Icons.info_outline_rounded,
              title: 'App Version',
              trailing: SettingsItemTrailing.value,
              valueText: _appVersion.isEmpty ? '—' : _appVersion,
            ),
          ],
        ),
        SettingsSectionData(
          title: 'Account',
          items: [
            SettingsItemData(
              icon: Icons.logout_rounded,
              title: 'Sign Out',
              destructive: true,
              trailing: SettingsItemTrailing.none,
              onTap: _signOut,
            ),
          ],
        ),
      ],
    );
  }
}
