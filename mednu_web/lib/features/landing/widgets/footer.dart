import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/responsive.dart';

class WebFooter extends StatelessWidget {
  const WebFooter({super.key});

  static const _links = {
    'Company': ['About Us', 'Careers', 'Blog', 'Contact'],
    'Services': [
      'Find Doctors',
      'Medicines',
      'Lab Tests',
      'Health Records'
    ],
    'Support': [
      'Help Center',
      'FAQs',
      'Privacy Policy',
      'Terms & Conditions'
    ],
  };

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Container(
      color: const Color(0xFFF8F9FB),
      child: Column(
        children: [
          // Main footer content
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
              vertical: isMobile ? 48 : 64,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: Responsive.maxContentWidth(context)),
                child: isMobile ? _MobileContent() : _DesktopContent(),
              ),
            ),
          ),

          // Divider
          Container(
            height: 1,
            color: const Color(0xFFEEEEEE),
          ),

          // Newsletter bar
          Container(
            color: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
              vertical: 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: Responsive.maxContentWidth(context)),
                child: const _Newsletter(),
              ),
            ),
          ),

          Container(height: 1, color: const Color(0xFFEEEEEE)),

          // Bottom bar
          Container(
            color: const Color(0xFFF8F9FB),
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
              vertical: 20,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: Responsive.maxContentWidth(context)),
                child: isMobile
                    ? Column(children: [
                        _SocialRow(),
                        const SizedBox(height: 14),
                        _CopyrightText(),
                      ])
                    : Row(children: [
                        _CopyrightText(),
                        const Spacer(),
                        _SocialRow(),
                      ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Desktop content ──────────────────────────────────────────────────────────

class _DesktopContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: _BrandSection()),
        const SizedBox(width: 48),
        ...WebFooter._links.entries.map((e) => Expanded(
              flex: 2,
              child: _LinkGroup(title: e.key, links: e.value),
            )),
      ],
    );
  }
}

class _MobileContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BrandSection(),
        const SizedBox(height: 36),
        ...WebFooter._links.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: _LinkGroup(title: e.key, links: e.value),
            )),
      ],
    );
  }
}

// ─── Brand Section ────────────────────────────────────────────────────────────

class _BrandSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo with pink cross icon
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: _MiniCross(size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          ShaderMask(
            shaderCallback: (b) =>
                AppColors.primaryGradient.createShader(b),
            blendMode: BlendMode.srcIn,
            child: Text('MedNu',
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5)),
          ),
        ]),
        const SizedBox(height: 16),
        Text(
          "India's most trusted healthcare platform. Connecting patients with verified doctors across the country.",
          style: GoogleFonts.poppins(
              fontSize: 13,
              color: const Color(0xFF757575),
              height: 1.7),
        ),
        const SizedBox(height: 20),
        _ContactRow(
            icon: Icons.email_outlined,
            text: AppConstants.contactEmail),
        const SizedBox(height: 6),
        _ContactRow(
            icon: Icons.phone_outlined,
            text: AppConstants.contactPhone),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.location_on_outlined,
              size: 14, color: Color(0xFFBDBDBD)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(AppConstants.contactAddress,
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: const Color(0xFF9E9E9E),
                    height: 1.5)),
          ),
        ]),
      ],
    );
  }
}

class _MiniCross extends StatelessWidget {
  final double size;
  final Color color;
  const _MiniCross({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _CrossPainter(color: color)));
  }
}

class _CrossPainter extends CustomPainter {
  final Color color;
  const _CrossPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final t = size.width / 3;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(t, 0, t, size.height), Radius.circular(t * 0.3)),
        paint);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(0, t, size.width, t), Radius.circular(t * 0.3)),
        paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ContactRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 14, color: const Color(0xFFBDBDBD)),
      const SizedBox(width: 6),
      Text(text,
          style: GoogleFonts.poppins(
              fontSize: 12, color: const Color(0xFF757575))),
    ]);
  }
}

// ─── Link Group ───────────────────────────────────────────────────────────────

class _LinkGroup extends StatelessWidget {
  final String title;
  final List<String> links;
  const _LinkGroup({required this.title, required this.links});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E),
                letterSpacing: 0.2)),
        const SizedBox(height: 16),
        ...links.map((l) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FooterLink(label: l),
            )),
      ],
    );
  }
}

class _FooterLink extends StatefulWidget {
  final String label;
  const _FooterLink({required this.label});

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: _hovered ? AppColors.primary : const Color(0xFF757575),
            fontWeight: FontWeight.w400,
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}

// ─── Newsletter ───────────────────────────────────────────────────────────────

class _Newsletter extends StatefulWidget {
  const _Newsletter();

  @override
  State<_Newsletter> createState() => _NewsletterState();
}

class _NewsletterState extends State<_Newsletter> {
  final _ctrl = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctrl.text.isNotEmpty) {
      setState(() => _sent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NewsletterText(),
          const SizedBox(height: 16),
          if (_sent) _SuccessMessage() else _NewsletterInput(ctrl: _ctrl, onSubmit: _submit),
        ],
      );
    }

    return Row(children: [
      Expanded(flex: 2, child: _NewsletterText()),
      const SizedBox(width: 32),
      Expanded(
          flex: 3,
          child: _sent
              ? _SuccessMessage()
              : _NewsletterInput(ctrl: _ctrl, onSubmit: _submit)),
    ]);
  }
}

class _NewsletterText extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Subscribe to our newsletter',
          style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E))),
      const SizedBox(height: 4),
      Text('Get health tips, updates and exclusive offers',
          style: GoogleFonts.poppins(
              fontSize: 13, color: const Color(0xFF9E9E9E))),
    ]);
  }
}

class _SuccessMessage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded,
            color: Colors.white, size: 18),
      ),
      const SizedBox(width: 10),
      Text("You're subscribed! Thank you.",
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary)),
    ]);
  }
}

class _NewsletterInput extends StatelessWidget {
  final TextEditingController ctrl;
  final VoidCallback onSubmit;
  const _NewsletterInput({required this.ctrl, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 8,
                  offset: Offset(0, 2))
            ],
          ),
          child: TextField(
            controller: ctrl,
            style: GoogleFonts.poppins(
                fontSize: 13, color: const Color(0xFF1A1A2E)),
            decoration: InputDecoration(
              hintText: 'Enter your email address',
              hintStyle: GoogleFonts.poppins(
                  fontSize: 13, color: const Color(0xFFBDBDBD)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
        ),
      ),
      const SizedBox(width: 10),
      GestureDetector(
        onTap: onSubmit,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: const Icon(Icons.arrow_forward_rounded,
              color: Colors.white, size: 20),
        ),
      ),
    ]);
  }
}

// ─── Social Row ───────────────────────────────────────────────────────────────

class _SocialRow extends StatelessWidget {
  static const _socials = [
    (icon: Icons.facebook_rounded, label: 'Facebook'),
    (icon: Icons.camera_alt_rounded, label: 'Instagram'),
    (icon: Icons.alternate_email_rounded, label: 'Twitter'),
    (icon: Icons.business_rounded, label: 'LinkedIn'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children:
          _socials.map((s) => _SocialBtn(icon: s.icon, label: s.label)).toList(),
    );
  }
}

class _SocialBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  const _SocialBtn({required this.icon, required this.label});

  @override
  State<_SocialBtn> createState() => _SocialBtnState();
}

class _SocialBtnState extends State<_SocialBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(left: 8),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.primary.withOpacity(0.1)
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? AppColors.primary.withOpacity(0.3)
                  : const Color(0xFFE0E0E0),
              width: 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                        color: AppColors.primary.withOpacity(0.1),
                        blurRadius: 8)
                  ]
                : [],
          ),
          child: Icon(widget.icon,
              size: 17,
              color: _hovered ? AppColors.primary : const Color(0xFF9E9E9E)),
        ),
      ),
    );
  }
}

// ─── Copyright ────────────────────────────────────────────────────────────────

class _CopyrightText extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      '© 2026 MedNu Healthcare Services Pvt. Ltd. All rights reserved.',
      style: GoogleFonts.poppins(
          fontSize: 12, color: const Color(0xFF9E9E9E)),
    );
  }
}
