import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/doctor_auth_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/widgets/ux_widgets.dart';

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

  // ── Step 2: Professional ──────────────────────────────────────────────────
  final _regNoCtrl      = TextEditingController();
  final _qualCtrl       = TextEditingController();
  final _expCtrl        = TextEditingController();
  final _feeCtrl        = TextEditingController();
  final _otherSpecCtrl  = TextEditingController();
  String _selectedSpec  = 'General';
  String _professionalType = 'doctor'; // 'doctor' | 'therapist'

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

  // Shown instead of _specialties when registering as a Therapist —
  // names match the therapy types on the patient app's Counselling screen.
  static const _therapistSpecialties = [
    'Psychiatry',
    'Psychology',
    'Counselling',
    'Pediatric Psychiatry',
    'Other',
  ];

  List<String> get _activeSpecialties =>
      _professionalType == 'therapist' ? _therapistSpecialties : _specialties;

  // ── Step 3: Documents ─────────────────────────────────────────────────────
  File? _mbbsDegreeFile;
  File? _specCertFile;
  File? _mbbsRegCertFile;
  File? _renewalCertFile;
  File? _profilePhotoFile;

  // ── Signature ─────────────────────────────────────────────────────────────
  final _sigController = _SignatureController();

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
    super.dispose();
  }

  // ── Validation helpers ────────────────────────────────────────────────────

  bool get _allDocsUploaded =>
      _mbbsDegreeFile  != null &&
      _specCertFile    != null &&
      _mbbsRegCertFile != null &&
      _renewalCertFile != null &&
      _profilePhotoFile != null &&
      _sigController.hasSignature;

  void _nextPage() => _pageController.nextPage(
      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);

  bool _validatePage1() {
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('Please enter your full name'); return false;
    }
    if (_emailCtrl.text.trim().isEmpty ||
        !_emailCtrl.text.contains('@')) {
      _snack('Please enter a valid email address'); return false;
    }
    return true;
  }

  bool _validatePage2() {
    if (_selectedSpec == 'Other') {
      final customSpec = _otherSpecCtrl.text.trim();
      if (customSpec.isEmpty) {
        _snack('Please specify your specialization'); return false;
      }
      if (customSpec.length > 100) {
        _snack('Specialization must be under 100 characters'); return false;
      }
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
    if (_feeCtrl.text.trim().isEmpty) {
      _snack('Please enter your consultation fee'); return false;
    }
    return true;
  }

  String get _effectiveSpecialty =>
      _selectedSpec == 'Other' ? _otherSpecCtrl.text.trim() : _selectedSpec;

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
              title: const Text('Take a Photo', style: TextStyle(fontFamily: 'Poppins')),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
              title: const Text('Choose from Gallery', style: TextStyle(fontFamily: 'Poppins')),
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
      // Export signature as PNG bytes
      if (mounted) setState(() => _uploadStatus = 'Exporting signature…');
      final sigBytes = await _sigController.toBytes();
      if (sigBytes == null) {
        if (mounted) {
          setState(() { _isLoading = false; _uploadStatus = ''; });
          _snack('Could not export signature. Please redraw and try again.');
        }
        return;
      }

      // Upload all 5 documents to Firebase Storage
      final uploads = <String, Future<String>>{
        'mbbs_degree':    ImageUploadService.uploadDoctorDocument(file: _mbbsDegreeFile!,  uid: uid, docType: 'mbbs_degree'),
        'spec_cert':      ImageUploadService.uploadDoctorDocument(file: _specCertFile!,    uid: uid, docType: 'spec_cert'),
        'mbbs_reg_cert':  ImageUploadService.uploadDoctorDocument(file: _mbbsRegCertFile!, uid: uid, docType: 'mbbs_reg_cert'),
        'renewal_cert':   ImageUploadService.uploadDoctorDocument(file: _renewalCertFile!, uid: uid, docType: 'renewal_cert'),
        'profile_photo':  ImageUploadService.uploadDoctorDocument(file: _profilePhotoFile!, uid: uid, docType: 'profile_photo'),
      };

      final urls = <String, String>{};
      for (final entry in uploads.entries) {
        if (mounted) setState(() => _uploadStatus = 'Uploading ${_docLabel(entry.key)}…');
        urls[entry.key] = await entry.value;
      }

      if (mounted) setState(() => _uploadStatus = 'Uploading signature…');
      final signatureUrl = await ImageUploadService.uploadDoctorSignatureBytes(
        bytes: sigBytes,
        uid: uid,
      );

      if (mounted) setState(() => _uploadStatus = 'Saving profile…');

      await DoctorAuthService.saveProfile(
        uid: uid,
        name:               _nameCtrl.text.trim(),
        phone:              _phoneCtrl.text.trim().isNotEmpty
            ? _phoneCtrl.text.trim()
            : FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
        email:              _emailCtrl.text.trim(),
        type:               _professionalType,
        specialty:          _effectiveSpecialty,
        qualifications:     _qualCtrl.text.trim(),
        experience:         _expCtrl.text.trim(),
        fee:                _feeCtrl.text.trim(),
        gender:             _selectedGender,
        registrationNumber: _regNoCtrl.text.trim(),
        documentUrls:       urls,
        signatureUrl:       signatureUrl,
      );

      if (mounted) context.go(AppRoutes.verificationPending);
    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; _uploadStatus = ''; });
        _snack('Error: $e');
      }
    }
  }

  String _docLabel(String key) => const {
    'mbbs_degree':   'MBBS Degree',
    'spec_cert':     'Specialization Certificate',
    'mbbs_reg_cert': 'Registration Certificate',
    'renewal_cert':  'Renewal Certificate',
    'profile_photo': 'Profile Photo',
  }[key] ?? key;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Doctor Registration',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () {
            if (_currentPage > 0) {
              _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut);
            } else {
              context.canPop() ? context.pop() : context.go(AppRoutes.login);
            }
          },
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
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
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF7B1FA2), Color(0xFFC2185B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
    child: Row(
      children: List.generate(4, (i) {
        final isActive = i == _currentPage;
        final isDone   = i < _currentPage;
        return Expanded(
          child: Row(children: [
            Expanded(
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: isDone
                        ? AppColors.success
                        : isActive
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    boxShadow: isActive ? [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 2)),
                    ] : null,
                  ),
                  child: Icon(
                    isDone ? Icons.check_rounded : _stepIcons[i],
                    color: isDone
                        ? Colors.white
                        : isActive
                            ? AppColors.primary
                            : Colors.white.withValues(alpha: 0.7),
                    size: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _stepLabels[i],
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ]),
            ),
            if (i < 3)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 18),
                  color: isDone ? AppColors.success : Colors.white.withValues(alpha: 0.3),
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
          decoration: BoxDecoration(
              gradient: AppColors.primaryGradient, shape: BoxShape.circle),
          child: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 24),
        Text('Submitting Your Application',
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
      _SectionHeader(icon: Icons.person_rounded, title: 'Personal Information', subtitle: 'Tell us about yourself'),
      const SizedBox(height: 20),
      Center(child: Stack(children: [
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
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
      _Field('Full Name (as per medical license) *', _nameCtrl, 'Dr. Firstname Lastname'),
      const SizedBox(height: 14),
      _Field('Email Address *', _emailCtrl, 'doctor@example.com', type: TextInputType.emailAddress),
      const SizedBox(height: 14),
      _Field('Mobile Number', _phoneCtrl, '10-digit number (auto-filled)', type: TextInputType.phone),
      const SizedBox(height: 14),
      Text('Gender', style: AppTextStyles.labelLarge),
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
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
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
      _SectionHeader(icon: Icons.work_rounded, title: 'Professional Details', subtitle: 'Your medical qualifications'),
      const SizedBox(height: 20),
      Text('I am registering as a *', style: AppTextStyles.labelLarge),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: _TypeChoiceCard(
            label: 'Doctor',
            icon: Icons.local_hospital_rounded,
            selected: _professionalType == 'doctor',
            onTap: () => setState(() {
              _professionalType = 'doctor';
              _selectedSpec = _specialties.first;
              _otherSpecCtrl.clear();
            }),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TypeChoiceCard(
            label: 'Therapist',
            icon: Icons.psychology_rounded,
            selected: _professionalType == 'therapist',
            onTap: () => setState(() {
              _professionalType = 'therapist';
              _selectedSpec = _therapistSpecialties.first;
              _otherSpecCtrl.clear();
            }),
          ),
        ),
      ]),
      const SizedBox(height: 20),
      Text('Specialization *', style: AppTextStyles.labelLarge),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: _selectedSpec,
        isExpanded: true,
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          prefixIcon: const Icon(Icons.local_hospital_rounded, color: AppColors.primary, size: 20),
        ),
        items: _activeSpecialties.map((s) => DropdownMenuItem(
          value: s,
          child: Text(s, style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: s == 'Other' ? FontWeight.w600 : FontWeight.normal,
            color: s == 'Other' ? AppColors.primary : null,
          )),
        )).toList(),
        onChanged: (v) => setState(() {
          _selectedSpec = v!;
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
      _Field('Medical Registration Number *', _regNoCtrl, 'e.g. MCI-12345'),
      const SizedBox(height: 14),
      _Field('Qualifications *', _qualCtrl, 'e.g. MBBS, MD, DNB'),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _Field('Experience (years) *', _expCtrl, 'e.g. 10', type: TextInputType.number)),
        const SizedBox(width: 12),
        Expanded(child: _Field('Consultation Fee (₹) *', _feeCtrl, 'e.g. 500', type: TextInputType.number)),
      ]),
      const SizedBox(height: 32),
      _NextButton(onTap: () { if (_validatePage2()) _nextPage(); }),
    ]),
  );

  // ── PAGE 3 — Document Upload ──────────────────────────────────────────────

  Widget _buildPage3() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionHeader(icon: Icons.folder_rounded, title: 'Upload Documents', subtitle: 'All 5 documents are mandatory'),
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
        title: 'MBBS Degree Certificate',
        subtitle: 'Your MBBS degree from a recognized university',
        icon: Icons.school_rounded,
        file: _mbbsDegreeFile,
        onTap: () => _pickDoc('MBBS Degree', (f) => _mbbsDegreeFile = f),
      ),
      const SizedBox(height: 12),
      _DocUploadTile(
        title: 'Specialization Certificate',
        subtitle: 'MD / MS / DNB or equivalent post-graduate degree',
        icon: Icons.workspace_premium_rounded,
        file: _specCertFile,
        onTap: () => _pickDoc('Specialization Certificate', (f) => _specCertFile = f),
      ),
      const SizedBox(height: 12),
      _DocUploadTile(
        title: 'MBBS Registration Certificate',
        subtitle: 'MCI / State Medical Council registration',
        icon: Icons.card_membership_rounded,
        file: _mbbsRegCertFile,
        onTap: () => _pickDoc('MBBS Registration Certificate', (f) => _mbbsRegCertFile = f),
      ),
      const SizedBox(height: 12),
      _DocUploadTile(
        title: 'Renewal Certificate',
        subtitle: 'Medical Council license renewal document',
        icon: Icons.autorenew_rounded,
        file: _renewalCertFile,
        onTap: () => _pickDoc('Renewal Certificate', (f) => _renewalCertFile = f),
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

      // ── Doctor Signature ──────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.draw_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Doctor Signature *', style: AppTextStyles.labelLarge),
              Text('Sign in the box below using your finger',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
            ])),
            TextButton.icon(
              onPressed: () {
                _sigController.clear();
                setState(() {});
              },
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('Clear', style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: const Color(0xFFF9F9FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _sigController.hasSignature
                    ? AppColors.success
                    : AppColors.primary.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: _SignaturePad(controller: _sigController, onChanged: () => setState(() {})),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(
              _sigController.hasSignature ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              size: 14,
              color: _sigController.hasSignature ? AppColors.success : AppColors.textHint,
            ),
            const SizedBox(width: 6),
            Text(
              _sigController.hasSignature
                  ? 'Signature captured'
                  : 'This signature will appear on every prescription',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: _sigController.hasSignature ? AppColors.success : AppColors.textHint,
              ),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 16),

      // Progress indicator
      _DocsProgressBar(
        uploaded: [_mbbsDegreeFile, _specCertFile, _mbbsRegCertFile, _renewalCertFile, _profilePhotoFile]
            .where((f) => f != null).length,
        total: 5,
        signatureDone: _sigController.hasSignature,
      ),
      const SizedBox(height: 24),
      _NextButton(
        label: 'Next: Declaration',
        icon: Icons.arrow_forward_rounded,
        enabled: _allDocsUploaded,
        onTap: _allDocsUploaded
            ? _nextPage
            : () => _snack(
                !_sigController.hasSignature
                    ? 'Please draw your signature'
                    : 'Please upload all 5 required documents'),
      ),
    ]),
  );

  // ── PAGE 4 — Declaration & Terms ──────────────────────────────────────────

  Widget _buildPage4() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionHeader(icon: Icons.gavel_rounded, title: 'Declaration', subtitle: 'Review and accept before submitting'),
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
            Text('Professional Declaration', style: AppTextStyles.h4),
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
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
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
              decoration: BoxDecoration(color: const Color(0xFF7B1FA2).withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.description_rounded, color: Color(0xFF7B1FA2), size: 20),
            ),
            const SizedBox(width: 10),
            Text('Terms & Conditions', style: AppTextStyles.h4),
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
                'By registering on MedNU Doctor platform, you agree to:\n\n'
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
                  color: _termsAccepted ? const Color(0xFF7B1FA2) : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: _termsAccepted ? const Color(0xFF7B1FA2) : AppColors.border,
                      width: 2),
                ),
                child: _termsAccepted
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text(
                'I have read and agree to the MedNU Terms & Conditions and Privacy Policy.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
              )),
            ]),
          ),
        ]),
      ),

      const SizedBox(height: 24),

      GradientButton(
        label: 'Submit for Admin Approval',
        icon: Icons.send_rounded,
        width: double.infinity,
        height: 54,
        colors: (_declarationAccepted && _termsAccepted)
            ? null
            : [AppColors.divider, AppColors.divider],
        onTap: (_declarationAccepted && _termsAccepted) ? _submit : () => _snack('Please accept the declaration and terms to proceed'),
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

class _TypeChoiceCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TypeChoiceCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(children: [
        Icon(icon, color: selected ? AppColors.primary : AppColors.textSecondary, size: 24),
        const SizedBox(height: 6),
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ]),
    ),
  );
}

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
  Widget build(BuildContext context) => GradientButton(
    label: label,
    icon: icon,
    width: double.infinity,
    height: 52,
    colors: enabled ? null : [AppColors.divider, AppColors.divider],
    onTap: onTap,
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
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
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
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
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
  final bool signatureDone;
  const _DocsProgressBar({required this.uploaded, required this.total, this.signatureDone = false});

  @override
  Widget build(BuildContext context) {
    final steps = total + 1; // docs + signature
    final done = uploaded + (signatureDone ? 1 : 0);
    final pct = done / steps;
    final allDone = done == steps;
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
            allDone ? 'All documents & signature done!' : '$done of $steps steps complete',
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600,
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
      fontFamily: 'Poppins',
      fontSize: 12.5,
      height: 1.6,
      color: AppColors.textSecondary,
    ),
  );
}

// ── Signature Pad ─────────────────────────────────────────────────────────────

class _SignatureController {
  _SignaturePadState? _state;

  bool get hasSignature => _state?._isEmpty == false;

  void clear() => _state?._clear();

  Future<Uint8List?> toBytes() async {
    return _state?._toBytes();
  }
}

class _SignaturePad extends StatefulWidget {
  final _SignatureController controller;
  final VoidCallback onChanged;
  const _SignaturePad({required this.controller, required this.onChanged});

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final _repaintKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  List<Offset>? _current;

  bool get _isEmpty => _strokes.isEmpty || _strokes.every((s) => s.isEmpty);

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  void _clear() {
    setState(() => _strokes.clear());
    widget.onChanged();
  }

  Future<Uint8List?> _toBytes() async {
    final boundary = _repaintKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _repaintKey,
      child: GestureDetector(
        onPanStart: (d) {
          setState(() {
            _current = [d.localPosition];
            _strokes.add(_current!);
          });
        },
        onPanUpdate: (d) {
          setState(() => _current?.add(d.localPosition));
          widget.onChanged();
        },
        onPanEnd: (_) => _current = null,
        child: CustomPaint(
          painter: _SignaturePainter(_strokes),
          child: Container(
            color: const Color(0xFFF9F9FF),
            child: _isEmpty
                ? const Center(
                    child: Text(
                      'Sign here',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Color(0xFFBBBBCC),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) => true;
}

// ── Field ─────────────────────────────────────────────────────────────────────

Widget _Field(String label, TextEditingController ctrl, String hint,
    {TextInputType type = TextInputType.text}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AppTextStyles.labelLarge),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: type,
        style: AppTextStyles.bodyLarge,
        decoration: InputDecoration(
          hintText: hint,
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    ]);
