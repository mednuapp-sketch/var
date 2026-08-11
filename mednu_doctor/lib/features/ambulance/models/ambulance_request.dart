import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// UI-only status vocabulary for this module's mock data — intentionally
/// close to (but not wired against) the ambulance status set already used
/// elsewhere in the platform's Cloud Functions (`accepted/assigned/
/// in_progress/arrived/completed/rejected/cancelled`), so a future backend
/// pass can map onto it without a UI rework.
enum AmbulanceRequestStatus { pending, accepted, enRoute, arrived, completed, cancelled }

extension AmbulanceRequestStatusX on AmbulanceRequestStatus {
  String get label {
    switch (this) {
      case AmbulanceRequestStatus.pending:
        return 'New Request';
      case AmbulanceRequestStatus.accepted:
        return 'Accepted';
      case AmbulanceRequestStatus.enRoute:
        return 'En Route';
      case AmbulanceRequestStatus.arrived:
        return 'Arrived';
      case AmbulanceRequestStatus.completed:
        return 'Completed';
      case AmbulanceRequestStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case AmbulanceRequestStatus.pending:
        return const Color(0xFF1565C0);
      case AmbulanceRequestStatus.accepted:
        return const Color(0xFF6A1B9A);
      case AmbulanceRequestStatus.enRoute:
        return const Color(0xFFF9A825);
      case AmbulanceRequestStatus.arrived:
        return const Color(0xFF00897B);
      case AmbulanceRequestStatus.completed:
        return const Color(0xFF2E7D32);
      case AmbulanceRequestStatus.cancelled:
        return const Color(0xFFC62828);
    }
  }
}

enum EmergencyType { cardiac, accident, maternity, general }

extension EmergencyTypeX on EmergencyType {
  String get label {
    switch (this) {
      case EmergencyType.cardiac:
        return 'Cardiac Emergency';
      case EmergencyType.accident:
        return 'Accident / Trauma';
      case EmergencyType.maternity:
        return 'Maternity';
      case EmergencyType.general:
        return 'General Transport';
    }
  }

  IconData get icon {
    switch (this) {
      case EmergencyType.cardiac:
        return Icons.favorite_rounded;
      case EmergencyType.accident:
        return Icons.car_crash_rounded;
      case EmergencyType.maternity:
        return Icons.pregnant_woman_rounded;
      case EmergencyType.general:
        return Icons.local_hospital_rounded;
    }
  }

  Color get color {
    switch (this) {
      case EmergencyType.cardiac:
        return const Color(0xFFD32F2F);
      case EmergencyType.accident:
        return const Color(0xFFE65100);
      case EmergencyType.maternity:
        return const Color(0xFFAD1457);
      case EmergencyType.general:
        return const Color(0xFF1565C0);
    }
  }
}

/// Backed by `ambulance_requests/{requestId}` — a Cloud-Function-maintained
/// mirror of the patient's `service_requests` doc (see functions/index.js,
/// `onAmbulanceServiceRequestCreated`). The client never writes
/// `service_requests` itself.
class AmbulanceRequest {
  final String id;
  final EmergencyType type;
  final AmbulanceRequestStatus status;
  final String patientName;
  final String patientPhone;
  final String pickupAddress;
  final String dropAddress;
  final double distanceKm;
  final int etaMinutes;
  final num fare;
  final DateTime requestedAt;

  const AmbulanceRequest({
    required this.id,
    required this.type,
    required this.status,
    required this.patientName,
    required this.patientPhone,
    required this.pickupAddress,
    required this.dropAddress,
    required this.distanceKm,
    required this.etaMinutes,
    required this.fare,
    required this.requestedAt,
  });

  /// Parses an `ambulance_requests` document. Unknown/missing enum strings
  /// fall back to the safest neutral value rather than throwing — a request
  /// with a slightly wrong badge colour is far better than a dispatch queue
  /// that fails to render because one document was written by an older
  /// version of the mirror.
  factory AmbulanceRequest.fromFirestore(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return AmbulanceRequest(
      id: doc.id,
      type: _emergencyTypeFrom(d['emergencyType'] as String?),
      status: _statusFrom(d['status'] as String?),
      patientName: d['patientName'] as String? ?? 'Patient',
      patientPhone: d['patientPhone'] as String? ?? '',
      pickupAddress: d['pickupAddress'] as String? ?? '',
      dropAddress: d['dropAddress'] as String? ?? '',
      distanceKm: ((d['distanceKm'] as num?) ?? 0).toDouble(),
      etaMinutes: ((d['etaMinutes'] as num?) ?? 0).toInt(),
      fare: (d['fare'] as num?) ?? 0,
      requestedAt: (d['requestedAt'] as Timestamp?)?.toDate() ??
          (d['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
    );
  }

  static AmbulanceRequestStatus _statusFrom(String? raw) {
    for (final s in AmbulanceRequestStatus.values) {
      if (s.name == raw) return s;
    }
    return AmbulanceRequestStatus.pending;
  }

  static EmergencyType _emergencyTypeFrom(String? raw) {
    for (final t in EmergencyType.values) {
      if (t.name == raw) return t;
    }
    return EmergencyType.general;
  }

  AmbulanceRequest copyWith({AmbulanceRequestStatus? status}) => AmbulanceRequest(
        id: id,
        type: type,
        status: status ?? this.status,
        patientName: patientName,
        patientPhone: patientPhone,
        pickupAddress: pickupAddress,
        dropAddress: dropAddress,
        distanceKm: distanceKm,
        etaMinutes: etaMinutes,
        fare: fare,
        requestedAt: requestedAt,
      );
}
