import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/mednu_components.dart';
import '../../../shared_core/shared_core.dart';
import '../../../shared_core/whatsapp/whatsapp_opt_in_service.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../security/services/biometric_service.dart';
import '../services/lab_profile_service.dart';

class LabSettingsScreen extends StatefulWidget {
  const LabSettingsScreen({super.key});

  @override
  State<LabSettingsScreen> createState() => _LabSettingsScreenState();
}

class _LabSettingsScreenState extends State<LabSettingsScreen> {
  bool _notifyNewBookings = true;
  bool _notifySampleCollection = true;
  bool _whatsappOptIn = false;
  String _appVersion = '';

  // Biometric lock state — device-local, independent of the profile stream
  // (mirrors HospitalProfileScreen's _biometricEnabled/_biometricSupported).
  bool _biometricEnabled = false;
  bool _biometricSupported = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadVersion();
    _loadWhatsAppOptIn();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final enabled = await BiometricService.isBiometricEnabled();
    final supported = await BiometricService.isDeviceSupported();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enabled;
      _biometricSupported = supported;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final ok = await BiometricService.authenticate(
        reason: 'Verify your identity to enable biometric lock',
      );
      if (!ok) {
        if (mounted) {
          FeedbackService.showError(context, 'Authentication failed — biometric lock not enabled');
        }
        return;
      }
    }
    await BiometricService.setBiometricEnabled(value);
    if (!mounted) return;
    setState(() => _biometricEnabled = value);
    FeedbackService.showSuccess(context, value ? 'Biometric lock enabled' : 'Biometric lock disabled');
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifyNewBookings = prefs.getBool('lab_notif_new_bookings') ?? true;
      _notifySampleCollection = prefs.getBool('lab_notif_sample_collection') ?? true;
    });
  }

  Future<void> _loadWhatsAppOptIn() async {
    final uid = LabProfileService.currentUid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('lab_profiles').doc(uid).get();
      if (mounted) setState(() => _whatsappOptIn = doc.data()?['whatsappOptIn'] == true);
    } catch (_) {}
  }

  Future<void> _toggleWhatsAppOptIn(bool value) async {
    final uid = LabProfileService.currentUid;
    if (uid == null) return;
    setState(() => _whatsappOptIn = value);
    try {
      await WhatsAppOptInService.save(collection: 'lab_profiles', uid: uid, value: value);
    } catch (_) {
      if (mounted) setState(() => _whatsappOptIn = !value);
    }
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
      query: 'subject=Lab & Diagnostics Partner Support Request',
    );
    if (!await launchUrl(uri)) {
      if (mounted) FeedbackService.showError(context, 'Could not open your email app.');
    }
  }

  Future<void> _signOut() async {
    final confirmed = await MedNuConfirmationDialog.show(
      context,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      confirmLabel: 'Sign Out',
      destructive: true,
    );
    if (!confirmed) return;
    await DoctorAuthService.signOut();
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
              title: 'New booking alerts',
              subtitle: 'Get notified the instant a test booking comes in',
              trailing: SettingsItemTrailing.toggle,
              toggleValue: _notifyNewBookings,
              onToggle: (v) {
                setState(() => _notifyNewBookings = v);
                _setPref('lab_notif_new_bookings', v);
              },
            ),
            SettingsItemData(
              icon: Icons.local_shipping_outlined,
              title: 'Sample collection updates',
              subtitle: 'Reminders for samples awaiting pickup',
              trailing: SettingsItemTrailing.toggle,
              toggleValue: _notifySampleCollection,
              onToggle: (v) {
                setState(() => _notifySampleCollection = v);
                _setPref('lab_notif_sample_collection', v);
              },
            ),
            SettingsItemData(
              icon: Icons.chat_outlined,
              title: 'WhatsApp Notifications',
              subtitle: 'Get booking & payout updates on WhatsApp',
              trailing: SettingsItemTrailing.toggle,
              toggleValue: _whatsappOptIn,
              onToggle: _toggleWhatsAppOptIn,
            ),
          ],
        ),
        SettingsSectionData(
          title: 'Security',
          items: [
            SettingsItemData(
              icon: Icons.fingerprint_rounded,
              title: 'Biometric Lock',
              subtitle: _biometricSupported
                  ? 'Lock app when sent to background'
                  : 'Your device does not support biometric authentication',
              trailing: SettingsItemTrailing.toggle,
              toggleValue: _biometricEnabled,
              onToggle: _biometricSupported ? _toggleBiometric : null,
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
            ...AccountSettingsItems.legal(context),
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
            AccountSettingsItems.deleteAccount(context, role: 'lab'),
          ],
        ),
      ],
    );
  }
}
