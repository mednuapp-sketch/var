import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/counselling_profile.dart';
import '../models/counselling_session.dart';
import '../services/counselling_profile_service.dart';
import '../services/counselling_session_service.dart';

// ── Raw realtime sources ─────────────────────────────────────────────────

final availableCounsellingSessionsProvider =
    StreamProvider.autoDispose<List<CounsellingSession>>((ref) {
  final uid = CounsellingProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return CounsellingSessionService.availableSessionsStream()
      .map((snap) => snap.docs.map(CounsellingSession.fromFirestore).toList());
});

final myCounsellingSessionsProvider =
    StreamProvider.autoDispose<List<CounsellingSession>>((ref) {
  final uid = CounsellingProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return CounsellingSessionService.mySessionsStream(uid)
      .map((snap) => snap.docs.map(CounsellingSession.fromFirestore).toList());
});

/// Everything this counsellor can currently see: the shared unclaimed pool
/// plus their own claimed sessions, de-duplicated by id.
final counsellingSessionsProvider = Provider.autoDispose<List<CounsellingSession>>((ref) {
  final available = ref.watch(availableCounsellingSessionsProvider).valueOrNull ?? const [];
  final mine = ref.watch(myCounsellingSessionsProvider).valueOrNull ?? const [];

  final byId = <String, CounsellingSession>{};
  for (final s in available) {
    byId[s.id] = s;
  }
  for (final s in mine) {
    byId[s.id] = s;
  }

  final all = byId.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return all;
});

final todayCounsellingSessionsProvider = Provider.autoDispose<List<CounsellingSession>>((ref) {
  final all = ref.watch(counsellingSessionsProvider);
  final now = DateTime.now();
  return all.where((s) {
    final d = DateTime.tryParse(s.preferredDate);
    if (d == null) return false;
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }).toList();
});

final upcomingCounsellingSessionsProvider = Provider.autoDispose<List<CounsellingSession>>((ref) {
  final all = ref.watch(counsellingSessionsProvider);
  return all
      .where((s) =>
          s.status == CounsellingSessionStatus.pending ||
          s.status == CounsellingSessionStatus.accepted ||
          s.status == CounsellingSessionStatus.inProgress)
      .toList();
});

final counsellingSessionHistoryProvider = Provider.autoDispose<List<CounsellingSession>>((ref) {
  final all = ref.watch(counsellingSessionsProvider);
  return all
      .where((s) =>
          s.status == CounsellingSessionStatus.completed ||
          s.status == CounsellingSessionStatus.cancelled ||
          s.status == CounsellingSessionStatus.expired)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

// ── Single-session detail ───────────────────────────────────────────────

final counsellingSessionDocProvider =
    StreamProvider.autoDispose.family<CounsellingSession?, String>((ref, sessionId) {
  return CounsellingSessionService.sessionStream(sessionId)
      .map((snap) => snap.exists ? CounsellingSession.fromFirestore(snap) : null);
});

// ── Profile ──────────────────────────────────────────────────────────────

final counsellingProfileDocProvider = StreamProvider.autoDispose<CounsellingProfile?>((ref) {
  final uid = CounsellingProfileService.currentUid;
  if (uid == null) return Stream.value(null);
  return CounsellingProfileService.profileStream(uid)
      .map((snap) => snap.exists ? CounsellingProfile.fromFirestore(snap) : null);
});

final counsellingProfileProvider = Provider.autoDispose<CounsellingProfile>((ref) {
  return ref.watch(counsellingProfileDocProvider).valueOrNull ?? CounsellingProfile.empty();
});

// ── Earnings ─────────────────────────────────────────────────────────────

final weeklyCounsellingEarningsProvider = Provider.autoDispose<List<double>>((ref) {
  final history = ref.watch(counsellingSessionHistoryProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));

  final buckets = List<double>.filled(7, 0);
  for (final s in history) {
    if (s.status != CounsellingSessionStatus.completed) continue;
    final day = DateTime(s.createdAt.year, s.createdAt.month, s.createdAt.day);
    final index = day.difference(weekStart).inDays;
    if (index >= 0 && index < 7) buckets[index] += s.amount.toDouble();
  }
  return buckets;
});

class CounsellingDashboardMetrics {
  final int todaySessions;
  final int completedToday;
  final num todayEarnings;
  final double rating;

  const CounsellingDashboardMetrics({
    required this.todaySessions,
    required this.completedToday,
    required this.todayEarnings,
    required this.rating,
  });
}

final counsellingDashboardMetricsProvider =
    Provider.autoDispose<CounsellingDashboardMetrics>((ref) {
  final today = ref.watch(todayCounsellingSessionsProvider);
  final profile = ref.watch(counsellingProfileProvider);
  final completedToday =
      today.where((s) => s.status == CounsellingSessionStatus.completed).toList();

  return CounsellingDashboardMetrics(
    todaySessions: today.length,
    completedToday: completedToday.length,
    todayEarnings: completedToday.fold<num>(0, (s, e) => s + e.amount),
    rating: profile.rating,
  );
});
