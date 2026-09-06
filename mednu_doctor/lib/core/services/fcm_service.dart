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

  /// `type` values used by the pool-vertical "new job created" pushes
  /// (`_broadcastNewJobToActiveProviders`/pinned `_sendProviderNotification`
  /// calls in functions/index.js) — kept as one set so the foreground
  /// handler below doesn't need a branch per vertical.
  static const _newJobTypes = {
    'new_lab_booking',
    'new_pharmacy_order',
    'new_ambulance_request',
    'new_caregiver_visit',
    'new_physio_session',
    'new_counselling_session',
  };

  /// Call once from [main] after Firebase is initialized. Deliberately does
  /// NOT request notification permission — awaiting that system dialog
  /// before runApp() blocks the first frame, leaving a blank window until
  /// the user answers. Message listeners are safe to register immediately;
  /// permission is requested separately via [requestPermissionAndRegisterToken]
  /// after the first frame (see main.dart), matching the patient app's pattern.
  static Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

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
      } else if (type == 'partner_approved') {
        CallNotificationService.showGenericNotification(
          title: message.notification?.title ?? 'Application Approved',
          body: message.notification?.body ??
              'Your MedNU partner account is verified — you can start receiving bookings now.',
          type: type,
        );
      } else if (_newJobTypes.contains(type)) {
        // These land via `_sendProviderNotification`/`_broadcastNewJobToActiveProviders`
        // (functions/index.js) — the same "new job" pushes that already show a
        // system notification when the app is backgrounded/killed. Without this
        // branch a provider foregrounded on a *different* screen would miss it
        // entirely: the incoming-requests streams behind each vertical's list
        // are `.autoDispose`, so they aren't even live unless that exact screen
        // is open — the Firestore bell record alone isn't enough to get their
        // attention in the moment.
        CallNotificationService.showGenericNotification(
          title: message.notification?.title ?? 'New Job Available',
          body: message.notification?.body ?? 'A new booking is available.',
          type: type,
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

  /// Requests notification permission and registers the FCM token. Call this
  /// from a post-first-frame callback (see main.dart) so the system
  /// permission dialog never blocks the initial render.
  static Future<void> requestPermissionAndRegisterToken() async {
    final messaging = FirebaseMessaging.instance;

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

    // Save token when the user is already signed in.
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
    await _saveTokenToRoleProfiles(uid, token);
  }

  /// Also keeps the token fresh on every non-Doctor role profile this
  /// account holds (`lab_profiles`, `pharmacy_profiles`, etc.) — the
  /// Cloud Function that pushes a "your application was approved"
  /// notification reads `fcmToken` straight off that document, not
  /// `doctors/{uid}`, so a token rotated after registration would
  /// otherwise go stale there and the push would silently fail to deliver.
  static Future<void> _saveTokenToRoleProfiles(String uid, String token) async {
    try {
      final doctorSnap =
          await FirebaseFirestore.instance.collection('doctors').doc(uid).get();
      final roles =
          (doctorSnap.data()?['roles'] as List?)?.cast<String>() ?? const [];
      for (final role in roles) {
        if (role == 'doctor') continue;
        try {
          await FirebaseFirestore.instance
              .collection('${role}_profiles')
              .doc(uid)
              .update({'fcmToken': token});
        } catch (_) {
          // Role profile doesn't exist yet (registration in progress) —
          // createProfile() already writes the token at creation time.
        }
      }
    } catch (_) {
      // Couldn't read roles (offline, doc missing) — safe to skip; the
      // token captured at registration still covers most of the pending
      // window.
    }
  }
}
