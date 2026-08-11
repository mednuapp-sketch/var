import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/router/app_router.dart';
import '../../../shared_core/shared_core.dart';

/// Reuses `SharedSettingsScreen` (Shared Core) the same way Pharmacy's and
/// Ambulance's Settings screens do — every item is a genuinely working
/// action, not a placeholder row.
class CaregiverSettingsScreen extends StatefulWidget {
  const CaregiverSettingsScreen({super.key});

  @override
  State<CaregiverSettingsScreen> createState() => _CaregiverSettingsScreenState();
}

class _CaregiverSettingsScreenState extends State<CaregiverSettingsScreen> {
  bool _notifyNewVisits = true;
  bool _notifyReminders = true;
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
      _notifyNewVisits = prefs.getBool('caregiver_notif_visits') ?? true;
      _notifyReminders = prefs.getBool('caregiver_notif_reminders') ?? true;
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
              title: 'New visit alerts',
              subtitle: 'Get notified when a new visit is assigned',
              trailing: SettingsItemTrailing.toggle,
              toggleValue: _notifyNewVisits,
              onToggle: (v) {
                setState(() => _notifyNewVisits = v);
                _setPref('caregiver_notif_visits', v);
              },
            ),
            SettingsItemData(
              icon: Icons.alarm_outlined,
              title: 'Visit reminders',
              subtitle: 'Reminders 30 minutes before a scheduled visit',
              trailing: SettingsItemTrailing.toggle,
              toggleValue: _notifyReminders,
              onToggle: (v) {
                setState(() => _notifyReminders = v);
                _setPref('caregiver_notif_reminders', v);
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
