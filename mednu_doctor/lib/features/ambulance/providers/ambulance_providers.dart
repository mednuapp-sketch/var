import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ambulance_request.dart';
import '../models/trip.dart';
import '../models/vehicle_profile.dart';
import '../services/ambulance_profile_service.dart';
import '../services/ambulance_request_service.dart';

/// True while the ambulance partner is marked online/available. Backed by
/// `ambulance_profiles/{uid}.isOnline` — written by AmbulancePresenceService
/// and read by `_findNearestOnlineAmbulance` (functions/index.js) to decide
/// who's a candidate for a new request. Defaults to false: an ambulance that
/// has never toggled online (or whose profile hasn't loaded yet) must never
/// read as available to dispatch.
final ambulanceOnlineProvider = StreamProvider.autoDispose<bool>((ref) {
  final uid = AmbulanceProfileService.currentUid;
  if (uid == null) return Stream.value(false);
  return AmbulanceProfileService.profileStream(uid)
      .map((snap) => snap.data()?['isOnline'] as bool? ?? false);
});

// ── Raw realtime sources ─────────────────────────────────────────────────
//
// Two separate queries rather than one: the unclaimed dispatch queue is
// shared across every ambulance partner (`ambulanceId == null`), while a
// partner's own runs are scoped to their uid. Firestore has no OR across
// those, so they're merged client-side in `ambulanceRequestsProvider` below.

final availableAmbulanceRequestsProvider =
    StreamProvider.autoDispose<List<AmbulanceRequest>>((ref) {
  final uid = AmbulanceProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  // Requests this driver declined stay in the shared pool for everyone else.
  return AmbulanceRequestService.availableRequestsStream().map((snap) => snap.docs
      .where((d) => !((d.data()['declinedBy'] as List?)?.contains(uid) ?? false))
      .map(AmbulanceRequest.fromFirestore)
      .toList());
});

final myAmbulanceRequestsProvider =
    StreamProvider.autoDispose<List<AmbulanceRequest>>((ref) {
  final uid = AmbulanceProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return AmbulanceRequestService.myRequestsStream(uid).map((snap) {
    // A declined request disappears at once, before the Cloud Function has
    // finished handing it to the next driver.
    final items = snap.docs
        .where((d) => d.data()['declineRequested'] != true)
        .map(AmbulanceRequest.fromFirestore)
        .toList()
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    return items;
  });
});

/// Everything this partner can currently see: the shared unclaimed queue
/// plus their own claimed runs, de-duplicated by id (a request claimed by
/// this partner briefly appears in both streams while they converge).
///
/// Kept as a plain `List<AmbulanceRequest>` provider — the same type the
/// previous mock `StateNotifierProvider` exposed — so every derived provider
/// and screen below reads exactly as it did before. Actions are no longer
/// methods on a notifier: they go through `AmbulanceRequestService` so each
/// one is a transaction-safe, conflict-detecting Firestore write.
final ambulanceRequestsProvider = Provider.autoDispose<List<AmbulanceRequest>>((ref) {
  final available = ref.watch(availableAmbulanceRequestsProvider).valueOrNull ?? const [];
  final mine = ref.watch(myAmbulanceRequestsProvider).valueOrNull ?? const [];

  final byId = <String, AmbulanceRequest>{};
  // `mine` is written second so an already-claimed request wins over its
  // stale copy in the shared queue.
  for (final r in available) {
    byId[r.id] = r;
  }
  for (final r in mine) {
    byId[r.id] = r;
  }

  final all = byId.values.toList()
    ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
  return all;
});

final pendingRequestsProvider = Provider.autoDispose<List<AmbulanceRequest>>((ref) {
  return ref
      .watch(ambulanceRequestsProvider)
      .where((r) => r.status == AmbulanceRequestStatus.pending)
      .toList();
});

final activeRequestProvider = Provider.autoDispose<AmbulanceRequest?>((ref) {
  final all = ref.watch(ambulanceRequestsProvider);
  for (final r in all) {
    if (r.status == AmbulanceRequestStatus.accepted ||
        r.status == AmbulanceRequestStatus.enRoute ||
        r.status == AmbulanceRequestStatus.arrived) {
      return r;
    }
  }
  return null;
});

// ── Job-list tabs (Active / Completed / Cancelled) ───────────────────────
//
// These expose `AsyncValue` (unlike the plain-list providers above) so the
// tabbed job list can distinguish loading and error from a genuinely empty
// tab. They reuse the two live request streams and the trips stream that
// already exist — no extra Firestore listeners, and no new query shapes:
// every query stays a single-field `where` (or the already-declared
// `ambulance_trips` composite index), and `firestore.rules` permits each
// read for the owning partner (`ambulanceId == auth.uid`) or, for the open
// dispatch pool, any ambulance partner.

const _liveStatuses = {
  AmbulanceRequestStatus.pending,
  AmbulanceRequestStatus.accepted,
  AmbulanceRequestStatus.enRoute,
  AmbulanceRequestStatus.arrived,
};

/// Active/Pending tab: unclaimed pool + this partner's own runs that are
/// still live (pending, accepted, en route, arrived), newest first.
final activeJobsProvider = Provider.autoDispose<AsyncValue<List<AmbulanceRequest>>>((ref) {
  final available = ref.watch(availableAmbulanceRequestsProvider);
  final mine = ref.watch(myAmbulanceRequestsProvider);

  // Either stream failing means the list would be silently incomplete.
  if (available.hasError && !available.hasValue) {
    return AsyncValue.error(available.error!, available.stackTrace ?? StackTrace.empty);
  }
  if (mine.hasError && !mine.hasValue) {
    return AsyncValue.error(mine.error!, mine.stackTrace ?? StackTrace.empty);
  }
  if (!available.hasValue && !mine.hasValue) return const AsyncValue.loading();

  final byId = <String, AmbulanceRequest>{};
  for (final r in available.valueOrNull ?? const <AmbulanceRequest>[]) {
    byId[r.id] = r;
  }
  for (final r in mine.valueOrNull ?? const <AmbulanceRequest>[]) {
    byId[r.id] = r;
  }
  final items = byId.values.where((r) => _liveStatuses.contains(r.status)).toList()
    ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
  return AsyncValue.data(items);
});

/// Cancelled tab: requests this partner declined (`reject` stamps
/// `ambulanceId` and sets `cancelled`) or that were cancelled after being
/// pinned/claimed. Derived from the partner's own-requests stream, sorted by
/// most recent activity.
final cancelledJobsProvider = Provider.autoDispose<AsyncValue<List<AmbulanceRequest>>>((ref) {
  return ref.watch(myAmbulanceRequestsProvider).whenData((all) {
    final items = all.where((r) => r.status == AmbulanceRequestStatus.cancelled).toList()
      ..sort((a, b) => (b.updatedAt ?? b.requestedAt).compareTo(a.updatedAt ?? a.requestedAt));
    return items;
  });
});

/// Realtime single-document stream. Backing the by-id lookup with its own
/// doc listener (rather than scanning the merged list) means a detail screen
/// stays live even once the request has left both list queries — e.g. after
/// it's completed, or after another partner claimed it.
final ambulanceRequestDocProvider =
    StreamProvider.autoDispose.family<AmbulanceRequest?, String>((ref, requestId) {
  return AmbulanceRequestService.requestStream(requestId)
      .map((snap) => snap.exists ? AmbulanceRequest.fromFirestore(snap) : null);
});

final requestByIdProvider =
    Provider.autoDispose.family<AmbulanceRequest?, String>((ref, id) {
  return ref.watch(ambulanceRequestDocProvider(id)).valueOrNull;
});

// ── Completed trips ──────────────────────────────────────────────────────

final ambulanceTripsProvider = StreamProvider.autoDispose<List<Trip>>((ref) {
  final uid = AmbulanceProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return AmbulanceRequestService.myTripsStream(uid)
      .map((snap) => snap.docs.map(Trip.fromFirestore).toList());
});

final tripHistoryProvider = Provider.autoDispose<List<Trip>>((ref) {
  return ref.watch(ambulanceTripsProvider).valueOrNull ?? const [];
});

// ── Vehicle / driver profile ─────────────────────────────────────────────

final ambulanceProfileDocProvider =
    StreamProvider.autoDispose<VehicleProfile?>((ref) {
  final uid = AmbulanceProfileService.currentUid;
  if (uid == null) return Stream.value(null);
  return AmbulanceProfileService.profileStream(uid)
      .map((snap) => snap.exists ? VehicleProfile.fromFirestore(snap) : null);
});

/// Non-null by design — a partner who hasn't onboarded yet gets
/// [VehicleProfile.empty] rather than a null the Vehicle Profile screen
/// would have to branch on.
final vehicleProfileProvider = Provider.autoDispose<VehicleProfile>((ref) {
  return ref.watch(ambulanceProfileDocProvider).valueOrNull ?? VehicleProfile.empty();
});

// ── Earnings ─────────────────────────────────────────────────────────────

/// Mon..Sun totals for the current week, derived from the real
/// `ambulance_trips` records. (The wallet's authoritative balance comes from
/// the `ambulance_transactions` ledger via `walletSummaryProvider` — this is
/// only the chart's weekly shape.)
final weeklyEarningsProvider = Provider.autoDispose<List<double>>((ref) {
  final trips = ref.watch(tripHistoryProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));

  final buckets = List<double>.filled(7, 0);
  for (final t in trips) {
    final day = DateTime(t.completedAt.year, t.completedAt.month, t.completedAt.day);
    final index = day.difference(weekStart).inDays;
    if (index >= 0 && index < 7) buckets[index] += t.fare.toDouble();
  }
  return buckets;
});

class AmbulanceDashboardMetrics {
  final int todayTrips;
  final num todayEarnings;
  final int pendingCount;
  final double rating;

  const AmbulanceDashboardMetrics({
    required this.todayTrips,
    required this.todayEarnings,
    required this.pendingCount,
    required this.rating,
  });
}

final ambulanceDashboardMetricsProvider =
    Provider.autoDispose<AmbulanceDashboardMetrics>((ref) {
  final trips = ref.watch(tripHistoryProvider);
  final pending = ref.watch(pendingRequestsProvider);
  final vehicle = ref.watch(vehicleProfileProvider);
  final now = DateTime.now();
  final todayTrips = trips
      .where((t) =>
          t.completedAt.year == now.year &&
          t.completedAt.month == now.month &&
          t.completedAt.day == now.day)
      .toList();

  return AmbulanceDashboardMetrics(
    todayTrips: todayTrips.length,
    todayEarnings: todayTrips.fold<num>(0, (s, t) => s + t.fare),
    pendingCount: pending.length,
    rating: vehicle.rating,
  );
});
