import 'package:cloud_firestore/cloud_firestore.dart';

/// CRUD over `lab_profiles/{labId}/tests` — a lab's own test catalogue,
/// private to that lab (see firestore.rules: owner-only read/write on the
/// subcollection). Every write here is mirrored by `onLabTestInventoryWrite`
/// (functions/index.js) into the patient-facing `lab_tests_catalogue`
/// collection while this lab is `active`, so tests added/edited/removed here
/// show up for patients in real time without this service touching that
/// collection itself.
class LabTestInventoryService {
  LabTestInventoryService._();

  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _collection(String labId) =>
      _db.collection('lab_profiles').doc(labId).collection('tests');

  static Stream<QuerySnapshot<Map<String, dynamic>>> stream(String labId) {
    return _collection(labId).orderBy('name').snapshots();
  }

  static Future<void> addTest(
    String labId, {
    required String name,
    required String category,
    required num price,
    required String duration,
    bool homeCollectionAvailable = false,
  }) {
    return _collection(labId).add({
      'name': name,
      'category': category,
      'price': price,
      'duration': duration,
      'homeCollectionAvailable': homeCollectionAvailable,
      'isAvailable': true,
    });
  }

  static Future<void> setAvailable(String labId, String testId, bool isAvailable) {
    return _collection(labId).doc(testId).update({'isAvailable': isAvailable});
  }

  static Future<void> deleteTest(String labId, String testId) {
    return _collection(labId).doc(testId).delete();
  }
}
