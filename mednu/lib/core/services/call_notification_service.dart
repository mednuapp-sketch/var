import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Incoming-call-style notification service for the patient app.
///
/// Used when a doctor initiates a call to the patient. Mirrors the doctor
/// app's [CallNotificationService] — shows a full-screen heads-up OS
/// notification that wakes the device and plays the system ringtone.
class CallNotificationService {
  CallNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _ringtonePlayer = FlutterRingtonePlayer();
  static bool _initialized = false;
  static bool _isRinging = false;

  static const _callChannelId = 'incoming_call_patient';
  static const _callChannelName = 'Incoming Doctor Calls';

  // ── Init ──────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          _callChannelId,
          _callChannelName,
          description: 'Incoming calls from your doctor',
          importance: Importance.max,
          enableVibration: true,
          vibrationPattern:
              Int64List.fromList([0, 800, 200, 800, 200, 800, 200, 800]),
          playSound: true,
          enableLights: true,
          ledColor: const Color(0xFF2196F3),
        ),
      );
    }

    _initialized = true;
  }

  // ── Show notification ─────────────────────────────────────────────────────

  static int _notifId = 200;

  static Future<void> showIncomingCall({
    required String doctorName,
    String specialty = '',
  }) async {
    final body = specialty.isNotEmpty ? specialty : 'Tap to accept or decline';

    await _plugin.show(
      _notifId++,
      '📞 Dr. $doctorName is calling',
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _callChannelId,
          _callChannelName,
          importance: Importance.max,
          priority: Priority.max,
          enableVibration: true,
          vibrationPattern:
              Int64List.fromList([0, 800, 200, 800, 200, 800, 200, 800]),
          playSound: true,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          ongoing: true,
          autoCancel: false,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.critical,
        ),
      ),
    );

    await startRinging();
  }

  // ── Ringtone + wakelock ───────────────────────────────────────────────────

  static Future<void> startRinging() async {
    if (_isRinging) return;
    _isRinging = true;
    try {
      await WakelockPlus.enable();
      await _ringtonePlayer.play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.electronic,
        looping: true,
        volume: 1.0,
        asAlarm: false,
      );
    } catch (_) {}
  }

  static Future<void> stopRinging() async {
    if (!_isRinging) return;
    _isRinging = false;
    try {
      await _ringtonePlayer.stop();
      await WakelockPlus.disable();
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    await stopRinging();
    await _plugin.cancelAll();
  }
}
