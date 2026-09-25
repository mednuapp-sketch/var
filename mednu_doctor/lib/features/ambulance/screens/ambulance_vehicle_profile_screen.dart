import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../../core/services/feedback_service.dart';
import '../models/vehicle_profile.dart';
import '../providers/ambulance_providers.dart';
import '../services/ambulance_profile_service.dart';

/// Vehicle + driver identity — a hero plate-number card, a tap-to-change
/// vehicle/driver avatar above it, an equipment checklist and document
/// status.
///
/// This screen is also the module's only profile *write* path: creating
/// `ambulance_profiles/{uid}` here is what makes `firestore.rules`'
/// `isAmbulancePartner()` start returning true, i.e. what lets this account
/// see the shared dispatch queue at all. There is no separate onboarding
/// screen for this role, so the edit action lives on the screen that already
/// displays exactly these fields.
///
/// The avatar upload flow mirrors `HospitalProfileScreen`'s
/// `_buildAvatar()`/`_showPhotoOptions()`/`_pickAndUpload()`/`_removePhoto()`
/// pattern exactly, adapted to this screen's `ambulance_profiles` collection
/// and hero-card layout.
class AmbulanceVehicleProfileScreen extends ConsumerStatefulWidget {
  const AmbulanceVehicleProfileScreen({super.key});

  @override
  ConsumerState<AmbulanceVehicleProfileScreen> createState() =>
      _AmbulanceVehicleProfileScreenState();
}

class _AmbulanceVehicleProfileScreenState extends ConsumerState<AmbulanceVehicleProfileScreen> {
  // Photo upload state
  File? _localImage;
  bool _uploading = false;
  double _uploadProgress = 0;
  String? _currentPhotoUrl;
  bool _synced = false;

  void _syncFromVehicle(VehicleProfile vehicle) {
    if (_synced) return;
    _synced = true;
    _currentPhotoUrl = vehicle.photoUrl;
  }

  Future<void> _edit(BuildContext context, VehicleProfile current) async {
    final uid = AmbulanceProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }

    final plate = TextEditingController(
        text: current.plateNumber == 'Not set' ? '' : current.plateNumber);
    final vehicleType = TextEditingController(
        text: current.vehicleType == 'Unverified' ? '' : current.vehicleType);
    final driverName = TextEditingController(text: current.driverName);
    final driverPhone = TextEditingController(text: current.driverPhone);
    final driverLicense = TextEditingController(text: current.driverLicense);
    final equipment = TextEditingController(text: current.equipment.join(', '));

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vehicle & Driver Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: plate, decoration: const InputDecoration(labelText: 'Plate number')),
              TextField(
                controller: vehicleType,
                decoration: const InputDecoration(
                  labelText: 'Vehicle type',
                  hintText: 'Basic Life Support / Advanced Life Support / ICU on Wheels',
                ),
              ),
              TextField(controller: driverName, decoration: const InputDecoration(labelText: 'Driver name')),
              TextField(
                controller: driverPhone,
                keyboardType: TextInputType.phone,
                readOnly: true,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Driver phone',
                  suffixIcon: Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
                  helperText: 'Verified via OTP — cannot be changed',
                ),
              ),
              TextField(controller: driverLicense, decoration: const InputDecoration(labelText: 'Driver license')),
              TextField(
                controller: equipment,
                decoration: const InputDecoration(
                  labelText: 'Onboard equipment',
                  hintText: 'Comma separated',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );

    // Disposal is deferred until well after the dialog's own exit transition
    // finishes — disposing synchronously right after showDialog's Future
    // resolves is the documented dispose-race crash pattern elsewhere in this
    // codebase (the AlertDialog/TextFields are still mounted and mid-animation
    // at that exact point, not actually unmounted yet). The default Material
    // dialog transition is ~150ms; 400ms leaves comfortable margin.
    unawaited(Future.delayed(const Duration(milliseconds: 400), () {
      plate.dispose();
      vehicleType.dispose();
      driverName.dispose();
      driverPhone.dispose();
      driverLicense.dispose();
      equipment.dispose();
    }));

    if (saved != true) return;

    final equipmentList = equipment.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    try {
      final exists = await AmbulanceProfileService.profileExists(uid);
      if (exists) {
        // A self-update can't touch status/isVerified/rating/totalTrips —
        // firestore.rules rejects those keys, so they're deliberately absent.
        await AmbulanceProfileService.updateProfile(uid, {
          'plateNumber': plate.text.trim(),
          'vehicleType': vehicleType.text.trim(),
          'driverName': driverName.text.trim(),
          'driverPhone': driverPhone.text.trim(),
          'driverLicense': driverLicense.text.trim(),
          'equipment': equipmentList,
        });
      } else {
        await AmbulanceProfileService.createProfile(
          uid: uid,
          plateNumber: plate.text.trim(),
          vehicleType: vehicleType.text.trim(),
          driverName: driverName.text.trim(),
          driverPhone: driverPhone.text.trim(),
          driverLicense: driverLicense.text.trim(),
          equipment: equipmentList,
        );
      }
      if (context.mounted) FeedbackService.showSuccess(context, 'Vehicle profile saved');
    } catch (_) {
      if (context.mounted) {
        FeedbackService.showError(context, "Couldn't save your profile. Please try again.");
      }
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
              const Text('Vehicle Photo', style: AppTextStyles.h4),
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
    final uid = AmbulanceProfileService.currentUid;
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
        profileCollection: 'ambulance_profiles',
        imageFile: file,
        uid: uid,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      await AmbulanceProfileService.updatePhotoUrl(uid, url);
      if (!mounted) return;
      setState(() {
        _currentPhotoUrl = url;
        _uploading = false;
      });
      FeedbackService.showSuccess(context, 'Vehicle photo updated!');
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
    final uid = AmbulanceProfileService.currentUid;
    if (uid == null) return;

    setState(() => _uploading = true);
    try {
      await ImageUploadService.deletePartnerProfileImage(profileCollection: 'ambulance_profiles', uid: uid);
      await AmbulanceProfileService.updatePhotoUrl(uid, '');
      if (!mounted) return;
      setState(() {
        _currentPhotoUrl = '';
        _localImage = null;
        _uploading = false;
      });
      FeedbackService.showSuccess(context, 'Vehicle photo removed.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      FeedbackService.showError(context, 'Remove failed: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ── Avatar widget ─────────────────────────────────────────

  Widget _buildAvatar(VehicleProfile vehicle) {
    final hasNetwork = _currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty;
    final avatarName = vehicle.driverName.isNotEmpty ? vehicle.driverName : vehicle.plateNumber;

    Widget imageCircle;
    if (_localImage != null) {
      imageCircle = CircleAvatar(radius: 45, backgroundImage: FileImage(_localImage!));
    } else if (hasNetwork) {
      imageCircle = CachedNetworkImage(
        imageUrl: _currentPhotoUrl!,
        imageBuilder: (_, imageProvider) => CircleAvatar(radius: 45, backgroundImage: imageProvider),
        placeholder: (_, __) => AppAvatar(name: avatarName, size: 90),
        errorWidget: (_, __, ___) => AppAvatar(name: avatarName, size: 90),
      );
    } else {
      imageCircle = AppAvatar(name: avatarName, size: 90);
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
    final vehicle = ref.watch(vehicleProfileProvider);
    _syncFromVehicle(vehicle);

    return SharedAppShell(
      currentRoute: AppRoutes.ambulanceVehicleProfile,
      title: 'Vehicle Profile',
      extraActions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
          onPressed: () => _edit(context, vehicle),
          tooltip: 'Edit vehicle details',
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
          onPressed: () => context.push(AppRoutes.ambulanceSettings),
          tooltip: 'Settings',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FadeInSlide(child: Center(child: _buildAvatar(vehicle))),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary, AppColors.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Column(
              children: [
                const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 40),
                const SizedBox(height: 12),
                Text(
                  vehicle.plateNumber,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.5),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text(vehicle.vehicleType, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _HeroStat(label: 'Rating', value: vehicle.rating.toStringAsFixed(1), icon: Icons.star_rounded),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Trips', value: '${vehicle.totalTrips}', icon: Icons.route_rounded),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Driver', style: AppTextStyles.labelMedium),
                    const Spacer(),
                    if (vehicle.documentsVerified) const StatusBadge(label: 'Verified', color: AppColors.success, icon: Icons.verified_rounded),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SharedProfileAvatar(name: vehicle.driverName, size: 46, isVerified: vehicle.documentsVerified),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(vehicle.driverName, style: AppTextStyles.labelLarge),
                          Text(vehicle.driverPhone, style: AppTextStyles.bodySmall),
                          Text('License: ${vehicle.driverLicense}', style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Onboard Equipment', style: AppTextStyles.labelMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: vehicle.equipment
                      .map((e) => InfoChip(icon: Icons.check_circle_outline_rounded, label: e, color: AppColors.success))
                      .toList(),
                ),
              ],
            ),
          ),
          if (AmbulanceProfileService.currentUid != null) ...[
            const SizedBox(height: 16),
            PartnerDocumentsSection(
              role: 'ambulance',
              uid: AmbulanceProfileService.currentUid!,
              documents: vehicle.documents,
              documentVerification: vehicle.documentVerification,
              locked: vehicle.status == 'active',
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _HeroStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.amberAccent, size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
        Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Colors.white60)),
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
