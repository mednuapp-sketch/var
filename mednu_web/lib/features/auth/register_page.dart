import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import 'auth_provider.dart';

const _kBloodGroups = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'];
const _kGenders = ['Male', 'Female', 'Other'];

class RegisterPage extends ConsumerStatefulWidget {
  final String phone;
  const RegisterPage({super.key, required this.phone});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  String _selectedGender = 'Male';
  String? _selectedBloodGroup;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _dobCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(1920),
      lastDate: DateTime(now.year - 1),
    );
    if (picked != null) {
      setState(() {
        _dobCtrl.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(authNotifierProvider.notifier).completeRegistration(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          dob: _dobCtrl.text.trim().isEmpty ? null : _dobCtrl.text.trim(),
          gender: _selectedGender,
          city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
          bloodGroup: _selectedBloodGroup,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    // Drive the post-registration transition explicitly off the live
    // Firestore listener rather than relying solely on the router's
    // refreshListenable — see the matching comment in otp_page.dart.
    ref.listen(authProfileProvider, (prev, next) {
      if (next.isLoading) return;
      if (hasCompletedProfile(next.valueOrNull)) context.go('/dashboard');
    });

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                    child: const Center(child: Text('📝', style: TextStyle(fontSize: 32))),
                  ),
                  const SizedBox(height: 24),
                  Text('Complete Your Profile', style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Text(
                    "We're new here — let's set up your MedNu account",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.verified_rounded, size: 14, color: AppColors.success),
                      const SizedBox(width: 6),
                      Text('+91 ${widget.phone} verified', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
                    ]),
                  ),
                  const SizedBox(height: 32),

                  _Label('Full Name *'),
                  const SizedBox(height: 6),
                  _TextField(
                    controller: _nameCtrl,
                    hint: 'Your full name',
                    icon: Icons.badge_outlined,
                    capitalization: TextCapitalization.words,
                    validator: (v) => v == null || v.trim().length < 2 ? 'Enter your full name' : null,
                  ),
                  const SizedBox(height: 16),

                  _Label('Email Address (optional)'),
                  const SizedBox(height: 6),
                  _TextField(
                    controller: _emailCtrl,
                    hint: 'you@example.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      if (!RegExp(r'^[\w.+-]+@[\w-]+\.[a-z]{2,}$').hasMatch(v.trim())) return 'Invalid email address';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _Label('Date of Birth'),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: _pickDob,
                          child: AbsorbPointer(
                            child: _TextField(controller: _dobCtrl, hint: 'DD/MM/YYYY', icon: Icons.cake_outlined, suffixIcon: Icons.calendar_today_rounded),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _Label('City'),
                        const SizedBox(height: 6),
                        _TextField(controller: _cityCtrl, hint: 'Your city', icon: Icons.location_city_outlined),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  _Label('Gender'),
                  const SizedBox(height: 8),
                  Row(
                    children: _kGenders.map((g) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: g != _kGenders.last ? 8 : 0),
                        child: _Chip(
                          label: g,
                          selected: _selectedGender == g,
                          onTap: () => setState(() => _selectedGender = g),
                        ),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),

                  _Label('Blood Group (optional)'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _kBloodGroups.map((bg) => _Chip(
                      label: bg,
                      width: 64,
                      selected: _selectedBloodGroup == bg,
                      onTap: () => setState(() => _selectedBloodGroup = _selectedBloodGroup == bg ? null : bg),
                    )).toList(),
                  ),
                  const SizedBox(height: 12),

                  if (authState.error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(authState.error!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error))),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(14)),
                      child: ElevatedButton(
                        onPressed: authState.loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: authState.loading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text('Create Account', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                              ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
  );
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final IconData? suffixIcon;
  final TextInputType keyboardType;
  final TextCapitalization capitalization;
  final String? Function(String?)? validator;

  const _TextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.suffixIcon,
    this.keyboardType = TextInputType.text,
    this.capitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: AppColors.primary),
        suffixIcon: suffixIcon != null ? Icon(suffixIcon, size: 18, color: AppColors.primary) : null,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double? width;
  const _Chip({required this.label, required this.selected, required this.onTap, this.width});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? AppColors.primaryGradient : null,
          color: selected ? null : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Colors.transparent : AppColors.border),
        ),
        child: Text(label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.textPrimary)),
      ),
    );
  }
}
