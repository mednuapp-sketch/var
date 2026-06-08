import 'package:cloud_firestore/cloud_firestore.dart';

class AmbulanceEntry {
  final String id;
  final String name;
  final String phone;
  final String type;
  final String serviceArea;
  final bool isAvailable;

  const AmbulanceEntry({
    required this.id,
    required this.name,
    required this.phone,
    required this.type,
    required this.serviceArea,
    required this.isAvailable,
  });

  factory AmbulanceEntry.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return AmbulanceEntry(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      type: (d['type'] as String?) ?? 'Basic',
      serviceArea: (d['serviceArea'] as String?) ?? '',
      isAvailable: (d['isAvailable'] as bool?) ?? true,
    );
  }
}

class AmbulanceDataService {
  static final _db = FirebaseFirestore.instance;

  static Stream<List<AmbulanceEntry>> stream() => _db
      .collection('ambulances')
      .where('isAvailable', isEqualTo: true)
      .snapshots()
      .map((s) => s.docs.map(AmbulanceEntry.fromFirestore).toList());
}
