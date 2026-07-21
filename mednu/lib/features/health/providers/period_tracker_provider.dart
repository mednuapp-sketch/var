import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/health_notification_service.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class PeriodEntry {
  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final String flowLevel; // 'Light' | 'Medium' | 'Heavy'
  final bool hasBloodClots;
  final List<String> symptoms;
  final String? mood;
  final String? notes;

  const PeriodEntry({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.flowLevel,
    this.hasBloodClots = false,
    this.symptoms = const [],
    this.mood,
    this.notes,
  });

  factory PeriodEntry.fromFirestore(
      String id, Map<String, dynamic> d, int defaultDuration) {
    final start =
        (d['startDate'] as Timestamp?)?.toDate() ?? DateTime.now();
    final end = (d['endDate'] as Timestamp?)?.toDate() ??
        start.add(Duration(days: defaultDuration - 1));
    return PeriodEntry(
      id: id,
      startDate: _dateOnly(start),
      endDate: _dateOnly(end),
      flowLevel: d['flowLevel'] as String? ?? 'Medium',
      hasBloodClots: d['hasBloodClots'] as bool? ?? false,
      symptoms: List<String>.from(d['symptoms'] as List? ?? []),
      mood: d['mood'] as String?,
      notes: d['notes'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'flowLevel': flowLevel,
        'hasBloodClots': hasBloodClots,
        'symptoms': symptoms,
        'mood': mood,
        'notes': notes,
      };

  PeriodEntry copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? flowLevel,
    bool? hasBloodClots,
    List<String>? symptoms,
    String? mood,
    String? notes,
  }) =>
      PeriodEntry(
        id: id,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        flowLevel: flowLevel ?? this.flowLevel,
        hasBloodClots: hasBloodClots ?? this.hasBloodClots,
        symptoms: symptoms ?? this.symptoms,
        mood: mood ?? this.mood,
        notes: notes ?? this.notes,
      );
}

// Keep PeriodCycle as an alias so existing imports in other files don't break
typedef PeriodCycle = PeriodEntry;

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

// ─── State ───────────────────────────────────────────────────────────────────

class PeriodTrackerState {
  final List<PeriodEntry> entries; // newest first
  final bool onboardingComplete;
  final int avgCycleLength;
  final int periodDuration;
  final String defaultFlow;
  final bool defaultHasBloodClots;
  final bool remindersEnabled;
  final int reminderDaysBefore;
  final bool isLoading;

  const PeriodTrackerState({
    this.entries = const [],
    this.onboardingComplete = false,
    this.avgCycleLength = 28,
    this.periodDuration = 5,
    this.defaultFlow = 'Medium',
    this.defaultHasBloodClots = false,
    this.remindersEnabled = false,
    this.reminderDaysBefore = 3,
    this.isLoading = true,
  });

  // ── Backward-compat helpers ──────────────────────────────────────────────
  PeriodEntry? get currentCycle => entries.isEmpty ? null : entries.first;
  List<PeriodEntry> get recentCycles => entries;
  bool get hasCycle => entries.isNotEmpty;

  // ── Cycle computations ──────────────────────────────────────────────────

  DateTime? get lastPeriodStart =>
      entries.isEmpty ? null : entries.first.startDate;

  DateTime? get nextPeriodDate => lastPeriodStart == null
      ? null
      : lastPeriodStart!.add(Duration(days: avgCycleLength));

  int get daysToNextPeriod {
    if (nextPeriodDate == null) return 0;
    final diff = nextPeriodDate!.difference(_dateOnly(DateTime.now())).inDays;
    return diff.clamp(0, avgCycleLength);
  }

  int get cycleDay {
    if (lastPeriodStart == null) return 0;
    return (_dateOnly(DateTime.now())
                .difference(lastPeriodStart!)
                .inDays +
            1)
        .clamp(1, avgCycleLength);
  }

  String get currentPhase {
    final d = cycleDay;
    if (d == 0) return 'Unknown';
    if (d <= periodDuration) return 'Menstruation';
    if (d <= 13) return 'Follicular';
    if (d <= 16) return 'Ovulation';
    return 'Luteal';
  }

  bool get isInFertileWindow {
    final d = cycleDay;
    return d >= 12 && d <= 16;
  }

  // ── Calendar data ───────────────────────────────────────────────────────

  /// All dates covered by logged period entries.
  Set<DateTime> get loggedPeriodDays {
    final days = <DateTime>{};
    for (final e in entries) {
      var d = e.startDate;
      while (!d.isAfter(e.endDate)) {
        days.add(d);
        d = d.add(const Duration(days: 1));
      }
    }
    return days;
  }

  /// Up to 3 future period start dates predicted from the last logged period.
  List<DateTime> get predictedPeriodStarts {
    if (lastPeriodStart == null) return [];
    final starts = <DateTime>[];
    var base = lastPeriodStart!;
    for (int i = 0; i < 3; i++) {
      base = base.add(Duration(days: avgCycleLength));
      starts.add(base);
    }
    return starts;
  }

  /// Predicted period days (from predicted starts, each lasting periodDuration).
  Set<DateTime> get predictedPeriodDays {
    final days = <DateTime>{};
    for (final start in predictedPeriodStarts) {
      var d = start;
      for (int i = 0; i < periodDuration; i++) {
        // Don't overlap with already-logged days
        if (!loggedPeriodDays.contains(d)) days.add(d);
        d = d.add(const Duration(days: 1));
      }
    }
    return days;
  }

  /// Fertile window days (cycle days 12–16) for the last 2 logged + next 3 predicted cycles.
  Set<DateTime> get fertileDays {
    final days = <DateTime>{};
    final starts = <DateTime>[];

    // Last 2 logged
    for (int i = 0; i < entries.length && i < 2; i++) {
      starts.add(entries[i].startDate);
    }
    // Next 3 predicted
    starts.addAll(predictedPeriodStarts);

    for (final start in starts) {
      for (int offset = 11; offset <= 15; offset++) {
        final d = start.add(Duration(days: offset));
        if (!loggedPeriodDays.contains(d)) days.add(d);
      }
    }
    return days;
  }

  /// Ovulation days (cycle day 14) for recent + predicted cycles.
  Set<DateTime> get ovulationDays {
    final days = <DateTime>{};
    final starts = <DateTime>[];
    for (int i = 0; i < entries.length && i < 2; i++) {
      starts.add(entries[i].startDate);
    }
    starts.addAll(predictedPeriodStarts);

    for (final start in starts) {
      final d = start.add(const Duration(days: 13));
      if (!loggedPeriodDays.contains(d)) days.add(d);
    }
    return days;
  }

  PeriodTrackerState copyWith({
    List<PeriodEntry>? entries,
    bool? onboardingComplete,
    int? avgCycleLength,
    int? periodDuration,
    String? defaultFlow,
    bool? defaultHasBloodClots,
    bool? remindersEnabled,
    int? reminderDaysBefore,
    bool? isLoading,
  }) =>
      PeriodTrackerState(
        entries: entries ?? this.entries,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        avgCycleLength: avgCycleLength ?? this.avgCycleLength,
        periodDuration: periodDuration ?? this.periodDuration,
        defaultFlow: defaultFlow ?? this.defaultFlow,
        defaultHasBloodClots: defaultHasBloodClots ?? this.defaultHasBloodClots,
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

  CollectionReference<Map<String, dynamic>>? get _entriesRef => _uid == null
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
    await Future.wait([_loadSettings(), _loadEntries()]);
    state = state.copyWith(isLoading: false);
  }

  Future<void> _loadSettings() async {
    if (_settingsRef == null) return;
    try {
      final snap = await _settingsRef!.get();
      if (!snap.exists) return;
      final d = snap.data();
      if (d == null) return;
      state = state.copyWith(
        onboardingComplete: d['onboardingComplete'] as bool? ?? false,
        avgCycleLength: d['avgCycleLength'] as int? ?? 28,
        periodDuration: d['periodDuration'] as int? ?? 5,
        defaultFlow: d['defaultFlow'] as String? ?? 'Medium',
        defaultHasBloodClots: d['defaultHasBloodClots'] as bool? ?? false,
        remindersEnabled: d['remindersEnabled'] as bool? ?? false,
        reminderDaysBefore: d['reminderDaysBefore'] as int? ?? 3,
      );
    } catch (_) {}
  }

  Future<void> _loadEntries() async {
    if (_entriesRef == null) return;
    try {
      final snap = await _entriesRef!
          .orderBy('startDate', descending: true)
          .limit(12)
          .get();
      if (snap.docs.isEmpty) return;
      final dur = state.periodDuration;
      final list = snap.docs
          .map((doc) => PeriodEntry.fromFirestore(doc.id, doc.data(), dur))
          .toList();
      state = state.copyWith(entries: list);
    } catch (_) {}
  }

  // ── Public API ──────────────────────────────────────────────────────────

  Future<void> completeOnboarding({
    required int cycleLength,
    required int periodDuration,
    required String defaultFlow,
    required bool hasBloodClots,
  }) async {
    state = state.copyWith(
      onboardingComplete: true,
      avgCycleLength: cycleLength,
      periodDuration: periodDuration,
      defaultFlow: defaultFlow,
      defaultHasBloodClots: hasBloodClots,
    );
    await _saveSettings();
  }

  Future<void> logPeriod({
    required DateTime startDate,
    required DateTime endDate,
    required String flowLevel,
    required bool hasBloodClots,
    List<String> symptoms = const [],
    String? mood,
    String? notes,
  }) async {
    if (_uid == null || _entriesRef == null) return;
    try {
      final ref = _entriesRef!.doc();
      final entry = PeriodEntry(
        id: ref.id,
        startDate: _dateOnly(startDate),
        endDate: _dateOnly(endDate),
        flowLevel: flowLevel,
        hasBloodClots: hasBloodClots,
        symptoms: symptoms,
        mood: mood,
        notes: notes,
      );
      await ref.set(entry.toFirestore());

      final updated = [entry, ...state.entries]
        ..sort((a, b) => b.startDate.compareTo(a.startDate));

      // Recalculate avg cycle length from historical gaps
      int newAvg = state.avgCycleLength;
      if (updated.length >= 2) {
        final gaps = <int>[];
        for (int i = 0; i < updated.length - 1; i++) {
          final gap = updated[i]
              .startDate
              .difference(updated[i + 1].startDate)
              .inDays;
          if (gap >= 21 && gap <= 45) gaps.add(gap);
        }
        if (gaps.isNotEmpty) {
          newAvg = (gaps.reduce((a, b) => a + b) / gaps.length).round();
        }
      }

      state = state.copyWith(
        entries: updated.take(12).toList(),
        avgCycleLength: newAvg,
      );
      await _saveSettings();

      if (state.remindersEnabled && state.nextPeriodDate != null) {
        await HealthNotificationService.schedulePeriodReminder(
          state.nextPeriodDate!,
          state.reminderDaysBefore,
        );
      }
      await HealthNotificationService.schedulePeriodWellnessNotifications(
        periodStartDate: startDate,
      );
    } catch (_) {}
  }

  Future<void> updateEntry({
    required String id,
    required DateTime startDate,
    required DateTime endDate,
    required String flowLevel,
    required bool hasBloodClots,
    List<String> symptoms = const [],
    String? mood,
    String? notes,
  }) async {
    if (_uid == null || _entriesRef == null) return;
    try {
      final updated = PeriodEntry(
        id: id,
        startDate: _dateOnly(startDate),
        endDate: _dateOnly(endDate),
        flowLevel: flowLevel,
        hasBloodClots: hasBloodClots,
        symptoms: symptoms,
        mood: mood,
        notes: notes,
      );
      await _entriesRef!.doc(id).set(updated.toFirestore());

      final list = state.entries.map((e) => e.id == id ? updated : e).toList()
        ..sort((a, b) => b.startDate.compareTo(a.startDate));
      state = state.copyWith(entries: list);
    } catch (_) {}
  }

  Future<void> deleteEntry(String id) async {
    if (_uid == null || _entriesRef == null) return;
    try {
      await _entriesRef!.doc(id).delete();
      final list = state.entries.where((e) => e.id != id).toList();
      state = state.copyWith(entries: list);
    } catch (_) {}
  }

  Future<void> saveSettings({
    int? cycleLength,
    int? periodDuration,
    String? defaultFlow,
    bool? defaultHasBloodClots,
    bool? remindersEnabled,
    int? reminderDaysBefore,
  }) async {
    state = state.copyWith(
      avgCycleLength: cycleLength,
      periodDuration: periodDuration,
      defaultFlow: defaultFlow,
      defaultHasBloodClots: defaultHasBloodClots,
      remindersEnabled: remindersEnabled,
      reminderDaysBefore: reminderDaysBefore,
    );
    await _saveSettings();

    if (state.remindersEnabled && state.nextPeriodDate != null) {
      await HealthNotificationService.schedulePeriodReminder(
        state.nextPeriodDate!,
        state.reminderDaysBefore,
      );
    } else if (!state.remindersEnabled) {
      await HealthNotificationService.cancelPeriodReminder();
    }
  }

  // Legacy methods for backward compat
  Future<void> logPeriodStart(String flowLevel) => logPeriod(
        startDate: DateTime.now(),
        endDate: DateTime.now()
            .add(Duration(days: state.periodDuration - 1)),
        flowLevel: flowLevel,
        hasBloodClots: state.defaultHasBloodClots,
      );

  Future<void> setCycleLength(int days) =>
      saveSettings(cycleLength: days);

  Future<void> setRemindersEnabled(bool enabled) async {
    if (enabled) {
      final granted =
          await HealthNotificationService.requestNotificationPermission();
      if (!granted) return;
    }
    await saveSettings(remindersEnabled: enabled);
  }

  Future<void> setReminderDaysBefore(int days) =>
      saveSettings(reminderDaysBefore: days);

  Future<void> toggleSymptom(String symptom) async {
    // Daily log (not per-entry) — legacy feature kept
    if (_todayDailyRef == null) return;
    try {
      final snap = await _todayDailyRef!.get();
      final existing = List<String>.from(
          snap.data()?['symptoms'] as List? ?? []);
      if (existing.contains(symptom)) {
        existing.remove(symptom);
      } else {
        existing.add(symptom);
      }
      await _todayDailyRef!.set(
          {'symptoms': existing, 'date': _today}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> setMood(String mood) async {
    if (_todayDailyRef == null) return;
    try {
      await _todayDailyRef!
          .set({'mood': mood, 'date': _today}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    if (_settingsRef == null) return;
    try {
      await _settingsRef!.set({
        'onboardingComplete': state.onboardingComplete,
        'avgCycleLength': state.avgCycleLength,
        'periodDuration': state.periodDuration,
        'defaultFlow': state.defaultFlow,
        'defaultHasBloodClots': state.defaultHasBloodClots,
        'remindersEnabled': state.remindersEnabled,
        'reminderDaysBefore': state.reminderDaysBefore,
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final periodTrackerProvider =
    StateNotifierProvider<PeriodTrackerNotifier, PeriodTrackerState>(
  (ref) => PeriodTrackerNotifier(),
);
