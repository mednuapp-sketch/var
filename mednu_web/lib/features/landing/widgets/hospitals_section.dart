import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/section_header.dart';

class HospitalsSection extends StatelessWidget {
  const HospitalsSection({super.key});

  static const List<Map<String, String>> _hospitals = [
    {'name': 'Apollo Hospitals', 'location': 'Bengaluru, Karnataka', 'phone': '+91 80 2941 4000', 'type': 'Multi-specialty', 'beds': '350', 'emoji': '🏥', 'tag': 'Premium'},
    {'name': 'Fortis Healthcare', 'location': 'Mumbai, Maharashtra', 'phone': '+91 22 6712 1000', 'type': 'Super-specialty', 'beds': '500', 'emoji': '🏨', 'tag': 'Top Rated'},
    {'name': 'AIIMS Regional', 'location': 'Delhi, NCR', 'phone': '+91 11 2658 8500', 'type': 'Government', 'beds': '1000', 'emoji': '🏫', 'tag': 'Govt.'},
    {'name': 'Manipal Hospitals', 'location': 'Mysuru, Karnataka', 'phone': '+91 821 422 2222', 'type': 'Multi-specialty', 'beds': '280', 'emoji': '🏢', 'tag': ''},
    {'name': 'Narayana Health', 'location': 'Hyderabad, Telangana', 'phone': '+91 40 7115 6565', 'type': 'Cardiac Center', 'beds': '400', 'emoji': '🏥', 'tag': 'Cardiac'},
    {'name': 'Kokilaben Hospital', 'location': 'Mumbai, Maharashtra', 'phone': '+91 22 4269 6969', 'type': 'Super-specialty', 'beds': '750', 'emoji': '🏨', 'tag': 'Premium'},
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final crossCount = isMobile ? 1 : Responsive.isTablet(context) ? 2 : 3;

    return Container(
      color: AppColors.surface,
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
                tag: 'Hospitals',
                title: 'Top Hospitals\nNear You',
                subtitle: 'Partner with 200+ accredited hospitals offering world-class care across India.',
              ),
              SizedBox(height: isMobile ? 32 : 48),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: isMobile ? 2.6 : 1.2,
                ),
                itemCount: _hospitals.length,
                itemBuilder: (context, i) => isMobile
                    ? _HospitalCardH(hospital: _hospitals[i])
                    : _HospitalCard(hospital: _hospitals[i]),
              ),
              const SizedBox(height: 40),
              GradientButton(
                label: 'View All Hospitals',
                width: 220,
                icon: Icons.arrow_forward_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HospitalCard extends StatefulWidget {
  final Map<String, String> hospital;
  const _HospitalCard({required this.hospital});

  @override
  State<_HospitalCard> createState() => _HospitalCardState();
}

class _HospitalCardState extends State<_HospitalCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.hospital;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        transform: Matrix4.translationValues(0, _hovered ? -6 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hovered ? AppColors.primary.withOpacity(0.3) : AppColors.border),
          boxShadow: _hovered
              ? [BoxShadow(color: AppColors.primary.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 12))]
              : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF42A5F5), Color(0xFF1565C0)]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(child: Text(h['emoji']!, style: const TextStyle(fontSize: 26))),
                ),
                const Spacer(),
                if (h['tag']!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(h['tag']!, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ),
              ]),
              const SizedBox(height: 14),
              Text(h['name']!, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.location_on_outlined, size: 13, color: AppColors.primary),
                const SizedBox(width: 4),
                Flexible(child: Text(h['location']!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary))),
              ]),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  _InfoChip(icon: Icons.local_hospital_outlined, label: h['type']!),
                  const SizedBox(width: 12),
                  _InfoChip(icon: Icons.bed_outlined, label: '${h['beds']} beds'),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.phone_outlined, size: 14),
                    label: Text('Call', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: GradientButton(label: 'Directions', height: 40, fontSize: 13, icon: Icons.directions_outlined)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _HospitalCardH extends StatelessWidget {
  final Map<String, String> hospital;
  const _HospitalCardH({required this.hospital});

  @override
  Widget build(BuildContext context) {
    final h = hospital;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF42A5F5), Color(0xFF1565C0)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(h['emoji']!, style: const TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(h['name']!, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 12, color: AppColors.primary),
              const SizedBox(width: 3),
              Flexible(child: Text(h['location']!, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary))),
            ]),
            const SizedBox(height: 4),
            Text(h['type']!, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w500)),
          ])),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            GradientButton(label: 'View', width: 70, height: 32, fontSize: 12),
          ]),
        ]),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: AppColors.textSecondary),
      const SizedBox(width: 4),
      Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
    ]);
  }
}
