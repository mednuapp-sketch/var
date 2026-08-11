import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

class PatientNotificationService {
  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _items(String uid) =>
      _db.collection('patient_notifications').doc(uid).collection('items');

  /// Realtime stream of all visible notifications ordered newest-first.
  /// deliverAt ≤ now filter ensures scheduled follow-ups are hidden until due.
  static Stream<List<NotificationModel>> streamForPatient(String uid) {
    return _items(uid)
        .where('deliverAt', isLessThanOrEqualTo: Timestamp.now())
        .orderBy('deliverAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map(NotificationModel.fromDoc).toList());
  }

  static Future<void> markRead(String uid, String notifId) =>
      _items(uid).doc(notifId).update({'isRead': true});

  static Future<void> markAllRead(String uid) async {
    // Paged in 500s like [deleteAll] — a single batch is capped at 500 writes,
    // so an account with more unread items than that used to throw and mark
    // nothing at all.
    const pageSize = 500;
    QuerySnapshot<Map<String, dynamic>> page;
    do {
      page = await _items(uid)
          .where('isRead', isEqualTo: false)
          .limit(pageSize)
          .get();
      if (page.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in page.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } while (page.docs.length == pageSize);
  }

  static Future<void> deleteNotification(String uid, String notifId) =>
      _items(uid).doc(notifId).delete();

  static Future<void> deleteAllRead(String uid) async {
    // Same 500-write batch cap as [markAllRead]/[deleteAll].
    const pageSize = 500;
    QuerySnapshot<Map<String, dynamic>> page;
    do {
      page = await _items(uid)
          .where('isRead', isEqualTo: true)
          .limit(pageSize)
          .get();
      if (page.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (page.docs.length == pageSize);
  }

  static Future<void> deleteAll(String uid) async {
    // Firestore has no recursive delete — batch in pages of 500.
    const pageSize = 500;
    QuerySnapshot<Map<String, dynamic>> page;
    do {
      page = await _items(uid).limit(pageSize).get();
      if (page.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (page.docs.length == pageSize);
  }

  static int unreadCount(List<NotificationModel> notifications) =>
      notifications.where((n) => !n.isRead).length;
}
