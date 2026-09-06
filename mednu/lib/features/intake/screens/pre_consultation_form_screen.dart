import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../services/intake_service.dart';

typedef _Item = ({String key, String label});

const _kSymptoms = <_Item>[
  (key: 'fever', label: 'Fever'),
  (key: 'cough', label: 'Cough'),
  (key: 'sore_throat', label: 'Sore throat'),
  (key: 'breathlessness', label: 'Shortness of breath'),
  (key: 'chest_pain', label: 'Chest pain'),
  (key: 'abdominal_pain', label: 'Abdominal pain'),
  (key: 'nausea_vomiting', label: 'Nausea or vomiting'),
  (key: 'diarrhea', label: 'Diarrhea'),
  (key: 'headache', label: 'Headache'),
  (key: 'dizziness', label: 'Dizziness'),
  (key: 'fatigue', label: 'Unusual fatigue'),
  (key: 'joint_pain', label: 'Joint or body pain'),
  (key: 'weight_loss', label: 'Unexplained weight loss'),
  (key: 'skin_rash', label: 'Skin rash'),
];

const _kComorbidities = <_Item>[
  (key: 'diabetes', label: 'Diabetes'),
  (key: 'hypertension', label: 'High blood pressure'),
  (key: 'heart_disease', label: 'Heart disease'),
  (key: 'asthma_copd', label: 'Asthma or COPD'),
  (key: 'kidney_disease', label: 'Kidney disease'),
  (key: 'liver_disease', label: 'Liver disease'),
  (key: 'thyroid', label: 'Thyroid disorder'),
  (key: 'cancer', label: 'Cancer (past or present)'),
  (key: 'tuberculosis', label: 'Tuberculosis'),
  (key: 'other_comorbid', label: 'Other ongoing condition'),
];

const _kTreatments = <_Item>[
  (key: 'past_surgery', label: 'Any past surgery'),
  (key: 'past_hospital', label: 'Any past hospitalization'),
  (key: 'ongoing_treatment', label: 'Currently under treatment elsewhere'),
];

const _kAllergies = <_Item>[
  (key: 'drug_allergy', label: 'Drug allergy'),
  (key: 'food_allergy', label: 'Food allergy'),
  (key: 'other_allergy', label: 'Other allergy (dust, latex, etc.)'),
];

const _kFamilyHistory = <_Item>[
  (key: 'fam_diabetes', label: 'Diabetes'),
  (key: 'fam_heart', label: 'Heart disease'),
  (key: 'fam_cancer', label: 'Cancer'),
  (key: 'fam_hypertension', label: 'High blood pressure'),
  (key: 'fam_mental', label: 'Mental health conditions'),
];

const _kDurations = [
  'Today',
  '2-3 days ago',
  'About a week ago',
  '2-4 weeks ago',
  '1-6 months ago',
  'Over 6 months ago',
];
const _kSeverities = ['Mild', 'Moderate', 'Severe'];
const _kGenders = ['Male', 'Female', 'Other', 'Prefer not to say'];

class _MedRow {
  final TextEditingController name = TextEditingController();
  final TextEditingController dose = TextEditingController();
  void dispose() {
    name.dispose();
    dose.dispose();
  }
}

/// Two modes, chosen by whether [appointmentId] is given:
///
/// - Pre-payment (appointmentId null) — used by every doctor-booking flow
///   (DoctorBookingFlow.collectIntake) before the booking even exists yet.
///   Mandatory: no "Skip for now" here, since without it a patient could
///   book without ever giving the doctor any history. "Submit & Continue"
///   just pops the collected answers as a Map (nothing is written to
///   Firestore yet — there's no appointment/consultation id to key the doc
///   on until payment succeeds); backing out via the close icon or the
///   system back gesture cancels the booking attempt entirely instead of
///   letting it through with no data (see _confirmCancelBooking).
/// - Post-booking (appointmentId given) — the "fill it later" recovery path
///   from My Appointments (see _IntakePendingChip in appointment_screen.dart).
///   The appointment already exists here, so skipping is still allowed (see
///   _confirmSkip) — it only defers filling in history the doctor doesn't
///   have yet, it can't un-book anything. Writes straight to
///   `patient_intake_forms/{appointmentId}`, which MedNU Doctor streams live
///   into the appointment card (pre_consultation_summary_card.dart).
class PreConsultationFormScreen extends StatefulWidget {
  final String? appointmentId;
  final String doctorId;
  final String doctorName;
  final String doctorSpecialty;

  const PreConsultationFormScreen({
    super.key,
    this.appointmentId,
    required this.doctorId,
    required this.doctorName,
    this.doctorSpecialty = '',
  });

  @override
  State<PreConsultationFormScreen> createState() =>
      _PreConsultationFormScreenState();
}

class _PreConsultationFormScreenState extends State<PreConsultationFormScreen> {
  final _ageCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _symptomsOtherCtrl = TextEditingController();

  final Map<String, bool> _yn = {};
  final Map<String, TextEditingController> _detailCtrls = {};
  final List<_MedRow> _medRows = [_MedRow()];

  String? _gender;
  String? _duration;
  String? _severity;

  bool _submitting = false;
  String? _profileAllergiesHint;
  String? _profileConditionsHint;

  TextEditingController _detailCtrl(String key) =>
      _detailCtrls.putIfAbsent(key, () => TextEditingController());

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data();
      if (data == null || !mounted) return;
      final dob = data['dob'] as String? ?? '';
      if (dob.isNotEmpty) {
        try {
          final years = DateTime.now().year - DateTime.parse(dob).year;
          if (years > 0 && years < 130) _ageCtrl.text = years.toString();
        } catch (_) {}
      }
      final g = data['gender'] as String?;
      if (g != null && _kGenders.contains(g)) _gender = g;
      _phoneCtrl.text =
          FirebaseAuth.instance.currentUser?.phoneNumber?.trim() ?? '';
      final allergies = (data['allergies'] as String? ?? '').trim();
      final conditions = (data['chronicConditions'] as String? ?? '').trim();
      setState(() {
        if (allergies.isNotEmpty) _profileAllergiesHint = allergies;
        if (conditions.isNotEmpty) _profileConditionsHint = conditions;
      });
    } catch (_) {
      // Non-critical — the form still works with blank fields.
    }
  }

  @override
  void dispose() {
    _ageCtrl.dispose();
    _phoneCtrl.dispose();
    _reasonCtrl.dispose();
    _symptomsOtherCtrl.dispose();
    for (final c in _detailCtrls.values) {
      c.dispose();
    }
    for (final r in _medRows) {
      r.dispose();
    }
    super.dispose();
  }

  bool _isYes(String key) => _yn[key] ?? false;

  void _toggle(String key, bool value) {
    setState(() => _yn[key] = value);
  }

  List<String> _activeKeys(List<_Item> items) =>
      items.where((i) => _isYes(i.key)).map((i) => i.label).toList();

  List<Map<String, String>> _activeWithDetail(List<_Item> items) => items
      .where((i) => _isYes(i.key))
      .map((i) => {
            'label': i.label,
            'detail': _detailCtrl(i.key).text.trim(),
          })
      .toList();

  Map<String, dynamic> _buildData() {
    final medications = _medRows
        .where((r) => r.name.text.trim().isNotEmpty)
        .map((r) => {'name': r.name.text.trim(), 'dose': r.dose.text.trim()})
        .toList();
    return {
      'age': _ageCtrl.text.trim(),
      'gender': _gender ?? '',
      'phone': _phoneCtrl.text.trim(),
      'reasonForVisit': _reasonCtrl.text.trim(),
      'symptoms': _activeKeys(_kSymptoms),
      'otherSymptoms': _symptomsOtherCtrl.text.trim(),
      'symptomDuration': _duration ?? '',
      'symptomSeverity': _severity ?? '',
      'comorbidities': _activeWithDetail(_kComorbidities),
      'treatments': _activeWithDetail(_kTreatments),
      'onMedication': _isYes('on_medication'),
      'medications': medications,
      'allergies': _activeWithDetail(_kAllergies),
      'familyHistory': _activeKeys(_kFamilyHistory),
      'lifestyle': {
        'smoking': _isYes('smoking'),
        'alcohol': _isYes('alcohol'),
        'pregnant': _isYes('pregnant'),
      },
    };
  }

  /// At least one value the patient actually chose or typed — a form with
  /// nothing but blank defaults doesn't give the doctor anything useful.
  bool _hasAnyValue(Map<String, dynamic> data) {
    bool nonEmpty(dynamic v) {
      if (v is String) return v.trim().isNotEmpty;
      if (v is List) return v.isNotEmpty;
      if (v is bool) return v;
      if (v is Map) return v.values.any(nonEmpty);
      return false;
    }
    return data.values.any(nonEmpty);
  }

  bool get _isPrePayment => widget.appointmentId == null;

  Future<void> _submit() async {
    if (_submitting) return;
    final data = _buildData();
    if (!_hasAnyValue(data)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isPrePayment
            ? 'Please fill in at least one detail before continuing — this is required to book.'
            : 'Please fill in at least one detail before continuing — or use "Skip for now".'),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    // Pre-payment mode — no appointment/consultation exists yet, so just
    // hand the answers back to the caller (see DoctorBookingFlow).
    if (widget.appointmentId == null) {
      Navigator.of(context).pop(data);
      return;
    }

    setState(() => _submitting = true);
    try {
      await IntakeService.submit(
        appointmentId: widget.appointmentId!,
        doctorId: widget.doctorId,
        doctorName: widget.doctorName,
        data: data,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save your form: ${e.toString().replaceAll('Exception: ', '')}'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Post-booking "fill it later" mode only — the appointment already
  /// exists, so this is a genuine skip: the doctor just won't have the
  /// patient's history ahead of time.
  Future<void> _confirmSkip() async {
    final skip = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Skip pre-consultation form?',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Your appointment stays booked either way. Without this, your doctor '
          'won\'t have your history ahead of the visit — you can still fill it '
          'in from My Appointments before then.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Filling'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (skip != true || !mounted) return;
    Navigator.of(context).pop(false);
  }

  /// Pre-payment mode only — this form is mandatory to book, so there's no
  /// "skip and book anyway". Leaving now abandons the booking attempt
  /// entirely (pop(null), which DoctorBookingFlow's callers already treat as
  /// "nothing was booked, reset and stop").
  Future<void> _confirmCancelBooking() async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Cancel this booking?',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Dr. ${widget.doctorName} requires a few details before you can book. '
          'Leaving now cancels this booking — nothing is charged and you can '
          'start again anytime.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Filling'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    if (cancel != true || !mounted) return;
    Navigator.of(context).pop(null);
  }

  void _handleExit() => _isPrePayment ? _confirmCancelBooking() : _confirmSkip();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleExit();
      },
      child: Scaffold(
        backgroundColor: context.appBackground,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Pre-Consultation Form',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: _isPrePayment ? 'Cancel booking' : 'Skip for now',
              onPressed: _submitting ? null : _handleExit,
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.primary,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Text(
                widget.doctorSpecialty.isNotEmpty
                    ? 'Help Dr. ${widget.doctorName} (${widget.doctorSpecialty}) prepare for your visit — takes about 3 minutes.'
                    : 'Help Dr. ${widget.doctorName} prepare for your visit — takes about 3 minutes.',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: Color(0xFFEBDCE7), height: 1.5),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _SectionCard(
                    title: 'Visit Details',
                    subtitle: 'Basic information for this appointment.',
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                          child: _LabeledField(
                            label: 'Age',
                            child: TextField(
                              controller: _ageCtrl,
                              keyboardType: TextInputType.number,
                              decoration: _inputDecoration(hint: 'Years'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _LabeledField(
                            label: 'Gender',
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('gender-$_gender'),
                              initialValue: _gender,
                              isExpanded: true,
                              decoration: _inputDecoration(),
                              items: _kGenders
                                  .map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5))))
                                  .toList(),
                              onChanged: (v) => setState(() => _gender = v),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      _LabeledField(
                        label: 'Contact number',
                        child: TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: _inputDecoration(hint: 'Phone number'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _LabeledField(
                        label: 'Reason for today\'s consultation',
                        child: TextField(
                          controller: _reasonCtrl,
                          maxLines: 3,
                          decoration: _inputDecoration(hint: 'Briefly describe why you\'re seeking care today'),
                        ),
                      ),
                    ]),
                  ),

                  _SectionCard(
                    title: 'Current Symptoms',
                    subtitle: 'Tap yes if you are currently experiencing this.',
                    child: Column(children: [
                      ..._kSymptoms.map((item) => _YesNoTile(
                            label: item.label,
                            value: _isYes(item.key),
                            onChanged: (v) => _toggle(item.key, v),
                          )),
                      const SizedBox(height: 14),
                      _LabeledField(
                        label: 'Other symptoms not listed above',
                        child: TextField(
                          controller: _symptomsOtherCtrl,
                          maxLines: 2,
                          decoration: _inputDecoration(hint: 'Describe any other symptoms'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: _LabeledField(
                            label: 'Symptoms started',
                            child: DropdownButtonFormField<String>(
                              initialValue: _duration,
                              isExpanded: true,
                              decoration: _inputDecoration(),
                              items: _kDurations.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5)))).toList(),
                              onChanged: (v) => setState(() => _duration = v),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _LabeledField(
                            label: 'Severity',
                            child: DropdownButtonFormField<String>(
                              initialValue: _severity,
                              isExpanded: true,
                              decoration: _inputDecoration(),
                              items: _kSeverities.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)))).toList(),
                              onChanged: (v) => setState(() => _severity = v),
                            ),
                          ),
                        ),
                      ]),
                    ]),
                  ),

                  _SectionCard(
                    title: 'Existing Medical Conditions',
                    subtitle: 'Also called comorbidities — conditions you currently have or are being treated for.',
                    hint: _profileConditionsHint == null ? null : 'From your profile: $_profileConditionsHint',
                    child: Column(
                      children: _kComorbidities
                          .map((item) => _YesNoTile(
                                label: item.label,
                                value: _isYes(item.key),
                                onChanged: (v) => _toggle(item.key, v),
                                detailController: _detailCtrl(item.key),
                                detailHint: 'Name the condition and how it is managed',
                              ))
                          .toList(),
                    ),
                  ),

                  _SectionCard(
                    title: 'Previous Treatment or Surgery',
                    subtitle: 'Any past hospitalizations, surgeries, or major treatments.',
                    child: Column(
                      children: _kTreatments
                          .map((item) => _YesNoTile(
                                label: item.label,
                                value: _isYes(item.key),
                                onChanged: (v) => _toggle(item.key, v),
                                detailController: _detailCtrl(item.key),
                                detailHint: 'Describe what and when',
                              ))
                          .toList(),
                    ),
                  ),

                  _SectionCard(
                    title: 'Current Medications',
                    child: Column(children: [
                      _YesNoTile(
                        label: 'Are you currently taking any medications?',
                        value: _isYes('on_medication'),
                        onChanged: (v) => _toggle('on_medication', v),
                        noBottomBorder: true,
                      ),
                      if (_isYes('on_medication')) ...[
                        const SizedBox(height: 4),
                        ..._medRows.asMap().entries.map((e) => _MedicationRow(
                              row: e.value,
                              onRemove: _medRows.length > 1
                                  ? () => setState(() {
                                        e.value.dispose();
                                        _medRows.removeAt(e.key);
                                      })
                                  : null,
                            )),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _medRows.add(_MedRow())),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add medication'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4), style: BorderStyle.solid),
                            minimumSize: const Size.fromHeight(42),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ]),
                  ),

                  _SectionCard(
                    title: 'Allergies',
                    subtitle: 'Include drug, food, or other allergies. This is important for your safety.',
                    hint: _profileAllergiesHint == null ? null : 'From your profile: $_profileAllergiesHint',
                    hintIsDanger: true,
                    child: Column(
                      children: _kAllergies
                          .map((item) => _YesNoTile(
                                label: item.label,
                                value: _isYes(item.key),
                                onChanged: (v) => _toggle(item.key, v),
                                detailController: _detailCtrl(item.key),
                                detailHint: 'Name the allergen and reaction',
                                dangerMode: true,
                              ))
                          .toList(),
                    ),
                  ),

                  _SectionCard(
                    title: 'Family History',
                    subtitle: 'Conditions that run in your immediate family (parents, siblings).',
                    child: Column(
                      children: _kFamilyHistory
                          .map((item) => _YesNoTile(
                                label: item.label,
                                value: _isYes(item.key),
                                onChanged: (v) => _toggle(item.key, v),
                              ))
                          .toList(),
                    ),
                  ),

                  _SectionCard(
                    title: 'Lifestyle',
                    child: Column(children: [
                      _YesNoTile(
                        label: 'Do you currently smoke?',
                        value: _isYes('smoking'),
                        onChanged: (v) => _toggle('smoking', v),
                      ),
                      _YesNoTile(
                        label: 'Do you drink alcohol?',
                        value: _isYes('alcohol'),
                        onChanged: (v) => _toggle('alcohol', v),
                      ),
                      if (_gender != 'Male')
                        _YesNoTile(
                          label: 'Currently pregnant or trying to conceive?',
                          value: _isYes('pregnant'),
                          onChanged: (v) => _toggle('pregnant', v),
                          noBottomBorder: true,
                        ),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              color: context.appSurface,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Submit & Continue', style: TextStyle(fontFamily: 'Poppins', fontSize: 15.5, fontWeight: FontWeight.w700)),
                ),
              ),
              if (!_isPrePayment) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _submitting ? null : _confirmSkip,
                  child: Text('Skip for now', style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
        filled: true,
        fillColor: context.appSurface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.appBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.appBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section card
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? hint;
  final bool hintIsDanger;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.subtitle,
    this.hint,
    this.hintIsDanger = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTextStyles.h4),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle!, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
        ],
        if (hint != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: (hintIsDanger ? AppColors.error : AppColors.accent).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: (hintIsDanger ? AppColors.error : AppColors.accent).withValues(alpha: 0.25)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(hintIsDanger ? Icons.warning_amber_rounded : Icons.info_outline_rounded, size: 15, color: hintIsDanger ? AppColors.error : AppColors.accentText),
              const SizedBox(width: 8),
              Expanded(child: Text(hint!, style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: hintIsDanger ? AppColors.error : AppColors.accentText, height: 1.4))),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: context.appTextPrimary)),
        const SizedBox(height: 6),
        child,
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Yes/No tile — mirrors the HTML form's segmented pill toggle
// ─────────────────────────────────────────────────────────────────────────────

class _YesNoTile extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final TextEditingController? detailController;
  final String? detailHint;
  final bool dangerMode;
  final bool noBottomBorder;

  const _YesNoTile({
    required this.label,
    required this.value,
    required this.onChanged,
    this.detailController,
    this.detailHint,
    this.dangerMode = false,
    this.noBottomBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = dangerMode ? AppColors.error : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: noBottomBorder ? null : Border(bottom: BorderSide(color: context.appDivider)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5, color: context.appTextPrimary)),
          ),
          const SizedBox(width: 10),
          _Segmented(value: value, onChanged: onChanged, activeColor: activeColor),
        ]),
        if (value && detailController != null) ...[
          const SizedBox(height: 8),
          TextField(
            controller: detailController,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5),
            decoration: InputDecoration(
              hintText: detailHint,
              hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint),
              filled: true,
              fillColor: activeColor.withValues(alpha: 0.04),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: activeColor.withValues(alpha: 0.25))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: activeColor.withValues(alpha: 0.25))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: activeColor, width: 1.5)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Segmented extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;
  const _Segmented({required this.value, required this.onChanged, required this.activeColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.appBorder),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _segBtn('No', !value, context.appTextSecondary, () => onChanged(false)),
        _segBtn('Yes', value, activeColor, () => onChanged(true)),
      ]),
    );
  }

  Widget _segBtn(String label, bool active, Color activeColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        color: active ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
        child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: active ? activeColor : Colors.grey)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Medication row
// ─────────────────────────────────────────────────────────────────────────────

class _MedicationRow extends StatelessWidget {
  final _MedRow row;
  final VoidCallback? onRemove;
  const _MedicationRow({required this.row, this.onRemove});

  @override
  Widget build(BuildContext context) {
    InputDecoration decoration(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint),
          filled: true,
          fillColor: context.appBackground,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: context.appBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: context.appBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          flex: 5,
          child: TextField(controller: row.name, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13), decoration: decoration('Medication name')),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: TextField(controller: row.dose, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13), decoration: decoration('Dose / frequency')),
        ),
        if (onRemove != null)
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.error),
            onPressed: onRemove,
            padding: const EdgeInsets.only(left: 4),
            constraints: const BoxConstraints(),
          ),
      ]),
    );
  }
}
