import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import '../../features/my_services/models/unified_booking.dart';

/// Schedules and cancels local reminders for all patient booking types.
///
/// Notification IDs are derived deterministically from booking IDs in the
/// range 2000–2499, so [cancelAllReminders] can sweep the entire range.
class BookingReminderService {
  BookingReminderService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialised = false;

  static const _channelId   = 'booking_reminders';
  static const _channelName = 'Appointment & Service Reminders';

  static const _notifDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Reminders before your upcoming appointments and services',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  // ── Initialisation ──────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialised) return;

    tz_data.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Reminders before your upcoming appointments and services',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    _initialised = true;
  }

  // ── Sync ────────────────────────────────────────────────────────────────────

  /// Cancel then re-schedule reminders for the provided [bookings].
  ///
  /// Every booking's existing reminder is cancelled first (handles stale
  /// notifications from previous sessions), then a new reminder is scheduled
  /// for each upcoming active booking.
  static Future<void> syncReminders(
    List<UnifiedBooking> bookings,
    int minutesBefore,
  ) async {
    if (!_initialised) await init();

    final now = DateTime.now();

    for (final booking in bookings) {
      final id = _notifId(booking.id);
      await _plugin.cancel(id);

      if (!booking.isActive) continue;

      final serviceTime = _parseBookingTime(booking);
      if (serviceTime == null) continue;

      final reminderTime = serviceTime.subtract(Duration(minutes: minutesBefore));
      if (!reminderTime.isAfter(now)) continue;

      final (:title, :body) = _buildMessage(booking, minutesBefore);
      await _schedule(id: id, title: title, body: body, when: reminderTime);
    }
  }

  /// Cancel a single booking's reminder (e.g. after manual cancellation).
  static Future<void> cancelReminder(String bookingId) async {
    await _plugin.cancel(_notifId(bookingId));
  }

  /// Cancel all booking reminders by sweeping the reserved ID range 2000–2499.
  static Future<void> cancelAllReminders() async {
    for (int id = 2000; id < 2500; id++) {
      await _plugin.cancel(id);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

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
      // Exact alarm permission may be denied on Android 12+; silently skip.
    }
  }

  static DateTime? _parseBookingTime(UnifiedBooking booking) {
    try {
      final dateStr = booking.date;
      final timeStr = booking.time;
      if (dateStr.isEmpty || timeStr.isEmpty) return null;

      final date  = DateTime.parse(dateStr);
      final parts = timeStr.trim().split(' ');
      final hm    = parts[0].split(':');
      int h       = int.parse(hm[0]);
      final m     = int.parse(hm[1]);
      if (parts.length > 1) {
        final period = parts[1].toUpperCase();
        if (period == 'PM' && h != 12) h += 12;
        if (period == 'AM' && h == 12) h = 0;
      }
      return DateTime(date.year, date.month, date.day, h, m);
    } catch (_) {
      return null;
    }
  }

  static ({String title, String body}) _buildMessage(
      UnifiedBooking booking, int minutesBefore) {
    final timeLabel = minutesBefore >= 60
        ? '${minutesBefore ~/ 60} hour${minutesBefore >= 120 ? 's' : ''}'
        : '$minutesBefore min${minutesBefore != 1 ? 's' : ''}';

    switch (booking.source) {
      case BookingSource.appointment:
        final doctor = booking.providerName ?? 'your doctor';
        return (
          title: 'Appointment in $timeLabel',
          body:  'Your appointment with $doctor is starting soon.',
        );
      case BookingSource.consultation:
        final doctor = booking.providerName ?? 'your doctor';
        return (
          title: 'Video Consultation in $timeLabel',
          body:  'Your video call with $doctor starts in $timeLabel. Get ready!',
        );
      case BookingSource.serviceRequest:
        final service = booking.serviceType;
        return (
          title: '$service in $timeLabel',
          body:  'Your $service is scheduled in $timeLabel.',
        );
      case BookingSource.nutrition:
        final provider = booking.providerName ?? 'your nutritionist';
        return (
          title: 'Nutrition Session in $timeLabel',
          body:  'Your session with $provider starts in $timeLabel.',
        );
    }
  }

  /// Deterministic notification ID in range 2000–2499.
  static int _notifId(String bookingId) =>
      2000 + (bookingId.hashCode.abs() % 500);
}
