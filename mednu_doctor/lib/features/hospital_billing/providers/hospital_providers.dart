import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/hospital_profile.dart';
import '../services/hospital_appointment_service.dart';
import '../services/hospital_payment_service.dart';
import '../services/hospital_profile_service.dart';

// ── Profile ──────────────────────────────────────────────────────────────

final hospitalProfileProvider = StreamProvider.autoDispose<HospitalProfile?>((ref) {
  final uid = HospitalProfileService.currentUid;
  if (uid == null) return Stream.value(null);
  return HospitalProfileService.profileStream(uid)
      .map((snap) => snap.exists ? HospitalProfile.fromDoc(snap) : null);
});

// ── OP appointment queue for this login's linked hospital ─────────────────

final hospitalAppointmentsProvider =
    StreamProvider.autoDispose<List<HospitalAppointment>>((ref) {
  final hospitalId = ref.watch(hospitalProfileProvider).valueOrNull?.hospitalId;
  if (hospitalId == null || hospitalId.isEmpty) return Stream.value(const <HospitalAppointment>[]);
  return HospitalAppointmentService.streamForHospital(hospitalId);
});

// ── Bill payments for this login's linked hospital ─────────────────────────

final hospitalPaymentsProvider =
    StreamProvider.autoDispose<List<HospitalBillPayment>>((ref) {
  final hospitalId = ref.watch(hospitalProfileProvider).valueOrNull?.hospitalId;
  if (hospitalId == null || hospitalId.isEmpty) return Stream.value(const <HospitalBillPayment>[]);
  return HospitalPaymentService.streamForHospital(hospitalId);
});

// ── Dashboard metrics — derived client-side from the two live streams ─────
// Mirrors `labDashboardMetricsProvider` (lab/providers/lab_providers.dart):
// one realtime query per source collection, aggregated in Dart rather than
// with a second Firestore round trip.

class HospitalDashboardMetrics {
  final int todayAppointments;
  final int pendingCheckIns;
  final int completedToday;
  final int pendingPayments;

  const HospitalDashboardMetrics({
    required this.todayAppointments,
    required this.pendingCheckIns,
    required this.completedToday,
    required this.pendingPayments,
  });

  factory HospitalDashboardMetrics.empty() => const HospitalDashboardMetrics(
        todayAppointments: 0,
        pendingCheckIns: 0,
        completedToday: 0,
        pendingPayments: 0,
      );
}

/// `HospitalAppointment.date` is a plain `yyyy-MM-dd`-shaped string (the
/// patient-chosen visit date, not the booking timestamp) — same
/// `DateTime.tryParse` + calendar-day comparison used by
/// `todayNutritionAppointmentsProvider` (nutrition/providers/nutrition_providers.dart)
/// for the equivalent field on that module's booking model.
bool _isToday(String dateStr) {
  final d = DateTime.tryParse(dateStr);
  if (d == null) return false;
  final now = DateTime.now();
  return d.year == now.year && d.month == now.month && d.day == now.day;
}

final hospitalDashboardMetricsProvider = Provider.autoDispose<HospitalDashboardMetrics>((ref) {
  final appointments =
      ref.watch(hospitalAppointmentsProvider).valueOrNull ?? const <HospitalAppointment>[];
  final payments =
      ref.watch(hospitalPaymentsProvider).valueOrNull ?? const <HospitalBillPayment>[];

  var todayAppointments = 0;
  var pendingCheckIns = 0;
  var completedToday = 0;
  for (final a in appointments) {
    final isToday = _isToday(a.date);
    if (!isToday) continue;
    todayAppointments++;
    if (a.status == 'booked') pendingCheckIns++;
    if (a.status == 'completed') completedToday++;
  }

  // Not date-scoped by design — this is the desk's outstanding verification
  // queue (HospitalPaymentsScreen's "Mark as Verified" action), which can
  // reasonably include payments from a prior day that were missed.
  final pendingPayments = payments.where((p) => !p.hospitalVerified).length;

  return HospitalDashboardMetrics(
    todayAppointments: todayAppointments,
    pendingCheckIns: pendingCheckIns,
    completedToday: completedToday,
    pendingPayments: pendingPayments,
  );
});

// ── Today's queue preview (Dashboard's "Today" list) ───────────────────────

final hospitalTodayQueueProvider = Provider.autoDispose<List<HospitalAppointment>>((ref) {
  final appointments =
      ref.watch(hospitalAppointmentsProvider).valueOrNull ?? const <HospitalAppointment>[];
  return appointments
      .where((a) => _isToday(a.date) && (a.status == 'booked' || a.status == 'checked_in'))
      .toList();
});
