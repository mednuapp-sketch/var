import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../location/models/precise_address.dart';
import '../../location/screens/map_location_picker_screen.dart';
import '../providers/pharmacy_providers.dart';
import '../services/pharmacy_profile_service.dart';

class PharmacyProfileScreen extends ConsumerStatefulWidget {
  const PharmacyProfileScreen({super.key});

  @override
  ConsumerState<PharmacyProfileScreen> createState() => _PharmacyProfileScreenState();
}

class _PharmacyProfileScreenState extends ConsumerState<PharmacyProfileScreen> {
  bool _editing = false;
  bool _saving = false;
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  double? _addressLat;
  double? _addressLng;
  String _addressCity = '';
  final _phoneCtrl = TextEditingController();

  // Photo upload state — updates independently of the text-field edit mode,
  // same as `HospitalProfileScreen`.
  bool _photoSynced = false;
  File? _localImage;
  bool _uploading = false;
  double _uploadProgress = 0;
  String? _currentPhotoUrl;

  void _syncPhoto(String photoUrl) {
    if (_photoSynced) return;
    _photoSynced = true;
    _currentPhotoUrl = photoUrl;
  }

  Future<void> _pickAddress() async {
    final result = await Navigator.of(context).push<PreciseAddress>(
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(initialLat: _addressLat, initialLng: _addressLng),
      ),
    );
    if (result == null) return;
    setState(() {
      _addressCtrl.text = result.formatted;
      _addressLat = result.lat;
      _addressLng = result.lng;
      _addressCity = result.city ?? '';
    });
  }

  Future<void> _save() async {
    final uid = PharmacyProfileService.currentUid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await PharmacyProfileService.updateProfile(uid, {
        'name': _nameCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        if (_addressLat != null) 'latitude': _addressLat,
        if (_addressLng != null) 'longitude': _addressLng,
        if (_addressCity.isNotEmpty) 'city': _addressCity,
        'phone': _phoneCtrl.text.trim(),
      });
      if (!mounted) return;
      FeedbackService.showSuccess(context, 'Profile updated');
      setState(() => _editing = false);
    } catch (e) {
      if (mounted) FeedbackService.showError(context, 'Could not save changes.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
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
              const Text('Pharmacy Photo', style: AppTextStyles.h4),
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
    final uid = PharmacyProfileService.currentUid;
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
        profileCollection: 'pharmacy_profiles',
        imageFile: file,
        uid: uid,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      await PharmacyProfileService.updatePhotoUrl(uid, url);
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
    final uid = PharmacyProfileService.currentUid;
    if (uid == null) return;

    setState(() => _uploading = true);
    try {
      await ImageUploadService.deletePartnerProfileImage(profileCollection: 'pharmacy_profiles', uid: uid);
      await PharmacyProfileService.updatePhotoUrl(uid, '');
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
      imageCircle = CircleAvatar(radius: 42, backgroundImage: FileImage(_localImage!));
    } else if (hasNetwork) {
      imageCircle = CachedNetworkImage(
        imageUrl: _currentPhotoUrl!,
        imageBuilder: (_, imageProvider) => CircleAvatar(radius: 42, backgroundImage: imageProvider),
        placeholder: (_, __) => AppAvatar(name: _nameCtrl.text, size: 84),
        errorWidget: (_, __, ___) => AppAvatar(name: _nameCtrl.text, size: 84),
      );
    } else {
      imageCircle = AppAvatar(name: _nameCtrl.text, size: 84);
    }

    return GestureDetector(
      onTap: _uploading ? null : _showPhotoOptions,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
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
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
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

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(pharmacyProfileProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.pharmacyProfile,
      title: 'Pharmacy Profile',
      extraActions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
          onPressed: () => context.push(AppRoutes.pharmacySettings),
          tooltip: 'Settings',
        ),
      ],
      body: profileAsync.when(
        loading: () => const PageLoadingState(),
        error: (_, __) => const NetworkErrorState(),
        data: (profile) {
          if (profile == null) {
            return const AppEmptyState(
              icon: Icons.storefront_outlined,
              title: 'Profile not found',
              message: 'Complete onboarding to set up your pharmacy profile.',
            );
          }
          if (!_editing) {
            _nameCtrl.text = profile.name;
            _addressCtrl.text = profile.address;
            _addressLat = profile.latitude;
            _addressLng = profile.longitude;
            _addressCity = profile.city;
            _phoneCtrl.text = profile.phone;
          }
          _syncPhoto(profile.photoUrl);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(child: _buildAvatar()),
              const SizedBox(height: 16),
              PremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _editableField('Pharmacy Name', _nameCtrl, Icons.storefront_rounded),
                    const Divider(height: 24, color: AppColors.divider),
                    _readOnlyField('License Number', profile.licenseNumber, Icons.badge_outlined),
                    const Divider(height: 24, color: AppColors.divider),
                    _editableField('Phone', _phoneCtrl, Icons.call_outlined, locked: true),
                    const Divider(height: 24, color: AppColors.divider),
                    _addressField(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Categories Offered', style: AppTextStyles.labelMedium),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: profile.categoriesOffered
                          .map((c) => InfoChip(icon: Icons.check_circle_outline_rounded, label: c))
                          .toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PartnerDocumentsSection(
                role: 'pharmacy',
                uid: profile.uid,
                documents: profile.documents,
                documentVerification: profile.documentVerification,
                locked: profile.status == 'active',
              ),
              const SizedBox(height: 24),
              if (_editing)
                GradientButton(label: 'Save Changes', isLoading: _saving, onTap: _save)
              else
                OutlinedButton.icon(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit Profile'),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _editableField(String label, TextEditingController ctrl, IconData icon, {bool locked = false}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: _editing
              ? TextField(
                  controller: ctrl,
                  readOnly: locked,
                  enabled: !locked,
                  decoration: InputDecoration(
                    labelText: label,
                    isDense: true,
                    suffixIcon: locked
                        ? const Icon(Icons.verified_rounded, color: AppColors.success, size: 18)
                        : null,
                    helperText: locked ? 'Verified via OTP — cannot be changed' : null,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.caption),
                    Text(ctrl.text.isEmpty ? '—' : ctrl.text, style: AppTextStyles.bodyLarge),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _addressField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.location_on_outlined, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: _editing
              ? InkWell(
                  onTap: _pickAddress,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      isDense: true,
                      suffixIcon: Icon(Icons.map_outlined, color: AppColors.primary, size: 20),
                    ),
                    child: Text(
                      _addressCtrl.text.isEmpty ? 'Select on map' : _addressCtrl.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Address', style: AppTextStyles.caption),
                    Text(_addressCtrl.text.isEmpty ? '—' : _addressCtrl.text, style: AppTextStyles.bodyLarge),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _readOnlyField(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              Text(value.isEmpty ? '—' : value, style: AppTextStyles.bodyLarge),
            ],
          ),
        ),
      ],
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
