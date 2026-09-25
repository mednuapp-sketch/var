import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/gradient_button.dart';
import 'auth_provider.dart';
import 'auth_shell.dart';

class LoginPage extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  const LoginPage({super.key, this.onBack});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _phoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      ref.read(authNotifierProvider.notifier).sendOtp(_phoneCtrl.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    ref.listen(authNotifierProvider, (prev, next) {
      if (next.step == AuthStep.otp && prev?.step == AuthStep.phone) {
        context.go('/otp?phone=${Uri.encodeComponent(next.phone)}');
      }
    });

    return AuthShell(
      onBack: widget.onBack,
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: const Icon(Icons.phone_iphone_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 22),
          Text('Welcome back',
              style: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.15, letterSpacing: -0.8)),
          const SizedBox(height: 8),
          Text('Enter your mobile number and we\'ll text you a secure one-time code.',
              style: GoogleFonts.poppins(fontSize: 13.5, color: AppColors.textSecondary, height: 1.6)),
          const SizedBox(height: 30),
          Text('Mobile number', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            autofocus: true,
            onFieldSubmitted: (_) => _submit(),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: AppColors.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.background,
              hintText: '98765 43210',
              hintStyle: GoogleFonts.poppins(fontSize: 16, color: AppColors.textHint, letterSpacing: 1.2),
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 16, right: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('+91', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 22, color: AppColors.border),
                ]),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 1.6)),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.error)),
              focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.error, width: 1.6)),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please enter your mobile number';
              if (v.length != 10) return 'Enter a valid 10-digit number';
              return null;
            },
          ),
          if (authState.error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
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
          authState.loading
              ? Container(
                  height: 54,
                  decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(16)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text('Sending code…', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.white)),
                  ]),
                )
              : GradientButton(label: 'Get OTP', onTap: _submit, width: double.infinity, height: 54, icon: Icons.arrow_forward_rounded, borderRadius: BorderRadius.circular(16)),
          const SizedBox(height: 22),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.textHint),
            const SizedBox(width: 6),
            Text('Secured with one-time verification', style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.textHint)),
          ]),
          const SizedBox(height: 14),
          Center(
            child: Text('By continuing, you agree to our Terms of Service and Privacy Policy',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textHint, height: 1.5)),
          ),
        ]),
      ),
    );
  }
}
