import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import 'auth_provider.dart';
import 'auth_shell.dart';

class OtpPage extends ConsumerStatefulWidget {
  final String phone;
  const OtpPage({super.key, required this.phone});

  @override
  ConsumerState<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends ConsumerState<OtpPage> {
  final List<TextEditingController> _ctrls = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());
  int _timerKey = 0;

  Stream<int> get _timer =>
      Stream.periodic(const Duration(seconds: 1), (i) => 59 - i).take(60);

  String get _otp => _ctrls.map((c) => c.text).join();

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    for (final n in _nodes) n.dispose();
    super.dispose();
  }

  void _onDigit(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _nodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _nodes[index - 1].requestFocus();
    }
    // Use microtask so all controller texts are settled before reading _otp
    if (value.isNotEmpty) {
      Future.microtask(() {
        if (_otp.length == 6 && mounted) _verify();
      });
    }
  }

  void _verify() {
    final otp = _otp;
    if (otp.length != 6) return;
    ref.read(authNotifierProvider.notifier).verifyOtp(otp);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    // The router's redirect also reacts to authProfileProvider (see
    // app_router.dart), but relying on that alone left this screen stuck
    // after a successful confirm() until a manual page reload — refreshing
    // re-runs the router's initial redirect, which is why that "unstuck" it.
    // Drive the transition explicitly from here too, off the same live
    // Firestore listener, so it fires the moment sign-in actually completes.
    ref.listen(authProfileProvider, (prev, next) {
      final user = ref.read(authStateProvider).valueOrNull;
      if (user == null || next.isLoading) return;
      if (hasCompletedProfile(next.valueOrNull)) {
        context.go('/dashboard');
      } else {
        final rawPhone = user.phoneNumber ?? '';
        final localPhone = rawPhone.startsWith('+91') ? rawPhone.substring(3) : rawPhone;
        context.go('/register?phone=${Uri.encodeComponent(localPhone.isEmpty ? widget.phone : localPhone)}');
      }
    });

    return AuthShell(
      onBack: () {
        ref.read(authNotifierProvider.notifier).goBack();
        context.go('/login');
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: const Icon(Icons.sms_rounded, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 22),
        Text('Verify your number',
            style: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.15, letterSpacing: -0.8)),
        const SizedBox(height: 8),
        Text('Enter the 6-digit code sent to +91 ${widget.phone}',
            style: GoogleFonts.poppins(fontSize: 13.5, color: AppColors.textSecondary, height: 1.6)),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) => _OtpBox(
            controller: _ctrls[i],
            focusNode: _nodes[i],
            onChanged: (v) => _onDigit(i, v),
            autoFocus: i == 0,
          )),
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
        Container(
          height: 54,
          decoration: BoxDecoration(
            gradient: authState.loading ? AppColors.primaryGradient : null,
            color: authState.loading ? null : AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: authState.loading ? null : Border.all(color: AppColors.border),
          ),
          child: Center(
            child: authState.loading
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text('Verifying…', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.white)),
                  ])
                : Text('Verifies automatically when you enter all 6 digits',
                    style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textHint)),
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text("Didn't get the code? ", style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            StreamBuilder(
              key: ValueKey(_timerKey),
              stream: _timer,
              builder: (context, snap) {
                final seconds = snap.data ?? 59;
                if (seconds <= 0) {
                  return GestureDetector(
                    onTap: () {
                      setState(() => _timerKey++);
                      for (final c in _ctrls) { c.clear(); }
                      _nodes[0].requestFocus();
                      ref.read(authNotifierProvider.notifier).sendOtp(widget.phone);
                    },
                    child: Text('Resend OTP', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  );
                }
                return Text('Resend in ${seconds}s', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textHint));
              },
            ),
          ]),
        ),
      ]),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool autoFocus;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.autoFocus,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 58,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autoFocus,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: AppColors.background,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
