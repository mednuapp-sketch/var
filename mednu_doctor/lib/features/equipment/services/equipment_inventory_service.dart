import 'package:cloud_firestore/cloud_firestore.dart';

/// CRUD over `equipment_profiles/{vendorId}/items` — the vendor's own menu,
/// private to that vendor (firestore.rules: owner-only read/write). Every
/// write is mirrored by `onEquipmentItemWrite` (functions/index.js) into the
/// patient-facing `services` collection while this vendor is `active`, so
/// edits show up for patients in real time without this service touching
/// that collection itself.
class EquipmentInventoryService {
  EquipmentInventoryService._();

  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _collection(String vendorId) =>
      _db.collection('equipment_profiles').doc(vendorId).collection('items');

  static Stream<QuerySnapshot<Map<String, dynamic>>> stream(String vendorId) {
    return _collection(vendorId).orderBy('name').snapshots();
  }

  /// A fresh id, so the item's photo can be uploaded to a stable path before
  /// the document itself exists.
  static String newItemId(String vendorId) => _collection(vendorId).doc().id;

  /// Creates or fully rewrites one menu item ([itemId] from [newItemId] for a
  /// new one). `merge` keeps fields this form doesn't own (none today, but it
  /// keeps a later field from being clobbered by an older client).
  static Future<void> saveItem(
    String vendorId,
    String itemId, {
    required String name,
    required String category,
    required String description,
    required String imageUrl,
    required bool offersRent,
    required bool offersBuy,
    required num rentPricePerDay,
    required num buyPrice,
    required num deposit,
    required int stock,
    int lowStockThreshold = 2,
    bool isAvailable = true,
  }) {
    return _collection(vendorId).doc(itemId).set({
      'name': name,
      'category': category,
      'description': description,
      'imageUrl': imageUrl,
      'offersRent': offersRent,
      'offersBuy': offersBuy,
      'rentPricePerDay': rentPricePerDay,
      'buyPrice': buyPrice,
      'deposit': deposit,
      'stock': stock,
      'lowStockThreshold': lowStockThreshold,
      'isAvailable': isAvailable,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// The "Available / Sold out" switch.
  static Future<void> setAvailable(String vendorId, String itemId, bool value) {
    return _collection(vendorId).doc(itemId).update({
      'isAvailable': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setStock(String vendorId, String itemId, int stock) {
    return _collection(vendorId).doc(itemId).update({
      'stock': stock < 0 ? 0 : stock,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteItem(String vendorId, String itemId) {
    return _collection(vendorId).doc(itemId).delete();
  }
}
