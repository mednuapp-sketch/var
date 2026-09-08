import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'physio_presence_task.dart';

/// Manages a physiotherapist partner's realtime online/offline presence —
/// the same architecture as `PresenceService` (doctors) and
/// `AmbulancePresenceService`, targeting `physiotherapist_profiles`:
/// • Foreground (app visible): Flutter `Timer.periodic` heartbeat every 60 s.
/// • Background (app minimised / screen locked): Android Foreground Service
///   keeps a Dart isolate alive that continues sending heartbeats even when
///   the Flutter engine is suspended.
/// • Killed / detached: `onDestroy` in [PhysioPresenceTaskHandler] marks the
///   partner offline as the service is stopped by the OS.
///
/// Unlike Ambulance, this only ever tracks the online/offline bit — no GPS
/// tracking is involved (sessions don't depend on live location).
class PhysioPresenceService with WidgetsBindingObserver {
  PhysioPresenceService._();
  static final PhysioPresenceService instance = PhysioPresenceService._();

  Timer? _heartbeatTimer;
  String? _uid;
  bool _isOnline = false;

  static const _heartbeatInterval = Duration(seconds: 60);

  void init(String uid) {
    _uid = uid;
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> dispose() async {
    _stopTimer();
    await _stopForegroundService();
    WidgetsBinding.instance.removeObserver(this);
  }

  bool get isOnline => _isOnline;

  Future<void> setOnline(bool online) async {
    _isOnline = online;
    if (online) {
      final uid = _uid;
      if (uid == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPhysioPresenceUidKey, uid);
      await _sendHeartbeat(online: true);
      _startTimer();
      await _startForegroundService();
    } else {
      _stopTimer();
      await _sendHeartbeat(online: false);
      await _stopForegroundService();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kPhysioPresenceUidKey);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        if (_isOnline) _stopTimer();
        break;
      case AppLifecycleState.resumed:
        if (_isOnline) {
          _sendHeartbeat(online: true);
          _startTimer();
        }
        break;
      case AppLifecycleState.detached:
        if (_isOnline) {
          _stopTimer();
          _sendHeartbeat(online: false);
        }
        break;
      default:
        break;
    }
  }

  Future<void> _startForegroundService() async {
    try {
      await FlutterForegroundTask.startService(
        serviceId: 1003, // distinct from PresenceService's 1001 / AmbulancePresenceService's 1002.
        notificationTitle: 'MedNU Service — You are Online',
        notificationText: 'Patients looking for a physiotherapist can find you. Tap to return to app.',
        callback: physioPresenceTaskCallback,
      );
    } catch (_) {
      // Ignore — foreground service is a best-effort enhancement.
    }
  }

  Future<void> _stopForegroundService() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  void _startTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_isOnline) _sendHeartbeat(online: true);
    });
  }

  void _stopTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _sendHeartbeat({required bool online}) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('physiotherapist_profiles').doc(uid).update({
        'isOnline': online,
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Network error — next heartbeat tick will retry.
    }
  }
}
