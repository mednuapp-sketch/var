import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/equipment_item.dart';
import '../models/equipment_order.dart';
import '../models/equipment_profile.dart';
import '../services/equipment_inventory_service.dart';
import '../services/equipment_order_service.dart';
import '../services/equipment_profile_service.dart';

// ── Profile ──────────────────────────────────────────────────────────────

final equipmentProfileProvider = StreamProvider.autoDispose<EquipmentProfile?>((ref) {
  final uid = EquipmentProfileService.currentUid;
  if (uid == null) return Stream.value(null);
  return EquipmentProfileService.profileStream(uid)
      .map((snap) => snap.exists ? EquipmentProfile.fromDoc(snap) : null);
});

// ── Menu ─────────────────────────────────────────────────────────────────

final equipmentItemsProvider = StreamProvider.autoDispose<List<EquipmentItem>>((ref) {
  final uid = EquipmentProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return EquipmentInventoryService.stream(uid)
      .map((snap) => snap.docs.map(EquipmentItem.fromDoc).toList());
});

// ── Orders ───────────────────────────────────────────────────────────────

/// Every order for this vendor, newest first. One realtime query; the
/// dashboard, the orders tabs and the badge counts are all derived from it.
final equipmentOrdersProvider = StreamProvider.autoDispose<List<EquipmentOrder>>((ref) {
  final uid = EquipmentProfileService.currentUid;
  if (uid == null) return Stream.value(const []);
  return EquipmentOrderService.ordersStream(uid)
      .map((snap) => snap.docs.map(EquipmentOrder.fromDoc).toList());
});

final equipmentOrderDetailProvider =
    StreamProvider.autoDispose.family<EquipmentOrder?, String>((ref, orderId) {
  return EquipmentOrderService.orderStream(orderId)
      .map((snap) => snap.exists ? EquipmentOrder.fromDoc(snap) : null);
});

// ── Dashboard metrics ────────────────────────────────────────────────────

class EquipmentDashboardMetrics {
  final int newOrders;
  final int toDeliver;
  final int activeRentals;
  final int soldOutItems;
  final num todayEarnings;

  const EquipmentDashboardMetrics({
    required this.newOrders,
    required this.toDeliver,
    required this.activeRentals,
    required this.soldOutItems,
    required this.todayEarnings,
  });

  static const empty = EquipmentDashboardMetrics(
    newOrders: 0,
    toDeliver: 0,
    activeRentals: 0,
    soldOutItems: 0,
    todayEarnings: 0,
  );
}

final equipmentDashboardMetricsProvider = Provider.autoDispose<AsyncValue<EquipmentDashboardMetrics>>((ref) {
  final orders = ref.watch(equipmentOrdersProvider);
  final items = ref.watch(equipmentItemsProvider);

  return orders.whenData((list) {
    final now = DateTime.now();
    bool isToday(DateTime d) => d.year == now.year && d.month == now.month && d.day == now.day;

    var newOrders = 0;
    var toDeliver = 0;
    var activeRentals = 0;
    num todayEarnings = 0;
    for (final o in list) {
      switch (o.status) {
        case EquipmentOrderStatus.pending:
          newOrders++;
        case EquipmentOrderStatus.accepted:
        case EquipmentOrderStatus.outForDelivery:
          toDeliver++;
        case EquipmentOrderStatus.delivered:
          if (o.isRent) activeRentals++;
          if (isToday(o.updatedAt)) todayEarnings += o.totalAmount;
        case EquipmentOrderStatus.returned:
        case EquipmentOrderStatus.rejected:
        case EquipmentOrderStatus.cancelled:
          break;
      }
    }

    final soldOut = items.valueOrNull
            ?.where((i) => i.availability == EquipmentAvailability.soldOut)
            .length ??
        0;

    return EquipmentDashboardMetrics(
      newOrders: newOrders,
      toDeliver: toDeliver,
      activeRentals: activeRentals,
      soldOutItems: soldOut,
      todayEarnings: todayEarnings,
    );
  });
});
