import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter ↔ Android bridge for the in-call foreground service.
///
/// Call [start] when a consultation call begins. This does two things:
///   1. Caches the Flutter engine so Android never kills the Dart VM when the
///      doctor swipes the app from recents (WhatsApp-style persistent calls).
///   2. Starts a foreground service with a persistent "In call" notification.
///
/// Call [stop] only when the call actually ends (not on widget dispose).
class ActiveCallService {
  ActiveCallService._();

  static const _channel = MethodChannel('mednu/active_call');

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

  static Future<void> stop() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('stopForeground');
    } catch (e) {
      debugPrint('[ActiveCallService] stop error: $e');
    }
  }

  static void setEndCallFromNotificationHandler(Future<void> Function() handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onEndCallFromNotification') {
        await handler();
      }
    });
  }

  static void clearEndCallFromNotificationHandler() {
    _channel.setMethodCallHandler(null);
  }
}
