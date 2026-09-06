import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../router/app_router.dart';

/// Real-time preview of the patient's pre-consultation intake form, streamed
/// straight from `patient_intake_forms/{appointmentId}` — the patient app
/// writes that doc from PreConsultationFormScreen right after payment. Tap
/// opens the full breakdown (PreConsultationSummaryScreen).
class PreConsultationSummaryCard extends StatelessWidget {
  final String appointmentId;
  final String patientName;

  const PreConsultationSummaryCard({
    super.key,
    required this.appointmentId,
    required this.patientName,
  });

  @override
  Widget build(BuildContext context) {
    if (appointmentId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('patient_intake_forms')
          .doc(appointmentId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final data = snap.data?.data();
        if (data == null) return _pendingChip();
        return _summaryCard(context, data);
      },
    );
  }

  Widget _pendingChip() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.neutralBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(children: [
        Icon(Icons.assignment_late_outlined, size: 14, color: AppColors.neutral),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Pre-consultation form not submitted yet',
            style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.neutral),
          ),
        ),
      ]),
    );
  }

  Widget _summaryCard(BuildContext context, Map<String, dynamic> data) {
    final allergies = (data['allergies'] as List?)?.cast<Map>() ?? const [];
    final symptoms = (data['symptoms'] as List?)?.cast<dynamic>().map((e) => e.toString()).toList() ?? const [];
    final reason = (data['reasonForVisit'] as String? ?? '').trim();
    final shownSymptoms = symptoms.take(4).toList();
    final moreCount = symptoms.length - shownSymptoms.length;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.preConsultationSummary, extra: {
        'appointmentId': appointmentId,
        'patientName': patientName,
      }),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.assignment_turned_in_rounded, size: 14, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Pre-Consultation Summary', style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
          ]),
          if (allergies.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: AppColors.critBg, borderRadius: BorderRadius.circular(8)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.crit),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Allergies: ${allergies.map((a) => a['label']).join(', ')}',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.crit),
                  ),
                ),
              ]),
            ),
          ],
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(reason, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary)),
          ],
          if (shownSymptoms.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ...shownSymptoms.map((s) => _chip(s)),
              if (moreCount > 0) _chip('+$moreCount more'),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
        child: Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      );
}
