import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/diagnostic_booking.dart';
import '../models/diagnostic_report.dart';
import '../models/lab_profile.dart';
import '../models/lab_test_item.dart';
import '../services/lab_booking_service.dart';
import '../services/lab_profile_service.dart';
import '../services/lab_test_inventory_service.dart';

// ── Profile ──────────────────────────────────────────────────────────────

final labProfileProvider = StreamProvider.autoDispose<LabProfile?>((ref) {
  final uid = LabProfileService.currentUid;
  if (uid == null) return Stream.value(null);
  return LabProfileService.profileStream(uid)
      .map((snap) => snap.exists ? LabProfile.fromDoc(snap) : null);
});

// ── Available (unclaimed) bookings queue ────────────────────────────────

final availableBookingsProvider =
    StreamProvider.autoDispose<List<DiagnosticBooking>>((ref) {
  return LabBookingService.availableBookingsStream()
      .map((snap) => snap.docs.map(DiagnosticBooking.fromDoc).toList());
});

// ── Dashboard metrics — one realtime query, computed client-side ─────────

class LabDashboardMetrics {
  final int todayBookings;
  final int pendingCollections;
  final int processingReports;
  final int completedReports;
  final num todayEarnings;

  const LabDashboardMetrics({
    required this.todayBookings,
    required this.pendingCollections,
    required this.processingReports,
    required this.completedReports,
    required this.todayEarnings,
  });

  factory LabDashboardMetrics.empty() => const LabDashboardMetrics(
        todayBookings: 0,
        pendingCollections: 0,
        processingReports: 0,
        completedReports: 0,
        todayEarnings: 0,
      );
}

final labDashboardMetricsProvider =
    StreamProvider.autoDispose<LabDashboardMetrics>((ref) {
  final uid = LabProfileService.currentUid;
  if (uid == null) return Stream.value(LabDashboardMetrics.empty());

  return LabBookingService.myAllBookingsStream(uid).map((snap) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var todayBookings = 0;
    var pendingCollections = 0;
    var processingReports = 0;
    var completedReports = 0;
    num todayEarnings = 0;

    for (final doc in snap.docs) {
      final b = DiagnosticBooking.fromDoc(doc);
      if (DateFormat('yyyy-MM-dd').format(b.createdAt) == todayStr) {
        todayBookings++;
      }
      if (b.status == DiagnosticBookingStatus.accepted ||
          b.status == DiagnosticBookingStatus.technicianAssigned) {
        pendingCollections++;
      }
      if (b.status == DiagnosticBookingStatus.sampleCollected ||
          b.status == DiagnosticBookingStatus.processing) {
        processingReports++;
      }
      if (b.status == DiagnosticBookingStatus.completed) {
        completedReports++;
        if (DateFormat('yyyy-MM-dd').format(b.updatedAt) == todayStr) {
          todayEarnings += b.amount;
        }
      }
    }

    return LabDashboardMetrics(
      todayBookings: todayBookings,
      pendingCollections: pendingCollections,
      processingReports: processingReports,
      completedReports: completedReports,
      todayEarnings: todayEarnings,
    );
  });
});

// ── Sample collection queue (accepted, awaiting/with a technician) ───────

final sampleCollectionQueueProvider =
    StreamProvider.autoDispose<List<DiagnosticBooking>>((ref) {
  final uid = LabProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return LabBookingService.myAllBookingsStream(uid).map((snap) {
    final all = snap.docs.map(DiagnosticBooking.fromDoc).toList();
    final queue = all
        .where((b) =>
            b.status == DiagnosticBookingStatus.accepted ||
            b.status == DiagnosticBookingStatus.technicianAssigned)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return queue;
  });
});

// ── Test catalogue ──────────────────────────────────────────────────────

final labTestInventoryProvider = StreamProvider.autoDispose<List<LabTestItem>>((ref) {
  final uid = LabProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return LabTestInventoryService.stream(uid)
      .map((snap) => snap.docs.map(LabTestItem.fromDoc).toList());
});

// ── Reports history ────────────────────────────────────────────────────

final labReportsProvider = StreamProvider.autoDispose<List<DiagnosticReport>>((ref) {
  final uid = LabProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return LabBookingService.reportsStream(uid)
      .map((snap) => snap.docs.map(DiagnosticReport.fromDoc).toList());
});

// ── Single booking detail (realtime) ──────────────────────────────────────

final bookingDetailProvider =
    StreamProvider.autoDispose.family<DiagnosticBooking?, String>((ref, bookingId) {
  return LabBookingService.bookingStream(bookingId)
      .map((snap) => snap.exists ? DiagnosticBooking.fromDoc(snap) : null);
});

// ── Paginated "My Bookings" list, optionally filtered by status ──────────

class MyBookingsState {
  final List<DiagnosticBooking> items;
  final bool isLoadingMore;
  final bool hasMore;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;

  const MyBookingsState({
    required this.items,
    required this.isLoadingMore,
    required this.hasMore,
    required this.lastDoc,
  });

  factory MyBookingsState.initial() =>
      const MyBookingsState(items: [], isLoadingMore: false, hasMore: true, lastDoc: null);

  MyBookingsState copyWith({
    List<DiagnosticBooking>? items,
    bool? isLoadingMore,
    bool? hasMore,
    DocumentSnapshot<Map<String, dynamic>>? lastDoc,
  }) =>
      MyBookingsState(
        items: items ?? this.items,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        lastDoc: lastDoc ?? this.lastDoc,
      );
}

/// Realtime first page + one-shot-fetched subsequent pages. Keeping the
/// first page live means new/updated bookings always show up instantly
/// without the user needing to pull-to-refresh; paging further back doesn't
/// need to be realtime since older, settled bookings rarely change.
class MyBookingsController extends StateNotifier<MyBookingsState> {
  final String labId;
  final String? statusFilter;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  MyBookingsController(this.labId, this.statusFilter) : super(MyBookingsState.initial()) {
    if (labId.isNotEmpty) _subscribe();
  }

  void _subscribe() {
    _sub = LabBookingService.myBookingsFirstPageStream(labId, statusFilter: statusFilter)
        .listen((snap) {
      final items = snap.docs.map(DiagnosticBooking.fromDoc).toList();
      state = state.copyWith(
        items: items,
        lastDoc: snap.docs.isNotEmpty ? snap.docs.last : null,
        hasMore: snap.docs.length >= LabBookingService.pageSize,
      );
    });
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.lastDoc == null) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final snap = await LabBookingService.fetchMoreMyBookings(
        labId,
        startAfter: state.lastDoc!,
        statusFilter: statusFilter,
      );
      // This provider is autoDispose: leaving the screen mid-fetch disposes
      // the notifier, and writing `state` afterwards throws.
      if (!mounted) return;
      final more = snap.docs.map(DiagnosticBooking.fromDoc).toList();
      state = state.copyWith(
        items: [...state.items, ...more],
        lastDoc: snap.docs.isNotEmpty ? snap.docs.last : state.lastDoc,
        hasMore: snap.docs.length >= LabBookingService.pageSize,
        isLoadingMore: false,
      );
    } catch (_) {
      // Clear the in-flight flag so the user can retry — otherwise a single
      // network failure wedges "load more" permanently.
      if (mounted) state = state.copyWith(isLoadingMore: false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final myBookingsControllerProvider = StateNotifierProvider.autoDispose
    .family<MyBookingsController, MyBookingsState, String?>((ref, statusFilter) {
  final uid = LabProfileService.currentUid ?? '';
  return MyBookingsController(uid, statusFilter);
});
