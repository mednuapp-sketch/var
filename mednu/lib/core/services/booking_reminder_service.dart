import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'scheduled_reminder_queue.dart';
import '../../features/my_services/models/unified_booking.dart';

/// Queues and cancels reminders for all patient booking types via the
/// server-driven `scheduled_reminders` queue (see [ScheduledReminderQueue]) —
/// delivery is a Cloud Function push, not a local device alarm, so a
/// reminder still arrives even if the app is fully closed by the time it's
/// due.
///
/// Doc IDs are deterministic (`{uid}_booking_{bookingId}`) so re-syncing a
/// booking overwrites its existing reminder rather than duplicating it.
class BookingReminderService {
  BookingReminderService._();

  static const _channelId = 'booking_reminders';
  static const _channelName = 'Appointment & Service Reminders';
  static bool _initialised = false;

  /// Creates the `booking_reminders` channel the FCM push references — the
  /// old local-scheduling path created it implicitly on first zonedSchedule
  /// call; nothing does that anymore now that firing is server-side.
  static Future<void> _ensureInit() async {
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
              description: 'Reminders before your upcoming appointments and services',
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
            ),
          );
    }
    _initialised = true;
  }

  /// Cancel then re-queue reminders for the provided [bookings].
  ///
  /// Every booking's existing reminder is cancelled first (handles stale
  /// reminders from a previous minutesBefore setting), then a new one is
  /// queued for each upcoming active booking.
  static Future<void> syncReminders(
    String uid,
    List<UnifiedBooking> bookings,
    int minutesBefore,
  ) async {
    await _ensureInit();
    final now = DateTime.now();

    for (final booking in bookings) {
      final docId = _docId(uid, booking.id);
      await ScheduledReminderQueue.cancel(docId);

      if (!booking.isActive) continue;

      final serviceTime = _parseBookingTime(booking);
      if (serviceTime == null) continue;

      final reminderTime = serviceTime.subtract(Duration(minutes: minutesBefore));
      if (!reminderTime.isAfter(now)) continue;

      final (:title, :body) = _buildMessage(booking, minutesBefore);
      await ScheduledReminderQueue.queue(
        docId: docId,
        uid: uid,
        role: 'patient',
        title: title,
        body: body,
        channelId: _channelId,
        fireAt: reminderTime,
        data: {'type': 'booking', 'bookingId': booking.id},
      );
    }
  }

  /// Cancel a single booking's reminder (e.g. after manual cancellation).
  static Future<void> cancelReminder(String uid, String bookingId) =>
      ScheduledReminderQueue.cancel(_docId(uid, bookingId));

  /// Cancel every booking reminder queued for this user.
  static Future<void> cancelAllReminders(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('scheduled_reminders')
        .where('uid', isEqualTo: uid)
        .get();
    final prefix = '${uid}_booking_';
    final ids = snap.docs.map((d) => d.id).where((id) => id.startsWith(prefix));
    await ScheduledReminderQueue.cancelMany(ids);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static String _docId(String uid, String bookingId) => '${uid}_booking_$bookingId';

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
}
