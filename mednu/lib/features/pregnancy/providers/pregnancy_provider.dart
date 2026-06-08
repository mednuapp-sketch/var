import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/pregnancy_models.dart';

// ─── Firestore paths ─────────────────────────────────────────────────────────

const _kProfiles  = 'pregnancy_profiles';
const _kLogs      = 'pregnancy_weekly_data';
const _kCheckups  = 'pregnancy_checkups';
const _kMeds      = 'pregnancy_medicines';
const _kAlerts    = 'pregnancy_alerts';
const _kNotes     = 'pregnancy_doctor_notes';

final _db  = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

// ─── State ───────────────────────────────────────────────────────────────────

class PregnancyState {
  final PregnancyProfile? profile;
  final List<PregnancyWeeklyLog> recentLogs;
  final List<PregnancyCheckup> checkups;
  final List<PregnancyMedicine> medicines;
  final List<PregnancyAlert> alerts;
  final List<PregnancyDoctorNote> doctorNotes;
  final bool isLoading;
  final String? error;

  const PregnancyState({
    this.profile,
    this.recentLogs = const [],
    this.checkups = const [],
    this.medicines = const [],
    this.alerts = const [],
    this.doctorNotes = const [],
    this.isLoading = false,
    this.error,
  });

  bool get hasProfile => profile != null;

  PregnancyState copyWith({
    PregnancyProfile? profile,
    List<PregnancyWeeklyLog>? recentLogs,
    List<PregnancyCheckup>? checkups,
    List<PregnancyMedicine>? medicines,
    List<PregnancyAlert>? alerts,
    List<PregnancyDoctorNote>? doctorNotes,
    bool? isLoading,
    String? error,
    bool clearProfile = false,
  }) => PregnancyState(
    profile: clearProfile ? null : (profile ?? this.profile),
    recentLogs: recentLogs ?? this.recentLogs,
    checkups: checkups ?? this.checkups,
    medicines: medicines ?? this.medicines,
    alerts: alerts ?? this.alerts,
    doctorNotes: doctorNotes ?? this.doctorNotes,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class PregnancyNotifier extends StateNotifier<PregnancyState> {
  PregnancyNotifier() : super(const PregnancyState()) {
    _uid = _auth.currentUser?.uid;
    if (_uid != null) _init();
  }

  String? _uid;

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    await _loadProfile();
    if (state.hasProfile) {
      await Future.wait([
        _loadRecentLogs(),
        _loadCheckups(),
        _loadMedicines(),
        _loadAlerts(),
        _loadDoctorNotes(),
      ]);
    }
    state = state.copyWith(isLoading: false);
  }

  // ── Profile ──────────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    if (_uid == null) return;
    try {
      final snap = await _db
          .collection(_kProfiles)
          .where('patientId', isEqualTo: _uid)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        state = state.copyWith(
          profile: PregnancyProfile.fromMap(snap.docs.first.id, snap.docs.first.data()),
        );
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<bool> createProfile(PregnancyProfile profile) async {
    if (_uid == null) return false;
    state = state.copyWith(isLoading: true);
    try {
      // Fetch patient name to store with profile for doctor-side display
      String patientName = 'Patient';
      try {
        final userDoc = await _db.collection('users').doc(_uid).get();
        patientName = userDoc.data()?['name'] as String? ?? 'Patient';
      } catch (_) {}

      final profileData = profile.toMap();
      profileData['patientName'] = patientName;
      profileData['createdAt'] = FieldValue.serverTimestamp();
      profileData['updatedAt'] = FieldValue.serverTimestamp();

      final ref = await _db.collection(_kProfiles).add(profileData);
      final created = PregnancyProfile.fromMap(ref.id, profileData);
      state = state.copyWith(profile: created, isLoading: false);
      await _init();
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  // ── Weekly Logs ──────────────────────────────────────────────────────────

  Future<void> _loadRecentLogs() async {
    if (_uid == null) return;
    try {
      final snap = await _db
          .collection(_kLogs)
          .where('patientId', isEqualTo: _uid)
          .orderBy('loggedAt', descending: true)
          .limit(10)
          .get();
      state = state.copyWith(
        recentLogs: snap.docs
            .map((d) => PregnancyWeeklyLog.fromMap(d.id, d.data()))
            .toList(),
      );
    } catch (_) {}
  }

  Future<bool> logToday({
    required List<String> symptoms,
    double? weightKg,
    String? bpSystolic,
    String? bpDiastolic,
    double? sugarLevel,
    int? babyMovements,
    required String mood,
    double? sleepHours,
    int? waterGlasses,
    required String notes,
  }) async {
    if (_uid == null || state.profile == null) return false;
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final log = PregnancyWeeklyLog(
        id: '',
        patientId: _uid!,
        date: today,
        pregnancyWeek: state.profile!.currentWeek,
        symptoms: symptoms,
        weightKg: weightKg,
        bpSystolic: bpSystolic,
        bpDiastolic: bpDiastolic,
        sugarLevel: sugarLevel,
        babyMovements: babyMovements,
        mood: mood,
        sleepHours: sleepHours,
        waterGlasses: waterGlasses,
        notes: notes,
        loggedAt: DateTime.now(),
      );
      // Upsert by date
      final existing = await _db
          .collection(_kLogs)
          .where('patientId', isEqualTo: _uid)
          .where('date', isEqualTo: today)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        await existing.docs.first.reference.set(log.toMap());
      } else {
        await _db.collection(_kLogs).add(log.toMap());
      }
      await _loadRecentLogs();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Checkups ─────────────────────────────────────────────────────────────

  Future<void> _loadCheckups() async {
    if (_uid == null) return;
    try {
      final snap = await _db
          .collection(_kCheckups)
          .where('patientId', isEqualTo: _uid)
          .get();
      final list = snap.docs
          .map((d) => PregnancyCheckup.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
      state = state.copyWith(checkups: list);
    } catch (_) {}
  }

  Future<void> addCheckup(PregnancyCheckup checkup) async {
    try {
      await _db.collection(_kCheckups).add(checkup.toMap());
      await _loadCheckups();
    } catch (_) {}
  }

  Future<void> markCheckupComplete(String checkupId, {String? notes}) async {
    try {
      await _db.collection(_kCheckups).doc(checkupId).update({
        'status': 'completed',
        'notes': notes,
        'completedAt': FieldValue.serverTimestamp(),
      });
      await _loadCheckups();
    } catch (_) {}
  }

  // ── Medicines ────────────────────────────────────────────────────────────

  Future<void> _loadMedicines() async {
    if (_uid == null) return;
    try {
      final snap = await _db
          .collection(_kMeds)
          .where('patientId', isEqualTo: _uid)
          .get();
      final list = snap.docs
          .map((d) => PregnancyMedicine.fromMap(d.id, d.data()))
          .where((m) => m.isActive)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(medicines: list);
    } catch (_) {}
  }

  Future<void> refreshMedicines() => _loadMedicines();

  // ── Alerts ───────────────────────────────────────────────────────────────

  Future<void> _loadAlerts() async {
    if (_uid == null) return;
    try {
      final snap = await _db
          .collection(_kAlerts)
          .where('patientId', isEqualTo: _uid)
          .where('isResolved', isEqualTo: false)
          .orderBy('reportedAt', descending: true)
          .get();
      state = state.copyWith(
        alerts: snap.docs
            .map((d) => PregnancyAlert.fromMap(d.id, d.data()))
            .toList(),
      );
    } catch (_) {}
  }

  Future<bool> reportEmergency({
    required String type,
    required String severity,
    required String message,
    required String patientName,
  }) async {
    if (_uid == null) return false;
    try {
      await _db.collection(_kAlerts).add({
        'patientId': _uid,
        'patientName': patientName,
        'type': type,
        'severity': severity,
        'message': message,
        'isResolved': false,
        'reportedAt': FieldValue.serverTimestamp(),
      });
      await _loadAlerts();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Doctor Notes ─────────────────────────────────────────────────────────

  Future<void> _loadDoctorNotes() async {
    if (_uid == null) return;
    try {
      final snap = await _db
          .collection(_kNotes)
          .where('patientId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();
      state = state.copyWith(
        doctorNotes: snap.docs
            .map((d) => PregnancyDoctorNote.fromMap(d.id, d.data()))
            .toList(),
      );
    } catch (_) {}
  }

  Future<void> refresh() => _init();
}

// ─── Providers ───────────────────────────────────────────────────────────────

final pregnancyProvider =
    StateNotifierProvider<PregnancyNotifier, PregnancyState>(
  (ref) => PregnancyNotifier(),
);

// Stream provider for real-time checkup updates
final pregnancyCheckupsStreamProvider = StreamProvider<List<PregnancyCheckup>>((ref) {
  final uid = _auth.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  return _db
      .collection(_kCheckups)
      .where('patientId', isEqualTo: uid)
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .map((d) => PregnancyCheckup.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
        return list;
      });
});

// Stream for doctor notes
final pregnancyDoctorNotesStreamProvider = StreamProvider<List<PregnancyDoctorNote>>((ref) {
  final uid = _auth.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  return _db
      .collection(_kNotes)
      .where('patientId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => PregnancyDoctorNote.fromMap(d.id, d.data()))
          .toList());
});

// Stream for medicines
final pregnancyMedicinesStreamProvider = StreamProvider<List<PregnancyMedicine>>((ref) {
  final uid = _auth.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  return _db
      .collection(_kMeds)
      .where('patientId', isEqualTo: uid)
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .map((d) => PregnancyMedicine.fromMap(d.id, d.data()))
            .where((m) => m.isActive)
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });
});
