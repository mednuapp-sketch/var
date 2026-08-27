import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum CounsellingSessionStatus { pending, accepted, inProgress, completed, cancelled, expired }

extension CounsellingSessionStatusX on CounsellingSessionStatus {
  String get label {
    switch (this) {
      case CounsellingSessionStatus.pending:
        return 'Pending';
      case CounsellingSessionStatus.accepted:
        return 'Accepted';
      case CounsellingSessionStatus.inProgress:
        return 'In Progress';
      case CounsellingSessionStatus.completed:
        return 'Completed';
      case CounsellingSessionStatus.cancelled:
        return 'Cancelled';
      case CounsellingSessionStatus.expired:
        return 'Expired';
    }
  }

  Color get color {
    switch (this) {
      case CounsellingSessionStatus.pending:
        return const Color(0xFF1565C0);
      case CounsellingSessionStatus.accepted:
        return const Color(0xFF5E35B1);
      case CounsellingSessionStatus.inProgress:
        return const Color(0xFFEF6C00);
      case CounsellingSessionStatus.completed:
        return const Color(0xFF2E7D32);
      case CounsellingSessionStatus.cancelled:
        return const Color(0xFFC62828);
      case CounsellingSessionStatus.expired:
        return const Color(0xFF757575);
    }
  }
}

/// Backed by `counselling_sessions/{sessionId}` — a Cloud-Function-maintained
/// mirror of the patient's `service_requests` doc (type 'counselling'; see
/// functions/index.js). Single-practitioner service: claiming a session sets
/// both `counsellorId` and `status` in one write (see
/// CounsellingSessionService.claim).
class CounsellingSession {
  final String id;
  final CounsellingSessionStatus status;
  final String sessionTitle;
  final String patientName;
  final String patientPhone;
  final String address;
  final String preferredDate;
  final String preferredTime;
  final String notes;
  final num amount;
  final String? counsellorId;
  final DateTime createdAt;

  const CounsellingSession({
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
    required this.counsellorId,
    required this.createdAt,
  });

  factory CounsellingSession.fromFirestore(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return CounsellingSession(
      id: doc.id,
      status: _statusFrom(d['status'] as String?),
      sessionTitle: d['sessionTitle'] as String? ?? 'Counselling Session',
      patientName: d['patientName'] as String? ?? 'Patient',
      patientPhone: d['patientPhone'] as String? ?? '',
      address: d['address'] as String? ?? '',
      preferredDate: d['preferredDate'] as String? ?? '',
      preferredTime: d['preferredTime'] as String? ?? '',
      notes: d['notes'] as String? ?? '',
      amount: (d['amount'] as num?) ?? 0,
      counsellorId: d['counsellorId'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  static CounsellingSessionStatus _statusFrom(String? raw) {
    for (final s in CounsellingSessionStatus.values) {
      if (s.name == raw) return s;
    }
    return CounsellingSessionStatus.pending;
  }
}
