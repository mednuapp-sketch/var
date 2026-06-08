import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/call_notification_service.dart';
import 'features/security/services/biometric_service.dart';
import 'features/security/screens/lock_screen.dart';
import 'features/health/services/health_notification_service.dart';
import 'core/widgets/offline_banner.dart';

class MedNUApp extends ConsumerStatefulWidget {
  const MedNUApp({super.key});

  @override
  ConsumerState<MedNUApp> createState() => _MedNUAppState();
}

class _MedNUAppState extends ConsumerState<MedNUApp>
    with WidgetsBindingObserver {
  bool _isLocked = false;
  bool _wentToBackground = false;
  bool _isAuthenticating = false;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot>? _notifSub;
  StreamSubscription<QuerySnapshot>? _incomingCallSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialNotifLoad = true;

  String? _lastAlertedCallId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialLock();
    _setupListeners();
  }

  void _setupListeners() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _notifSub?.cancel();
      _incomingCallSub?.cancel();
      _initialNotifLoad = true;
      _lastAlertedCallId = null;

      if (user == null) {
        FirebaseCrashlytics.instance.setUserIdentifier('');
        return;
      }

      FirebaseCrashlytics.instance.setUserIdentifier(user.uid);

      // ── Save FCM token for this patient ─────────────────────────────────
      _saveFcmToken(user.uid);

      // ── General notification pop-ups ────────────────────────────────────
      _notifSub = FirebaseFirestore.instance
          .collection('patient_notifications')
          .doc(user.uid)
          .collection('items')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .listen((snap) {
        if (_initialNotifLoad) {
          _initialNotifLoad = false;
          return;
        }
        for (final change in snap.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          final data =
              change.doc.data() as Map<String, dynamic>? ?? {};
          if (data['isRead'] == true) continue;
          final title = data['title'] as String? ?? 'MedNU';
          final body = data['body'] as String? ?? '';
          HealthNotificationService.showMedicalAlert(
              title: title, body: body);
        }
      });

      // ── Doctor-initiated incoming call listener ──────────────────────────
      // Watches for consultations where this patient is the callee
      // (callerType == 'doctor') and status is 'pending'.
      _incomingCallSub = FirebaseFirestore.instance
          .collection('consultations')
          .where('patientId', isEqualTo: user.uid)
          .where('callerType', isEqualTo: 'doctor')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots()
          .listen((snap) {
        if (!mounted || snap.docs.isEmpty) return;
        final doc = snap.docs.first;
        if (doc.id == _lastAlertedCallId) return;
        _lastAlertedCallId = doc.id;

        final data = doc.data();
        final doctorName = data['doctorName'] as String? ?? 'Doctor';
        final specialty = data['doctorSpecialty'] as String? ?? '';
        final consultationType =
            data['consultationType'] as String? ?? 'Video';

        // Show OS notification + ringtone
        CallNotificationService.showIncomingCall(
          doctorName: doctorName,
          specialty: specialty,
        );

        // Navigate to full-screen incoming call UI
        ref.read(appRouterProvider).push(
          AppRoutes.incomingCall,
          extra: {
            'consultationId': doc.id,
            'doctorName': doctorName,
            'doctorSpecialty': specialty,
            'consultationType': consultationType,
          },
        );
      });
    });
  }

  Future<void> _saveFcmToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      final db = FirebaseFirestore.instance;
      // Save to both collections: patients (used by consultation creation) and
      // users (used by Cloud Function fallback for doctor-initiated calls).
      await Future.wait([
        db.collection('patients').doc(uid).set({'fcmToken': token}, SetOptions(merge: true)),
        db.collection('users').doc(uid).set({'fcmToken': token}, SetOptions(merge: true)),
      ]);
    } catch (e) {
      debugPrint('[App] FCM token save failed: $e');
    }

    // Cancel any previous listener before creating a new one (prevents leak on
    // repeated sign-in / sign-out cycles).
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub =
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      try {
        final db = FirebaseFirestore.instance;
        await Future.wait([
          db.collection('patients').doc(uid).set({'fcmToken': newToken}, SetOptions(merge: true)),
          db.collection('users').doc(uid).set({'fcmToken': newToken}, SetOptions(merge: true)),
        ]);
      } catch (e) {
        debugPrint('[App] FCM token refresh save failed: $e');
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _notifSub?.cancel();
    _incomingCallSub?.cancel();
    _tokenRefreshSub?.cancel();
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
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'MedNU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
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
              OfflineBanner(child: child ?? const SizedBox.expand()),
              if (_isLocked)
                LockScreen(
                  onAuthStarted: () => _isAuthenticating = true,
                  onAuthEnded: () => _isAuthenticating = false,
                  onUnlocked: () {
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
