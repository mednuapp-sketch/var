import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/section_header.dart';

class WhyMednuSection extends StatelessWidget {
  const WhyMednuSection({super.key});

  static const List<Map<String, dynamic>> _features = [
    {'icon': Icons.access_time_filled_rounded, 'title': '24/7 Healthcare', 'desc': 'Round-the-clock access to doctors, emergency support, and health resources — anytime, anywhere.'},
    {'icon': Icons.verified_rounded, 'title': 'Verified Doctors', 'desc': 'Every doctor is background-checked, credential-verified, and continuously rated by patients.'},
    {'icon': Icons.bolt_rounded, 'title': 'Instant Booking', 'desc': 'Book appointments in under 60 seconds. Choose time slots that work for your schedule.'},
    {'icon': Icons.local_shipping_rounded, 'title': 'Emergency Support', 'desc': 'One tap to dispatch the nearest ambulance. Real-time tracking until help arrives.'},
    {'icon': Icons.folder_shared_rounded, 'title': 'Digital Records', 'desc': 'All prescriptions, reports, and medical history stored securely in your digital locker.'},
    {'icon': Icons.shield_rounded, 'title': 'Secure Platform', 'desc': 'Your health data is encrypted in transit and at rest, with role-based access controls. Privacy-first by design.'},
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final crossCount = isMobile ? 1 : Responsive.isTablet(context) ? 2 : 3;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF33172C), Color(0xFF522546)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: Responsive.sectionPaddingV(context),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: Responsive.maxContentWidth(context)),
          child: Column(
            children: [
              const SectionHeader(
                tag: 'About MedNU',
                title: 'Healthcare Reimagined\nFor You',
                subtitle: 'We\'re not just an app. We\'re your complete healthcare partner.',
                alignment: CrossAxisAlignment.center,
                lightMode: true,
              ),
              SizedBox(height: isMobile ? 32 : 48),
              _VisionMission(isMobile: isMobile),
              SizedBox(height: isMobile ? 36 : 56),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: isMobile ? 2.5 : 1.4,
                ),
                itemCount: _features.length,
                itemBuilder: (context, i) => _FeatureCard(feature: _features[i], index: i),
              ),
              const SizedBox(height: 60),
              _TrustBadges(),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisionMission extends StatelessWidget {
  final bool isMobile;
  const _VisionMission({required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        icon: Icons.remove_red_eye_rounded,
        title: 'Our Vision',
        body: 'A world where quality healthcare is never out of reach — where every '
            'person, in every city and town, can consult a trusted doctor, get the '
            'right medicine, and manage their health with confidence, on their own terms.',
      ),
      (
        icon: Icons.flag_rounded,
        title: 'Our Mission',
        body: 'To make healthcare simple, accessible, and dependable for every family — '
            'connecting patients with verified doctors, pharmacies, and diagnostic '
            'services through one secure platform, and standing by them 24/7 when it matters most.',
      ),
    ];

    final children = cards.map((c) => Expanded(child: _VisionMissionCard(data: c))).toList();

    return isMobile
        ? Column(children: [
            for (int i = 0; i < children.length; i++) ...[
              _VisionMissionCard(data: cards[i]),
              if (i < children.length - 1) const SizedBox(height: 16),
            ],
          ])
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1) const SizedBox(width: 20),
                ],
              ],
            ),
          );
  }
}

class _VisionMissionCard extends StatelessWidget {
  final ({IconData icon, String title, String body}) data;
  const _VisionMissionCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
              child: Icon(data.icon, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(data.title, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
          ]),
          const SizedBox(height: 14),
          Text(data.body, style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70, height: 1.7)),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  final Map<String, dynamic> feature;
  final int index;
  const _FeatureCard({required this.feature, required this.index});

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: _hovered ? 0.1 : 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hovered ? AppColors.primary.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: isMobile
            ? Row(children: [
                _FeatureIconBox(icon: widget.feature['icon'] as IconData, hovered: _hovered),
                const SizedBox(width: 16),
                Expanded(child: _CardText(feature: widget.feature)),
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FeatureIconBox(icon: widget.feature['icon'] as IconData, hovered: _hovered),
                  const SizedBox(height: 16),
                  _CardText(feature: widget.feature),
                ],
              ),
      ),
    );
  }
}

class _FeatureIconBox extends StatelessWidget {
  final IconData icon;
  final bool hovered;
  const _FeatureIconBox({required this.icon, required this.hovered});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: hovered ? AppColors.primaryGradient : null,
        color: hovered ? null : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(child: Icon(icon, size: 24, color: Colors.white)),
    );
  }
}

class _CardText extends StatelessWidget {
  final Map<String, dynamic> feature;
  const _CardText({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          feature['title'] as String,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(
          feature['desc'] as String,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.white70, height: 1.6),
        ),
      ],
    );
  }
}

class _TrustBadges extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Wrap(
      spacing: isMobile ? 24 : 48,
      runSpacing: 24,
      alignment: WrapAlignment.center,
      children: const [
        _TrustBadge(value: '8', label: 'Care Services'),
        _TrustBadge(value: '3', label: 'Languages'),
        _TrustBadge(value: 'Video', label: 'Consultations'),
        _TrustBadge(value: 'Oct 2026', label: 'Launch'),
      ],
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final String value;
  final String label;
  const _TrustBadge({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ShaderMask(
        shaderCallback: (b) => const LinearGradient(colors: [Colors.white, Color(0xFFE9CFEE)]).createShader(b),
        child: Text(
          value,
          style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      ),
      Text(
        label,
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500),
      ),
    ]);
  }
}
