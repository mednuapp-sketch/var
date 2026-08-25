import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kReminderMinutes = 'appt_reminder_minutes';
const _kDefaultMinutes  = 15;

/// Queues appointment-reminder pushes for doctors via the server-driven
/// `scheduled_reminders` collection — a Cloud Function (processDueReminders)
/// delivers them via FCM, so a reminder still arrives even if the app is
/// fully closed by the time it's due (unlike the old on-device alarm, which
/// OEM battery optimization could kill).
///
/// Two reminders are queued per upcoming appointment:
///   • T-N min  — configurable (default 15), stored in SharedPreferences
///   • T-0 min  — fires at the exact slot time as a "starting now" alert
///
/// Must call [init] once during app startup — the FCM push references the
/// `appointment_reminders` channel below, which needs to exist on-device
/// *before* the push arrives (the old local-scheduling path created it
/// implicitly via zonedSchedule; nothing does that anymore).
class AppointmentReminderService {
  AppointmentReminderService._();

  static const _channelId = 'appointment_reminders';
  static const _channelName = 'Appointment Reminders';
  static final _queueCol =
      FirebaseFirestore.instance.collection('scheduled_reminders');
  static bool _initialised = false;

  static Future<void> init() async {
    if (_initialised) return;
    if (Platform.isAndroid) {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: 'Reminders before scheduled consultations',
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
            ),
          );
    }
    _initialised = true;
  }

  // ── Reminder preference ─────────────────────────────────────────────────────

  static Future<int> getReminderMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kReminderMinutes) ?? _kDefaultMinutes;
  }

  static Future<void> setReminderMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kReminderMinutes, minutes);
  }

  // ── Queue reminders for an upcoming appointment ────────────────────────────

  /// [uid]           the doctor's own uid (recipient of the push).
  /// [appointmentId]  must be the Firestore document ID.
  /// [dateStr]       YYYY-MM-DD (ISO date stored in Firestore).
  /// [timeStr]       slot string, e.g. "10:00 AM" or "02:30 PM".
  static Future<void> scheduleReminders({
    required String uid,
    required String appointmentId,
    required String patientName,
    required String dateStr,
    required String timeStr,
  }) async {
    final slotTime = _parseSlot(dateStr, timeStr);
    if (slotTime == null) return;

    final now = DateTime.now();
    final minutes = await getReminderMinutes();
    final timeLabel = minutes >= 60
        ? '${minutes ~/ 60} hour${minutes >= 120 ? 's' : ''}'
        : '$minutes minute${minutes != 1 ? 's' : ''}';

    final reminderTime = slotTime.subtract(Duration(minutes: minutes));
    if (reminderTime.isAfter(now)) {
      await _queue(
        docId: _reminderDocId(uid, appointmentId),
        uid: uid,
        title: 'Appointment in $timeLabel',
        body: '$patientName — tap to get ready.',
        fireAt: reminderTime,
        data: {'type': 'appointment_reminder', 'appointmentId': appointmentId},
      );
    } else {
      await _queueCol.doc(_reminderDocId(uid, appointmentId)).delete().catchError((_) {});
    }

    if (slotTime.isAfter(now)) {
      await _queue(
        docId: _startDocId(uid, appointmentId),
        uid: uid,
        title: 'Consultation Starting NOW',
        body: 'Your appointment with $patientName is starting. Tap to join.',
        fireAt: slotTime,
        data: {'type': 'appointment_start', 'appointmentId': appointmentId},
      );
    } else {
      await _queueCol.doc(_startDocId(uid, appointmentId)).delete().catchError((_) {});
    }
  }

  // ── Cancel reminders (e.g. appointment cancelled) ─────────────────────────

  static Future<void> cancelReminders(String uid, String appointmentId) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.delete(_queueCol.doc(_reminderDocId(uid, appointmentId)));
    batch.delete(_queueCol.doc(_startDocId(uid, appointmentId)));
    await batch.commit().catchError((_) {});
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Future<void> _queue({
    required String docId,
    required String uid,
    required String title,
    required String body,
    required DateTime fireAt,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _queueCol.doc(docId).set({
        'uid': uid,
        'role': 'doctor',
        'title': title,
        'body': body,
        'channelId': _channelId,
        'data': data,
        'fireAt': Timestamp.fromDate(fireAt),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static DateTime? _parseSlot(String dateStr, String timeStr) {
    try {
      final date  = DateTime.parse(dateStr);
      final parts = timeStr.trim().split(' ');
      final hm    = parts[0].split(':');
      int h       = int.parse(hm[0]);
      final m     = int.parse(hm[1]);
      if (parts.length > 1 && parts[1].toUpperCase() == 'PM' && h != 12) h += 12;
      if (parts.length > 1 && parts[1].toUpperCase() == 'AM' && h == 12) h = 0;
      return DateTime(date.year, date.month, date.day, h, m);
    } catch (_) {
      return null;
    }
  }

  static String _reminderDocId(String uid, String appointmentId) =>
      '${uid}_appt_${appointmentId}_reminder';

  static String _startDocId(String uid, String appointmentId) =>
      '${uid}_appt_${appointmentId}_start';
}
