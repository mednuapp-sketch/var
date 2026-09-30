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
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/services/image_upload_service.dart';
import '../../location/models/precise_address.dart';
import '../../location/screens/map_location_picker_screen.dart';
import '../models/caregiver_profile.dart';
import '../providers/caregiver_providers.dart';
import '../services/caregiver_profile_service.dart';

/// Caregiver identity — a hero avatar/stat card plus certification and
/// specialty chips, mirroring the Ambulance module's Vehicle Profile shape
/// (hero + fact cards + chip groups) applied to a person instead of a
/// vehicle. No rating is shown here by design — see the patient-facing
/// listing screens for the same decision.
///
/// This screen is also the module's only profile *write* path: creating
/// `caregiver_profiles/{uid}` here is what makes `firestore.rules`'
/// `isCaregiverPartner()` start returning true, i.e. what lets this account
/// see unclaimed visits at all. There is no separate onboarding screen for
/// this role, so the edit action lives on the screen that already displays
/// exactly these fields.
class CaregiverProfileScreen extends ConsumerStatefulWidget {
  const CaregiverProfileScreen({super.key});

  @override
  ConsumerState<CaregiverProfileScreen> createState() => _CaregiverProfileScreenState();
}

class _CaregiverProfileScreenState extends ConsumerState<CaregiverProfileScreen> {
  // Photo upload state
  File? _localImage;
  bool _uploading = false;
  double _uploadProgress = 0;

  Future<void> _edit(BuildContext context, CaregiverProfile current) async {
    final uid = CaregiverProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }

    final name = TextEditingController(
        text: current.name == 'Complete your profile' ? '' : current.name);
    final certifications = TextEditingController(text: current.certifications.join(', '));
    final specialties = TextEditingController(text: current.specialties.join(', '));
    final hourlyRate =
        TextEditingController(text: current.hourlyRate == 0 ? '' : '${current.hourlyRate}');
    final experienceYears = TextEditingController(
        text: current.experienceYears == 0 ? '' : '${current.experienceYears}');
    var city = current.city;
    var lat = current.lat;
    var lng = current.lng;
    var gender = current.gender.isEmpty ? 'Female' : current.gender;
    var serviceType = current.serviceType;

    const fieldGap = SizedBox(height: 16);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Caregiver Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
                fieldGap,
                Text('I offer', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    (value: 'caregiver', label: 'Caregiver'),
                    (value: 'care_assistant', label: 'Care Assistant'),
                  ].map((opt) => ChoiceChip(
                        label: Text(opt.label),
                        selected: serviceType == opt.value,
                        onSelected: (_) => setDialogState(() => serviceType = opt.value),
                        selectedColor: AppColors.primary.withValues(alpha: 0.16),
                        labelStyle: TextStyle(
                          color: serviceType == opt.value ? AppColors.primary : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      )).toList(),
                ),
                fieldGap,
                Text('Gender', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['Female', 'Male'].map((g) => ChoiceChip(
                        label: Text(g),
                        selected: gender == g,
                        onSelected: (_) => setDialogState(() => gender = g),
                        selectedColor: AppColors.primary.withValues(alpha: 0.16),
                        labelStyle: TextStyle(
                          color: gender == g ? AppColors.primary : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      )).toList(),
                ),
                fieldGap,
                TextField(
                  controller: certifications,
                  decoration: const InputDecoration(
                    labelText: 'Certifications',
                    hintText: 'Comma separated',
                  ),
                ),
                fieldGap,
                TextField(
                  controller: specialties,
                  decoration: const InputDecoration(
                    labelText: 'Specialties',
                    hintText: 'Comma separated',
                  ),
                ),
                fieldGap,
                TextField(
                  controller: hourlyRate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Hourly rate (₹)'),
                ),
                fieldGap,
                TextField(
                  controller: experienceYears,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Years of experience'),
                ),
                fieldGap,
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
      certifications.dispose();
      specialties.dispose();
      hourlyRate.dispose();
      experienceYears.dispose();
    }));

    if (saved != true) return;

    List<String> split(TextEditingController c) =>
        c.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final rate = num.tryParse(hourlyRate.text.trim()) ?? 0;
    final years = int.tryParse(experienceYears.text.trim()) ?? 0;

    try {
      final exists = await CaregiverProfileService.profileExists(uid);
      if (exists) {
        // A self-update can't touch status/isVerified/rating/totalVisits —
        // firestore.rules rejects those keys, so they're deliberately absent.
        await CaregiverProfileService.updateProfile(uid, {
          'name': name.text.trim(),
          'certifications': split(certifications),
          'specialties': split(specialties),
          'hourlyRate': rate,
          'experienceYears': years,
          'gender': gender,
          'serviceType': serviceType,
          'city': city,
          if (lat != null && lng != null) 'lat': lat,
          if (lat != null && lng != null) 'lng': lng,
        }, currentStatus: current.status);
      } else {
        await CaregiverProfileService.createProfile(
          uid: uid,
          name: name.text.trim(),
          certifications: split(certifications),
          specialties: split(specialties),
          hourlyRate: rate,
          experienceYears: years,
          gender: gender,
          serviceType: serviceType,
          city: city,
          lat: lat,
          lng: lng,
        );
      }
      if (context.mounted) FeedbackService.showSuccess(context, 'Profile saved');
    } catch (_) {
      if (context.mounted) {
        FeedbackService.showError(context, "Couldn't save your profile. Please try again.");
      }
    }
  }

  // ── Photo picker ──────────────────────────────────────────

  void _showPhotoOptions(String currentPhotoUrl) {
    final hasPhoto = currentPhotoUrl.isNotEmpty || _localImage != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
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
    final uid = CaregiverProfileService.currentUid;
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
        profileCollection: 'caregiver_profiles',
        imageFile: file,
        uid: uid,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      await CaregiverProfileService.updatePhotoUrl(uid, url, currentStatus: ref.read(caregiverProfileProvider).status);
      if (!mounted) return;
      setState(() => _uploading = false);
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
    final uid = CaregiverProfileService.currentUid;
    if (uid == null) return;

    setState(() => _uploading = true);
    try {
      await ImageUploadService.deletePartnerProfileImage(profileCollection: 'caregiver_profiles', uid: uid);
      await CaregiverProfileService.updatePhotoUrl(uid, '', currentStatus: ref.read(caregiverProfileProvider).status);
      if (!mounted) return;
      setState(() {
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

  Widget _buildAvatar(CaregiverProfile profile) {
    final hasNetwork = profile.photoUrl.isNotEmpty;

    Widget imageCircle;
    if (_localImage != null) {
      imageCircle = CircleAvatar(radius: 38, backgroundImage: FileImage(_localImage!));
    } else if (hasNetwork) {
      imageCircle = CachedNetworkImage(
        imageUrl: profile.photoUrl,
        width: 76,
        height: 76,
        fit: BoxFit.cover,
        imageBuilder: (_, imageProvider) => CircleAvatar(radius: 38, backgroundImage: imageProvider),
        placeholder: (_, __) => AppAvatar(name: profile.name, size: 76),
        errorWidget: (_, __, ___) => AppAvatar(name: profile.name, size: 76),
      );
    } else {
      imageCircle = AppAvatar(name: profile.name, size: 76);
    }

    return GestureDetector(
      onTap: _uploading ? null : () => _showPhotoOptions(profile.photoUrl),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(child: imageCircle),
              ),
              if (_uploading)
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
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
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13),
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
            style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(caregiverProfileProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.caregiverProfile,
      title: 'Caregiver Profile',
      extraActions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
          onPressed: () => _edit(context, profile),
          tooltip: 'Edit profile',
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
          onPressed: () => context.push(AppRoutes.caregiverSettings),
          tooltip: 'Settings',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (profile.hasPendingChanges) const PendingReviewBanner(),
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
                const SizedBox(height: 4),
                Text('${profile.experienceYears} years of experience', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _HeroStat(
                      label: profile.serviceType == 'care_assistant' ? 'Care Assistant' : 'Caregiver',
                      value: profile.gender.isEmpty ? '—' : profile.gender,
                      icon: Icons.badge_rounded,
                    ),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Visits', value: '${profile.totalVisits}', icon: Icons.event_note_rounded),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Rate/hr', value: '₹${profile.hourlyRate}', icon: Icons.currency_rupee_rounded),
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
                const Row(
                  children: [
                    Text('Certifications', style: AppTextStyles.labelMedium),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: profile.certifications
                      .map((c) => InfoChip(icon: Icons.workspace_premium_outlined, label: c, color: AppColors.secondary))
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Specialties', style: AppTextStyles.labelMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: profile.specialties
                      .map((s) => InfoChip(icon: Icons.favorite_border_rounded, label: s, color: AppColors.accentText))
                      .toList(),
                ),
              ],
            ),
          ),
          if (CaregiverProfileService.currentUid != null) ...[
            const SizedBox(height: 16),
            PartnerDocumentsSection(
              role: 'caregiver',
              uid: CaregiverProfileService.currentUid!,
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
        Icon(icon, color: AppColors.primaryLight, size: 20),
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
