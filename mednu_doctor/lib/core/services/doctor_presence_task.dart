import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../firebase_options.dart';

// ── SharedPreferences key used by the background isolate ──────────────────────
// Written by PresenceService before starting the foreground service so the
// background isolate (which cannot access FirebaseAuth) knows which doctor to
// send heartbeats for.
const kPresenceUidKey = 'mednu_doctor_presence_uid';

// ── Top-level entry point called by flutter_foreground_task ─────────���─────────
// Must be annotated with vm:entry-point so the Dart tree-shaker keeps it alive
// in release builds (it is invoked from a separate isolate, not from main()).
@pragma('vm:entry-point')
void presenceTaskCallback() {
  FlutterForegroundTask.setTaskHandler(DoctorPresenceTaskHandler());
}

// ── Task handler — runs in a dedicated background isolate ───────────────���─────
class DoctorPresenceTaskHandler extends TaskHandler {
  FirebaseFirestore? _db;

  // Called once when the background isolate starts.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // The background isolate has its own Dart VM — Firebase must be initialised
    // here independently of the main isolate.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    _db = FirebaseFirestore.instance;
    // Send an immediate heartbeat as soon as the service launches so the doctor
    // appears online instantly even before the first repeat tick.
    await _sendHeartbeat();
  }

  // Called on every repeat tick (every 60 s).
  @override
  Future<void> onRepeatEvent(DateTime timestamp) => _sendHeartbeat();

  // Called when the service is stopped (doctor goes offline or app is killed).
  // Mark the doctor as offline so no ghost-online state is left in Firestore.
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    final uid = await _getUid();
    if (uid == null || uid.isEmpty) return;
    try {
      await _db?.collection('doctors').doc(uid).update({
        'isOnline': false,
        'acceptingConsultations': false,
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _sendHeartbeat() async {
    final uid = await _getUid();
    if (uid == null || uid.isEmpty) return;
    try {
      await _db?.collection('doctors').doc(uid).update({
        'isOnline': true,
        'acceptingConsultations': true,
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Network error — next tick will retry.
    }
  }

  Future<String?> _getUid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(kPresenceUidKey);
    } catch (_) {
      return null;
    }
  }
}
