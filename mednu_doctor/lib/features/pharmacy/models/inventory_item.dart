import 'package:cloud_firestore/cloud_firestore.dart';

/// Lives at `pharmacy_profiles/{uid}/inventory/{itemId}` — a pharmacy's own
/// stock, private to that pharmacy (see firestore.rules). Deliberately a
/// subcollection rather than a new top-level collection: it's owned data
/// with no cross-pharmacy or patient-facing read pattern, unlike
/// `pharmacy_orders`/`pharmacy_transactions`.
class InventoryItem {
  final String id;
  final String name;
  final String brand;
  final num price;
  final int stock;
  final int lowStockThreshold;
  final bool requiresPrescription;

  const InventoryItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.price,
    required this.stock,
    required this.lowStockThreshold,
    required this.requiresPrescription,
  });

  factory InventoryItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return InventoryItem(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      brand: (d['brand'] as String?) ?? '',
      price: (d['price'] as num?) ?? 0,
      stock: (d['stock'] as int?) ?? 0,
      lowStockThreshold: (d['lowStockThreshold'] as int?) ?? 10,
      requiresPrescription: (d['requiresPrescription'] as bool?) ?? false,
    );
  }

  bool get isLowStock => stock <= lowStockThreshold;
  bool get isOutOfStock => stock <= 0;
}
