import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter ↔ Android bridge for the in-call foreground service.
///
/// Call [start] when a consultation call begins. This does two things:
///   1. Caches the Flutter engine so Android never kills the Dart VM when the
///      user swipes the app from recents (WhatsApp-style persistent calls).
///   2. Starts a foreground service with a persistent "In call" notification.
///
/// Call [stop] only when the call actually ends (not on widget dispose).
///
/// Only active on Android — iOS calls stay alive via the audio session.
class ActiveCallService {
  ActiveCallService._();

  static const _channel = MethodChannel('mednu/active_call');

  /// Starts the foreground service and caches the Flutter engine.
  /// [callerName] is shown in the persistent notification.
  static Future<void> start({
    required String callId,
    required String callerName,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('startForeground', {
        'callId': callId,
        'callerName': callerName,
      });
    } catch (e) {
      debugPrint('[ActiveCallService] start error: $e');
    }
  }

  /// Stops the foreground service and releases the engine cache.
  /// Call this when the call is explicitly ended (not on widget dispose).
  static Future<void> stop() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('stopForeground');
    } catch (e) {
      debugPrint('[ActiveCallService] stop error: $e');
    }
  }

  /// Registers a callback invoked when the user taps "End Call" in the
  /// persistent notification while the app is in the background.
  static void setEndCallFromNotificationHandler(Future<void> Function() handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onEndCallFromNotification') {
        await handler();
      }
    });
  }

  /// Clears the notification "End Call" handler (call in widget dispose).
  static void clearEndCallFromNotificationHandler() {
    _channel.setMethodCallHandler(null);
  }
}
