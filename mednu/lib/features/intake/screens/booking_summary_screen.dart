import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';

/// The "confirm" step every doctor-booking flow ends on: what got booked (on
/// success, plus a recap of the pre-consultation answers actually given —
/// only the sections the patient filled in), or why it didn't go through (on
/// failure). Reached via DoctorBookingFlow.showSummary after payment
/// resolves, from Doctor Profile, Quick Connect and the Schedule-tab
/// booking sheet alike.
class BookingSummaryScreen extends StatelessWidget {
  final bool success;
  final String doctorName;
  final String doctorSpecialty;
  final String? date;
  final String? time;
  final String? consultationType;
  final String? fee;
  final Map<String, dynamic>? formData;
  final String? failureReason;

  const BookingSummaryScreen({
    super.key,
    required this.success,
    required this.doctorName,
    this.doctorSpecialty = '',
    this.date,
    this.time,
    this.consultationType,
    this.fee,
    this.formData,
    this.failureReason,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.appBackground,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                  children: [
                    _StatusHeader(success: success),
                    const SizedBox(height: 24),
                    _AppointmentCard(
                      doctorName: doctorName,
                      doctorSpecialty: doctorSpecialty,
                      date: date,
                      time: time,
                      consultationType: consultationType,
                      fee: fee,
                    ),
                    if (success && formData != null) ...[
                      const SizedBox(height: 16),
                      _IntakeRecap(data: formData!, doctorName: doctorName),
                    ],
                    if (!success && (failureReason ?? '').isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          failureReason!,
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.error, height: 1.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      if (success) {
                        context.go(AppRoutes.appointment);
                      } else {
                        context.pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text(
                      success ? 'View My Appointments' : 'Try Again',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final bool success;
  const _StatusHeader({required this.success});

  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xFF2E7D32) : AppColors.error;
    final colorLight = success ? const Color(0xFF66BB6A) : const Color(0xFFE57373);
    return Column(
      children: [
        Container(
          width: 84, height: 84,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color, colorLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Icon(success ? Icons.check_rounded : Icons.close_rounded, color: Colors.white, size: 42),
        ),
        const SizedBox(height: 18),
        Text(
          success ? 'Appointment Booked!' : 'Booking Not Completed',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 21, fontWeight: FontWeight.w800, color: context.appTextPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          success ? 'Your appointment is confirmed' : 'Your payment wasn\'t completed, so nothing was booked',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(color: context.appTextSecondary),
        ),
      ],
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final String doctorName;
  final String doctorSpecialty;
  final String? date;
  final String? time;
  final String? consultationType;
  final String? fee;

  const _AppointmentCard({
    required this.doctorName,
    required this.doctorSpecialty,
    this.date,
    this.time,
    this.consultationType,
    this.fee,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(children: [
        _row(context, Icons.person_rounded, doctorSpecialty.isNotEmpty ? 'Dr. $doctorName · $doctorSpecialty' : 'Dr. $doctorName', AppColors.primary),
        if ((date ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          _row(context, Icons.calendar_today_rounded, date!, const Color(0xFF1565C0)),
        ],
        if ((time ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          _row(context, Icons.schedule_rounded, time!, const Color(0xFF2E7D32)),
        ],
        if ((consultationType ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          _row(context, Icons.videocam_rounded, consultationType!, const Color(0xFF6A1B9A)),
        ],
        if ((fee ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          _row(context, Icons.payments_rounded, '₹$fee', AppColors.accent),
        ],
      ]),
    );
  }

  Widget _row(BuildContext context, IconData icon, String text, Color color) {
    return Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, size: 16, color: color),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(text, style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5, fontWeight: FontWeight.w600, color: context.appTextPrimary)),
      ),
    ]);
  }
}

/// Renders only the sections the patient actually filled in — an empty
/// pre-consultation form (fully skipped) means this widget isn't shown at
/// all (see BookingSummaryScreen.build).
class _IntakeRecap extends StatelessWidget {
  final Map<String, dynamic> data;
  final String doctorName;
  const _IntakeRecap({required this.data, required this.doctorName});

  @override
  Widget build(BuildContext context) {
    final reason = (data['reasonForVisit'] as String? ?? '').trim();
    final symptoms = (data['symptoms'] as List?)?.cast<dynamic>().map((e) => e.toString()).toList() ?? const [];
    final otherSymptoms = (data['otherSymptoms'] as String? ?? '').trim();
    final allergies = (data['allergies'] as List?)?.cast<Map>() ?? const [];
    final comorbidities = (data['comorbidities'] as List?)?.cast<Map>() ?? const [];
    final familyHistory = (data['familyHistory'] as List?)?.cast<dynamic>().map((e) => e.toString()).toList() ?? const [];

    final hasAnything = reason.isNotEmpty || symptoms.isNotEmpty || otherSymptoms.isNotEmpty ||
        allergies.isNotEmpty || comorbidities.isNotEmpty || familyHistory.isNotEmpty;
    if (!hasAnything) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.assignment_turned_in_rounded, size: 17, color: AppColors.primary),
          const SizedBox(width: 8),
          const Text('What you told Dr.', style: AppTextStyles.h4),
          Text(' $doctorName', style: AppTextStyles.h4.copyWith(color: AppColors.primary)),
        ]),
        const SizedBox(height: 12),
        if (allergies.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Allergies: ${allergies.map((a) => a['label']).join(', ')}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.error),
                ),
              ),
            ]),
          ),
        ],
        if (reason.isNotEmpty) ...[
          Text(reason, style: AppTextStyles.bodyMedium.copyWith(color: context.appTextPrimary)),
          const SizedBox(height: 10),
        ],
        if (symptoms.isNotEmpty || otherSymptoms.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: [
            ...symptoms.map((s) => _chip(s)),
            if (otherSymptoms.isNotEmpty) _chip(otherSymptoms),
          ]),
        if (comorbidities.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: comorbidities.map((c) => _chip(c['label'] as String? ?? '')).toList()),
        ],
        if (familyHistory.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Family history: ${familyHistory.join(', ')}', style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
        ],
      ]),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
      );
}
