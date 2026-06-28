import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

// ── SETUP REQUIRED ──────────────────────────────────────────────────────────
// 1. Firebase Console → Project Settings → Cloud Messaging → Web Push certificates
// 2. Click "Generate key pair" (or add existing key)
// 3. Copy the Key pair value and paste it below replacing the placeholder.
const _vapidKey = 'BLmu6pUBnb50n2Mv92hv-vXjvTY6jNMAAyMiritoMgf-OJoeah1QzEJr52PlckIgRedC4Q6TiK-lPHzD8np4jmo';
// ─────────────────────────────────────────────────────────────────────────────

typedef MessageHandler = void Function(RemoteMessage message);

class FcmService {
  FcmService._();

  static MessageHandler? _foregroundHandler;

  static Future<void> init({MessageHandler? onForegroundMessage}) async {
    if (!kIsWeb) return;

    _foregroundHandler = onForegroundMessage;

    final messaging = FirebaseMessaging.instance;

    // Request browser notification permission
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[FCM] Notification permission denied by user.');
      return;
    }

    // Register token whenever auth state changes (login / logout)
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      await _registerToken(messaging, user.uid);
    });

    // Refresh token if it rotates
    messaging.onTokenRefresh.listen((token) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await _saveToken(uid, token);
    });

    // Handle messages while the app is in the foreground
    FirebaseMessaging.onMessage.listen((message) {
      _foregroundHandler?.call(message);
    });

    // Handle tap on notification that opened the app from background
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _foregroundHandler?.call(message);
    });
  }

  static Future<void> _registerToken(FirebaseMessaging messaging, String uid) async {
    try {
      // vapidKey is required for web push
      final token = await messaging.getToken(vapidKey: _vapidKey);
      if (token == null) return;
      await _saveToken(uid, token);
    } catch (e) {
      debugPrint('[FCM] Token registration failed: $e');
    }
  }

  static Future<void> _saveToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'fcmTokenWeb': token, 'fcmTokenWebUpdatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      debugPrint('[FCM] Web token saved for $uid');
    } catch (e) {
      debugPrint('[FCM] Failed to save token: $e');
    }
  }
}
