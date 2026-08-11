import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../shared_core/shared_core.dart';

/// First real consumer of `SharedSettingsScreen`/`SettingsSectionData` from
/// Shared Core — every item here is a genuinely working action (no
/// placeholder rows): local notification prefs actually persist, sign-out
/// actually signs out, support actually opens an email compose sheet.
class PharmacySettingsScreen extends StatefulWidget {
  const PharmacySettingsScreen({super.key});

  @override
  State<PharmacySettingsScreen> createState() => _PharmacySettingsScreenState();
}

class _PharmacySettingsScreenState extends State<PharmacySettingsScreen> {
  bool _notifyNewOrders = true;
  bool _notifyDeliveryUpdates = true;
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
      _notifyNewOrders = prefs.getBool('pharmacy_notif_new_orders') ?? true;
      _notifyDeliveryUpdates = prefs.getBool('pharmacy_notif_delivery') ?? true;
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

  Future<void> _contactSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@mednu.in',
      query: 'subject=Pharmacy Partner Support Request',
    );
    if (!await launchUrl(uri)) {
      if (mounted) FeedbackService.showError(context, 'Could not open your email app.');
    }
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
              title: 'New order alerts',
              subtitle: 'Get notified the instant an order comes in',
              trailing: SettingsItemTrailing.toggle,
              toggleValue: _notifyNewOrders,
              onToggle: (v) {
                setState(() => _notifyNewOrders = v);
                _setPref('pharmacy_notif_new_orders', v);
              },
            ),
            SettingsItemData(
              icon: Icons.local_shipping_outlined,
              title: 'Delivery updates',
              subtitle: 'Reminders for orders awaiting dispatch',
              trailing: SettingsItemTrailing.toggle,
              toggleValue: _notifyDeliveryUpdates,
              onToggle: (v) {
                setState(() => _notifyDeliveryUpdates = v);
                _setPref('pharmacy_notif_delivery', v);
              },
            ),
          ],
        ),
        SettingsSectionData(
          title: 'Support',
          items: [
            SettingsItemData(
              icon: Icons.support_agent_rounded,
              title: 'Contact Support',
              subtitle: 'support@mednu.in',
              onTap: _contactSupport,
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
