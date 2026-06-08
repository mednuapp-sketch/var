import 'dart:async';
import 'dart:ui';
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
import 'core/theme/app_theme.dart';
import 'features/security/services/biometric_service.dart';
import 'features/security/screens/lock_screen.dart';

// ── Background FCM handler ────────────────────────────────────────────────────
// Runs in a separate Dart isolate when the app is terminated/backgrounded.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CallNotificationService.init();
  if (message.data['type'] == 'incoming_consultation') {
    await CallNotificationService.showIncomingCall(
      patientName: message.data['patientName'] ?? 'Patient',
      complaint:   message.data['complaint']   ?? '',
    );
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
        androidProvider: AndroidProvider.playIntegrity,
        appleProvider: AppleProvider.appAttest,
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
      if (user != null) _setupCallListener();
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

  // ── Global Firestore call listener ─────────────────────────────────────────
  // A consultation is considered "fresh" only if it was created within the
  // last 90 seconds. Older pending docs are stale leftovers from previous
  // sessions and must never trigger the incoming call screen.
  static const _kFreshWindowSeconds = 90;

  void _setupCallListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

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
  }

  @override
  void dispose() {
    _callSub?.cancel();
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title:                    'MedNU Doctor',
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
