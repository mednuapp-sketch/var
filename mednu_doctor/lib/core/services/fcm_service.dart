import 'dart:async';
import 'dart:developer' as dev;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'call_notification_service.dart';

/// Manages Firebase Cloud Messaging for the doctor app.
///
/// Responsibilities:
///  - Request notification permission on first run.
///  - Persist the FCM token to `doctors/{uid}/fcmToken` so the Cloud
///    Function can target the correct device when a patient books.
///  - Handle foreground FCM messages (show local call notification).
///  - Refresh the token whenever Firebase rotates it.
class FcmService {
  FcmService._();

  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<User?>? _authSub;

  /// Call once from [main] after Firebase is initialized.
  static Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    // Request permission (required on iOS; shows dialog on Android 13+).
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
      announcement: false,
      carPlay: false,
      provisional: false,
    );

    final granted = settings.authorizationStatus == AuthorizationStatus.authorized
        || settings.authorizationStatus == AuthorizationStatus.provisional;
    dev.log('[FCM] Permission status: ${settings.authorizationStatus}', name: 'FcmService');

    if (!granted) {
      dev.log('[FCM] Notifications denied — skipping token registration', name: 'FcmService');
      return;
    }

    // Save token when the user is already signed in at startup.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final token = await messaging.getToken();
      if (token != null) await _saveToken(uid, token);
    }

    // Watch auth state so we always save a fresh token after login.
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      final token = await messaging.getToken();
      if (token != null) await _saveToken(user.uid, token);
    });

    // Keep the token current if Firebase rotates it.
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
      final uid2 = FirebaseAuth.instance.currentUser?.uid;
      if (uid2 != null) await _saveToken(uid2, newToken);
    });

    // Foreground messages: FCM delivers data payloads silently when the app
    // is open, so we show a local call notification ourselves.
    FirebaseMessaging.onMessage.listen((message) {
      final type = message.data['type'];
      if (type == 'incoming_consultation') {
        CallNotificationService.showIncomingCall(
          patientName: message.data['patientName'] ?? 'Patient',
          complaint: message.data['complaint'] ?? '',
        );
      } else if (type == 'emergency_doctor_request') {
        CallNotificationService.showEmergencyAlert(
          patientName: message.data['patientName'] ?? 'Patient',
          requestId: message.data['requestId'] ?? '',
        );
      }
    });

    // Background tap: the user tapped the FCM notification while the app
    // was backgrounded. The Firestore listener in main.dart will pick up
    // the pending consultation and route automatically — no extra work needed.
    FirebaseMessaging.onMessageOpenedApp.listen((_) {});

    // Terminated tap: same as above; the listener re-connects on startup.
    await messaging.getInitialMessage();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<void> _saveToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance
          .collection('doctors')
          .doc(uid)
          .update({'fcmToken': token});
    } catch (_) {
      // Doc doesn't exist yet (new registration in progress) — the token will
      // be included in saveProfile() when the doctor document is first created.
      // Do NOT create the doc here; a premature partial doc causes the
      // subsequent saveProfile() set(merge:true) to be treated as an update,
      // which is blocked by Firestore rules because it sets the 'status' field.
    }
  }
}
