import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/mednu_components.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../security/services/biometric_service.dart';
import '../models/hospital_profile.dart';
import '../providers/hospital_providers.dart';
import '../services/hospital_profile_service.dart';

/// Billing desk profile — edit pattern (tap-to-change avatar with upload
/// progress, validated fields, gradient-header section cards) mirroring
/// `DoctorProfileEditScreen`'s UX, but composed from this module's own
/// `PremiumCard`/`GradientButton`/`ux_widgets.dart` visual language (as
/// `HospitalAppointmentsScreen`/`HospitalPaymentsScreen` already are) rather
/// than Doctor's raw `Container`/`AppBar` styling.
///
/// Only `contactName`/`phone`/`photoUrl` are ever written here —
/// `hospitalId`/`hospitalName`/`status` are locked to this login by
/// firestore.rules' `hospital_profiles` update rule (a Director must change
/// those), so they render read-only.
class HospitalProfileScreen extends ConsumerStatefulWidget {
  const HospitalProfileScreen({super.key});

  @override
  ConsumerState<HospitalProfileScreen> createState() => _HospitalProfileScreenState();
}

class _HospitalProfileScreenState extends ConsumerState<HospitalProfileScreen> {
  final _contactNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _synced = false;
  bool _saving = false;
  String? _nameError;
  String? _phoneError;

  // Photo upload state
  File? _localImage;
  bool _uploading = false;
  double _uploadProgress = 0;
  String? _currentPhotoUrl;

  // Biometric lock state — device-local, independent of the profile stream.
  bool _biometricEnabled = false;
  bool _biometricSupported = false;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _contactNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _syncFromProfile(HospitalProfile profile) {
    if (_synced) return;
    _synced = true;
    _contactNameCtrl.text = profile.contactName;
    _phoneCtrl.text = profile.phone;
    _currentPhotoUrl = profile.photoUrl;
  }

  Future<void> _save(String uid) async {
    final nameError = Validators.name(_contactNameCtrl.text, label: 'Contact name');
    final phoneError = Validators.phone(_phoneCtrl.text);
    setState(() {
      _nameError = nameError;
      _phoneError = phoneError;
    });
    if (nameError != null || phoneError != null) return;

    setState(() => _saving = true);
    try {
      await HospitalProfileService.updateContactInfo(
        uid,
        contactName: _contactNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
      if (!mounted) return;
      FeedbackService.showSuccess(context, 'Profile updated');
    } catch (_) {
      if (mounted) FeedbackService.showError(context, "Couldn't save changes. Please try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Photo picker ──────────────────────────────────────────

  void _showPhotoOptions() {
    final hasPhoto = (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) || _localImage != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text('Desk Photo', style: AppTextStyles.h4),
              const SizedBox(height: 20),
              _PhotoSheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                color: AppColors.primary,
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 12),
              _PhotoSheetOption(
                icon: Icons.camera_alt_rounded,
                label: 'Take a Photo',
                color: AppColors.secondary,
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(ImageSource.camera);
                },
              ),
              if (hasPhoto) ...[
                const SizedBox(height: 12),
                _PhotoSheetOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove Photo',
                  color: AppColors.error,
                  onTap: () {
                    Navigator.pop(context);
                    _removePhoto();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final uid = HospitalProfileService.currentUid;
    if (uid == null) return;

    File? file;
    try {
      file = source == ImageSource.gallery
          ? await ImageUploadService.pickFromGallery()
          : await ImageUploadService.pickFromCamera();
    } catch (e) {
      if (!mounted) return;
      FeedbackService.showError(context, 'Could not open picker: ${e.toString().replaceAll('Exception: ', '')}');
      return;
    }
    if (file == null || !mounted) return;

    setState(() {
      _localImage = file;
      _uploading = true;
      _uploadProgress = 0;
    });

    try {
      final url = await ImageUploadService.uploadPartnerProfileImage(
        profileCollection: 'hospital_profiles',
        imageFile: file,
        uid: uid,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      await HospitalProfileService.updatePhotoUrl(uid, url);
      if (!mounted) return;
      setState(() {
        _currentPhotoUrl = url;
        _uploading = false;
      });
      FeedbackService.showSuccess(context, 'Profile photo updated!');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _localImage = null;
      });
      FeedbackService.showError(context, 'Upload failed: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  Future<void> _removePhoto() async {
    final uid = HospitalProfileService.currentUid;
    if (uid == null) return;

    setState(() => _uploading = true);
    try {
      await ImageUploadService.deletePartnerProfileImage(profileCollection: 'hospital_profiles', uid: uid);
      await HospitalProfileService.updatePhotoUrl(uid, '');
      if (!mounted) return;
      setState(() {
        _currentPhotoUrl = '';
        _localImage = null;
        _uploading = false;
      });
      FeedbackService.showSuccess(context, 'Profile photo removed.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      FeedbackService.showError(context, 'Remove failed: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ── Avatar widget ─────────────────────────────────────────

  Widget _buildAvatar() {
    final hasNetwork = _currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty;

    Widget imageCircle;
    if (_localImage != null) {
      imageCircle = CircleAvatar(radius: 45, backgroundImage: FileImage(_localImage!));
    } else if (hasNetwork) {
      imageCircle = CachedNetworkImage(
        imageUrl: _currentPhotoUrl!,
        imageBuilder: (_, imageProvider) => CircleAvatar(radius: 45, backgroundImage: imageProvider),
        placeholder: (_, __) => AppAvatar(name: _contactNameCtrl.text, size: 90),
        errorWidget: (_, __, ___) => AppAvatar(name: _contactNameCtrl.text, size: 90),
      );
    } else {
      imageCircle = AppAvatar(name: _contactNameCtrl.text, size: 90);
    }

    return GestureDetector(
      onTap: _uploading ? null : _showPhotoOptions,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(child: imageCircle),
              ),
              if (_uploading)
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        value: _uploadProgress > 0 ? _uploadProgress : null,
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
              if (!_uploading)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _uploading
                ? (_uploadProgress > 0
                    ? 'Uploading ${(_uploadProgress * 100).toStringAsFixed(0)}%...'
                    : 'Uploading...')
                : 'Tap to change photo',
            style: AppTextStyles.bodySmall.copyWith(
              color: _uploading ? AppColors.primary : AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(hospitalProfileProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.hospitalProfile,
      title: 'Hospital Profile',
      body: profileAsync.when(
        loading: () => const PageLoadingState(),
        error: (_, __) => const NetworkErrorState(),
        data: (profile) {
          if (profile == null) {
            return const AppEmptyState(
              icon: Icons.local_hospital_outlined,
              title: 'Profile not found',
              message: 'Complete registration to set up your billing desk profile.',
            );
          }
          _syncFromProfile(profile);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FadeInSlide(child: Center(child: _buildAvatar())),
              const SizedBox(height: 20),

              _sectionCard(
                icon: Icons.badge_rounded,
                title: 'Contact Details',
                children: [
                  _field('Contact Name', _contactNameCtrl, errorText: _nameError),
                  const SizedBox(height: 12),
                  _field('Phone', _phoneCtrl, type: TextInputType.phone, errorText: _phoneError),
                ],
              ),
              const SizedBox(height: 16),

              _sectionCard(
                icon: Icons.local_hospital_rounded,
                title: 'Linked Hospital',
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lock_rounded, size: 15, color: AppColors.textHint),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          profile.isLinked ? profile.hospitalName ?? 'Linked hospital' : 'Awaiting confirmation',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      StatusBadge(
                        label: profile.isActive ? 'Active' : 'Pending',
                        color: profile.isActive ? AppColors.success : AppColors.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Which hospital this billing desk represents, and whether it\'s live, '
                    'is set by our team once your application is reviewed.',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _sectionCard(
                icon: Icons.security_rounded,
                title: 'Security',
                children: [
                  _biometricRow(),
                  if (!_biometricSupported)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Your device does not support biometric authentication.',
                        style: AppTextStyles.caption,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              _sectionCard(
                icon: Icons.gavel_rounded,
                title: 'Legal & Account',
                children: [
                  _actionRow(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    onTap: () => _openUrl(AccountSettingsItems.privacyPolicyUrl),
                  ),
                  _actionRow(
                    icon: Icons.description_outlined,
                    label: 'Terms of Service',
                    onTap: () => _openUrl(AccountSettingsItems.termsUrl),
                  ),
                  _actionRow(
                    icon: Icons.logout_rounded,
                    label: 'Sign Out',
                    color: AppColors.error,
                    showChevron: false,
                    onTap: _signOut,
                  ),
                  _actionRow(
                    icon: Icons.delete_forever_outlined,
                    label: 'Delete Account',
                    subtitle: 'Request permanent deletion of your account and data',
                    color: AppColors.error,
                    showChevron: false,
                    onTap: () => AccountSettingsItems.confirmAndRequestDeletion(context, role: 'hospital'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              GradientButton(
                label: 'Save Changes',
                isLoading: _saving,
                onTap: () => _save(profile.uid),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType type = TextInputType.text,
    String? errorText,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.labelLarge),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: type,
            decoration: InputDecoration(errorText: errorText),
          ),
        ],
      );

  Widget _biometricRow() => Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (_biometricSupported ? AppColors.primary : AppColors.textHint).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.fingerprint_rounded,
              color: _biometricSupported ? AppColors.primary : AppColors.textHint,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Biometric Lock', style: AppTextStyles.labelLarge),
                Text('Lock app when sent to background', style: AppTextStyles.caption),
              ],
            ),
          ),
          Switch(
            value: _biometricEnabled,
            onChanged: _biometricSupported ? _toggleBiometric : null,
          ),
        ],
      );

  Future<void> _openUrl(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        FeedbackService.showError(context, 'Could not open the page. Please try again.');
      }
    } catch (_) {
      if (mounted) FeedbackService.showError(context, 'Could not open the page. Please try again.');
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
    await FirebaseAuth.instance.signOut();
    if (mounted) context.go(AppRoutes.login);
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? subtitle,
    Color color = AppColors.primary,
    bool showChevron = true,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: color == AppColors.error ? AppColors.error : null,
                        ),
                      ),
                      if (subtitle != null) Text(subtitle, style: AppTextStyles.caption),
                    ],
                  ),
                ),
                if (showChevron) const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
              ],
            ),
          ),
        ),
      );

  Widget _sectionCard({required IconData icon, required String title, required List<Widget> children}) {
    return PremiumCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primarySoft, AppColors.surfaceVariant],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title, style: AppTextStyles.h4),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ],
      ),
    );
  }
}

class _PhotoSheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PhotoSheetOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
}
