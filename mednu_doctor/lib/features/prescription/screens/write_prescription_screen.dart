import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/services/operation_logger.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/providers/role_providers.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../notifications/services/notification_service.dart';
import '../../notifications/models/notification_model.dart';

// â”€â”€ Constants â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

const _kInvestigations = [
  'CBC', 'LFT', 'KFT', 'ECG', '2D Echo', 'Chest X-Ray',
  'MRI', 'CT Scan', 'Blood Sugar', 'Urine Test', 'Thyroid',
  'Vitamin D', 'Vitamin B12',
];

const _kDurationOptions = [
  '1 day', '3 days', '5 days', '7 days', '10 days', '14 days', '30 days', 'Custom',
];

const _kFoodTimings = [
  'Before food', 'After food', 'With food', 'Empty stomach', 'At bedtime',
];

const _kFollowUpOptions = ['1', '3', '5', '7', '14', '30'];

// â”€â”€ Medicine Entry â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _MedicineEntry {
  final TextEditingController nameCtrl        = TextEditingController();
  final TextEditingController strengthCtrl    = TextEditingController();
  final TextEditingController instructionCtrl = TextEditingController();
  final TextEditingController customDurCtrl   = TextEditingController();
  bool morning      = true;
  bool afternoon    = false;
  bool night        = true;
  String foodTiming = 'After food';
  String duration   = '5 days';
  bool customDur    = false;

  void dispose() {
    nameCtrl.dispose();
    strengthCtrl.dispose();
    instructionCtrl.dispose();
    customDurCtrl.dispose();
  }

  String get effectiveDuration =>
      customDur ? customDurCtrl.text.trim() : duration;

  String _freqStr() {
    final count = [morning, afternoon, night].where((b) => b).length;
    if (count == 3) return 'Three times daily';
    if (count == 2) return 'Twice daily';
    if (count == 1) return 'Once daily';
    return 'As needed';
  }

  Map<String, dynamic> toMap(int idx) => {
    'serialNo':     idx + 1,
    'medicineName': nameCtrl.text.trim().toUpperCase(),
    'strength':     strengthCtrl.text.trim(),
    'morning':      morning,
    'afternoon':    afternoon,
    'night':        night,
    'foodTiming':   foodTiming,
    'duration':     effectiveDuration,
    'instruction':  instructionCtrl.text.trim(),
    // Legacy compat fields
    'name':      nameCtrl.text.trim().toUpperCase(),
    'dosage':    strengthCtrl.text.trim().isNotEmpty ? strengthCtrl.text.trim() : '1 tablet',
    'frequency': _freqStr(),
    'timing':    foodTiming,
  };
}

// â”€â”€ Screen â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class WritePrescriptionScreen extends StatefulWidget {
  final String  patientId;
  final String  patientName;
  final String? appointmentId;
  final String? consultationId;
  final bool    sessionValidated;
  final bool    allowOffline;

  const WritePrescriptionScreen({
    super.key,
    this.patientId        = '',
    this.patientName      = 'Patient',
    this.appointmentId,
    this.consultationId,
    this.sessionValidated = false,
    this.allowOffline     = false,
  });

  @override
  State<WritePrescriptionScreen> createState() =>
      _WritePrescriptionScreenState();
}

class _WritePrescriptionScreenState extends State<WritePrescriptionScreen>
    with TickerProviderStateMixin {
  // â”€â”€ Form controllers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final _chiefComplaintsCtrl     = TextEditingController();
  final _historyCtrl             = TextEditingController();
  final _allergiesCtrl           = TextEditingController();
  final _examinationCtrl         = TextEditingController();
  final _diagnosisCtrl           = TextEditingController();
  final _specialInstructionsCtrl = TextEditingController();
  final _additionalNotesCtrl     = TextEditingController();
  final _customInvestCtrl        = TextEditingController();
  final _customFollowUpCtrl      = TextEditingController();

  // â”€â”€ Medicines â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final List<_MedicineEntry> _medicines = [];

  // â”€â”€ Investigations â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final Set<String> _selectedInvestigations = {};

  // â”€â”€ Allergies â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _showAllergies = false;

  // â”€â”€ Follow-up â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool   _followUpRequired = false;
  String _followUpDays     = '7';
  bool   _customFollowUp   = false;

  // â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _saving          = false;
  bool _offlineConfirmed = false;
  bool _draftSaved      = false;

  // â”€â”€ Doctor / Patient info â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String? _doctorName;
  String? _doctorSpecialty;
  String? _doctorRegNo;
  String? _doctorHospital;
  String? _doctorSignatureUrl;
  String? _patientAge;
  String? _patientGender;
  String? _patientPhone;

  // â”€â”€ Auto-save â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Timer? _autoSaveTimer;
  bool   _hasDraftChanges = false;

  // â”€â”€ Session guard â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool get _isSessionValid =>
      widget.patientId.isNotEmpty &&
      (widget.sessionValidated || _offlineConfirmed);

  @override
  void initState() {
    super.initState();
    _loadDoctorInfo();
    _loadPatientInfo();
    _startAutoSave();
    for (final c in [
      _chiefComplaintsCtrl, _historyCtrl, _allergiesCtrl, _examinationCtrl,
      _diagnosisCtrl, _specialInstructionsCtrl, _additionalNotesCtrl,
    ]) {
      c.addListener(() => _hasDraftChanges = true);
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _chiefComplaintsCtrl.dispose();
    _historyCtrl.dispose();
    _allergiesCtrl.dispose();
    _examinationCtrl.dispose();
    _diagnosisCtrl.dispose();
    _specialInstructionsCtrl.dispose();
    _additionalNotesCtrl.dispose();
    _customInvestCtrl.dispose();
    _customFollowUpCtrl.dispose();
    for (final m in _medicines) {
      m.dispose();
    }
    super.dispose();
  }

  // â”€â”€ Loaders â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _loadDoctorInfo() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;
    try {
      final data = await DoctorAuthService.getProfile(uid);
      if (!mounted) return;
      setState(() {
        _doctorName        = data?['name']               as String?;
        _doctorSpecialty   = data?['specialty']          as String?;
        _doctorRegNo       = data?['registrationNumber'] as String?;
        _doctorHospital    = data?['clinicName']         as String?
            ?? data?['hospitalName']                     as String?;
        _doctorSignatureUrl = data?['signatureUrl']      as String?;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Could not load your doctor profile — check your connection and try again.')),
      );
    }
  }

  Future<void> _loadPatientInfo() async {
    if (widget.patientId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.patientId)
          .get();
      if (!mounted || !doc.exists) return;
      final d   = doc.data()!;
      final dob = d['dob'] as String? ?? '';
      String age = '--';
      if (dob.isNotEmpty) {
        try {
          final parts = dob.split('-');
          if (parts.length == 3) {
            age = '${DateTime.now().year - int.parse(parts[0])} yrs';
          }
        } catch (_) {}
      }
      setState(() {
        _patientAge    = age;
        _patientGender = d['gender'] as String?;
        _patientPhone  = d['phone']  as String?;
      });
    } catch (_) {}
  }

  // â”€â”€ Auto-save â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _startAutoSave() {
    _autoSaveTimer =
        Timer.periodic(const Duration(seconds: 10), (_) {
      if (_hasDraftChanges && _isSessionValid) _saveDraft();
    });
  }

  Future<void> _saveDraft() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('prescription_drafts')
          .doc(uid)
          .set({
        'chiefComplaints':     _chiefComplaintsCtrl.text,
        'history':             _historyCtrl.text,
        'allergies':           _showAllergies ? _allergiesCtrl.text : '',
        'examination':         _examinationCtrl.text,
        'diagnosis':           _diagnosisCtrl.text,
        'specialInstructions': _specialInstructionsCtrl.text,
        'additionalNotes':     _additionalNotesCtrl.text,
        'investigations':      _selectedInvestigations.toList(),
        'medicines':           _medicines
            .asMap()
            .entries
            .map((e) => e.value.toMap(e.key))
            .toList(),
        'followUpRequired': _followUpRequired,
        'followUpDays': _followUpRequired
            ? (_customFollowUp
                ? int.tryParse(_customFollowUpCtrl.text)
                : int.tryParse(_followUpDays))
            : null,
        'patientId':   widget.patientId,
        'patientName': widget.patientName,
        'updatedAt':   FieldValue.serverTimestamp(),
      });
      _hasDraftChanges = false;
      if (mounted) setState(() => _draftSaved = true);
      Future.delayed(
          const Duration(seconds: 2),
          () { if (mounted) setState(() => _draftSaved = false); });
    } catch (_) {}
  }

  // â”€â”€ Rx ID â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _generateRxId() {
    final now = DateTime.now();
    final date = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final suffix =
        List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
    return 'MN-$date-$suffix';
  }

  // â”€â”€ Medicine management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _addMedicine() {
    setState(() => _medicines.add(_MedicineEntry()));
    _hasDraftChanges = true;
  }

  void _removeMedicine(int index) {
    _medicines[index].dispose();
    setState(() => _medicines.removeAt(index));
    _hasDraftChanges = true;
  }

  // â”€â”€ Validation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  bool _validate() {
    if (_chiefComplaintsCtrl.text.trim().isEmpty) {
      FeedbackService.showError(context, 'Chief Complaints is required.');
      return false;
    }
    if (_diagnosisCtrl.text.trim().isEmpty) {
      FeedbackService.showError(context, 'Diagnosis is required.');
      return false;
    }
    if (_medicines.isEmpty) {
      FeedbackService.showError(
          context, 'Add at least one medicine to the prescription.');
      return false;
    }
    for (int i = 0; i < _medicines.length; i++) {
      if (_medicines[i].nameCtrl.text.trim().isEmpty) {
        FeedbackService.showError(
            context, 'Please enter the medicine name for item ${i + 1}.');
        return false;
      }
    }
    return true;
  }

  // â”€â”€ Submit â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _submitPrescription() async {
    if (!_isSessionValid) {
      FeedbackService.showError(
          context, 'Please confirm to write an offline prescription.');
      return;
    }
    if (!_validate()) return;

    setState(() => _saving = true);
    // Block role switching while the prescription is being written/sent â€”
    // mirrors the call-screen guards in incoming_request_screen.dart /
    // doctor_video_call_screen.dart.
    ProviderScope.containerOf(context, listen: false)
        .read(criticalOperationInProgressProvider.notifier)
        .state = true;
    FeedbackService.showLoading(context, 'Sending prescription...');

    try {
      final uid            = DoctorAuthService.currentUid;
      final doctorName     = _doctorName     ?? 'Doctor';
      final doctorSpecialty = _doctorSpecialty ?? '';
      final rxId           = _generateRxId();
      final now            = DateTime.now();

      final allInvestigations = [
        ..._selectedInvestigations,
        if (_customInvestCtrl.text.trim().isNotEmpty)
          _customInvestCtrl.text.trim(),
      ];

      final followUpDaysVal = _followUpRequired
          ? (_customFollowUp
              ? int.tryParse(_customFollowUpCtrl.text.trim()) ?? 7
              : int.tryParse(_followUpDays) ?? 7)
          : null;

      final medicinesList = _medicines
          .asMap()
          .entries
          .map((e) => e.value.toMap(e.key))
          .toList();

      // Legacy advice list from special instructions
      final adviceLines = _specialInstructionsCtrl.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      // Carried over so records_screen.dart's per-family-member Records tab
      // (`.where('memberId', ...)`) picks this prescription up — otherwise
      // a consult booked "for" a family member always lands under the
      // account holder's own history instead. Prefer the consultation doc
      // (more specific to this exact session) and fall back to the
      // appointment for offline/in-person prescriptions with no consultation.
      String? memberId;
      try {
        if (widget.consultationId?.isNotEmpty == true) {
          final snap = await FirebaseFirestore.instance
              .collection('consultations')
              .doc(widget.consultationId!)
              .get();
          memberId = snap.data()?['memberId'] as String?;
        }
        if ((memberId == null || memberId.isEmpty) && widget.appointmentId?.isNotEmpty == true) {
          final snap = await FirebaseFirestore.instance
              .collection('appointments')
              .doc(widget.appointmentId!)
              .get();
          memberId = snap.data()?['memberId'] as String?;
        }
      } catch (_) {}

      final prescriptionData = {
        'rxId':                  rxId,
        'doctorId':              uid,
        'doctorName':            doctorName,
        'doctorSpecialty':       doctorSpecialty,
        'doctorRegNo':           _doctorRegNo ?? '',
        'doctorHospital':        _doctorHospital ?? '',
        'doctorSignatureUrl':    _doctorSignatureUrl ?? '',
        'patientId':             widget.patientId,
        'patientName':           widget.patientName,
        'patientAge':    _patientAge    ?? '--',
        'patientGender': _patientGender ?? '--',
        'patientPhone':  _patientPhone  ?? '',
        'chiefComplaints':       _chiefComplaintsCtrl.text.trim(),
        'history':               _historyCtrl.text.trim(),
        'historyComorbidities':  _historyCtrl.text.trim(),
        'allergies':             _showAllergies ? _allergiesCtrl.text.trim() : '',
        'examination':           _examinationCtrl.text.trim(),
        'investigations':        allInvestigations,
        'diagnosis':             _diagnosisCtrl.text.trim(),
        'medicines':             medicinesList,
        'specialInstructions':   _specialInstructionsCtrl.text.trim(),
        'additionalNotes':       _additionalNotesCtrl.text.trim(),
        'advice':                adviceLines,
        'followUpRequired':      _followUpRequired,
        'followUpDays':          followUpDaysVal,
        'appointmentId':         widget.appointmentId,
        'consultationId':        widget.consultationId,
        if (memberId != null && memberId.isNotEmpty) 'memberId': memberId,
        'isOfflinePrescription': !widget.sessionValidated && widget.allowOffline,
        'status':                'active',
        'createdAt':             FieldValue.serverTimestamp(),
      };

      final prescRef = await FirebaseFirestore.instance
          .collection('prescriptions')
          .add(prescriptionData);

      // Update appointment — prescriptionId lets the patient app's live
      // appointments stream flip the OP/prescription status without a
      // separate query (see mednu appointment_screen.dart card rendering).
      if (widget.appointmentId?.isNotEmpty == true) {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(widget.appointmentId!)
            .update({
          'status':        'completed',
          'prescriptionId': prescRef.id,
          'updatedAt':      FieldValue.serverTimestamp(),
        })
            .catchError((_) {});
      }

      // Update consultation
      if (widget.consultationId?.isNotEmpty == true) {
        await FirebaseFirestore.instance
            .collection('consultations')
            .doc(widget.consultationId!)
            .update({
          'prescriptionId':      prescRef.id,
          'prescriptionWritten': true,
        }).catchError((_) {});
      }

      // Delete draft
      if (uid != null) {
        FirebaseFirestore.instance
            .collection('prescription_drafts')
            .doc(uid)
            .delete()
            .catchError((_) {});
      }

      // Doctor notification
      if (uid != null && widget.patientId.isNotEmpty) {
        await NotificationService.addDoctorNotification(
          doctorId: uid,
          type: NotifType.summary,
          title: 'Prescription Sent',
          body:
              'Prescription for ${widget.patientName} has been sent successfully.',
          payload: {'patientId': widget.patientId},
        );
      }

      // Patient notification
      if (widget.patientId.isNotEmpty) {
        final batch  = FirebaseFirestore.instance.batch();
        final notifRef = FirebaseFirestore.instance
            .collection('patient_notifications')
            .doc(widget.patientId)
            .collection('items')
            .doc();

        batch.set(notifRef, {
          'type':           'prescription_received',
          'title':          'New Prescription from $doctorName',
          'body':
              'Dr. $doctorName has written a prescription for ${_diagnosisCtrl.text.trim()}.',
          'createdAt':      FieldValue.serverTimestamp(),
          'deliverAt':      Timestamp.fromDate(now),
          'isRead':         false,
          'doctorName':     doctorName,
          'doctorSpecialty': doctorSpecialty,
          'ctaLabel':       'View Prescription',
          'ctaRoute':       'records',
          'prescriptionId': prescRef.id,
        });

        if (_followUpRequired && followUpDaysVal != null) {
          final fuRef = FirebaseFirestore.instance
              .collection('patient_notifications')
              .doc(widget.patientId)
              .collection('items')
              .doc();
          final fuDate = now.add(Duration(days: followUpDaysVal));
          batch.set(fuRef, {
            'type':       'appointment_reminder',
            'title':      'Follow-up Reminder',
            'body':
                'Dr. $doctorName recommends a follow-up in $followUpDaysVal days.',
            'createdAt':  FieldValue.serverTimestamp(),
            'deliverAt':  Timestamp.fromDate(fuDate),
            'isRead':     false,
            'doctorName': doctorName,
            'ctaLabel':   'Book Follow-up',
            'ctaRoute':   'consultation',
          });
        }
        await batch.commit();
      }

      await OperationLogger.logSuccess(
        action: DoctorOpAction.prescriptionSent,
        entityType: 'prescription',
        message: 'Prescription sent to ${widget.patientName}',
        metadata: {
          'patientId':     widget.patientId,
          'appointmentId': widget.appointmentId,
          'rxId':          rxId,
        },
      );

      if (!mounted) return;
      FeedbackService.dismiss(context);
      _showSuccessDialog(rxId);
    } catch (e) {
      await OperationLogger.logError(
        action: DoctorOpAction.prescriptionSent,
        errorDetails: e.toString(),
        message: 'Failed to send prescription to ${widget.patientName}',
      );
      if (!mounted) return;
      FeedbackService.dismiss(context);
      FeedbackService.showError(
        context,
        'Failed to send prescription. Please try again.',
        onRetry: _submitPrescription,
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        ProviderScope.containerOf(context, listen: false)
            .read(criticalOperationInProgressProvider.notifier)
            .state = false;
      }
    }
  }

  // â”€â”€ Success dialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showSuccessDialog(String rxId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SuccessDialog(
        patientName: widget.patientName,
        rxId: rxId,
        onDone: () {
          Navigator.pop(context);
          context.go(AppRoutes.dashboard);
        },
      ),
    );
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: _isSessionValid
          ? _buildForm()
          : _buildInvalidSessionState(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.dashboard);
          }
        },
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Write Prescription',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontSize: 16,
              )),
          if (widget.patientName.isNotEmpty)
            Text('for ${widget.patientName}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                )),
        ],
      ),
      actions: [
        if (_draftSaved)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Draft saved',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                  )),
            ),
          ),
        if (_saving)
          const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
          )
        else
          TextButton(
            onPressed: _isSessionValid ? _submitPrescription : null,
            child: Text(
              'Send Rx',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: _isSessionValid ? Colors.white : Colors.white38,
              ),
            ),
          ),
      ],
    );
  }

  // â”€â”€ Invalid session state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildInvalidSessionState() {
    // Show offline confirmation whenever there is a patient to prescribe for â€”
    // this covers the case where go_router's refreshListenable rebuilt the route
    // without extra params (losing sessionValidated) but patientId is still set.
    if (widget.patientId.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_note_rounded,
                    color: AppColors.warning, size: 40),
              ),
              const SizedBox(height: 20),
              const Text('Offline Prescription', style: AppTextStyles.h3),
              const SizedBox(height: 10),
              Text(
                'You are writing a prescription outside of a live session. This will be saved as an offline prescription.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(height: 1.55),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Only prescribe for patients you have personally consulted with.',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.warning, height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              GradientButton(
                label: 'Confirm & Write Prescription',
                icon: Icons.check_rounded,
                colors: const [AppColors.warning, Color(0xFFE65100)],
                onTap: () => setState(() => _offlineConfirmed = true),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRoutes.dashboard);
                  }
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded,
                  color: AppColors.error, size: 40),
            ),
            const SizedBox(height: 20),
            const Text('Prescription Locked', style: AppTextStyles.h3),
            const SizedBox(height: 10),
            Text(
              'A prescription can only be written after a completed consultation.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(height: 1.55),
            ),
            const SizedBox(height: 32),
            GradientButton(
              label: 'Back to Dashboard',
              icon: Icons.dashboard_rounded,
              onTap: () => context.go(AppRoutes.dashboard),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Main form â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // â”€â”€ Rx Header Banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _RxHeaderBanner(
            patientName:     widget.patientName,
            patientId:       widget.patientId,
            patientAge:    _patientAge,
            patientGender: _patientGender,
            patientPhone:  _patientPhone,
            doctorName:    _doctorName,
            doctorSpecialty: _doctorSpecialty,
            doctorRegNo:     _doctorRegNo,
            doctorHospital:  _doctorHospital,
          ),
          const SizedBox(height: 20),

          // â”€â”€ Section 1: Chief Complaints â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const _SectionHeader(
            sectionNumber: '01',
            icon: Icons.sick_rounded,
            title: 'Chief Complaints',
            subtitle: 'Primary reason for visit',
            required: true,
            color: Color(0xFFE53935),
          ),
          const SizedBox(height: 10),
          _PremiumTextField(
            controller: _chiefComplaintsCtrl,
            hintText: 'e.g. Fever, Headache, Cough, Chest pain, Vomiting...',
            maxLines: 3,
          ),
          const SizedBox(height: 20),

          // â”€â”€ Section 2: Relevant History â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const _SectionHeader(
            sectionNumber: '02',
            icon: Icons.history_edu_rounded,
            title: 'Relevant History',
            subtitle: 'Past illnesses, allergies, family history',
            color: AppColors.secondary,
          ),
          const SizedBox(height: 10),
          _PremiumTextField(
            controller: _historyCtrl,
            hintText:
                'e.g. Diabetes, Hypertension, Thyroid, Previous surgery, Allergy, Pregnancy...',
            maxLines: 3,
          ),
          const SizedBox(height: 20),

          // â”€â”€ Allergies (Optional, collapsible) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _AllergiesSection(
            show: _showAllergies,
            controller: _allergiesCtrl,
            onToggle: (v) {
              setState(() => _showAllergies = v);
              _hasDraftChanges = true;
            },
            onChanged: () => _hasDraftChanges = true,
          ),
          const SizedBox(height: 20),

          // â”€â”€ Section 3: Examination / Vitals â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const _SectionHeader(
            sectionNumber: '03',
            icon: Icons.monitor_heart_rounded,
            title: 'Examination / Lab Findings',
            subtitle: 'Vitals, physical examination, lab results',
            color: Color(0xFF1565C0),
          ),
          const SizedBox(height: 10),
          _PremiumTextField(
            controller: _examinationCtrl,
            hintText:
                'BP: 120/80  Pulse: 80/min  Temp: 98.6Â°F  Weight: 65 kg\nSpOâ‚‚: 98%  Sugar: 110 mg/dL\nPhysical Exam / Lab Findings...',
            maxLines: 5,
          ),
          const SizedBox(height: 20),

          // â”€â”€ Section 4: Investigations â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const _SectionHeader(
            sectionNumber: '04',
            icon: Icons.biotech_rounded,
            title: 'Suggested Investigations',
            subtitle: 'Lab tests and diagnostic procedures',
            color: Color(0xFF00838F),
          ),
          const SizedBox(height: 10),
          _InvestigationsPanel(
            selected: _selectedInvestigations,
            customCtrl: _customInvestCtrl,
            onChanged: () {
              setState(() {});
              _hasDraftChanges = true;
            },
          ),
          const SizedBox(height: 20),

          // â”€â”€ Section 5: Diagnosis â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const _SectionHeader(
            sectionNumber: '05',
            icon: Icons.medical_information_rounded,
            title: 'Diagnosis / Provisional Diagnosis',
            subtitle: 'Clinical findings and final diagnosis',
            required: true,
            color: Color(0xFF2E7D32),
          ),
          const SizedBox(height: 10),
          _PremiumTextField(
            controller: _diagnosisCtrl,
            hintText:
                'e.g. Viral Fever, Migraine, Hypertension, Diabetes Mellitus, GERD, URI...',
            maxLines: 3,
          ),
          const SizedBox(height: 20),

          // â”€â”€ Section 6: Rx (Medicines) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Row(
            children: [
              const _SectionHeader(
                sectionNumber: '06',
                icon: Icons.medication_rounded,
                title: 'Rx â€” Medicines',
                subtitle: 'Prescribed medications',
                required: true,
                color: AppColors.primary,
              ),
              const Spacer(),
              TapScale(
                onTap: _addMedicine,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius:
                        BorderRadius.all(Radius.circular(12)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Add',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_medicines.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.medication_outlined,
                    size: 40,
                    color: AppColors.textHint.withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                const Text('No medicines added yet.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textHint,
                    )),
                const SizedBox(height: 4),
                const Text('Tap "Add" to add a medicine.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    )),
              ]),
            ),
          ...List.generate(_medicines.length, (i) => _MedicineCard(
            index:   i,
            entry:   _medicines[i],
            onRemove: () => _removeMedicine(i),
            onChanged: () {
              setState(() {});
              _hasDraftChanges = true;
            },
          )),
          const SizedBox(height: 20),

          // â”€â”€ Section 7: Special Instructions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const _SectionHeader(
            sectionNumber: '07',
            icon: Icons.lightbulb_rounded,
            title: 'Special Instructions',
            subtitle: 'Diet, rest, lifestyle recommendations',
            color: Color(0xFFF57F17),
          ),
          const SizedBox(height: 10),
          _PremiumTextField(
            controller: _specialInstructionsCtrl,
            hintText:
                'e.g. Drink plenty of water\nBed rest for 3 days\nAvoid oily food\nSteam inhalation twice daily\nReturn if fever persists...',
            maxLines: 4,
            bordered: true,
          ),
          const SizedBox(height: 20),

          // â”€â”€ Additional Notes (no heading) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _PremiumTextField(
            controller: _additionalNotesCtrl,
            hintText: 'Additional notes (optional)...',
            maxLines: 3,
            bordered: true,
          ),
          const SizedBox(height: 20),

          // â”€â”€ Follow-up â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          _FollowUpSection(
            required:    _followUpRequired,
            days:        _followUpDays,
            customMode:  _customFollowUp,
            customCtrl:  _customFollowUpCtrl,
            onToggle: (v) => setState(() => _followUpRequired = v),
            onDaysChanged: (v) => setState(() {
              if (v == 'Custom') {
                _customFollowUp = true;
              } else {
                _customFollowUp = false;
                _followUpDays = v;
              }
            }),
          ),
          const SizedBox(height: 28),

          // â”€â”€ Send Button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          GradientButton(
            label: _saving ? 'Sending...' : 'Send Prescription to Patient',
            icon:  Icons.send_rounded,
            isLoading: _saving,
            onTap: (_saving || !_isSessionValid)
                ? null
                : _submitPrescription,
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Rx Header Banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _RxHeaderBanner extends StatelessWidget {
  final String  patientName;
  final String  patientId;
  final String? patientAge;
  final String? patientGender;
  final String? patientPhone;
  final String? doctorName;
  final String? doctorSpecialty;
  final String? doctorRegNo;
  final String? doctorHospital;

  const _RxHeaderBanner({
    required this.patientName,
    required this.patientId,
    this.patientAge,
    this.patientGender,
    this.patientPhone,
    this.doctorName,
    this.doctorSpecialty,
    this.doctorRegNo,
    this.doctorHospital,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMM yyyy  hh:mm a').format(DateTime.now());

    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top: Rx watermark + header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // MedNU logo icon
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/icons/mednu_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('MedNU Healthcare',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontSize: 15,
                          )),
                      if (doctorHospital?.isNotEmpty == true)
                        Text(doctorHospital!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            )),
                      Text(dateStr,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white60,
                          )),
                    ],
                  ),
                ),
                // Large Rx watermark
                const Text('Rx',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontStyle: FontStyle.italic,
                    )),
              ],
            ),
          ),

          // Divider
          Divider(
              color: Colors.white.withValues(alpha: 0.2),
              height: 1,
              indent: 18,
              endIndent: 18),

          // Doctor info
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DOCTOR',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white54,
                      letterSpacing: 1.2,
                    )),
                const SizedBox(height: 2),
                Text('Dr. ${doctorName ?? 'Doctor'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontSize: 14,
                    )),
                if (doctorSpecialty?.isNotEmpty == true)
                  Text(doctorSpecialty!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      )),
                if (doctorRegNo?.isNotEmpty == true)
                  Text('Reg. No: $doctorRegNo',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white60,
                      )),
              ],
            ),
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 12),
            child: Divider(
                color: Colors.white.withValues(alpha: 0.2), height: 1),
          ),

          // Patient info
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PATIENT',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white54,
                      letterSpacing: 1.2,
                    )),
                const SizedBox(height: 2),
                Text(patientName.isNotEmpty ? patientName : 'Patient',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontSize: 14,
                    )),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (patientAge != null && patientAge != '--')
                      _InfoChip(Icons.cake_outlined, patientAge!),
                    if (patientGender?.isNotEmpty == true)
                      _InfoChip(Icons.person_outline_rounded,
                          patientGender!),
                    if (patientPhone?.isNotEmpty == true)
                      _InfoChip(Icons.phone_outlined, patientPhone!),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: Colors.white70),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              )),
        ]),
      );
}

// â”€â”€ Section Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SectionHeader extends StatelessWidget {
  final String   sectionNumber;
  final IconData icon;
  final String   title;
  final String   subtitle;
  final bool     required;
  final Color    color;

  const _SectionHeader({
    required this.sectionNumber,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.required = false,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(title,
                      style: AppTextStyles.labelLarge
                          .copyWith(color: AppColors.textPrimary)),
                  if (required) ...[
                    const SizedBox(width: 4),
                    Text('*',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.red.shade600,
                          fontSize: 14,
                        )),
                  ],
                ]),
                Text(subtitle,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      );
}

// â”€â”€ Premium Text Field â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PremiumTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final int    maxLines;
  final bool   bordered;

  const _PremiumTextField({
    required this.controller,
    required this.hintText,
    this.maxLines = 3,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: bordered
              ? Border.all(
                  color: AppColors.border,
                  width: 1.5,
                )
              : Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textPrimary, height: 1.5),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: AppTextStyles.caption
                .copyWith(color: AppColors.textHint, height: 1.5),
            contentPadding: const EdgeInsets.all(14),
            border: InputBorder.none,
          ),
        ),
      );
}

// â”€â”€ Investigations Panel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _InvestigationsPanel extends StatefulWidget {
  final Set<String>          selected;
  final TextEditingController customCtrl;
  final VoidCallback         onChanged;

  const _InvestigationsPanel({
    required this.selected,
    required this.customCtrl,
    required this.onChanged,
  });

  @override
  State<_InvestigationsPanel> createState() => _InvestigationsPanelState();
}

class _InvestigationsPanelState extends State<_InvestigationsPanel> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kInvestigations.map((inv) {
              final isSelected = widget.selected.contains(inv);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      widget.selected.remove(inv);
                    } else {
                      widget.selected.add(inv);
                    }
                  });
                  widget.onChanged();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF00838F).withValues(alpha: 0.12)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF00838F)
                          : AppColors.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isSelected) ...[
                      const Icon(Icons.check_rounded,
                          size: 13, color: Color(0xFF00838F)),
                      const SizedBox(width: 5),
                    ],
                    Text(inv,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isSelected
                              ? const Color(0xFF00838F)
                              : AppColors.textSecondary,
                        )),
                  ]),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          TextField(
            controller: widget.customCtrl,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Other investigation (type here)...',
              prefixIcon:
                  Icon(Icons.add_circle_outline_rounded, size: 18),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 0, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Medicine Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _MedicineCard extends StatefulWidget {
  final int            index;
  final _MedicineEntry entry;
  final VoidCallback   onRemove;
  final VoidCallback   onChanged;

  const _MedicineCard({
    required this.index,
    required this.entry,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_MedicineCard> createState() => _MedicineCardState();
}

class _MedicineCardState extends State<_MedicineCard> {
  @override
  Widget build(BuildContext context) {
    final e = widget.entry;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // â”€â”€ Card header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.07),
                  AppColors.secondary.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(17)),
            ),
            child: Row(children: [
              Container(
                width: 30, height: 30,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text('${widget.index + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      )),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.medication_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 6),
              Text('Medicine ${widget.index + 1}',
                  style: AppTextStyles.labelMedium),
              const Spacer(),
              GestureDetector(
                onTap: widget.onRemove,
                child: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded,
                      size: 15, color: Colors.red.shade400),
                ),
              ),
            ]),
          ),

          // â”€â”€ Medicine name + strength â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: _FieldBox(
                  child: TextField(
                    controller: e.nameCtrl,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (v) {
                      if (v != v.toUpperCase()) {
                        e.nameCtrl.value = TextEditingValue(
                          text: v.toUpperCase(),
                          selection: TextSelection.collapsed(
                              offset: v.length),
                        );
                      }
                      widget.onChanged();
                    },
                    style: AppTextStyles.labelMedium,
                    decoration: const InputDecoration(
                      hintText: 'MEDICINE NAME',
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      hintStyle: TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _FieldBox(
                  child: TextField(
                    controller: e.strengthCtrl,
                    onChanged: (_) => widget.onChanged(),
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Strength',
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      hintStyle: TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint),
                    ),
                  ),
                ),
              ),
            ]),
          ),

          // â”€â”€ Dosage row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dosage',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    )),
                const SizedBox(height: 8),
                Row(children: [
                  _DoseCheckbox(
                    label: 'Morning',
                    icon: Icons.wb_sunny_outlined,
                    color: const Color(0xFFFF9800),
                    value: e.morning,
                    onChanged: (v) {
                      setState(() => e.morning = v ?? false);
                      widget.onChanged();
                    },
                  ),
                  const SizedBox(width: 8),
                  _DoseCheckbox(
                    label: 'Afternoon',
                    icon: Icons.wb_twilight_rounded,
                    color: const Color(0xFFF44336),
                    value: e.afternoon,
                    onChanged: (v) {
                      setState(() => e.afternoon = v ?? false);
                      widget.onChanged();
                    },
                  ),
                  const SizedBox(width: 8),
                  _DoseCheckbox(
                    label: 'Night',
                    icon: Icons.nights_stay_outlined,
                    color: const Color(0xFF5C6BC0),
                    value: e.night,
                    onChanged: (v) {
                      setState(() => e.night = v ?? false);
                      widget.onChanged();
                    },
                  ),
                ]),
              ],
            ),
          ),

          // â”€â”€ Food timing + Duration â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Food',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        )),
                    const SizedBox(height: 4),
                    _FieldBox(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: e.foodTiming,
                          isExpanded: true,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textPrimary),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => e.foodTiming = v);
                            widget.onChanged();
                          },
                          items: _kFoodTimings
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t,
                                        style: const TextStyle(
                                          fontSize: 12,
                                        )),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Duration',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        )),
                    const SizedBox(height: 4),
                    if (e.customDur)
                      _FieldBox(
                        child: Row(children: [
                          Expanded(
                            child: TextField(
                              controller: e.customDurCtrl,
                              onChanged: (_) => widget.onChanged(),
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: AppColors.textPrimary),
                              decoration: const InputDecoration(
                                hintText: 'e.g. 2 weeks',
                                border: InputBorder.none,
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 10),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                e.customDur = false;
                                e.duration  = '5 days';
                              });
                              widget.onChanged();
                            },
                            child: const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.close_rounded,
                                  size: 14, color: AppColors.textHint),
                            ),
                          ),
                        ]),
                      )
                    else
                      _FieldBox(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: e.duration,
                            isExpanded: true,
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.textPrimary),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                if (v == 'Custom') {
                                  e.customDur = true;
                                } else {
                                  e.duration = v;
                                }
                              });
                              widget.onChanged();
                            },
                            items: _kDurationOptions
                                .map((d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(d,
                                          style: const TextStyle(
                                            fontSize: 12,
                                          )),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ]),
          ),

          // â”€â”€ Instructions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: _FieldBox(
              child: TextField(
                controller: e.instructionCtrl,
                onChanged: (_) => widget.onChanged(),
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Special instruction (optional)...',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  hintStyle: TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldBox extends StatelessWidget {
  final Widget child;
  const _FieldBox({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

class _DoseCheckbox extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color    color;
  final bool     value;
  final ValueChanged<bool?> onChanged;

  const _DoseCheckbox({
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: value
                  ? color.withValues(alpha: 0.12)
                  : AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: value ? color : AppColors.border,
                width: value ? 1.5 : 1,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 18,
                  color: value ? color : AppColors.textHint),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        value ? FontWeight.w600 : FontWeight.w400,
                    color: value ? color : AppColors.textHint,
                  )),
            ]),
          ),
        ),
      );
}

// â”€â”€ Allergies Section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AllergiesSection extends StatelessWidget {
  final bool                  show;
  final TextEditingController controller;
  final ValueChanged<bool>    onToggle;
  final VoidCallback          onChanged;

  const _AllergiesSection({
    required this.show,
    required this.controller,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: show
              ? const Color(0xFFE53935).withValues(alpha: 0.3)
              : AppColors.border.withValues(alpha: 0.5),
          width: show ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFE53935), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('Allergies & Adverse Reactions',
                          style: AppTextStyles.labelLarge
                              .copyWith(color: AppColors.textPrimary)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.textHint.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Optional',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textHint,
                              letterSpacing: 0.5,
                            )),
                      ),
                    ]),
                    Text('Known drug, food, or environmental allergies',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Switch(
                value: show,
                activeThumbColor: const Color(0xFFE53935),
                activeTrackColor:
                    const Color(0xFFE53935).withValues(alpha: 0.3),
                onChanged: onToggle,
              ),
            ]),
          ),
          if (show) ...[
            Divider(
              height: 1,
              color: const Color(0xFFE53935).withValues(alpha: 0.15),
              indent: 14,
              endIndent: 14,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: TextField(
                controller: controller,
                maxLines: 3,
                onChanged: (_) => onChanged(),
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimary, height: 1.5),
                decoration: InputDecoration(
                  hintText:
                      'e.g. Penicillin â€” rash\nAspirin â€” GI bleeding\nSulfa drugs â€” anaphylaxis\nPeanuts â€” swelling...',
                  hintStyle: AppTextStyles.caption
                      .copyWith(color: AppColors.textHint, height: 1.5),
                  contentPadding: const EdgeInsets.all(12),
                  filled: true,
                  fillColor: const Color(0xFFE53935).withValues(alpha: 0.03),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: const Color(0xFFE53935).withValues(alpha: 0.2),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: const Color(0xFFE53935).withValues(alpha: 0.2),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFFE53935),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// â”€â”€ Follow-up Section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _FollowUpSection extends StatelessWidget {
  final bool                 required;
  final String               days;
  final bool                 customMode;
  final TextEditingController customCtrl;
  final ValueChanged<bool>   onToggle;
  final ValueChanged<String> onDaysChanged;

  const _FollowUpSection({
    required this.required,
    required this.days,
    required this.customMode,
    required this.customCtrl,
    required this.onToggle,
    required this.onDaysChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_repeat_rounded,
                color: AppColors.secondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Follow-up Required',
                    style: AppTextStyles.labelLarge),
                Text('Schedule patient return visit',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textHint)),
              ],
            ),
          ),
          Switch(
            value: required,
            activeThumbColor: AppColors.secondary,
            onChanged: onToggle,
          ),
        ]),
        if (required) ...[
          const Divider(height: 20),
          const Text('Follow-up after',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              )),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._kFollowUpOptions.map((d) {
                final isSelected = !customMode && days == d;
                return GestureDetector(
                  onTap: () => onDaysChanged(d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.secondary.withValues(alpha: 0.12)
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.secondary
                            : AppColors.border,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text('$d days',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isSelected
                              ? AppColors.secondary
                              : AppColors.textSecondary,
                        )),
                  ),
                );
              }),
              GestureDetector(
                onTap: () => onDaysChanged('Custom'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: customMode
                        ? AppColors.secondary.withValues(alpha: 0.12)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: customMode
                          ? AppColors.secondary
                          : AppColors.border,
                      width: customMode ? 1.5 : 1,
                    ),
                  ),
                  child: Text('Custom',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: customMode
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: customMode
                            ? AppColors.secondary
                            : AppColors.textSecondary,
                      )),
                ),
              ),
            ],
          ),
          if (customMode) ...[
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: customCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Enter number of days',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ]),
    );
  }
}

// â”€â”€ Success Dialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SuccessDialog extends StatefulWidget {
  final String      patientName;
  final String      rxId;
  final VoidCallback onDone;

  const _SuccessDialog({
    required this.patientName,
    required this.rxId,
    required this.onDone,
  });

  @override
  State<_SuccessDialog> createState() => _SuccessDialogState();
}

class _SuccessDialogState extends State<_SuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.all(28),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ScaleTransition(
          scale: _scale,
          child: Container(
            width: 80, height: 80,
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: Colors.white, size: 42),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Prescription Sent!', style: AppTextStyles.h3),
        const SizedBox(height: 8),
        Text(
          '${widget.patientName} has been notified via the MedNU app.\nRx ID: ${widget.rxId}',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(height: 1.5),
        ),
        const SizedBox(height: 24),
        GradientButton(
          label: 'Back to Dashboard',
          icon: Icons.dashboard_rounded,
          onTap: widget.onDone,
        ),
      ]),
    );
  }
}
