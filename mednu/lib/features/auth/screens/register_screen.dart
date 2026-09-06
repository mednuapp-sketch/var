import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/image_upload_service.dart';
import '../providers/auth_provider.dart';

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

  String  _selectedGender    = 'Male';
  bool    _isLoading         = false;
  File?   _profileImage;
  double  _uploadProgress    = 0;

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
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _dobCtrl.dispose();
    _cityCtrl.dispose();
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
                    color: AppColors.primary),
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
                    color: AppColors.primary),
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
            primary: AppColors.primary,
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
      backgroundColor: AppColors.darkBase,
      body: Stack(
        children: [
          // ── Gradient background ─────────────────────────────────────────
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.heroBannerGradient,
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
                                  colors: [AppColors.primary, AppColors.secondary],
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
                              size: 17, color: AppColors.primary),
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
                            const SizedBox(height: 6),
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

                          const SizedBox(height: 24),

                          // ── Upload progress ───────────────────────────
                          if (_isLoading && _uploadProgress > 0 && _uploadProgress < 1) ...[
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Uploading photo ${(_uploadProgress * 100).toInt()}%',
                                    style: const TextStyle(
                                      fontSize: 12, fontFamily: 'Poppins',
                                      color: AppColors.primary,
                                    )),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _uploadProgress,
                                    backgroundColor: const Color(0xFFF0E8FA),
                                    valueColor: const AlwaysStoppedAnimation(
                                        AppColors.primary),
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
                              gradient: AppColors.primaryGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.35),
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
    prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
    filled: true,
    fillColor: const Color(0xFFF8F4FF),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
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
              ? Icon(suffix, color: AppColors.primary, size: 18)
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
        child: Icon(icon, size: 16, color: AppColors.primary),
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
        color: selected ? AppColors.primary : const Color(0xFFF8F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.2),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
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
              color: selected ? Colors.white : AppColors.primary),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.primary,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
                fontSize: 13,
              )),
        ],
      ),
    ),
  );
}

