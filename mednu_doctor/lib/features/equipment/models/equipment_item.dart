import 'package:cloud_firestore/cloud_firestore.dart';

/// Where an item stands on the vendor's menu, as patients will see it.
enum EquipmentAvailability { available, lowStock, soldOut }

/// One dish on the vendor's menu, at `equipment_profiles/{uid}/items/{id}`.
///
/// Private to the vendor — a Cloud Function (`onEquipmentItemWrite`) mirrors
/// each item into the patient-facing `services` collection while the vendor
/// is approved, so every edit here (price, stock, Available / Sold out) shows
/// up for patients in real time without this app touching `services` itself.
class EquipmentItem {
  final String id;
  final String name;
  final String category;
  final String description;
  final String imageUrl;
  final bool offersRent;
  final bool offersBuy;
  final num rentPricePerDay;
  final num buyPrice;
  final num deposit;
  final int stock;
  final int lowStockThreshold;

  /// The vendor's manual "available / sold out" switch. A unit count of zero
  /// also reads as sold out, regardless of this flag.
  final bool isAvailable;

  const EquipmentItem({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.imageUrl,
    required this.offersRent,
    required this.offersBuy,
    required this.rentPricePerDay,
    required this.buyPrice,
    required this.deposit,
    required this.stock,
    required this.lowStockThreshold,
    required this.isAvailable,
  });

  factory EquipmentItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return EquipmentItem(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      category: (d['category'] as String?) ?? '',
      description: (d['description'] as String?) ?? '',
      imageUrl: (d['imageUrl'] as String?) ?? '',
      offersRent: (d['offersRent'] as bool?) ?? true,
      offersBuy: (d['offersBuy'] as bool?) ?? false,
      rentPricePerDay: (d['rentPricePerDay'] as num?) ?? 0,
      buyPrice: (d['buyPrice'] as num?) ?? 0,
      deposit: (d['deposit'] as num?) ?? 0,
      stock: (d['stock'] as num?)?.toInt() ?? 0,
      lowStockThreshold: (d['lowStockThreshold'] as num?)?.toInt() ?? 2,
      isAvailable: (d['isAvailable'] as bool?) ?? true,
    );
  }

  bool get isOutOfStock => stock <= 0;

  EquipmentAvailability get availability {
    if (!isAvailable || isOutOfStock) return EquipmentAvailability.soldOut;
    if (stock <= lowStockThreshold) return EquipmentAvailability.lowStock;
    return EquipmentAvailability.available;
  }
}
