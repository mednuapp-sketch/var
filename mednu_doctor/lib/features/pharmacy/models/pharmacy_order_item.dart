import 'package:cloud_firestore/cloud_firestore.dart';

class PharmacyOrderItem {
  final String id;
  final String orderId;
  /// The `medicines_catalogue` doc id this item was ordered from
  /// (`phinv_{pharmacyId}_{itemId}` for pharmacy-sourced medicines, null for
  /// admin-added catalogue medicines with no owning inventory doc).
  final String? medicineId;
  final String name;
  final String brand;
  final num price;
  final int count;
  final num subtotal;

  const PharmacyOrderItem({
    required this.id,
    required this.orderId,
    this.medicineId,
    required this.name,
    required this.brand,
    required this.price,
    required this.count,
    required this.subtotal,
  });

  factory PharmacyOrderItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return PharmacyOrderItem(
      id: doc.id,
      orderId: (d['orderId'] as String?) ?? '',
      medicineId: d['medicineId'] as String?,
      name: (d['name'] as String?) ?? 'Item',
      brand: (d['brand'] as String?) ?? '',
      price: (d['price'] as num?) ?? 0,
      count: (d['count'] as int?) ?? 1,
      subtotal: (d['subtotal'] as num?) ?? 0,
    );
  }
}
