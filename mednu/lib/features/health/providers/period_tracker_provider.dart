import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/health_notification_service.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class PeriodCycle {
  final String id;
  final DateTime startDate;
  final DateTime? endDate;
  final String flowLevel;

  const PeriodCycle({
    required this.id,
    required this.startDate,
    this.endDate,
    required this.flowLevel,
  });
}

// ─── State ───────────────────────────────────────────────────────────────────

class PeriodTrackerState {
  final PeriodCycle? currentCycle;
  final List<PeriodCycle> recentCycles;
  final List<String> todaySymptoms;
  final String? todayMood;
  final int avgCycleLength;
  final bool remindersEnabled;
  final int reminderDaysBefore;
  final bool isLoading;

  const PeriodTrackerState({
    this.currentCycle,
    this.recentCycles = const [],
    this.todaySymptoms = const [],
    this.todayMood,
    this.avgCycleLength = 28,
    this.remindersEnabled = false,
    this.reminderDaysBefore = 3,
    this.isLoading = false,
  });

  // ─── Computed ─────────────────────────────────────────────────────────────

  bool get hasCycle => currentCycle != null;

  int get cycleDay {
    if (currentCycle == null) return 0;
    return (DateTime.now().difference(currentCycle!.startDate).inDays + 1)
        .clamp(1, avgCycleLength);
  }

  DateTime? get nextPeriodDate {
    if (currentCycle == null) return null;
    return currentCycle!.startDate.add(Duration(days: avgCycleLength));
  }

  int get daysToNextPeriod {
    if (nextPeriodDate == null) return 0;
    return nextPeriodDate!.difference(DateTime.now()).inDays.clamp(0, avgCycleLength);
  }

  String get currentPhase {
    final day = cycleDay;
    if (day == 0) return 'Unknown';
    if (day <= 5) return 'Menstruation';
    if (day <= 13) return 'Follicular';
    if (day <= 16) return 'Ovulation';
    return 'Luteal';
  }

  bool get isInFertileWindow {
    final day = cycleDay;
    return day >= 12 && day <= 16;
  }

  PeriodTrackerState copyWith({
    PeriodCycle? currentCycle,
    List<PeriodCycle>? recentCycles,
    List<String>? todaySymptoms,
    String? todayMood,
    bool clearMood = false,
    int? avgCycleLength,
    bool? remindersEnabled,
    int? reminderDaysBefore,
    bool? isLoading,
  }) =>
      PeriodTrackerState(
        currentCycle: currentCycle ?? this.currentCycle,
        recentCycles: recentCycles ?? this.recentCycles,
        todaySymptoms: todaySymptoms ?? this.todaySymptoms,
        todayMood: clearMood ? null : (todayMood ?? this.todayMood),
        avgCycleLength: avgCycleLength ?? this.avgCycleLength,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
        isLoading: isLoading ?? this.isLoading,
      );
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class PeriodTrackerNotifier extends StateNotifier<PeriodTrackerState> {
  PeriodTrackerNotifier() : super(const PeriodTrackerState()) {
    _uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid != null) _init();
  }

  static final _db = FirebaseFirestore.instance;
  String? _uid;

  static String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  CollectionReference<Map<String, dynamic>>? get _cyclesRef => _uid == null
      ? null
      : _db.collection('health_data').doc(_uid).collection('period_cycles');

  DocumentReference<Map<String, dynamic>>? get _settingsRef => _uid == null
      ? null
      : _db
          .collection('health_data')
          .doc(_uid)
          .collection('settings')
          .doc('period');

  DocumentReference<Map<String, dynamic>>? get _todayDailyRef => _uid == null
      ? null
      : _db
          .collection('health_data')
          .doc(_uid)
          .collection('period_daily')
          .doc(_today);

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    await Future.wait([_loadSettings(), _loadRecentCycles(), _loadTodayLog()]);
    state = state.copyWith(isLoading: false);
  }

  Future<void> _loadSettings() async {
    if (_settingsRef == null) return;
    try {
      final snap = await _settingsRef!.get();
      if (!snap.exists) return;
      final d = snap.data()!;
      state = state.copyWith(
        avgCycleLength: d['avgCycleLength'] as int? ?? 28,
        remindersEnabled: d['remindersEnabled'] as bool? ?? false,
        reminderDaysBefore: d['reminderDaysBefore'] as int? ?? 3,
      );
    } catch (_) {}
  }

  Future<void> _loadRecentCycles() async {
    if (_cyclesRef == null) return;
    try {
      final snap = await _cyclesRef!
          .orderBy('startDate', descending: true)
          .limit(6)
          .get();
      if (snap.docs.isEmpty) return;
      final cycles = snap.docs.map((doc) {
        final d = doc.data();
        return PeriodCycle(
          id: doc.id,
          startDate: (d['startDate'] as Timestamp).toDate(),
          endDate: (d['endDate'] as Timestamp?)?.toDate(),
          flowLevel: d['flowLevel'] as String? ?? 'Medium',
        );
      }).toList();
      state = state.copyWith(recentCycles: cycles, currentCycle: cycles.first);
    } catch (_) {}
  }

  Future<void> _loadTodayLog() async {
    if (_todayDailyRef == null) return;
    try {
      final snap = await _todayDailyRef!.get();
      if (!snap.exists) return;
      final d = snap.data()!;
      state = state.copyWith(
        todaySymptoms: List<String>.from(d['symptoms'] as List? ?? []),
        todayMood: d['mood'] as String?,
      );
    } catch (_) {}
  }

  // ─── Public API ─────────────────────────────────────────────────────────

  Future<void> logPeriodStart(String flowLevel) async {
    if (_uid == null || _cyclesRef == null) return;
    try {
      final ref = _cyclesRef!.doc();
      final now = DateTime.now();
      await ref.set({
        'startDate': Timestamp.fromDate(now),
        'flowLevel': flowLevel,
        'endDate': null,
      });

      final newCycle = PeriodCycle(id: ref.id, startDate: now, flowLevel: flowLevel);

      // Recalculate avg cycle length from historical start dates
      int newAvg = state.avgCycleLength;
      if (state.recentCycles.isNotEmpty) {
        final sorted = [...state.recentCycles]
          ..sort((a, b) => a.startDate.compareTo(b.startDate));
        final gaps = <int>[];
        for (int i = 1; i < sorted.length; i++) {
          final gap = sorted[i].startDate.difference(sorted[i - 1].startDate).inDays;
          if (gap >= 21 && gap <= 35) gaps.add(gap);
        }
        // Include the gap from last cycle to now
        final lastGap = now.difference(sorted.last.startDate).inDays;
        if (lastGap >= 21 && lastGap <= 35) gaps.add(lastGap);
        if (gaps.isNotEmpty) {
          newAvg = (gaps.reduce((a, b) => a + b) / gaps.length).round();
        }
      }

      final updatedCycles = [newCycle, ...state.recentCycles].take(6).toList();
      state = state.copyWith(
        currentCycle: newCycle,
        recentCycles: updatedCycles,
        avgCycleLength: newAvg,
      );
      await _saveSettings();

      if (state.remindersEnabled && state.nextPeriodDate != null) {
        await HealthNotificationService.schedulePeriodReminder(
          state.nextPeriodDate!,
          state.reminderDaysBefore,
        );
      }

      // Always send caring wellness notifications when period starts
      await HealthNotificationService.schedulePeriodWellnessNotifications(
        periodStartDate: now,
      );
    } catch (_) {}
  }

  Future<void> toggleSymptom(String symptom) async {
    final current = List<String>.from(state.todaySymptoms);
    if (current.contains(symptom)) {
      current.remove(symptom);
    } else {
      current.add(symptom);
    }
    state = state.copyWith(todaySymptoms: current);
    await _saveTodayLog();
  }

  Future<void> setMood(String mood) async {
    final isSame = state.todayMood == mood;
    if (isSame) {
      state = state.copyWith(clearMood: true);
    } else {
      state = state.copyWith(todayMood: mood);
    }
    await _saveTodayLog();
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    if (enabled) {
      final granted = await HealthNotificationService.requestNotificationPermission();
      if (!granted) return;
      state = state.copyWith(remindersEnabled: true);
      await _saveSettings();
      if (state.nextPeriodDate != null) {
        await HealthNotificationService.schedulePeriodReminder(
          state.nextPeriodDate!,
          state.reminderDaysBefore,
        );
      }
    } else {
      state = state.copyWith(remindersEnabled: false);
      await _saveSettings();
      await HealthNotificationService.cancelPeriodReminder();
    }
  }

  Future<void> setReminderDaysBefore(int days) async {
    state = state.copyWith(reminderDaysBefore: days);
    await _saveSettings();
    if (state.remindersEnabled && state.nextPeriodDate != null) {
      await HealthNotificationService.schedulePeriodReminder(
        state.nextPeriodDate!,
        days,
      );
    }
  }

  Future<void> setCycleLength(int days) async {
    state = state.copyWith(avgCycleLength: days);
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    if (_settingsRef == null) return;
    try {
      await _settingsRef!.set({
        'avgCycleLength': state.avgCycleLength,
        'remindersEnabled': state.remindersEnabled,
        'reminderDaysBefore': state.reminderDaysBefore,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _saveTodayLog() async {
    if (_todayDailyRef == null) return;
    try {
      await _todayDailyRef!.set({
        'date': _today,
        'symptoms': state.todaySymptoms,
        'mood': state.todayMood,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final periodTrackerProvider =
    StateNotifierProvider<PeriodTrackerNotifier, PeriodTrackerState>(
  (ref) => PeriodTrackerNotifier(),
);
