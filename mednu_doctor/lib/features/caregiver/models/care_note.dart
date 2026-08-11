import 'package:cloud_firestore/cloud_firestore.dart';

/// A free-text care note attached to a visit, backed by
/// `caregiver_visits/{visitId}/notes/{noteId}`. Append-only: a care note is
/// a clinical record, so `firestore.rules` denies clients any update/delete
/// once it's written.
class CareNote {
  final String id;
  final String text;
  final DateTime createdAt;

  const CareNote({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  factory CareNote.fromFirestore(DocumentSnapshot<Object?> doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    return CareNote(
      id: doc.id,
      text: d['text'] as String? ?? '',
      // A note written locally moments ago has no server timestamp resolved
      // yet — falling back to "now" keeps it ordered last (i.e. newest)
      // rather than jumping to the top of the list until the write lands.
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
