import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/launch_utils.dart';
import '../../../core/utils/responsive.dart';

class DownloadAppSection extends StatelessWidget {
  const DownloadAppSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isTablet = Responsive.isTablet(context);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF33172C), Color(0xFF3D1D36), Color(0xFF522546)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: isMobile ? 56 : 88,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: Responsive.maxContentWidth(context)),
          child: isMobile
              ? _MobileLayout()
              : _DesktopLayout(isTablet: isTablet),
        ),
      ),
    );
  }
}

// ─── Desktop ──────────────────────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  final bool isTablet;
  const _DesktopLayout({required this.isTablet});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left — cross icon + branding
        Expanded(
          flex: 3,
          child: _BrandVisual(compact: isTablet),
        ),
        SizedBox(width: isTablet ? 32 : 56),
        // Center — text content + stats
        Expanded(
          flex: 4,
          child: _TextContent(compact: isTablet),
        ),
        SizedBox(width: isTablet ? 32 : 48),
        // Right — QR + store buttons
        _StorePanel(compact: isTablet),
      ],
    );
  }
}

// ─── Mobile ───────────────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _BrandVisual(compact: true, mobile: true),
        SizedBox(height: 32),
        _TextContent(compact: true, center: true),
        SizedBox(height: 32),
        _StorePanel(compact: true, mobile: true),
      ],
    );
  }
}

// ─── Brand Visual ─────────────────────────────────────────────────────────────

class _BrandVisual extends StatelessWidget {
  final bool compact;
  final bool mobile;
  const _BrandVisual({required this.compact, this.mobile = false});

  @override
  Widget build(BuildContext context) {
    final size = mobile ? 90.0 : compact ? 110.0 : 140.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // MedNU logo
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.28),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.28),
            child: Image.asset('assets/images/mednu_logo.png',
                width: size, height: size, fit: BoxFit.cover, filterQuality: FilterQuality.high),
          ),
        ),
        SizedBox(height: mobile ? 16 : 24),
        Text(
          'MedNU',
          style: GoogleFonts.poppins(
            fontSize: mobile ? 24 : compact ? 28 : 36,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Healthcare App',
          style: GoogleFonts.poppins(
            fontSize: mobile ? 13 : 14,
            color: Colors.white70,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// ─── Text Content ─────────────────────────────────────────────────────────────

class _TextContent extends StatelessWidget {
  final bool compact;
  final bool center;
  const _TextContent({required this.compact, this.center = false});

  static const _stats = [
    (value: '8', label: 'Care Services'),
    (value: '3', label: 'Languages'),
    (value: 'Video', label: 'Consultations'),
    (value: 'Oct 2026', label: 'Launch'),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = center;
    final align = isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = isMobile ? TextAlign.center : TextAlign.left;
    final titleSize = compact ? 26.0 : 36.0;

    return Column(
      crossAxisAlignment: align,
      children: [
        // Tag
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Text('Download Free',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70)),
        ),
        const SizedBox(height: 18),
        Text(
          'Take MedNU\nEverywhere You Go',
          textAlign: textAlign,
          style: GoogleFonts.poppins(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.2,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Book doctors, order medicines, track your health —\nall from your pocket, anytime, anywhere.',
          textAlign: textAlign,
          style: GoogleFonts.poppins(
            fontSize: compact ? 13 : 14.5,
            color: Colors.white70,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 28),
        // Stats grid
        Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: isMobile ? WrapAlignment.center : WrapAlignment.start,
          children: _stats.map((s) => _StatChip(stat: s)).toList(),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final ({String value, String label}) stat;
  const _StatChip({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(colors: [Colors.white, Color(0xFFE9CFEE)]).createShader(b),
            blendMode: BlendMode.srcIn,
            child: Text(
              stat.value,
              style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
          ),
          Text(stat.label,
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─── Store Panel ──────────────────────────────────────────────────────────────

class _StorePanel extends StatelessWidget {
  final bool compact;
  final bool mobile;
  const _StorePanel({required this.compact, this.mobile = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!mobile) ...[
          _QRCodeWidget(size: compact ? 110 : 130),
          const SizedBox(height: 12),
          Text('Scan to download',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 16),
        ],
        _ContactUsBtn(),
        SizedBox(height: mobile ? 20 : 16),
        _PlayStoreBtn(),
        const SizedBox(height: 10),
        _AppStoreBtn(),
      ],
    );
  }
}

// ─── QR Code — real, scannable, links to the Play Store listing ───────────────

class _QRCodeWidget extends StatelessWidget {
  final double size;
  const _QRCodeWidget({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: QrImageView(
        data: AppConstants.apkDownloadUrl,
        version: QrVersions.auto,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF33172C)),
        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF33172C)),
      ),
    );
  }
}

// ─── Contact Us ───────────────────────────────────────────────────────────────

class _ContactUsBtn extends StatefulWidget {
  @override
  State<_ContactUsBtn> createState() => _ContactUsBtnState();
}

class _ContactUsBtnState extends State<_ContactUsBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => _showContactSheet(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 180,
          height: 44,
          decoration: BoxDecoration(
            color: _hovered ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: _hovered ? 0.3 : 0.18), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.headset_mic_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text('Contact Us',
                  style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

void _showContactSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _ContactSheet(),
  );
}

class _ContactSheet extends StatelessWidget {
  const _ContactSheet();

  @override
  Widget build(BuildContext context) {
    final options = <(FaIconData, String, String, VoidCallback)>[
      (FontAwesomeIcons.phone, 'Call us', AppConstants.contactPhone,
          () => openUrl('tel:${AppConstants.contactPhone.replaceAll(' ', '')}')),
      (FontAwesomeIcons.envelope, 'Email us', AppConstants.contactEmail,
          () => openUrl('mailto:${AppConstants.contactEmail}')),
      if (AppConstants.whatsappNumber.isNotEmpty)
        (
          FontAwesomeIcons.whatsapp,
          'WhatsApp',
          AppConstants.whatsappNumber,
          () => openUrl('https://wa.me/${AppConstants.whatsappNumber.replaceAll(RegExp(r'[^0-9]'), '')}'),
        ),
      if (AppConstants.instagramUrl.isNotEmpty)
        (FontAwesomeIcons.instagram, 'Instagram', '@mednu', () => openUrl(AppConstants.instagramUrl)),
      if (AppConstants.facebookUrl.isNotEmpty)
        (FontAwesomeIcons.facebook, 'Facebook', 'MedNU', () => openUrl(AppConstants.facebookUrl)),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('Contact MedNU',
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textSecondary),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text('Reach us directly through any of these channels',
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            ...options.map((o) => _ContactOptionTile(icon: o.$1, label: o.$2, value: o.$3, onTap: o.$4)),
          ],
        ),
      ),
    );
  }
}

class _ContactOptionTile extends StatelessWidget {
  final FaIconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _ContactOptionTile({required this.icon, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
            child: Center(child: FaIcon(icon, size: 17, color: Colors.white)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(value, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 18),
        ]),
      ),
    );
  }
}

// ─── Play Store Button ────────────────────────────────────────────────────────

class _PlayStoreBtn extends StatefulWidget {
  @override
  State<_PlayStoreBtn> createState() => _PlayStoreBtnState();
}

class _PlayStoreBtnState extends State<_PlayStoreBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => openUrl(AppConstants.playStoreUrl),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 180,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF1A1A1A) : Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _hovered ? Colors.white38 : Colors.white24,
                width: 1),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ]
                : [],
          ),
          child: Row(
            children: [
              // Google Play triangle icon (custom drawn)
              SizedBox(
                width: 24,
                height: 24,
                child: CustomPaint(painter: _PlayIconPainter()),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GET IT ON',
                      style: GoogleFonts.poppins(
                          fontSize: 9,
                          color: Colors.white70,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w400)),
                  Text('Google Play',
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Simplified Google Play triangle in 4 colors
    final colors = [
      const Color(0xFF00C853),
      const Color(0xFFFFD600),
      const Color(0xFFFF6D00),
      const Color(0xFF2979FF),
    ];

    // Top-left triangle (teal)
    final p1 = Paint()..color = colors[0];
    final path1 = Path()
      ..moveTo(2, 0)
      ..lineTo(w * 0.52, h * 0.5)
      ..lineTo(2, h)
      ..close();
    canvas.drawPath(path1, p1);

    // Bottom triangle (yellow)
    final p2 = Paint()..color = colors[1];
    final path2 = Path()
      ..moveTo(2, h)
      ..lineTo(w * 0.52, h * 0.5)
      ..lineTo(w, h * 0.75)
      ..close();
    canvas.drawPath(path2, p2);

    // Right triangle (orange/red)
    final p3 = Paint()..color = colors[2];
    final path3 = Path()
      ..moveTo(2, 0)
      ..lineTo(w * 0.52, h * 0.5)
      ..lineTo(w, h * 0.25)
      ..close();
    canvas.drawPath(path3, p3);

    // Center triangle (blue)
    final p4 = Paint()..color = colors[3];
    final path4 = Path()
      ..moveTo(w * 0.52, h * 0.5)
      ..lineTo(w, h * 0.25)
      ..lineTo(w, h * 0.75)
      ..close();
    canvas.drawPath(path4, p4);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── App Store Button ─────────────────────────────────────────────────────────

class _AppStoreBtn extends StatefulWidget {
  @override
  State<_AppStoreBtn> createState() => _AppStoreBtnState();
}

class _AppStoreBtnState extends State<_AppStoreBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => openUrl(AppConstants.appStoreUrl),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 180,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF1A1A1A) : Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _hovered ? Colors.white38 : Colors.white24,
                width: 1),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ]
                : [],
          ),
          child: Row(
            children: [
              const Icon(Icons.apple, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Download on the',
                      style: GoogleFonts.poppins(
                          fontSize: 9,
                          color: Colors.white70,
                          letterSpacing: 0.3,
                          fontWeight: FontWeight.w400)),
                  Text('App Store',
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
