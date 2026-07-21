import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
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
    return Column(
      children: [
        _BrandVisual(compact: true, mobile: true),
        const SizedBox(height: 32),
        _TextContent(compact: true, center: true),
        const SizedBox(height: 32),
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
        // Cross / Plus medical icon
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(size * 0.28),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.4),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Center(
            child: _MedicalCross(size: size * 0.52, color: Colors.white),
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
            color: Colors.white54,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// ─── Medical cross custom painter ─────────────────────────────────────────────

class _MedicalCross extends StatelessWidget {
  final double size;
  final Color color;
  const _MedicalCross({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CrossPainter(color: color)),
    );
  }
}

class _CrossPainter extends CustomPainter {
  final Color color;
  const _CrossPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    final t = w / 3;

    // Vertical bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(t, 0, t, h), Radius.circular(t * 0.3)),
      paint,
    );
    // Horizontal bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, t, w, t), Radius.circular(t * 0.3)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Text Content ─────────────────────────────────────────────────────────────

class _TextContent extends StatelessWidget {
  final bool compact;
  final bool center;
  const _TextContent({required this.compact, this.center = false});

  static const _stats = [
    (value: '50K+', label: 'Happy Users'),
    (value: '1000+', label: 'Verified Doctors'),
    (value: '20K+', label: 'Orders Delivered'),
    (value: '4.8/5', label: 'App Rating'),
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
            color: Colors.white.withOpacity(0.1),
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
            color: Colors.white60,
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
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
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
                  color: Colors.white54,
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
                  fontSize: 12, color: Colors.white54)),
          const SizedBox(height: 20),
        ],
        _PlayStoreBtn(),
        const SizedBox(height: 10),
        _AppStoreBtn(),
      ],
    );
  }
}

// ─── QR Code ──────────────────────────────────────────────────────────────────

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
            color: Colors.black.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: CustomPaint(painter: _QRPainter()),
    );
  }
}

class _QRPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.fill;
    final lightPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Fill background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), lightPaint);

    final cell = size.width / 10;
    final rng = math.Random(42);

    // Draw random QR-like cells with corner finders
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 10; c++) {
        final x = c * cell;
        final y = r * cell;
        // Corner finder patterns (7x7 logic simplified to 3x3 boxes)
        bool isFinderTL = (r < 4 && c < 4);
        bool isFinderTR = (r < 4 && c >= 6);
        bool isFinderBL = (r >= 6 && c < 4);

        if (isFinderTL || isFinderTR || isFinderBL) {
          bool isBorder = (r == 0 || r == 3 || c == 0 || c == 3) ||
              (r == 6 || r == 9 || c == 6 || c == 9) ||
              (r >= 6 && r <= 9 && (c == 0 || c == 3));
          bool isInner = (r == 1 || r == 2) && (c == 1 || c == 2);
          bool isInnerTR = (r == 1 || r == 2) && (c == 7 || c == 8);
          bool isInnerBL = (r >= 7 && r <= 8) && (c == 1 || c == 2);

          if (isBorder || isInner || isInnerTR || isInnerBL) {
            canvas.drawRect(
                Rect.fromLTWH(x + 0.5, y + 0.5, cell - 1, cell - 1), paint);
          }
        } else if (rng.nextBool()) {
          canvas.drawRect(
              Rect.fromLTWH(x + 0.5, y + 0.5, cell - 1, cell - 1), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
                        color: Colors.black.withOpacity(0.4),
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
                        color: Colors.black.withOpacity(0.4),
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
