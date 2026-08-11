import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Mirrors the exact status vocabulary the Lab Partner module operates on.
/// A Cloud Function (see `functions/index.js`,
/// `onDiagnosticBookingStatusChange`) translates these onto the
/// patient-facing `service_requests` status vocabulary — this enum never
/// needs to know about that mapping.
enum DiagnosticBookingStatus {
  pending,
  accepted,
  rejected,
  technicianAssigned,
  sampleCollected,
  processing,
  reportUploaded,
  completed,
  cancelled,
  /// Set by the hourly `cleanupStaleDiagnosticBookings` Cloud Function when
  /// a booking sits `pending` (unclaimed) for more than 24h. Terminal, like
  /// `cancelled`/`rejected` — never set by a client.
  expired,
  unknown,
}

extension DiagnosticBookingStatusX on DiagnosticBookingStatus {
  String get firestoreValue {
    switch (this) {
      case DiagnosticBookingStatus.pending:
        return 'pending';
      case DiagnosticBookingStatus.accepted:
        return 'accepted';
      case DiagnosticBookingStatus.rejected:
        return 'rejected';
      case DiagnosticBookingStatus.technicianAssigned:
        return 'technician_assigned';
      case DiagnosticBookingStatus.sampleCollected:
        return 'sample_collected';
      case DiagnosticBookingStatus.processing:
        return 'processing';
      case DiagnosticBookingStatus.reportUploaded:
        return 'report_uploaded';
      case DiagnosticBookingStatus.completed:
        return 'completed';
      case DiagnosticBookingStatus.cancelled:
        return 'cancelled';
      case DiagnosticBookingStatus.expired:
        return 'expired';
      case DiagnosticBookingStatus.unknown:
        return 'unknown';
    }
  }

  String get label {
    switch (this) {
      case DiagnosticBookingStatus.pending:
        return 'New Request';
      case DiagnosticBookingStatus.accepted:
        return 'Accepted';
      case DiagnosticBookingStatus.rejected:
        return 'Rejected';
      case DiagnosticBookingStatus.technicianAssigned:
        return 'Technician Assigned';
      case DiagnosticBookingStatus.sampleCollected:
        return 'Sample Collected';
      case DiagnosticBookingStatus.processing:
        return 'Processing';
      case DiagnosticBookingStatus.reportUploaded:
        return 'Report Uploaded';
      case DiagnosticBookingStatus.completed:
        return 'Completed';
      case DiagnosticBookingStatus.cancelled:
        return 'Cancelled';
      case DiagnosticBookingStatus.expired:
        return 'Expired';
      case DiagnosticBookingStatus.unknown:
        return 'Unknown';
    }
  }

  Color get color {
    switch (this) {
      case DiagnosticBookingStatus.pending:
        return const Color(0xFF1565C0);
      case DiagnosticBookingStatus.accepted:
        return const Color(0xFF00897B);
      case DiagnosticBookingStatus.rejected:
      case DiagnosticBookingStatus.cancelled:
      case DiagnosticBookingStatus.expired:
        return const Color(0xFFC62828);
      case DiagnosticBookingStatus.technicianAssigned:
        return const Color(0xFF6A1B9A);
      case DiagnosticBookingStatus.sampleCollected:
        return const Color(0xFFEF6C00);
      case DiagnosticBookingStatus.processing:
        return const Color(0xFFF9A825);
      case DiagnosticBookingStatus.reportUploaded:
      case DiagnosticBookingStatus.completed:
        return const Color(0xFF2E7D32);
      case DiagnosticBookingStatus.unknown:
        return const Color(0xFF757575);
    }
  }

  static DiagnosticBookingStatus fromFirestoreValue(String? raw) {
    switch (raw) {
      case 'pending':
        return DiagnosticBookingStatus.pending;
      case 'accepted':
        return DiagnosticBookingStatus.accepted;
      case 'rejected':
        return DiagnosticBookingStatus.rejected;
      case 'technician_assigned':
        return DiagnosticBookingStatus.technicianAssigned;
      case 'sample_collected':
        return DiagnosticBookingStatus.sampleCollected;
      case 'processing':
        return DiagnosticBookingStatus.processing;
      case 'report_uploaded':
        return DiagnosticBookingStatus.reportUploaded;
      case 'completed':
        return DiagnosticBookingStatus.completed;
      case 'cancelled':
        return DiagnosticBookingStatus.cancelled;
      case 'expired':
        return DiagnosticBookingStatus.expired;
      default:
        return DiagnosticBookingStatus.unknown;
    }
  }
}

class DiagnosticBooking {
  final String id;
  final String? sourceRequestId;
  final String type; // 'diagnostics' | 'lab_tests'
  final String testName;
  final num price;
  final num amount;
  final String patientId;
  final String patientName;
  final String patientPhone;
  final String address;
  final String preferredDate;
  final String preferredTime;
  final String notes;
  final String? labId;
  final DiagnosticBookingStatus status;
  final String? technicianId;
  final String? technicianName;
  final DateTime? collectionTime;
  final String? reportUrl;
  final DateTime? reportUploadedAt;
  final int reportVersion;
  final String? latestReportId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DiagnosticBooking({
    required this.id,
    required this.sourceRequestId,
    required this.type,
    required this.testName,
    required this.price,
    required this.amount,
    required this.patientId,
    required this.patientName,
    required this.patientPhone,
    required this.address,
    required this.preferredDate,
    required this.preferredTime,
    required this.notes,
    required this.labId,
    required this.status,
    required this.technicianId,
    required this.technicianName,
    required this.collectionTime,
    required this.reportUrl,
    required this.reportUploadedAt,
    required this.reportVersion,
    required this.latestReportId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DiagnosticBooking.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return DiagnosticBooking(
      id: doc.id,
      sourceRequestId: d['sourceRequestId'] as String?,
      type: (d['type'] as String?) ?? 'diagnostics',
      testName: (d['testName'] as String?) ?? 'Diagnostic Test',
      price: (d['price'] as num?) ?? 0,
      amount: (d['amount'] as num?) ?? (d['price'] as num?) ?? 0,
      patientId: (d['patientId'] as String?) ?? '',
      patientName: (d['patientName'] as String?) ?? 'Patient',
      patientPhone: (d['patientPhone'] as String?) ?? '',
      address: (d['address'] as String?) ?? '',
      preferredDate: (d['preferredDate'] as String?) ?? '',
      preferredTime: (d['preferredTime'] as String?) ?? '',
      notes: (d['notes'] as String?) ?? '',
      labId: d['labId'] as String?,
      status: DiagnosticBookingStatusX.fromFirestoreValue(d['status'] as String?),
      technicianId: d['technicianId'] as String?,
      technicianName: d['technicianName'] as String?,
      collectionTime: (d['collectionTime'] as Timestamp?)?.toDate(),
      reportUrl: d['reportUrl'] as String?,
      reportUploadedAt: (d['reportUploadedAt'] as Timestamp?)?.toDate(),
      reportVersion: ((d['reportVersion'] as num?) ?? 0).toInt(),
      latestReportId: d['latestReportId'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  bool get isUnclaimed => labId == null;
}
