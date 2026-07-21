import 'package:cloud_firestore/cloud_firestore.dart';

class AmbulanceEntry {
  final String id;
  final String name;
  final String phone;
  final String type;
  final String serviceArea;
  final double latitude;
  final double longitude;
  final bool isAvailable;
  final bool isEnabled;

  const AmbulanceEntry({
    required this.id,
    required this.name,
    required this.phone,
    required this.type,
    required this.serviceArea,
    required this.latitude,
    required this.longitude,
    required this.isAvailable,
    required this.isEnabled,
  });

  bool get hasLocation => latitude != 0 || longitude != 0;

  factory AmbulanceEntry.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return AmbulanceEntry(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      type: (d['type'] as String?) ?? 'Basic',
      serviceArea: (d['serviceArea'] as String?) ?? '',
      latitude: (d['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (d['longitude'] as num?)?.toDouble() ?? 0,
      isAvailable: (d['isAvailable'] as bool?) ?? true,
      // Default true so ambulances saved before this field existed still appear
      isEnabled: (d['isEnabled'] as bool?) ?? true,
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

  // Fetch all ambulances and filter client-side so admin-visible/available
  // status is always respected, including docs saved before those fields existed.
  static Stream<List<AmbulanceEntry>> availableStream() => _db
      .collection('ambulances')
      .snapshots()
      .map((s) => s.docs
          .map(AmbulanceEntry.fromFirestore)
          .where((a) => a.isEnabled && a.isAvailable)
          .toList());
}
