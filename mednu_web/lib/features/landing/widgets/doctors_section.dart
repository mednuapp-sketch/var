import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/section_header.dart';

class DoctorsSection extends StatelessWidget {
  const DoctorsSection({super.key});

  static const List<Map<String, dynamic>> _doctors = [
    {'name': 'Dr. Priya Sharma',   'specialty': 'Cardiologist',      'exp': '15 yrs', 'fee': '₹800',  'rating': '4.9', 'reviews': '1.2k', 'initials': 'PS', 'tag': 'Top Rated',    'available': true,  'color': Color(0xFFC2185B)},
    {'name': 'Dr. Arjun Menon',    'specialty': 'Pediatrician',      'exp': '12 yrs', 'fee': '₹600',  'rating': '4.8', 'reviews': '980',  'initials': 'AM', 'tag': 'Most Booked',  'available': true,  'color': Color(0xFF7B1FA2)},
    {'name': 'Dr. Sanya Kapoor',   'specialty': 'Dermatologist',     'exp': '8 yrs',  'fee': '₹700',  'rating': '4.9', 'reviews': '745',  'initials': 'SK', 'tag': '',             'available': false, 'color': Color(0xFF1976D2)},
    {'name': 'Dr. Ravi Kumar',     'specialty': 'Orthopedic',        'exp': '18 yrs', 'fee': '₹900',  'rating': '4.7', 'reviews': '1.5k', 'initials': 'RK', 'tag': 'Expert',       'available': true,  'color': Color(0xFF00897B)},
    {'name': 'Dr. Meena Rao',      'specialty': 'Gynecologist',      'exp': '14 yrs', 'fee': '₹750',  'rating': '4.9', 'reviews': '2.1k', 'initials': 'MR', 'tag': 'Top Rated',    'available': true,  'color': Color(0xFFE91E8C)},
    {'name': 'Dr. Vikram Singh',   'specialty': 'Neurologist',       'exp': '20 yrs', 'fee': '₹1,200','rating': '4.8', 'reviews': '890',  'initials': 'VS', 'tag': 'Senior',       'available': false, 'color': Color(0xFF5C6BC0)},
    {'name': 'Dr. Ananya Das',     'specialty': 'Psychiatrist',      'exp': '10 yrs', 'fee': '₹650',  'rating': '4.9', 'reviews': '612',  'initials': 'AD', 'tag': '',             'available': true,  'color': Color(0xFFAB47BC)},
    {'name': 'Dr. Suresh Pillai',  'specialty': 'General Physician', 'exp': '22 yrs', 'fee': '₹400',  'rating': '4.7', 'reviews': '3.4k', 'initials': 'SP', 'tag': 'Most Booked',  'available': true,  'color': Color(0xFF26A69A)},
  ];

  static const List<String> _specialties = [
    'All', 'Cardiologist', 'Pediatrician', 'Dermatologist',
    'Orthopedic', 'Gynecologist', 'Neurologist', 'General Physician',
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final crossCount = isMobile ? 1 : Responsive.isTablet(context) ? 2 : 4;

    return Container(
      color: const Color(0xFFFAF8FF),
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
              const SectionHeader(
                tag: 'Our Doctors',
                title: 'Consult Top-Verified\nSpecialists',
                subtitle:
                    'Over 1,200 verified doctors across 40+ specialties — available for in-person and video consultations.',
              ),
              SizedBox(height: isMobile ? 28 : 44),
              const _SpecialtyFilter(specialties: _specialties),
              SizedBox(height: isMobile ? 24 : 36),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 18,
                  mainAxisSpacing: 18,
                  childAspectRatio: isMobile ? 2.6 : 0.75,
                ),
                itemCount: _doctors.length,
                itemBuilder: (_, i) => isMobile
                    ? _DoctorCardRow(doctor: _doctors[i])
                    : _DoctorCard(doctor: _doctors[i]),
              ),
              const SizedBox(height: 44),
              const GradientButton(
                label: 'View All 1,200+ Doctors',
                width: 250,
                height: 52,
                icon: Icons.arrow_forward_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Specialty filter chips ───────────────────────────────────────────────────

class _SpecialtyFilter extends StatefulWidget {
  final List<String> specialties;
  const _SpecialtyFilter({required this.specialties});

  @override
  State<_SpecialtyFilter> createState() => _SpecialtyFilterState();
}

class _SpecialtyFilterState extends State<_SpecialtyFilter> {
  String _selected = 'All';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.specialties.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final item = widget.specialties[i];
          final sel = _selected == item;
          return GestureDetector(
            onTap: () => setState(() => _selected = item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: BoxDecoration(
                gradient: sel ? AppColors.primaryGradient : null,
                color: sel ? null : Colors.white,
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                    color: sel
                        ? Colors.transparent
                        : AppColors.border,
                    width: 1.5),
                boxShadow: sel
                    ? [
                        BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ]
                    : [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2))
                      ],
              ),
              child: Text(
                item,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                  color: sel ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Desktop doctor card ──────────────────────────────────────────────────────

class _DoctorCard extends StatefulWidget {
  final Map<String, dynamic> doctor;
  const _DoctorCard({required this.doctor});

  @override
  State<_DoctorCard> createState() => _DoctorCardState();
}

class _DoctorCardState extends State<_DoctorCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.doctor;
    final color = d['color'] as Color;
    final tag = d['tag'] as String;
    final available = d['available'] as bool;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        transform: Matrix4.translationValues(0, _hovered ? -8 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _hovered
                ? color.withValues(alpha: 0.35)
                : const Color(0xFFEEEBF8),
            width: 1.5,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                      color: color.withValues(alpha: 0.2),
                      blurRadius: 32,
                      offset: const Offset(0, 16)),
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(initials: d['initials'] as String, color: color),
                  const Spacer(),
                  // Available indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: available
                          ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: available
                                ? const Color(0xFF22C55E)
                                : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          available ? 'Available' : 'Busy',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: available
                                ? const Color(0xFF22C55E)
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Tag
              if (tag.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    tag,
                    style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                d['name'] as String,
                style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                d['specialty'] as String,
                style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: color),
              ),
              const SizedBox(height: 12),
              // Rating + experience
              Row(children: [
                const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 15),
                const SizedBox(width: 4),
                Text(d['rating'] as String,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(width: 4),
                Text('(${d['reviews']})',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.textSecondary)),
                const Spacer(),
                const Icon(Icons.work_history_rounded,
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(d['exp'] as String,
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 10),
              // Divider
              Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
              const SizedBox(height: 10),
              Row(children: [
                Text(
                  d['fee'] as String,
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color),
                ),
                Text('/consult',
                    style: GoogleFonts.poppins(
                        fontSize: 10.5, color: AppColors.textSecondary)),
                const Spacer(),
              ]),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: _BookBtn(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Mobile doctor row card ───────────────────────────────────────────────────

class _DoctorCardRow extends StatelessWidget {
  final Map<String, dynamic> doctor;
  const _DoctorCardRow({required this.doctor});

  @override
  Widget build(BuildContext context) {
    final d = doctor;
    final color = d['color'] as Color;
    final available = d['available'] as bool;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEEBF8), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          _Avatar(initials: d['initials'] as String, color: color, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(d['name'] as String,
                        style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: available
                          ? const Color(0xFF22C55E)
                          : Colors.grey,
                    ),
                  ),
                ]),
                Text(d['specialty'] as String,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.star_rounded,
                      color: Color(0xFFF59E0B), size: 13),
                  const SizedBox(width: 3),
                  Text(d['rating'] as String,
                      style: GoogleFonts.poppins(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text(d['exp'] as String,
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: AppColors.textSecondary)),
                ]),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(d['fee'] as String,
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color)),
              const SizedBox(height: 6),
              _BookBtn(color: color, compact: true),
            ],
          ),
        ]),
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String initials;
  final Color color;
  final double size;
  const _Avatar(
      {required this.initials, required this.color, this.size = 62});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.poppins(
            fontSize: size * 0.3,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _BookBtn extends StatefulWidget {
  final Color color;
  final bool compact;
  const _BookBtn({required this.color, this.compact = false});

  @override
  State<_BookBtn> createState() => _BookBtnState();
}

class _BookBtnState extends State<_BookBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // Booking requires an account, so send the visitor straight into
        // the login flow — same entry point as "Get Started" elsewhere.
        onTap: () => context.go('/login'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: widget.compact ? 34 : 42,
          width: widget.compact ? 80 : null,
          padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 0 : 12, vertical: 0),
          decoration: BoxDecoration(
            gradient: _hovered || !widget.compact
                ? LinearGradient(
                    colors: [widget.color, widget.color.withValues(alpha: 0.8)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: _hovered || !widget.compact
                ? null
                : widget.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                        color: widget.color.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : [],
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.compact ? 'Book' : 'Book Now',
                  style: GoogleFonts.poppins(
                    fontSize: widget.compact ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: widget.compact && !_hovered
                        ? widget.color
                        : Colors.white,
                  ),
                ),
                if (!widget.compact) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 14, color: Colors.white),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
