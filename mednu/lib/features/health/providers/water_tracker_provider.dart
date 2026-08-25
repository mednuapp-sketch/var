import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/health_notification_service.dart';

// ─── Model ──────────────────────────────────────────────────────────────────

class WaterLog {
  final DateTime loggedAt;
  final int amountMl;
  const WaterLog({required this.loggedAt, required this.amountMl});
}

// ─── State ───────────────────────────────────────────────────────────────────

class WaterTrackerState {
  final List<WaterLog> todayLogs;
  final int goalGlasses;
  final int glassSizeMl;
  final bool remindersEnabled;
  final int reminderIntervalHours; // 1, 2, or 3
  final int reminderStartHour;
  final int reminderStartMinute;
  final bool isLoading;

  const WaterTrackerState({
    this.todayLogs = const [],
    this.goalGlasses = 8,
    this.glassSizeMl = 250,
    this.remindersEnabled = false,
    this.reminderIntervalHours = 2,
    this.reminderStartHour = 8,
    this.reminderStartMinute = 0,
    this.isLoading = false,
  });

  int get totalMl => todayLogs.fold(0, (s, l) => s + l.amountMl);
  int get glassesLogged => todayLogs.length;
  double get progress =>
      goalGlasses > 0 ? (glassesLogged / goalGlasses).clamp(0.0, 1.0) : 0.0;
  int get goalMl => goalGlasses * glassSizeMl;
  bool get goalReached => glassesLogged >= goalGlasses;

  WaterTrackerState copyWith({
    List<WaterLog>? todayLogs,
    int? goalGlasses,
    int? glassSizeMl,
    bool? remindersEnabled,
    int? reminderIntervalHours,
    int? reminderStartHour,
    int? reminderStartMinute,
    bool? isLoading,
  }) =>
      WaterTrackerState(
        todayLogs: todayLogs ?? this.todayLogs,
        goalGlasses: goalGlasses ?? this.goalGlasses,
        glassSizeMl: glassSizeMl ?? this.glassSizeMl,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        reminderIntervalHours: reminderIntervalHours ?? this.reminderIntervalHours,
        reminderStartHour: reminderStartHour ?? this.reminderStartHour,
        reminderStartMinute: reminderStartMinute ?? this.reminderStartMinute,
        isLoading: isLoading ?? this.isLoading,
      );
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class WaterTrackerNotifier extends StateNotifier<WaterTrackerState> {
  WaterTrackerNotifier() : super(const WaterTrackerState()) {
    // Listen to auth state instead of reading currentUser once — on a cold
    // start Firebase Auth restores the session asynchronously, so reading
    // currentUser in the constructor can race and leave _uid stuck at null,
    // which made logs silently fail to load *and* fail to save.
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  static final _db = FirebaseFirestore.instance;
  String? _uid;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _logsSub;

  static String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  DocumentReference<Map<String, dynamic>>? get _settingsRef => _uid == null
      ? null
      : _db
          .collection('health_data')
          .doc(_uid)
          .collection('settings')
          .doc('water');

  DocumentReference<Map<String, dynamic>>? get _todayLogRef => _uid == null
      ? null
      : _db
          .collection('health_data')
          .doc(_uid)
          .collection('water_logs')
          .doc(_today);

  void _onAuthChanged(User? user) {
    final newUid = user?.uid;
    if (newUid == _uid) return;
    _uid = newUid;
    _settingsSub?.cancel();
    _logsSub?.cancel();
    if (newUid == null) {
      state = const WaterTrackerState();
      return;
    }
    _listen();
  }

  // Live Firestore listeners (not one-shot reads) so logging a glass on one
  // screen — or another device — is reflected everywhere immediately, and
  // reopening this screen always shows current server state instead of a
  // stale in-memory snapshot from before the app was backgrounded.
  void _listen() {
    state = state.copyWith(isLoading: true);

    _settingsSub = _settingsRef!.snapshots().listen((snap) {
      final d = snap.data();
      if (d != null) {
        state = state.copyWith(
          goalGlasses: d['goalGlasses'] as int? ?? 8,
          glassSizeMl: d['glassSizeMl'] as int? ?? 250,
          remindersEnabled: d['remindersEnabled'] as bool? ?? false,
          reminderIntervalHours: d['reminderIntervalHours'] as int? ?? 2,
          reminderStartHour: d['reminderStartHour'] as int? ?? 8,
          reminderStartMinute: d['reminderStartMinute'] as int? ?? 0,
        );
      }
    }, onError: (_) {});

    _logsSub = _todayLogRef!.snapshots().listen((snap) {
      final rawLogs = snap.data()?['logs'] as List? ?? [];
      final logs = rawLogs.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        return WaterLog(
          loggedAt: (m['loggedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          amountMl: m['amountMl'] as int? ?? 250,
        );
      }).toList();
      state = state.copyWith(todayLogs: logs, isLoading: false);
    }, onError: (_) => state = state.copyWith(isLoading: false));
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _settingsSub?.cancel();
    _logsSub?.cancel();
    super.dispose();
  }

  // ─── Public API ─────────────────────────────────────────────────────────

  Future<void> logWater() async {
    if (_uid == null || state.goalReached) return;
    final ref = _todayLogRef;
    if (ref == null) return;
    final previousLogs = state.todayLogs;
    final newLog = WaterLog(loggedAt: DateTime.now(), amountMl: state.glassSizeMl);
    final updated = [...previousLogs, newLog];
    state = state.copyWith(todayLogs: updated);
    try {
      await ref.set({
        'date': _today,
        'logs': updated
            .map((l) => {
                  'loggedAt': Timestamp.fromDate(l.loggedAt),
                  'amountMl': l.amountMl,
                })
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Firestore write failed — roll back the optimistic update so the UI
      // doesn't show a "saved" log that never actually persisted.
      state = state.copyWith(todayLogs: previousLogs);
    }
  }

  Future<void> setGlassSizeMl(int ml) async {
    state = state.copyWith(glassSizeMl: ml);
    await _saveSettings();
  }

  Future<void> setGoalGlasses(int goal) async {
    state = state.copyWith(goalGlasses: goal);
    await _saveSettings();
  }

  Future<bool> setRemindersEnabled(bool enabled) async {
    if (enabled) {
      // Notification permission (Android 13+) — still required even though
      // firing is server-driven now, since the OS needs it to display any
      // notification at all, local or push.
      final notifGranted =
          await HealthNotificationService.requestNotificationPermission();
      if (!notifGranted) return false;

      state = state.copyWith(remindersEnabled: true);
      await _saveSettings();
      return true;
    } else {
      state = state.copyWith(remindersEnabled: false);
      await _saveSettings();
      return true;
    }
  }

  Future<void> setReminderInterval(int hours) async {
    state = state.copyWith(reminderIntervalHours: hours);
    await _saveSettings();
  }

  Future<void> setReminderStartTime(int hour, int minute) async {
    state = state.copyWith(reminderStartHour: hour, reminderStartMinute: minute);
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    if (_settingsRef == null) return;
    try {
      await _settingsRef!.set({
        'goalGlasses': state.goalGlasses,
        'glassSizeMl': state.glassSizeMl,
        'remindersEnabled': state.remindersEnabled,
        'reminderIntervalHours': state.reminderIntervalHours,
        'reminderStartHour': state.reminderStartHour,
        'reminderStartMinute': state.reminderStartMinute,
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final waterTrackerProvider =
    StateNotifierProvider<WaterTrackerNotifier, WaterTrackerState>(
  (ref) => WaterTrackerNotifier(),
);
