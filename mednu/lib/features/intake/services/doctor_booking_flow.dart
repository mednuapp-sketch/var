import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import 'intake_service.dart';

/// Shared steps every doctor-booking entry point (Doctor Profile, Quick
/// Connect, the Schedule-tab booking sheet) runs around payment: collect the
/// pre-consultation form BEFORE the booking exists, then — once payment
/// succeeds and a real appointment/consultation id comes back — attach the
/// answers to it and show the patient a confirmed/failed summary.
///
/// Previously only Doctor Profile's booking flow asked for this form, and it
/// asked for it AFTER payment. Both were bugs: patients booking through
/// Quick Connect or the Schedule tab never saw the form at all, and asking
/// for it post-payment meant a doctor could already be mid-charge before the
/// patient had given any history.
class DoctorBookingFlow {
  DoctorBookingFlow._();

  /// Shows the pre-consultation form in "pre-payment" mode (no appointmentId
  /// yet — see PreConsultationFormScreen) and returns what the patient
  /// entered. Mandatory: there is no "Skip for now" in this mode, so the
  /// only two outcomes are a non-empty Map (the patient gave at least one
  /// detail — enforced by the form itself) or null, meaning they backed out
  /// and cancelled the whole booking attempt. Callers must treat null as
  /// "stop here, nothing was booked" rather than proceeding to payment.
  static Future<Map<String, dynamic>?> collectIntake(
    BuildContext context, {
    required String doctorId,
    required String doctorName,
    String doctorSpecialty = '',
  }) {
    return context.push<Map<String, dynamic>>(
      AppRoutes.preConsultationForm,
      extra: {
        'doctorId': doctorId,
        'doctorName': doctorName,
        'doctorSpecialty': doctorSpecialty,
      },
    );
  }

  static bool _hasContent(Map<String, dynamic> data) {
    bool nonEmpty(dynamic v) {
      if (v is String) return v.trim().isNotEmpty;
      if (v is List) return v.isNotEmpty;
      if (v is bool) return v;
      if (v is Map) return v.values.any(nonEmpty);
      return false;
    }
    return data.values.any(nonEmpty);
  }

  /// Attaches the answers collected via [collectIntake] to the now-real
  /// booking. Best-effort: the booking itself already succeeded by the time
  /// this runs, so a failure here is logged-and-swallowed rather than shown
  /// to the patient as a booking failure. No-ops if the patient skipped
  /// (empty/null data) — the doctor app then correctly shows "not submitted
  /// yet" instead of an empty submission.
  static Future<void> submitIntake({
    required String appointmentId,
    required String doctorId,
    required String doctorName,
    required Map<String, dynamic>? data,
  }) async {
    if (data == null || !_hasContent(data)) return;
    try {
      await IntakeService.submit(
        appointmentId: appointmentId,
        doctorId: doctorId,
        doctorName: doctorName,
        data: data,
      );
    } catch (e) {
      debugPrint('Could not attach pre-consultation form to $appointmentId: $e');
    }
  }

  /// Pushes the patient-facing booking summary — the "confirm" step after
  /// payment, showing what was booked (and, on success, what was told to the
  /// doctor) or why it didn't go through.
  static Future<void> showSummary(
    BuildContext context, {
    required bool success,
    required String doctorName,
    String doctorSpecialty = '',
    String? date,
    String? time,
    String? consultationType,
    String? fee,
    Map<String, dynamic>? formData,
    String? failureReason,
  }) {
    return context.push(
      AppRoutes.bookingSummary,
      extra: {
        'success': success,
        'doctorName': doctorName,
        'doctorSpecialty': doctorSpecialty,
        'date': date,
        'time': time,
        'consultationType': consultationType,
        'fee': fee,
        'formData': formData,
        'failureReason': failureReason,
      },
    );
  }
}
