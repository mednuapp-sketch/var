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
    final snap = await _items(uid).where('isRead', isEqualTo: false).get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  static Future<void> deleteNotification(String uid, String notifId) =>
      _items(uid).doc(notifId).delete();

  static Future<void> deleteAllRead(String uid) async {
    final snap = await _items(uid).where('isRead', isEqualTo: true).get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
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
