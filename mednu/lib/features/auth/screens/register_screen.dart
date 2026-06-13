import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../referral/referral_service.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _referralCodeController = TextEditingController();

  String _selectedGender = 'Male';
  String _selectedCountryCode = '+91';
  bool _isLoading = false;
  String? _googlePhotoUrl;

  // Referral validation
  Timer? _debounce;
  bool _isValidatingCode = false;
  ReferralValidationResult? _codeResult;

  late AnimationController _animCtrl;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();

    // Pre-fill name and photo from the authenticated Google account
    final googleUser = FirebaseAuth.instance.currentUser;
    if (googleUser != null) {
      if (googleUser.displayName?.isNotEmpty ?? false) {
        _nameController.text = googleUser.displayName!;
      }
      _googlePhotoUrl = googleUser.photoURL;
    }

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _referralCodeController.dispose();
    _debounce?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Referral code validation (debounced 700 ms) ─────────────────────────
  void _onReferralCodeChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _isValidatingCode = false;
        _codeResult = null;
      });
      return;
    }
    setState(() {
      _isValidatingCode = true;
      _codeResult = null;
    });
    _debounce = Timer(const Duration(milliseconds: 700), () async {
      final result = await ReferralService().validateReferralCode(value.trim());
      if (mounted) {
        setState(() {
          _isValidatingCode = false;
          _codeResult = result;
        });
      }
    });
  }

  // ── Send OTP + navigate to verification screen ──────────────────────────
  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    if (_codeResult != null && !_codeResult!.isValid) {
      _showSnack('Please enter a valid referral code or clear the field.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final fullPhone = '$_selectedCountryCode${_phoneController.text.trim()}';
      await ref.read(authProvider.notifier).sendOtp(fullPhone);

      if (!mounted) return;
      context.push(
        AppRoutes.otp,
        extra: {
          'phone': fullPhone,
          'name': _nameController.text.trim(),
          'dob': _dobController.text.trim(),
          'gender': _selectedGender,
          'referralCode': _referralCodeController.text.trim().isEmpty
              ? null
              : _referralCodeController.text.trim(),
        },
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDob() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (date != null) {
      _dobController.text =
          '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.error,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeIn,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Gradient header ──────────────────────────────────────
                _Header(
                  photoUrl: _googlePhotoUrl,
                  onBack: () => context.pop(),
                ),

                // ── Form ─────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Info notice
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha:0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha:0.14),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  color: AppColors.primary, size: 16),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Phone verification happens only once — you\'ll never need to re-verify.',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color: AppColors.primary,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Full name
                        _Label('Full Name'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          style: AppTextStyles.bodyLarge,
                          decoration: const InputDecoration(
                            hintText: 'Enter your full name',
                            prefixIcon:
                                Icon(Icons.person_outline_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter your name'
                              : null,
                        ),
                        const SizedBox(height: 18),

                        // Mobile number
                        _Label('Mobile Number'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Country code picker
                            GestureDetector(
                              onTap: _showCountryPicker,
                              child: Container(
                                height: 54,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _countryFlag(_selectedCountryCode),
                                      style:
                                          const TextStyle(fontSize: 18),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _selectedCountryCode,
                                      style: AppTextStyles.labelMedium,
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 16,
                                        color: AppColors.textSecondary),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                style: AppTextStyles.bodyLarge,
                                decoration: const InputDecoration(
                                  hintText: 'Enter 10-digit number',
                                  counterText: '',
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 16),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Enter phone number';
                                  }
                                  if (v.length < 10) {
                                    return 'Enter valid 10-digit number';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Date of birth
                        _Label('Date of Birth'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _dobController,
                          readOnly: true,
                          onTap: _pickDob,
                          style: AppTextStyles.bodyLarge,
                          decoration: const InputDecoration(
                            hintText: 'DD/MM/YYYY',
                            prefixIcon:
                                Icon(Icons.calendar_today_outlined),
                          ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Select date of birth'
                              : null,
                        ),
                        const SizedBox(height: 18),

                        // Gender
                        _Label('Gender'),
                        const SizedBox(height: 8),
                        Row(
                          children:
                              ['Male', 'Female', 'Other'].map((g) {
                            final selected = _selectedGender == g;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedGender = g),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  margin: EdgeInsets.only(
                                      right: g != 'Other' ? 8 : 0),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.primary
                                        : Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.border,
                                      width: selected ? 1.5 : 1,
                                    ),
                                    boxShadow: selected
                                        ? [
                                            BoxShadow(
                                              color: AppColors.primary
                                                  .withValues(alpha:0.25),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Text(
                                    g,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 18),

                        // Referral code
                        _Label('Referral Code (Optional)'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _referralCodeController,
                          textCapitalization: TextCapitalization.characters,
                          style: AppTextStyles.bodyLarge,
                          decoration: InputDecoration(
                            hintText: 'Enter referral code',
                            prefixIcon: const Icon(
                                Icons.card_giftcard_rounded),
                            suffixIcon: _buildReferralSuffix(),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: _codeResult == null
                                    ? AppColors.border
                                    : _codeResult!.isValid
                                        ? AppColors.success
                                        : AppColors.error,
                                width: _codeResult != null ? 1.5 : 1,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: _codeResult == null
                                    ? AppColors.primary
                                    : _codeResult!.isValid
                                        ? AppColors.success
                                        : AppColors.error,
                                width: 1.5,
                              ),
                            ),
                          ),
                          onChanged: _onReferralCodeChanged,
                        ),

                        // Validation feedback
                        if (_isValidatingCode)
                          _CodeFeedback(
                            icon: Icons.hourglass_top_rounded,
                            color: AppColors.textSecondary,
                            message: 'Checking code…',
                          )
                        else if (_codeResult != null && _codeResult!.isValid)
                          _CodeFeedback(
                            icon: Icons.check_circle_rounded,
                            color: AppColors.success,
                            message: _codeResult!.referredReward > 0
                                ? 'Invited by ${_codeResult!.referrerName ?? 'a friend'} · You\'ll get ${_codeResult!.referredRewardFormatted} in your wallet!'
                                : 'Invited by ${_codeResult!.referrerName ?? 'a friend'} ✓',
                          )
                        else if (_codeResult != null &&
                            !_codeResult!.isValid)
                          _CodeFeedback(
                            icon: Icons.cancel_rounded,
                            color: AppColors.error,
                            message: _codeResult!.error ??
                                'Invalid referral code',
                          ),

                        const SizedBox(height: 32),

                        // Continue button → sends OTP
                        _ContinueButton(
                          isLoading: _isLoading,
                          onTap: _continue,
                        ),

                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            'We\'ll send a one-time OTP to verify your mobile number.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textHint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildReferralSuffix() {
    if (_isValidatingCode) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_referralCodeController.text.isNotEmpty) {
      return IconButton(
        icon: const Icon(Icons.clear_rounded, size: 18),
        onPressed: () {
          _referralCodeController.clear();
          setState(() => _codeResult = null);
        },
      );
    }
    return null;
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Select Country Code', style: AppTextStyles.h4),
              const SizedBox(height: 12),
              ...[
                ('🇮🇳', 'India', '+91'),
                ('🇺🇸', 'USA', '+1'),
                ('🇬🇧', 'UK', '+44'),
                ('🇦🇪', 'UAE', '+971'),
              ].map(
                (c) => ListTile(
                  leading: Text(c.$1,
                      style: const TextStyle(fontSize: 24)),
                  title: Text(c.$2, style: AppTextStyles.labelLarge),
                  trailing:
                      Text(c.$3, style: AppTextStyles.bodyMedium),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () {
                    setState(() => _selectedCountryCode = c.$3);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _countryFlag(String code) => switch (code) {
        '+91' => '🇮🇳',
        '+1' => '🇺🇸',
        '+44' => '🇬🇧',
        '+971' => '🇦🇪',
        _ => '🌐',
      };
}

// ── Header ───────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String? photoUrl;
  final VoidCallback onBack;
  const _Header({required this.photoUrl, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Profile photo or placeholder
          Stack(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha:0.35),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: photoUrl != null && photoUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photoUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const Icon(
                            Icons.person_rounded,
                            size: 42,
                            color: Colors.white70,
                          ),
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.person_rounded,
                            size: 42,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          size: 42,
                          color: Colors.white,
                        ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Create Your Profile',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Just a few details to personalise\nyour MedNU experience.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Continue Button ───────────────────────────────────────────────────────────
class _ContinueButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;
  const _ContinueButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isLoading
              ? null
              : const LinearGradient(
                  colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          color: isLoading ? AppColors.primary : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isLoading
              ? null
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha:0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Send OTP & Verify',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 18),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Label ─────────────────────────────────────────────────────────────────────
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppTextStyles.labelLarge);
}

// ── Code Feedback ─────────────────────────────────────────────────────────────
class _CodeFeedback extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  const _CodeFeedback(
      {required this.icon, required this.color, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
