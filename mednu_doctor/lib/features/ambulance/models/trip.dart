import 'package:cloud_firestore/cloud_firestore.dart';
import 'ambulance_request.dart';

/// A completed trip, backed by `ambulance_trips/{requestId}` — written once
/// by the Cloud Function on the request's ->completed edge and immutable
/// afterwards (`firestore.rules`: `allow write: if false`).
class Trip {
  final String id;
  final EmergencyType type;
  final String patientName;
  final String pickupAddress;
  final String dropAddress;
  final double distanceKm;
  final int durationMinutes;
  final num fare;
  final double rating;
  final DateTime completedAt;

  const Trip({
    required this.id,
    required this.type,
    required this.patientName,
    required this.pickupAddress,
    required this.dropAddress,
    required this.distanceKm,
    required this.durationMinutes,
    required this.fare,
    required this.rating,
    required this.completedAt,
  });

  /// `rating` is written as null by the Cloud Function (the patient hasn't
  /// rated the trip yet at completion time) — surfaced here as 0.0, which is
  /// what the history/earnings screens already render as "unrated".
  factory Trip.fromFirestore(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return Trip(
      id: doc.id,
      type: _typeFrom(d['type'] as String?),
      patientName: d['patientName'] as String? ?? 'Patient',
      pickupAddress: d['pickupAddress'] as String? ?? '',
      dropAddress: d['dropAddress'] as String? ?? '',
      distanceKm: ((d['distanceKm'] as num?) ?? 0).toDouble(),
      durationMinutes: ((d['durationMinutes'] as num?) ?? 0).toInt(),
      fare: (d['fare'] as num?) ?? 0,
      rating: ((d['rating'] as num?) ?? 0).toDouble(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  static EmergencyType _typeFrom(String? raw) {
    for (final t in EmergencyType.values) {
      if (t.name == raw) return t;
    }
    return EmergencyType.general;
  }
}
