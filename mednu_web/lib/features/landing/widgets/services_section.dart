import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

class ServicesSection extends StatelessWidget {
  const ServicesSection({super.key});

  static const List<Map<String, dynamic>> _services = [
    {
      'icon': Icons.person_search_rounded,
      'title': 'Consult Doctors',
      'desc': 'Talk to expert doctors online or visit clinic',
      'cta': 'Book Now',
    },
    {
      'icon': Icons.medication_rounded,
      'title': 'Order Medicines',
      'desc': 'Get medicines delivered at home',
      'cta': 'Order Now',
    },
    {
      'icon': Icons.biotech_rounded,
      'title': 'Lab Tests',
      'desc': 'Book tests at home & get reports online',
      'cta': 'Book Now',
    },
    {
      'icon': Icons.folder_shared_rounded,
      'title': 'Health Records',
      'desc': 'Store & manage your health records securely',
      'cta': 'View Now',
    },
    {
      'icon': Icons.health_and_safety_rounded,
      'title': 'Health Checkups',
      'desc': 'Full body checkups for you & your family',
      'cta': 'Book Now',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isTablet = Responsive.isTablet(context);

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

              // Service cards
              isMobile
                  ? GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 0.88,
                      ),
                      itemCount: _services.length,
                      itemBuilder: (_, i) =>
                          _ServiceCard(service: _services[i]),
                    )
                  : isTablet
                      ? Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: _services
                              .map((s) => SizedBox(
                                    width: (MediaQuery.sizeOf(context).width -
                                            Responsive.horizontalPadding(
                                                    context) *
                                                2 -
                                            32) /
                                        3,
                                    child: _ServiceCard(service: s),
                                  ))
                              .toList(),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _services
                              .map((s) => Expanded(
                                      child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    child: _ServiceCard(service: s),
                                  )))
                              .toList(),
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: _hovered
            ? (Matrix4.identity()..translate(0.0, -4.0))
            : Matrix4.identity(),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered
                ? AppColors.primary.withOpacity(0.25)
                : const Color(0xFFF0F0F0),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? AppColors.primary.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.08),
              blurRadius: _hovered ? 24 : 12,
              offset: const Offset(0, 4),
              spreadRadius: _hovered ? 2 : 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _hovered
                    ? AppColors.primary
                    : AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                widget.service['icon'] as IconData,
                size: 26,
                color: _hovered ? Colors.white : AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              widget.service['title'] as String,
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
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded,
                    size: 14, color: AppColors.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
