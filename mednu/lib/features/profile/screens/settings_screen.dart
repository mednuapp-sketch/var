import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/booking_reminder_service.dart';
import '../../../core/utils/r.dart';
import '../../auth/providers/auth_provider.dart';
import '../../my_services/services/my_services_service.dart';
import '../../security/services/biometric_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

String _reminderMinutesLabel(int minutes) {
  if (minutes < 60) return '$minutes minutes';
  final hours = minutes ~/ 60;
  return '$hours hour${hours > 1 ? 's' : ''}';
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notifications = true;
  bool _waterReminder = true;
  bool _periodTracker = true;
  bool _medicineReminder = true;
  bool _appointmentReminder = true;
  int  _appointmentReminderMinutes = 15;
  bool _biometric = false;
  bool _biometricSupported = false;
  bool _locationAccess = true;
  bool _loadingBiometric = true;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
    _loadAppVersion();
    _loadReminderSettings();
  }

  Future<void> _loadReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _appointmentReminder = prefs.getBool('booking_reminder_enabled') ?? true;
        _appointmentReminderMinutes = prefs.getInt('booking_reminder_minutes') ?? 15;
      });
    }
  }

  Future<void> _toggleAppointmentReminder(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('booking_reminder_enabled', value);
    if (mounted) setState(() => _appointmentReminder = value);
    if (!value) {
      await BookingReminderService.cancelAllReminders(uid);
    } else {
      try {
        final bookings = await MyServicesService.allBookingsStream().first;
        await BookingReminderService.syncReminders(uid, bookings, _appointmentReminderMinutes);
      } catch (_) {}
    }
  }

  Future<void> _setReminderMinutes(int minutes) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('booking_reminder_minutes', minutes);
    if (mounted) setState(() => _appointmentReminderMinutes = minutes);
    try {
      final bookings = await MyServicesService.allBookingsStream().first;
      await BookingReminderService.syncReminders(uid, bookings, minutes);
    } catch (_) {}
  }

  void _showTimingPicker(BuildContext context) {
    const options = [5, 10, 15, 30, 60, 120, 180];
    showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 20))),
        title: const Text(
          'Remind me before',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((m) {
            final label = _reminderMinutesLabel(m);
            final selected = _appointmentReminderMinutes == m;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.primary : null,
                  )),
              trailing: selected
                  ? Icon(Icons.check_circle_rounded, color: AppColors.primary, size: R.w(context, 20))
                  : null,
              onTap: () => Navigator.pop(ctx, m),
            );
          }).toList(),
        ),
      ),
    ).then((picked) {
      if (picked != null) _setReminderMinutes(picked);
    });
  }

  Future<void> _loadBiometricState() async {
    final enabled = await BiometricService.isBiometricEnabled();
    final supported = await BiometricService.isDeviceSupported();
    if (mounted) {
      setState(() {
        _biometric = enabled;
        _biometricSupported = supported;
        _loadingBiometric = false;
      });
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = 'v${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      if (mounted) setState(() => _appVersion = 'v1.0.0');
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final ok = await BiometricService.authenticate(
        reason: 'Verify your identity to enable biometric lock',
      );
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication failed — biometric lock not enabled'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }
    await BiometricService.setBiometricEnabled(value);
    if (mounted) {
      setState(() => _biometric = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'Biometric lock enabled' : 'Biometric lock disabled'),
          backgroundColor: value ? AppColors.success : AppColors.textSecondary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ignore: unused_element — kept for future use (account deletion flow)
  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 20))),
        content: Row(
          children: [
            SizedBox(
              width: R.w(context, 24),
              height: R.h(context, 24),
              child: const CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: R.w(context, 16)),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final uid = userAsync.value?.uid ?? '';
    final userDocAsync = ref.watch(userDocProvider(uid));
    final userName = userDocAsync.value?['name'] as String? ?? '';
    final userPhone = userAsync.value?.phoneNumber ?? '';
    final photoUrl = userDocAsync.value?['photoUrl'] as String? ?? '';

    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          // ── Gradient header ───────────────────────────────
          SliverAppBar(
            expandedHeight: R.h(context, 160),
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF33172C), Color(0xFF522546), Color(0xFF633058)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -30,
                      right: -30,
                      child: Container(
                        width: R.w(context, 130),
                        height: R.h(context, 130),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha:0.06),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -10,
                      left: -20,
                      child: Container(
                        width: R.w(context, 90),
                        height: R.h(context, 90),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha:0.05),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: constraints.maxHeight),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 52),
                                    R.p(context, 20), R.p(context, 16)),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: R.w(context, 56),
                                          height: R.h(context, 56),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white.withValues(alpha: 0.18),
                                            border: Border.all(
                                              color: Colors.white.withValues(alpha: 0.35),
                                              width: 2,
                                            ),
                                          ),
                                          child: ClipOval(
                                            child: photoUrl.isNotEmpty
                                                ? CachedNetworkImage(
                                                    imageUrl: photoUrl,
                                                    fit: BoxFit.cover,
                                                    width: R.w(context, 56),
                                                    height: R.h(context, 56),
                                                    errorWidget: (_, __, ___) => Icon(
                                                      Icons.person_rounded,
                                                      color: Colors.white,
                                                      size: R.w(context, 28),
                                                    ),
                                                  )
                                                : Icon(Icons.person_rounded,
                                                    color: Colors.white, size: R.w(context, 28)),
                                          ),
                                        ),
                                        SizedBox(width: R.w(context, 14)),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                userName.isNotEmpty ? userName : 'My Account',
                                                style: const TextStyle(
                                                  fontFamily: 'Poppins',
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (userPhone.isNotEmpty) ...[
                                                SizedBox(height: R.h(context, 2)),
                                                Text(
                                                  userPhone,
                                                  style: const TextStyle(
                                                    fontFamily: 'Poppins',
                                                    fontSize: 12,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () => context.push(AppRoutes.profile),
                                          child: Container(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: R.p(context, 12), vertical: R.p(context, 7)),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha:0.18),
                                              borderRadius: BorderRadius.circular(R.r(context, 20)),
                                              border: Border.all(
                                                color: Colors.white.withValues(alpha:0.3),
                                              ),
                                            ),
                                            child: const Text(
                                              'Edit Profile',
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Settings content ──────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 20),
                  R.p(context, 16), R.p(context, 32)),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Notifications
                const _SectionHeader(
                  icon: Icons.notifications_rounded,
                  title: 'Notifications',
                  color: Color(0xFF633058),
                ),
                SizedBox(height: R.h(context, 8)),
                _SettingsCard(children: [
                  _SwitchTile(Icons.notifications_rounded, 'Push Notifications',
                      'Receive alerts for appointments & orders', _notifications,
                      (v) => setState(() => _notifications = v)),
                  const Divider(height: 1, indent: 62),
                  _SwitchTile(Icons.water_drop_rounded, 'Water Reminder',
                      'Get reminded to drink water every 2 hours', _waterReminder,
                      (v) => setState(() => _waterReminder = v)),
                  const Divider(height: 1, indent: 62),
                  _SwitchTile(Icons.favorite_rounded, 'Period Tracker Alerts',
                      'Cycle and ovulation reminders', _periodTracker,
                      (v) => setState(() => _periodTracker = v)),
                  const Divider(height: 1, indent: 62),
                  _SwitchTile(Icons.medication_rounded, 'Medicine Reminders',
                      'Alerts for prescribed medicines', _medicineReminder,
                      (v) => setState(() => _medicineReminder = v)),
                  const Divider(height: 1, indent: 62),
                  _SwitchTile(
                    Icons.alarm_rounded,
                    'Appointment Reminders',
                    'Get notified before upcoming appointments & services',
                    _appointmentReminder,
                    _toggleAppointmentReminder,
                    iconColor: const Color(0xFFF9943B),
                  ),
                  if (_appointmentReminder) ...[
                    const Divider(height: 1, indent: 62),
                    _ReminderTimingTile(
                      minutes: _appointmentReminderMinutes,
                      onTap: () => _showTimingPicker(context),
                    ),
                  ],
                ]),

                SizedBox(height: R.h(context, 20)),

                // Security
                const _SectionHeader(
                  icon: Icons.security_rounded,
                  title: 'Security & Privacy',
                  color: Color(0xFF1565C0),
                ),
                SizedBox(height: R.h(context, 8)),
                _SettingsCard(children: [
                  _loadingBiometric
                      ? Padding(
                          padding: EdgeInsets.all(R.p(context, 16)),
                          child: Center(
                              child: SizedBox(
                                  width: R.w(context, 20),
                                  height: R.h(context, 20),
                                  child: const CircularProgressIndicator(strokeWidth: 2))),
                        )
                      : _BiometricTile(
                          enabled: _biometric,
                          supported: _biometricSupported,
                          onToggle: _toggleBiometric,
                        ),
                  const Divider(height: 1, indent: 62),
                  _SwitchTile(Icons.location_on_rounded, 'Location Access',
                      'Find nearby hospitals & pharmacies', _locationAccess,
                      (v) => setState(() => _locationAccess = v)),
                  const Divider(height: 1, indent: 62),
                  _NavTile(Icons.privacy_tip_rounded, 'Privacy Policy',
                      'Read our privacy policy',
                      () => context.push(AppRoutes.privacyPolicy)),
                  const Divider(height: 1, indent: 62),
                  _NavTile(Icons.gavel_rounded, 'Terms of Service',
                      'Read our terms of service',
                      () => context.push(AppRoutes.termsOfService)),
                ]),

                SizedBox(height: R.h(context, 20)),

                // Appearance
                const _SectionHeader(
                  icon: Icons.palette_rounded,
                  title: 'Appearance',
                  color: Color(0xFFF9943B),
                ),
                SizedBox(height: R.h(context, 8)),
                _SettingsCard(children: [
                  _SwitchTile(
                    Icons.dark_mode_rounded,
                    'Dark Mode',
                    'Switch to dark theme',
                    ref.watch(themeProvider) == ThemeMode.dark,
                    (_) => ref.read(themeProvider.notifier).toggle(),
                    iconColor: const Color(0xFF37474F),
                  ),
                ]),

                SizedBox(height: R.h(context, 20)),

                // Account
                const _SectionHeader(
                  icon: Icons.manage_accounts_rounded,
                  title: 'Account',
                  color: AppColors.primary,
                ),
                SizedBox(height: R.h(context, 8)),
                _SettingsCard(children: [
                  _NavTile(Icons.person_outline_rounded, 'Edit Profile',
                      'Update name, email & photo',
                      () => context.push(AppRoutes.profile)),
                  const Divider(height: 1, indent: 62),
                  _NavTile(Icons.card_giftcard_rounded, 'Referral & Rewards',
                      'Invite friends and earn rewards',
                      () => context.push(AppRoutes.referral)),
                ]),

                SizedBox(height: R.h(context, 20)),

                // Support
                const _SectionHeader(
                  icon: Icons.help_rounded,
                  title: 'Support',
                  color: Color(0xFFE65100),
                ),
                SizedBox(height: R.h(context, 8)),
                _SettingsCard(children: [
                  _NavTile(Icons.help_outline_rounded, 'Help & FAQ',
                      'Find answers to common questions',
                      () => context.push(AppRoutes.helpSupport)),
                  const Divider(height: 1, indent: 62),
                  _NavTile(Icons.chat_rounded, 'Contact Support',
                      'Email or call our support team', () async {
                    final uri = Uri(
                      scheme: 'mailto',
                      path: 'support@mednu.in',
                      queryParameters: {'subject': 'MedNU App Support'},
                    );
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  }),
                  const Divider(height: 1, indent: 62),
                  _NavTile(Icons.star_outline_rounded, 'Rate App',
                      'Rate us on Play Store', () async {
                    final uri = Uri.parse(
                        'https://play.google.com/store/apps/details?id=com.mednu.app');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }),
                  const Divider(height: 1, indent: 62),
                  _NavTile(Icons.info_outline_rounded, 'About MedNU',
                      'Mission, services & legal info',
                      () => context.push(AppRoutes.about)),
                  const Divider(height: 1, indent: 62),
                  _NavTile(
                    Icons.verified_outlined,
                    'App Version',
                    _appVersion.isEmpty ? 'Loading...' : _appVersion,
                    () {},
                    showChevron: false,
                  ),
                ]),

                SizedBox(height: R.h(context, 28)),

                // Sign Out
                SizedBox(
                  width: double.infinity,
                  height: R.h(context, 52),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(R.r(context, 20))),
                          title: const Text('Sign Out'),
                          content: const Text(
                              'Are you sure you want to sign out?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Sign Out'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && mounted) {
                        await FirebaseAuth.instance.signOut();
                        if (!mounted || !context.mounted) return;
                        context.go(AppRoutes.login);
                      }
                    },
                    icon: Icon(Icons.logout_rounded, size: R.w(context, 18)),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error.withValues(alpha:0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(R.r(context, 14))),
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Biometric tile ────────────────────────────────────────────────────────────
class _BiometricTile extends StatelessWidget {
  final bool enabled;
  final bool supported;
  final ValueChanged<bool> onToggle;
  const _BiometricTile(
      {required this.enabled, required this.supported, required this.onToggle});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: R.p(context, 16), vertical: R.p(context, 4)),
        leading: Container(
          width: R.w(context, 38),
          height: R.h(context, 38),
          decoration: BoxDecoration(
            color: (supported ? const Color(0xFF1565C0) : context.appTextHint)
                .withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(R.r(context, 11)),
          ),
          child: Icon(Icons.fingerprint_rounded,
              color: supported ? const Color(0xFF1565C0) : context.appTextHint,
              size: R.w(context, 20)),
        ),
        title: const Text('Biometric Login', style: AppTextStyles.labelLarge),
        subtitle: Text(
          supported
              ? 'Use fingerprint or face to unlock'
              : 'Not supported on this device',
          style: AppTextStyles.caption,
        ),
        trailing: Switch(
          value: enabled,
          onChanged: supported ? onToggle : null,
        ),
      );
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  const _SectionHeader(
      {required this.icon, required this.title, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: R.w(context, 28),
            height: R.h(context, 28),
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(R.r(context, 8)),
            ),
            child: Icon(icon, size: R.w(context, 15), color: color),
          ),
          SizedBox(width: R.w(context, 8)),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      );
}

// ── Settings card ─────────────────────────────────────────────────────────────
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(R.r(context, 16)),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(children: children),
      );
}

// ── Switch tile ───────────────────────────────────────────────────────────────
class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? iconColor;
  const _SwitchTile(this.icon, this.title, this.subtitle, this.value,
      this.onChanged, {this.iconColor});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: R.p(context, 16), vertical: R.p(context, 4)),
        leading: Container(
          width: R.w(context, 38),
          height: R.h(context, 38),
          decoration: BoxDecoration(
            color: (iconColor ?? AppColors.primary).withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(R.r(context, 11)),
          ),
          child: Icon(icon,
              color: iconColor ?? AppColors.primary, size: R.w(context, 20)),
        ),
        title: Text(title, style: AppTextStyles.labelLarge),
        subtitle: Text(subtitle, style: AppTextStyles.caption),
        trailing: Switch(value: value, onChanged: onChanged),
      );
}

// ── Nav tile ──────────────────────────────────────────────────────────────────
class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool showChevron;
  const _NavTile(this.icon, this.title, this.subtitle, this.onTap,
      {this.showChevron = true});

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(horizontal: R.p(context, 16), vertical: R.p(context, 4)),
        leading: Container(
          width: R.w(context, 38),
          height: R.h(context, 38),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(R.r(context, 11)),
          ),
          child: Icon(icon, color: AppColors.primary, size: R.w(context, 20)),
        ),
        title: Text(title, style: AppTextStyles.labelLarge),
        subtitle: Text(subtitle, style: AppTextStyles.caption),
        trailing: showChevron
            ? Icon(Icons.chevron_right_rounded,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.3),
                size: R.w(context, 20))
            : null,
      );
}

// ── Reminder timing tile ──────────────────────────────────────────────────────
class _ReminderTimingTile extends StatelessWidget {
  final int minutes;
  final VoidCallback onTap;
  const _ReminderTimingTile({required this.minutes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = '${_reminderMinutesLabel(minutes)} before';
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.symmetric(horizontal: R.p(context, 16), vertical: R.p(context, 4)),
      leading: Container(
        width: R.w(context, 38),
        height: R.h(context, 38),
        decoration: BoxDecoration(
          color: const Color(0xFFF9943B).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(R.r(context, 11)),
        ),
        child: Icon(Icons.schedule_rounded,
            color: const Color(0xFFF9943B), size: R.w(context, 20)),
      ),
      title: const Text('Reminder Timing', style: AppTextStyles.labelLarge),
      subtitle: Text(label, style: AppTextStyles.caption),
      trailing: Icon(Icons.chevron_right_rounded,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          size: R.w(context, 20)),
    );
  }
}
