import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nutrition_appointment.dart';
import '../services/nutrition_appointment_service.dart';

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

// ── Profile (read-only) ────────────────────────────────────────────────────
//
// `nutritionists/{uid}` is an admin-curated catalogue the patient app reads
// from directly (see mednu/lib/features/services/nutrition/services/
// nutrition_service.dart) — this module only ever reads it, it never writes
// (see firestore.rules and the Phase A scope note in functions/index.js).

final nutritionistCatalogueDocProvider =
    StreamProvider.autoDispose<Map<String, dynamic>?>((ref) {
  final uid = NutritionAppointmentService.currentUid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('nutritionists')
      .doc(uid)
      .snapshots()
      .map((snap) => snap.data());
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
