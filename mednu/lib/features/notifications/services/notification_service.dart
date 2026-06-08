import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

class PatientNotificationService {
  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _items(String uid) =>
      _db.collection('patient_notifications').doc(uid).collection('items');

  /// Stream only notifications whose deliverAt <= now, newest first.
  static Stream<List<NotificationModel>> streamForPatient(String uid) {
    return _items(uid)
        .where('deliverAt', isLessThanOrEqualTo: Timestamp.now())
        .orderBy('deliverAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map(NotificationModel.fromDoc).toList());
  }

  static Future<void> markRead(String uid, String notifId) =>
      _items(uid).doc(notifId).update({'isRead': true});

  static Future<void> markAllRead(String uid) async {
    final batch = _db.batch();
    final snap =
        await _items(uid).where('isRead', isEqualTo: false).get();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }
}
