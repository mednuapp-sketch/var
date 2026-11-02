import 'package:cloud_firestore/cloud_firestore.dart';

/// Thrown by [EquipmentOrderService.accept] when the menu no longer has
/// enough units for the order (e.g. another order took the last one first).
class InsufficientStockException implements Exception {
  final int available;
  final int requested;
  const InsufficientStockException({required this.available, required this.requested});

  @override
  String toString() => 'Only $available in stock, order needs $requested.';
}

/// Thrown when an order moved on (cancelled by the patient, already handled)
/// between the vendor opening it and tapping the button.
class OrderNoLongerActionableException implements Exception {
  final String currentStatus;
  const OrderNoLongerActionableException(this.currentStatus);

  @override
  String toString() => 'This order is already "$currentStatus".';
}

/// Vendor-side actions over `equipment_orders`. Orders are created only by a
/// Cloud Function (`onEquipmentServiceRequestCreated`) when a patient books
/// from this vendor's menu; this service only ever advances them, following
/// the transition graph firestore.rules enforces server-side.
///
/// Stock: accepting an order *holds* its units (decrements the menu item and
/// sets `stockHeld`) in one transaction, so two simultaneous orders can never
/// both take the last unit. The Cloud Function `onEquipmentOrderStatusChange`
/// puts the units back when the order is later cancelled / rejected /
/// returned — this service never restores stock itself.
class EquipmentOrderService {
  EquipmentOrderService._();

  static final _db = FirebaseFirestore.instance;

  static const pageLimit = 150;

  static CollectionReference<Map<String, dynamic>> get _orders => _db.collection('equipment_orders');

  /// Realtime feed of this vendor's orders, newest first.
  static Stream<QuerySnapshot<Map<String, dynamic>>> ordersStream(String vendorId) {
    return _orders
        .where('vendorId', isEqualTo: vendorId)
        .orderBy('createdAt', descending: true)
        .limit(pageLimit)
        .snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> orderStream(String orderId) =>
      _orders.doc(orderId).snapshots();

  /// pending -> accepted, holding stock.
  static Future<void> accept(String orderId) {
    return _db.runTransaction((tx) async {
      final orderRef = _orders.doc(orderId);
      final orderSnap = await tx.get(orderRef);
      final order = orderSnap.data();
      if (order == null) throw const OrderNoLongerActionableException('missing');
      if (order['status'] != 'pending') {
        throw OrderNoLongerActionableException(order['status']?.toString() ?? 'unknown');
      }

      final qty = ((order['quantity'] as num?)?.toInt() ?? 1).clamp(1, 1000);
      final itemId = order['itemId'] as String?;
      var holdsStock = false;

      if (itemId != null && itemId.isNotEmpty) {
        final itemRef = _db
            .collection('equipment_profiles')
            .doc(order['vendorId'] as String)
            .collection('items')
            .doc(itemId);
        final itemSnap = await tx.get(itemRef);
        if (itemSnap.exists) {
          final stock = (itemSnap.data()?['stock'] as num?)?.toInt() ?? 0;
          if (stock < qty) {
            throw InsufficientStockException(available: stock, requested: qty);
          }
          tx.update(itemRef, {
            'stock': stock - qty,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          holdsStock = true;
        }
      }

      tx.update(orderRef, {
        'status': 'accepted',
        'stockHeld': holdsStock,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// pending -> rejected. The patient is refunded automatically.
  static Future<void> reject(String orderId, {String reason = ''}) => _orders.doc(orderId).update({
        'status': 'rejected',
        'cancelledBy': 'vendor',
        if (reason.trim().isNotEmpty) 'cancelReason': reason.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// accepted / out_for_delivery -> cancelled. Stock is released and the
  /// patient refunded automatically.
  static Future<void> cancel(String orderId, {String reason = ''}) => _orders.doc(orderId).update({
        'status': 'cancelled',
        'cancelledBy': 'vendor',
        if (reason.trim().isNotEmpty) 'cancelReason': reason.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> markOutForDelivery(String orderId) => _setStatus(orderId, 'out_for_delivery');

  static Future<void> markDelivered(String orderId) => _setStatus(orderId, 'delivered');

  /// Rentals only — the unit is back with the vendor and goes back on the menu.
  static Future<void> markReturned(String orderId) => _setStatus(orderId, 'returned');

  static Future<void> _setStatus(String orderId, String status) => _orders.doc(orderId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
