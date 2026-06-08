import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/services/operation_logger.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../notifications/services/notification_service.dart';
import '../../notifications/models/notification_model.dart';

class WritePrescriptionScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String? appointmentId;

  /// Consultation this prescription belongs to.
  final String? consultationId;

  /// True when navigated from a completed, patient-joined consultation session.
  /// False when writing a prescription manually from patient profile.
  final bool sessionValidated;

  /// When true, allows writing a prescription without a live consultation.
  /// Set by patient-detail screen navigation.
  final bool allowOffline;

  const WritePrescriptionScreen({
    super.key,
    this.patientId = '',
    this.patientName = 'Patient',
    this.appointmentId,
    this.consultationId,
    this.sessionValidated = false,
    this.allowOffline = false,
  });

  @override
  State<WritePrescriptionScreen> createState() => _WritePrescriptionScreenState();
}

class _WritePrescriptionScreenState extends State<WritePrescriptionScreen> {
  final _diagnosisCtrl = TextEditingController();
  final _adviceCtrl    = TextEditingController();
  final List<Map<String, dynamic>> _medicines = [];
  bool _followUpRequired = false;
  String _followUpDays = '7';
  bool _saving = false;
  bool _offlineConfirmed = false;

  String? _doctorName;
  String? _doctorSpecialty;
  String? _doctorRegNo;

  String? _patientAge;
  String? _patientGender;

  /// True when prescription writing is allowed.
  /// Either from a validated session OR confirmed offline mode.
  bool get _isSessionValid =>
      widget.patientId.isNotEmpty &&
      (widget.sessionValidated || (widget.allowOffline && _offlineConfirmed));

  @override
  void initState() {
    super.initState();
    _loadDoctorInfo();
    _loadPatientInfo();
  }

  Future<void> _loadDoctorInfo() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;
    final data = await DoctorAuthService.getProfile(uid);
    if (!mounted) return;
    setState(() {
      _doctorName    = data?['name']               as String?;
      _doctorSpecialty = data?['specialty']        as String?;
      _doctorRegNo   = data?['registrationNumber'] as String?;
    });
  }

  Future<void> _loadPatientInfo() async {
    if (widget.patientId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.patientId)
          .get();
      if (!mounted || !doc.exists) return;
      final data = doc.data()!;
      final dob    = data['dob']    as String? ?? '';
      final gender = data['gender'] as String? ?? '';
      String age = '--';
      if (dob.isNotEmpty) {
        try {
          final parts = dob.split('-');
          if (parts.length == 3) {
            final birthYear = int.parse(parts[0]);
            age = '${DateTime.now().year - birthYear} yrs';
          }
        } catch (_) {}
      }
      setState(() {
        _patientAge    = age;
        _patientGender = gender;
      });
    } catch (_) {}
  }

  String _generateRxId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'RX-${ts.toRadixString(36).toUpperCase().substring(3)}';
  }

  void _addMedicine() {
    setState(() => _medicines.add({
      'name': '',
      'dosage': '',
      'frequency': 'Twice daily',
      'duration': '5 days',
      'timing': 'After food',
    }));
  }

  Future<void> _submitPrescription() async {
    if (!_isSessionValid) {
      FeedbackService.showError(context, 'Please confirm you want to write an offline prescription.');
      return;
    }

    if (_diagnosisCtrl.text.trim().isEmpty) {
      FeedbackService.showError(context, 'Please enter a diagnosis before sending');
      return;
    }

    if (_medicines.isEmpty) {
      FeedbackService.showWarning(context, 'Consider adding at least one medicine to the prescription');
    }

    for (final med in _medicines) {
      if ((med['name'] as String).trim().isEmpty) {
        FeedbackService.showError(context, 'Please fill in all medicine names');
        return;
      }
    }

    setState(() => _saving = true);
    FeedbackService.showLoading(context, 'Sending prescription to patient...');
    try {
      final uid = DoctorAuthService.currentUid;
      final doctorName = _doctorName ?? 'Doctor';
      final doctorSpecialty = _doctorSpecialty ?? '';

      final rxId = _generateRxId();
      final adviceLines = _adviceCtrl.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      final prescriptionData = {
        'rxId':            rxId,
        'doctorId':        uid,
        'doctorName':      doctorName,
        'doctorSpecialty': doctorSpecialty,
        'doctorRegNo':     _doctorRegNo ?? '',
        'patientId':       widget.patientId,
        'patientName':     widget.patientName,
        'patientAge':      _patientAge ?? '--',
        'patientGender':   _patientGender ?? '--',
        'patientBloodGroup': '--',
        'diagnosis':       _diagnosisCtrl.text.trim(),
        'advice':          adviceLines,
        'medicines':       _medicines.map((m) => {
          'name':      m['name'],
          'dosage':    m['dosage'],
          'frequency': m['frequency'],
          'duration':  m['duration'],
          'timing':    m['timing'],
        }).toList(),
        'followUpRequired': _followUpRequired,
        'followUpDays':     _followUpRequired ? int.tryParse(_followUpDays) ?? 7 : null,
        'appointmentId':    widget.appointmentId,
        'consultationId':   widget.consultationId,
        'isOfflinePrescription': !widget.sessionValidated && widget.allowOffline,
        'createdAt':        FieldValue.serverTimestamp(),
      };

      final prescRef = await FirebaseFirestore.instance
          .collection('prescriptions')
          .add(prescriptionData);

      // Mark appointment as completed when applicable
      if (widget.appointmentId != null && widget.appointmentId!.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('appointments')
              .doc(widget.appointmentId!)
              .update({'status': 'completed'});
        } catch (_) {}
      }

      // Link prescription back to the consultation document
      if (widget.consultationId != null && widget.consultationId!.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('consultations')
              .doc(widget.consultationId!)
              .update({
            'prescriptionId': prescRef.id,
            'prescriptionWritten': true,
          });
        } catch (_) {}
      }

      // Notify the doctor themselves
      if (uid != null && widget.patientId.isNotEmpty) {
        await NotificationService.addDoctorNotification(
          doctorId: uid,
          type: NotifType.summary,
          title: 'Prescription Sent',
          body: 'Prescription for ${widget.patientName} has been sent successfully.',
          payload: {'patientId': widget.patientId},
        );
      }

      // Write patient notification (immediate + follow-ups)
      if (widget.patientId.isNotEmpty) {
        final now = DateTime.now();
        final batch = FirebaseFirestore.instance.batch();
        final patientNotifRef = FirebaseFirestore.instance
            .collection('patient_notifications')
            .doc(widget.patientId)
            .collection('items')
            .doc();

        batch.set(patientNotifRef, {
          'type':           'prescription_received',
          'title':          'New Prescription from $doctorName',
          'body':           'Dr. $doctorName has written you a prescription for ${_diagnosisCtrl.text.trim()}. '
                            'Open the MedNU app to view and download.',
          'createdAt':      FieldValue.serverTimestamp(),
          'deliverAt':      Timestamp.fromDate(now),
          'isRead':         false,
          'doctorName':     doctorName,
          'doctorSpecialty':doctorSpecialty,
          'ctaLabel':       'View Prescription',
          'ctaRoute':       'records',
        });

        if (_followUpRequired) {
          final followUpRef = FirebaseFirestore.instance
              .collection('patient_notifications')
              .doc(widget.patientId)
              .collection('items')
              .doc();
          final followUpDate = now.add(Duration(days: int.tryParse(_followUpDays) ?? 7));
          batch.set(followUpRef, {
            'type':       'appointment_reminder',
            'title':      'Follow-up Reminder 📅',
            'body':       'Dr. $doctorName recommends a follow-up in $_followUpDays days. Book your appointment now.',
            'createdAt':  FieldValue.serverTimestamp(),
            'deliverAt':  Timestamp.fromDate(followUpDate),
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
        metadata: {'patientId': widget.patientId, 'appointmentId': widget.appointmentId},
      );
      if (!mounted) return;
      FeedbackService.dismiss(context);
      _showSuccessDialog();
    } catch (e) {
      await OperationLogger.logError(
        action: DoctorOpAction.prescriptionSent,
        errorDetails: e.toString(),
        message: 'Failed to send prescription to ${widget.patientName}',
      );
      if (!mounted) return;
      FeedbackService.showError(
        context,
        'Failed to send prescription. Please try again.',
        onRetry: _submitPrescription,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 70, height: 70,
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 16),
          Text('Prescription Sent! ✅', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          Text(
            '${widget.patientName} has been notified via the MedNU app.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go(AppRoutes.dashboard);
            },
            child: const Text('Back to Dashboard'),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _diagnosisCtrl.dispose();
    _adviceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Write Prescription',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            TextButton(
              onPressed: _isSessionValid ? _submitPrescription : null,
              child: Text(
                'Send',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: _isSessionValid ? Colors.white : Colors.white38,
                ),
              ),
            ),
        ],
      ),
      body: _isSessionValid ? _buildForm() : _buildInvalidSessionState(),
    );
  }

  /// Shown when prescription is accessed without a live consultation session.
  Widget _buildInvalidSessionState() {
    // If allowOffline is true (from patient profile), show confirmation UI
    if (widget.allowOffline && widget.patientId.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_note_rounded,
                    color: AppColors.warning, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Offline Prescription', style: AppTextStyles.h3),
              const SizedBox(height: 10),
              const Text(
                'You are writing a prescription outside of a live consultation session. This will be saved as an offline prescription and sent to the patient.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Only write prescriptions for patients you have consulted with.',
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.warning, height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      setState(() => _offlineConfirmed = true),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Confirm & Write Prescription'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    }

    // No patient selected at all — hard block
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded,
                  color: AppColors.error, size: 40),
            ),
            const SizedBox(height: 20),
            Text('Prescription Locked', style: AppTextStyles.h3),
            const SizedBox(height: 10),
            const Text(
              'A prescription can only be written after a completed consultation where the patient has successfully joined the session.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.go(AppRoutes.dashboard),
              icon: const Icon(Icons.dashboard_rounded),
              label: const Text('Back to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Patient banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.all(Radius.circular(14))),
            child: Row(children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    widget.patientName.isNotEmpty ? widget.patientName : 'Patient',
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15),
                  ),
                  Text(
                    widget.patientId.isNotEmpty ? 'ID: ${widget.patientId.substring(0, 8)}...' : 'Walk-in patient',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70),
                  ),
                ]),
              ),
              const Text('Rx', style: TextStyle(fontFamily: 'Poppins', fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white54, fontStyle: FontStyle.italic)),
            ]),
          ),
          const SizedBox(height: 16),

          // Diagnosis
          Text('Diagnosis *', style: AppTextStyles.h4),
          const SizedBox(height: 8),
          TextField(
            controller: _diagnosisCtrl,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Enter diagnosis / clinical findings...'),
          ),
          const SizedBox(height: 16),

          // Medicines
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Medicines', style: AppTextStyles.h4),
            GestureDetector(
              onTap: _addMedicine,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: const BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.all(Radius.circular(10))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text('Add Medicine', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          if (_medicines.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(
                child: Text('Tap "Add Medicine" to add prescriptions',
                    style: TextStyle(fontFamily: 'Poppins', color: AppColors.textHint)),
              ),
            ),
          ..._medicines.asMap().entries.map((e) => _MedicineCard(
            index: e.key,
            medicine: e.value,
            onRemove: () => setState(() => _medicines.removeAt(e.key)),
            onUpdate: (key, val) => setState(() => _medicines[e.key][key] = val),
          )),
          const SizedBox(height: 16),

          // Advice
          Text('Doctor\'s Advice', style: AppTextStyles.h4),
          const SizedBox(height: 8),
          TextField(
            controller: _adviceCtrl,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Rest, diet, lifestyle advice...'),
          ),
          const SizedBox(height: 16),

          // Follow-up
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 3)),
              ],
            ),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
                const SizedBox(width: 10),
                Text('Follow-up Required', style: AppTextStyles.labelLarge),
                const Spacer(),
                Switch(
                  value: _followUpRequired,
                  onChanged: (v) => setState(() => _followUpRequired = v),
                  activeColor: AppColors.primary,
                ),
              ]),
              if (_followUpRequired) ...[
                const Divider(height: 16),
                Row(children: [
                  Text('Follow-up after', style: AppTextStyles.bodyMedium),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _followUpDays,
                    underline: const SizedBox(),
                    items: ['3', '5', '7', '10', '14', '30']
                        .map((d) => DropdownMenuItem(value: d, child: Text('$d days', style: AppTextStyles.labelLarge)))
                        .toList(),
                    onChanged: (v) => setState(() => _followUpDays = v!),
                  ),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: (_saving || !_isSessionValid)
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: (_saving || !_isSessionValid)
                    ? null
                    : [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: ElevatedButton.icon(
                onPressed: (_saving || !_isSessionValid) ? null : _submitPrescription,
                style: ElevatedButton.styleFrom(
                  backgroundColor: (_saving || !_isSessionValid) ? null : Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(_saving ? 'Sending...' : 'Send Prescription to Patient'),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _MedicineCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> medicine;
  final VoidCallback onRemove;
  final Function(String, String) onUpdate;

  const _MedicineCard({
    required this.index,
    required this.medicine,
    required this.onRemove,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 24, height: 24,
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
            child: Center(child: Text('${index + 1}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white))),
          ),
          const SizedBox(width: 8),
          Text('Medicine ${index + 1}', style: AppTextStyles.labelLarge),
          const Spacer(),
          GestureDetector(onTap: onRemove, child: const Icon(Icons.close_rounded, color: AppColors.error, size: 20)),
        ]),
        const SizedBox(height: 10),
        TextField(
          onChanged: (v) => onUpdate('name', v),
          decoration: const InputDecoration(
            hintText: 'Medicine name (e.g. Paracetamol 500mg)',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            onChanged: (v) => onUpdate('dosage', v),
            decoration: const InputDecoration(hintText: 'Dosage (1 tab)', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          )),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            onChanged: (v) => onUpdate('duration', v),
            decoration: const InputDecoration(hintText: 'Duration (5 days)', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            value: medicine['frequency'] as String,
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            items: ['Once daily', 'Twice daily', 'Three times daily', 'Four times daily', 'As needed']
                .map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12))))
                .toList(),
            onChanged: (v) => onUpdate('frequency', v!),
          )),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String>(
            value: medicine['timing'] as String,
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            items: ['Before food', 'After food', 'With food', 'Empty stomach', 'At bedtime']
                .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12))))
                .toList(),
            onChanged: (v) => onUpdate('timing', v!),
          )),
        ]),
      ]),
    );
  }
}
