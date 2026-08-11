import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/section_header.dart';

class WhyMednuSection extends StatelessWidget {
  const WhyMednuSection({super.key});

  static const List<Map<String, String>> _features = [
    {'emoji': '🕐', 'title': '24/7 Healthcare', 'desc': 'Round-the-clock access to doctors, emergency support, and health resources — anytime, anywhere.'},
    {'emoji': '✅', 'title': 'Verified Doctors', 'desc': 'Every doctor is background-checked, credential-verified, and continuously rated by patients.'},
    {'emoji': '⚡', 'title': 'Instant Booking', 'desc': 'Book appointments in under 60 seconds. Choose time slots that work for your schedule.'},
    {'emoji': '🚑', 'title': 'Emergency Support', 'desc': 'One tap to dispatch the nearest ambulance. Real-time tracking until help arrives.'},
    {'emoji': '📁', 'title': 'Digital Records', 'desc': 'All prescriptions, reports, and medical history stored securely in your digital locker.'},
    {'emoji': '🔒', 'title': 'Secure Platform', 'desc': 'Bank-level encryption protects your health data. HIPAA-compliant and privacy-first.'},
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final crossCount = isMobile ? 1 : Responsive.isTablet(context) ? 2 : 3;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF2D1B4E)],
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
                tag: 'Why MedNU',
                title: 'Healthcare Reimagined\nFor You',
                subtitle: 'We\'re not just an app. We\'re your complete healthcare partner.',
                alignment: CrossAxisAlignment.center,
              ),
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

class _FeatureCard extends StatefulWidget {
  final Map<String, String> feature;
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
                _EmojiBox(emoji: widget.feature['emoji']!, hovered: _hovered),
                const SizedBox(width: 16),
                Expanded(child: _CardText(feature: widget.feature)),
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EmojiBox(emoji: widget.feature['emoji']!, hovered: _hovered),
                  const SizedBox(height: 16),
                  _CardText(feature: widget.feature),
                ],
              ),
      ),
    );
  }
}

class _EmojiBox extends StatelessWidget {
  final String emoji;
  final bool hovered;
  const _EmojiBox({required this.emoji, required this.hovered});

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
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
    );
  }
}

class _CardText extends StatelessWidget {
  final Map<String, String> feature;
  const _CardText({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          feature['title']!,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(
          feature['desc']!,
          style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.white60, height: 1.6),
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
        _TrustBadge(value: '50K+', label: 'Patients Served'),
        _TrustBadge(value: '1,200+', label: 'Verified Doctors'),
        _TrustBadge(value: '200+', label: 'Hospitals'),
        _TrustBadge(value: '4.9 ★', label: 'Average Rating'),
        _TrustBadge(value: '98%', label: 'Satisfaction Rate'),
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
        shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
        child: Text(
          value,
          style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      ),
      Text(
        label,
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w500),
      ),
    ]);
  }
}
