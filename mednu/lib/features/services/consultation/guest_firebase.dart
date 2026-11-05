import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// A second, independent Firebase app used only for guest-link calls.
///
/// Firebase Auth keeps exactly one signed-in user per app, so signing in with
/// the guest custom token on the default app used to replace — and then sign
/// out — whoever was logged in to their own MedNU account on this device. The
/// guest session lives here instead, leaving the default app's login alone:
/// joining a call via a link works the same whether or not the person is
/// signed in, like joining a Google Meet link.
class GuestFirebase {
  GuestFirebase._();

  static const _appName = 'guest_session';

  /// Creates the guest app on first use. Must complete before touching
  /// [auth], [firestore] or [functions].
  static Future<void> ensureInitialized() async {
    try {
      Firebase.app(_appName);
      return;
    } catch (_) {
      // Not created yet.
    }
    final app = await Firebase.initializeApp(
      name: _appName,
      options: Firebase.app().options,
    );
    try {
      await FirebaseAppCheck.instanceFor(app: app).activate(
        androidProvider:
            kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider:
            kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
      );
    } catch (e) {
      debugPrint('[GuestFirebase] App Check activation failed: $e');
    }
  }

  static FirebaseApp get _app => Firebase.app(_appName);

  static FirebaseAuth get auth => FirebaseAuth.instanceFor(app: _app);
  static FirebaseFirestore get firestore =>
      FirebaseFirestore.instanceFor(app: _app);
  static FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(app: _app);
}
