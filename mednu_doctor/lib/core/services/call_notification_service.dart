import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Handles incoming-call-style alerts for the doctor app.
///
/// Combines a high-priority heads-up OS notification (with full-screen intent
/// to wake the device) with the system ringtone played via
/// [FlutterRingtonePlayer] so the doctor hears a continuous, looping ring
/// regardless of whether the app is in the foreground or background.
class CallNotificationService {
  CallNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _ringtonePlayer = FlutterRingtonePlayer();
  static bool _initialized = false;
  static bool _isRinging = false;

  static const _callChannelId = 'incoming_call';
  static const _callChannelName = 'Incoming Consultations';
  static const _emergencyChannelId = 'emergency_alert';
  static const _emergencyChannelName = 'Emergency Alerts';

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
      // Create the dedicated call channel with maximum importance so
      // the OS never suppresses or delays incoming-call alerts.
      await androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          _callChannelId,
          _callChannelName,
          description: 'Incoming patient consultation requests',
          importance: Importance.max,
          enableVibration: true,
          vibrationPattern:
              Int64List.fromList([0, 800, 200, 800, 200, 800, 200, 800]),
          playSound: true,
          enableLights: true,
          ledColor: const Color(0xFF4CAF50),
        ),
      );
      await androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          _emergencyChannelId,
          _emergencyChannelName,
          description: 'Critical emergency patient alerts',
          importance: Importance.max,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 100, 500, 100, 500]),
          playSound: true,
          enableLights: true,
          ledColor: const Color(0xFFE53935),
        ),
      );
    }

    _initialized = true;
  }

  // ── Show notification ─────────────────────────────────────────────────────

  static int _notifId = 100;

  /// Shows a full-screen, ongoing call notification and starts ringing.
  static Future<void> showIncomingCall({
    required String patientName,
    String complaint = '',
  }) async {
    final body =
        complaint.isNotEmpty ? complaint : 'Tap to accept or decline';

    await _plugin.show(
      _notifId++,
      '📞 Incoming from $patientName',
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
          // fullScreenIntent wakes the device screen and shows the
          // notification even on the lock screen.
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          // ongoing + autoCancel:false keeps the notification sticky
          // until the doctor explicitly accepts or declines.
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

    // Start ringtone AFTER posting the notification so the OS wake-up
    // happens first and the audio plays on the now-active screen.
    await startRinging();
  }

  /// Shows a high-priority emergency alert notification (not a call UI).
  /// Plays a short alert tone once instead of looping the ringtone.
  static Future<void> showEmergencyAlert({
    required String patientName,
    String requestId = '',
  }) async {
    const title = '🚨 Emergency Doctor Request';
    final body = '$patientName needs immediate medical assistance.';

    await _plugin.show(
      _notifId++,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _emergencyChannelId,
          _emergencyChannelName,
          importance: Importance.max,
          priority: Priority.max,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 100, 500, 100, 500]),
          playSound: true,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          autoCancel: true,
          styleInformation: BigTextStyleInformation(body),
          color: const Color(0xFFE53935),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.critical,
        ),
      ),
    );

    // Single short alert tone — not a looping ringtone.
    try {
      await _ringtonePlayer.play(
        android: AndroidSounds.alarm,
        ios: IosSounds.electronic,
        looping: false,
        volume: 1.0,
        asAlarm: true,
      );
    } catch (_) {}
  }

  // ── Ringtone + wakelock ───────────────────────────────────────────────────

  /// Starts the system ringtone (looping) and enables the wakelock.
  /// Safe to call multiple times — will only ring once until [stopRinging].
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
    } catch (_) {
      // Ringtone failure must never crash the app.
    }
  }

  /// Stops the ringtone immediately and releases the wakelock.
  static Future<void> stopRinging() async {
    if (!_isRinging) return;
    _isRinging = false;
    try {
      await _ringtonePlayer.stop();
      await WakelockPlus.disable();
    } catch (_) {}
  }

  // ── Cancel all ────────────────────────────────────────────────────────────

  /// Stops ringing, removes the wakelock, and cancels all OS notifications.
  static Future<void> cancelAll() async {
    await stopRinging();
    await _plugin.cancelAll();
  }
}
