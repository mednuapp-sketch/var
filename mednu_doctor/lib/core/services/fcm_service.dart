import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
    'new_equipment_order',
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
    await syncTokenForCurrentUser(force: true);

    // Watch auth state so a sign-in on a new phone re-registers immediately.
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) return;
      syncTokenForCurrentUser(force: true);
    });

    // Keep the token current if Firebase rotates it.
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) {
      syncTokenForCurrentUser(force: true, knownToken: newToken);
    }, onError: (Object e) {
      dev.log('[FCM] onTokenRefresh error: $e', name: 'FcmService');
    });

    // Re-assert the token whenever the app returns to the foreground (covers
    // failed/offline earlier writes and a token that changed while we were
    // in the background).
    if (!_lifecycleRegistered) {
      _lifecycleRegistered = true;
      WidgetsBinding.instance.addObserver(_ResumeObserver());
    }
  }

  // ── Real-time token sync ──────────────────────────────────────────────────

  static bool _lifecycleRegistered = false;
  static bool _syncing = false;
  static bool _dirty = true; // last attempt failed / never ran → retry
  static String? _lastUid;
  static DateTime? _lastSyncAt;
  static const _resumeMinInterval = Duration(minutes: 30);

  static String get _platform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return defaultTargetPlatform.name;
    }
  }

  /// Collections that may hold this account's partner profile, derived from
  /// `doctors/{uid}.roles`. Care Assistant shares `caregiver_profiles`.
  static List<String> _profileCollections(List roles) {
    final out = <String>{};
    for (final r in roles) {
      if (r is! String || r == 'doctor' || r == 'admin') continue;
      out.add(r == 'care_assistant' ? 'caregiver_profiles' : '${r}_profiles');
    }
    return out.toList();
  }

  /// Writes this device's token to `doctors/{uid}` and every role profile the
  /// account holds. Safe to call at any time; never throws. When [force] is
  /// false (app resume) it is skipped if the last sync succeeded recently.
  /// A failed attempt marks the sync dirty so the next trigger retries.
  static Future<void> syncTokenForCurrentUser({
    bool force = false,
    String? knownToken,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_syncing) {
      _dirty = true; // run again on the next trigger
      return;
    }
    if (!force &&
        !_dirty &&
        _lastUid == uid &&
        _lastSyncAt != null &&
        DateTime.now().difference(_lastSyncAt!) < _resumeMinInterval) {
      return;
    }
    _syncing = true;
    try {
      final token = knownToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null) {
        _dirty = true;
        return;
      }
      final ok = await _saveToken(uid, token);
      _dirty = !ok;
      if (ok) {
        _lastUid = uid;
        _lastSyncAt = DateTime.now();
      }
    } catch (e) {
      _dirty = true;
      dev.log('[FCM] token sync failed (will retry): $e', name: 'FcmService');
    } finally {
      _syncing = false;
    }
  }

  /// Called right BEFORE sign-out (needs the auth session to write): removes
  /// this device's token from the account's docs (only where it is still this
  /// device's token — a newer phone's token is never wiped) and invalidates
  /// the token on this device so a logged-out phone stops getting partner
  /// pushes. Best effort and time-boxed so logout is never blocked.
  static Future<void> clearTokenOnSignOut() async {
    try {
      await _clearTokenOnSignOut().timeout(const Duration(seconds: 8));
    } catch (e) {
      dev.log('[FCM] clear token on sign-out failed: $e', name: 'FcmService');
    }
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(const Duration(seconds: 5));
    } catch (e) {
      dev.log('[FCM] deleteToken failed: $e', name: 'FcmService');
    }
    _lastUid = null;
    _lastSyncAt = null;
    _dirty = true;
  }

  static Future<void> _clearTokenOnSignOut() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    final db = FirebaseFirestore.instance;
    final doctorRef = db.collection('doctors').doc(uid);
    List roles = const [];
    try {
      final snap = await doctorRef.get();
      roles = (snap.data()?['roles'] as List?) ?? const [];
    } catch (_) {}
    final refs = <DocumentReference<Map<String, dynamic>>>[
      doctorRef,
      for (final c in _profileCollections(roles)) db.collection(c).doc(uid),
    ];
    for (final ref in refs) {
      try {
        final s = await ref.get();
        if (!s.exists || s.data()?['fcmToken'] != token) continue;
        await ref.update({
          'fcmToken': FieldValue.delete(),
          'fcmTokenUpdatedAt': FieldValue.delete(),
          'fcmPlatform': FieldValue.delete(),
        });
      } catch (e) {
        dev.log('[FCM] clear token on ${ref.path} failed: $e', name: 'FcmService');
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns true when every doc that exists accepted the write (a missing
  /// doc is not a failure — profile docs are never created just for a token).
  static Future<bool> _saveToken(String uid, String token) async {
    final db = FirebaseFirestore.instance;
    final payload = <String, dynamic>{
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      'fcmPlatform': _platform,
    };
    var ok = true;

    Future<void> write(DocumentReference<Map<String, dynamic>> ref) async {
      try {
        // update(), not set(merge) — must never create a partial doc (a
        // premature doctors/{uid} breaks the later registration write).
        await ref.update(payload);
      } on FirebaseException catch (e) {
        if (e.code == 'not-found') return; // registration still in progress
        ok = false; // permission-denied / unavailable / etc → retry later
        dev.log('[FCM] token write to ${ref.path} failed (${e.code}); will retry',
            name: 'FcmService');
      } catch (e) {
        ok = false;
        dev.log('[FCM] token write to ${ref.path} failed: $e; will retry',
            name: 'FcmService');
      }
    }

    final doctorRef = db.collection('doctors').doc(uid);
    List roles = const [];
    try {
      final snap = await doctorRef.get();
      roles = (snap.data()?['roles'] as List?) ?? const [];
    } catch (e) {
      ok = false;
      dev.log('[FCM] could not read roles (will retry): $e', name: 'FcmService');
    }

    await write(doctorRef);
    for (final c in _profileCollections(roles)) {
      await write(db.collection(c).doc(uid));
    }
    return ok;
  }
}

class _ResumeObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FcmService.syncTokenForCurrentUser();
    }
  }
}
