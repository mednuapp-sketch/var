import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'core/router/app_router.dart';
import 'features/health/services/health_notification_service.dart';
import 'core/services/call_notification_service.dart';
import 'core/services/crash_reporting_service.dart';

// FCM background/terminated handler — runs in a separate Dart isolate.
// Must re-initialise Firebase because isolates do not share state.
// Guard with Firebase.apps.isEmpty so a hot-restart in debug mode
// does not trigger the "already initialised" assertion.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  }
  await CallNotificationService.init();
  if (message.data['type'] == 'incoming_doctor_call') {
    await CallNotificationService.showIncomingCall(
      doctorName: message.data['doctorName'] ?? 'Doctor',
      specialty: message.data['doctorSpecialty'] ?? '',
    );
  }
}

// Local notifications plugin instance
final _localNotifications = FlutterLocalNotificationsPlugin();

// Android notification channel for FCM high-importance alerts
const _androidChannel = AndroidNotificationChannel(
  'mednu_default_channel',
  'MedNU Notifications',
  description: 'Appointment reminders, service updates and health alerts',
  importance: Importance.high,
  playSound: true,
);

Future<void> _initFCM() async {
  final messaging = FirebaseMessaging.instance;

  // Request permission (iOS + Android 13+)
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );

  // Register background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Create Android notification channel
  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_androidChannel);

  // Init local notifications plugin
  await _localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;
      final ctx = appNavigatorKey.currentContext;
      if (ctx == null) return;
      // Route based on notification payload type
      if (payload.startsWith('appointment:')) {
        ctx.go(AppRoutes.appointment);
      } else if (payload.startsWith('consultation:')) {
        ctx.go(AppRoutes.consultation);
      } else if (payload.startsWith('health:')) {
        ctx.go(AppRoutes.healthDashboard);
      } else if (payload.startsWith('prescription:')) {
        ctx.go(AppRoutes.prescriptionViewer);
      } else if (payload.startsWith('water_reminder')) {
        ctx.go(AppRoutes.waterReminder);
      } else if (payload.startsWith('period_tracker')) {
        ctx.go(AppRoutes.periodTracker);
      } else {
        ctx.go(AppRoutes.notifications);
      }
    },
  );

  // Show incoming call notification for doctor-initiated calls (foreground)
  FirebaseMessaging.onMessage.listen((message) {
    if (message.data['type'] == 'incoming_doctor_call') {
      CallNotificationService.showIncomingCall(
        doctorName: message.data['doctorName'] ?? 'Doctor',
        specialty: message.data['doctorSpecialty'] ?? '',
      );
      return;
    }

    // Show local notification when app is in foreground
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  });

  // iOS foreground presentation options
  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
}

void main() {
  // Run everything inside a zone to catch all uncaught async errors
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // ── Global Flutter framework error handler ──────────────
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        CrashReportingService.recordFlutterError(details);
        if (!kDebugMode) {
          FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        }
      };

      // ── Unhandled platform dispatcher errors ────────────────
      PlatformDispatcher.instance.onError = (error, stack) {
        CrashReportingService.recordError(error, stack, fatal: false);
        if (!kDebugMode) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
        }
        return true; // swallow to prevent force-close
      };

      // ── Firebase init ────────────────────────────────────────
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // ── Firestore offline persistence (serve cached data instantly) ─
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      // ── Parallelise all post-Firebase init work ───────────────
      // App Check, FCM, notification services, and localisation
      // are independent of each other — run them concurrently to
      // cut cold-start time by ~600-900 ms.
      await Future.wait([
        FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.playIntegrity,
          appleProvider: AppleProvider.appAttest,
        ),
        _initFCM(),
        CallNotificationService.init(),
        HealthNotificationService.init(),
        EasyLocalization.ensureInitialized(),
      ]);

      // ── Lock to portrait ─────────────────────────────────────
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      // ── Status bar style ─────────────────────────────────────
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );

      runApp(
        EasyLocalization(
          supportedLocales: const [
            Locale('en'),
            Locale('te'), // Telugu
            Locale('hi'), // Hindi
          ],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          child: const ProviderScope(
            child: MedNUApp(),
          ),
        ),
      );
    },
    (error, stack) {
      CrashReportingService.recordError(error, stack, fatal: true);
      if (!kDebugMode) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
    },
  );
}
