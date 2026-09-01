import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'core/router/app_router.dart';
import 'core/services/appointment_reminder_service.dart';
import 'core/services/call_notification_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/presence_service.dart';
import 'core/services/battery_optimization_service.dart';
import 'core/theme/app_theme.dart';
import 'features/security/services/biometric_service.dart';
import 'features/security/screens/lock_screen.dart';
import 'core/widgets/active_session_bridge.dart';
import 'shared_core/models/app_role.dart';
import 'shared_core/providers/role_providers.dart';
import 'features/lab/providers/lab_providers.dart';
import 'features/pharmacy/providers/pharmacy_providers.dart';
import 'features/ambulance/providers/ambulance_providers.dart';
import 'features/caregiver/providers/caregiver_providers.dart';
import 'features/physiotherapy/providers/physio_providers.dart';
import 'features/counselling/providers/counselling_providers.dart';
import 'features/nutrition/providers/nutrition_providers.dart';

// ── Background FCM handler ────────────────────────────────────────────────────
// Runs in a separate Dart isolate when the app is terminated/backgrounded.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CallNotificationService.init();

  final type = message.data['type'] as String? ?? '';

  if (type == 'incoming_consultation') {
    await CallNotificationService.showIncomingCall(
      patientName: message.data['patientName'] ?? 'Patient',
      complaint:   message.data['complaint']   ?? '',
    );
    return;
  }

  if (type == 'emergency_doctor_request') {
    await CallNotificationService.showEmergencyAlert(
      patientName: message.data['patientName'] ?? 'Patient',
      requestId:   message.data['requestId']   ?? '',
    );
    return;
  }

  // All other types: only manually show a local notification for truly
  // data-only messages. Messages that already carry a top-level
  // `notification` payload are auto-displayed by the OS in background/
  // killed state; calling this again here would double-post the same alert.
  final title = message.notification?.title ?? message.data['title'] as String? ?? '';
  final body  = message.notification?.body  ?? message.data['body']  as String? ?? '';
  if (message.notification == null && (title.isNotEmpty || body.isNotEmpty)) {
    await CallNotificationService.showGenericNotification(title: title, body: body, type: type);
  }
}

// ── Stale status cleanup ──────────────────────────────────────────────────────
Future<void> _clearStaleOnlineStatus() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('doctors')
          .doc(uid)
          .update({'isOnline': false});
    }
  } catch (_) {}
}

// ── flutter_foreground_task one-time setup ────────────────────────────────────
void _initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId:          'doctor_online_service',
      channelName:        'Doctor Online Service',
      channelImportance:  NotificationChannelImportance.LOW,
      priority:           NotificationPriority.LOW,
      showWhen:           false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound:        false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction:   ForegroundTaskEventAction.repeat(60000), // every 60 s
      autoRunOnBoot: false,
      allowWakeLock: false,
      allowWifiLock: true,
    ),
  );
}

// ── Entry point ───────────────────────────────────────────────────────────────
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialise the foreground task communication port before runApp.
    FlutterForegroundTask.initCommunicationPort();

    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // ── Firestore offline persistence ───────────────────────────────────────
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // ── Crashlytics error hooks (sync — must be before any async work) ──────
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
      return true;
    };

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // ── Parallelise all post-Firebase init work ─────────────────────────────
    // App Check, call/FCM/reminder services are independent — run concurrently
    // to cut cold-start time by ~500-800 ms.
    await Future.wait([
      FirebaseAppCheck.instance.activate(
        androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
      ),
      CallNotificationService.init(),
      FcmService.init(),
      AppointmentReminderService.init(),
    ]);

    _initForegroundTask();

    // Fire-and-forget: clearing stale online status is best-effort cleanup
    // — don't block app launch waiting for this Firestore write.
    _clearStaleOnlineStatus();

    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:        Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    runApp(const ProviderScope(child: MedNUDoctorApp()));

    // Deferred to after the first frame so the notification-permission
    // system dialog never blocks the initial render on cold start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FcmService.requestPermissionAndRegisterToken();
    });
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

// ── Root widget ───────────────────────────────────────────────────────────────
class MedNUDoctorApp extends ConsumerStatefulWidget {
  const MedNUDoctorApp({super.key});

  @override
  ConsumerState<MedNUDoctorApp> createState() => _MedNUDoctorAppState();
}

class _MedNUDoctorAppState extends ConsumerState<MedNUDoctorApp>
    with WidgetsBindingObserver {
  bool _isLocked          = false;
  bool _wentToBackground  = false;
  bool _isAuthenticating  = false;

  StreamSubscription<QuerySnapshot>? _callSub;
  StreamSubscription<QuerySnapshot>? _scheduledWaitingSub;
  StreamSubscription<User?>?         _authStateSub;
  String? _lastAlertedConsultId;

  static const _kAlertedConsultPrefKey = 'last_alerted_consult_id';

  /// Persists the alerted consultation ID so it survives app restarts.
  /// On relaunch, if the same pending doc is still in Firestore (i.e., the
  /// doctor didn't respond), it is auto-marked missed instead of re-alerting.
  Future<void> _saveAlertedId(String id) async {
    _lastAlertedConsultId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAlertedConsultPrefKey, id);
  }

  Future<void> _loadAlertedId() async {
    final prefs = await SharedPreferences.getInstance();
    _lastAlertedConsultId = prefs.getString(_kAlertedConsultPrefKey);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialLock();

    // ── Handle FCM notification taps (backgrounded / killed) ────────────────
    FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmTap);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _handleFcmTap(message);
    });

    // Load the persisted alerted ID before subscribing to auth, so the
    // de-duplicate check is ready before the first Firestore snapshot fires.
    _initCallListener();
  }

  /// Awaits SharedPreferences load, then subscribes to auth state to set up
  /// the Firestore call listener. Ordering ensures the persisted ID is ready
  /// before any snapshot can arrive.
  Future<void> _initCallListener() async {
    await _loadAlertedId();
    if (!mounted) return;
    _authStateSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _setupCallListener();

        // ── Battery optimization whitelist prompt (Android, once ever) ────
        // Delayed so it never collides with the biometric lock screen or
        // other startup dialogs.
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) BatteryOptimizationService.promptIfNeeded(context);
        });
      } else {
        // User signed out — cancel all per-UID listeners immediately so we
        // don't keep live Firestore streams open for the previous account.
        _callSub?.cancel();
        _callSub = null;
        _scheduledWaitingSub?.cancel();
        _scheduledWaitingSub = null;
      }
    });
  }

  /// Route the doctor to the right screen based on the FCM notification data.
  void _handleFcmTap(RemoteMessage message) {
    final type = message.data['type'] as String? ?? '';
    final router = ref.read(appRouterProvider);
    switch (type) {
      case 'incoming_consultation':
        // Delay one frame so the router widget is mounted.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) router.go(AppRoutes.incomingRequest);
        });
        break;
      case 'appointment_reminder':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) router.go(AppRoutes.dashboard);
        });
        break;
      default:
        break;
    }
  }

  // ── Global Firestore call listeners ───────────────────────────────────────
  // Quick-connect pending calls expire after 90 s — stale docs from a previous
  // session must never re-alert the doctor on relaunch.
  static const _kFreshWindowSeconds = 90;
  // Scheduled-waiting consultations live for the full join window (30 min
  // after the slot) plus a small drift buffer.
  static const _kScheduledFreshWindowSeconds = 2400; // 40 min

  void _setupCallListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // ── Quick-connect / instant calls (callerType: patient, status: pending) ─
    _callSub?.cancel();
    _callSub = FirebaseFirestore.instance
        .collection('consultations')
        .where('doctorId',   isEqualTo: uid)
        .where('callerType', isEqualTo: 'patient')
        .where('status',     isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      // Ignore local-cache emissions — only trust server-confirmed data.
      if (!mounted || snap.metadata.isFromCache) return;
      if (snap.docs.isEmpty) return;

      final doc  = snap.docs.first;
      final data = doc.data();

      // Age guard: ignore consultations that are older than the fresh window.
      // This prevents stale pending docs from a previous app session from
      // instantly pushing the doctor to the incoming-call screen on launch.
      final createdAt = data['createdAt'];
      if (createdAt != null) {
        try {
          final created = (createdAt as Timestamp).toDate();
          if (DateTime.now().difference(created).inSeconds > _kFreshWindowSeconds) {
            return; // Stale — skip silently.
          }
        } catch (_) {
          // Timestamp parse failure — let it through so we don't miss a real call.
        }
      }

      // De-duplicate: only alert once per unique consultation document.
      // _lastAlertedConsultId is persisted in SharedPreferences so it
      // survives app restarts. If the doctor closed the app without
      // responding, the same pending doc will fire again on relaunch —
      // we mark it missed instead of re-showing the call screen.
      if (doc.id == _lastAlertedConsultId) {
        FirebaseFirestore.instance
            .collection('consultations')
            .doc(doc.id)
            .update({
          'status':           'missed',
          'missedAt':         FieldValue.serverTimestamp(),
          'missedReason':     'doctor_relaunched_without_response',
        }).catchError((_) {});
        return;
      }
      _saveAlertedId(doc.id);

      final patientName = data['patientName'] as String? ?? 'Patient';
      final complaint   = data['chiefComplaint'] as String? ?? '';

      CallNotificationService.showIncomingCall(
        patientName: patientName,
        complaint:   complaint,
      );
      ref.read(appRouterProvider).go(AppRoutes.incomingRequest);
    });

    // ── Scheduled appointments: patient entered waiting room ───────────────
    // Fires when the patient joins within the time window and creates a
    // consultation with status = 'scheduled_waiting'. The doctor is notified
    // regardless of which screen they are on and is taken to the dashboard
    // where the appointment card shows the "Patient is waiting" banner.
    _scheduledWaitingSub?.cancel();
    _scheduledWaitingSub = FirebaseFirestore.instance
        .collection('consultations')
        .where('doctorId', isEqualTo: uid)
        .where('status',   isEqualTo: 'scheduled_waiting')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      if (!mounted || snap.metadata.isFromCache) return;
      if (snap.docs.isEmpty) return;

      final doc  = snap.docs.first;
      final data = doc.data();

      // Freshness guard — covers the full 30-min appointment window.
      final createdAt = data['createdAt'];
      if (createdAt != null) {
        try {
          final created = (createdAt as Timestamp).toDate();
          if (DateTime.now().difference(created).inSeconds >
              _kScheduledFreshWindowSeconds) { return; }
        } catch (_) {}
      }

      // De-duplicate — same logic as the quick-connect listener.
      if (doc.id == _lastAlertedConsultId) return;
      _saveAlertedId(doc.id);

      final patientName = data['patientName'] as String? ?? 'Patient';
      CallNotificationService.showPatientWaiting(patientName: patientName);
      // Go to dashboard — the appointment card will show the
      // "Patient is in the waiting room" banner in real-time.
      ref.read(appRouterProvider).go(AppRoutes.dashboard);
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _scheduledWaitingSub?.cancel();
    _authStateSub?.cancel();
    PresenceService.instance.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkInitialLock() async {
    if (await BiometricService.isBiometricEnabled()) {
      if (mounted) setState(() => _isLocked = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused && !_isAuthenticating) {
      _wentToBackground = true;
      // PresenceService handles the background transition internally — do NOT
      // also mark offline here; that would create a race condition.
    } else if (state == AppLifecycleState.resumed && _wentToBackground) {
      _wentToBackground = false;
      if (await BiometricService.isBiometricEnabled()) {
        if (mounted) setState(() => _isLocked = true);
      }
      _refreshActiveRoleQueues();
    }
  }

  /// Safety net for the role dispatch queues after a resume.
  ///
  /// The role-scoped incoming-work streams (Lab bookings, Pharmacy orders,
  /// Ambulance requests, Caregiver visits) rely on the Firestore SDK's own
  /// reconnect after a long background/suspend. That is usually reliable,
  /// but for a live incoming-request queue "usually" is not enough: a stream
  /// that quietly stops delivering means the partner misses paid work with
  /// no visible sign anything is wrong.
  ///
  /// This is deliberately *not* a connectivity-monitoring system and not a
  /// replacement for the SDK's reconnect — it is a one-shot re-fetch of only
  /// the active role's incoming-request providers, alongside it. Riverpod
  /// retains the previous value across the invalidation, so watchers refresh
  /// in place rather than flashing a loading state.
  void _refreshActiveRoleQueues() {
    if (!mounted) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      switch (ref.read(roleEngineProvider).activeRole) {
        case AppRole.lab:
          ref.invalidate(availableBookingsProvider);
          ref.invalidate(sampleCollectionQueueProvider);
          break;
        case AppRole.pharmacy:
          ref.invalidate(availableOrdersProvider);
          ref.invalidate(prescriptionVerificationQueueProvider);
          break;
        case AppRole.ambulance:
          ref.invalidate(availableAmbulanceRequestsProvider);
          ref.invalidate(myAmbulanceRequestsProvider);
          break;
        case AppRole.caregiver:
          ref.invalidate(availableCaregiverVisitsProvider);
          ref.invalidate(myCaregiverVisitsProvider);
          break;
        case AppRole.physiotherapist:
          ref.invalidate(availablePhysioSessionsProvider);
          ref.invalidate(myPhysioSessionsProvider);
          break;
        case AppRole.counsellor:
          ref.invalidate(availableCounsellingSessionsProvider);
          ref.invalidate(myCounsellingSessionsProvider);
          break;
        case AppRole.nutritionist:
          ref.invalidate(myNutritionAppointmentsProvider);
          break;
        case AppRole.doctor:
        case AppRole.admin:
          // The Doctor role's incoming-call queue is not a Riverpod stream —
          // it is the raw `_setupCallListener` subscription above, whose
          // alert de-duplication has side effects (it marks an already
          // alerted pending consultation as missed). Re-subscribing here
          // could cancel a live incoming call, so it is left to the SDK's
          // own reconnect.
          break;
      }
    } catch (_) {
      // Never let a best-effort refresh surface as a crash on resume.
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title:                    'MedNU Service',
      debugShowCheckedModeBanner: false,
      theme:                    AppTheme.lightTheme,
      routerConfig:             router,
      builder: (context, child) {
        // Clamp system font scaling so layouts never overflow on large-text
        // accessibility settings, while still honouring small-scale reductions.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.0,
            ),
          ),
          child: Stack(
            children: [
              child ?? const SizedBox.expand(),
              ActiveSessionBridge(router: router),
              if (_isLocked)
                LockScreen(
                  onAuthStarted: () => _isAuthenticating = true,
                  onAuthEnded:   () => _isAuthenticating = false,
                  onUnlocked:    () {
                    _isAuthenticating = false;
                    if (mounted) setState(() => _isLocked = false);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
