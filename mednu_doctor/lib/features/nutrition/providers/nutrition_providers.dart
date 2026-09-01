import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nutrition_appointment.dart';
import '../models/nutritionist_profile.dart';
import '../services/nutrition_appointment_service.dart';
import '../services/nutritionist_profile_service.dart';

final myNutritionAppointmentsProvider =
    StreamProvider.autoDispose<List<NutritionAppointment>>((ref) {
  final uid = NutritionAppointmentService.currentUid;
  if (uid == null) return Stream.value(const []);
  return NutritionAppointmentService.myAppointmentsStream(uid)
      .map((snap) => snap.docs.map(NutritionAppointment.fromFirestore).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
});

final todayNutritionAppointmentsProvider =
    Provider.autoDispose<List<NutritionAppointment>>((ref) {
  final all = ref.watch(myNutritionAppointmentsProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  return all.where((a) {
    final d = DateTime.tryParse(a.date);
    if (d == null) return false;
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }).toList();
});

final upcomingNutritionAppointmentsProvider =
    Provider.autoDispose<List<NutritionAppointment>>((ref) {
  final all = ref.watch(myNutritionAppointmentsProvider).valueOrNull ?? const [];
  return all
      .where((a) =>
          a.status == NutritionAppointmentStatus.pending ||
          a.status == NutritionAppointmentStatus.confirmed ||
          a.status == NutritionAppointmentStatus.inProgress)
      .toList();
});

final nutritionAppointmentHistoryProvider =
    Provider.autoDispose<List<NutritionAppointment>>((ref) {
  final all = ref.watch(myNutritionAppointmentsProvider).valueOrNull ?? const [];
  return all
      .where((a) =>
          a.status == NutritionAppointmentStatus.completed ||
          a.status == NutritionAppointmentStatus.cancelled)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

final nutritionAppointmentDocProvider =
    StreamProvider.autoDispose.family<NutritionAppointment?, String>((ref, id) {
  return NutritionAppointmentService.appointmentStream(id)
      .map((snap) => snap.exists ? NutritionAppointment.fromFirestore(snap) : null);
});

// ── Profile ──────────────────────────────────────────────────────────────
//
// `nutritionist_profiles/{uid}` is this partner's own, private, editable
// profile — a Cloud Function mirrors it into the public `nutritionists/{uid}`
// catalogue entry the patient app reads (see
// `onNutritionistProfileWriteForVisibility`, functions/index.js) once
// `status == 'active'`. This module never reads/writes `nutritionists`
// directly, same as every other partner module keeps its own operational
// data separate from what patients see.

final nutritionistProfileProvider = StreamProvider.autoDispose<NutritionistProfile>((ref) {
  final uid = NutritionistProfileService.currentUid;
  if (uid == null) return Stream.value(NutritionistProfile.empty());
  return NutritionistProfileService.profileStream(uid)
      .map((snap) => snap.exists ? NutritionistProfile.fromFirestore(snap) : NutritionistProfile.empty());
});

// ── Earnings ─────────────────────────────────────────────────────────────

class NutritionDashboardMetrics {
  final int todayAppointments;
  final int completedToday;
  final num todayEarnings;

  const NutritionDashboardMetrics({
    required this.todayAppointments,
    required this.completedToday,
    required this.todayEarnings,
  });
}

final nutritionDashboardMetricsProvider = Provider.autoDispose<NutritionDashboardMetrics>((ref) {
  final today = ref.watch(todayNutritionAppointmentsProvider);
  final completedToday =
      today.where((a) => a.status == NutritionAppointmentStatus.completed).toList();

  return NutritionDashboardMetrics(
    todayAppointments: today.length,
    completedToday: completedToday.length,
    todayEarnings: completedToday.fold<num>(0, (s, a) => s + a.fee),
  );
});
