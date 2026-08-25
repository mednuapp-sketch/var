import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../../../core/services/scheduled_reminder_queue.dart';

class HealthNotificationService {
  HealthNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _waterChannelId = 'water_reminders';
  static const _waterChannelName = 'Water Reminders';
  static const _periodChannelId = 'period_reminders';
  static const _periodChannelName = 'Period Reminders';

  static Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _waterChannelId,
          _waterChannelName,
          description: 'Reminders to drink water throughout the day',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _periodChannelId,
          _periodChannelName,
          description: 'Period cycle reminders',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _periodWellnessChannelId,
          _periodWellnessChannelName,
          description: 'Caring wellness check-ins during your period',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidPlugin?.requestNotificationsPermission() ?? false;
    } else if (Platform.isIOS) {
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  static Future<bool> requestNotificationPermission() => requestPermission();

  static Future<bool> hasNotificationPermission() async {
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidPlugin?.areNotificationsEnabled() ?? false;
    }
    return true;
  }

  static Future<bool> hasExactAlarmPermission() async {
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidPlugin?.canScheduleExactNotifications() ?? true;
    }
    return true;
  }

  static Future<void> requestExactAlarmPermission() async {
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestExactAlarmsPermission();
    }
  }

  /// Returns the next scheduled water reminder time based on [intervalHours],
  /// starting the daily slot grid at [startHour]:[startMinute].
  static DateTime? nextReminderTime(int intervalHours,
      {int startHour = 8, int startMinute = 0}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfDay = today.add(Duration(minutes: startHour * 60 + startMinute));
    for (int offset = 0; offset <= _reminderSpanMinutes; offset += intervalHours * 60) {
      final candidate = startOfDay.add(Duration(minutes: offset));
      if (candidate.isAfter(now)) return candidate;
    }
    // All today's slots passed — return first slot tomorrow
    return startOfDay.add(const Duration(days: 1));
  }

  // Slots span 13 hours from the start time (e.g. 8 AM–9 PM by default),
  // matching a typical waking day.
  static const _reminderSpanMinutes = 13 * 60;

  static const _periodWellnessChannelId   = 'period_wellness';
  static const _periodWellnessChannelName = 'Period Wellness';

  static const _medAlertChannelId   = 'med_alerts';
  static const _medAlertChannelName = 'Medical Alerts';

  static Future<void> showMedicalAlert({
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _medAlertChannelId,
          _medAlertChannelName,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
    }
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _medAlertChannelId,
          _medAlertChannelName,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  // Water reminders are now delivered server-side (Cloud Function
  // sendDueWaterReminders, driven off this same settings doc) so they still
  // fire even if the app is fully closed — see the reminders migration plan.
  // The _waterChannelId channel above is still created here so the FCM
  // message that references it has somewhere to land.

  // Period reminders and wellness check-ins are delivered server-side (Cloud
  // Function processDueReminders, polling the `scheduled_reminders`
  // collection this queues into) so they still fire even if the app is
  // fully closed — see the reminders migration plan. Message content stays
  // here since it's unchanged; only the delivery sink moved.

  static Future<void> schedulePeriodReminder(
      String uid, DateTime nextPeriodDate, int daysBefore) async {
    final reminderDay = nextPeriodDate.subtract(Duration(days: daysBefore));
    final reminderDateTime =
        DateTime(reminderDay.year, reminderDay.month, reminderDay.day, 9, 0);
    if (reminderDateTime.isBefore(DateTime.now())) {
      await cancelPeriodReminder(uid);
      return;
    }

    await ScheduledReminderQueue.queue(
      docId: '${uid}_period_reminder',
      uid: uid,
      role: 'patient',
      title: '🌸 Period coming soon',
      body: 'Your period is expected in $daysBefore day${daysBefore == 1 ? '' : 's'}. Stay prepared!',
      channelId: _periodChannelId,
      fireAt: reminderDateTime,
      data: const {'type': 'period_tracker'},
    );
  }

  static Future<void> cancelPeriodReminder(String uid) =>
      ScheduledReminderQueue.cancel('${uid}_period_reminder');

  // Period wellness slots: 7 days × 3/day (morning/afternoon/evening)
  static const _wellnessMessages = [
    // [title, body] — morning slot (index 0,3,6,...)
    ['🌸 Good morning, take care!', 'Your body is working hard today. Stay warm and drink plenty of water. 💕'],
    ['🌺 Morning check-in', 'How are you feeling today? Remember to be gentle with yourself. 💜'],
    ['🌸 Rise & rest easy', 'It\'s okay to slow down today. Listen to your body and take breaks. 🌿'],
    ['🌺 Morning wellness', 'Deep breaths help ease cramps. Try gentle stretching to start your day. 🧘‍♀️'],
    ['🌸 Good morning!', 'Warmth helps — try a warm compress or heating pad on your lower abdomen. 💕'],
    ['🌺 You\'ve got this!', 'Period days can be tough. We\'re rooting for you. Take it one hour at a time. 💜'],
    ['🌸 A gentle reminder', 'Hydration is your best friend right now. Aim for 8+ glasses today! 💧'],
  ];

  static const _foodMessages = [
    // afternoon slot
    ['🍫 Period-friendly snack time!', 'Dark chocolate eases cramps + boosts mood. Also try bananas and nuts! 🍌'],
    ['🥗 Nourish your body', 'Iron-rich foods like spinach, lentils, and tofu help replenish your body. 💚'],
    ['🍵 Warm drinks are magic', 'Ginger tea or chamomile tea soothes cramps and reduces bloating. ☕'],
    ['🍓 Vitamin boost time!', 'Berries and citrus fruits are rich in Vitamin C, helping iron absorption. 🍊'],
    ['🥦 Eat well today', 'Broccoli, kale, and leafy greens are your best friends on period days. 🌿'],
    ['🫚 Omega-3 helps!', 'Walnuts and flaxseeds contain Omega-3 which can reduce inflammation and cramps. 🌰'],
    ['🍵 Stay warm inside', 'A warm bowl of soup or porridge is comforting and easy on your tummy. 🍲'],
  ];

  static const _eveningMessages = [
    // evening slot
    ['🌙 Evening check-in', 'How was your day? Rest well tonight. Apply warmth to ease any discomfort. 💜'],
    ['💜 How do you feel now?', 'Gentle yoga or legs-up-the-wall pose can relieve cramps before sleep. 🧘‍♀️'],
    ['🌙 Wind down gently', 'A warm bath with Epsom salt can relax tense muscles tonight. 🛁'],
    ['💕 You deserve rest', 'Skip strenuous workouts today. Light walks are enough — be kind to yourself. 🌿'],
    ['🌙 Good night check-in', 'Are you okay? Sleep is healing — try to get at least 8 hours tonight. 😴'],
    ['💜 Evening wellness tip', 'Avoid caffeine and salty foods at night — they can worsen bloating. 🌙'],
    ['🌸 Rest & recover', 'Your body is doing something incredible. Honor it with rest and warmth tonight. 💕'],
  ];

  static const _wellnessSlotHours = [9, 13, 19]; // morning / afternoon / evening

  /// Queues caring wellness reminders for [durationDays] days starting from
  /// [periodStartDate]. 3 per day, at 9 AM / 1 PM / 7 PM.
  static Future<void> schedulePeriodWellnessNotifications({
    required String uid,
    required DateTime periodStartDate,
    int durationDays = 7,
  }) async {
    await cancelPeriodWellnessNotifications(uid, durationDays: durationDays);

    final now = DateTime.now();

    for (int day = 0; day < durationDays; day++) {
      final base = DateTime(
        periodStartDate.year,
        periodStartDate.month,
        periodStartDate.day + day,
      );

      final slots = [
        (_wellnessSlotHours[0], _wellnessMessages[day % _wellnessMessages.length]),
        (_wellnessSlotHours[1], _foodMessages[day % _foodMessages.length]),
        (_wellnessSlotHours[2], _eveningMessages[day % _eveningMessages.length]),
      ];

      for (final (hour, msg) in slots) {
        final scheduled = DateTime(base.year, base.month, base.day, hour);
        if (scheduled.isBefore(now)) continue;
        await ScheduledReminderQueue.queue(
          docId: '${uid}_wellness_${day}_$hour',
          uid: uid,
          role: 'patient',
          title: msg[0],
          body: msg[1],
          channelId: _periodWellnessChannelId,
          fireAt: scheduled,
          data: const {'type': 'period_tracker'},
        );
      }
    }
  }

  static Future<void> cancelPeriodWellnessNotifications(String uid,
      {int durationDays = 7}) {
    final docIds = <String>[
      for (int day = 0; day < durationDays; day++)
        for (final hour in _wellnessSlotHours) '${uid}_wellness_${day}_$hour',
    ];
    return ScheduledReminderQueue.cancelMany(docIds);
  }
}
