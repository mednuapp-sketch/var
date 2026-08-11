import 'package:cloud_firestore/cloud_firestore.dart';

/// A single checklist item for a visit (vitals check, medication reminder,
/// mobility assistance, etc.), backed by
/// `caregiver_visits/{visitId}/tasks/{taskId}`. The four defaults are seeded
/// by the Cloud Function when the visit is mirrored; `firestore.rules` lets
/// the assigned caregiver change `isDone` and nothing else, so the wording
/// can never be rewritten after the fact.
class CareTask {
  final String id;
  final String title;
  final String? subtitle;
  final bool isDone;

  const CareTask({
    required this.id,
    required this.title,
    this.subtitle,
    required this.isDone,
  });

  factory CareTask.fromFirestore(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    final subtitle = d['subtitle'] as String?;
    return CareTask(
      id: doc.id,
      title: d['title'] as String? ?? 'Task',
      subtitle: (subtitle == null || subtitle.isEmpty) ? null : subtitle,
      isDone: d['isDone'] as bool? ?? false,
    );
  }

  CareTask copyWith({bool? isDone}) => CareTask(
        id: id,
        title: title,
        subtitle: subtitle,
        isDone: isDone ?? this.isDone,
      );
}
