import 'package:cloud_firestore/cloud_firestore.dart';

class DiagnosticReport {
  final String id;
  final String bookingId;
  final String patientId;
  final String patientName;
  final String labId;
  final String testName;
  final String fileUrl;
  final String fileName;
  final String fileType; // 'pdf' | 'image'
  final int version;
  final DateTime uploadedAt;

  const DiagnosticReport({
    required this.id,
    required this.bookingId,
    required this.patientId,
    required this.patientName,
    required this.labId,
    required this.testName,
    required this.fileUrl,
    required this.fileName,
    required this.fileType,
    required this.version,
    required this.uploadedAt,
  });

  factory DiagnosticReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return DiagnosticReport(
      id: doc.id,
      bookingId: (d['bookingId'] as String?) ?? '',
      patientId: (d['patientId'] as String?) ?? '',
      patientName: (d['patientName'] as String?) ?? 'Patient',
      labId: (d['labId'] as String?) ?? '',
      testName: (d['testName'] as String?) ?? 'Diagnostic Test',
      fileUrl: (d['fileUrl'] as String?) ?? '',
      fileName: (d['fileName'] as String?) ?? 'report',
      fileType: (d['fileType'] as String?) ?? 'pdf',
      version: ((d['version'] as num?) ?? 1).toInt(),
      uploadedAt: (d['uploadedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
