import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/router/app_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../../security/services/biometric_service.dart';
import '../../legal/screens/privacy_policy_screen.dart';
import '../../legal/screens/terms_of_service_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notifications = true;
  bool _waterReminder = true;
  bool _periodTracker = true;
  bool _medicineReminder = true;
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

  Future<void> _handleDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 28),
            SizedBox(width: 10),
            Text('Delete Account?'),
          ],
        ),
        content: const Text(
          'This action is permanent and cannot be undone.\n\n'
          'Deleting your account will:\n'
          '• Remove all your personal data\n'
          '• Cancel any pending appointments\n'
          '• Delete your health records\n'
          '• Remove your wallet balance\n\n'
          'Are you absolutely sure you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete Account', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final phoneController = TextEditingController();
    final reauthed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Verify Your Identity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'For security, we need to verify your identity before deleting your account.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            const Text('Confirm your phone number:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: user.phoneNumber ?? 'Your registered phone',
                prefixIcon: const Icon(Icons.phone_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Confirm Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (reauthed != true || !mounted) return;

    _showLoadingDialog('Deleting your account...');

    try {
      final uid = user.uid;
      final db = FirebaseFirestore.instance;

      await db.collection('users').doc(uid).update({
        'accountStatus': 'deleted',
        'deletedAt': FieldValue.serverTimestamp(),
        'deletionRequested': true,
      });

      await db.collection('deletion_requests').doc(uid).set({
        'userId': uid,
        'requestedAt': FieldValue.serverTimestamp(),
        'collections': [
          'patient_notifications',
          'appointments',
          'health_records',
          'wallet_transactions',
          'family_members',
        ],
        'status': 'pending',
      });

      await user.delete();

      if (mounted) {
        Navigator.of(context).pop();
        context.go(AppRoutes.login);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deleted. We\'re sorry to see you go.'),
            backgroundColor: AppColors.textSecondary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        String message = 'Failed to delete account. Please try again.';
        if (e.code == 'requires-recent-login') {
          message = 'Please log out and log back in before deleting your account.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please contact support.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
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
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Gradient header ───────────────────────────────
          SliverAppBar(
            expandedHeight: 160,
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
                    colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
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
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -10,
                      left: -20,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.18),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.35),
                                  width: 2,
                                ),
                                image: photoUrl.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(photoUrl),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: photoUrl.isEmpty
                                  ? const Icon(Icons.person_rounded,
                                      color: Colors.white, size: 28)
                                  : null,
                            ),
                            const SizedBox(width: 14),
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
                                    const SizedBox(height: 2),
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
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
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Settings content ──────────────────────────────
          SliverToBoxAdapter(
            child: ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                // Notifications
                _SectionHeader(
                  icon: Icons.notifications_rounded,
                  title: 'Notifications',
                  color: const Color(0xFF7B1FA2),
                ),
                const SizedBox(height: 8),
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
                ]),

                const SizedBox(height: 20),

                // Security
                _SectionHeader(
                  icon: Icons.security_rounded,
                  title: 'Security & Privacy',
                  color: const Color(0xFF1565C0),
                ),
                const SizedBox(height: 8),
                _SettingsCard(children: [
                  _loadingBiometric
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2))),
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
                      'Read our privacy policy', () {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
                  }),
                  const Divider(height: 1, indent: 62),
                  _NavTile(Icons.gavel_rounded, 'Terms of Service',
                      'Read our terms of service', () {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const TermsOfServiceScreen()));
                  }),
                ]),

                const SizedBox(height: 20),

                // Appearance
                _SectionHeader(
                  icon: Icons.palette_rounded,
                  title: 'Appearance',
                  color: const Color(0xFF00897B),
                ),
                const SizedBox(height: 8),
                _SettingsCard(children: [
                  _SwitchTile(
                    Icons.dark_mode_rounded,
                    'Dark Mode',
                    'Switch to dark theme',
                    ref.watch(themeProvider) == ThemeMode.dark,
                    (_) => ref.read(themeProvider.notifier).toggle(),
                    iconColor: const Color(0xFF37474F),
                  ),
                  const Divider(height: 1, indent: 62),
                  _NavTile(Icons.language_rounded, 'Language',
                      'English (Default)', () => context.push(AppRoutes.language)),
                ]),

                const SizedBox(height: 20),

                // Account
                _SectionHeader(
                  icon: Icons.manage_accounts_rounded,
                  title: 'Account',
                  color: AppColors.primary,
                ),
                const SizedBox(height: 8),
                _SettingsCard(children: [
                  _NavTile(Icons.person_outline_rounded, 'Edit Profile',
                      'Update name, email & photo',
                      () => context.push(AppRoutes.profile)),
                  const Divider(height: 1, indent: 62),
                  _NavTile(Icons.card_giftcard_rounded, 'Referral & Rewards',
                      'Invite friends and earn rewards',
                      () => context.push(AppRoutes.referral)),
                  const Divider(height: 1, indent: 62),
                  _NavTile(
                    Icons.delete_forever_rounded,
                    'Delete Account',
                    'Permanently remove your account and all data',
                    _handleDeleteAccount,
                    isDestructive: true,
                  ),
                ]),

                const SizedBox(height: 20),

                // Support
                _SectionHeader(
                  icon: Icons.help_rounded,
                  title: 'Support',
                  color: const Color(0xFFE65100),
                ),
                const SizedBox(height: 8),
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
                      queryParameters: {'subject': 'MedNu App Support'},
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
                  _NavTile(Icons.info_outline_rounded, 'About MedNu',
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

                const SizedBox(height: 28),

                // Sign Out
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
                        if (mounted) context.go(AppRoutes.login);
                      }
                    },
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error.withOpacity(0.5)),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: (supported ? const Color(0xFF1565C0) : AppColors.textHint)
                .withOpacity(0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.fingerprint_rounded,
              color: supported ? const Color(0xFF1565C0) : AppColors.textHint,
              size: 20),
        ),
        title: Text('Biometric Login', style: AppTextStyles.labelLarge),
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

// ── Settings card ─────────────────────────────────────────────────────────────
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: (iconColor ?? AppColors.primary).withOpacity(0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon,
              color: iconColor ?? AppColors.primary, size: 20),
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
  final bool isDestructive;
  final bool showChevron;
  const _NavTile(this.icon, this.title, this.subtitle, this.onTap,
      {this.isDestructive = false, this.showChevron = true});

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: (isDestructive ? AppColors.error : AppColors.primary)
                .withOpacity(0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon,
              color: isDestructive ? AppColors.error : AppColors.primary,
              size: 20),
        ),
        title: Text(
          title,
          style: AppTextStyles.labelLarge.copyWith(
              color: isDestructive ? AppColors.error : null),
        ),
        subtitle: Text(subtitle, style: AppTextStyles.caption),
        trailing: showChevron
            ? Icon(Icons.chevron_right_rounded,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.3),
                size: 20)
            : null,
      );
}
