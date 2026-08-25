import 'package:cloud_firestore/cloud_firestore.dart';

/// CRUD over `pharmacy_profiles/{pharmacyId}/inventory` — a pharmacy's own
/// stock, private to that pharmacy (see firestore.rules: owner-only
/// read/write on the subcollection). Every write here is mirrored by
/// `onPharmacyInventoryWrite` (functions/index.js) into the patient-facing
/// `medicines_catalogue` collection while this pharmacy is `active`, so
/// items added/edited/removed here show up for patients in real time
/// without this service touching that collection itself.
class PharmacyInventoryService {
  PharmacyInventoryService._();

  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _collection(String pharmacyId) =>
      _db.collection('pharmacy_profiles').doc(pharmacyId).collection('inventory');

  static Stream<QuerySnapshot<Map<String, dynamic>>> stream(String pharmacyId) {
    return _collection(pharmacyId).orderBy('name').snapshots();
  }

  static Future<void> addItem(
    String pharmacyId, {
    required String name,
    required String brand,
    required num price,
    required int stock,
    int lowStockThreshold = 10,
    bool requiresPrescription = false,
  }) {
    return _collection(pharmacyId).add({
      'name': name,
      'brand': brand,
      'price': price,
      'stock': stock,
      'lowStockThreshold': lowStockThreshold,
      'requiresPrescription': requiresPrescription,
    });
  }

  static Future<void> updateStock(String pharmacyId, String itemId, int newStock) {
    return _collection(pharmacyId).doc(itemId).update({'stock': newStock});
  }

  static Future<void> deleteItem(String pharmacyId, String itemId) {
    return _collection(pharmacyId).doc(itemId).delete();
  }
}
