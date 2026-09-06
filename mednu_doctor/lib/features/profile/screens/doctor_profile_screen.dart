import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/router/app_router.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../core/utils/validators.dart';
import '../../location/models/precise_address.dart';
import '../../location/screens/map_location_picker_screen.dart';

class DoctorProfileEditScreen extends StatefulWidget {
  const DoctorProfileEditScreen({super.key});
  @override
  State<DoctorProfileEditScreen> createState() => _DoctorProfileEditScreenState();
}

class _DoctorProfileEditScreenState extends State<DoctorProfileEditScreen> {
  final _nameCtrl       = TextEditingController();
  final _bioCtrl        = TextEditingController();
  final _feeCtrl        = TextEditingController();
  final _expCtrl        = TextEditingController();
  final _qualCtrl       = TextEditingController();
  final _clinicNameCtrl = TextEditingController();
  final _clinicAddrCtrl = TextEditingController();

  static const _specializations = [
    'General Physician', 'Cardiology', 'Dermatology', 'Gynaecology',
    'Paediatrics', 'Orthopaedics', 'Neurology', 'ENT', 'Oncology',
    'Psychiatry', 'Ophthalmology', 'Urology', 'Radiology', 'Anaesthesiology',
  ];

  static const _allLanguages = [
    'English', 'Telugu', 'Hindi', 'Tamil', 'Kannada',
    'Malayalam', 'Marathi', 'Bengali',
  ];

  String       _selectedSpec      = 'General Physician';
  List<String> _selectedLanguages = ['English'];
  bool         _loading           = true;
  bool         _saving            = false;
  bool         _hasPendingSpecRequest = false;
  String?      _nameError;
  String?      _clinicAddrError;
  double?      _clinicLat;
  double?      _clinicLng;
  String       _clinicCity = '';

  // Photo upload state
  File?   _localImage;
  bool    _uploading      = false;
  double  _uploadProgress = 0;
  String? _currentPhotoUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final data = await DoctorAuthService.getProfile(uid)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (data != null) {
        _nameCtrl.text       = data['name']       as String? ?? '';
        _bioCtrl.text        = data['bio']         as String? ?? data['about'] as String? ?? '';
        _feeCtrl.text        = (data['fee']        ?? '').toString();
        _expCtrl.text        = (data['experience'] ?? '').toString();
        _qualCtrl.text       = data['qualifications'] as String? ?? '';
        _clinicNameCtrl.text = data['clinicName']  as String? ?? '';
        _clinicAddrCtrl.text = data['clinicAddress'] as String? ?? '';
        _clinicLat           = (data['clinicLat'] as num?)?.toDouble();
        _clinicLng           = (data['clinicLng'] as num?)?.toDouble();
        _clinicCity          = data['clinicCity'] as String? ?? '';
        _currentPhotoUrl     = data['photoUrl']    as String?;

        final spec = data['specialty'] as String?;
        if (spec != null && _specializations.contains(spec)) _selectedSpec = spec;

        final langs = data['languages'];
        if (langs is List) _selectedLanguages = langs.cast<String>().toList();
      }

      // Check for pending specialization change request
      try {
        final specSnap = await FirebaseFirestore.instance
            .collection('doctor_specialization_requests')
            .where('doctorId', isEqualTo: uid)
            .where('status', whereIn: ['pending', 'under_review'])
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 10));
        _hasPendingSpecRequest = specSnap.docs.isNotEmpty;
      } catch (_) {
        _hasPendingSpecRequest = false;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to load profile: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;

    final name = _nameCtrl.text.trim();
    final nameError = Validators.name(name, label: 'Name');
    if (nameError != null) {
      setState(() => _nameError = nameError);
      return;
    }
    setState(() => _nameError = null);

    // Clinic address is mandatory — it drives the "Directions" link patients
    // use to navigate to an in-person appointment (see appointment_screen.dart
    // in the patient app), so a doctor profile without it breaks that flow.
    final clinicAddress = _clinicAddrCtrl.text.trim();
    if (clinicAddress.isEmpty) {
      setState(() => _clinicAddrError = 'Enter your clinic/hospital address');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Clinic address is required so patients can get directions to you.'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _clinicAddrError = null);

    setState(() => _saving = true);
    try {
      // Specialization is intentionally excluded — changes require admin approval
      await FirebaseFirestore.instance.collection('doctors').doc(uid).update({
        'name':           name,
        'bio':            _bioCtrl.text.trim(),
        'about':          _bioCtrl.text.trim(),
        'fee':            _feeCtrl.text.trim(),
        'experience':     _expCtrl.text.trim(),
        'qualifications': _qualCtrl.text.trim(),
        'clinicName':     _clinicNameCtrl.text.trim(),
        'clinicAddress':  clinicAddress,
        'languages':      _selectedLanguages,
        if (_clinicLat != null && _clinicLng != null) 'clinicLat': _clinicLat,
        if (_clinicLat != null && _clinicLng != null) 'clinicLng': _clinicLng,
        if (_clinicCity.isNotEmpty) 'clinicCity': _clinicCity,
        'updatedAt':      FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Profile updated successfully ✅'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
      context.safeBack();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to save: $e'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAddress() async {
    final result = await Navigator.of(context).push<PreciseAddress>(
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
            initialLat: _clinicLat, initialLng: _clinicLng),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _clinicAddrCtrl.text = result.formatted;
      _clinicLat = result.lat;
      _clinicLng = result.lng;
      _clinicCity = result.city ?? '';
      _clinicAddrError = null;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _feeCtrl.dispose();
    _expCtrl.dispose();
    _qualCtrl.dispose();
    _clinicNameCtrl.dispose();
    _clinicAddrCtrl.dispose();
    super.dispose();
  }

  // ── Photo picker ──────────────────────────────────────────

  void _showPhotoOptions() {
    final hasPhoto =
        (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) ||
        _localImage != null;

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
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text('Profile Photo',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              _SheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                color: AppColors.primary,
                onTap: () { Navigator.pop(context); _pickAndUpload(ImageSource.gallery); },
              ),
              const SizedBox(height: 12),
              _SheetOption(
                icon: Icons.camera_alt_rounded,
                label: 'Take a Photo',
                color: AppColors.secondary,
                onTap: () { Navigator.pop(context); _pickAndUpload(ImageSource.camera); },
              ),
              if (hasPhoto) ...[
                const SizedBox(height: 12),
                _SheetOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove Photo',
                  color: AppColors.error,
                  onTap: () { Navigator.pop(context); _removePhoto(); },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;

    File? file;
    try {
      file = source == ImageSource.gallery
          ? await ImageUploadService.pickFromGallery()
          : await ImageUploadService.pickFromCamera();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open picker: ${e.toString().replaceAll('Exception: ', '')}'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (file == null || !mounted) return;

    setState(() {
      _localImage     = file;
      _uploading      = true;
      _uploadProgress = 0;
    });

    try {
      final url = await ImageUploadService.uploadDoctorProfileImage(
        imageFile: file,
        uid: uid,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      await DoctorAuthService.updatePhotoUrl(uid, url);
      if (!mounted) return;
      setState(() {
        _currentPhotoUrl = url;
        _uploading       = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Profile photo updated!'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() { _uploading = false; _localImage = null; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Upload failed: ${_uploadError(e)}'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _removePhoto() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;

    setState(() => _uploading = true);
    try {
      await ImageUploadService.deleteDoctorProfileImage(uid);
      await DoctorAuthService.updatePhotoUrl(uid, '');
      if (!mounted) return;
      setState(() {
        _currentPhotoUrl = '';
        _localImage      = null;
        _uploading       = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Profile photo removed.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Remove failed: ${_removeError(e)}'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  String _uploadError(Object e) {
    final s = e.toString();
    if (s.contains('network') || s.contains('socket') || s.contains('connection')) {
      return 'Network error. Check your connection.';
    }
    if (s.contains('not-authorized') || s.contains('unauthorized') || s.contains('permission-denied')) {
      return 'Storage permission denied. Update Firebase Storage rules to allow writes.';
    }
    if (s.contains('quota')) return 'Storage quota exceeded.';
    return s.replaceAll('Exception: ', '');
  }

  String _removeError(Object e) {
    final s = e.toString();
    if (s.contains('object-not-found')) return 'No existing photo found to remove.';
    return s.replaceAll('Exception: ', '');
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
        imageBuilder: (_, imageProvider) =>
            CircleAvatar(radius: 45, backgroundImage: imageProvider),
        placeholder: (_, __) => _defaultAvatar(),
        errorWidget: (_, __, ___) => _defaultAvatar(),
      );
    } else {
      imageCircle = _defaultAvatar();
    }

    return GestureDetector(
      onTap: _uploading ? null : _showPhotoOptions,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha:0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(child: imageCircle),
              ),

              if (_uploading)
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha:0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 36, height: 36,
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
                  bottom: 0, right: 0,
                  child: Container(
                    width: 28, height: 28,
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

  Widget _defaultAvatar() {
    final name = _nameCtrl.text.trim();
    final initials = name.isNotEmpty
        ? name.split(' ').take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join()
        : '';
    return Container(
      width: 90,
      height: 90,
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: initials.isNotEmpty
            ? Text(
                initials,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1,
                ),
              )
            : const Icon(Icons.person_rounded, size: 50, color: Colors.white),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primary, AppColors.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.safeBack(),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _saveProfile,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const Center(child: SkeletonCircle(size: 100)),
                const SizedBox(height: 20),
                ...List.generate(6, (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: SkeletonBox(width: double.infinity, height: 52, radius: 12),
                )),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Avatar ──
                FadeInSlide(child: Center(child: _buildAvatar())),
                const SizedBox(height: 20),

                _sectionCard('Personal Info', [
                  _field('Full Name', _nameCtrl, errorText: _nameError),
                  const SizedBox(height: 12),
                  const Text('Specialization', style: AppTextStyles.labelLarge),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(children: [
                      const Icon(Icons.lock_rounded, size: 15, color: AppColors.textHint),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_selectedSpec,
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 14,
                              fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                      if (_hasPendingSpecRequest)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha:0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Pending',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 10,
                                  fontWeight: FontWeight.w700, color: AppColors.warning)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.specChangeRequest),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _hasPendingSpecRequest
                            ? AppColors.warning.withValues(alpha:0.08)
                            : AppColors.primary.withValues(alpha:0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _hasPendingSpecRequest
                              ? AppColors.warning.withValues(alpha:0.3)
                              : AppColors.primary.withValues(alpha:0.25),
                        ),
                      ),
                      child: Row(children: [
                        Icon(
                          _hasPendingSpecRequest
                              ? Icons.hourglass_empty_rounded
                              : Icons.swap_horiz_rounded,
                          size: 16,
                          color: _hasPendingSpecRequest ? AppColors.warning : AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          _hasPendingSpecRequest
                              ? 'View pending specialization request'
                              : 'Request specialization change',
                          style: TextStyle(
                            fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600,
                            color: _hasPendingSpecRequest ? AppColors.warning : AppColors.primary,
                          ),
                        )),
                        Icon(Icons.chevron_right_rounded, size: 16,
                            color: _hasPendingSpecRequest ? AppColors.warning : AppColors.primary),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),

                _sectionCard('Professional Details', [
                  _field('Bio / About', _bioCtrl, maxLines: 4),
                  const SizedBox(height: 12),
                  _field('Qualifications (e.g. MBBS, MD)', _qualCtrl),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _field('Experience (years)', _expCtrl, type: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(child: _field('Fee (₹)', _feeCtrl, type: TextInputType.number)),
                  ]),
                ]),
                const SizedBox(height: 16),

                _sectionCard('Languages Spoken', [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allLanguages.map((lang) => FilterChip(
                      label: Text(lang, style: const TextStyle(fontFamily: 'Inter', fontSize: 12)),
                      selected: _selectedLanguages.contains(lang),
                      selectedColor: AppColors.primary.withValues(alpha:0.12),
                      checkmarkColor: AppColors.primary,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedLanguages.add(lang);
                          } else if (_selectedLanguages.length > 1) {
                            _selectedLanguages.remove(lang);
                          }
                        });
                      },
                    )).toList(),
                  ),
                ]),
                const SizedBox(height: 16),

                _sectionCard('Clinic / Hospital Details', [
                  _field('Clinic / Hospital Name', _clinicNameCtrl),
                  const SizedBox(height: 12),
                  _field('Address *', _clinicAddrCtrl,
                      maxLines: 2, errorText: _clinicAddrError),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickAddress,
                    icon: Icon(_clinicLat != null ? Icons.check_circle_rounded : Icons.map_outlined,
                        size: 17, color: _clinicLat != null ? AppColors.success : AppColors.primary),
                    label: Text(
                      _clinicLat != null ? 'Location pinned on map — tap to change' : 'Pick precise location on map',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w600,
                          color: _clinicLat != null ? AppColors.success : AppColors.primary),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _clinicLat != null ? AppColors.success : AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      minimumSize: const Size(double.infinity, 0),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Required for in-person patients — used for map directions. '
                      'Pinning your exact location also lets nearby patients find and sort you by distance.',
                      style: TextStyle(
                          fontFamily: 'Inter', fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
                ]),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
          {TextInputType type = TextInputType.text, int maxLines = 1, String? errorText}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTextStyles.labelLarge),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: type,
          maxLines: maxLines,
          decoration: InputDecoration(errorText: errorText),
        ),
      ]);
}

Widget _sectionCard(String title, List<Widget> children) => Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Row(children: [
            Container(
              width: 4,
              height: 16,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(title, style: AppTextStyles.h4),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children),
        ),
      ]),
    );

// ── Sheet option tile ─────────────────────────────────────
class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SheetOption({
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
            color: color.withValues(alpha:0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                )),
          ]),
        ),
      );
}
