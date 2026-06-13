import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/pregnancy_models.dart';

// ─── Firestore paths ─────────────────────────────────────────────────────────

const _kProfiles = 'pregnancy_profiles';
const _kLogs     = 'pregnancy_weekly_data';
const _kCheckups = 'pregnancy_checkups';
const _kMeds     = 'pregnancy_medicines';
const _kAlerts   = 'pregnancy_alerts';
const _kNotes    = 'pregnancy_doctor_notes';

final _db   = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

String? get _currentUid => _auth.currentUser?.uid;

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
    bool clearError = false,
  }) => PregnancyState(
    profile: clearProfile ? null : (profile ?? this.profile),
    recentLogs: recentLogs ?? this.recentLogs,
    checkups: checkups ?? this.checkups,
    medicines: medicines ?? this.medicines,
    alerts: alerts ?? this.alerts,
    doctorNotes: doctorNotes ?? this.doctorNotes,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
  );
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class PregnancyNotifier extends StateNotifier<PregnancyState> {
  PregnancyNotifier() : super(const PregnancyState()) {
    if (_currentUid != null) _init();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
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
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  // ── Profile ──────────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    final uid = _currentUid;
    if (uid == null) return;
    final snap = await _db
        .collection(_kProfiles)
        .where('patientId', isEqualTo: uid)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      state = state.copyWith(
        profile: PregnancyProfile.fromMap(snap.docs.first.id, snap.docs.first.data()),
      );
    }
  }

  Future<bool> createProfile(PregnancyProfile profile) async {
    final uid = _currentUid;
    if (uid == null) return false;

    // Prevent duplicate active profiles
    final existing = await _db
        .collection(_kProfiles)
        .where('patientId', isEqualTo: uid)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      // Update existing instead of creating a new one
      await _db.collection(_kProfiles).doc(existing.docs.first.id).update({
        ...profile.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      state = state.copyWith(
        profile: PregnancyProfile.fromMap(existing.docs.first.id, {
          ...profile.toMap(),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        }),
      );
      await _loadSubCollections();
      return true;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      String patientName = 'Patient';
      try {
        final userDoc = await _db.collection('users').doc(uid).get();
        patientName = userDoc.data()?['name'] as String? ?? 'Patient';
      } catch (_) {}

      final profileData = profile.toMap();
      profileData['patientName'] = patientName;
      profileData['createdAt'] = FieldValue.serverTimestamp();
      profileData['updatedAt'] = FieldValue.serverTimestamp();

      final ref = await _db.collection(_kProfiles).add(profileData);
      // Re-fetch the created doc to get server-resolved timestamps
      final created = await ref.get();
      state = state.copyWith(
        profile: PregnancyProfile.fromMap(ref.id, created.data() ?? profileData),
        isLoading: false,
      );
      await _loadSubCollections();
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> updateProfile(Map<String, dynamic> updates) async {
    final profile = state.profile;
    if (profile == null) return false;
    try {
      updates['updatedAt'] = FieldValue.serverTimestamp();
      await _db.collection(_kProfiles).doc(profile.id).update(updates);
      await _loadProfile();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> _loadSubCollections() async {
    await Future.wait([
      _loadRecentLogs(),
      _loadCheckups(),
      _loadMedicines(),
      _loadAlerts(),
      _loadDoctorNotes(),
    ]);
  }

  // ── Weekly Logs ──────────────────────────────────────────────────────────

  Future<void> _loadRecentLogs() async {
    final uid = _currentUid;
    if (uid == null) return;
    try {
      final snap = await _db
          .collection(_kLogs)
          .where('patientId', isEqualTo: uid)
          .orderBy('loggedAt', descending: true)
          .limit(10)
          .get();
      state = state.copyWith(
        recentLogs: snap.docs
            .map((d) => PregnancyWeeklyLog.fromMap(d.id, d.data()))
            .toList(),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
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
    final uid = _currentUid;
    if (uid == null || state.profile == null) return false;
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final data = {
        'patientId': uid,
        'date': today,
        'pregnancyWeek': state.profile!.currentWeek,
        'symptoms': symptoms,
        'weightKg': weightKg,
        'bpSystolic': bpSystolic,
        'bpDiastolic': bpDiastolic,
        'sugarLevel': sugarLevel,
        'babyMovements': babyMovements,
        'mood': mood,
        'sleepHours': sleepHours,
        'waterGlasses': waterGlasses,
        'notes': notes,
        'loggedAt': FieldValue.serverTimestamp(),
      };

      // Upsert by date to prevent duplicate entries per day
      final existing = await _db
          .collection(_kLogs)
          .where('patientId', isEqualTo: uid)
          .where('date', isEqualTo: today)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        await existing.docs.first.reference.set(data);
      } else {
        await _db.collection(_kLogs).add(data);
      }
      await _loadRecentLogs();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ── Checkups ─────────────────────────────────────────────────────────────

  Future<void> _loadCheckups() async {
    final uid = _currentUid;
    if (uid == null) return;
    try {
      final snap = await _db
          .collection(_kCheckups)
          .where('patientId', isEqualTo: uid)
          .get();
      final list = snap.docs
          .map((d) => PregnancyCheckup.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
      state = state.copyWith(checkups: list);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<bool> addCheckup(PregnancyCheckup checkup) async {
    try {
      final data = checkup.toMap();
      data['createdAt'] = FieldValue.serverTimestamp();
      await _db.collection(_kCheckups).add(data);
      await _loadCheckups();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> markCheckupComplete(String checkupId, {String? notes}) async {
    try {
      await _db.collection(_kCheckups).doc(checkupId).update({
        'status': 'completed',
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'completedAt': FieldValue.serverTimestamp(),
      });
      await _loadCheckups();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> markCheckupMissed(String checkupId) async {
    try {
      await _db.collection(_kCheckups).doc(checkupId).update({'status': 'missed'});
      await _loadCheckups();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> deleteCheckup(String checkupId) async {
    try {
      await _db.collection(_kCheckups).doc(checkupId).delete();
      state = state.copyWith(
        checkups: state.checkups.where((c) => c.id != checkupId).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ── Medicines ────────────────────────────────────────────────────────────

  Future<void> _loadMedicines() async {
    final uid = _currentUid;
    if (uid == null) return;
    try {
      final snap = await _db
          .collection(_kMeds)
          .where('patientId', isEqualTo: uid)
          .get();
      final list = snap.docs
          .map((d) => PregnancyMedicine.fromMap(d.id, d.data()))
          .where((m) => m.isActive)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(medicines: list);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> refreshMedicines() => _loadMedicines();

  Future<bool> addMedicine(PregnancyMedicine medicine) async {
    try {
      final data = medicine.toMap();
      data['createdAt'] = FieldValue.serverTimestamp();
      await _db.collection(_kMeds).add(data);
      await _loadMedicines();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> deleteMedicine(String medicineId) async {
    try {
      await _db.collection(_kMeds).doc(medicineId).update({'isActive': false});
      state = state.copyWith(
        medicines: state.medicines.where((m) => m.id != medicineId).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ── Alerts ───────────────────────────────────────────────────────────────

  Future<void> _loadAlerts() async {
    final uid = _currentUid;
    if (uid == null) return;
    try {
      final snap = await _db
          .collection(_kAlerts)
          .where('patientId', isEqualTo: uid)
          .where('isResolved', isEqualTo: false)
          .orderBy('reportedAt', descending: true)
          .get();
      state = state.copyWith(
        alerts: snap.docs
            .map((d) => PregnancyAlert.fromMap(d.id, d.data()))
            .toList(),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<bool> reportEmergency({
    required String type,
    required String severity,
    required String message,
    required String patientName,
  }) async {
    final uid = _currentUid;
    if (uid == null) return false;
    try {
      await _db.collection(_kAlerts).add({
        'patientId': uid,
        'patientName': patientName,
        'type': type,
        'severity': severity,
        'message': message,
        'isResolved': false,
        'reportedAt': FieldValue.serverTimestamp(),
      });
      await _loadAlerts();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ── Doctor Notes ─────────────────────────────────────────────────────────

  Future<void> _loadDoctorNotes() async {
    final uid = _currentUid;
    if (uid == null) return;
    try {
      final snap = await _db
          .collection(_kNotes)
          .where('patientId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();
      state = state.copyWith(
        doctorNotes: snap.docs
            .map((d) => PregnancyDoctorNote.fromMap(d.id, d.data()))
            .toList(),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> refresh() => _init();

  void clearError() => state = state.copyWith(clearError: true);
}

// ─── Providers ───────────────────────────────────────────────────────────────

final pregnancyProvider =
    StateNotifierProvider<PregnancyNotifier, PregnancyState>(
  (ref) => PregnancyNotifier(),
);

// Real-time stream for profile (detects doctor assignments, high-risk updates)
final pregnancyProfileStreamProvider = StreamProvider.autoDispose<PregnancyProfile?>((ref) {
  final uid = _currentUid;
  if (uid == null) return const Stream.empty();
  return _db
      .collection(_kProfiles)
      .where('patientId', isEqualTo: uid)
      .where('isActive', isEqualTo: true)
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isEmpty
          ? null
          : PregnancyProfile.fromMap(snap.docs.first.id, snap.docs.first.data()));
});

// Real-time stream for checkups
final pregnancyCheckupsStreamProvider = StreamProvider.autoDispose<List<PregnancyCheckup>>((ref) {
  final uid = _currentUid;
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

// Real-time stream for doctor notes
final pregnancyDoctorNotesStreamProvider = StreamProvider.autoDispose<List<PregnancyDoctorNote>>((ref) {
  final uid = _currentUid;
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

// Real-time stream for medicines
final pregnancyMedicinesStreamProvider = StreamProvider.autoDispose<List<PregnancyMedicine>>((ref) {
  final uid = _currentUid;
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
