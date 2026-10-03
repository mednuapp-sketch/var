import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

class ServicesSection extends StatelessWidget {
  final VoidCallback onServiceTap;
  const ServicesSection({super.key, required this.onServiceTap});

  static List<Map<String, dynamic>> get _services {
    final colors = AppColors.serviceCardColors;
    final raw = [
      (
        Icons.emergency_rounded,
        'Emergency',
        'Immediate 24/7 help in a medical emergency',
        'Get the app'
      ),
      (
        Icons.video_call_rounded,
        'Consultation',
        'Video or in-clinic consults with top doctors',
        'Get the app'
      ),
      (
        Icons.medication_liquid_rounded,
        'Pharmacy',
        'Medicines delivered to your doorstep',
        'Get the app'
      ),
      (
        Icons.science_rounded,
        'Lab & Diagnostics',
        'X-Ray, MRI, CT, ECG & lab tests at home',
        'Get the app'
      ),
      (
        Icons.pregnant_woman_rounded,
        'Pregnancy',
        'Track your pregnancy journey week by week',
        'Get the app'
      ),
      (
        Icons.local_shipping_rounded,
        'Ambulance',
        'Emergency ambulance dispatched to your location',
        'Get the app'
      ),
      (
        Icons.support_agent_rounded,
        'Care Assist',
        'A health assistant on call whenever you need one',
        'Get the app'
      ),
      (
        Icons.elderly_rounded,
        'Caregivers',
        'Trained attendants & caregiver support at home',
        'Get the app'
      ),
      (
        Icons.fitness_center_rounded,
        'Physiotherapy',
        'Physiotherapy & rehabilitation sessions',
        'Get the app'
      ),
      (
        Icons.restaurant_rounded,
        'Diet & Dietician',
        'Personalised diet plans from dieticians',
        'Get the app'
      ),
      (
        Icons.psychology_rounded,
        'Therapy and Counselling',
        'Mental health support & therapy sessions',
        'Get the app'
      ),
      (
        Icons.medical_services_rounded,
        'Equipment',
        'Rent or buy medical equipment online',
        'Get the app'
      ),
      (
        Icons.local_hospital_rounded,
        'Nearby Hospitals',
        'Locate hospitals nearby & pay bills with instant discounts',
        'Get the app'
      ),
      (
        Icons.receipt_long_rounded,
        'Pay Hospital Bill',
        'Pay hospital bills online with instant discounts',
        'Get the app'
      ),
    ];
    return [
      for (int i = 0; i < raw.length; i++)
        {
          'icon': raw[i].$1,
          'title': raw[i].$2,
          'desc': raw[i].$3,
          'cta': raw[i].$4,
          'color': colors[i % colors.length],
        },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: Responsive.sectionPaddingV(context),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: Responsive.maxContentWidth(context)),
          child: Column(
            children: [
              // Section heading
              Column(
                children: [
                  Text(
                    'Our Services',
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 28 : 36,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF33172C),
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Everything you need for a healthier you',
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 13.5 : 15,
                      color: const Color(0xFF7A6472),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 32 : 52),

              // Service cards — every cell gets the same fixed height
              // (mainAxisExtent) so all cards render at equal size. Safe
              // from overflow because the card's title/description are
              // capped with maxLines, bounding their max content height.
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: Responsive.gridCrossAxisCount(
                    context,
                    desktop: 4,
                    tablet: 3,
                    mobile: 2,
                  ),
                  crossAxisSpacing: isMobile ? 14 : 16,
                  mainAxisSpacing: isMobile ? 14 : 16,
                  mainAxisExtent: 240,
                ),
                itemCount: _services.length,
                itemBuilder: (_, i) =>
                    _ServiceCard(service: _services[i], onTap: onServiceTap),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceCard extends StatefulWidget {
  final Map<String, dynamic> service;
  final VoidCallback onTap;
  const _ServiceCard({required this.service, required this.onTap});

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.service['color'] as Color? ?? AppColors.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: _hovered
              ? (Matrix4.identity()..translateByDouble(0.0, -4.0, 0.0, 1.0))
              : Matrix4.identity(),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered
                  ? accent.withValues(alpha: 0.35)
                  : const Color(0xFFEDE3EA),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? accent.withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.08),
                blurRadius: _hovered ? 24 : 12,
                offset: const Offset(0, 4),
                spreadRadius: _hovered ? 2 : 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _hovered ? accent : accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  widget.service['icon'] as IconData,
                  size: 26,
                  color: _hovered ? Colors.white : accent,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                widget.service['title'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF33172C),
                ),
              ),
              const SizedBox(height: 6),

              // Description
              Text(
                widget.service['desc'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: const Color(0xFF7A6472),
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 16),

              // CTA link
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.service['cta'] as String,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
