import 'package:cloud_firestore/cloud_firestore.dart';

class Hospital {
  final String id;
  final String name;
  final String address;
  final String phone;
  final String mapsUrl;
  final bool isEmergency;
  final bool isEnabled;

  /// Google Places `place_id`, set only when this entry was added via the
  /// admin's "Search Google Maps" picker rather than typed freehand. Kept
  /// for hospitals added that way before location capture existed.
  final String? placeId;

  /// Set by `onHospitalProfileApproved` (functions/index.js) once a
  /// hospital billing-desk applicant's registration is approved — the
  /// location they picked on the map picker at registration
  /// (`PartnerRoleRegisterScreen` in mednu_doctor). Null until then, so a
  /// freshly-registered or admin-only-added hospital just shows without a
  /// distance in the patient app rather than a wrong one.
  final double? latitude;
  final double? longitude;

  const Hospital({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.mapsUrl,
    required this.isEmergency,
    required this.isEnabled,
    this.placeId,
    this.latitude,
    this.longitude,
  });

  factory Hospital.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return Hospital(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      address: (d['address'] as String?) ?? '',
      phone: (d['phone'] as String?) ?? '',
      mapsUrl: (d['mapsUrl'] as String?) ?? '',
      isEmergency: (d['isEmergency'] as bool?) ?? false,
      // Default true so hospitals saved before this field was introduced still appear
      isEnabled: (d['isEnabled'] as bool?) ?? true,
      placeId: d['placeId'] as String?,
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
    );
  }
}

class HospitalService {
  static final _db = FirebaseFirestore.instance;

  // Fetch all hospitals and filter client-side so documents without isEnabled
  // (saved before the field existed) are treated as enabled.
  static Stream<List<Hospital>> stream() => _db
      .collection('hospitals')
      .snapshots()
      .map((s) => s.docs
          .map(Hospital.fromFirestore)
          .where((h) => h.isEnabled)
          .toList());

  static Stream<List<Hospital>> emergencyStream() => _db
      .collection('hospitals')
      .snapshots()
      .map((s) => s.docs
          .map(Hospital.fromFirestore)
          .where((h) => h.isEnabled && h.isEmergency)
          .toList());
}
