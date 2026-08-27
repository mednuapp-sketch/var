import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/physio_profile.dart';
import '../models/physio_session.dart';
import '../services/physio_profile_service.dart';
import '../services/physio_session_service.dart';

// ── Raw realtime sources ─────────────────────────────────────────────────
//
// Two separate queries rather than one: the unclaimed session pool is shared
// across every physiotherapist partner, while a physiotherapist's own
// sessions are scoped to their uid. Firestore has no OR across those, so
// they're merged client-side in [physioSessionsProvider] below — same shape
// as the Caregiver module.

final availablePhysioSessionsProvider =
    StreamProvider.autoDispose<List<PhysioSession>>((ref) {
  final uid = PhysioProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return PhysioSessionService.availableSessionsStream()
      .map((snap) => snap.docs.map(PhysioSession.fromFirestore).toList());
});

final myPhysioSessionsProvider = StreamProvider.autoDispose<List<PhysioSession>>((ref) {
  final uid = PhysioProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return PhysioSessionService.mySessionsStream(uid)
      .map((snap) => snap.docs.map(PhysioSession.fromFirestore).toList());
});

/// Everything this physiotherapist can currently see: the shared unclaimed
/// pool plus their own claimed sessions, de-duplicated by id.
final physioSessionsProvider = Provider.autoDispose<List<PhysioSession>>((ref) {
  final available = ref.watch(availablePhysioSessionsProvider).valueOrNull ?? const [];
  final mine = ref.watch(myPhysioSessionsProvider).valueOrNull ?? const [];

  final byId = <String, PhysioSession>{};
  for (final s in available) {
    byId[s.id] = s;
  }
  for (final s in mine) {
    byId[s.id] = s;
  }

  final all = byId.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return all;
});

final todayPhysioSessionsProvider = Provider.autoDispose<List<PhysioSession>>((ref) {
  final all = ref.watch(physioSessionsProvider);
  final now = DateTime.now();
  return all.where((s) {
    final d = DateTime.tryParse(s.preferredDate);
    if (d == null) return false;
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }).toList();
});

final upcomingPhysioSessionsProvider = Provider.autoDispose<List<PhysioSession>>((ref) {
  final all = ref.watch(physioSessionsProvider);
  return all
      .where((s) =>
          s.status == PhysioSessionStatus.pending ||
          s.status == PhysioSessionStatus.accepted ||
          s.status == PhysioSessionStatus.inProgress)
      .toList();
});

final physioSessionHistoryProvider = Provider.autoDispose<List<PhysioSession>>((ref) {
  final all = ref.watch(physioSessionsProvider);
  return all
      .where((s) =>
          s.status == PhysioSessionStatus.completed ||
          s.status == PhysioSessionStatus.cancelled ||
          s.status == PhysioSessionStatus.expired)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

// ── Single-session detail ───────────────────────────────────────────────

final physioSessionDocProvider =
    StreamProvider.autoDispose.family<PhysioSession?, String>((ref, sessionId) {
  return PhysioSessionService.sessionStream(sessionId)
      .map((snap) => snap.exists ? PhysioSession.fromFirestore(snap) : null);
});

// ── Profile ──────────────────────────────────────────────────────────────

final physioProfileDocProvider = StreamProvider.autoDispose<PhysioProfile?>((ref) {
  final uid = PhysioProfileService.currentUid;
  if (uid == null) return Stream.value(null);
  return PhysioProfileService.profileStream(uid)
      .map((snap) => snap.exists ? PhysioProfile.fromFirestore(snap) : null);
});

/// Non-null by design — a partner who hasn't onboarded yet gets
/// [PhysioProfile.empty] rather than a null the Profile screen would have to
/// branch on.
final physioProfileProvider = Provider.autoDispose<PhysioProfile>((ref) {
  return ref.watch(physioProfileDocProvider).valueOrNull ?? PhysioProfile.empty();
});

// ── Earnings ─────────────────────────────────────────────────────────────

/// Mon..Sun totals for the current week, derived from real completed
/// sessions. (The wallet's authoritative balance comes from the
/// `physio_transactions` ledger via `walletSummaryProvider` — this is only
/// the chart's weekly shape.)
final weeklyPhysioEarningsProvider = Provider.autoDispose<List<double>>((ref) {
  final history = ref.watch(physioSessionHistoryProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));

  final buckets = List<double>.filled(7, 0);
  for (final s in history) {
    if (s.status != PhysioSessionStatus.completed) continue;
    final day = DateTime(s.createdAt.year, s.createdAt.month, s.createdAt.day);
    final index = day.difference(weekStart).inDays;
    if (index >= 0 && index < 7) buckets[index] += s.amount.toDouble();
  }
  return buckets;
});

class PhysioDashboardMetrics {
  final int todaySessions;
  final int completedToday;
  final num todayEarnings;
  final double rating;

  const PhysioDashboardMetrics({
    required this.todaySessions,
    required this.completedToday,
    required this.todayEarnings,
    required this.rating,
  });
}

final physioDashboardMetricsProvider = Provider.autoDispose<PhysioDashboardMetrics>((ref) {
  final today = ref.watch(todayPhysioSessionsProvider);
  final profile = ref.watch(physioProfileProvider);
  final completedToday =
      today.where((s) => s.status == PhysioSessionStatus.completed).toList();

  return PhysioDashboardMetrics(
    todaySessions: today.length,
    completedToday: completedToday.length,
    todayEarnings: completedToday.fold<num>(0, (s, e) => s + e.amount),
    rating: profile.rating,
  );
});
