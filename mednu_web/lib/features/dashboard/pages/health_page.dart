import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

class HealthPage extends StatelessWidget {
  const HealthPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Health Dashboard', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text('Track your vital health metrics', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: isMobile ? 2 : 4,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.1,
          children: const [
            _VitalCard(emoji: '❤️', title: 'Blood Pressure', value: '120/80', unit: 'mmHg', status: 'Normal', statusColor: AppColors.success),
            _VitalCard(emoji: '🩸', title: 'Blood Sugar', value: '95', unit: 'mg/dL', status: 'Normal', statusColor: AppColors.success),
            _VitalCard(emoji: '⚖️', title: 'BMI', value: '22.5', unit: 'kg/m²', status: 'Healthy', statusColor: AppColors.success),
            _VitalCard(emoji: '🏃', title: 'Steps Today', value: '7,842', unit: 'steps', status: 'Active', statusColor: AppColors.info),
          ],
        ),
        const SizedBox(height: 24),
        _MedicalInfoCard(),
        const SizedBox(height: 20),
        _AllergyCard(),
      ]),
    );
  }
}

class _VitalCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String value;
  final String unit;
  final String status;
  final Color statusColor;

  const _VitalCard({
    required this.emoji,
    required this.title,
    required this.value,
    required this.unit,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(status, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary, height: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: value, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  TextSpan(text: '  $unit', style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textHint)),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _MedicalInfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Medical Information', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        const Divider(height: 1),
        ...[
          ('🩸', 'Blood Group', 'B+'),
          ('📏', 'Height', '5\'8" (172 cm)'),
          ('⚖️', 'Weight', '70 kg'),
          ('🚭', 'Smoking', 'Non-smoker'),
          ('🍷', 'Alcohol', 'Occasional'),
          ('💊', 'Chronic Conditions', 'Hypertension'),
        ].map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Text(item.$1, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(child: Text(item.$2, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary))),
            Text(item.$3, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ]),
        )),
      ]),
    );
  }
}

class _AllergyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final allergies = ['Penicillin', 'Aspirin', 'Peanuts'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('⚠️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text('Known Allergies', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.error)),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: allergies.map((a) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.error.withOpacity(0.2)),
            ),
            child: Text(a, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error)),
          )).toList(),
        ),
      ]),
    );
  }
}
