import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/gradient_button.dart';
import 'auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  const LoginPage({super.key, this.onBack});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with TickerProviderStateMixin {
  final _phoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    ref.listen(authNotifierProvider, (prev, next) {
      if (next.step == AuthStep.otp && prev?.step == AuthStep.phone) {
        context.go('/otp?phone=${Uri.encodeComponent(next.phone)}');
      }
    });

    return Scaffold(
      body: Row(
        children: [
          if (!Responsive.isMobile(context)) Expanded(flex: 5, child: _LoginHeroPanel()),
          Expanded(
            flex: 4,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _LoginFormPanel(
                formKey: _formKey,
                phoneCtrl: _phoneCtrl,
                authState: authState,
                onSendOtp: () {
                  if (_formKey.currentState!.validate()) {
                    ref.read(authNotifierProvider.notifier).sendOtp(_phoneCtrl.text.trim());
                  }
                },
                onBack: widget.onBack ?? () {},
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginHeroPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        // Floating accent cards need real margin around the text column to
        // not collide with it — only show them once the panel is wide
        // enough (this panel only renders on tablet/desktop to begin with).
        final showFloatingCards = constraints.maxWidth > 560;
        return Stack(
          children: [
            Positioned(top: -80, left: -80, child: _Orb(size: 320, opacity: 0.12)),
            Positioned(bottom: -60, right: -60, child: _Orb(size: 280, opacity: 0.1)),
            if (showFloatingCards) ...[
              Positioned(
                top: 36,
                right: 36,
                child: _HeroFloatingCard(
                  icon: Icons.verified_rounded,
                  iconColor: const Color(0xFF2E7D32),
                  title: 'Verified Doctors',
                  subtitle: '1000+ specialists',
                ),
              ),
              Positioned(
                bottom: 48,
                right: 40,
                child: _HeroFloatingCard(
                  icon: Icons.support_agent_rounded,
                  iconColor: AppColors.primary,
                  title: '24/7 Support',
                  subtitle: "We're always here",
                ),
              ),
            ],
            Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                        child: const Center(child: Text('M', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800))),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('MedNu', style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5, height: 1.1)),
                          Text('Always with you', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70, letterSpacing: 0.3)),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 48),
                    Text(
                      'Your Health,\nOur Priority.',
                      style: GoogleFonts.poppins(fontSize: 42, fontWeight: FontWeight.w800, color: Colors.white, height: 1.15, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Log in to access your health records,\nappointments, prescriptions, and more.',
                      style: GoogleFonts.poppins(fontSize: 15, color: Colors.white70, height: 1.65),
                    ),
                    const SizedBox(height: 48),
                    ...[
                      (Icons.calendar_month_rounded, 'Book appointments instantly'),
                      (Icons.folder_shared_rounded, 'Access all your health records'),
                      (Icons.medication_rounded, 'View prescriptions & reports'),
                      (Icons.lock_rounded, 'Secured with end-to-end encryption'),
                    ].map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                          child: Center(child: Icon(item.$1, size: 18, color: Colors.white)),
                        ),
                        const SizedBox(width: 14),
                        Text(item.$2, style: GoogleFonts.poppins(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500)),
                      ]),
                    )),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _HeroFloatingCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  const _HeroFloatingCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      constraints: const BoxConstraints(maxWidth: 190),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 17, color: iconColor),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(subtitle, style: GoogleFonts.poppins(fontSize: 10.5, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

class _Orb extends StatelessWidget {
  final double size;
  final double opacity;
  const _Orb({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
      ),
    );
  }
}

class _LoginFormPanel extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController phoneCtrl;
  final AuthState authState;
  final VoidCallback onSendOtp;
  final VoidCallback onBack;

  const _LoginFormPanel({
    required this.formKey,
    required this.phoneCtrl,
    required this.authState,
    required this.onSendOtp,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    GestureDetector(
                      onTap: onBack,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.textPrimary),
                      ),
                    ),
                    if (Responsive.isMobile(context)) ...[
                      const SizedBox(width: 12),
                      Row(children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(8)),
                          child: const Center(child: Text('M', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
                        ),
                        const SizedBox(width: 8),
                        Text('MedNu', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      ]),
                    ],
                  ]),
                  const SizedBox(height: 36),
                  authState.step == AuthStep.phone
                      ? _PhoneForm(formKey: formKey, phoneCtrl: phoneCtrl, authState: authState, onSendOtp: onSendOtp)
                      : const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController phoneCtrl;
  final AuthState authState;
  final VoidCallback onSendOtp;

  const _PhoneForm({
    required this.formKey,
    required this.phoneCtrl,
    required this.authState,
    required this.onSendOtp,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome Back! 👋', style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.2)),
          const SizedBox(height: 8),
          Text('Enter your mobile number to receive a secure OTP', style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary, height: 1.5)),
          const SizedBox(height: 36),
          Text('Mobile Number', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          TextFormField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            decoration: InputDecoration(
              prefixIcon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🇮🇳', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text('+91', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 20, color: AppColors.border),
                ]),
              ),
              hintText: '98765 43210',
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please enter your mobile number';
              if (v.length != 10) return 'Enter a valid 10-digit number';
              return null;
            },
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
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: authState.loading
                ? Container(
                    height: 52,
                    decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(14)),
                    child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
                  )
                : GradientButton(label: 'Send OTP', onTap: onSendOtp, width: double.infinity, icon: Icons.send_rounded),
          ),
          const SizedBox(height: 32),
          _OrDivider(),
          const SizedBox(height: 24),
          _GoogleSignInButton(),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'By continuing, you agree to our Terms of Service\nand Privacy Policy',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textHint, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Expanded(child: Divider()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text('or', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textHint)),
      ),
      const Expanded(child: Divider()),
    ]);
  }
}

class _GoogleSignInButton extends StatefulWidget {
  @override
  State<_GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<_GoogleSignInButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.background : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hovered ? AppColors.border : AppColors.divider, width: 1.5),
            boxShadow: _hovered ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))] : [],
          ),
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF4285F4))),
              const SizedBox(width: 10),
              Text('Continue with Google', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ]),
          ),
        ),
      ),
    );
  }
}
