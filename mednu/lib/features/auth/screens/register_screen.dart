import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/image_upload_service.dart';
import '../../referral/referral_service.dart';
import '../providers/auth_provider.dart';

const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'];

class RegisterScreen extends ConsumerStatefulWidget {
  final String phone;
  const RegisterScreen({super.key, this.phone = ''});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _dobCtrl     = TextEditingController();
  final _cityCtrl    = TextEditingController();
  final _referralCtrl = TextEditingController();

  String  _selectedGender    = 'Male';
  String? _selectedBloodGroup;
  bool    _isLoading         = false;
  bool    _termsAccepted     = false;
  File?   _profileImage;
  double  _uploadProgress    = 0;

  Timer? _debounce;
  bool   _isValidatingCode   = false;
  ReferralValidationResult? _codeResult;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeIn;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _debounce?.cancel();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _dobCtrl.dispose();
    _cityCtrl.dispose();
    _referralCtrl.dispose();
    super.dispose();
  }

  // ── Photo picker ──────────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Choose photo',
                  style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins', color: Color(0xFF1A0A2E),
                  )),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0E8FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: Color(0xFF7b2d6e)),
              ),
              title: const Text('Camera',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              subtitle: const Text('Take a new photo',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0E8FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.photo_library_rounded,
                    color: Color(0xFF7b2d6e)),
              ),
              title: const Text('Gallery',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              subtitle: const Text('Choose from your photos',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
          ],
        ),
      ),
    );

    File? file;
    if (choice == 'camera') {
      file = await ImageUploadService.pickFromCamera();
    } else if (choice == 'gallery') {
      file = await ImageUploadService.pickFromGallery();
    }
    if (file != null && mounted) setState(() => _profileImage = file);
  }

  // ── Referral validation ───────────────────────────────────────────────────
  void _onReferralChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() { _codeResult = null; _isValidatingCode = false; });
      return;
    }
    setState(() => _isValidatingCode = true);
    _debounce = Timer(const Duration(milliseconds: 700), () async {
      final result = await ReferralService()
          .validateReferralCode(value.trim().toUpperCase());
      if (mounted) setState(() { _codeResult = result; _isValidatingCode = false; });
    });
  }

  // ── DOB picker ────────────────────────────────────────────────────────────
  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(1920),
      lastDate: DateTime(now.year - 1),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF7b2d6e),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dobCtrl.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_termsAccepted) {
      _showError('Please accept the Terms & Privacy Policy.');
      return;
    }
    if (_dobCtrl.text.trim().isEmpty) {
      _showError('Please select your date of birth.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      String? photoUrl;
      if (_profileImage != null) {
        final uid = ref.read(authProvider).user?.uid ?? '';
        photoUrl = await ImageUploadService.uploadUserProfileImage(
          imageFile: _profileImage!,
          uid: uid,
          onProgress: (p) => setState(() => _uploadProgress = p),
        );
      }

      await ref.read(authProvider.notifier).completeRegistration(
        name:         _nameCtrl.text.trim(),
        phone:        widget.phone,
        dob:          _dobCtrl.text.trim(),
        gender:       _selectedGender,
        email:        _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        city:         _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        bloodGroup:   _selectedBloodGroup,
        referralCode: _referralCtrl.text.trim().isEmpty ? null : _referralCtrl.text.trim(),
      );

      // Update photo URL if uploaded
      if (photoUrl != null && mounted) {
        await ref.read(authProvider.notifier).updatePhotoUrl(photoUrl);
      }

      if (!mounted) return;
      context.go(AppRoutes.createMpin, extra: {'mode': 'setup'});
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() { _isLoading = false; _uploadProgress = 0; });
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontFamily: 'Poppins')),
      backgroundColor: const Color(0xFFB00020),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0520),
      body: Stack(
        children: [
          // ── Gradient background ─────────────────────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0D0520), Color(0xFF3B0F50), Color(0xFF7b2d6e)],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          FadeTransition(
            opacity: _fadeIn,
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => context.canPop() ? context.pop() : context.go(AppRoutes.login),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text('Create Account',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins',
                            )),
                      ],
                    ),
                  ),
                ),

                // ── Profile photo picker ─────────────────────────────────
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _pickPhoto,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glow ring
                      Container(
                        width: 104, height: 104,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 2,
                          ),
                        ),
                      ),
                      // Avatar
                      Container(
                        width: 96, height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _profileImage == null
                              ? const LinearGradient(
                                  colors: [Color(0xFFA36BAC), Color(0xFF7b2d6e)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          image: _profileImage != null
                              ? DecorationImage(
                                  image: FileImage(_profileImage!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _profileImage == null
                            ? const Icon(Icons.person_rounded,
                                color: Colors.white54, size: 46)
                            : null,
                      ),
                      // Camera badge
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          width: 32, height: 32,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              size: 17, color: Color(0xFF7b2d6e)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text('Add photo (optional)',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontFamily: 'Poppins',
                    )),
                const SizedBox(height: 16),

                // ── Scrollable form ─────────────────────────────────────
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                            20, 24, 20,
                            MediaQuery.of(context).padding.bottom + 40),
                        children: [

                          // ── Verified phone ────────────────────────────
                          if (widget.phone.isNotEmpty) ...[
                            _sectionLabel('Mobile Number'),
                            const SizedBox(height: 8),
                            _VerifiedPhone(phone: widget.phone),
                            const SizedBox(height: 20),
                          ],

                          // ══ Personal Info ══════════════════════════════
                          _SectionHeader(icon: Icons.person_rounded, label: 'Personal Info'),
                          const SizedBox(height: 12),

                          _sectionLabel('Full Name *'),
                          const SizedBox(height: 6),
                          _field(
                            controller: _nameCtrl,
                            hint: 'Your full name',
                            prefix: Icons.badge_outlined,
                            capitalization: TextCapitalization.words,
                            validator: (v) => v == null || v.trim().length < 2
                                ? 'Enter your full name'
                                : null,
                          ),
                          const SizedBox(height: 14),

                          _sectionLabel('Email Address (optional)'),
                          const SizedBox(height: 6),
                          _field(
                            controller: _emailCtrl,
                            hint: 'you@example.com',
                            prefix: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              if (!RegExp(r'^[\w.+-]+@[\w-]+\.[a-z]{2,}$')
                                  .hasMatch(v.trim())) return 'Invalid email address';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          _sectionLabel('Date of Birth *'),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _pickDob,
                            child: AbsorbPointer(
                              child: _field(
                                controller: _dobCtrl,
                                hint: 'DD / MM / YYYY',
                                prefix: Icons.cake_outlined,
                                suffix: Icons.calendar_today_rounded,
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Select your date of birth'
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // ── Gender ────────────────────────────────────
                          _sectionLabel('Gender *'),
                          const SizedBox(height: 8),
                          Row(
                            children: ['Male', 'Female', 'Other']
                                .map((g) => Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                            right: g != 'Other' ? 8 : 0),
                                        child: _GenderChip(
                                          label: g,
                                          icon: g == 'Male'
                                              ? Icons.male_rounded
                                              : g == 'Female'
                                                  ? Icons.female_rounded
                                                  : Icons.transgender_rounded,
                                          selected: _selectedGender == g,
                                          onTap: () =>
                                              setState(() => _selectedGender = g),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 14),

                          _sectionLabel('City (optional)'),
                          const SizedBox(height: 6),
                          _field(
                            controller: _cityCtrl,
                            hint: 'Your city',
                            prefix: Icons.location_city_outlined,
                          ),

                          const SizedBox(height: 20),

                          // ══ Health Info ════════════════════════════════
                          _SectionHeader(
                              icon: Icons.favorite_rounded,
                              label: 'Health Info'),
                          const SizedBox(height: 12),

                          _sectionLabel('Blood Group (optional)'),
                          const SizedBox(height: 6),
                          _BloodGroupPicker(
                            selected: _selectedBloodGroup,
                            onSelect: (v) =>
                                setState(() => _selectedBloodGroup = v),
                          ),

                          const SizedBox(height: 20),

                          // ══ Referral ═══════════════════════════════════
                          _SectionHeader(
                              icon: Icons.card_giftcard_rounded,
                              label: 'Referral (optional)'),
                          const SizedBox(height: 12),

                          _sectionLabel('Referral Code'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _referralCtrl,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF1A0A2E),
                              fontFamily: 'Poppins',
                              letterSpacing: 1,
                            ),
                            decoration: _inputDeco(
                                    Icons.card_giftcard_outlined, 'e.g. MED12345')
                                .copyWith(
                              suffixIcon: _isValidatingCode
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: SizedBox(
                                        width: 18, height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF7b2d6e)),
                                      ))
                                  : _codeResult != null
                                      ? Icon(
                                          _codeResult!.isValid
                                              ? Icons.check_circle_rounded
                                              : Icons.cancel_rounded,
                                          color: _codeResult!.isValid
                                              ? const Color(0xFF2E7D32)
                                              : const Color(0xFFB00020),
                                          size: 22,
                                        )
                                      : null,
                            ),
                            onChanged: _onReferralChanged,
                          ),
                          if (_codeResult != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6, left: 4),
                              child: Text(
                                _codeResult!.isValid
                                    ? '✓ Referred by ${_codeResult!.referrerName ?? "a friend"}'
                                    : '✗ Invalid referral code',
                                style: TextStyle(
                                  color: _codeResult!.isValid
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFB00020),
                                  fontSize: 12,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),

                          const SizedBox(height: 24),

                          // ── Terms ─────────────────────────────────────
                          GestureDetector(
                            onTap: () =>
                                setState(() => _termsAccepted = !_termsAccepted),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _termsAccepted
                                    ? const Color(0xFFF0E8FA)
                                    : const Color(0xFFFAFAFA),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _termsAccepted
                                      ? const Color(0xFF7b2d6e).withValues(alpha: 0.5)
                                      : const Color(0xFFE0E0E0),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 22, height: 22,
                                    margin: const EdgeInsets.only(top: 1),
                                    decoration: BoxDecoration(
                                      color: _termsAccepted
                                          ? const Color(0xFF7b2d6e)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _termsAccepted
                                            ? const Color(0xFF7b2d6e)
                                            : const Color(0xFFBBBBBB),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: _termsAccepted
                                        ? const Icon(Icons.check,
                                            color: Colors.white, size: 14)
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'I agree to the Terms of Service and Privacy Policy',
                                      style: TextStyle(
                                        color: Color(0xFF444444),
                                        fontSize: 13,
                                        fontFamily: 'Poppins',
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ── Upload progress ───────────────────────────
                          if (_isLoading && _uploadProgress > 0 && _uploadProgress < 1) ...[
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Uploading photo ${(_uploadProgress * 100).toInt()}%',
                                    style: const TextStyle(
                                      fontSize: 12, fontFamily: 'Poppins',
                                      color: Color(0xFF7b2d6e),
                                    )),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _uploadProgress,
                                    backgroundColor: const Color(0xFFF0E8FA),
                                    valueColor: const AlwaysStoppedAnimation(
                                        Color(0xFF7b2d6e)),
                                    minHeight: 5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ],

                          // ── Submit button ─────────────────────────────
                          Container(
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                colors: [Color(0xFFA36BAC), Color(0xFF7b2d6e)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF7b2d6e).withValues(alpha: 0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: _isLoading ? null : _submit,
                                child: Center(
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 24, height: 24,
                                          child: CircularProgressIndicator(
                                              color: Colors.white, strokeWidth: 2.5),
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text('Continue',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  fontFamily: 'Poppins',
                                                  color: Colors.white,
                                                )),
                                            SizedBox(width: 8),
                                            Icon(Icons.arrow_forward_rounded,
                                                color: Colors.white, size: 18),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Full-screen loading overlay ──────────────────────────────────
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.05),
              ),
            ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF555555),
        fontFamily: 'Poppins',
        letterSpacing: 0.3,
      ));

  InputDecoration _inputDeco(IconData icon, String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
        color: Color(0xFFBBBBBB), fontFamily: 'Poppins', fontSize: 14),
    prefixIcon: Icon(icon, color: const Color(0xFF7b2d6e), size: 20),
    filled: true,
    fillColor: const Color(0xFFF8F4FF),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: const Color(0xFF7b2d6e).withValues(alpha: 0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: const Color(0xFF7b2d6e).withValues(alpha: 0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF7b2d6e), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFB00020)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFB00020), width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData prefix,
    IconData? suffix,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: capitalization,
        style: const TextStyle(
            fontSize: 14, color: Color(0xFF1A0A2E), fontFamily: 'Poppins'),
        decoration: _inputDeco(prefix, hint).copyWith(
          suffixIcon: suffix != null
              ? Icon(suffix, color: const Color(0xFF7b2d6e), size: 18)
              : null,
        ),
        validator: validator,
      );
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFFF0E8FA),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF7b2d6e)),
      ),
      const SizedBox(width: 10),
      Text(label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A0A2E),
            fontFamily: 'Poppins',
          )),
      const SizedBox(width: 10),
      Expanded(
        child: Container(height: 1, color: const Color(0xFFF0E0F8)),
      ),
    ],
  );
}

class _VerifiedPhone extends StatelessWidget {
  final String phone;
  const _VerifiedPhone({required this.phone});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF0FAF0),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.phone_android_rounded,
            color: Color(0xFF2E7D32), size: 18),
        const SizedBox(width: 10),
        Text(phone,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A0A2E),
              fontFamily: 'Poppins',
            )),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, size: 11, color: Color(0xFF2E7D32)),
              SizedBox(width: 3),
              Text('Verified',
                  style: TextStyle(
                    color: Color(0xFF2E7D32),
                    fontSize: 11,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      ],
    ),
  );
}

class _GenderChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _GenderChip(
      {required this.label, required this.icon,
       required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF7b2d6e) : const Color(0xFFF8F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? const Color(0xFF7b2d6e)
              : const Color(0xFF7b2d6e).withValues(alpha: 0.2),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: const Color(0xFF7b2d6e).withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 16,
              color: selected ? Colors.white : const Color(0xFF7b2d6e)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF7b2d6e),
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
                fontSize: 13,
              )),
        ],
      ),
    ),
  );
}

class _BloodGroupPicker extends StatelessWidget {
  final String? selected;
  final void Function(String?) onSelect;
  const _BloodGroupPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: _bloodGroups.map((bg) {
      final isSelected = selected == bg;
      return GestureDetector(
        onTap: () => onSelect(isSelected ? null : bg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 60, height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF7b2d6e) : const Color(0xFFF8F4FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF7b2d6e)
                  : const Color(0xFF7b2d6e).withValues(alpha: 0.2),
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF7b2d6e).withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(bg,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF7b2d6e),
                fontWeight: FontWeight.w700,
                fontFamily: 'Poppins',
                fontSize: 13,
              )),
        ),
      );
    }).toList(),
  );
}
