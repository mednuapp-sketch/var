import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

/// Schedules and cancels local appointment-reminder notifications.
///
/// Two reminders are fired per upcoming appointment:
///   • T-10 min  — "Consultation starting in 10 minutes"
///   • T-5  min  — "Patient may already be waiting — Start now"
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

  // ── Initialisation ─────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialised) return;
    // Load timezone database (bundled with the timezone package).
    tz_data.initializeTimeZones();
    // We use UTC-based scheduling; exact wall-clock is computed by the device.
    // For per-device local time, call tz.setLocalLocation() with the device's
    // IANA timezone name obtained via flutter_timezone or similar.

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

    final fiveMinBefore = slotTime.subtract(const Duration(minutes: 5));

    if (fiveMinBefore.isAfter(now)) {
      await _schedule(
        id:    _notifId(appointmentId, 5),
        title: '⏰ Consultation in 5 minutes',
        body:  '$patientName is waiting. Tap to get ready.',
        when:  fiveMinBefore,
      );
    }

    // T=0 alert — fires at the exact appointment time to trigger auto-connect.
    if (slotTime.isAfter(now)) {
      await _schedule(
        id:    _notifId(appointmentId, 0),
        title: '🔴 Consultation Starting NOW',
        body:  'Your appointment with $patientName is starting. Tap to join.',
        when:  slotTime,
      );
    }
  }

  // ── Cancel reminders (e.g. appointment cancelled) ─────────────────────────

  static Future<void> cancelReminders(String appointmentId) async {
    await _plugin.cancel(_notifId(appointmentId, 5));
    await _plugin.cancel(_notifId(appointmentId, 0));
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
        tz.TZDateTime.from(when, tz.UTC),
        _notifDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Exact alarm permission denied on some Android 12+ devices; silently
      // fall back rather than crashing the app.
    }
  }

  /// Converts the Firestore date + time-slot strings into a [DateTime].
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

  /// Deterministic integer notification ID derived from the Firestore doc ID
  /// and the reminder offset in minutes.  Stays within the 32-bit int range.
  static int _notifId(String appointmentId, int minutesBefore) =>
      (appointmentId.hashCode.abs() % 1000000) * 100 + minutesBefore;
}
