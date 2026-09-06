import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/launch_utils.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/gradient_button.dart';

class HeroSection extends StatefulWidget {
  final VoidCallback onGetStarted;
  const HeroSection({super.key, required this.onGetStarted});

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isTablet = Responsive.isTablet(context);

    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: Responsive.horizontalPadding(context),
        right: Responsive.horizontalPadding(context),
        top: isMobile ? 40 : 72,
        bottom: isMobile ? 48 : 80,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: Responsive.maxContentWidth(context)),
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: isMobile
                  ? _MobileHero(onGetStarted: widget.onGetStarted)
                  : _DesktopHero(
                      onGetStarted: widget.onGetStarted,
                      isTablet: isTablet,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Desktop ──────────────────────────────────────────────────────────────────

class _DesktopHero extends StatelessWidget {
  final VoidCallback onGetStarted;
  final bool isTablet;
  const _DesktopHero({required this.onGetStarted, required this.isTablet});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 55,
          child: _HeroContent(
              onGetStarted: onGetStarted, isTablet: isTablet),
        ),
        SizedBox(width: isTablet ? 24 : 56),
        Expanded(
          flex: 45,
          child: Center(child: _HeroVisual(compact: isTablet)),
        ),
      ],
    );
  }
}

// ─── Mobile ───────────────────────────────────────────────────────────────────

class _MobileHero extends StatelessWidget {
  final VoidCallback onGetStarted;
  const _MobileHero({required this.onGetStarted});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HeroContent(onGetStarted: onGetStarted, isMobile: true),
        const SizedBox(height: 40),
        const Center(child: _HeroVisual(compact: true, mobile: true)),
      ],
    );
  }
}

// ─── Hero Content ─────────────────────────────────────────────────────────────

class _HeroContent extends StatelessWidget {
  final VoidCallback onGetStarted;
  final bool isMobile;
  final bool isTablet;

  const _HeroContent({
    required this.onGetStarted,
    this.isMobile = false,
    this.isTablet = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleSize = isMobile ? 32.0 : isTablet ? 38.0 : 50.0;

    return Column(
      crossAxisAlignment:
          isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        // Tag pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2), width: 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.favorite_rounded,
                size: 13, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('Your Health, Our Priority',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ]),
        ),
        const SizedBox(height: 22),

        // Heading — dark line + pink gradient line
        Column(
          crossAxisAlignment: isMobile
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              'Healthcare Made Simple,',
              textAlign:
                  isMobile ? TextAlign.center : TextAlign.left,
              style: GoogleFonts.poppins(
                fontSize: titleSize,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A1A2E),
                height: 1.18,
                letterSpacing: -0.5,
              ),
            ),
            ShaderMask(
              shaderCallback: (b) =>
                  AppColors.primaryGradient.createShader(b),
              blendMode: BlendMode.srcIn,
              child: Text(
                'Smarter & Closer',
                textAlign:
                    isMobile ? TextAlign.center : TextAlign.left,
                style: GoogleFonts.poppins(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.18,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Description
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Text(
            'Consult doctors, order medicines, book lab tests and manage your health – all in one secure app.',
            textAlign:
                isMobile ? TextAlign.center : TextAlign.left,
            style: GoogleFonts.poppins(
              fontSize: isMobile ? 14 : 15.5,
              color: const Color(0xFF757575),
              height: 1.8,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 32),

        // CTA buttons
        if (isMobile)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GradientButton(
                label: 'Book Consultation',
                onTap: onGetStarted,
                height: 52,
                icon: Icons.arrow_forward_rounded,
              ),
              const SizedBox(height: 12),
              _DownloadBtn(onTap: onGetStarted, stretch: true),
            ],
          )
        else
          Row(children: [
            GradientButton(
              label: 'Book Consultation',
              onTap: onGetStarted,
              width: 210,
              height: 52,
              icon: Icons.arrow_forward_rounded,
            ),
            const SizedBox(width: 12),
            _DownloadBtn(onTap: onGetStarted),
          ]),
        const SizedBox(height: 32),

        // Trust row
        _TrustRow(center: isMobile),
      ],
    );
  }
}

// ─── Download outline button ──────────────────────────────────────────────────

class _DownloadBtn extends StatefulWidget {
  final VoidCallback onTap;
  final bool stretch;
  const _DownloadBtn({required this.onTap, this.stretch = false});

  @override
  State<_DownloadBtn> createState() => _DownloadBtnState();
}

class _DownloadBtnState extends State<_DownloadBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => openUrl(AppConstants.apkDownloadUrl),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.stretch ? double.infinity : 185,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.primary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.primary, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.download_rounded,
                  size: 18,
                  color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Download App',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Trust Row ────────────────────────────────────────────────────────────────

class _TrustRow extends StatelessWidget {
  final bool center;
  const _TrustRow({required this.center});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment:
          center ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        const SizedBox(
          width: 76,
          height: 34,
          child: Stack(children: [
            _AvatarBubble(offset: 0, color: AppColors.primary),
            _AvatarBubble(offset: 22, color: AppColors.secondary),
            _AvatarBubble(
                offset: 44, color: Color(0xFF00897B)),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Trusted by 50,000+ users',
              style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF212121))),
          Row(children: [
            ...List.generate(
                5,
                (_) => const Icon(Icons.star_rounded,
                    size: 13, color: Color(0xFFFB8C00))),
            const SizedBox(width: 5),
            Text('4.8',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF424242))),
            const SizedBox(width: 3),
            Text('(2.5k reviews)',
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: const Color(0xFF9E9E9E))),
          ]),
        ]),
      ],
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  final double offset;
  final Color color;
  const _AvatarBubble({required this.offset, required this.color});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Center(
            child: Icon(Icons.person, size: 17, color: Colors.white)),
      ),
    );
  }
}

// ─── Hero Visual (right side) ─────────────────────────────────────────────────

class _HeroVisual extends StatelessWidget {
  final bool compact;
  final bool mobile;
  const _HeroVisual({this.compact = false, this.mobile = false});

  @override
  Widget build(BuildContext context) {
    final phoneW = mobile ? 185.0 : compact ? 190.0 : 210.0;
    final phoneH = mobile ? 375.0 : compact ? 390.0 : 430.0;

    if (mobile) {
      return SizedBox(
        width: phoneW,
        height: phoneH + 40,
        child: _PhoneMockup(w: phoneW, h: phoneH),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth.isFinite ? constraints.maxWidth : 480.0;
        final totalH = phoneH + 60;

        // Phone sits left-center; doctor occupies right ~55%
        const phoneLeft = 0.0;
        final doctorLeft = availW * 0.38;
        final doctorW = availW - doctorLeft;

        return SizedBox(
          width: availW,
          height: totalH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Pink gradient circle backdrop (right side)
              Positioned(
                right: -availW * 0.08,
                top: totalH * 0.04,
                child: Container(
                  width: availW * 0.68,
                  height: totalH * 0.88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.18),
                        AppColors.secondary.withValues(alpha: 0.09),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),

              // Doctor image — RIGHT side
              Positioned(
                left: doctorLeft,
                top: 0,
                bottom: 0,
                width: doctorW,
                child: _DoctorImage(totalW: doctorW, totalH: totalH),
              ),

              // Phone mockup — LEFT-CENTER (drawn on top of doctor's left edge)
              Positioned(
                left: phoneLeft,
                top: 20,
                child: _PhoneMockup(w: phoneW, h: phoneH),
              ),

              // Floating cards
              Positioned(
                top: 24,
                left: phoneW - 16,
                child: const _FloatingCard(
                  icon: Icons.calendar_month_rounded,
                  iconColor: AppColors.primary,
                  title: 'Next Appointment',
                  subtitle: 'Dr. Priya · Today 3PM',
                ),
              ),
              const Positioned(
                bottom: 90,
                left: 0,
                child: _FloatingCard(
                  icon: Icons.bolt_rounded,
                  iconColor: Color(0xFFF59E0B),
                  title: 'Book in 60 sec',
                  subtitle: 'Instant confirmation',
                ),
              ),

              // 24/7 badge bottom-right
              Positioned(
                bottom: 20,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.support_agent_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(height: 4),
                      Text('24/7',
                          style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      Text('Support',
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Phone Mockup ─────────────────────────────────────────────────────────────

class _PhoneMockup extends StatelessWidget {
  final double w;
  final double h;
  const _PhoneMockup({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.12), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34.5),
        child: Column(
          children: [
            _StatusBar(w: w),
            Expanded(
              child: Container(
                color: const Color(0xFFF8F9FA),
                child: Column(children: [
                  _AppHeader(w: w),
                  _SearchBar(w: w),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(children: [
                        _ConsultCard(w: w),
                        _ServicesRow(w: w),
                        _AppointmentCard(w: w),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            _BottomNav(w: w),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final double w;
  const _StatusBar({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w,
      height: 24,
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(children: [
        Text('9:31',
            style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        const Spacer(),
        Row(children: [
          Container(
              width: 12,
              height: 7,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color: Colors.white70)),
          const SizedBox(width: 3),
          Container(
              width: 5,
              height: 7,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color: Colors.white)),
          const SizedBox(width: 3),
          Container(
            width: 14,
            height: 7,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.white70, width: 1),
            ),
            child: Row(children: [
              Container(
                  width: 9,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1),
                      color: Colors.white)),
            ]),
          ),
        ]),
      ]),
    );
  }
}

class _AppHeader extends StatelessWidget {
  final double w;
  const _AppHeader({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(w * 0.07, 10, w * 0.07, 8),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hi, Rahul \u{1F44B}',
                  style: GoogleFonts.poppins(
                      fontSize: w * 0.063,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E))),
              Text('How are you feeling today?',
                  style: GoogleFonts.poppins(
                      fontSize: w * 0.042,
                      color: const Color(0xFF9E9E9E))),
            ],
          ),
        ),
        Row(children: [
          Container(
            width: w * 0.11,
            height: w * 0.11,
            decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.notifications_none_rounded,
                size: w * 0.065, color: const Color(0xFF424242)),
          ),
          const SizedBox(width: 6),
          Container(
            width: w * 0.11,
            height: w * 0.11,
            decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.primaryGradient),
            child: Center(
                child: Text('R',
                    style: GoogleFonts.poppins(
                        fontSize: w * 0.045,
                        fontWeight: FontWeight.w700,
                        color: Colors.white))),
          ),
        ]),
      ]),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final double w;
  const _SearchBar({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(w * 0.07, 0, w * 0.07, 10),
      child: Container(
        height: w * 0.12,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: EdgeInsets.symmetric(horizontal: w * 0.04),
        child: Row(children: [
          Icon(Icons.search_rounded,
              size: w * 0.065, color: const Color(0xFFBDBDBD)),
          SizedBox(width: w * 0.03),
          Text('Search doctors, medicines…',
              style: GoogleFonts.poppins(
                  fontSize: w * 0.04,
                  color: const Color(0xFFBDBDBD))),
        ]),
      ),
    );
  }
}

class _ConsultCard extends StatelessWidget {
  final double w;
  const _ConsultCard({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:
          EdgeInsets.symmetric(horizontal: w * 0.07, vertical: w * 0.04),
      padding:
          EdgeInsets.symmetric(horizontal: w * 0.06, vertical: w * 0.05),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Consult a Doctor',
                  style: GoogleFonts.poppins(
                      fontSize: w * 0.06,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              SizedBox(height: w * 0.02),
              Text('Instant video consultation\nwith verified doctors',
                  style: GoogleFonts.poppins(
                      fontSize: w * 0.038,
                      color: Colors.white70,
                      height: 1.4)),
              SizedBox(height: w * 0.04),
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: w * 0.065, vertical: w * 0.025),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Consult Now',
                    style: GoogleFonts.poppins(
                        fontSize: w * 0.04,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
            ],
          ),
        ),
        SizedBox(width: w * 0.03),
        Container(
          width: w * 0.18,
          height: w * 0.18,
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle),
          child: Icon(Icons.medical_services_rounded,
              size: w * 0.1, color: Colors.white),
        ),
      ]),
    );
  }
}

class _ServicesRow extends StatelessWidget {
  final double w;
  const _ServicesRow({required this.w});

  @override
  Widget build(BuildContext context) {
    final items = [
      (icon: Icons.video_call_rounded, label: 'Consult'),
      (icon: Icons.medication_liquid_rounded, label: 'Pharmacy'),
      (icon: Icons.science_rounded, label: 'Lab Tests'),
      (icon: Icons.local_shipping_rounded, label: 'Ambulance'),
    ];
    return Container(
      color: Colors.white,
      margin: EdgeInsets.only(bottom: w * 0.02),
      padding: EdgeInsets.symmetric(
          horizontal: w * 0.07, vertical: w * 0.05),
      child: Column(children: [
        Row(children: [
          Text('Our Services',
              style: GoogleFonts.poppins(
                  fontSize: w * 0.05,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E))),
          const Spacer(),
          Text('View all',
              style: GoogleFonts.poppins(
                  fontSize: w * 0.04,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600)),
        ]),
        SizedBox(height: w * 0.04),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: items
              .map((item) => Column(children: [
                    Container(
                      width: w * 0.13,
                      height: w * 0.13,
                      decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(item.icon,
                          size: w * 0.07, color: AppColors.primary),
                    ),
                    SizedBox(height: w * 0.02),
                    Text(item.label,
                        style: GoogleFonts.poppins(
                            fontSize: w * 0.036,
                            color: const Color(0xFF424242),
                            fontWeight: FontWeight.w500)),
                  ]))
              .toList(),
        ),
      ]),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final double w;
  const _AppointmentCard({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
          horizontal: w * 0.07, vertical: w * 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Upcoming Appointment',
                style: GoogleFonts.poppins(
                    fontSize: w * 0.048,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E))),
            const Spacer(),
            Text('View all',
                style: GoogleFonts.poppins(
                    fontSize: w * 0.038,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          ]),
          SizedBox(height: w * 0.04),
          Container(
            padding: EdgeInsets.all(w * 0.04),
            decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFEEEEEE), width: 1)),
            child: Row(children: [
              Container(
                width: w * 0.11,
                height: w * 0.11,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient),
                child: Center(
                    child: Text('AS',
                        style: GoogleFonts.poppins(
                            fontSize: w * 0.038,
                            fontWeight: FontWeight.w700,
                            color: Colors.white))),
              ),
              SizedBox(width: w * 0.04),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dr. Ananya Sharma',
                        style: GoogleFonts.poppins(
                            fontSize: w * 0.046,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1A1A2E))),
                    Text('Cardiologist',
                        style: GoogleFonts.poppins(
                            fontSize: w * 0.036,
                            color: const Color(0xFF9E9E9E))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(children: [
                    Icon(Icons.calendar_today_rounded,
                        size: w * 0.036,
                        color: const Color(0xFF9E9E9E)),
                    const SizedBox(width: 2),
                    Text('Tomorrow',
                        style: GoogleFonts.poppins(
                            fontSize: w * 0.032,
                            color: const Color(0xFF9E9E9E))),
                  ]),
                  Text('11:30 AM',
                      style: GoogleFonts.poppins(
                          fontSize: w * 0.036,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ],
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final double w;
  const _BottomNav({required this.w});

  @override
  Widget build(BuildContext context) {
    final items = [
      (icon: Icons.home_rounded, active: true),
      (icon: Icons.search_rounded, active: false),
      (icon: Icons.calendar_month_rounded, active: false),
      (icon: Icons.person_rounded, active: false),
    ];
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0), width: 1)),
      ),
      padding: EdgeInsets.symmetric(horizontal: w * 0.04),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: items
            .map((item) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (item.active)
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 2),
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary),
                      )
                    else
                      const SizedBox(height: 6),
                    Icon(item.icon,
                        size: w * 0.09,
                        color: item.active
                            ? AppColors.primary
                            : const Color(0xFFBDBDBD)),
                  ],
                ))
            .toList(),
      ),
    );
  }
}

// ─── Floating Card ────────────────────────────────────────────────────────────

class _FloatingCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  const _FloatingCard(
      {required this.icon,
      required this.iconColor,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 6)),
        ],
        border: Border.all(color: const Color(0xFFF0F0F0), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 9),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E))),
          Text(subtitle,
              style: GoogleFonts.poppins(
                  fontSize: 10, color: const Color(0xFF9E9E9E))),
        ]),
      ]),
    );
  }
}

// ─── Doctor Image ─────────────────────────────────────────────────────────────

class _DoctorImage extends StatelessWidget {
  final double totalW;
  final double totalH;
  const _DoctorImage({required this.totalW, required this.totalH});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: totalW,
      height: totalH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Doctor photo — fades edges to white so gray bg disappears
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
                stops: [0.0, 0.18, 0.82, 1.0],
              ).createShader(bounds),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0.0, 0.78, 1.0],
                ).createShader(bounds),
                child: Image.asset(
                  'assets/images/doctor_hero.png',
                  width: totalW,
                  height: totalH,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ),

          // Verified badge — top-left
          Positioned(
            left: 4,
            top: totalH * 0.08,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 5)),
                ],
                border: Border.all(color: const Color(0xFFF0F0F0), width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                      color: Color(0xFFE8F5E9), shape: BoxShape.circle),
                  child: const Icon(Icons.verified_rounded,
                      size: 15, color: Color(0xFF2E7D32)),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Verified Doctor',
                        style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1A1A2E))),
                    Text('MBBS, MD · 8 yrs exp',
                        style: GoogleFonts.poppins(
                            fontSize: 9, color: const Color(0xFF9E9E9E))),
                  ],
                ),
              ]),
            ),
          ),

          // Rating badge — bottom-left
          Positioned(
            left: 8,
            bottom: totalH * 0.14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5)),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded,
                      size: 13, color: Color(0xFFFFF176)),
                  const SizedBox(width: 4),
                  Text('4.9',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ]),
                Text('Rating',
                    style: GoogleFonts.poppins(
                        fontSize: 9, color: Colors.white70)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

