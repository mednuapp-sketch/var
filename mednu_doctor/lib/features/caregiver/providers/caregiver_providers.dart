import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/care_note.dart';
import '../models/care_task.dart';
import '../models/caregiver_profile.dart';
import '../models/visit.dart';
import '../services/caregiver_profile_service.dart';
import '../services/caregiver_visit_service.dart';

/// True while the caregiver is marked on-duty/available. Local,
/// session-only state — nothing server-side consumes it yet, and inventing a
/// field for it would mean a schema change this module isn't allowed to make.
final caregiverOnDutyProvider = StateProvider<bool>((ref) => true);

// ── Raw realtime sources ─────────────────────────────────────────────────
//
// Two separate queries rather than one: the unclaimed assignment pool is
// shared across every caregiver partner (`caregiverId == null`), while a
// caregiver's own visits are scoped to their uid. Firestore has no OR across
// those, so they're merged client-side in `caregiverVisitsProvider` below.

final availableCaregiverVisitsProvider =
    StreamProvider.autoDispose<List<Visit>>((ref) {
  final uid = CaregiverProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return CaregiverVisitService.availableVisitsStream()
      .map((snap) => snap.docs.map(Visit.fromFirestore).toList());
});

final myCaregiverVisitsProvider = StreamProvider.autoDispose<List<Visit>>((ref) {
  final uid = CaregiverProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return CaregiverVisitService.myVisitsStream(uid)
      .map((snap) => snap.docs.map(Visit.fromFirestore).toList());
});

/// Everything this caregiver can currently see: the shared unclaimed pool
/// plus their own assigned visits, de-duplicated by id (a just-claimed visit
/// briefly appears in both streams while they converge).
///
/// Kept as a plain `List<Visit>` provider — the same type the previous mock
/// `StateNotifierProvider` exposed — so every derived provider and screen
/// below reads exactly as it did before. Items here carry empty
/// `tasks`/`notes`: those live in subcollections and are only joined in by
/// [visitByIdProvider], which is all the detail screens use.
final caregiverVisitsProvider = Provider.autoDispose<List<Visit>>((ref) {
  final available = ref.watch(availableCaregiverVisitsProvider).valueOrNull ?? const [];
  final mine = ref.watch(myCaregiverVisitsProvider).valueOrNull ?? const [];

  final byId = <String, Visit>{};
  // `mine` is written second so an already-claimed visit wins over its stale
  // copy in the shared pool.
  for (final v in available) {
    byId[v.id] = v;
  }
  for (final v in mine) {
    byId[v.id] = v;
  }

  final all = byId.values.toList()..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return all;
});

final todayVisitsProvider = Provider.autoDispose<List<Visit>>((ref) {
  final all = ref.watch(caregiverVisitsProvider);
  final now = DateTime.now();
  return all
      .where((v) =>
          v.scheduledAt.year == now.year &&
          v.scheduledAt.month == now.month &&
          v.scheduledAt.day == now.day)
      .toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
});

final upcomingVisitsProvider = Provider.autoDispose<List<Visit>>((ref) {
  final all = ref.watch(caregiverVisitsProvider);
  return all
      .where((v) => v.status == VisitStatus.scheduled || v.status == VisitStatus.checkedIn)
      .toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
});

final visitHistoryProvider = Provider.autoDispose<List<Visit>>((ref) {
  final all = ref.watch(caregiverVisitsProvider);
  return all
      .where((v) => v.status == VisitStatus.completed || v.status == VisitStatus.missed)
      .toList()
    ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
});

// ── Single-visit detail: header doc + tasks + notes, all realtime ─────────

/// Realtime single-document stream. Backing the by-id lookup with its own
/// doc listener (rather than scanning the merged list) means a detail screen
/// stays live even once the visit has left both list queries — e.g. after
/// it's completed, or after another caregiver claimed it.
final caregiverVisitDocProvider =
    StreamProvider.autoDispose.family<Visit?, String>((ref, visitId) {
  return CaregiverVisitService.visitStream(visitId)
      .map((snap) => snap.exists ? Visit.fromFirestore(snap) : null);
});

final visitTasksProvider =
    StreamProvider.autoDispose.family<List<CareTask>, String>((ref, visitId) {
  return CaregiverVisitService.tasksStream(visitId)
      .map((snap) => snap.docs.map(CareTask.fromFirestore).toList());
});

final visitNotesProvider =
    StreamProvider.autoDispose.family<List<CareNote>, String>((ref, visitId) {
  return CaregiverVisitService.notesStream(visitId)
      .map((snap) => snap.docs.map(CareNote.fromFirestore).toList());
});

/// The visit header joined with its `tasks`/`notes` subcollections — the
/// complete `Visit` the detail/checklist/notes/photos/summary screens expect.
/// Three separate listeners rather than one denormalised document, so ticking
/// a checklist item doesn't rewrite (and re-notify listeners of) the whole
/// visit.
final visitByIdProvider = Provider.autoDispose.family<Visit?, String>((ref, id) {
  final visit = ref.watch(caregiverVisitDocProvider(id)).valueOrNull;
  if (visit == null) return null;
  return visit.copyWith(
    tasks: ref.watch(visitTasksProvider(id)).valueOrNull ?? const [],
    notes: ref.watch(visitNotesProvider(id)).valueOrNull ?? const [],
  );
});

// ── Profile ──────────────────────────────────────────────────────────────

final caregiverProfileDocProvider =
    StreamProvider.autoDispose<CaregiverProfile?>((ref) {
  final uid = CaregiverProfileService.currentUid;
  if (uid == null) return Stream.value(null);
  return CaregiverProfileService.profileStream(uid)
      .map((snap) => snap.exists ? CaregiverProfile.fromFirestore(snap) : null);
});

/// Non-null by design — a partner who hasn't onboarded yet gets
/// [CaregiverProfile.empty] rather than a null the Profile screen would have
/// to branch on.
final caregiverProfileProvider = Provider.autoDispose<CaregiverProfile>((ref) {
  return ref.watch(caregiverProfileDocProvider).valueOrNull ?? CaregiverProfile.empty();
});

// ── Earnings ─────────────────────────────────────────────────────────────

/// Mon..Sun totals for the current week, derived from real completed visits.
/// (The wallet's authoritative balance comes from the
/// `caregiver_transactions` ledger via `walletSummaryProvider` — this is only
/// the chart's weekly shape.)
final weeklyCaregiverEarningsProvider = Provider.autoDispose<List<double>>((ref) {
  final history = ref.watch(visitHistoryProvider);
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

class CaregiverDashboardMetrics {
  final int todayVisits;
  final int completedToday;
  final num todayEarnings;
  final double rating;

  const CaregiverDashboardMetrics({
    required this.todayVisits,
    required this.completedToday,
    required this.todayEarnings,
    required this.rating,
  });
}

final caregiverDashboardMetricsProvider =
    Provider.autoDispose<CaregiverDashboardMetrics>((ref) {
  final today = ref.watch(todayVisitsProvider);
  final profile = ref.watch(caregiverProfileProvider);
  final completedToday = today.where((v) => v.status == VisitStatus.completed).toList();

  return CaregiverDashboardMetrics(
    todayVisits: today.length,
    completedToday: completedToday.length,
    todayEarnings: completedToday.fold<num>(0, (s, v) => s + v.fare),
    rating: profile.rating,
  );
});
