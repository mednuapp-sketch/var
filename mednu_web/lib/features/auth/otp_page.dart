import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import 'auth_provider.dart';

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

    // No manual navigation here: once confirm() succeeds, the router's
    // redirect reacts to authProfileProvider's live snapshot and sends the
    // user to /register or /dashboard itself — see app_router.dart.

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                  child: const Center(child: Text('🔐', style: TextStyle(fontSize: 32))),
                ),
                const SizedBox(height: 24),
                Text(
                  'Verify Your Number',
                  style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'We\'ve sent a 6-digit OTP to\n+91 ${widget.phone}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
                ),
                const SizedBox(height: 36),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) => _OtpBox(
                    controller: _ctrls[i],
                    focusNode: _nodes[i],
                    onChanged: (v) => _onDigit(i, v),
                    autoFocus: i == 0,
                  )),
                ),
                const SizedBox(height: 12),
                if (authState.error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(authState.error!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error))),
                    ]),
                  ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: authState.loading
                      ? Container(
                          decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(14)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                            const SizedBox(width: 12),
                            Text('Verifying…', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                          ]),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Center(
                            child: Text(
                              'Enter all 6 digits to verify automatically',
                              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textHint),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text("Didn't receive OTP? ", style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                  StreamBuilder(
                    key: ValueKey(_timerKey),
                    stream: _timer,
                    builder: (context, snap) {
                      final seconds = snap.data ?? 59;
                      if (seconds <= 0) {
                        return GestureDetector(
                          onTap: () {
                            setState(() => _timerKey++);
                            for (final c in _ctrls) c.clear();
                            _nodes[0].requestFocus();
                            ref.read(authNotifierProvider.notifier).sendOtp(widget.phone);
                          },
                          child: Text('Resend OTP', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                        );
                      }
                      return Text('Resend in ${seconds}s', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textHint));
                    },
                  ),
                ]),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: () {
                    ref.read(authNotifierProvider.notifier).goBack();
                    context.go('/login');
                  },
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: Text('Change number', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),
        ),
      ),
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
    return Container(
      width: 48,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 5),
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
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
