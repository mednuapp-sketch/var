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
  final bool isLoading;

  const WaterTrackerState({
    this.todayLogs = const [],
    this.goalGlasses = 8,
    this.glassSizeMl = 250,
    this.remindersEnabled = false,
    this.reminderIntervalHours = 2,
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
    bool? isLoading,
  }) =>
      WaterTrackerState(
        todayLogs: todayLogs ?? this.todayLogs,
        goalGlasses: goalGlasses ?? this.goalGlasses,
        glassSizeMl: glassSizeMl ?? this.glassSizeMl,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        reminderIntervalHours: reminderIntervalHours ?? this.reminderIntervalHours,
        isLoading: isLoading ?? this.isLoading,
      );
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class WaterTrackerNotifier extends StateNotifier<WaterTrackerState> {
  WaterTrackerNotifier() : super(const WaterTrackerState()) {
    _uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid != null) _init();
  }

  static final _db = FirebaseFirestore.instance;
  String? _uid;

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

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    await Future.wait([_loadSettings(), _loadTodayLogs()]);
    state = state.copyWith(isLoading: false);
    // Reschedule on every app open — Android clears alarms after reboot.
    if (state.remindersEnabled) {
      await HealthNotificationService.scheduleWaterReminders(state.reminderIntervalHours);
    }
  }

  // Re-fetches settings + today's logs without the isLoading flip, so
  // pull-to-refresh doesn't flash a skeleton over already-visible data.
  Future<void> refresh() => Future.wait([_loadSettings(), _loadTodayLogs()]);

  Future<void> _loadSettings() async {
    if (_settingsRef == null) return;
    try {
      final snap = await _settingsRef!.get();
      if (!snap.exists) return;
      final d = snap.data();
      if (d == null) return;
      state = state.copyWith(
        goalGlasses: d['goalGlasses'] as int? ?? 8,
        glassSizeMl: d['glassSizeMl'] as int? ?? 250,
        remindersEnabled: d['remindersEnabled'] as bool? ?? false,
        reminderIntervalHours: d['reminderIntervalHours'] as int? ?? 2,
      );
    } catch (_) {}
  }

  Future<void> _loadTodayLogs() async {
    if (_todayLogRef == null) return;
    try {
      final snap = await _todayLogRef!.get();
      if (!snap.exists) return;
      final rawLogs = snap.data()?['logs'] as List? ?? [];
      final logs = rawLogs.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        return WaterLog(
          loggedAt: (m['loggedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          amountMl: m['amountMl'] as int? ?? 250,
        );
      }).toList();
      state = state.copyWith(todayLogs: logs);
    } catch (_) {}
  }

  // ─── Public API ─────────────────────────────────────────────────────────

  Future<void> logWater() async {
    if (_uid == null || state.goalReached) return;
    final ref = _todayLogRef;
    if (ref == null) return;
    final newLog = WaterLog(loggedAt: DateTime.now(), amountMl: state.glassSizeMl);
    final updated = [...state.todayLogs, newLog];
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
    } catch (_) {}
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
      // 1. Notification permission (Android 13+)
      final notifGranted =
          await HealthNotificationService.requestNotificationPermission();
      if (!notifGranted) return false;

      // 2. Exact alarm permission — best-effort request (opens settings on Android 12)
      if (!await HealthNotificationService.hasExactAlarmPermission()) {
        await HealthNotificationService.requestExactAlarmPermission();
      }

      state = state.copyWith(remindersEnabled: true);
      await _saveSettings();
      await HealthNotificationService.scheduleWaterReminders(state.reminderIntervalHours);
      return true;
    } else {
      state = state.copyWith(remindersEnabled: false);
      await _saveSettings();
      await HealthNotificationService.cancelWaterReminders();
      return true;
    }
  }

  Future<void> setReminderInterval(int hours) async {
    state = state.copyWith(reminderIntervalHours: hours);
    await _saveSettings();
    if (state.remindersEnabled) {
      await HealthNotificationService.scheduleWaterReminders(hours);
    }
  }

  Future<void> _saveSettings() async {
    if (_settingsRef == null) return;
    try {
      await _settingsRef!.set({
        'goalGlasses': state.goalGlasses,
        'glassSizeMl': state.glassSizeMl,
        'remindersEnabled': state.remindersEnabled,
        'reminderIntervalHours': state.reminderIntervalHours,
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final waterTrackerProvider =
    StateNotifierProvider<WaterTrackerNotifier, WaterTrackerState>(
  (ref) => WaterTrackerNotifier(),
);
