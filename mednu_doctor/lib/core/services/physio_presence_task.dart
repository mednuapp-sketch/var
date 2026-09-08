import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../firebase_options.dart';

// ── SharedPreferences key used by the background isolate ──────────────────────
// Mirrors `kPresenceUidKey` (doctor_presence_task.dart) — written by
// PhysioPresenceService before starting the foreground service so the
// background isolate (which cannot access FirebaseAuth) knows which
// physiotherapist to send heartbeats for.
const kPhysioPresenceUidKey = 'mednu_doctor_physio_presence_uid';

// ── Top-level entry point called by flutter_foreground_task ───────────────────
// Must be annotated with vm:entry-point so the Dart tree-shaker keeps it alive
// in release builds (it is invoked from a separate isolate, not from main()).
@pragma('vm:entry-point')
void physioPresenceTaskCallback() {
  FlutterForegroundTask.setTaskHandler(PhysioPresenceTaskHandler());
}

// ── Task handler — runs in a dedicated background isolate ─────────────────────
// Same shape as DoctorPresenceTaskHandler/AmbulancePresenceTaskHandler,
// targeting `physiotherapist_profiles` instead.
class PhysioPresenceTaskHandler extends TaskHandler {
  FirebaseFirestore? _db;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    _db = FirebaseFirestore.instance;
    await _sendHeartbeat();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) => _sendHeartbeat();

  // Called when the service is stopped (partner goes offline or app is
  // killed). Mark them offline so no ghost-online state is left in Firestore.
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    final uid = await _getUid();
    if (uid == null || uid.isEmpty) return;
    try {
      await _db?.collection('physiotherapist_profiles').doc(uid).update({
        'isOnline': false,
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _sendHeartbeat() async {
    final uid = await _getUid();
    if (uid == null || uid.isEmpty) return;
    try {
      await _db?.collection('physiotherapist_profiles').doc(uid).update({
        'isOnline': true,
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Network error — next tick will retry.
    }
  }

  Future<String?> _getUid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(kPhysioPresenceUidKey);
    } catch (_) {
      return null;
    }
  }
}
