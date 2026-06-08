import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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

  /// Returns the next scheduled water reminder time based on [intervalHours].
  static DateTime? nextReminderTime(int intervalHours) {
    final now = DateTime.now();
    for (int hour = 8; hour <= 21; hour += intervalHours) {
      final candidate = DateTime(now.year, now.month, now.day, hour);
      if (candidate.isAfter(now)) return candidate;
    }
    // All today's slots passed — return first slot tomorrow
    return DateTime(now.year, now.month, now.day + 1, 8);
  }

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

  // Water reminder IDs: 100-119
  static Future<void> cancelWaterReminders() async {
    for (int id = 100; id < 120; id++) {
      await _plugin.cancel(id);
    }
  }

  /// Schedules daily water reminders from 8 AM to 9 PM at [intervalHours] gaps.
  static Future<void> scheduleWaterReminders(int intervalHours) async {
    await cancelWaterReminders();
    final now = tz.TZDateTime.now(tz.local);
    int notifId = 100;

    for (int hour = 8; hour <= 21 && notifId < 120; hour += intervalHours) {
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, 0);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      await _plugin.zonedSchedule(
        notifId++,
        '💧 Time to hydrate!',
        'Keep it up — drink a glass of water to stay healthy.',
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _waterChannelId,
            _waterChannelName,
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
        payload: 'water_reminder',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  // Period reminder ID: 200
  static Future<void> schedulePeriodReminder(
      DateTime nextPeriodDate, int daysBefore) async {
    await cancelPeriodReminder();
    final reminderDay = nextPeriodDate.subtract(Duration(days: daysBefore));
    final reminderDateTime =
        DateTime(reminderDay.year, reminderDay.month, reminderDay.day, 9, 0);
    if (reminderDateTime.isBefore(DateTime.now())) return;

    await _plugin.zonedSchedule(
      200,
      '🌸 Period coming soon',
      'Your period is expected in $daysBefore day${daysBefore == 1 ? '' : 's'}. Stay prepared!',
      tz.TZDateTime.from(reminderDateTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _periodChannelId,
          _periodChannelName,
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
      payload: 'period_tracker',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelPeriodReminder() => _plugin.cancel(200);

  // Period wellness IDs: 300–370 (7 days × 3 slots/day + buffer)
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

  static const _wellnessDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _periodWellnessChannelId,
      _periodWellnessChannelName,
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
  );

  /// Schedules caring wellness notifications for [durationDays] days
  /// starting from [periodStartDate]. 3 per day: 9 AM, 1 PM, 7 PM.
  static Future<void> schedulePeriodWellnessNotifications({
    required DateTime periodStartDate,
    int durationDays = 7,
  }) async {
    if (!_initialized) await init();
    await cancelPeriodWellnessNotifications();

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
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

    final now = DateTime.now();
    int notifId = 300;

    for (int day = 0; day < durationDays && notifId < 370; day++) {
      final base = DateTime(
        periodStartDate.year,
        periodStartDate.month,
        periodStartDate.day + day,
      );

      final slots = [
        (9, _wellnessMessages[day % _wellnessMessages.length]),
        (13, _foodMessages[day % _foodMessages.length]),
        (19, _eveningMessages[day % _eveningMessages.length]),
      ];

      for (final (hour, msg) in slots) {
        if (notifId >= 370) break;
        final scheduled = DateTime(base.year, base.month, base.day, hour);
        if (scheduled.isBefore(now)) {
          notifId++;
          continue;
        }
        await _plugin.zonedSchedule(
          notifId++,
          msg[0],
          msg[1],
          tz.TZDateTime.from(scheduled, tz.local),
          _wellnessDetails,
          payload: 'period_tracker',
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  static Future<void> cancelPeriodWellnessNotifications() async {
    for (int id = 300; id < 370; id++) {
      await _plugin.cancel(id);
    }
  }
}
