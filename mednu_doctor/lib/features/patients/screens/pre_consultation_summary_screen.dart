import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/ux_widgets.dart';

/// Full, real-time breakdown of a patient's pre-consultation intake form —
/// streams `patient_intake_forms/{appointmentId}` live, so if the patient
/// submits (or the doctor re-opens this screen) while it's on screen, it
/// updates without a manual refresh. Reached from the "Pre-Consultation
/// Summary" card on the appointment list (see pre_consultation_summary_card.dart).
class PreConsultationSummaryScreen extends StatelessWidget {
  final String appointmentId;
  final String patientName;

  const PreConsultationSummaryScreen({
    super.key,
    required this.appointmentId,
    required this.patientName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Pre-Consultation Summary', style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          Text(patientName, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
        ]),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: appointmentId.isEmpty
            ? const Stream.empty()
            : FirebaseFirestore.instance.collection('patient_intake_forms').doc(appointmentId).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return ListView(padding: const EdgeInsets.all(16), children: List.generate(4, (_) => const SkeletonListTile()));
          }
          final data = snap.data?.data();
          if (data == null) {
            return const AppEmptyState(
              icon: Icons.assignment_late_outlined,
              title: 'Not Submitted Yet',
              message: 'The patient hasn\'t filled in their pre-consultation form yet. This screen updates automatically the moment they do.',
            );
          }
          return _buildBody(context, data);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> data) {
    final allergies = (data['allergies'] as List?)?.cast<Map>() ?? const [];
    final comorbidities = (data['comorbidities'] as List?)?.cast<Map>() ?? const [];
    final treatments = (data['treatments'] as List?)?.cast<Map>() ?? const [];
    final medications = (data['medications'] as List?)?.cast<Map>() ?? const [];
    final familyHistory = (data['familyHistory'] as List?)?.cast<dynamic>().map((e) => e.toString()).toList() ?? const [];
    final symptoms = (data['symptoms'] as List?)?.cast<dynamic>().map((e) => e.toString()).toList() ?? const [];
    final lifestyle = (data['lifestyle'] as Map?) ?? const {};
    final age = (data['age'] as String? ?? '').trim();
    final gender = (data['gender'] as String? ?? '').trim();
    final phone = (data['phone'] as String? ?? '').trim();
    final reason = (data['reasonForVisit'] as String? ?? '').trim();
    final otherSymptoms = (data['otherSymptoms'] as String? ?? '').trim();
    final duration = (data['symptomDuration'] as String? ?? '').trim();
    final severity = (data['symptomSeverity'] as String? ?? '').trim();
    final onMedication = data['onMedication'] as bool? ?? false;
    final submittedAt = (data['submittedAt'] as Timestamp?)?.toDate();

    final lifestyleFlags = <String>[
      if (lifestyle['smoking'] == true) 'Smokes',
      if (lifestyle['alcohol'] == true) 'Drinks alcohol',
      if (lifestyle['pregnant'] == true) 'Pregnant / trying to conceive',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Allergies first — safety-critical, always shown ────────────────
        allergies.isEmpty
            ? _bannerCard(
                icon: Icons.verified_rounded,
                color: AppColors.good,
                bg: AppColors.goodBg,
                text: 'No known allergies reported',
              )
            : _bannerCard(
                icon: Icons.warning_amber_rounded,
                color: AppColors.crit,
                bg: AppColors.critBg,
                text: 'Known allergies',
                detailItems: allergies,
              ),
        const SizedBox(height: 16),

        _Section(
          title: 'Visit Details',
          icon: Icons.badge_outlined,
          child: Column(children: [
            _kv('Age', age.isEmpty ? '—' : age),
            _kv('Gender', gender.isEmpty ? '—' : gender),
            _kv('Phone', phone.isEmpty ? '—' : phone),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Reason for visit', style: AppTextStyles.labelSmall),
              const SizedBox(height: 3),
              Text(reason, style: AppTextStyles.body),
            ],
          ]),
        ),

        _Section(
          title: 'Symptoms',
          icon: Icons.sick_outlined,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (duration.isNotEmpty || severity.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  if (duration.isNotEmpty) ...[const Icon(Icons.schedule_rounded, size: 13, color: AppColors.textHint), const SizedBox(width: 4), Text(duration, style: AppTextStyles.bodySmall), const SizedBox(width: 14)],
                  if (severity.isNotEmpty) ...[const Icon(Icons.speed_rounded, size: 13, color: AppColors.textHint), const SizedBox(width: 4), Text(severity, style: AppTextStyles.bodySmall)],
                ]),
              ),
            symptoms.isEmpty && otherSymptoms.isEmpty
                ? Text('None reported', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint))
                : Wrap(spacing: 8, runSpacing: 8, children: symptoms.map((s) => _chip(s)).toList()),
            if (otherSymptoms.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Other: $otherSymptoms', style: AppTextStyles.bodySmall),
            ],
          ]),
        ),

        _Section(
          title: 'Existing Medical Conditions',
          icon: Icons.health_and_safety_outlined,
          child: comorbidities.isEmpty
              ? Text('None reported', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint))
              : Column(children: comorbidities.map((c) => _detailTile(c['label'] as String? ?? '', c['detail'] as String? ?? '')).toList()),
        ),

        _Section(
          title: 'Previous Treatment / Surgery',
          icon: Icons.local_hospital_outlined,
          child: treatments.isEmpty
              ? Text('None reported', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint))
              : Column(children: treatments.map((t) => _detailTile(t['label'] as String? ?? '', t['detail'] as String? ?? '')).toList()),
        ),

        _Section(
          title: 'Current Medications',
          icon: Icons.medication_outlined,
          child: (!onMedication || medications.isEmpty)
              ? Text('None reported', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint))
              : Column(
                  children: medications.map((m) {
                    final name = m['name'] as String? ?? '';
                    final dose = m['dose'] as String? ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        const Icon(Icons.circle, size: 5, color: AppColors.textHint),
                        const SizedBox(width: 8),
                        Expanded(child: Text(dose.isNotEmpty ? '$name — $dose' : name, style: AppTextStyles.body)),
                      ]),
                    );
                  }).toList(),
                ),
        ),

        _Section(
          title: 'Family History',
          icon: Icons.family_restroom_rounded,
          child: familyHistory.isEmpty
              ? Text('None reported', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint))
              : Wrap(spacing: 8, runSpacing: 8, children: familyHistory.map((f) => _chip(f)).toList()),
        ),

        _Section(
          title: 'Lifestyle',
          icon: Icons.self_improvement_rounded,
          child: lifestyleFlags.isEmpty
              ? Text('No lifestyle risk factors reported', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint))
              : Wrap(spacing: 8, runSpacing: 8, children: lifestyleFlags.map((f) => _chip(f, color: AppColors.warn, bg: AppColors.warnBg)).toList()),
        ),

        if (submittedAt != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Submitted ${DateFormat('d MMM yyyy, h:mm a').format(submittedAt)}',
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ],
    );
  }

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 70, child: Text(label, style: AppTextStyles.labelSmall)),
          Expanded(child: Text(value, style: AppTextStyles.body)),
        ]),
      );

  Widget _chip(String label, {Color? color, Color? bg}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg ?? AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: color ?? AppColors.primary)),
      );

  Widget _detailTile(String label, String detail) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 5), child: Icon(Icons.circle, size: 5, color: AppColors.textHint)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppTextStyles.labelMedium),
              if (detail.isNotEmpty) ...[const SizedBox(height: 2), Text(detail, style: AppTextStyles.bodySmall)],
            ]),
          ),
        ]),
      );

  Widget _bannerCard({
    required IconData icon,
    required Color color,
    required Color bg,
    required String text,
    List<Map>? detailItems,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: TextStyle(fontFamily: 'Inter', fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
            if (detailItems != null && detailItems.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...detailItems.map((a) {
                final label = a['label'] as String? ?? '';
                final detail = a['detail'] as String? ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    detail.isNotEmpty ? '$label — $detail' : label,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: color),
                  ),
                );
              }),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Section({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(title, style: AppTextStyles.sectionTitle),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}
