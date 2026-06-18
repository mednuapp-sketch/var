import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/gradient_button.dart';

class PrescriptionsPage extends StatelessWidget {
  const PrescriptionsPage({super.key});

  static const _prescriptions = [
    {'doctor': 'Dr. Priya Sharma', 'date': 'June 10, 2026', 'diagnosis': 'Hypertension Management', 'medicines': '3 medicines', 'emoji': '👩‍⚕️', 'type': 'pdf'},
    {'doctor': 'Dr. Arjun Menon', 'date': 'May 28, 2026', 'diagnosis': 'Fever & Cold', 'medicines': '2 medicines', 'emoji': '👨‍⚕️', 'type': 'image'},
    {'doctor': 'Dr. Ravi Kumar', 'date': 'May 15, 2026', 'diagnosis': 'Knee Pain Treatment', 'medicines': '4 medicines', 'emoji': '👨‍⚕️', 'type': 'pdf'},
    {'doctor': 'Dr. Sanya Kapoor', 'date': 'May 1, 2026', 'diagnosis': 'Skin Allergy', 'medicines': '2 medicines', 'emoji': '👩‍⚕️', 'type': 'image'},
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Prescriptions', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text('All your doctor prescriptions in one place', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        Expanded(
          child: ListView.separated(
            itemCount: _prescriptions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) => _PrescriptionCard(data: _prescriptions[i]),
          ),
        ),
      ]),
    );
  }
}

class _PrescriptionCard extends StatefulWidget {
  final Map<String, String> data;
  const _PrescriptionCard({required this.data});

  @override
  State<_PrescriptionCard> createState() => _PrescriptionCardState();
}

class _PrescriptionCardState extends State<_PrescriptionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final isPdf = d['type'] == 'pdf';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hovered ? AppColors.primary.withOpacity(0.3) : AppColors.border),
          boxShadow: _hovered
              ? [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 16, offset: const Offset(0, 4))]
              : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
        ),
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isPdf ? AppColors.error.withOpacity(0.1) : AppColors.info.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text(isPdf ? '📄' : '🖼️', style: const TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['doctor']!, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(d['diagnosis']!, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Wrap(spacing: 16, children: [
              _ChipInfo(icon: Icons.calendar_today_rounded, label: d['date']!),
              _ChipInfo(icon: Icons.medication_rounded, label: d['medicines']!),
              _ChipInfo(icon: isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded, label: isPdf ? 'PDF' : 'Image'),
            ]),
          ])),
          const SizedBox(width: 12),
          Column(mainAxisSize: MainAxisSize.min, children: [
            _ActionBtn(icon: Icons.visibility_outlined, label: 'View', color: AppColors.primary),
            const SizedBox(height: 8),
            _ActionBtn(icon: Icons.download_rounded, label: 'Download', color: AppColors.accent),
          ]),
        ]),
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ChipInfo({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: AppColors.textSecondary),
      const SizedBox(width: 4),
      Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
    ]);
  }
}

class _ActionBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ActionBtn({required this.icon, required this.label, required this.color});

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered ? widget.color.withOpacity(0.1) : widget.color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _hovered ? widget.color.withOpacity(0.4) : widget.color.withOpacity(0.2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 13, color: widget.color),
            const SizedBox(width: 5),
            Text(widget.label, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: widget.color)),
          ]),
        ),
      ),
    );
  }
}
