import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/mednu_components.dart';
import '../../../shared_core/shared_core.dart';
import '../../../shared_core/whatsapp/whatsapp_opt_in_service.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../security/services/biometric_service.dart';
import '../services/caregiver_profile_service.dart';

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
  bool _whatsappOptIn = false;
  String _appVersion = '';

  // Biometric lock state — device-local, independent of the profile stream.
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
      _notifyNewVisits = prefs.getBool('caregiver_notif_visits') ?? true;
      _notifyReminders = prefs.getBool('caregiver_notif_reminders') ?? true;
    });
  }

  Future<void> _loadWhatsAppOptIn() async {
    final uid = CaregiverProfileService.currentUid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('caregiver_profiles').doc(uid).get();
      if (mounted) setState(() => _whatsappOptIn = doc.data()?['whatsappOptIn'] == true);
    } catch (_) {}
  }

  Future<void> _toggleWhatsAppOptIn(bool value) async {
    final uid = CaregiverProfileService.currentUid;
    if (uid == null) return;
    setState(() => _whatsappOptIn = value);
    try {
      await WhatsAppOptInService.save(collection: 'caregiver_profiles', uid: uid, value: value);
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

  Future<void> _signOut() async {
    final confirmed = await MedNuConfirmationDialog.show(
      context,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      confirmLabel: 'Sign Out',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await DoctorAuthService.signOut();
      if (mounted) context.go(AppRoutes.login);
    } catch (e) {
      if (mounted) FeedbackService.showError(context, Validators.friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SharedSettingsScreen(
      title: 'Settings',
      headerIcon: Icons.settings_rounded,
      sections: [
        SettingsSectionData(
          title: 'Security',
          items: [
            SettingsItemData(
              icon: Icons.fingerprint_rounded,
              title: 'Biometric Lock',
              subtitle: _biometricSupported
                  ? 'Lock app when sent to background'
                  : 'Your device does not support biometric authentication.',
              trailing: SettingsItemTrailing.toggle,
              toggleValue: _biometricEnabled,
              onToggle: _biometricSupported ? _toggleBiometric : null,
            ),
          ],
        ),
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
            SettingsItemData(
              icon: Icons.chat_outlined,
              title: 'WhatsApp Notifications',
              subtitle: 'Get visit & payout updates on WhatsApp',
              trailing: SettingsItemTrailing.toggle,
              toggleValue: _whatsappOptIn,
              onToggle: _toggleWhatsAppOptIn,
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
            AccountSettingsItems.deleteAccount(context, role: 'caregiver'),
          ],
        ),
      ],
    );
  }
}
