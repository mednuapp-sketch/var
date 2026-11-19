import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/doctor_auth_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/specialty_utils.dart';
import '../../../shared_core/documents/partner_document_models.dart';
import '../../../shared_core/documents/partner_other_documents.dart';
import '../../location/models/precise_address.dart';
import '../../location/screens/map_location_picker_screen.dart';

class DoctorRegisterScreen extends StatefulWidget {
  const DoctorRegisterScreen({super.key});
  @override
  State<DoctorRegisterScreen> createState() => _DoctorRegisterScreenState();
}

class _DoctorRegisterScreenState extends State<DoctorRegisterScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;
  String _uploadStatus = '';

  // ── Step 1: Personal ──────────────────────────────────────────────────────
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _selectedGender = 'Male';
  String? _nameError;
  String? _emailError;

  // ── Step 2: Professional ──────────────────────────────────────────────────
  final _regNoCtrl      = TextEditingController();
  final _qualCtrl       = TextEditingController();
  final _expCtrl        = TextEditingController();
  final _feeCtrl        = TextEditingController();
  final _otherSpecCtrl  = TextEditingController();
  final _clinicNameCtrl = TextEditingController();
  final _clinicAddrCtrl = TextEditingController();
  String? _selectedSpec;
  // 'online' | 'inperson' | 'both' — decides whether clinic details are asked.
  String _consultMode = 'online';
  bool get _needsClinic => _consultMode != 'online';
  String? _clinicAddrError;
  double? _clinicLat;
  double? _clinicLng;
  String _clinicCity = '';
  final List<String> _selectedLanguages = ['English'];

  // Matches the language list offered in profile-edit, and what the patient
  // app's "Find Doctors" filter sheet filters on — keep these three in sync.
  static const _allLanguages = [
    'English', 'Telugu', 'Hindi', 'Tamil', 'Kannada',
    'Malayalam', 'Marathi', 'Bengali',
  ];

  // Names match patient app specialty filters exactly so search/filter works
  static const _specialties = [
    'General',
    'Cardiology',
    'Dermatology',
    'Gynaecology',
    'Paediatrics',
    'ENT',
    'Orthopaedics',
    'Neurology',
    'Ophthalmology',
    'Psychiatry',
    'Psychology',
    'Counselling',
    'Pediatric Psychiatry',
    'Urology',
    'Gastroenterology',
    'General Surgery',
    'Dental',
    'Radiology',
    'Oncology',
    'Nephrology',
    'Endocrinology',
    'Pulmonology',
    'Anaesthesiology',
    'Rheumatology',
    'Other',
  ];

  // ── Step 3: Documents ─────────────────────────────────────────────────────
  File? _mbbsDegreeFile;      // UG degree
  File? _specCertFile;        // PG degree
  File? _mbbsRegCertFile;     // State registration (first)
  File? _stateReg2File;       // Additional state registrations (optional)
  File? _stateReg3File;
  File? _nationalRegFile;     // National registration
  File? _renewalCertFile;     // optional
  File? _otherCertFile;       // optional

  /// Optional extra documents (`other_doc_1..5`): typed title + picked image.
  final Map<String, String> _otherDocLabels = {};
  final Map<String, File> _otherDocFiles = {};
  File? _resumeFile;          // optional
  File? _profilePhotoFile;
  int _extraStateRegs = 0;    // how many optional state-registration slots are shown

  // ── Step 4: Declaration ───────────────────────────────────────────────────
  bool _declarationAccepted = false;
  bool _termsAccepted       = false;

  static const _stepLabels = ['Personal', 'Professional', 'Documents', 'Declaration'];
  static const _stepIcons  = [
    Icons.person_rounded,
    Icons.work_rounded,
    Icons.folder_rounded,
    Icons.gavel_rounded,
  ];

  @override
  void initState() {
    super.initState();
    // Phone comes from the OTP login; show it so the field is truly auto-filled.
    final digits = (FirebaseAuth.instance.currentUser?.phoneNumber ?? '')
        .replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      _phoneCtrl.text = digits.substring(digits.length - 10);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _regNoCtrl.dispose();
    _qualCtrl.dispose();
    _expCtrl.dispose();
    _feeCtrl.dispose();
    _otherSpecCtrl.dispose();
    _clinicNameCtrl.dispose();
    _clinicAddrCtrl.dispose();
    super.dispose();
  }

  // ── Validation helpers ────────────────────────────────────────────────────

  /// Dental specialty => BDS/MDS/DCI document set (PG optional, renewal required).
  bool get _dental => isDentalSpecialty(_effectiveSpecialty);

  /// Files that must be present for the current specialty (always 5).
  List<File?> get _requiredDocFiles => [
        _mbbsDegreeFile,
        if (!_dental) _specCertFile,
        _mbbsRegCertFile,
        _nationalRegFile,
        if (_dental) _renewalCertFile,
        _profilePhotoFile,
      ];

  bool get _allDocsUploaded => _requiredDocFiles.every((f) => f != null);

  void _nextPage() => _pageController.nextPage(
      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

  bool _validatePage1() {
    final nameErr = Validators.name(_nameCtrl.text, label: 'Full Name');
    final emailErr = Validators.email(_emailCtrl.text);
    setState(() {
      _nameError = nameErr;
      _emailError = emailErr;
    });
    return nameErr == null && emailErr == null;
  }

  bool _validatePage2() {
    if (_selectedSpec == null) {
      _snack('Please select your specialization'); return false;
    }
    if (_selectedSpec == 'Other' && _otherSpecCtrl.text.trim().isEmpty) {
      _snack('Please specify your specialization'); return false;
    }
    if (_regNoCtrl.text.trim().isEmpty) {
      _snack('Please enter your registration number'); return false;
    }
    if (_qualCtrl.text.trim().isEmpty) {
      _snack('Please enter your qualifications'); return false;
    }
    if (_expCtrl.text.trim().isEmpty) {
      _snack('Please enter years of experience'); return false;
    }
    if (Validators.money(_feeCtrl.text, min: 1) != null) {
      _snack('Please enter a valid consultation fee'); return false;
    }
    if (int.tryParse(_expCtrl.text.trim()) == null) {
      _snack('Please enter your experience as a number of years'); return false;
    }
    if (_needsClinic && _clinicAddrCtrl.text.trim().isEmpty) {
      setState(() => _clinicAddrError = 'Enter your clinic/hospital consultation address');
      _snack('Please enter your consultation address'); return false;
    }
    setState(() => _clinicAddrError = null);
    return true;
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

  String get _effectiveSpecialty =>
      _selectedSpec == 'Other' ? _otherSpecCtrl.text.trim() : (_selectedSpec ?? '');

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  // ── Document picker ───────────────────────────────────────────────────────

  Future<void> _pickDoc(String label, void Function(File f) onPicked) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
            Text('Upload $label',
                style: AppTextStyles.h4.copyWith(fontSize: 15)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
              title: const Text('Take a Photo', style: TextStyle(fontFamily: 'Inter')),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
              title: const Text('Choose from Gallery', style: TextStyle(fontFamily: 'Inter')),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
          ]),
        ),
      ),
    );
    if (choice == null) return;
    final file = choice == 'camera'
        ? await ImageUploadService.pickDocumentFromCamera()
        : await ImageUploadService.pickDocument();
    if (file != null && mounted) setState(() => onPicked(file));
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    // Re-check every step, not just the documents, so no earlier page's
    // details can be skipped on the way to the final submit.
    if (!_validatePage1() || !_validatePage2()) return;
    final docFiles = _requiredDocFiles;
    // Optional files (incl. whichever of PG / renewal is optional for the
    // current specialty) only need to exist on disk when they were picked.
    final optionalFiles = [_stateReg2File, _stateReg3File,
        if (_dental) _specCertFile else _renewalCertFile,
        _otherCertFile, _resumeFile];
    if (!_allDocsUploaded ||
        docFiles.any((f) => !f!.existsSync()) ||
        optionalFiles.any((f) => f != null && !f.existsSync()) ||
        _otherDocFiles.values.any((f) => !f.existsSync())) {
      _snack('Please upload all required documents before submitting');
      return;
    }
    if (!_declarationAccepted || !_termsAccepted) {
      _snack('Please accept the declaration and terms to proceed'); return;
    }
    final uid = DoctorAuthService.currentUid;
    if (uid == null) {
      _snack('Session expired. Please login again.');
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    setState(() { _isLoading = true; _uploadStatus = 'Uploading documents…'; });

    try {
      // Upload required + any optional documents the doctor chose to add.
      final files = <String, File?>{
        'mbbs_degree':       _mbbsDegreeFile,
        'spec_cert':         _specCertFile,
        'mbbs_reg_cert':     _mbbsRegCertFile,
        'state_reg_cert_2':  _stateReg2File,
        'state_reg_cert_3':  _stateReg3File,
        'national_reg_cert': _nationalRegFile,
        'renewal_cert':      _renewalCertFile,
        'other_cert':        _otherCertFile,
        'resume':            _resumeFile,
        'profile_photo':     _profilePhotoFile,
      };
      final uploads = <String, Future<String>>{
        for (final e in files.entries)
          if (e.value != null)
            e.key: ImageUploadService.uploadDoctorDocument(
                file: e.value!, uid: uid, docType: e.key),
      };

      // Values are Storage PATHS (never download URLs) — see uploadDoctorDocument.
      final urls = <String, String>{};
      for (final entry in uploads.entries) {
        if (mounted) setState(() => _uploadStatus = 'Uploading ${_docLabel(entry.key)}…');
        urls[entry.key] = await entry.value;
      }
      // The profile photo doubles as the public avatar (`photoUrl`), so it is
      // ALSO stored at the public-read `doctors/{uid}/profile.jpg` path. The
      // copy under docs/ stays private and only its path is recorded.
      String photoUrl = '';
      if (_profilePhotoFile != null) {
        try {
          photoUrl = await ImageUploadService.uploadDoctorProfileImage(
              imageFile: _profilePhotoFile!, uid: uid);
        } catch (_) {
          // Avatar is best-effort (e.g. >5 MB); the doctor can re-upload it
          // from their profile. Registration must not fail because of it.
          photoUrl = '';
        }
      }
      // Optional "Other documents" — skipped entirely when none were added.
      final docLabels = <String, String>{};
      for (final e in _otherDocFiles.entries) {
        final title = _otherDocLabels[e.key] ?? '';
        if (mounted) setState(() => _uploadStatus = 'Uploading ${title.isEmpty ? 'other document' : title}…');
        urls[e.key] = await ImageUploadService.uploadDoctorDocument(
            file: e.value, uid: uid, docType: e.key);
        if (title.isNotEmpty) docLabels[e.key] = title;
      }

      if (mounted) setState(() => _uploadStatus = 'Saving profile…');

      await DoctorAuthService.saveProfile(
        uid: uid,
        name:               _nameCtrl.text.trim(),
        phone:              _phoneCtrl.text.trim().isNotEmpty
            ? _phoneCtrl.text.trim()
            : FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
        email:              _emailCtrl.text.trim(),
        specialty:          _effectiveSpecialty,
        qualifications:     _qualCtrl.text.trim(),
        experience:         _expCtrl.text.trim(),
        fee:                _feeCtrl.text.trim(),
        gender:             _selectedGender,
        registrationNumber: _regNoCtrl.text.trim(),
        clinicName:         _needsClinic ? _clinicNameCtrl.text.trim() : '',
        clinicAddress:      _needsClinic ? _clinicAddrCtrl.text.trim() : '',
        languages:          _selectedLanguages,
        clinicLat:          _needsClinic ? _clinicLat : null,
        clinicLng:          _needsClinic ? _clinicLng : null,
        clinicCity:         _needsClinic ? _clinicCity : '',
        documentPaths:      urls,
        photoUrl:           photoUrl,
        documentLabels:     docLabels,
      );

      if (mounted) context.go(AppRoutes.verificationPending);
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; _uploadStatus = ''; });
        _snack(Validators.friendlyError(e));
      }
    }
  }

  String _docLabel(String key) =>
      doctorDocLabels(dental: _dental)[key] ?? key;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Doctor Registration'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (_currentPage > 0) {
              _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut);
            } else {
              context.pop();
            }
          },
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildStepBar(),
          Expanded(
            child: _isLoading
                ? _buildUploadingOverlay()
                : PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    children: [
                      _buildPage1(),
                      _buildPage2(),
                      _buildPage3(),
                      _buildPage4(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Step progress bar ─────────────────────────────────────────────────────

  Widget _buildStepBar() => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 14),
    child: Row(
      children: List.generate(4, (i) {
        final isActive = i == _currentPage;
        final isDone   = i < _currentPage;
        final lineColor = (i < _currentPage) ? AppColors.success : AppColors.divider;
        final prevLineColor = (i - 1 < _currentPage) ? AppColors.success : AppColors.divider;
        return Expanded(
          child: Column(children: [
            SizedBox(
              height: 32,
              child: Stack(alignment: Alignment.center, children: [
                // Connector lines run centre-to-edge so circles stay centred
                // over their (equal-width) label columns.
                Row(children: [
                  Expanded(
                    child: Container(
                        height: 2, color: i == 0 ? Colors.transparent : prevLineColor),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    child: Container(
                        height: 2, color: i == 3 ? Colors.transparent : lineColor),
                  ),
                ]),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: isDone ? AppColors.success
                        : isActive ? AppColors.primary
                        : AppColors.divider,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isDone ? Icons.check_rounded : _stepIcons[i],
                    color: (isDone || isActive) ? Colors.white : AppColors.textHint,
                    size: 16,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _stepLabels[i],
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? AppColors.primary : AppColors.textHint,
                  ),
                ),
              ),
            ),
          ]),
        );
      }),
    ),
  );

  // ── Uploading overlay ─────────────────────────────────────────────────────

  Widget _buildUploadingOverlay() => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient, shape: BoxShape.circle),
          child: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 24),
        const Text('Submitting Your Application',
            style: AppTextStyles.h4, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(_uploadStatus,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center),
        const SizedBox(height: 28),
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Text('Please do not close the app',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
      ]),
    ),
  );

  // ── PAGE 1 — Personal Info ────────────────────────────────────────────────

  Widget _buildPage1() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionHeader(icon: Icons.person_rounded, title: 'Personal Information', subtitle: 'Tell us about yourself'),
      const SizedBox(height: 20),
      Center(child: Stack(children: [
        Container(
          width: 96, height: 96,
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 52),
        ),
        Positioned(bottom: 0, right: 0, child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
              color: AppColors.primary, shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5)),
          child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
        )),
      ])),
      const SizedBox(height: 24),
      _field('Full Name (as per medical license) *', _nameCtrl, 'Dr. Firstname Lastname',
          errorText: _nameError,
          onChanged: (_) { if (_nameError != null) setState(() => _nameError = null); }),
      const SizedBox(height: 14),
      _field('Email Address *', _emailCtrl, 'doctor@example.com', type: TextInputType.emailAddress,
          errorText: _emailError,
          onChanged: (_) { if (_emailError != null) setState(() => _emailError = null); }),
      const SizedBox(height: 14),
      _field('Mobile Number', _phoneCtrl, '10-digit number (auto-filled)', type: TextInputType.phone),
      const SizedBox(height: 14),
      const Text('Gender', style: AppTextStyles.labelLarge),
      const SizedBox(height: 8),
      Row(children: ['Male', 'Female', 'Other'].map((g) => Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _selectedGender = g),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _selectedGender == g ? AppColors.primary.withValues(alpha:0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _selectedGender == g ? AppColors.primary : AppColors.border,
                  width: _selectedGender == g ? 2 : 1),
            ),
            child: Text(g, textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _selectedGender == g ? AppColors.primary : AppColors.textSecondary)),
          ),
        ),
      )).toList()),
      const SizedBox(height: 32),
      _NextButton(onTap: () { if (_validatePage1()) _nextPage(); }),
    ]),
  );

  // ── PAGE 2 — Professional Details ─────────────────────────────────────────

  Widget _buildPage2() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionHeader(icon: Icons.work_rounded, title: 'Professional Details', subtitle: 'Your medical qualifications'),
      const SizedBox(height: 20),
      const Text('Specialization *', style: AppTextStyles.labelLarge),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _selectedSpec,
        isExpanded: true,
        hint: Text('Select your specialization',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          prefixIcon: const Icon(Icons.local_hospital_rounded, color: AppColors.primary, size: 20),
        ),
        items: _specialties.map((s) => DropdownMenuItem(
          value: s,
          child: Text(s, style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: s == 'Other' ? FontWeight.w600 : FontWeight.normal,
            color: s == 'Other' ? AppColors.primary : null,
          )),
        )).toList(),
        onChanged: (v) => setState(() {
          _selectedSpec = v;
          if (v != 'Other') _otherSpecCtrl.clear();
        }),
      ),
      if (_selectedSpec == 'Other') ...[
        const SizedBox(height: 12),
        TextFormField(
          controller: _otherSpecCtrl,
          textCapitalization: TextCapitalization.words,
          style: AppTextStyles.bodyMedium,
          decoration: InputDecoration(
            labelText: 'Please specify your specialization *',
            labelStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            hintText: 'e.g. Sports Medicine, Geriatrics…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
            filled: true, fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            prefixIcon: const Icon(Icons.edit_rounded, color: AppColors.primary, size: 20),
          ),
        ),
      ],
      const SizedBox(height: 14),
      _field('Medical Registration Number *', _regNoCtrl, 'e.g. MCI-12345'),
      const SizedBox(height: 14),
      _field('Qualifications *', _qualCtrl, 'e.g. MBBS, MD, DNB'),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _field('Experience (years) *', _expCtrl, 'e.g. 10', type: TextInputType.number)),
        const SizedBox(width: 12),
        Expanded(child: _field('Consultation Fee (₹) *', _feeCtrl, 'e.g. 500', type: TextInputType.number)),
      ]),
      const SizedBox(height: 20),
      const _SectionHeader(icon: Icons.translate_rounded, title: 'Languages Spoken', subtitle: 'Patients can filter doctors by language'),
      const SizedBox(height: 12),
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
      const SizedBox(height: 20),
      const _SectionHeader(icon: Icons.event_available_rounded, title: 'How will you consult?', subtitle: 'Choose how patients can book you'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in const [
          ('online', 'Online', Icons.videocam_rounded),
          ('inperson', 'In-person', Icons.local_hospital_rounded),
          ('both', 'Both', Icons.swap_horiz_rounded),
        ])
          ChoiceChip(
            avatar: Icon(m.$3, size: 16,
                color: _consultMode == m.$1 ? AppColors.primary : AppColors.textSecondary),
            label: Text(m.$2, style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
            selected: _consultMode == m.$1,
            selectedColor: AppColors.primary.withValues(alpha: 0.12),
            showCheckmark: false,
            onSelected: (_) => setState(() {
              _consultMode = m.$1;
              _clinicAddrError = null;
            }),
          ),
      ]),
      if (_needsClinic) ..._clinicSection(),
      const SizedBox(height: 32),
      _NextButton(onTap: () { if (_validatePage2()) _nextPage(); }),
    ]),
  );

  List<Widget> _clinicSection() => [
      const SizedBox(height: 20),
      const _SectionHeader(icon: Icons.local_hospital_rounded, title: 'Clinic / Hospital Details', subtitle: 'Where patients will meet you in person'),
      const SizedBox(height: 14),
      _field('Clinic / Hospital Name', _clinicNameCtrl, 'e.g. Sunshine Multispeciality Clinic'),
      const SizedBox(height: 14),
      _field('Consultation Address *', _clinicAddrCtrl, 'Full address for in-person visits',
          maxLines: 2,
          errorText: _clinicAddrError,
          onChanged: (_) { if (_clinicAddrError != null) setState(() => _clinicAddrError = null); }),
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
          'Required for in-person patients — shown on your profile and used for map directions. '
          'Pinning your exact location also lets nearby patients find and sort you by distance.',
          style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.textSecondary),
        ),
      ),
  ];

  // ── Optional "Other documents" (other_doc_1..5, typed titles) ────────────

  List<Widget> _otherDocsBlock() {
    final keys = _otherDocLabels.keys.toList()..sort();
    final atCap = keys.length >= PartnerDocumentType.maxOtherDocs;
    return [
      const OtherDocumentsHeading(),
      const SizedBox(height: 4),
      const Text(
        'If you have any other documents, you can add them here (up to 5). Optional.',
        style: AppTextStyles.caption,
      ),
      const SizedBox(height: 10),
      for (final k in keys) ...[
        _DocUploadTile(
          title: _otherDocLabels[k] ?? 'Other document',
          subtitle: 'Optional · tap to replace',
          icon: Icons.description_rounded,
          file: _otherDocFiles[k],
          onTap: () => _pickDoc(_otherDocLabels[k] ?? 'Other document',
              (f) => _otherDocFiles[k] = f),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _otherDocLabels.remove(k);
              _otherDocFiles.remove(k);
            }),
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Remove'),
          ),
        ),
      ],
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: atCap ? null : _addOtherDoc,
          icon: const Icon(Icons.add_rounded),
          label: Text(atCap
              ? 'Maximum ${PartnerDocumentType.maxOtherDocs} documents added'
              : 'Add another document'),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  Future<void> _addOtherDoc() async {
    final key = PartnerDocumentType.nextFreeOtherDocKey(_otherDocLabels.keys);
    if (key == null) return;
    final title = await askOtherDocumentTitle(context);
    if (title == null || !mounted) return;
    await _pickDoc(title, (f) {
      _otherDocLabels[key] = title;
      _otherDocFiles[key] = f;
    });
  }

  // ── PAGE 3 — Document Upload ──────────────────────────────────────────────

  Widget _buildPage3() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionHeader(icon: Icons.folder_rounded, title: 'Upload Documents', subtitle: 'Documents marked optional can be skipped'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha:0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha:0.2)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Upload clear, legible photos or scans. All documents must be valid and unexpired.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, height: 1.5),
          )),
        ]),
      ),
      const SizedBox(height: 20),
      _DocUploadTile(
        title: _dental ? 'BDS Degree' : 'UG Degree',
        subtitle: _dental
            ? 'Bachelor of Dental Surgery degree from a recognised university'
            : 'MBBS / BDS / BAMS or equivalent undergraduate degree',
        icon: Icons.school_rounded,
        file: _mbbsDegreeFile,
        onTap: () => _pickDoc(_docLabel('mbbs_degree'), (f) => _mbbsDegreeFile = f),
      ),
      const SizedBox(height: 12),
      _DocUploadTile(
        title: _dental ? 'MDS Degree (optional)' : 'PG Degree',
        subtitle: _dental
            ? 'Master of Dental Surgery or other post-graduate dental degree'
            : 'MD / MS / DNB or equivalent post-graduate degree',
        icon: Icons.workspace_premium_rounded,
        file: _specCertFile,
        onTap: () => _pickDoc(_docLabel('spec_cert'), (f) => _specCertFile = f),
      ),
      const SizedBox(height: 12),
      _DocUploadTile(
        title: _dental ? 'State Dental Council Registration' : 'Registration - State',
        subtitle: _dental
            ? 'Registration with your State Dental Council'
            : 'State Medical Council registration',
        icon: Icons.card_membership_rounded,
        file: _mbbsRegCertFile,
        onTap: () => _pickDoc(_docLabel('mbbs_reg_cert'), (f) => _mbbsRegCertFile = f),
      ),
      if (_extraStateRegs >= 1) ...[
      const SizedBox(height: 12),
      _DocUploadTile(
        title: _dental ? 'State Dental Council Registration 2 (optional)' : 'Registration - State 2 (optional)',
        subtitle: _dental
            ? 'Registration with another State Dental Council'
            : 'Registration with another State Medical Council',
        icon: Icons.card_membership_rounded,
        file: _stateReg2File,
        onTap: () => _pickDoc(_docLabel('state_reg_cert_2'), (f) => _stateReg2File = f),
      ),
      ],
      if (_extraStateRegs >= 2) ...[
      const SizedBox(height: 12),
      _DocUploadTile(
        title: _dental ? 'State Dental Council Registration 3 (optional)' : 'Registration - State 3 (optional)',
        subtitle: _dental
            ? 'Registration with another State Dental Council'
            : 'Registration with another State Medical Council',
        icon: Icons.card_membership_rounded,
        file: _stateReg3File,
        onTap: () => _pickDoc(_docLabel('state_reg_cert_3'), (f) => _stateReg3File = f),
      ),
      ],
      if (_extraStateRegs < 2)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _extraStateRegs++),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add another state registration'),
          ),
        ),
      const SizedBox(height: 12),
      _DocUploadTile(
        title: _dental ? 'Dental Council of India (DCI) Registration' : 'Registration - National',
        subtitle: _dental
            ? 'Dental Council of India registration'
            : 'National Medical Commission (NMC) registration',
        icon: Icons.verified_user_rounded,
        file: _nationalRegFile,
        onTap: () => _pickDoc(_dental ? 'DCI Registration' : 'National Registration', (f) => _nationalRegFile = f),
      ),
      const SizedBox(height: 12),
      _DocUploadTile(
        title: _dental ? 'Renewal Certificate' : 'Renewal Certificate (optional)',
        subtitle: _dental
            ? 'Dental Council registration renewal document'
            : 'Medical Council license renewal document',
        icon: Icons.autorenew_rounded,
        file: _renewalCertFile,
        onTap: () => _pickDoc('Renewal Certificate', (f) => _renewalCertFile = f),
      ),
      const SizedBox(height: 12),
      _DocUploadTile(
        title: _dental ? 'Other Certificates (optional)' : 'Other Certificate (optional)',
        subtitle: 'Any additional qualification or certificate',
        icon: Icons.description_rounded,
        file: _otherCertFile,
        onTap: () => _pickDoc('Other Certificate', (f) => _otherCertFile = f),
      ),
      const SizedBox(height: 12),
      ..._otherDocsBlock(),
      _DocUploadTile(
        title: 'Resume (optional)',
        subtitle: 'Your CV / professional resume',
        icon: Icons.article_rounded,
        file: _resumeFile,
        onTap: () => _pickDoc('Resume', (f) => _resumeFile = f),
      ),
      const SizedBox(height: 12),
      _DocUploadTile(
        title: 'Profile Photo',
        subtitle: 'Clear passport-size photo of yourself',
        icon: Icons.person_rounded,
        file: _profilePhotoFile,
        onTap: () => _pickDoc('Profile Photo', (f) => _profilePhotoFile = f),
      ),
      const SizedBox(height: 20),
      // Progress indicator
      _DocsProgressBar(
        uploaded: _requiredDocFiles.where((f) => f != null).length,
        total: _requiredDocFiles.length,
      ),
      const SizedBox(height: 24),
      _NextButton(
        label: 'Next: Declaration',
        icon: Icons.arrow_forward_rounded,
        enabled: _allDocsUploaded,
        onTap: _allDocsUploaded ? _nextPage : () => _snack('Please upload all required documents'),
      ),
    ]),
  );

  // ── PAGE 4 — Declaration & Terms ──────────────────────────────────────────

  Widget _buildPage4() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionHeader(icon: Icons.gavel_rounded, title: 'Declaration', subtitle: 'Review and accept before submitting'),
      const SizedBox(height: 20),

      // Declaration card
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.medical_services_rounded, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Professional Declaration', style: AppTextStyles.h4),
          ]),
          const SizedBox(height: 16),
          const _DeclText(
            'I, the undersigned, hereby declare that:\n\n'
            '1. I wish to continue to work with MedNU as a registered medical professional on this platform.\n\n'
            '2. All the information and documents submitted by me are true, correct, and authentic to the best of my knowledge.\n\n'
            '3. I hold a valid medical license and am authorized to practice medicine in India.\n\n'
            '4. I will maintain professional standards and ethics while providing medical consultations through MedNU.\n\n'
            '5. I understand that providing false information may result in immediate termination of my account and may attract legal consequences.\n\n'
            '6. I consent to MedNU verifying my credentials with the relevant medical authorities.',
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _declarationAccepted = !_declarationAccepted),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: _declarationAccepted ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: _declarationAccepted ? AppColors.primary : AppColors.border,
                      width: 2),
                ),
                child: _declarationAccepted
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text(
                'I confirm that I wish to work with MedNU as a medical professional and all the above statements are true.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.5),
              )),
            ]),
          ),
        ]),
      ),

      const SizedBox(height: 16),

      // Terms & Conditions card
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.description_rounded, color: AppColors.secondary, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Terms & Conditions', style: AppTextStyles.h4),
          ]),
          const SizedBox(height: 14),
          Container(
            height: 140,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: const SingleChildScrollView(
              child: _DeclText(
                'By registering on MedNU Service platform, you agree to:\n\n'
                '• Provide accurate and up-to-date medical consultations to patients.\n\n'
                '• Maintain patient confidentiality and comply with applicable privacy laws.\n\n'
                '• Not misuse the platform for non-medical solicitation or advertising.\n\n'
                '• Allow MedNU to display your profile, ratings, and reviews to patients.\n\n'
                '• Respond to patient consultations in a timely and professional manner.\n\n'
                '• Comply with the Indian Medical Council Act and all applicable medical regulations.\n\n'
                '• Allow MedNU to collect a platform service fee per consultation as per the agreed rate.\n\n'
                '• Accept that MedNU may suspend or terminate your account for violations of these terms.',
              ),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => setState(() => _termsAccepted = !_termsAccepted),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: _termsAccepted ? AppColors.secondary : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: _termsAccepted ? AppColors.secondary : AppColors.border,
                      width: 2),
                ),
                child: _termsAccepted
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text(
                'I have read and agree to the MedNU Terms & Conditions and Privacy Policy.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.5),
              )),
            ]),
          ),
        ]),
      ),

      const SizedBox(height: 24),

      // Submit button
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_declarationAccepted && _termsAccepted) ? _submit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.divider,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.send_rounded, size: 18),
            SizedBox(width: 8),
            Text('Submit for Admin Approval',
                style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Center(child: Text(
        'Your application will be reviewed by our admin team.\nYou will be notified once approved.',
        textAlign: TextAlign.center,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint, height: 1.5),
      )),
    ]),
  );
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _SectionHeader({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 44, height: 44,
      decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: Colors.white, size: 22),
    ),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: AppTextStyles.h4),
      Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
    ])),
  ]);
}

class _NextButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final bool enabled;
  const _NextButton({
    required this.onTap,
    this.label = 'Next',
    this.icon = Icons.arrow_forward_rounded,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: enabled ? onTap : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.divider,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Icon(icon, size: 18),
      ]),
    ),
  );
}

class _DocUploadTile extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final File? file;
  final VoidCallback onTap;
  const _DocUploadTile({
    required this.title, required this.subtitle,
    required this.icon, required this.file, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final uploaded = file != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: uploaded ? AppColors.success.withValues(alpha:0.04) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: uploaded ? AppColors.success.withValues(alpha:0.5) : AppColors.border,
            width: uploaded ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: (uploaded ? AppColors.success : AppColors.primary).withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: uploaded
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(file!, fit: BoxFit.cover),
                  )
                : Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title,
                  style: AppTextStyles.labelLarge.copyWith(
                      color: uploaded ? AppColors.success : AppColors.textPrimary))),
              if (uploaded) const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
            ]),
            const SizedBox(height: 2),
            Text(subtitle, style: AppTextStyles.bodySmall),
          ])),
          const SizedBox(width: 8),
          if (!uploaded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
              child: const Text('Upload',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11,
                      fontWeight: FontWeight.w700, color: Colors.white)),
            )
          else
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.success.withValues(alpha:0.3))),
                child: const Text('Change',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 11,
                        fontWeight: FontWeight.w600, color: AppColors.success)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _DocsProgressBar extends StatelessWidget {
  final int uploaded, total;
  const _DocsProgressBar({required this.uploaded, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = uploaded / total;
    final allDone = uploaded == total;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: allDone ? AppColors.success.withValues(alpha:0.06) : AppColors.warning.withValues(alpha:0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: allDone ? AppColors.success.withValues(alpha:0.3) : AppColors.warning.withValues(alpha:0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(allDone ? Icons.check_circle_rounded : Icons.upload_file_rounded,
              color: allDone ? AppColors.success : AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Text(
            allDone ? 'All documents uploaded!' : '$uploaded of $total documents uploaded',
            style: TextStyle(
                fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600,
                color: allDone ? AppColors.success : AppColors.warning),
          ),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation(allDone ? AppColors.success : AppColors.warning),
            minHeight: 6,
          ),
        ),
      ]),
    );
  }
}

class _DeclText extends StatelessWidget {
  final String text;
  const _DeclText(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 12.5,
      height: 1.6,
      color: AppColors.textSecondary,
    ),
  );
}

Widget _field(String label, TextEditingController ctrl, String hint,
    {TextInputType type = TextInputType.text, String? errorText, ValueChanged<String>? onChanged, int maxLines = 1}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AppTextStyles.labelLarge),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: type,
        maxLines: maxLines,
        style: AppTextStyles.bodyLarge,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          filled: true, fillColor: Colors.white,
          errorText: errorText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.error)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.error, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    ]);
