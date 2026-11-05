import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../caregiver/models/visit.dart';
import '../../caregiver/providers/caregiver_providers.dart';
import '../../caregiver/services/caregiver_profile_service.dart';

// A Care Assistant shares the `caregiver_visits` pipeline with nurses (same
// Cloud Function mirror to the patient's `service_requests`, same wallet
// ledger); these providers only slice it down to care-assistant jobs.
// Everything derives from the two realtime streams in `caregiver_providers`,
// so a request booked in the patient app appears here the moment it lands.

final _careAssistantJobsProvider = Provider.autoDispose<List<Visit>>((ref) {
  final available = ref.watch(availableCaregiverVisitsProvider).valueOrNull ?? const <Visit>[];
  final mine = ref.watch(myCaregiverVisitsProvider).valueOrNull ?? const <Visit>[];

  final byId = <String, Visit>{};
  for (final v in available) {
    if (v.isCareAssistantJob) byId[v.id] = v;
  }
  // Written second so an already-claimed job wins over its stale pool copy.
  for (final v in mine) {
    if (v.isCareAssistantJob) byId[v.id] = v;
  }
  return byId.values.toList();
});

/// Requests waiting on this assistant: open-pool jobs they haven't declined
/// (only while on duty) plus jobs the patient pinned to them directly.
final incomingCareRequestsProvider = Provider.autoDispose<List<Visit>>((ref) {
  final uid = CaregiverProfileService.currentUid;
  if (uid == null) return const [];
  final onDuty = ref.watch(caregiverOnDutyProvider);
  final jobs = ref.watch(_careAssistantJobsProvider);
  return jobs
      .where((v) =>
          v.awaitingResponseFrom(uid) ||
          (onDuty && v.isOpenRequest && !v.declinedBy.contains(uid)))
      .toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
});

/// Accepted but not finished: accepted-and-scheduled, or in progress.
final activeCareJobsProvider = Provider.autoDispose<List<Visit>>((ref) {
  final uid = CaregiverProfileService.currentUid;
  if (uid == null) return const [];
  return ref
      .watch(_careAssistantJobsProvider)
      .where((v) =>
          v.caregiverId == uid &&
          (v.status == VisitStatus.checkedIn ||
              (v.status == VisitStatus.scheduled && v.acceptedAt != null)))
      .toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
});

final careJobHistoryProvider = Provider.autoDispose<List<Visit>>((ref) {
  final uid = CaregiverProfileService.currentUid;
  if (uid == null) return const [];
  return ref
      .watch(_careAssistantJobsProvider)
      .where((v) =>
          v.caregiverId == uid &&
          (v.status == VisitStatus.completed ||
              v.status == VisitStatus.missed ||
              v.status == VisitStatus.cancelled))
      .toList()
    ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
});

class CareAssistantMetrics {
  final int newRequests;
  final int activeJobs;
  final int completedToday;
  final num todayEarnings;
  const CareAssistantMetrics({
    required this.newRequests,
    required this.activeJobs,
    required this.completedToday,
    required this.todayEarnings,
  });
}

final careAssistantMetricsProvider = Provider.autoDispose<CareAssistantMetrics>((ref) {
  final history = ref.watch(careJobHistoryProvider);
  final now = DateTime.now();
  final completedToday = history.where((v) =>
      v.status == VisitStatus.completed &&
      v.scheduledAt.year == now.year &&
      v.scheduledAt.month == now.month &&
      v.scheduledAt.day == now.day);
  return CareAssistantMetrics(
    newRequests: ref.watch(incomingCareRequestsProvider).length,
    activeJobs: ref.watch(activeCareJobsProvider).length,
    completedToday: completedToday.length,
    todayEarnings: completedToday.fold<num>(0, (s, v) => s + v.fare),
  );
});

// ── Earnings (same bucketing as the Nurse module, over care-assistant jobs) ──

final careWeeklyEarningsProvider = Provider.autoDispose<List<double>>((ref) {
  final history = ref.watch(careJobHistoryProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final buckets = List<double>.filled(7, 0);
  for (final v in history) {
    if (v.status != VisitStatus.completed) continue;
    final day = DateTime(v.scheduledAt.year, v.scheduledAt.month, v.scheduledAt.day);
    final index = day.difference(weekStart).inDays;
    if (index >= 0 && index < 7) buckets[index] += v.fare.toDouble();
  }
  return buckets;
});

final careEarningsBreakdownProvider = Provider.autoDispose<CaregiverEarningsBreakdown>((ref) {
  final history = ref.watch(careJobHistoryProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final monthStart = DateTime(now.year, now.month, 1);
  num todayEarnings = 0, weekEarnings = 0, monthEarnings = 0;
  var monthJobs = 0;
  for (final v in history) {
    if (v.status != VisitStatus.completed) continue;
    final day = DateTime(v.scheduledAt.year, v.scheduledAt.month, v.scheduledAt.day);
    if (day.isBefore(monthStart)) continue;
    monthEarnings += v.fare;
    monthJobs++;
    if (!day.isBefore(weekStart)) weekEarnings += v.fare;
    if (!day.isBefore(today)) todayEarnings += v.fare;
  }
  return CaregiverEarningsBreakdown(
    todayEarnings: todayEarnings,
    weekEarnings: weekEarnings,
    monthEarnings: monthEarnings,
    avgPerVisit: monthJobs > 0 ? (monthEarnings / monthJobs).round() : 0,
  );
});
