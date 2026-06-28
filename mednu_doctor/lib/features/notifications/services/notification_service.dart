import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

class NotificationService {
  static final _db = FirebaseFirestore.instance;

  // ── Doctor notifications ───────────────────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> _doctorNotifs(String uid) =>
      _db.collection('doctor_notifications').doc(uid).collection('items');

  static Stream<List<NotificationModel>> streamForDoctor(String uid) =>
      _doctorNotifs(uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .map((s) {
        final now = Timestamp.now();
        return s.docs
            .where((doc) {
              // Support scheduled delivery: hide notifications whose deliverAt
              // is in the future. Documents without deliverAt are shown immediately.
              final deliverAt = doc.data()['deliverAt'];
              if (deliverAt is Timestamp) return deliverAt.compareTo(now) <= 0;
              return true;
            })
            .map(NotificationModel.fromDoc)
            .toList();
      });

  static Future<void> markRead(String uid, String notifId) =>
      _doctorNotifs(uid).doc(notifId).update({'isRead': true});

  static Future<void> markAllRead(String uid) async {
    final batch = _db.batch();
    final snap = await _doctorNotifs(uid).where('isRead', isEqualTo: false).get();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  static Future<void> addDoctorNotification({
    required String doctorId,
    required NotifType type,
    required String title,
    required String body,
    Map<String, dynamic> payload = const {},
  }) async {
    await _doctorNotifs(doctorId).add({
      'type':      type.name,
      'title':     title,
      'body':      body,
      'createdAt': FieldValue.serverTimestamp(),
      // deliverAt = now so the client-side filter shows this immediately.
      // Admin-scheduled broadcasts override this field with a future timestamp.
      'deliverAt': FieldValue.serverTimestamp(),
      'isRead':    false,
      'payload':   payload,
    });
  }

  // ── Patient notifications (read by the patient app) ───────────────────────

  static CollectionReference<Map<String, dynamic>> _patientNotifs(String patientId) =>
      _db.collection('patient_notifications').doc(patientId).collection('items');

  /// Called when the doctor ends a consultation. Writes three personalized
  /// notifications for the patient: immediate, 24 h follow-up, 48 h follow-up.
  static Future<void> schedulePostConsultationNotifications({
    required String patientId,
    required String patientName,
    required String doctorName,
    required String doctorSpecialty,
    required String consultationId,
  }) async {
    final now = DateTime.now();
    final batch = _db.batch();

    // 1. Immediate — consultation complete
    final ref1 = _patientNotifs(patientId).doc();
    batch.set(ref1, {
      'type':           'consultation_done',
      'title':          'Consultation Complete',
      'body':           'Your consultation with $doctorName is complete. '
                        'Follow the prescription and rest well. '
                        'How are you feeling right now?',
      'createdAt':      FieldValue.serverTimestamp(),
      'deliverAt':      Timestamp.fromDate(now),
      'isRead':         false,
      'doctorName':     doctorName,
      'doctorSpecialty':doctorSpecialty,
      'consultationId': consultationId,
      'ctaLabel':       'Share how I feel',
      'ctaRoute':       'health_checkin',
    });

    // 2. Next-day morning follow-up (~22 h so it hits before 9 AM)
    final ref2 = _patientNotifs(patientId).doc();
    batch.set(ref2, {
      'type':           'followup_day1',
      'title':          'Good morning, ${_firstName(patientName)}! 🌅',
      'body':           'It\'s been a day since your consultation with $doctorName. '
                        'How do you feel today? Let us know if you need anything.',
      'createdAt':      FieldValue.serverTimestamp(),
      'deliverAt':      Timestamp.fromDate(now.add(const Duration(hours: 22))),
      'isRead':         false,
      'doctorName':     doctorName,
      'doctorSpecialty':doctorSpecialty,
      'consultationId': consultationId,
      'ctaLabel':       'Check in',
      'ctaRoute':       'health_checkin',
    });

    // 3. 48 h recovery check
    final ref3 = _patientNotifs(patientId).doc();
    batch.set(ref3, {
      'type':           'followup_day2',
      'title':          'Recovery Check-in 💊',
      'body':           'Hi ${_firstName(patientName)}, it\'s been 2 days since your '
                        'consultation with $doctorName. Are you feeling better? '
                        'If symptoms persist, please consult again.',
      'createdAt':      FieldValue.serverTimestamp(),
      'deliverAt':      Timestamp.fromDate(now.add(const Duration(hours: 46))),
      'isRead':         false,
      'doctorName':     doctorName,
      'doctorSpecialty':doctorSpecialty,
      'consultationId': consultationId,
      'ctaLabel':       'I\'m feeling better',
      'ctaRoute':       'health_checkin',
    });

    await batch.commit();
  }

  static String _firstName(String fullName) {
    final parts = fullName.trim().split(' ').where((p) => p.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.first : fullName.trim();
  }
}
