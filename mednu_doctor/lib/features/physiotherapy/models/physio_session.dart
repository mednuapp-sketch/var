import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum PhysioSessionStatus { pending, accepted, inProgress, completed, cancelled, expired }

extension PhysioSessionStatusX on PhysioSessionStatus {
  String get label {
    switch (this) {
      case PhysioSessionStatus.pending:
        return 'Pending';
      case PhysioSessionStatus.accepted:
        return 'Accepted';
      case PhysioSessionStatus.inProgress:
        return 'In Progress';
      case PhysioSessionStatus.completed:
        return 'Completed';
      case PhysioSessionStatus.cancelled:
        return 'Cancelled';
      case PhysioSessionStatus.expired:
        return 'Expired';
    }
  }

  Color get color {
    switch (this) {
      case PhysioSessionStatus.pending:
        return const Color(0xFF1565C0);
      case PhysioSessionStatus.accepted:
        return const Color(0xFF00838F);
      case PhysioSessionStatus.inProgress:
        return const Color(0xFFEF6C00);
      case PhysioSessionStatus.completed:
        return const Color(0xFF2E7D32);
      case PhysioSessionStatus.cancelled:
        return const Color(0xFFC62828);
      case PhysioSessionStatus.expired:
        return const Color(0xFF757575);
    }
  }
}

/// Backed by `physio_sessions/{sessionId}` — a Cloud-Function-maintained
/// mirror of the patient's `service_requests` doc (type 'physiotherapy'; see
/// functions/index.js). Single-practitioner service, unlike Lab/Pharmacy —
/// there is no separate "assign a staff member" step, so claiming a session
/// sets both `physiotherapistId` and `status` in one write (see
/// PhysioSessionService.claim).
class PhysioSession {
  final String id;
  final PhysioSessionStatus status;
  final String sessionTitle;
  final String patientId;
  final String patientName;
  final String patientPhone;
  final String address;
  final String preferredDate;
  final String preferredTime;
  final String notes;
  final num amount;
  final String? physiotherapistId;
  final DateTime createdAt;

  const PhysioSession({
    required this.id,
    required this.status,
    required this.sessionTitle,
    required this.patientId,
    required this.patientName,
    required this.patientPhone,
    required this.address,
    required this.preferredDate,
    required this.preferredTime,
    required this.notes,
    required this.amount,
    required this.physiotherapistId,
    required this.createdAt,
  });

  factory PhysioSession.fromFirestore(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return PhysioSession(
      id: doc.id,
      status: _statusFrom(d['status'] as String?),
      sessionTitle: d['sessionTitle'] as String? ?? 'Physiotherapy Session',
      patientId: d['patientId'] as String? ?? '',
      patientName: d['patientName'] as String? ?? 'Patient',
      patientPhone: d['patientPhone'] as String? ?? '',
      address: d['address'] as String? ?? '',
      preferredDate: d['preferredDate'] as String? ?? '',
      preferredTime: d['preferredTime'] as String? ?? '',
      notes: d['notes'] as String? ?? '',
      amount: (d['amount'] as num?) ?? 0,
      physiotherapistId: d['physiotherapistId'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// `PhysioSessionService.start` writes `status: 'in_progress'` (snake_case,
  /// matching every other status string this module ever writes/checks —
  /// `complete`'s own precondition reads it back the same way) — but this
  /// used to match against `PhysioSessionStatus.values`' `.name` (Dart's
  /// enum-identifier casing, 'inProgress', camelCase). Those never matched,
  /// so an in-progress session silently fell through to the `pending`
  /// default: the session detail screen showed "Pending" with Accept/Decline
  /// again, and tapping Accept correctly failed against the *real* Firestore
  /// status ('in_progress' — not 'pending') but with the wrong, misleading
  /// "already taken by another physiotherapist" message.
  static PhysioSessionStatus _statusFrom(String? raw) {
    switch (raw) {
      case 'pending':
        return PhysioSessionStatus.pending;
      case 'accepted':
        return PhysioSessionStatus.accepted;
      case 'in_progress':
        return PhysioSessionStatus.inProgress;
      case 'completed':
        return PhysioSessionStatus.completed;
      case 'cancelled':
        return PhysioSessionStatus.cancelled;
      case 'expired':
        return PhysioSessionStatus.expired;
      default:
        return PhysioSessionStatus.pending;
    }
  }
}
