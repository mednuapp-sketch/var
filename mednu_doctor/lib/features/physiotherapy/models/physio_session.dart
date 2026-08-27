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

  static PhysioSessionStatus _statusFrom(String? raw) {
    for (final s in PhysioSessionStatus.values) {
      if (s.name == raw) return s;
    }
    return PhysioSessionStatus.pending;
  }
}
