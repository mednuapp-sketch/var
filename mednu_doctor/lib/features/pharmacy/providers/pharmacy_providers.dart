import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/inventory_item.dart';
import '../models/pharmacy_order.dart';
import '../models/pharmacy_order_item.dart';
import '../models/pharmacy_profile.dart';
import '../services/pharmacy_inventory_service.dart';
import '../services/pharmacy_order_service.dart';
import '../services/pharmacy_profile_service.dart';

// ── Profile ──────────────────────────────────────────────────────────────

final pharmacyProfileProvider = StreamProvider.autoDispose<PharmacyProfile?>((ref) {
  final uid = PharmacyProfileService.currentUid;
  if (uid == null) return Stream.value(null);
  return PharmacyProfileService.profileStream(uid)
      .map((snap) => snap.exists ? PharmacyProfile.fromDoc(snap) : null);
});

// ── Available (unclaimed) orders queue ──────────────────────────────────

final availableOrdersProvider = StreamProvider.autoDispose<List<PharmacyOrder>>((ref) {
  return PharmacyOrderService.availableOrdersStream()
      .map((snap) => snap.docs.map(PharmacyOrder.fromDoc).toList());
});

// ── Dashboard metrics — one realtime query, computed client-side ─────────

class PharmacyDashboardMetrics {
  final int todayOrders;
  final int pendingVerification;
  final int packedAwaitingDispatch;
  final int outForDelivery;
  final int deliveredToday;
  final num todayEarnings;

  const PharmacyDashboardMetrics({
    required this.todayOrders,
    required this.pendingVerification,
    required this.packedAwaitingDispatch,
    required this.outForDelivery,
    required this.deliveredToday,
    required this.todayEarnings,
  });

  factory PharmacyDashboardMetrics.empty() => const PharmacyDashboardMetrics(
        todayOrders: 0,
        pendingVerification: 0,
        packedAwaitingDispatch: 0,
        outForDelivery: 0,
        deliveredToday: 0,
        todayEarnings: 0,
      );
}

final pharmacyDashboardMetricsProvider =
    StreamProvider.autoDispose<PharmacyDashboardMetrics>((ref) {
  final uid = PharmacyProfileService.currentUid;
  if (uid == null) return Stream.value(PharmacyDashboardMetrics.empty());

  return PharmacyOrderService.myAllOrdersStream(uid).map((snap) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var todayOrders = 0;
    var pendingVerification = 0;
    var packedAwaitingDispatch = 0;
    var outForDelivery = 0;
    var deliveredToday = 0;
    num todayEarnings = 0;

    for (final doc in snap.docs) {
      final o = PharmacyOrder.fromDoc(doc);
      if (DateFormat('yyyy-MM-dd').format(o.createdAt) == todayStr) todayOrders++;
      if (o.status == PharmacyOrderStatus.prescriptionRequired) pendingVerification++;
      if (o.status == PharmacyOrderStatus.packed) packedAwaitingDispatch++;
      if (o.status == PharmacyOrderStatus.outForDelivery) outForDelivery++;
      if (o.status == PharmacyOrderStatus.delivered) {
        if (DateFormat('yyyy-MM-dd').format(o.updatedAt) == todayStr) {
          deliveredToday++;
          todayEarnings += o.totalAmount;
        }
      }
    }

    return PharmacyDashboardMetrics(
      todayOrders: todayOrders,
      pendingVerification: pendingVerification,
      packedAwaitingDispatch: packedAwaitingDispatch,
      outForDelivery: outForDelivery,
      deliveredToday: deliveredToday,
      todayEarnings: todayEarnings,
    );
  });
});

// ── Prescription verification queue ───────────────────────────────────────

final prescriptionVerificationQueueProvider =
    StreamProvider.autoDispose<List<PharmacyOrder>>((ref) {
  final uid = PharmacyProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return PharmacyOrderService.myAllOrdersStream(uid).map((snap) {
    final queue = snap.docs
        .map(PharmacyOrder.fromDoc)
        .where((o) => o.status == PharmacyOrderStatus.prescriptionRequired)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return queue;
  });
});

// ── Delivery tracking queue ────────────────────────────────────────────────

final deliveryQueueProvider = StreamProvider.autoDispose<List<PharmacyOrder>>((ref) {
  final uid = PharmacyProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return PharmacyOrderService.deliveryQueueStream(uid)
      .map((snap) => snap.docs.map(PharmacyOrder.fromDoc).toList());
});

// ── Single order detail + its line items (realtime) ───────────────────────

final orderDetailProvider =
    StreamProvider.autoDispose.family<PharmacyOrder?, String>((ref, orderId) {
  return PharmacyOrderService.orderStream(orderId)
      .map((snap) => snap.exists ? PharmacyOrder.fromDoc(snap) : null);
});

final orderItemsProvider =
    StreamProvider.autoDispose.family<List<PharmacyOrderItem>, String>((ref, orderId) {
  return PharmacyOrderService.orderItemsStream(orderId).map(
    (items) => items
        .map((m) => PharmacyOrderItem(
              id: m['id'] as String,
              orderId: (m['orderId'] as String?) ?? orderId,
              name: (m['name'] as String?) ?? 'Item',
              brand: (m['brand'] as String?) ?? '',
              price: (m['price'] as num?) ?? 0,
              count: (m['count'] as int?) ?? 1,
              subtotal: (m['subtotal'] as num?) ?? 0,
            ))
        .toList(),
  );
});

// ── Inventory ───────────────────────────────────────────────────────────

final inventoryProvider = StreamProvider.autoDispose<List<InventoryItem>>((ref) {
  final uid = PharmacyProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return PharmacyInventoryService.stream(uid)
      .map((snap) => snap.docs.map(InventoryItem.fromDoc).toList());
});

// ── Paginated "My Orders" list, optionally filtered by status ────────────

class MyOrdersState {
  final List<PharmacyOrder> items;
  final bool isLoadingMore;
  final bool hasMore;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;

  const MyOrdersState({
    required this.items,
    required this.isLoadingMore,
    required this.hasMore,
    required this.lastDoc,
  });

  factory MyOrdersState.initial() =>
      const MyOrdersState(items: [], isLoadingMore: false, hasMore: true, lastDoc: null);

  MyOrdersState copyWith({
    List<PharmacyOrder>? items,
    bool? isLoadingMore,
    bool? hasMore,
    DocumentSnapshot<Map<String, dynamic>>? lastDoc,
  }) =>
      MyOrdersState(
        items: items ?? this.items,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        lastDoc: lastDoc ?? this.lastDoc,
      );
}

/// Realtime first page + one-shot-fetched subsequent pages — same hybrid
/// pattern as the Lab module's `MyBookingsController`.
class MyOrdersController extends StateNotifier<MyOrdersState> {
  final String pharmacyId;
  final String? statusFilter;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  MyOrdersController(this.pharmacyId, this.statusFilter) : super(MyOrdersState.initial()) {
    if (pharmacyId.isNotEmpty) _subscribe();
  }

  void _subscribe() {
    _sub = PharmacyOrderService.myOrdersFirstPageStream(pharmacyId, statusFilter: statusFilter)
        .listen((snap) {
      final items = snap.docs.map(PharmacyOrder.fromDoc).toList();
      state = state.copyWith(
        items: items,
        lastDoc: snap.docs.isNotEmpty ? snap.docs.last : null,
        hasMore: snap.docs.length >= PharmacyOrderService.pageSize,
      );
    });
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.lastDoc == null) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final snap = await PharmacyOrderService.fetchMoreMyOrders(
        pharmacyId,
        startAfter: state.lastDoc!,
        statusFilter: statusFilter,
      );
      // This provider is autoDispose: leaving the screen mid-fetch disposes
      // the notifier, and writing `state` afterwards throws.
      if (!mounted) return;
      final more = snap.docs.map(PharmacyOrder.fromDoc).toList();
      state = state.copyWith(
        items: [...state.items, ...more],
        lastDoc: snap.docs.isNotEmpty ? snap.docs.last : state.lastDoc,
        hasMore: snap.docs.length >= PharmacyOrderService.pageSize,
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

final myOrdersControllerProvider = StateNotifierProvider.autoDispose
    .family<MyOrdersController, MyOrdersState, String?>((ref, statusFilter) {
  final uid = PharmacyProfileService.currentUid ?? '';
  return MyOrdersController(uid, statusFilter);
});
