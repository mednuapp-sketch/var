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
import '../../../core/services/feedback_service.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../location/models/precise_address.dart';
import '../../location/screens/map_location_picker_screen.dart';
import '../models/nutritionist_profile.dart';
import '../providers/nutrition_providers.dart';
import '../services/nutritionist_profile_service.dart';

/// Nutritionist identity — a hero avatar/rating card plus specialization
/// info, mirroring the Caregiver module's profile shape. This screen is also
/// the module's only profile *write* path: creating
/// `nutritionist_profiles/{uid}` here is what starts the admin-approval gate
/// (see `AppRouteRefreshListenable`) and, once approved, is what
/// `onNutritionistProfileWriteForVisibility` (functions/index.js) mirrors
/// into the patient-facing `nutritionists/{uid}` catalogue entry — before
/// that, a nutritionist simply isn't findable or bookable by patients.
///
/// The hero avatar is tap-to-change (bottom sheet → gallery/camera/remove,
/// upload-progress ring), mirroring `HospitalProfileScreen`'s avatar flow.
class NutritionProfileScreen extends ConsumerStatefulWidget {
  const NutritionProfileScreen({super.key});

  static const _allLanguages = [
    'English', 'Telugu', 'Hindi', 'Tamil', 'Kannada',
    'Malayalam', 'Marathi', 'Bengali',
  ];

  @override
  ConsumerState<NutritionProfileScreen> createState() => _NutritionProfileScreenState();
}

class _NutritionProfileScreenState extends ConsumerState<NutritionProfileScreen> {
  // Photo upload state
  File? _localImage;
  bool _uploading = false;
  double _uploadProgress = 0;
  String? _currentPhotoUrl;
  bool _photoSynced = false;

  void _syncPhoto(NutritionistProfile profile) {
    if (_photoSynced) return;
    _photoSynced = true;
    _currentPhotoUrl = profile.photoUrl;
  }

  Future<void> _edit(BuildContext context, NutritionistProfile current) async {
    final uid = NutritionistProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }

    final name = TextEditingController(
        text: current.name == 'Complete your profile' ? '' : current.name);
    final qualification = TextEditingController(text: current.qualification);
    final specialization = TextEditingController(text: current.specialization);
    final experienceYears = TextEditingController(
        text: current.experienceYears == 0 ? '' : '${current.experienceYears}');
    final consultationFee = TextEditingController(
        text: current.consultationFee == 0 ? '' : '${current.consultationFee}');
    var city = current.city;
    var lat = current.lat;
    var lng = current.lng;
    final bio = TextEditingController(text: current.bio);
    final selectedLanguages = <String>{
      ...current.languages.isEmpty ? const ['English'] : current.languages,
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Dietician Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
                TextField(controller: qualification, decoration: const InputDecoration(labelText: 'Qualification (e.g. RD, MSc Nutrition)')),
                TextField(controller: specialization, decoration: const InputDecoration(labelText: 'Specialization')),
                TextField(
                  controller: experienceYears,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Years of experience'),
                ),
                TextField(
                  controller: consultationFee,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Consultation fee (₹)'),
                ),
                InkWell(
                  onTap: () async {
                    final result = await Navigator.of(dialogContext).push<PreciseAddress>(
                      MaterialPageRoute(
                        builder: (_) => MapLocationPickerScreen(initialLat: lat, initialLng: lng),
                      ),
                    );
                    if (result == null) return;
                    setDialogState(() {
                      city = result.city ?? city;
                      lat = result.lat;
                      lng = result.lng;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Service Area',
                      prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.textSecondary),
                      suffixIcon: Icon(Icons.map_outlined, color: AppColors.primary),
                      helperText: 'Tap to pick the city/area you serve on the map',
                    ),
                    child: Text(
                      city.isEmpty ? 'Select on map' : city,
                      style: TextStyle(color: city.isEmpty ? AppColors.textHint : AppColors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bio,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'About you'),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Languages Spoken', style: AppTextStyles.labelMedium),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: NutritionProfileScreen._allLanguages.map((lang) => FilterChip(
                    label: Text(lang),
                    selected: selectedLanguages.contains(lang),
                    onSelected: (v) => setDialogState(() {
                      if (v) {
                        selectedLanguages.add(lang);
                      } else if (selectedLanguages.length > 1) {
                        selectedLanguages.remove(lang);
                      }
                    }),
                    selectedColor: AppColors.primary.withValues(alpha: 0.14),
                    checkmarkColor: AppColors.primary,
                  )).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    // Disposal is deferred until well after the dialog's own exit transition
    // finishes — disposing synchronously right after showDialog's Future
    // resolves is the documented dispose-race crash pattern elsewhere in this
    // codebase (the AlertDialog/TextFields are still mounted and mid-animation
    // at that exact point, not actually unmounted yet). The default Material
    // dialog transition is ~150ms; 400ms leaves comfortable margin.
    unawaited(Future.delayed(const Duration(milliseconds: 400), () {
      name.dispose();
      qualification.dispose();
      specialization.dispose();
      experienceYears.dispose();
      consultationFee.dispose();
      bio.dispose();
    }));

    if (saved != true) return;

    final fee = num.tryParse(consultationFee.text.trim()) ?? 0;
    final years = int.tryParse(experienceYears.text.trim()) ?? 0;

    try {
      await NutritionistProfileService.updateProfile(uid, {
        'name': name.text.trim(),
        'qualification': qualification.text.trim(),
        'specialization': specialization.text.trim(),
        'experienceYears': years,
        'consultationFee': fee,
        'city': city,
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
        'bio': bio.text.trim(),
        'languages': selectedLanguages.toList(),
      });
      if (context.mounted) FeedbackService.showSuccess(context, 'Profile saved');
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
              const Text('Profile Photo', style: AppTextStyles.h4),
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
    final uid = NutritionistProfileService.currentUid;
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
        profileCollection: 'nutritionist_profiles',
        imageFile: file,
        uid: uid,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      await NutritionistProfileService.updatePhotoUrl(uid, url);
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
    final uid = NutritionistProfileService.currentUid;
    if (uid == null) return;

    setState(() => _uploading = true);
    try {
      await ImageUploadService.deletePartnerProfileImage(profileCollection: 'nutritionist_profiles', uid: uid);
      await NutritionistProfileService.updatePhotoUrl(uid, '');
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

  Widget _buildAvatar(NutritionistProfile profile) {
    final hasNetwork = _currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty;
    const size = 76.0;

    Widget imageCircle;
    if (_localImage != null) {
      imageCircle = CircleAvatar(radius: size / 2, backgroundImage: FileImage(_localImage!));
    } else if (hasNetwork) {
      imageCircle = CachedNetworkImage(
        imageUrl: _currentPhotoUrl!,
        imageBuilder: (_, imageProvider) => CircleAvatar(radius: size / 2, backgroundImage: imageProvider),
        placeholder: (_, __) => AppAvatar(name: profile.name, size: size),
        errorWidget: (_, __, ___) => AppAvatar(name: profile.name, size: size),
      );
    } else {
      imageCircle = AppAvatar(name: profile.name, size: size);
    }

    return GestureDetector(
      onTap: _uploading ? null : _showPhotoOptions,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: ClipOval(child: imageCircle),
              ),
              if (_uploading)
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 30,
                      height: 30,
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
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 12),
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
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(nutritionistProfileProvider).valueOrNull ?? NutritionistProfile.empty();
    _syncPhoto(profile);

    return SharedAppShell(
      currentRoute: AppRoutes.nutritionProfile,
      title: 'Dietician Profile',
      extraActions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
          onPressed: () => _edit(context, profile),
          tooltip: 'Edit profile',
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
          onPressed: () => context.push(AppRoutes.nutritionSettings),
          tooltip: 'Settings',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (profile.status == 'pending')
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: PremiumCard(
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, color: AppColors.warning),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your application is under review. Patients will be able to find and book you once approved.',
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary, AppColors.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Column(
              children: [
                _buildAvatar(profile),
                const SizedBox(height: 14),
                Text(profile.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                if (profile.specialization.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(profile.specialization, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _HeroStat(label: 'Rating', value: profile.rating.toStringAsFixed(1), icon: Icons.star_rounded),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Experience', value: '${profile.experienceYears} yrs', icon: Icons.workspace_premium_outlined),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Fee', value: '₹${profile.consultationFee}', icon: Icons.currency_rupee_rounded),
                  ],
                ),
              ],
            ),
          ),
          if (profile.qualification.isNotEmpty) ...[
            const SizedBox(height: 16),
            PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Qualification', style: AppTextStyles.labelMedium),
                      const Spacer(),
                      if (profile.documentsVerified)
                        const StatusBadge(label: 'Verified', color: AppColors.success, icon: Icons.verified_rounded),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(profile.qualification, style: AppTextStyles.bodyMedium),
                ],
              ),
            ),
          ],
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 16),
            PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('About', style: AppTextStyles.labelMedium),
                  const SizedBox(height: 10),
                  Text(profile.bio, style: AppTextStyles.bodyMedium),
                ],
              ),
            ),
          ],
          if (NutritionistProfileService.currentUid != null) ...[
            const SizedBox(height: 16),
            PartnerDocumentsSection(
              role: 'nutritionist',
              uid: NutritionistProfileService.currentUid!,
              documents: profile.documents,
              documentVerification: profile.documentVerification,
              locked: profile.status == 'active',
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
        Text(value, style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
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
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
