import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

class ServicesSection extends StatelessWidget {
  const ServicesSection({super.key});

  static List<Map<String, dynamic>> get _services {
    final colors = AppColors.serviceCardColors;
    final raw = [
      (Icons.emergency_rounded, 'Emergency',
          'Immediate 24/7 help in a medical emergency', 'Call Now'),
      (Icons.video_call_rounded, 'Consultation',
          'Video or in-clinic consults with top doctors', 'Book Now'),
      (Icons.medication_liquid_rounded, 'Pharmacy',
          'Medicines delivered to your doorstep', 'Order Now'),
      (Icons.science_rounded, 'Diagnostics',
          'X-Ray, MRI, CT, ECG & lab tests at home', 'Book Test'),
      (Icons.pregnant_woman_rounded, 'Pregnancy',
          'Track your pregnancy journey week by week', 'Track Now'),
      (Icons.local_shipping_rounded, 'Ambulance',
          'Emergency ambulance dispatched to your location', 'Call Now'),
      (Icons.support_agent_rounded, 'Care Assist',
          'A health assistant on call whenever you need one', 'Try Now'),
      (Icons.elderly_rounded, 'Caregivers',
          'Trained attendants & caregiver support at home', 'Hire Now'),
      (Icons.fitness_center_rounded, 'Physiotherapy',
          'Physiotherapy & rehabilitation sessions', 'Book Now'),
      (Icons.restaurant_rounded, 'Nutrition and Diet',
          'Personalised diet plans from nutritionists', 'Get Plan'),
      (Icons.psychology_rounded, 'Therapy and Counselling',
          'Mental health support & therapy sessions', 'Book Now'),
      (Icons.medical_services_rounded, 'Equipment',
          'Rent or buy medical equipment online', 'Browse'),
      (Icons.local_hospital_rounded, 'Nearby Hospitals',
          'Locate hospitals nearby & pay bills with instant discounts',
          'Explore'),
      (Icons.receipt_long_rounded, 'Pay Hospital Bill',
          'Pay hospital bills online with instant discounts', 'Pay Now'),
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
                      color: const Color(0xFF1A1A2E),
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Everything you need for a healthier you',
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 13.5 : 15,
                      color: const Color(0xFF9E9E9E),
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
                itemBuilder: (_, i) => _ServiceCard(service: _services[i]),
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
  const _ServiceCard({required this.service});

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
                : const Color(0xFFF0F0F0),
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
                color: const Color(0xFF1A1A2E),
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
                color: const Color(0xFF9E9E9E),
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
    );
  }
}
