import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// Typed "Details" the client's document checklist asks for next to the file
/// slots `lab_technician_details`, `pathologist_registration` (lab) and
/// `pharmacist_registration` (pharmacy / equipment).
///
/// Stored on `{role}_profiles/{uid}.staffDetails`:
/// `{ labTechnician: {name, registrationNo, qualification?},
///    specialist:    {type, name, registrationNo},
///    pharmacist:    {name, registrationNo} }`
/// (only the keys relevant to the role are written).
///
/// Enforced only for NEW applications — already-approved partners have no
/// `staffDetails` and are never blocked on it (see PartnerDocumentType.missingFor).
class StaffDetails {
  StaffDetails._();

  static const maxLen = 80;
  static const specialistTypes = ['Pathologist', 'Biochemist', 'Microbiologist'];

  /// Roles that collect typed staff details.
  static bool appliesTo(String role) =>
      role == 'lab' || role == 'pharmacy' || role == 'equipment';

  static bool isLab(String role) => role == 'lab';
}

/// Owns the text controllers / specialist type for [StaffDetailsFields] and
/// builds the Firestore map. Create one per screen, [dispose] it with the
/// screen.
class StaffDetailsController extends ChangeNotifier {
  StaffDetailsController(this.role, {Map<String, dynamic>? initial}) {
    if (initial != null) load(initial);
  }

  /// 'lab' | 'pharmacy' | 'equipment'.
  final String role;

  final techName = TextEditingController();
  final techRegNo = TextEditingController();
  final techQualification = TextEditingController();
  final specialistName = TextEditingController();
  final specialistRegNo = TextEditingController();
  final pharmacistName = TextEditingController();
  final pharmacistRegNo = TextEditingController();
  String? _specialistType;

  String? get specialistType => _specialistType;
  set specialistType(String? v) {
    _specialistType = v;
    notifyListeners();
  }

  bool get isLab => StaffDetails.isLab(role);

  static Map<String, dynamic> _sub(Object? raw) =>
      raw is Map ? Map<String, dynamic>.from(raw) : const {};

  static String _s(Map<String, dynamic> m, String k) => m[k]?.toString() ?? '';

  /// Fill the controllers from a stored / pending `staffDetails` map.
  void load(Map<String, dynamic> map) {
    final tech = _sub(map['labTechnician']);
    techName.text = _s(tech, 'name');
    techRegNo.text = _s(tech, 'registrationNo');
    techQualification.text = _s(tech, 'qualification');
    final spec = _sub(map['specialist']);
    specialistName.text = _s(spec, 'name');
    specialistRegNo.text = _s(spec, 'registrationNo');
    final t = _s(spec, 'type');
    _specialistType = StaffDetails.specialistTypes.contains(t) ? t : null;
    final ph = _sub(map['pharmacist']);
    pharmacistName.text = _s(ph, 'name');
    pharmacistRegNo.text = _s(ph, 'registrationNo');
    notifyListeners();
  }

  /// Live `staffDetails` with any not-yet-approved `pendingChanges.staffDetails`
  /// layered on top (sub-map by sub-map), i.e. what the partner last submitted.
  static Map<String, dynamic> effective(Object? live, Object? pendingChanges) {
    final out = _sub(live);
    final pending = pendingChanges is Map ? pendingChanges['staffDetails'] : null;
    if (pending is Map) {
      pending.forEach((k, v) => out[k.toString()] = v);
    }
    return out;
  }

  /// Whether the typed values differ from [stored] (so an unchanged profile
  /// save does not needlessly send `staffDetails` for admin review).
  bool differsFrom(Map<String, dynamic> stored) {
    final mine = toMap();
    for (final key in mine.keys) {
      final a = _sub(mine[key]);
      final b = _sub(stored[key]);
      final keys = {...a.keys, ...b.keys};
      for (final k in keys) {
        if ((a[k]?.toString() ?? '') != (b[k]?.toString() ?? '')) return true;
      }
    }
    return false;
  }

  /// True when every typed field is empty — used so a legacy partner (no
  /// staff details yet) can still save other profile edits without being
  /// forced to fill these in.
  bool get isBlank {
    final all = isLab
        ? [techName, techRegNo, techQualification, specialistName, specialistRegNo]
        : [pharmacistName, pharmacistRegNo];
    return all.every((c) => c.text.trim().isEmpty) &&
        (!isLab || _specialistType == null);
  }

  /// True when nothing has been stored for this role (legacy partner).
  static bool isEmpty(String role, Map<String, dynamic> map) {
    if (StaffDetails.isLab(role)) {
      return _sub(map['labTechnician']).isEmpty && _sub(map['specialist']).isEmpty;
    }
    return _sub(map['pharmacist']).isEmpty;
  }

  static String? _required(String? v, String label) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return '$label is required';
    if (t.length > StaffDetails.maxLen) {
      return '$label must be ${StaffDetails.maxLen} characters or fewer';
    }
    return null;
  }

  static String? validateRequired(String? v, String label) =>
      _required(v, label);

  static String? validateOptional(String? v, String label) {
    if ((v ?? '').trim().length > StaffDetails.maxLen) {
      return '$label must be ${StaffDetails.maxLen} characters or fewer';
    }
    return null;
  }

  /// First validation problem, or null when valid — for screens that validate
  /// manually (profile edit) rather than through a [Form].
  String? firstError() {
    if (isLab) {
      return _required(techName.text, 'Lab technician name') ??
          _required(techRegNo.text, 'Lab technician registration number') ??
          validateOptional(techQualification.text, 'Qualification') ??
          (_specialistType == null ? 'Select the specialist type' : null) ??
          _required(specialistName.text, 'Specialist name') ??
          _required(specialistRegNo.text, 'Specialist registration number');
    }
    return _required(pharmacistName.text, 'Pharmacist name') ??
        _required(pharmacistRegNo.text, 'Pharmacist registration number');
  }

  /// The `staffDetails` map for this role (values trimmed). Call only after
  /// validation passes.
  Map<String, dynamic> toMap() {
    if (isLab) {
      final qual = techQualification.text.trim();
      return {
        'labTechnician': {
          'name': techName.text.trim(),
          'registrationNo': techRegNo.text.trim(),
          if (qual.isNotEmpty) 'qualification': qual,
        },
        'specialist': {
          'type': _specialistType ?? '',
          'name': specialistName.text.trim(),
          'registrationNo': specialistRegNo.text.trim(),
        },
      };
    }
    return {
      'pharmacist': {
        'name': pharmacistName.text.trim(),
        'registrationNo': pharmacistRegNo.text.trim(),
      },
    };
  }

  @override
  void dispose() {
    techName.dispose();
    techRegNo.dispose();
    techQualification.dispose();
    specialistName.dispose();
    specialistRegNo.dispose();
    pharmacistName.dispose();
    pharmacistRegNo.dispose();
    super.dispose();
  }
}

/// Form fields for [StaffDetailsController]. Place inside a [Form] to get
/// inline errors on `validate()`; with [enabled] false it renders nothing
/// editable (callers show a read-only view instead).
class StaffDetailsFields extends StatelessWidget {
  final StaffDetailsController controller;

  /// When true, errors show as soon as the user edits a field (profile edit);
  /// registration relies on the surrounding Form's `validate()`.
  final bool validateOnInteraction;

  const StaffDetailsFields({
    super.key,
    required this.controller,
    this.validateOnInteraction = false,
  });

  AutovalidateMode get _auto => validateOnInteraction
      ? AutovalidateMode.onUserInteraction
      : AutovalidateMode.disabled;

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool required = true,
  }) {
    return TextFormField(
      controller: ctrl,
      autovalidateMode: _auto,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      inputFormatters: [LengthLimitingTextInputFormatter(StaffDetails.maxLen)],
      validator: (v) => required
          ? StaffDetailsController.validateRequired(v, label)
          : StaffDetailsController.validateOptional(v, label),
      decoration: InputDecoration(
        labelText: required ? label : '$label (optional)',
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: AppTextStyles.labelLarge),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.isLab) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading('Lab Technician Details'),
              _field(controller.techName, 'Full name', Icons.person_outline_rounded),
              const SizedBox(height: 12),
              _field(controller.techRegNo, 'Registration / licence number',
                  Icons.badge_outlined),
              const SizedBox(height: 12),
              _field(controller.techQualification, 'Qualification',
                  Icons.school_outlined,
                  required: false),
              const SizedBox(height: 20),
              _heading('Biochemist / Pathologist / Microbiologist Details'),
              DropdownButtonFormField<String>(
                initialValue: controller.specialistType,
                isExpanded: true,
                autovalidateMode: _auto,
                validator: (v) => v == null ? 'Select the specialist type' : null,
                decoration: const InputDecoration(
                  labelText: 'Specialist type',
                  prefixIcon: Icon(Icons.science_outlined,
                      color: AppColors.textSecondary),
                ),
                items: [
                  for (final t in StaffDetails.specialistTypes)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => controller.specialistType = v,
              ),
              const SizedBox(height: 12),
              _field(controller.specialistName, 'Full name',
                  Icons.person_outline_rounded),
              const SizedBox(height: 12),
              _field(controller.specialistRegNo, 'Registration number',
                  Icons.badge_outlined),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading('Pharmacist Details'),
            _field(controller.pharmacistName, 'Full name', Icons.person_outline_rounded),
            const SizedBox(height: 12),
            _field(controller.pharmacistRegNo, 'Pharmacy council registration number',
                Icons.badge_outlined),
          ],
        );
      },
    );
  }
}

/// Read-only summary of a stored `staffDetails` map, for profile screens.
class StaffDetailsReadOnly extends StatelessWidget {
  final String role;
  final Map<String, dynamic> details;

  const StaffDetailsReadOnly({super.key, required this.role, required this.details});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> sub(String k) {
      final v = details[k];
      return v is Map ? Map<String, dynamic>.from(v) : const {};
    }

    Widget row(String label, String? value) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              Text(
                (value == null || value.isEmpty) ? '—' : value,
                style: AppTextStyles.bodyLarge,
              ),
            ],
          ),
        );

    if (StaffDetailsController.isEmpty(role, details)) {
      return const Text(
        'Not provided yet. Tap Edit Profile to add these details.',
        style: AppTextStyles.caption,
      );
    }
    if (StaffDetails.isLab(role)) {
      final t = sub('labTechnician');
      final s = sub('specialist');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Lab Technician', style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
          row('Full name', t['name']?.toString()),
          row('Registration / licence number', t['registrationNo']?.toString()),
          row('Qualification', t['qualification']?.toString()),
          const SizedBox(height: 4),
          const Text('Biochemist / Pathologist / Microbiologist',
              style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
          row('Specialist type', s['type']?.toString()),
          row('Full name', s['name']?.toString()),
          row('Registration number', s['registrationNo']?.toString()),
        ],
      );
    }
    final p = sub('pharmacist');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('Full name', p['name']?.toString()),
        row('Pharmacy council registration number',
            p['registrationNo']?.toString()),
      ],
    );
  }
}
