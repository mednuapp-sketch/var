import 'package:cloud_firestore/cloud_firestore.dart';

/// Backed by `ambulance_profiles/{uid}` — the partner's own vehicle/driver
/// identity document, and the same doc `firestore.rules`' `isAmbulancePartner()`
/// existence-checks to decide who may see the shared dispatch queue.
class VehicleProfile {
  final String plateNumber;
  final String vehicleType; // 'Basic Life Support' | 'Advanced Life Support' | 'ICU on Wheels'
  final String driverName;
  final String driverPhone;
  final String driverLicense;
  final List<String> equipment;
  final bool documentsVerified;
  final double rating;
  final int totalTrips;

  /// Raw `documents` / `documentVerification` maps, keyed by canonical
  /// docType. Kept untyped here so the shared documents layer
  /// (`shared_core/documents`) owns their parsing for every role.
  final Map<String, dynamic> documents;
  final Map<String, dynamic> documentVerification;

  const VehicleProfile({
    required this.plateNumber,
    required this.vehicleType,
    required this.driverName,
    required this.driverPhone,
    required this.driverLicense,
    required this.equipment,
    required this.documentsVerified,
    required this.rating,
    required this.totalTrips,
    this.documents = const {},
    this.documentVerification = const {},
  });

  /// What the Vehicle Profile screen renders before the partner has
  /// completed onboarding (no `ambulance_profiles/{uid}` doc yet). Keeping
  /// this non-null keeps `vehicleProfileProvider`'s type — and therefore
  /// every screen consuming it — unchanged.
  factory VehicleProfile.empty() => const VehicleProfile(
        plateNumber: 'Not set',
        vehicleType: 'Unverified',
        driverName: '',
        driverPhone: '',
        driverLicense: '',
        equipment: [],
        documentsVerified: false,
        rating: 0,
        totalTrips: 0,
      );

  factory VehicleProfile.fromFirestore(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return VehicleProfile(
      plateNumber: d['plateNumber'] as String? ?? 'Not set',
      vehicleType: d['vehicleType'] as String? ?? 'Unverified',
      driverName: d['driverName'] as String? ?? '',
      driverPhone: d['driverPhone'] as String? ?? '',
      driverLicense: d['driverLicense'] as String? ?? '',
      equipment: (d['equipment'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      documentsVerified: d['documentsVerified'] as bool? ?? false,
      rating: ((d['rating'] as num?) ?? 0).toDouble(),
      totalTrips: ((d['totalTrips'] as num?) ?? 0).toInt(),
      documents: Map<String, dynamic>.from(
          (d['documents'] as Map?) ?? const <String, dynamic>{}),
      documentVerification: Map<String, dynamic>.from(
          (d['documentVerification'] as Map?) ?? const <String, dynamic>{}),
    );
  }
}
