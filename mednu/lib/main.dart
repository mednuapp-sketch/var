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
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'core/router/app_router.dart';
import 'features/health/services/health_notification_service.dart';
import 'core/services/call_notification_service.dart';
import 'core/services/crash_reporting_service.dart';

// FCM background/terminated handler — runs in a separate Dart isolate.
// Must re-initialise Firebase because isolates do not share state.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  }

  final type  = message.data['type'] as String? ?? '';
  final title = message.notification?.title ?? message.data['title'] as String? ?? '';
  final body  = message.notification?.body  ?? message.data['body']  as String? ?? '';

  // Incoming call from doctor — show full-screen call UI even when killed.
  if (type == 'incoming_doctor_call') {
    await CallNotificationService.init();
    await CallNotificationService.showIncomingCall(
      doctorName: message.data['doctorName'] ?? 'Doctor',
      specialty:  message.data['doctorSpecialty'] ?? '',
    );
    return;
  }

  // All other types: show a local heads-up notification so the user is
  // alerted even when the FCM message has no top-level notification payload
  // (e.g. data-only messages from Cloud Functions or admin broadcasts).
  if (title.isNotEmpty || body.isNotEmpty) {
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'mednu_default_channel',
          'MedNU Notifications',
          importance: Importance.high,
        ));
    await _localNotifications.show(
      type.hashCode,
      title.isNotEmpty ? title : 'MedNu',
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'mednu_default_channel',
          'MedNU Notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}

// Local notifications plugin instance
final _localNotifications = FlutterLocalNotificationsPlugin();

/// Routes the user to the correct screen when they tap an FCM notification.
/// Works for background taps (onMessageOpenedApp), terminated taps
/// (getInitialMessage), and local notification taps (onDidReceiveNotificationResponse).
/// [data] is the FCM data map or the pipe-split local-notification payload.
void _handleFcmNavigation(Map<String, dynamic> data) {
  final ctx = appNavigatorKey.currentContext;
  if (ctx == null) return;

  final type        = data['type']        as String? ?? '';
  final serviceType = data['serviceType'] as String? ?? '';
  final actionType  = data['actionType']  as String? ?? '';

  // Incoming call: go straight to the incoming call screen.
  if (type == 'incoming_doctor_call') {
    ctx.go(AppRoutes.incomingCall, extra: {
      'doctorName':      data['doctorName']      ?? 'Doctor',
      'doctorSpecialty': data['doctorSpecialty'] ?? '',
      'consultationId':  data['consultationId']  ?? '',
      'doctorPhotoUrl':  data['doctorPhotoUrl']  ?? '',
    });
    return;
  }

  // Route by explicit actionType first (most specific).
  switch (actionType) {
    case 'open_call':
      ctx.go(AppRoutes.consultation);
      return;
    case 'open_prescription':
      ctx.go(AppRoutes.prescriptionViewer);
      return;
    case 'open_order':
      ctx.go(AppRoutes.orderTracking);
      return;
    case 'open_diagnostics':
      ctx.go(AppRoutes.diagnostics);
      return;
    case 'open_ambulance':
      ctx.go(AppRoutes.ambulance);
      return;
    case 'open_appointment':
      ctx.go(AppRoutes.appointment);
      return;
    case 'open_pregnancy':
      ctx.go(AppRoutes.pregnancyCheckups);
      return;
    case 'open_service':
      ctx.go(_serviceRouteFromType(serviceType));
      return;
  }

  // Fallback: route by notification type string.
  if (type.startsWith('appointment_') || type == 'appointment_reminder') {
    ctx.go(AppRoutes.appointment);
  } else if (type.startsWith('medicine_') || type == 'order_update') {
    ctx.go(AppRoutes.orderTracking);
  } else if (type.startsWith('lab_') || type.startsWith('diagnostics_')) {
    ctx.go(AppRoutes.diagnostics);
  } else if (type.startsWith('ambulance_')) {
    ctx.go(AppRoutes.ambulance);
  } else if (type.startsWith('homecare_') || type.startsWith('caregiver_')) {
    ctx.go(AppRoutes.caregivers);
  } else if (type.startsWith('physio_')) {
    ctx.go(AppRoutes.physio);
  } else if (type.startsWith('hospital_')) {
    ctx.go(AppRoutes.hospitals);
  } else if (type.startsWith('pregnancy_')) {
    ctx.go(AppRoutes.pregnancyCheckups);
  } else if (type.startsWith('nutrition_')) {
    ctx.go(AppRoutes.nutrition);
  } else if (type.startsWith('quickconnect_')) {
    ctx.go(AppRoutes.consultation);
  } else if (type == 'prescription_uploaded') {
    ctx.go(AppRoutes.prescriptionViewer);
  } else if (type == 'consultation_done' || type == 'followup_day1' || type == 'followup_day2') {
    ctx.go(AppRoutes.postConsultation);
  } else if (type == 'water_reminder') {
    ctx.go(AppRoutes.waterReminder);
  } else if (type == 'period_tracker') {
    ctx.go(AppRoutes.periodTracker);
  } else if (type == 'review_prompt') {
    ctx.go(AppRoutes.submitReview);
  } else {
    ctx.go(AppRoutes.notifications);
  }
}

String _serviceRouteFromType(String serviceType) {
  switch (serviceType.toLowerCase()) {
    case 'appointment':   return AppRoutes.appointment;
    case 'medicine':      return AppRoutes.orderTracking;
    case 'diagnostics':
    case 'lab':           return AppRoutes.diagnostics;
    case 'ambulance':     return AppRoutes.ambulance;
    case 'home_care':
    case 'caregiver':     return AppRoutes.caregivers;
    case 'physiotherapy': return AppRoutes.physio;
    case 'hospital':      return AppRoutes.hospitals;
    case 'pregnancy':     return AppRoutes.pregnancyCheckups;
    case 'nutrition':     return AppRoutes.nutrition;
    case 'quick_connect': return AppRoutes.consultation;
    case 'counselling':   return AppRoutes.careAssistant;
    default:              return AppRoutes.myServices;
  }
}

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

  // On Android, request battery optimization exemption so that OEM power
  // managers (MIUI, ColorOS, FuntouchOS, OneUI, etc.) do not block FCM
  // wake-ups when the app is swiped away or killed by the system.
  // The system dialog only appears if the user hasn't granted it yet.
  if (defaultTargetPlatform == TargetPlatform.android) {
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

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
      final raw = response.payload;
      if (raw == null || raw.isEmpty) return;
      // Payload format: "type|serviceType|bookingId|actionType"
      // (written by the foreground onMessage handler above)
      final parts = raw.split('|');
      _handleFcmNavigation({
        'type':        parts.isNotEmpty ? parts[0] : '',
        'serviceType': parts.length > 1 ? parts[1] : '',
        'bookingId':   parts.length > 2 ? parts[2] : '',
        'actionType':  parts.length > 3 ? parts[3] : '',
      });
    },
  );

  // Foreground FCM handler — app is open and in the foreground.
  FirebaseMessaging.onMessage.listen((message) {
    final type = message.data['type'] ?? '';

    // Doctor-initiated incoming call — show full-screen call overlay.
    if (type == 'incoming_doctor_call') {
      CallNotificationService.showIncomingCall(
        doctorName: message.data['doctorName'] ?? 'Doctor',
        specialty:  message.data['doctorSpecialty'] ?? '',
      );
      return;
    }

    // All other notification types: show as local heads-up notification.
    // The Firestore stream already updates the in-app notification center
    // in realtime, so the heads-up banner is the only extra step needed here.
    final n = message.notification;
    final title = n?.title ?? message.data['title'] ?? '';
    final body  = n?.body  ?? message.data['body']  ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final serviceType = message.data['serviceType'] ?? '';
    final bookingId   = message.data['bookingId']   ?? '';
    final actionType  = message.data['actionType']  ?? '';

    // Build a compact payload so the tap handler can deep-link correctly.
    final payload = '$type|$serviceType|$bookingId|$actionType';

    _localNotifications.show(
      // Use a stable ID so duplicate pushes replace rather than stack.
      (type + bookingId).hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance:       Importance.high,
          priority:         Priority.high,
          icon:             '@mipmap/ic_launcher',
          playSound:        true,
          enableVibration:  true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  });

  // Background tap — user tapped the system notification while app was backgrounded.
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    _handleFcmNavigation(message.data);
  });

  // Terminated tap — user tapped a notification that launched the app from killed.
  final initial = await messaging.getInitialMessage();
  if (initial != null) {
    // Delay to let the navigator finish mounting.
    Future.delayed(const Duration(milliseconds: 800), () {
      _handleFcmNavigation(initial.data);
    });
  }

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
        if (!kDebugMode)
          FirebaseAppCheck.instance.activate(
            androidProvider: AndroidProvider.playIntegrity,
            appleProvider: AppleProvider.appAttest,
          )
        else
          Future.value(),
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
