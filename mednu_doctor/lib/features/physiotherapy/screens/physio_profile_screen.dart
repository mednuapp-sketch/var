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
import '../models/physio_profile.dart';
import '../providers/physio_providers.dart';
import '../services/physio_profile_service.dart';

/// Physiotherapist identity — a hero avatar/rating card plus certification
/// and specialty chips. Mirrors the Caregiver module's Profile screen shape.
///
/// This screen is also the module's only profile *write* path: creating
/// `physiotherapist_profiles/{uid}` here is what makes `firestore.rules`'
/// `isPhysiotherapistPartner()` start returning true (once an admin flips
/// `status` to 'active') — i.e. what lets this account see unclaimed
/// sessions at all.
class PhysioProfileScreen extends ConsumerStatefulWidget {
  const PhysioProfileScreen({super.key});

  @override
  ConsumerState<PhysioProfileScreen> createState() => _PhysioProfileScreenState();
}

class _PhysioProfileScreenState extends ConsumerState<PhysioProfileScreen> {
  static const _allLanguages = [
    'English', 'Telugu', 'Hindi', 'Tamil', 'Kannada',
    'Malayalam', 'Marathi', 'Bengali',
  ];

  // Photo upload state. The persisted URL is read live from the profile
  // stream (physioProfileProvider) so avatar changes made elsewhere show up
  // in real time; only the in-flight local preview is held here.
  File? _localImage;
  bool _uploading = false;
  double _uploadProgress = 0;

  // ── Photo picker ──────────────────────────────────────────

  void _showPhotoOptions(String currentPhotoUrl) {
    final hasPhoto = currentPhotoUrl.isNotEmpty || _localImage != null;

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
    final uid = PhysioProfileService.currentUid;
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
        profileCollection: 'physiotherapist_profiles',
        imageFile: file,
        uid: uid,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      await PhysioProfileService.updatePhotoUrl(uid, url);
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
    final uid = PhysioProfileService.currentUid;
    if (uid == null) return;

    setState(() => _uploading = true);
    try {
      await ImageUploadService.deletePartnerProfileImage(profileCollection: 'physiotherapist_profiles', uid: uid);
      await PhysioProfileService.updatePhotoUrl(uid, '');
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

  Widget _buildAvatar(PhysioProfile profile) {
    final hasNetwork = profile.photoUrl.isNotEmpty;

    Widget imageCircle;
    if (_localImage != null) {
      imageCircle = CircleAvatar(radius: 38, backgroundImage: FileImage(_localImage!));
    } else if (hasNetwork) {
      imageCircle = CachedNetworkImage(
        imageUrl: profile.photoUrl,
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
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(child: imageCircle),
              ),
              if (profile.documentsVerified && !_uploading)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.6),
                    ),
                    child: const Icon(Icons.verified_rounded, size: 14, color: Colors.white),
                  ),
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
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 12),
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

  Future<void> _edit(BuildContext context, PhysioProfile current) async {
    final uid = PhysioProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }

    final name = TextEditingController(
        text: current.name == 'Complete your profile' ? '' : current.name);
    final certifications = TextEditingController(text: current.certifications.join(', '));
    final specialties = TextEditingController(text: current.specialties.join(', '));
    final onlineRate =
        TextEditingController(text: current.onlineRate == 0 ? '' : '${current.onlineRate}');
    final homeRate =
        TextEditingController(text: current.homeRate == 0 ? '' : '${current.homeRate}');
    final clinicRate =
        TextEditingController(text: current.clinicRate == 0 ? '' : '${current.clinicRate}');
    var offersClinicVisit = current.clinicRate > 0;
    final experienceYears = TextEditingController(
        text: current.experienceYears == 0 ? '' : '${current.experienceYears}');
    var city = current.city;
    var clinicLat = current.clinicLat;
    var clinicLng = current.clinicLng;
    final selectedLanguages = <String>{
      ...current.languages.isEmpty ? const ['English'] : current.languages,
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Physiotherapist Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
                TextField(
                  controller: certifications,
                  decoration: const InputDecoration(
                    labelText: 'Certifications',
                    hintText: 'Comma separated',
                  ),
                ),
                TextField(
                  controller: specialties,
                  decoration: const InputDecoration(
                    labelText: 'Specialties',
                    hintText: 'Comma separated',
                  ),
                ),
                TextField(
                  controller: onlineRate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Online video consultation fee (₹)'),
                ),
                TextField(
                  controller: homeRate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Home visit fee (₹)'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: offersClinicVisit,
                  onChanged: (v) => setDialogState(() => offersClinicVisit = v),
                  title: const Text('Offers in-clinic appointments'),
                ),
                if (offersClinicVisit)
                  TextField(
                    controller: clinicRate,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'In-clinic appointment fee (₹)'),
                  ),
                TextField(
                  controller: experienceYears,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Years of experience'),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final result = await Navigator.of(dialogContext).push<PreciseAddress>(
                      MaterialPageRoute(
                        builder: (_) => MapLocationPickerScreen(initialLat: clinicLat, initialLng: clinicLng),
                      ),
                    );
                    if (result == null) return;
                    setDialogState(() {
                      city = result.city ?? city;
                      clinicLat = result.lat;
                      clinicLng = result.lng;
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
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Languages Spoken', style: AppTextStyles.labelMedium),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allLanguages.map((lang) => FilterChip(
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
      certifications.dispose();
      specialties.dispose();
      onlineRate.dispose();
      homeRate.dispose();
      clinicRate.dispose();
      experienceYears.dispose();
    }));

    if (saved != true) return;

    List<String> split(TextEditingController c) =>
        c.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final online = num.tryParse(onlineRate.text.trim()) ?? 0;
    final home = num.tryParse(homeRate.text.trim()) ?? 0;
    final clinic = offersClinicVisit ? (num.tryParse(clinicRate.text.trim()) ?? 0) : 0;
    final startingFrom = [online, clinic, home].where((r) => r > 0).fold<num?>(
        null, (min, r) => min == null || r < min ? r : min) ?? 0;
    final years = int.tryParse(experienceYears.text.trim()) ?? 0;

    try {
      final exists = await PhysioProfileService.profileExists(uid);
      if (exists) {
        // A self-update can't touch status/isVerified/rating/totalSessions —
        // firestore.rules rejects those keys, so they're deliberately absent.
        await PhysioProfileService.updateProfile(uid, {
          'name': name.text.trim(),
          'certifications': split(certifications),
          'specialties': split(specialties),
          'onlineRate': online,
          'clinicRate': clinic,
          'homeRate': home,
          'hourlyRate': startingFrom,
          'experienceYears': years,
          'city': city,
          if (clinicLat != null && clinicLng != null) 'clinicLat': clinicLat,
          if (clinicLat != null && clinicLng != null) 'clinicLng': clinicLng,
          'languages': selectedLanguages.toList(),
        });
      } else {
        await PhysioProfileService.createProfile(
          uid: uid,
          name: name.text.trim(),
          certifications: split(certifications),
          specialties: split(specialties),
          onlineRate: online,
          clinicRate: clinic,
          homeRate: home,
          experienceYears: years,
          city: city,
          clinicLat: clinicLat,
          clinicLng: clinicLng,
          languages: selectedLanguages.toList(),
        );
      }
      if (context.mounted) FeedbackService.showSuccess(context, 'Profile saved');
    } catch (_) {
      if (context.mounted) {
        FeedbackService.showError(context, "Couldn't save your profile. Please try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(physioProfileProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.physioProfile,
      title: 'Physiotherapist Profile',
      extraActions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
          onPressed: () => _edit(context, profile),
          tooltip: 'Edit profile',
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
          onPressed: () => context.push(AppRoutes.physioSettings),
          tooltip: 'Settings',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                    _HeroStat(label: 'Rating', value: profile.rating.toStringAsFixed(1), icon: Icons.star_rounded),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Sessions', value: '${profile.totalSessions}', icon: Icons.event_note_rounded),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'From', value: '₹${profile.hourlyRate}', icon: Icons.currency_rupee_rounded),
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
                    const Text('Certifications', style: AppTextStyles.labelMedium),
                    const Spacer(),
                    if (profile.documentsVerified) const StatusBadge(label: 'Verified', color: AppColors.success, icon: Icons.verified_rounded),
                  ],
                ),
                const SizedBox(height: 12),
                profile.certifications.isEmpty
                    ? const Text('No certifications added yet', style: AppTextStyles.bodySmall)
                    : Wrap(
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
                profile.specialties.isEmpty
                    ? const Text('No specialties added yet', style: AppTextStyles.bodySmall)
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: profile.specialties
                            .map((s) => InfoChip(icon: Icons.accessibility_new_rounded, label: s, color: AppColors.accentText))
                            .toList(),
                      ),
              ],
            ),
          ),
          if (PhysioProfileService.currentUid != null) ...[
            const SizedBox(height: 16),
            PartnerDocumentsSection(
              role: 'physiotherapist',
              uid: PhysioProfileService.currentUid!,
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
