import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/section_header.dart';

class TestimonialsSection extends StatefulWidget {
  const TestimonialsSection({super.key});

  @override
  State<TestimonialsSection> createState() => _TestimonialsSectionState();
}

class _TestimonialsSectionState extends State<TestimonialsSection> {
  final PageController _ctrl = PageController(viewportFraction: 0.85);
  int _current = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final items = AppConstants.testimonials;

    return Container(
      color: Colors.white,
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
                tag: 'Testimonials',
                title: 'What Our Patients Say',
                subtitle: 'Thousands of families trust MedNu for their healthcare journey.',
              ),
              SizedBox(height: isMobile ? 32 : 48),
              isMobile
                  ? _MobileCarousel(ctrl: _ctrl, current: _current, items: items, onPageChanged: (i) => setState(() => _current = i))
                  : _DesktopGrid(items: items),
              if (isMobile) ...[
                const SizedBox(height: 20),
                _Dots(count: items.length, current: _current),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileCarousel extends StatelessWidget {
  final PageController ctrl;
  final int current;
  final List<Map<String, String>> items;
  final ValueChanged<int> onPageChanged;

  const _MobileCarousel({required this.ctrl, required this.current, required this.items, required this.onPageChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: PageView.builder(
        controller: ctrl,
        itemCount: items.length,
        onPageChanged: onPageChanged,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _TestimonialCard(item: items[i]),
        ),
      ),
    );
  }
}

class _DesktopGrid extends StatelessWidget {
  final List<Map<String, String>> items;
  const _DesktopGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final count = Responsive.isTablet(context) ? 2 : 3;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: count,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 1.5,
      ),
      itemCount: items.length > 6 ? 6 : items.length,
      itemBuilder: (context, i) => _TestimonialCard(item: items[i]),
    );
  }
}

class _TestimonialCard extends StatefulWidget {
  final Map<String, String> item;
  const _TestimonialCard({required this.item});

  @override
  State<_TestimonialCard> createState() => _TestimonialCardState();
}

class _TestimonialCardState extends State<_TestimonialCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.item;
    final rating = int.tryParse(d['rating'] ?? '5') ?? 5;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hovered ? AppColors.primary.withOpacity(0.3) : AppColors.border),
          boxShadow: _hovered
              ? [BoxShadow(color: AppColors.primary.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, 8))]
              : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              ...List.generate(rating, (_) => const Padding(
                padding: EdgeInsets.only(right: 2),
                child: Icon(Icons.star_rounded, color: Color(0xFFFFA726), size: 16),
              )),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Text('💬', style: const TextStyle(fontSize: 14)),
              ),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: Text(
                '"${d['review']!}"',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.65,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    d['avatar']!,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d['name']!, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text(d['location']!, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int current;
  const _Dots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: i == current ? 20 : 8,
        height: 8,
        decoration: BoxDecoration(
          gradient: i == current ? AppColors.primaryGradient : null,
          color: i == current ? null : AppColors.border,
          borderRadius: BorderRadius.circular(4),
        ),
      )),
    );
  }
}
