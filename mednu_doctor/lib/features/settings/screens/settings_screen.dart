import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/appointment_reminder_service.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../security/services/biometric_service.dart';
import '../../../core/widgets/ux_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricEnabled      = false;
  bool _deviceSupported       = false;
  bool _notifAppointments     = true;
  bool _notifConsultations    = true;
  bool _notifPayments         = true;
  int  _apptReminderMinutes   = 15;
  bool _loading = true;
  String _appVersion = '';
  String? _doctorName;
  String? _doctorSpecialty;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final enabled   = await BiometricService.isBiometricEnabled();
    final supported = await BiometricService.isDeviceSupported();
    final prefs     = await SharedPreferences.getInstance();
    PackageInfo? info;
    try { info = await PackageInfo.fromPlatform(); } catch (_) {}

    final uid = DoctorAuthService.currentUid;
    if (uid != null) {
      try {
        final profile = await DoctorAuthService.getProfile(uid);
        if (mounted) {
          setState(() {
            _doctorName     = profile?['name'] as String?;
            _doctorSpecialty = profile?['specialty'] as String?;
          });
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _biometricEnabled     = enabled;
        _deviceSupported      = supported;
        _notifAppointments    = prefs.getBool('notif_appointments') ?? true;
        _notifConsultations   = prefs.getBool('notif_consultations') ?? true;
        _notifPayments        = prefs.getBool('notif_payments') ?? true;
        _apptReminderMinutes  = prefs.getInt('appt_reminder_minutes') ?? 15;
        _appVersion           = info != null ? '${info.version}+${info.buildNumber}' : '1.0.0';
        _loading              = false;
      });
    }
  }

  Future<void> _setApptReminderMinutes(int minutes) async {
    await AppointmentReminderService.setReminderMinutes(minutes);
    if (mounted) setState(() => _apptReminderMinutes = minutes);
  }

  void _showReminderTimingPicker() {
    const options = [5, 10, 15, 30, 60];
    showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remind me before',
          style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((m) {
            final label    = m >= 60 ? '1 hour' : '$m minutes';
            final selected = _apptReminderMinutes == m;
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
                  ? const Icon(Icons.check_circle_rounded,
                      color: AppColors.primary, size: 20)
                  : null,
              onTap: () => Navigator.pop(ctx, m),
            );
          }).toList(),
        ),
      ),
    ).then((picked) {
      if (picked != null) _setApptReminderMinutes(picked);
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final ok = await BiometricService.authenticate(
        reason: 'Verify your identity to enable biometric lock',
      );
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Authentication failed — biometric lock not enabled'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
    }
    await BiometricService.setBiometricEnabled(value);
    if (mounted) {
      setState(() => _biometricEnabled = value);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(value ? 'Biometric lock enabled' : 'Biometric lock disabled'),
        backgroundColor: value ? AppColors.success : AppColors.textSecondary,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _setNotifPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showUrlError();
      }
    } catch (_) {
      _showUrlError();
    }
  }

  void _showUrlError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Could not open the page. Please try again.'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.error,
    ));
  }

  Future<void> _rateApp() async {
    const packageName = 'com.mednu.mednuDoctor';
    final marketUri = Uri.parse('market://details?id=$packageName');
    final webUri = Uri.parse(
        'https://play.google.com/store/apps/details?id=$packageName');
    try {
      if (await canLaunchUrl(marketUri)) {
        await launchUrl(marketUri);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      _showUrlError();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? _buildSkeleton()
          : CustomScrollView(
              slivers: [
                // ── Gradient App Bar ─────────────────────────
                const GradientSliverAppBar(
                  headerIcon: Icons.settings_rounded,
                  title: 'Settings',
                  subtitle: 'Preferences & account',
                ),

                // ── Doctor Profile Card ──────────────────────
                SliverToBoxAdapter(
                  child: FadeInSlide(
                    child: _DoctorProfileCard(
                      name: _doctorName,
                      specialty: _doctorSpecialty,
                    ),
                  ),
                ),

                // ── Settings List ────────────────────────────
                // A plain Column, not a shrink-wrapped ListView: a nested
                // scrollable inside this CustomScrollView installs a
                // competing drag recognizer and stalls upward swipes.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                      // ── Security ──────────────────────────────────────
                      const FadeInSlide(
                        delay: Duration(milliseconds: 60),
                        child: _SectionHeader(
                          icon: Icons.security_rounded,
                          title: 'Security',
                          color: Color(0xFF1565C0),
                        ),
                      ),
                      FadeInSlide(
                        delay: const Duration(milliseconds: 80),
                        child: _SettingsCard(children: [
                          _BiometricTile(
                            enabled: _biometricEnabled,
                            supported: _deviceSupported,
                            onToggle: _toggleBiometric,
                          ),
                        ]),
                      ),
                      if (!_deviceSupported)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                          child: Row(children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 14, color: AppColors.textHint),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Your device does not support biometric authentication.',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.textHint),
                              ),
                            ),
                          ]),
                        ),
                      const SizedBox(height: 20),

                      // ── Notifications ─────────────────────────────────
                      const FadeInSlide(
                        delay: Duration(milliseconds: 100),
                        child: _SectionHeader(
                          icon: Icons.notifications_rounded,
                          title: 'Notifications',
                          color: AppColors.secondary,
                        ),
                      ),
                      FadeInSlide(
                        delay: const Duration(milliseconds: 120),
                        child: _SettingsCard(children: [
                          _ToggleTile(
                            icon: Icons.calendar_month_rounded,
                            iconColor: const Color(0xFF1565C0),
                            title: 'Appointment Reminders',
                            subtitle: 'Upcoming appointment alerts',
                            value: _notifAppointments,
                            onChanged: (v) {
                              setState(() => _notifAppointments = v);
                              _setNotifPref('notif_appointments', v);
                            },
                          ),
                          _divider(),
                          _ToggleTile(
                            icon: Icons.video_call_rounded,
                            iconColor: AppColors.primary,
                            title: 'Consultation Requests',
                            subtitle: 'New patient request alerts',
                            value: _notifConsultations,
                            onChanged: (v) {
                              setState(() => _notifConsultations = v);
                              _setNotifPref('notif_consultations', v);
                            },
                          ),
                          _divider(),
                          _ToggleTile(
                            icon: Icons.account_balance_wallet_rounded,
                            iconColor: AppColors.success,
                            title: 'Payment Updates',
                            subtitle: 'Earnings & payout notifications',
                            value: _notifPayments,
                            onChanged: (v) {
                              setState(() => _notifPayments = v);
                              _setNotifPref('notif_payments', v);
                            },
                          ),
                          _divider(),
                          _SettingsTile(
                            icon: Icons.schedule_rounded,
                            iconColor: const Color(0xFF1565C0),
                            title: 'Reminder Timing',
                            trailing: Text(
                              _apptReminderMinutes >= 60
                                  ? '1 hour before'
                                  : '$_apptReminderMinutes min before',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textHint),
                            ),
                            onTap: _showReminderTimingPicker,
                          ),
                        ]),
                      ),
                      const SizedBox(height: 20),

                      // ── Help & Support ────────────────────────────────
                      const FadeInSlide(
                        delay: Duration(milliseconds: 140),
                        child: _SectionHeader(
                          icon: Icons.support_rounded,
                          title: 'Support',
                          color: Color(0xFF00695C),
                        ),
                      ),
                      FadeInSlide(
                        delay: const Duration(milliseconds: 160),
                        child: _SettingsCard(children: [
                          _SettingsTile(
                            icon: Icons.help_outline_rounded,
                            iconColor: const Color(0xFF00695C),
                            title: 'Help & FAQ',
                            onTap: () => context.push(AppRoutes.helpSupport),
                          ),
                          _divider(),
                          _SettingsTile(
                            icon: Icons.bug_report_outlined,
                            iconColor: AppColors.warning,
                            title: 'Report a Problem',
                            onTap: () => context.push(AppRoutes.reportProblem),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 20),

                      // ── About ─────────────────────────────────────────
                      const FadeInSlide(
                        delay: Duration(milliseconds: 180),
                        child: _SectionHeader(
                          icon: Icons.info_rounded,
                          title: 'About',
                          color: Color(0xFFE65100),
                        ),
                      ),
                      FadeInSlide(
                        delay: const Duration(milliseconds: 200),
                        child: _SettingsCard(children: [
                          _SettingsTile(
                            icon: Icons.info_outline_rounded,
                            iconColor: AppColors.primary,
                            title: 'App Version',
                            trailing: Text(
                              _appVersion,
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textHint),
                            ),
                          ),
                          _divider(),
                          _SettingsTile(
                            icon: Icons.privacy_tip_outlined,
                            iconColor: const Color(0xFF1565C0),
                            title: 'Privacy Policy',
                            onTap: () =>
                                _openUrl('https://mednu.in/privacy-policy'),
                          ),
                          _divider(),
                          _SettingsTile(
                            icon: Icons.description_outlined,
                            iconColor: const Color(0xFF2E7D32),
                            title: 'Terms of Service',
                            onTap: () => _openUrl('https://mednu.in/terms'),
                          ),
                          _divider(),
                          _SettingsTile(
                            icon: Icons.star_outline_rounded,
                            iconColor: const Color(0xFFF57F17),
                            title: 'Rate the App',
                            onTap: _rateApp,
                          ),
                        ]),
                      ),
                      const SizedBox(height: 28),

                      // ── Sign Out ───────────────────────────────────────
                      FadeInSlide(
                        delay: const Duration(milliseconds: 220),
                        child: _SignOutButton(
                          onConfirmed: () async {
                            final router = GoRouter.of(context);
                            await FirebaseAuth.instance.signOut();
                            if (!mounted) return;
                            router.go(AppRoutes.login);
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 160, 16, 16),
      child: Column(
        children: [
          const SkeletonBox(
              width: double.infinity, height: 80, radius: 18),
          const SizedBox(height: 20),
          ...List.generate(
            5,
            (_) => const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: SkeletonBox(
                  width: double.infinity, height: 56, radius: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      const Divider(height: 1, indent: 56, endIndent: 16);
}

// ──────────────────────────────────────────────────────────────
// Doctor Profile Card
// ──────────────────────────────────────────────────────────────

class _DoctorProfileCard extends StatelessWidget {
  final String? name;
  final String? specialty;

  const _DoctorProfileCard({this.name, this.specialty});

  @override
  Widget build(BuildContext context) {
    final displayName = name ?? 'Doctor';
    final displaySpec = specialty ?? 'General Physician';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.32),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.4), width: 2),
          ),
          child: Center(
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'D',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dr. $displayName',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                displaySpec,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.verified_rounded,
                      size: 10, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Verified Doctor',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Section Header
// ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  const _SectionHeader(
      {required this.icon, required this.title, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 8),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      );
}

// ──────────────────────────────────────────────────────────────
// Settings Card Container
// ──────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(children: children),
      );
}

// ──────────────────────────────────────────────────────────────
// Tiles
// ──────────────────────────────────────────────────────────────

class _BiometricTile extends StatelessWidget {
  final bool enabled;
  final bool supported;
  final ValueChanged<bool> onToggle;
  const _BiometricTile(
      {required this.enabled,
      required this.supported,
      required this.onToggle});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (supported ? AppColors.primary : AppColors.textHint)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.fingerprint_rounded,
                color: supported ? AppColors.primary : AppColors.textHint,
                size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Biometric Lock', style: AppTextStyles.labelLarge),
              Text(
                'Lock app when sent to background',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textHint),
              ),
            ]),
          ),
          Switch(
            value: enabled,
            onChanged: supported ? onToggle : null,
          ),
        ]),
      );
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title, style: AppTextStyles.labelLarge),
              Text(
                subtitle,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textHint),
              ),
            ]),
          ),
          Switch(value: value, onChanged: onChanged),
        ]),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsTile(
      {required this.icon,
      required this.iconColor,
      required this.title,
      this.trailing,
      this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(title, style: AppTextStyles.labelLarge),
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textHint, size: 20)
                : null),
      );
}

// ──────────────────────────────────────────────────────────────
// Sign Out Button
// ──────────────────────────────────────────────────────────────

class _SignOutButton extends StatelessWidget {
  final VoidCallback onConfirmed;
  const _SignOutButton({required this.onConfirmed});

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: () => _confirm(context),
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: Colors.red.shade400, size: 20),
            const SizedBox(width: 10),
            Text(
              'Sign Out',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirm == true) onConfirmed();
  }
}
