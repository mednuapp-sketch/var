import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/responsive.dart';

/// Shared immersive frame for login / OTP: dark-plum backdrop with soft glow
/// orbs, brand story on the left (desktop), form card on the right.
class AuthShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  const AuthShell({super.key, required this.child, this.onBack});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      backgroundColor: const Color(0xFF1C0F19),
      body: Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1C0F19), Color(0xFF33172C), Color(0xFF522546)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        const Positioned(top: -120, left: -100, child: _Glow(size: 420, color: Color(0xFFA36BAC), opacity: 0.22)),
        const Positioned(bottom: -160, right: -120, child: _Glow(size: 520, color: Color(0xFFC494CD), opacity: 0.16)),
        const Positioned(top: 180, right: 260, child: _Glow(size: 160, color: Color(0xFFC494CD), opacity: 0.10)),
        SafeArea(
          child: isMobile
              ? _MobileLayout(onBack: onBack, child: child)
              : _DesktopLayout(onBack: onBack, child: child),
        ),
      ]),
    );
  }
}

class _Glow extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;
  const _Glow({required this.size, required this.color, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  const _DesktopLayout({required this.child, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Expanded(flex: 6, child: _BrandStory()),
      Expanded(
        flex: 5,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _FormCard(onBack: onBack, child: child),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _MobileLayout extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  const _MobileLayout({required this.child, this.onBack});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(children: [
        const _BrandMark(size: 40),
        const SizedBox(height: 8),
        Text('Your health, beautifully simple.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 24),
        _FormCard(onBack: onBack, child: child),
      ]),
    );
  }
}

class _FormCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  const _FormCard({required this.child, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 60, offset: const Offset(0, 24)),
          BoxShadow(color: AppColors.primaryLight.withValues(alpha: 0.18), blurRadius: 0, spreadRadius: 1),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (onBack != null) ...[
          GestureDetector(
            onTap: onBack,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.textPrimary),
                const SizedBox(width: 6),
                Text('Back', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ]),
            ),
          ),
          const SizedBox(height: 24),
        ],
        child,
      ]),
    );
  }
}

class _BrandMark extends StatelessWidget {
  final double size;
  const _BrandMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Image.asset('assets/images/mednu_logo.png', width: size, height: size, filterQuality: FilterQuality.high),
      const SizedBox(width: 12),
      Text('MedNU', style: GoogleFonts.poppins(fontSize: size * 0.62, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
    ]);
  }
}

class _BrandStory extends StatelessWidget {
  const _BrandStory();

  @override
  Widget build(BuildContext context) {
    const points = [
      (Icons.event_available_rounded, 'Book & manage appointments', 'Live status, instantly synced'),
      (Icons.folder_shared_rounded, 'Records & prescriptions', 'Everything in one secure place'),
      (Icons.family_restroom_rounded, 'Care for the whole family', 'One account, every profile'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 48, 24, 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandMark(size: 48),
          const SizedBox(height: 56),
          Text('Your health,\nbeautifully simple.',
              style: GoogleFonts.poppins(fontSize: 52, fontWeight: FontWeight.w800, color: Colors.white, height: 1.08, letterSpacing: -1.5)),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text('Sign in with just your mobile number — no passwords, no hassle.',
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.white70, height: 1.65)),
          ),
          const SizedBox(height: 44),
          for (final p in points) ...[
            Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(13)),
                  child: Icon(p.$1, size: 21, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.$2, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                    Text(p.$3, style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
