import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

class PrescriptionsPage extends StatelessWidget {
  const PrescriptionsPage({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> get _stream {
    if (_uid.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('prescriptions')
        .where('patientId', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Padding(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Prescriptions',
            style: GoogleFonts.poppins(
                fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text('All your doctor prescriptions in one place',
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        Expanded(
          child: _uid.isEmpty
              ? _emptyState()
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _stream,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Text('Error loading prescriptions',
                            style: GoogleFonts.poppins(color: AppColors.error)),
                      );
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) return _emptyState();
                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, i) =>
                          _PrescriptionCard(data: docs[i].data()),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('💊', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        Text('No prescriptions yet',
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text('Your doctor prescriptions will appear here',
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _PrescriptionCard extends StatefulWidget {
  final Map<String, dynamic> data;
  const _PrescriptionCard({required this.data});

  @override
  State<_PrescriptionCard> createState() => _PrescriptionCardState();
}

class _PrescriptionCardState extends State<_PrescriptionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final doctorName = d['doctorName'] as String? ?? 'Doctor';
    final diagnosis = d['diagnosis'] as String? ?? '';
    final medicines = d['medicines'];
    final medicineCount = medicines is List ? medicines.length : 0;
    final createdAt = d['createdAt'];
    final dateStr = createdAt is Timestamp
        ? _formatTs(createdAt)
        : (createdAt as String? ?? '');
    final fileType = (d['fileType'] as String? ?? '').toLowerCase();
    final isPdf = fileType == 'pdf';
    final hasFile = (d['fileUrl'] as String? ?? '').isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: _hovered ? AppColors.primary.withValues(alpha: 0.3) : AppColors.border),
          boxShadow: _hovered
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 4))]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
        ),
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isPdf
                  ? AppColors.error.withValues(alpha: 0.1)
                  : AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                isPdf ? '📄' : '💊',
                style: const TextStyle(fontSize: 26),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(doctorName,
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              if (diagnosis.isNotEmpty)
                Text(diagnosis,
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Wrap(spacing: 16, children: [
                if (dateStr.isNotEmpty)
                  _ChipInfo(icon: Icons.calendar_today_rounded, label: dateStr),
                if (medicineCount > 0)
                  _ChipInfo(
                      icon: Icons.medication_rounded,
                      label: '$medicineCount ${medicineCount == 1 ? 'medicine' : 'medicines'}'),
                if (hasFile)
                  _ChipInfo(
                      icon: isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                      label: isPdf ? 'PDF' : 'Image'),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

String _formatTs(Timestamp ts) {
  final d = ts.toDate();
  const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month]} ${d.year}';
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
