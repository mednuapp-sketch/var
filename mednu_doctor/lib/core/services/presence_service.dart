import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'doctor_presence_task.dart';

/// Manages the doctor's realtime online/offline presence.
///
/// Architecture:
/// • Foreground (app visible): Flutter `Timer.periodic` heartbeat every 60 s.
/// • Background (app minimised / screen locked): Android Foreground Service via
///   `flutter_foreground_task`.  The service keeps a Dart isolate alive that
///   continues sending heartbeats even when the Flutter engine is suspended.
/// • Killed / detached: `onDestroy` in [DoctorPresenceTaskHandler] marks the
///   doctor offline as the service is stopped by the OS.
///
/// Key behaviour change from the previous implementation:
/// Going to the BACKGROUND no longer marks the doctor offline.  The foreground
/// service takes over heartbeat responsibility so the doctor remains visible to
/// patients while using other apps.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  Timer? _heartbeatTimer;
  String? _uid;
  bool _isOnline = false;

  // Flutter-side heartbeat interval.  Patient app considers > 3 min stale.
  static const _heartbeatInterval = Duration(seconds: 60);

  // ── Setup / teardown ───────────────────────────────────────────────────────

  void init(String uid) {
    _uid = uid;
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> dispose() async {
    _stopTimer();
    await _stopForegroundService();
    WidgetsBinding.instance.removeObserver(this);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  bool get isOnline => _isOnline;

  Future<void> setOnline(bool online) async {
    _isOnline = online;
    if (online) {
      final uid = _uid;
      if (uid == null) return;
      // Persist UID so the background isolate can read it from SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPresenceUidKey, uid);
      // Immediate heartbeat from the Flutter isolate.
      await _sendHeartbeat(online: true);
      // Start timer for when app is in foreground.
      _startTimer();
      // Start the Android Foreground Service for background heartbeats.
      await _startForegroundService();
    } else {
      _stopTimer();
      await _sendHeartbeat(online: false);
      // Stop the Android Foreground Service — its onDestroy also marks offline.
      await _stopForegroundService();
      // Clear persisted UID so a stale service restart doesn't ghost us.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kPresenceUidKey);
    }
  }

  // ── App lifecycle ──────────────────────────────────────────────────────────
  // KEY CHANGE: We no longer mark the doctor offline when the app is paused.
  // The foreground service continues heartbeats in the background.
  // We only stop heartbeats / mark offline when the app is truly detached
  // (force-killed by the OS after the service has already been stopped).

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // App moved to background — foreground service takes over.
        // Stop the Flutter-side timer to avoid duplicate heartbeats.
        if (_isOnline) _stopTimer();
        break;

      case AppLifecycleState.resumed:
        // App returned to foreground — Flutter timer resumes.
        if (_isOnline) {
          _sendHeartbeat(online: true);
          _startTimer();
        }
        break;

      case AppLifecycleState.detached:
        // App is being killed (after the OS has already removed the foreground
        // service).  Best-effort offline write.
        if (_isOnline) {
          _stopTimer();
          _sendHeartbeat(online: false);
        }
        break;

      default:
        break;
    }
  }

  // ── Foreground service ─────────────────────────────────────────────────────

  Future<void> _startForegroundService() async {
    try {
      await FlutterForegroundTask.startService(
        serviceId: 1001,
        notificationTitle: 'MedNU Doctor — You are Online',
        notificationText: 'Patients can find you. Tap to return to app.',
        callback: presenceTaskCallback,
      );
      // If the service failed to start (rare — e.g. battery-optimisation block),
      // the Flutter-side timer above remains as a foreground-only fallback.
    } catch (_) {
      // Ignore — foreground service is a best-effort enhancement.
    }
  }

  Future<void> _stopForegroundService() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  // ── Flutter-side heartbeat timer ───────────────────────────────────────────

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

  // ── Firestore write ────────────────────────────────────────────────────────

  Future<void> _sendHeartbeat({required bool online}) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('doctors').doc(uid).update({
        'isOnline': online,
        // acceptingConsultations mirrors isOnline so Quick Connect queries
        // can filter on a dedicated field without conflating presence with
        // availability. Both fields are always written together.
        'acceptingConsultations': online,
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Network error — next heartbeat tick will retry.
    }
  }
}
