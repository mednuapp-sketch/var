import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
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
      title.isNotEmpty ? title : 'MedNU',
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

  // Every deep-link target below is an authenticated-only route, and several
  // (incomingCall in particular) replace the whole navigation stack. If the
  // session isn't confirmed yet, navigating there would drop the user onto a
  // screen whose providers have no uid to read — bail out and leave the
  // normal splash/login flow in charge.
  if (FirebaseAuth.instance.currentUser == null) {
    CrashReportingService.log(
      'FCM deep link ignored — no authenticated user (type=${data['type']})',
      tag: 'FCM',
    );
    return;
  }

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

/// Routes that mean "the app hasn't handed the user to their real landing
/// screen yet" — splash is still deciding, or the user is mid-auth. A launch
/// deep link fired while one of these is on screen would either be
/// immediately overwritten by splash's own `context.go(...)` or would bypass
/// the MPIN/OTP gate, so we wait for the app to leave them instead.
const _preLandingRoutes = <String>{
  AppRoutes.splash,
  AppRoutes.onboarding,
  AppRoutes.login,
  AppRoutes.otp,
  AppRoutes.register,
  AppRoutes.mpin,
  AppRoutes.createMpin,
};

/// Handles a deep link from a notification tap that launched the app from a
/// terminated state.
///
/// Previously this was a single fixed `Future.delayed(800ms)` followed by a
/// one-shot `appNavigatorKey.currentContext` null check, which silently
/// dropped the deep link on a slow cold start — and, because the splash
/// screen performs its own `context.go(...)` ~1.5 s after launch, an 800 ms
/// deep link was also liable to be overwritten by splash a moment later.
///
/// This polls on a short interval within a bounded window for the navigator
/// to be mounted *and* the app to have left the pre-landing routes, then
/// navigates once. It reduces — it does not eliminate — the drop rate: if
/// the window elapses (very slow device, or the user is sitting on the
/// medical-disclaimer / MPIN screen) the link is dropped, but now with an
/// explicit warning so the failure mode is observable in Crashlytics rather
/// than silent.
Future<void> _navigateOnLaunchNotification(Map<String, dynamic> data) async {
  const pollInterval = Duration(milliseconds: 150);
  // Generous relative to splash's own ~1.5 s hand-off, but still bounded.
  const window = Duration(seconds: 6);
  final deadline = DateTime.now().add(window);

  while (DateTime.now().isBefore(deadline)) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null) {
      String location;
      try {
        // ctx is re-read from the global navigator key on every iteration,
        // so it is always current — not a stale across-async-gap context.
        // ignore: use_build_context_synchronously
        final router = GoRouter.of(ctx);
        location = router.routerDelegate.currentConfiguration.uri.path;
      } catch (_) {
        location = AppRoutes.splash; // Router not ready yet — keep waiting.
      }
      if (!_preLandingRoutes.contains(location)) {
        // App has landed. _handleFcmNavigation applies its own auth guard.
        _handleFcmNavigation(data);
        return;
      }
    }
    await Future.delayed(pollInterval);
  }

  CrashReportingService.log(
    'Launch deep link dropped — navigator/route not ready after '
    '${window.inSeconds}s (type=${data['type']}, '
    'actionType=${data['actionType']})',
    tag: 'FCM',
  );
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

  // NOTE: the notification permission prompt is deliberately NOT requested
  // here. Awaiting a system permission dialog before runApp() blocks the
  // first frame, so a cold start shows a blank window until the user answers.
  // It is requested from _requestNotificationPermission() after the first
  // frame instead. Battery-optimization exemption is likewise handled by
  // BatteryOptimizationService.promptIfNeeded() (post-login, once ever) —
  // requesting it here as well double-prompted on every cold start.

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
    unawaited(_navigateOnLaunchNotification(initial.data));
  }

  // iOS foreground presentation options
  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
}

/// Notification permission prompt (iOS + Android 13+). Called after the first
/// frame so the system dialog never appears over a blank window.
Future<void> _requestNotificationPermission() async {
  try {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
  } catch (_) {
    // Non-critical — never block app usage over this.
  }
}

void main() {
  // Run everything inside a zone to catch all uncaught async errors
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // TEMP DIAGNOSTIC: force Hybrid Composition (real embedded SurfaceView)
      // for Google Maps instead of the default Texture/Virtual-Display mode,
      // whose backing SurfaceTexture was observed disconnecting the instant
      // a drag gesture starts (onCameraMoveStarted -> Surface::disconnect),
      // freezing the map on interaction.
      final mapsImplementation = GoogleMapsFlutterPlatform.instance;
      if (mapsImplementation is GoogleMapsFlutterAndroid) {
        mapsImplementation.useAndroidViewSurface = true;
      }

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
          androidProvider: kDebugMode
              ? AndroidProvider.debug
              : AndroidProvider.playIntegrity,
          appleProvider: kDebugMode
              ? AppleProvider.debug
              : AppleProvider.appAttest,
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

      // Deferred to after the first frame — see _initFCM().
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_requestNotificationPermission());
      });
    },
    (error, stack) {
      CrashReportingService.recordError(error, stack, fatal: true);
      if (!kDebugMode) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
    },
  );
}
