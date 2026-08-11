import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'care_note.dart';
import 'care_task.dart';

enum VisitStatus { scheduled, checkedIn, completed, missed, cancelled }

extension VisitStatusX on VisitStatus {
  String get label {
    switch (this) {
      case VisitStatus.scheduled:
        return 'Scheduled';
      case VisitStatus.checkedIn:
        return 'In Progress';
      case VisitStatus.completed:
        return 'Completed';
      case VisitStatus.missed:
        return 'Missed';
      case VisitStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case VisitStatus.scheduled:
        return const Color(0xFF1565C0);
      case VisitStatus.checkedIn:
        return const Color(0xFFEF6C00);
      case VisitStatus.completed:
        return const Color(0xFF2E7D32);
      case VisitStatus.missed:
        return const Color(0xFFC62828);
      case VisitStatus.cancelled:
        return const Color(0xFF757575);
    }
  }
}

/// UI-only care category — drives icon/color coding across the module the
/// same way `EmergencyType` does for the Ambulance module.
enum CareType { elderlyCare, postSurgery, physiotherapy, medicationManagement, generalNursing }

extension CareTypeX on CareType {
  String get label {
    switch (this) {
      case CareType.elderlyCare:
        return 'Elderly Care';
      case CareType.postSurgery:
        return 'Post-Surgery Care';
      case CareType.physiotherapy:
        return 'Physiotherapy';
      case CareType.medicationManagement:
        return 'Medication Management';
      case CareType.generalNursing:
        return 'General Nursing';
    }
  }

  IconData get icon {
    switch (this) {
      case CareType.elderlyCare:
        return Icons.elderly_rounded;
      case CareType.postSurgery:
        return Icons.healing_rounded;
      case CareType.physiotherapy:
        return Icons.accessibility_new_rounded;
      case CareType.medicationManagement:
        return Icons.medication_rounded;
      case CareType.generalNursing:
        return Icons.volunteer_activism_rounded;
    }
  }

  Color get color {
    switch (this) {
      case CareType.elderlyCare:
        return const Color(0xFF00695C);
      case CareType.postSurgery:
        return const Color(0xFFAD1457);
      case CareType.physiotherapy:
        return const Color(0xFF1565C0);
      case CareType.medicationManagement:
        return const Color(0xFFEF6C00);
      case CareType.generalNursing:
        return const Color(0xFF6A1B9A);
    }
  }
}

/// Backed by `caregiver_visits/{visitId}` — a Cloud-Function-maintained
/// mirror of the patient's `service_requests` doc (type `care_assistant` or
/// `caregivers`; see functions/index.js). `tasks` and `notes` live in
/// subcollections of that document and are joined in by
/// `visitByIdProvider`; list views leave them empty since they only need the
/// visit header.
class Visit {
  final String id;
  final CareType type;
  final VisitStatus status;
  final String patientName;
  final int patientAge;
  final String address;
  final DateTime scheduledAt;
  final int durationMinutes;
  final num fare;
  final List<CareTask> tasks;
  final List<CareNote> notes;
  final List<String> photoPaths;

  const Visit({
    required this.id,
    required this.type,
    required this.status,
    required this.patientName,
    required this.patientAge,
    required this.address,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.fare,
    required this.tasks,
    required this.notes,
    required this.photoPaths,
  });

  /// Parses a `caregiver_visits` document. Subcollection-backed [tasks] and
  /// [notes] are passed in by the caller (they arrive on their own streams);
  /// `photoPaths` maps the doc's `photoUrls` array — Storage download URLs
  /// now, not local file paths, which is why `PhotoGrid` renders them with
  /// `Image.network`.
  factory Visit.fromFirestore(
    DocumentSnapshot<Object?> doc, {
    List<CareTask> tasks = const [],
    List<CareNote> notes = const [],
  }) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return Visit(
      id: doc.id,
      type: _careTypeFrom(d['type'] as String?),
      status: _statusFrom(d['status'] as String?),
      patientName: d['patientName'] as String? ?? 'Patient',
      patientAge: ((d['patientAge'] as num?) ?? 0).toInt(),
      address: d['address'] as String? ?? '',
      scheduledAt: (d['scheduledAt'] as Timestamp?)?.toDate() ??
          (d['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      durationMinutes: ((d['durationMinutes'] as num?) ?? 60).toInt(),
      fare: (d['fare'] as num?) ?? 0,
      tasks: tasks,
      notes: notes,
      photoPaths: (d['photoUrls'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  static VisitStatus _statusFrom(String? raw) {
    for (final s in VisitStatus.values) {
      if (s.name == raw) return s;
    }
    return VisitStatus.scheduled;
  }

  static CareType _careTypeFrom(String? raw) {
    for (final t in CareType.values) {
      if (t.name == raw) return t;
    }
    return CareType.generalNursing;
  }

  Visit copyWith({
    VisitStatus? status,
    List<CareTask>? tasks,
    List<CareNote>? notes,
    List<String>? photoPaths,
  }) =>
      Visit(
        id: id,
        type: type,
        status: status ?? this.status,
        patientName: patientName,
        patientAge: patientAge,
        address: address,
        scheduledAt: scheduledAt,
        durationMinutes: durationMinutes,
        fare: fare,
        tasks: tasks ?? this.tasks,
        notes: notes ?? this.notes,
        photoPaths: photoPaths ?? this.photoPaths,
      );

  int get completedTaskCount => tasks.where((t) => t.isDone).length;
  double get taskProgress => tasks.isEmpty ? 0 : completedTaskCount / tasks.length;
  bool get allTasksDone => tasks.isNotEmpty && completedTaskCount == tasks.length;
}
