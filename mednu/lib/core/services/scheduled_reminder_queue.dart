import 'package:cloud_firestore/cloud_firestore.dart';

/// Thin wrapper around the `scheduled_reminders` collection that the Cloud
/// Function `processDueReminders` polls every 5 minutes and delivers via
/// FCM — the server-driven replacement for local `zonedSchedule()` alarms,
/// which get killed by OEM battery optimization once the app is closed.
///
/// Callers own the doc-ID scheme; it must be deterministic per reminder
/// instance so re-scheduling is a plain overwrite and cancelling is a plain
/// delete-by-ID (mirrors the old local-notification integer-ID convention).
class ScheduledReminderQueue {
  ScheduledReminderQueue._();

  static final _col =
      FirebaseFirestore.instance.collection('scheduled_reminders');

  static Future<void> queue({
    required String docId,
    required String uid,
    required String role, // 'patient' | 'doctor'
    required String title,
    required String body,
    required String channelId,
    required DateTime fireAt,
    Map<String, dynamic> data = const {},
  }) async {
    try {
      await _col.doc(docId).set({
        'uid': uid,
        'role': role,
        'title': title,
        'body': body,
        'channelId': channelId,
        'data': data,
        'fireAt': Timestamp.fromDate(fireAt),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static Future<void> cancel(String docId) async {
    try {
      await _col.doc(docId).delete();
    } catch (_) {}
  }

  static Future<void> cancelMany(Iterable<String> docIds) async {
    if (docIds.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final id in docIds) {
      batch.delete(_col.doc(id));
    }
    try {
      await batch.commit();
    } catch (_) {}
  }
}
