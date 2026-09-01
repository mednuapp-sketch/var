import 'package:cloud_firestore/cloud_firestore.dart';

/// Lives at `lab_profiles/{uid}/tests/{testId}` — a lab's own test catalogue,
/// private to that lab (see firestore.rules). Deliberately a subcollection
/// rather than a new top-level collection, mirroring
/// `pharmacy_profiles/{uid}/inventory`: it's owned data with no cross-lab or
/// direct patient-facing read pattern. A Cloud Function mirrors each test's
/// public fields into `lab_tests_catalogue` (see `onLabTestInventoryWrite`),
/// so patients still see it — just never by reading this subcollection
/// itself.
class LabTestItem {
  final String id;
  final String name;
  final String category;
  final num price;
  final String duration;
  final bool homeCollectionAvailable;
  final bool isAvailable;

  const LabTestItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.duration,
    required this.homeCollectionAvailable,
    required this.isAvailable,
  });

  factory LabTestItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return LabTestItem(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      category: (d['category'] as String?) ?? '',
      price: (d['price'] as num?) ?? 0,
      duration: (d['duration'] as String?) ?? '',
      homeCollectionAvailable: (d['homeCollectionAvailable'] as bool?) ?? false,
      isAvailable: (d['isAvailable'] as bool?) ?? true,
    );
  }
}
