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
import 'package:app_links/app_links.dart';
import 'package:easy_localization/easy_localization.dart';
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

  // Incoming call from a provider (doctor, physiotherapist, or counsellor)
  // — show full-screen call UI even when killed.
  if (type == 'incoming_doctor_call') {
    await CallNotificationService.init();
    await CallNotificationService.showIncomingCall(
      doctorName: message.data['doctorName'] ?? 'Doctor',
      specialty:  message.data['doctorSpecialty'] ?? '',
      providerRole: message.data['providerRole'] ?? 'doctor',
    );
    return;
  }

  // All other types: only manually show a local heads-up notification for
  // truly data-only messages. Messages that already carry a top-level
  // `notification` payload (the vast majority — see functions/index.js
  // _sendPatientNotification) are auto-displayed by the OS in background/
  // killed state; calling show() again here would double-post the same alert.
  if (message.notification == null && (title.isNotEmpty || body.isNotEmpty)) {
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
      'providerRole':    data['providerRole']    ?? 'doctor',
    });
    return;
  }

  // Route by explicit actionType first (most specific).
  switch (actionType) {
    case 'open_call':
      ctx.go(AppRoutes.consultation);
      return;
    case 'open_prescription':
      _openPrescriptionFromNotification(ctx, data['bookingId'] as String? ?? '');
      return;
    case 'open_order':
      _goMedicineOrder(ctx, data);
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
      // The real pharmacy order pipeline (onMedicineOrderCreated in
      // functions/index.js) sends actionType:'open_service',
      // serviceType:'medicine' with a real order id in `bookingId` —
      // _serviceRouteFromType('medicine') has no order id and previously
      // always landed on the medicine shopping catalogue instead of the
      // order itself (e.g. a "please upload your prescription" push).
      if (serviceType.toLowerCase() == 'medicine') {
        _goMedicineOrder(ctx, data);
        return;
      }
      ctx.go(_serviceRouteFromType(serviceType));
      return;
  }

  // Fallback: route by notification type string.
  if (type.startsWith('appointment_') || type == 'appointment_reminder') {
    ctx.go(AppRoutes.appointment);
  } else if (type.startsWith('medicine_') ||
      type.startsWith('pharmacy_') ||
      (type.startsWith('prescription_') && type != 'prescription_uploaded') ||
      type == 'order_update') {
    _goMedicineOrder(ctx, data);
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
    _openPrescriptionFromNotification(ctx, data['bookingId'] as String? ?? '');
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

/// Routes a medicine/pharmacy order notification to the specific order
/// (`AppRoutes.orderDetail`, backed by the real `orders` collection via
/// `orderDetailProvider`) when `data['bookingId']` names one, falling back to
/// the real orders list otherwise. Replaces landing on either a fake generic
/// tracker with hardcoded placeholder data, or the medicine shopping
/// catalogue — see functions/index.js's onMedicineOrderCreated, which sets
/// `bookingId: orderId` for every pharmacy order-status push.
void _goMedicineOrder(BuildContext ctx, Map<String, dynamic> data) {
  final orderId = data['bookingId'] as String? ?? '';
  if (orderId.isNotEmpty) {
    ctx.go(AppRoutes.orderDetail, extra: {'orderId': orderId});
  } else {
    ctx.go(AppRoutes.medicineOrders);
  }
}

/// Fetches the real prescription doc linked to [appointmentId] (the
/// notification's `bookingId` — see `_sendPatientNotification` in
/// functions/index.js, which sets `bookingId: apptId` for the
/// `prescription_uploaded` status change) before navigating.
///
/// PrescriptionViewerScreen has no fetch-by-id fallback of its own: pushing
/// its route with no `extra` renders every field on a placeholder ('RX-0000',
/// empty diagnosis/medicines) instead of the real prescription — this was the
/// case for every "Prescription Ready" push tap. `write_prescription_screen
/// .dart` stores the originating appointment id as `prescriptions
/// .appointmentId`, so that's the lookup key.
Future<void> _openPrescriptionFromNotification(
  BuildContext ctx,
  String appointmentId,
) async {
  Map<String, dynamic>? rx;
  if (appointmentId.isNotEmpty) {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('prescriptions')
          .where('appointmentId', isEqualTo: appointmentId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        rx = {...snap.docs.first.data(), 'id': snap.docs.first.id};
      }
    } catch (_) {}
  }
  if (!ctx.mounted) return;
  if (rx != null) {
    ctx.go(AppRoutes.prescriptionViewer, extra: rx);
  } else {
    // No linked prescription found (missing bookingId, deleted doc, or the
    // query failed) — land on Records instead of a blank placeholder viewer.
    ctx.go(AppRoutes.records);
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
/// terms-acceptance / MPIN screen) the link is dropped, but now with an
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

/// Handles the `mednu://join?a=<appointmentId>&t=<token>&exp=<epochSeconds>`
/// deep link — a family member tapping the "guest join" link shared from
/// the appointment screen (see createGuestJoinLink in functions/index.js and
/// _ShareGuestLinkButton in appointment_screen.dart).
///
/// Unlike _handleFcmNavigation, this deliberately does NOT require an
/// existing session — the whole point of a guest link is that the family
/// member has no MedNU login. It waits for the app to leave the splash
/// screen (so it doesn't get immediately overwritten by splash's own
/// ~1.5s-delayed context.go — see _navigateOnLaunchNotification above for
/// the same race on the FCM side) but, unlike that FCM path, does NOT wait
/// for the user to be authenticated or past login/OTP/MPIN — a guest may
/// never pass through any of those.
Future<void> _handleGuestDeepLink(Uri uri) async {
  if (uri.host != 'join') return;
  final appointmentId = uri.queryParameters['a'];
  final token = uri.queryParameters['t'];
  final exp = int.tryParse(uri.queryParameters['exp'] ?? '');
  if (appointmentId == null || appointmentId.isEmpty ||
      token == null || token.isEmpty || exp == null) {
    CrashReportingService.log('Malformed guest join link: $uri', tag: 'DeepLink');
    return;
  }

  const pollInterval = Duration(milliseconds: 150);
  const window = Duration(seconds: 6);
  final deadline = DateTime.now().add(window);

  while (DateTime.now().isBefore(deadline)) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null) {
      var location = AppRoutes.splash;
      try {
        // ignore: use_build_context_synchronously
        location = GoRouter.of(ctx).routerDelegate.currentConfiguration.uri.path;
      } catch (_) {
        location = AppRoutes.splash; // Router not ready yet — keep waiting.
      }
      if (location != AppRoutes.splash) {
        // ignore: use_build_context_synchronously
        ctx.go(AppRoutes.guestJoin, extra: {
          'appointmentId': appointmentId,
          'token': token,
          'exp': exp,
        });
        return;
      }
    }
    await Future.delayed(pollInterval);
  }

  CrashReportingService.log(
    'Guest join deep link dropped — navigator/route not ready after '
    '${window.inSeconds}s',
    tag: 'DeepLink',
  );
}

Future<void> _initDeepLinks() async {
  final appLinks = AppLinks();
  try {
    final initial = await appLinks.getInitialLink();
    if (initial != null && initial.scheme == 'mednu') {
      unawaited(_handleGuestDeepLink(initial));
    }
  } catch (e) {
    CrashReportingService.log('getInitialLink failed: $e', tag: 'DeepLink');
  }
  appLinks.uriLinkStream.listen((uri) {
    if (uri.scheme == 'mednu') {
      unawaited(_handleGuestDeepLink(uri));
    }
  }, onError: (e) {
    CrashReportingService.log('uriLinkStream error: $e', tag: 'DeepLink');
  });
}

String _serviceRouteFromType(String serviceType) {
  switch (serviceType.toLowerCase()) {
    case 'appointment':   return AppRoutes.appointment;
    // Fallback only (no bookingId) — _goMedicineOrder handles the real-order
    // case. The real orders list, not the fake tracker or the shopping
    // catalogue.
    case 'medicine':      return AppRoutes.medicineOrders;
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

    // Provider-initiated incoming call — show full-screen call overlay.
    if (type == 'incoming_doctor_call') {
      CallNotificationService.showIncomingCall(
        doctorName: message.data['doctorName'] ?? 'Doctor',
        specialty:  message.data['doctorSpecialty'] ?? '',
        providerRole: message.data['providerRole'] ?? 'doctor',
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

      // ── App Check + localisation ──────────────────────────────
      // These two are the only pre-runApp async steps left blocking the
      // first frame: App Check gates every Firestore/Functions call made
      // right after launch (including the splash screen's own read), and
      // EasyLocalization's data is read synchronously by the
      // EasyLocalization widget below (no loading builder is configured for
      // it). FCM, call/health notification setup, and deep-link listener
      // registration used to block here too — moved below, after runApp(),
      // since none of them gate the first frame and their setup can be
      // network-bound (App Check's own Play Integrity/App Attest fetch is
      // the same story, but activate() itself only configures the provider;
      // token fetch happens lazily per-request afterwards).
      await Future.wait([
        FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode
              ? AndroidProvider.debug
              : AndroidProvider.playIntegrity,
          appleProvider: kDebugMode
              ? AppleProvider.debug
              : AppleProvider.appAttest,
        ),
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

      // Deferred to after the first frame: the notification permission
      // prompt (see _requestNotificationPermission()), plus FCM/call/health
      // notification setup and deep-link listener registration — none of
      // these gate the first frame, and running them here instead of in the
      // blocking Future.wait above means a slow/flaky network can no longer
      // delay the app's very first paint. The terminated-tap FCM handler and
      // guest deep-link handler both already poll for splash to hand off
      // before navigating (see _navigateOnLaunchNotification /
      // _handleGuestDeepLink above), so registering their listeners a few
      // hundred ms later than before is harmless.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_requestNotificationPermission());
        unawaited(Future.wait([
          _initFCM(),
          CallNotificationService.init(),
          HealthNotificationService.init(),
          _initDeepLinks(),
        ]));
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
