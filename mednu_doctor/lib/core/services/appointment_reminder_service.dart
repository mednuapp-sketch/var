import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

const _kReminderMinutes = 'appt_reminder_minutes';
const _kDefaultMinutes  = 15;

/// Schedules and cancels local appointment-reminder notifications for doctors.
///
/// Two notifications are fired per upcoming appointment:
///   • T-N min  — configurable (default 15), stored in SharedPreferences
///   • T-0 min  — fires at the exact slot time as a "starting now" alert
///
/// Must call [init] once during app startup before any other method.
class AppointmentReminderService {
  AppointmentReminderService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialised = false;

  // ── Notification channel ────────────────────────────────────────────────────
  static const _channelId   = 'appointment_reminders';
  static const _channelName = 'Appointment Reminders';

  static const _androidDetails = AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: 'Reminders before scheduled consultations',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
    enableVibration: true,
    playSound: true,
  );

  static const _notifDetails = NotificationDetails(android: _androidDetails);

  // ── Reminder preference ─────────────────────────────────────────────────────

  static Future<int> getReminderMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kReminderMinutes) ?? _kDefaultMinutes;
  }

  static Future<void> setReminderMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kReminderMinutes, minutes);
  }

  // ── Initialisation ─────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialised) return;
    tz_data.initializeTimeZones();
    final platformTz = DateTime.now().timeZoneName;
    try {
      tz.setLocalLocation(tz.getLocation(platformTz));
    } catch (_) {
      final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
      for (final loc in tz.timeZoneDatabase.locations.values) {
        try {
          final tzNow = tz.TZDateTime.now(loc);
          if (tzNow.timeZoneOffset.inMinutes == offsetMinutes) {
            tz.setLocalLocation(loc);
            break;
          }
        } catch (_) {}
      }
    }

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    _initialised = true;
  }

  // ── Schedule reminders for an upcoming appointment ─────────────────────────

  /// [appointmentId] must be the Firestore document ID.
  /// [dateStr]       YYYY-MM-DD (ISO date stored in Firestore).
  /// [timeStr]       slot string, e.g. "10:00 AM" or "02:30 PM".
  static Future<void> scheduleReminders({
    required String appointmentId,
    required String patientName,
    required String dateStr,
    required String timeStr,
  }) async {
    if (!_initialised) await init();

    final slotTime = _parseSlot(dateStr, timeStr);
    if (slotTime == null) return;

    final now = DateTime.now();
    final minutes = await getReminderMinutes();
    final timeLabel = minutes >= 60
        ? '${minutes ~/ 60} hour${minutes >= 120 ? 's' : ''}'
        : '$minutes minute${minutes != 1 ? 's' : ''}';

    final reminderTime = slotTime.subtract(Duration(minutes: minutes));
    if (reminderTime.isAfter(now)) {
      await _schedule(
        id:    _reminderNotifId(appointmentId),
        title: 'Appointment in $timeLabel',
        body:  '$patientName — tap to get ready.',
      when:  reminderTime,
      );
    }

    if (slotTime.isAfter(now)) {
      await _schedule(
        id:    _startNotifId(appointmentId),
        title: 'Consultation Starting NOW',
        body:  'Your appointment with $patientName is starting. Tap to join.',
        when:  slotTime,
      );
    }
  }

  // ── Cancel reminders (e.g. appointment cancelled) ─────────────────────────

  static Future<void> cancelReminders(String appointmentId) async {
    await _plugin.cancel(_reminderNotifId(appointmentId));
    await _plugin.cancel(_startNotifId(appointmentId));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        _notifDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Exact alarm permission denied on some Android 12+ devices; silently skip.
    }
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

  /// Stable notification ID for the pre-appointment reminder.
  static int _reminderNotifId(String appointmentId) =>
      (appointmentId.hashCode.abs() % 1000000) * 10 + 1;

  /// Stable notification ID for the "starting now" alert.
  static int _startNotifId(String appointmentId) =>
      (appointmentId.hashCode.abs() % 1000000) * 10 + 2;
}
