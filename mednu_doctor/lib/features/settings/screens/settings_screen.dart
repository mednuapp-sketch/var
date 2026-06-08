import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../security/services/biometric_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricEnabled   = false;
  bool _deviceSupported    = false;
  bool _notifAppointments  = true;
  bool _notifConsultations = true;
  bool _notifPayments      = true;
  bool _loading = true;
  String _appVersion = '';

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

    if (mounted) {
      setState(() {
        _biometricEnabled   = enabled;
        _deviceSupported    = supported;
        _notifAppointments  = prefs.getBool('notif_appointments') ?? true;
        _notifConsultations = prefs.getBool('notif_consultations') ?? true;
        _notifPayments      = prefs.getBool('notif_payments') ?? true;
        _appVersion         = info != null ? '${info.version}+${info.buildNumber}' : '1.0.0';
        _loading            = false;
      });
    }
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
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // ── Gradient header ──────────────────────────────
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 130,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.pin,
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF880E4F),
                            Color(0xFFC2185B),
                            Color(0xFF7B1FA2)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: -20,
                            right: -20,
                            child: Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.06),
                              ),
                            ),
                          ),
                          SafeArea(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 52, 20, 16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.settings_rounded,
                                        color: Colors.white, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Settings',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: ListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    children: [
                      // ── Security ──────────────────────────────────────
                      _SectionHeader(
                          icon: Icons.security_rounded,
                          title: 'Security',
                          color: const Color(0xFF1565C0)),
                      const SizedBox(height: 8),
                      _SettingsCard(children: [
                        _BiometricTile(
                          enabled: _biometricEnabled,
                          supported: _deviceSupported,
                          onToggle: _toggleBiometric,
                        ),
                      ]),
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
                            )),
                          ]),
                        ),
                      const SizedBox(height: 20),

                      // ── Notifications ─────────────────────────────────
                      _SectionHeader(
                          icon: Icons.notifications_rounded,
                          title: 'Notifications',
                          color: const Color(0xFF7B1FA2)),
                      const SizedBox(height: 8),
                      _SettingsCard(children: [
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
                      ]),
                      const SizedBox(height: 20),

                      // ── About ─────────────────────────────────────────
                      _SectionHeader(
                          icon: Icons.info_rounded,
                          title: 'About',
                          color: const Color(0xFFE65100)),
                      const SizedBox(height: 8),
                      _SettingsCard(children: [
                        _SettingsTile(
                          icon: Icons.info_outline_rounded,
                          iconColor: AppColors.primary,
                          title: 'App Version',
                          trailing: Text(_appVersion,
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.textHint)),
                        ),
                        _divider(),
                        _SettingsTile(
                          icon: Icons.privacy_tip_outlined,
                          iconColor: const Color(0xFF1565C0),
                          title: 'Privacy Policy',
                          onTap: () => _openUrl('https://mednu.in/privacy-policy'),
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
                      const SizedBox(height: 28),

                      // ── Sign Out ───────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                                title: const Text('Sign Out'),
                                content: const Text(
                                    'Are you sure you want to sign out?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Sign Out'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true && mounted) {
                              await FirebaseAuth.instance.signOut();
                              if (mounted) context.go(AppRoutes.login);
                            }
                          },
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: const Text('Sign Out'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: BorderSide(
                                color: AppColors.error.withOpacity(0.5)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 56, endIndent: 16);
}

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
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
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

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(children: children),
      );
}

class _BiometricTile extends StatelessWidget {
  final bool enabled;
  final bool supported;
  final ValueChanged<bool> onToggle;
  const _BiometricTile({required this.enabled, required this.supported, required this.onToggle});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: (supported ? AppColors.primary : AppColors.textHint).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.fingerprint_rounded, color: supported ? AppColors.primary : AppColors.textHint, size: 22),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Biometric Lock', style: AppTextStyles.labelLarge),
        Text('Lock app when sent to background', style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
      ])),
      Switch(
        value: enabled,
        onChanged: supported ? onToggle : null,
        activeThumbColor: AppColors.primary,
        activeTrackColor: AppColors.primary.withOpacity(0.4),
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
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTextStyles.labelLarge),
        Text(subtitle, style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
      ])),
      Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.primary,
        activeTrackColor: AppColors.primary.withOpacity(0.4),
      ),
    ]),
  );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsTile({required this.icon, required this.iconColor, required this.title, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: iconColor, size: 20),
    ),
    title: Text(title, style: AppTextStyles.labelLarge),
    trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right_rounded, color: AppColors.textHint) : null),
  );
}
