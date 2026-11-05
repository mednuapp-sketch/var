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
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../caregiver/models/caregiver_profile.dart';
import '../../caregiver/providers/caregiver_providers.dart';
import '../../caregiver/services/caregiver_profile_service.dart';
import '../../location/models/precise_address.dart';
import '../../location/screens/map_location_picker_screen.dart';
import '../widgets/care_job_widgets.dart';

const _allLanguages = ['English', 'Telugu', 'Hindi', 'Tamil', 'Kannada', 'Malayalam', 'Marathi', 'Bengali'];

/// The Care Assistant's public profile — what patients see in the Care
/// Assistant list in the MedNu app: photo, bio, services, languages and all
/// four duration rates. Backed live by `caregiver_profiles/{uid}`; once
/// approved, edits go to admin review (see [PendingProfileEditService]) and
/// the on-duty switch stays instant.
class CareAssistantProfileScreen extends ConsumerStatefulWidget {
  const CareAssistantProfileScreen({super.key});

  @override
  ConsumerState<CareAssistantProfileScreen> createState() => _CareAssistantProfileScreenState();
}

class _CareAssistantProfileScreenState extends ConsumerState<CareAssistantProfileScreen> {
  File? _localImage;
  bool _uploading = false;
  double _uploadProgress = 0;

  // ── Photo ───────────────────────────────────────────────────────────────

  void _showPhotoOptions(bool hasPhoto) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
              ),
              const Text('Profile Photo', style: AppTextStyles.h4),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: careAssistantTeal),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUpload(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: careAssistantTeal),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUpload(ImageSource.camera);
                },
              ),
              if (hasPhoto)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                  title: const Text('Remove photo', style: TextStyle(color: AppColors.error)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _removePhoto();
                  },
                ),
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
      if (mounted) {
        FeedbackService.showError(context, 'Could not open picker: ${e.toString().replaceAll('Exception: ', '')}');
      }
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
      FeedbackService.showSuccess(context, 'Profile photo updated');
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
      FeedbackService.showSuccess(context, 'Profile photo removed');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      FeedbackService.showError(context, 'Remove failed: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ── Edit ────────────────────────────────────────────────────────────────

  Future<void> _edit(CaregiverProfile current) async {
    final uid = CaregiverProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EditSheet(current: current),
    );
    if (result == null || !mounted) return;
    try {
      final exists = await CaregiverProfileService.profileExists(uid);
      if (exists) {
        await CaregiverProfileService.updateProfile(uid, result, currentStatus: current.status);
      } else {
        await CaregiverProfileService.createProfile(
          uid: uid,
          name: result['name'] as String,
          certifications: List<String>.from(result['certifications'] as List),
          specialties: List<String>.from(result['specialties'] as List),
          hourlyRate: result['hourlyRate'] as num,
          rateHalfDay: result['rateHalfDay'] as num,
          rateFullDay: result['rateFullDay'] as num,
          rateMultiDay: result['rateMultiDay'] as num,
          bio: result['bio'] as String,
          languages: List<String>.from(result['languages'] as List),
          experienceYears: result['experienceYears'] as int,
          gender: result['gender'] as String,
          serviceType: 'care_assistant',
          city: result['city'] as String,
          lat: (result['lat'] as num?)?.toDouble(),
          lng: (result['lng'] as num?)?.toDouble(),
        );
      }
      if (mounted) {
        FeedbackService.showSuccess(
          context,
          current.status == 'active' ? 'Changes sent for review' : 'Profile saved',
        );
      }
    } catch (e) {
      if (mounted) {
        FeedbackService.showError(
          context,
          e.toString().startsWith('Exception: ')
              ? e.toString().replaceFirst('Exception: ', '')
              : "Couldn't save your profile. Please try again.",
        );
      }
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  Widget _avatar(CaregiverProfile p) {
    const size = 84.0;
    Widget image;
    if (_localImage != null) {
      image = Image.file(_localImage!, width: size, height: size, fit: BoxFit.cover);
    } else if (p.photoUrl.isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: p.photoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => AppAvatar(name: p.name, size: size),
        errorWidget: (_, __, ___) => AppAvatar(name: p.name, size: size),
      );
    } else {
      image = AppAvatar(name: p.name, size: size);
    }
    return GestureDetector(
      onTap: _uploading ? null : () => _showPhotoOptions(p.photoUrl.isNotEmpty || _localImage != null),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: ClipOval(child: image),
          ),
          if (_uploading)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
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
            )
          else
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: careAssistantTeal,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(caregiverProfileProvider);
    final uid = CaregiverProfileService.currentUid;
    final tiers = <(String, num, String)>[
      ('Hourly', p.hourlyRate, '/hr'),
      ('Half-day', p.rateHalfDay, '/half-day'),
      ('Full-day', p.rateFullDay, '/day'),
      ('Multi-day', p.rateMultiDay, '/day'),
    ];

    return SharedAppShell(
      currentRoute: AppRoutes.careAssistantProfile,
      title: 'My Profile',
      extraActions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
          onPressed: () => _edit(p),
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
          if (p.hasPendingChanges) const PendingReviewBanner(),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(R.p(context, 22)),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00695C), careAssistantTeal, Color(0xFF26A69A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: careAssistantTeal.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Column(
              children: [
                _avatar(p),
                const SizedBox(height: 12),
                Text(p.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  p.status == 'active' ? 'Care Assistant • Approved' : 'Care Assistant • Pending approval',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _HeroStat(label: 'Rating', value: p.rating == 0 ? '—' : p.rating.toStringAsFixed(1)),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Jobs', value: '${p.totalVisits}'),
                    Container(width: 1, height: 30, color: Colors.white24),
                    _HeroStat(label: 'Experience', value: '${p.experienceYears} yrs'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (p.bio.isNotEmpty) ...[
            PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('About', style: AppTextStyles.labelMedium),
                  const SizedBox(height: 8),
                  Text(p.bio, style: AppTextStyles.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your rates', style: AppTextStyles.labelMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: tiers
                      .map((t) => Container(
                            constraints: const BoxConstraints(minWidth: 130),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: careAssistantTeal.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: careAssistantTeal.withValues(alpha: 0.25)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(t.$1, style: AppTextStyles.caption),
                                const SizedBox(height: 2),
                                Text('₹${t.$2}${t.$3}',
                                    style: AppTextStyles.labelLarge.copyWith(color: careAssistantTeal)),
                              ],
                            ),
                          ))
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
                const Text('Services & details', style: AppTextStyles.labelMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (p.gender.isNotEmpty) InfoChip(icon: Icons.person_outline_rounded, label: p.gender),
                    if (p.city.isNotEmpty) InfoChip(icon: Icons.location_on_outlined, label: p.city),
                    ...p.specialties.map((s) =>
                        InfoChip(icon: Icons.support_agent_rounded, label: s, color: careAssistantTeal)),
                    ...p.languages.map((l) =>
                        InfoChip(icon: Icons.translate_rounded, label: l, color: AppColors.secondary)),
                  ],
                ),
                if (p.specialties.isEmpty && p.languages.isEmpty && p.city.isEmpty)
                  Text('Tap the pencil to complete your profile.', style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          if (uid != null) ...[
            const SizedBox(height: 16),
            PartnerDocumentsSection(
              role: 'caregiver',
              uid: uid,
              documents: p.documents,
              documentVerification: p.documentVerification,
              locked: p.status == 'active',
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
  const _HeroStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Flexible(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Colors.white70)),
          ],
        ),
      );
}

/// Bottom-sheet editor. Owns (and disposes) its own controllers so the sheet
/// can't leak or race the way a dialog with externally-owned controllers can.
class _EditSheet extends StatefulWidget {
  final CaregiverProfile current;
  const _EditSheet({required this.current});

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _name = TextEditingController(
      text: widget.current.name == 'Complete your profile' ? '' : widget.current.name);
  late final _bio = TextEditingController(text: widget.current.bio);
  late final _services = TextEditingController(text: widget.current.specialties.join(', '));
  late final _certs = TextEditingController(text: widget.current.certifications.join(', '));
  late final _experience = TextEditingController(
      text: widget.current.experienceYears == 0 ? '' : '${widget.current.experienceYears}');
  late final _hourly = TextEditingController(text: _num(widget.current.hourlyRate));
  late final _half = TextEditingController(text: _num(widget.current.rateHalfDay));
  late final _full = TextEditingController(text: _num(widget.current.rateFullDay));
  late final _multi = TextEditingController(text: _num(widget.current.rateMultiDay));
  late String _gender = widget.current.gender.isEmpty ? 'Female' : widget.current.gender;
  late final Set<String> _languages =
      widget.current.languages.isEmpty ? {'English'} : widget.current.languages.toSet();
  late String _city = widget.current.city;
  late double? _lat = widget.current.lat;
  late double? _lng = widget.current.lng;
  final _formKey = GlobalKey<FormState>();

  static String _num(num n) => n == 0 ? '' : '$n';

  @override
  void dispose() {
    for (final c in [_name, _bio, _services, _certs, _experience, _hourly, _half, _full, _multi]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _split(TextEditingController c) =>
      c.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _rate(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = num.tryParse(v.trim());
    return (n == null || n <= 0) ? 'Enter a valid amount' : null;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final hourly = num.parse(_hourly.text.trim());
    Navigator.pop(context, <String, dynamic>{
      'name': _name.text.trim(),
      'bio': _bio.text.trim(),
      'specialties': _split(_services),
      'certifications': _split(_certs),
      'languages': _languages.toList(),
      'experienceYears': int.tryParse(_experience.text.trim()) ?? 0,
      'hourlyRate': hourly,
      'rateHalfDay': num.tryParse(_half.text.trim()) ?? hourly * 4,
      'rateFullDay': num.tryParse(_full.text.trim()) ?? hourly * 8,
      'rateMultiDay': num.tryParse(_multi.text.trim()) ?? hourly * 8,
      'gender': _gender,
      'serviceType': 'care_assistant',
      'city': _city,
      if (_lat != null && _lng != null) 'lat': _lat,
      if (_lat != null && _lng != null) 'lng': _lng,
    });
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          shrinkWrap: true,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Edit Care Assistant Profile', style: AppTextStyles.h3),
            if (widget.current.status == 'active') ...[
              const SizedBox(height: 6),
              Text('Changes go live after a quick admin review.', style: AppTextStyles.bodySmall),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              validator: _required,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            gap,
            TextFormField(
              controller: _bio,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'About you',
                hintText: 'Tell patients how you can help',
              ),
            ),
            gap,
            Text('Gender', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['Female', 'Male']
                  .map((g) => ChoiceChip(
                        label: Text(g),
                        selected: _gender == g,
                        onSelected: (_) => setState(() => _gender = g),
                        selectedColor: careAssistantTeal.withValues(alpha: 0.16),
                      ))
                  .toList(),
            ),
            gap,
            TextFormField(
              controller: _services,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Services you offer',
                hintText: 'Hospital escort, report collection, medicine pickup',
                helperText: 'Comma separated',
              ),
            ),
            gap,
            TextFormField(
              controller: _certs,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Certifications', helperText: 'Comma separated'),
            ),
            gap,
            TextFormField(
              controller: _experience,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Years of experience'),
            ),
            const SizedBox(height: 20),
            const Text('Rates (₹)', style: AppTextStyles.labelLarge),
            const SizedBox(height: 10),
            TextFormField(
              controller: _hourly,
              keyboardType: TextInputType.number,
              validator: _rate,
              decoration: const InputDecoration(labelText: 'Hourly'),
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _half,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Half-day'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _full,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Full-day'),
                  ),
                ),
              ],
            ),
            gap,
            TextFormField(
              controller: _multi,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Multi-day (per day)',
                helperText: 'Blank tiers default to a multiple of your hourly rate',
              ),
            ),
            const SizedBox(height: 20),
            Text('Languages spoken', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allLanguages
                  .map((l) => FilterChip(
                        label: Text(l),
                        selected: _languages.contains(l),
                        selectedColor: careAssistantTeal.withValues(alpha: 0.16),
                        checkmarkColor: careAssistantTeal,
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _languages.add(l);
                          } else if (_languages.length > 1) {
                            _languages.remove(l);
                          }
                        }),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: () async {
                final result = await Navigator.of(context).push<PreciseAddress>(
                  MaterialPageRoute(builder: (_) => MapLocationPickerScreen(initialLat: _lat, initialLng: _lng)),
                );
                if (result == null) return;
                setState(() {
                  _city = result.city ?? _city;
                  _lat = result.lat;
                  _lng = result.lng;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Service area',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  suffixIcon: Icon(Icons.map_outlined, color: careAssistantTeal),
                ),
                child: Text(
                  _city.isEmpty ? 'Select on map' : _city,
                  style: TextStyle(color: _city.isEmpty ? AppColors.textHint : AppColors.textPrimary),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: careAssistantTeal,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
