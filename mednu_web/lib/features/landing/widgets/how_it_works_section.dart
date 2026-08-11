import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

class HowItWorksSection extends StatelessWidget {
  const HowItWorksSection({super.key});

  static const _steps = [
    (
      num: '01',
      icon: Icons.apps_rounded,
      title: 'Choose Service',
      desc: 'Select from consultations, medicines, lab tests, or home care services.',
    ),
    (
      num: '02',
      icon: Icons.person_search_rounded,
      title: 'Select & Book',
      desc: 'Pick your preferred doctor or service slot with real-time availability.',
    ),
    (
      num: '03',
      icon: Icons.payment_rounded,
      title: 'Book & Pay',
      desc: 'Securely confirm your booking with multiple payment options in seconds.',
    ),
    (
      num: '04',
      icon: Icons.favorite_border_rounded,
      title: 'Receive Care',
      desc: 'Get expert healthcare delivered at your doorstep or via video call.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isTablet = Responsive.isTablet(context);

    return Container(
      color: const Color(0xFFF8F9FB),
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: isMobile ? 56 : 88,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: Responsive.maxContentWidth(context)),
          child: isMobile
              ? const _MobileLayout(steps: _steps)
              : _DesktopLayout(steps: _steps, compact: isTablet),
        ),
      ),
    );
  }
}

// ─── Desktop ──────────────────────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  final List<({String num, IconData icon, String title, String desc})> steps;
  final bool compact;
  const _DesktopLayout({required this.steps, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        const _SectionHeader(),
        SizedBox(height: compact ? 48 : 64),
        // 4-step horizontal flow
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              Expanded(child: _StepCard(step: steps[i], compact: compact)),
              if (i < steps.length - 1)
                Padding(
                  padding: EdgeInsets.only(top: compact ? 36 : 42),
                  child: const _DashedArrow(),
                ),
            ],
          ],
        ),
      ],
    );
  }
}

// ─── Mobile ───────────────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final List<({String num, IconData icon, String title, String desc})> steps;
  const _MobileLayout({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SectionHeader(center: true),
        const SizedBox(height: 40),
        ...steps.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _StepCardMobile(step: s),
            )),
      ],
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final bool center;
  const _SectionHeader({this.center = false});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final align =
        (center || isMobile) ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = (center || isMobile) ? TextAlign.center : TextAlign.left;

    return Column(
      crossAxisAlignment: align,
      children: [
        // Tag pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2), width: 1),
          ),
          child: Text('Simple Steps',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary)),
        ),
        const SizedBox(height: 16),
        Text(
          'How MedNU Works',
          textAlign: textAlign,
          style: GoogleFonts.poppins(
            fontSize: isMobile ? 26 : 34,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1A1A2E),
            letterSpacing: -0.5,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'From choosing a service to receiving care — your complete health journey in four simple steps.',
            textAlign: textAlign,
            style: GoogleFonts.poppins(
              fontSize: isMobile ? 14 : 15,
              color: const Color(0xFF757575),
              height: 1.7,
            ),
          ),
        ),
        if (!isMobile && !center) ...[
          const SizedBox(height: 20),
          _LearnMoreBtn(),
        ],
      ],
    );
  }
}

class _LearnMoreBtn extends StatefulWidget {
  @override
  State<_LearnMoreBtn> createState() => _LearnMoreBtnState();
}

class _LearnMoreBtnState extends State<_LearnMoreBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {},
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
            blendMode: BlendMode.srcIn,
            child: Text(
              'Learn More',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: _hovered
                ? (Matrix4.identity()..translateByDouble(4.0, 0.0, 0.0, 1.0))
                : Matrix4.identity(),
            child: ShaderMask(
              shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
              blendMode: BlendMode.srcIn,
              child: const Icon(Icons.arrow_forward_rounded,
                  size: 16, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Step Card (desktop) ──────────────────────────────────────────────────────

class _StepCard extends StatefulWidget {
  final ({String num, IconData icon, String title, String desc}) step;
  final bool compact;
  const _StepCard({required this.step, required this.compact});

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.all(widget.compact ? 20 : 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hovered
                ? AppColors.primary.withValues(alpha: 0.25)
                : const Color(0xFFEEEEEE),
            width: 1.5,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8))
                ]
              : [
                  const BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 10,
                      offset: Offset(0, 3))
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Gradient circle icon
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: _hovered
                        ? AppColors.primaryGradient
                        : const LinearGradient(colors: [
                            Color(0xFFF5F5F5),
                            Color(0xFFEEEEEE)
                          ]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.step.icon,
                    size: 24,
                    color: _hovered ? Colors.white : AppColors.primary,
                  ),
                ),
                // Step number badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: ShaderMask(
                    shaderCallback: (b) =>
                        AppColors.primaryGradient.createShader(b),
                    blendMode: BlendMode.srcIn,
                    child: Text(
                      widget.step.num,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              widget.step.title,
              style: GoogleFonts.poppins(
                fontSize: widget.compact ? 14 : 15.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.step.desc,
              style: GoogleFonts.poppins(
                fontSize: widget.compact ? 12 : 13,
                color: const Color(0xFF757575),
                height: 1.65,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step Card (mobile) ───────────────────────────────────────────────────────

class _StepCardMobile extends StatelessWidget {
  final ({String num, IconData icon, String title, String desc}) step;
  const _StepCardMobile({required this.step});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000),
              blurRadius: 10,
              offset: Offset(0, 3))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(step.icon, size: 22, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(step.title,
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A1A2E))),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: ShaderMask(
                      shaderCallback: (b) =>
                          AppColors.primaryGradient.createShader(b),
                      blendMode: BlendMode.srcIn,
                      child: Text(step.num,
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(step.desc,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: const Color(0xFF757575),
                        height: 1.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dashed Arrow ─────────────────────────────────────────────────────────────

class _DashedArrow extends StatelessWidget {
  const _DashedArrow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 24,
      child: CustomPaint(painter: _DashedArrowPainter()),
    );
  }
}

class _DashedArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.35)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const dashWidth = 5.0;
    const dashSpace = 4.0;
    double x = 0;
    final y = size.height / 2;

    while (x < size.width - 10) {
      canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), paint);
      x += dashWidth + dashSpace;
    }

    // Arrow head
    final arrowPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final tipX = size.width;
    canvas.drawLine(Offset(tipX - 8, y - 5), Offset(tipX, y), arrowPaint);
    canvas.drawLine(Offset(tipX - 8, y + 5), Offset(tipX, y), arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
