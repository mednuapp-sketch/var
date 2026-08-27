import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../features/location/models/precise_address.dart';
import '../../../features/location/screens/map_location_picker_screen.dart';
import '../../../shared_core/documents/partner_document_models.dart';
import '../../../shared_core/documents/partner_document_service.dart';
import '../../../shared_core/models/app_role.dart';
import '../../ambulance/services/ambulance_profile_service.dart';
import '../../caregiver/services/caregiver_profile_service.dart';
import '../../counselling/services/counselling_profile_service.dart';
import '../../lab/models/lab_profile.dart';
import '../../lab/services/lab_profile_service.dart';
import '../../pharmacy/models/pharmacy_profile.dart';
import '../../pharmacy/services/pharmacy_profile_service.dart';
import '../../physiotherapy/services/physio_profile_service.dart';
import '../services/doctor_auth_service.dart';

/// Registration for a brand-new non-Doctor partner account (Lab, Pharmacy,
/// Ambulance, Caregiver).
///
/// One screen parameterised by [role] rather than four near-identical
/// screens. It writes exactly two documents, in this order:
///
///  1. `doctors/{uid}` — the universal base identity document every role in
///     this app shares (`currentUserProvider` reads it regardless of role).
///     It is written sparsely on purpose: no `specialty`/`fee`/
///     `qualifications`, and `status: 'pending'` to match Doctor
///     registration's own default, so a partner account never surfaces in
///     the patient-facing doctor directory (which requires `status ==
///     'active'`). Crucially it carries `roles: [<role>]` — the field
///     `roleEngineProvider` reads and which nothing else in this codebase
///     has ever written.
///  2. `{role}_profiles/{uid}` — the role-specific operational profile, via
///     that role's existing `createProfile(...)`. No service method is
///     modified here; they are only called.
///
/// The Doctor role never reaches this screen — it keeps
/// `DoctorRegisterScreen` untouched.
class PartnerRoleRegisterScreen extends StatefulWidget {
  final AppRole role;

  const PartnerRoleRegisterScreen({super.key, required this.role});

  @override
  State<PartnerRoleRegisterScreen> createState() =>
      _PartnerRoleRegisterScreenState();
}

class _PartnerRoleRegisterScreenState extends State<PartnerRoleRegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  // Shared / Lab / Pharmacy / Caregiver
  final _nameCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  double? _addressLat;
  double? _addressLng;
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _deliveryAvailable = true;
  final _selectedServices = <String>{};
  final _selectedCategories = <String>{};

  // Ambulance
  final _plateCtrl = TextEditingController();
  final _vehicleTypeCtrl = TextEditingController();
  final _driverNameCtrl = TextEditingController();
  final _driverPhoneCtrl = TextEditingController();
  final _driverLicenseCtrl = TextEditingController();
  final _equipmentCtrl = TextEditingController();

  // Caregiver
  final _certificationsCtrl = TextEditingController();
  final _specialtiesCtrl = TextEditingController();
  final _hourlyRateCtrl = TextEditingController();

  bool _saving = false;

  // Verification documents, keyed by canonical docType — picked here and
  // held locally, uploaded once the profile document exists (during
  // _submit()). Required before submission so the pending-review screen
  // never needs its own upload step.
  final Map<String, File?> _pickedDocs = {};

  AppRole get _role => widget.role;

  @override
  void initState() {
    super.initState();
    // Phone is already verified by OTP at this point — pre-fill it so the
    // partner does not retype it, exactly as Doctor registration does.
    final authPhone = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    _phoneCtrl.text = authPhone;
    _driverPhoneCtrl.text = authPhone;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _licenseCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _plateCtrl.dispose();
    _vehicleTypeCtrl.dispose();
    _driverNameCtrl.dispose();
    _driverPhoneCtrl.dispose();
    _driverLicenseCtrl.dispose();
    _equipmentCtrl.dispose();
    _certificationsCtrl.dispose();
    _specialtiesCtrl.dispose();
    _hourlyRateCtrl.dispose();
    super.dispose();
  }

  /// Same comma-separated parsing the Ambulance vehicle-profile edit dialog
  /// already uses, so a list typed here round-trips identically there.
  List<String> _csv(TextEditingController ctrl) => ctrl.text
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// The human-facing name of this account — also what lands in
  /// `doctors/{uid}.name`. For Ambulance the account is the driver.
  String get _accountName => _role == AppRole.ambulance
      ? _driverNameCtrl.text.trim()
      : _nameCtrl.text.trim();

  /// The contact phone for this account.
  String get _accountPhone => _role == AppRole.ambulance
      ? _driverPhoneCtrl.text.trim()
      : _phoneCtrl.text.trim();

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_role == AppRole.lab && _selectedServices.isEmpty) {
      FeedbackService.showError(context, 'Select at least one service you offer.');
      return;
    }
    if (_role == AppRole.pharmacy && _selectedCategories.isEmpty) {
      FeedbackService.showError(context, 'Select at least one category you stock.');
      return;
    }

    final uid = DoctorAuthService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'Session expired. Please login again.');
      context.go(AppRoutes.login);
      return;
    }

    setState(() => _saving = true);
    try {
      // 1 ── Base identity document, shared by every role.
      //
      // Two distinct callers reach this screen: OTP verification for a
      // brand-new account (no `doctors/{uid}` doc yet — write it fresh),
      // and an already-registered account adding a second service from
      // the role switcher sheet (a doc already exists — only append the
      // new role, never overwrite the existing name/phone/status/roles).
      final doctorRef = FirebaseFirestore.instance.collection('doctors').doc(uid);
      final existingSnap = await doctorRef.get();

      if (existingSnap.exists) {
        await doctorRef.update({
          'roles': FieldValue.arrayUnion([_role.firestoreValue]),
        });
      } else {
        await doctorRef.set({
          'uid': uid,
          'name': _accountName,
          'phone': _accountPhone.isNotEmpty
              ? _accountPhone
              : FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
          'status': 'pending',
          'roles': [_role.firestoreValue],
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // 2 ── Role-specific operational profile.
      await _createRoleProfile(uid);

      // 3 ── Verification documents, uploaded now that the profile document
      // exists. Must run after step 2: `uploadDocument` merge-writes into
      // the profile doc, but `_createRoleProfile` writes with a plain
      // (non-merge) `set()` — uploading first would get clobbered.
      // `_documentPickerField`'s validator already guarantees every
      // required slot is non-null before the form lets `_submit()` run.
      final docTypes = PartnerDocumentType.forRole(_role.firestoreValue);
      if (docTypes.isNotEmpty) {
        final docService = PartnerDocumentService(_role.firestoreValue, uid);
        for (final type in docTypes) {
          final file = _pickedDocs[type.key];
          if (file != null) {
            await docService.uploadDocument(docType: type.key, file: file);
          }
        }
      }

      if (!mounted) return;
      if (existingSnap.exists) {
        // Adding a role to a working account — that account's own flow
        // keeps working exactly as before; only the new role is pending
        // review. Return to wherever this was opened from instead of the
        // brand-new-account waiting screen.
        FeedbackService.showSuccess(
          context,
          '${_role.label} application submitted — it will appear once approved.',
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } else {
        context.go(AppRoutes.verificationPending);
      }
    } catch (e, st) {
      debugPrint('[PartnerRoleRegister] submit failed for role=${_role.firestoreValue}: $e\n$st');
      if (!mounted) return;
      FeedbackService.showError(
        context,
        'Could not submit your application. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createRoleProfile(String uid) {
    switch (_role) {
      case AppRole.lab:
        return LabProfileService.createProfile(
          uid: uid,
          name: _nameCtrl.text.trim(),
          licenseNumber: _licenseCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          latitude: _addressLat,
          longitude: _addressLng,
          phone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          servicesOffered: _selectedServices.toList(),
        );
      case AppRole.pharmacy:
        return PharmacyProfileService.createProfile(
          uid: uid,
          name: _nameCtrl.text.trim(),
          licenseNumber: _licenseCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          latitude: _addressLat,
          longitude: _addressLng,
          phone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          deliveryAvailable: _deliveryAvailable,
          categoriesOffered: _selectedCategories.toList(),
        );
      case AppRole.ambulance:
        return AmbulanceProfileService.createProfile(
          uid: uid,
          plateNumber: _plateCtrl.text.trim(),
          vehicleType: _vehicleTypeCtrl.text.trim(),
          driverName: _driverNameCtrl.text.trim(),
          driverPhone: _driverPhoneCtrl.text.trim(),
          driverLicense: _driverLicenseCtrl.text.trim(),
          equipment: _csv(_equipmentCtrl),
        );
      case AppRole.caregiver:
        return CaregiverProfileService.createProfile(
          uid: uid,
          name: _nameCtrl.text.trim(),
          certifications: _csv(_certificationsCtrl),
          specialties: _csv(_specialtiesCtrl),
          hourlyRate: num.tryParse(_hourlyRateCtrl.text.trim()) ?? 0,
        );
      case AppRole.physiotherapist:
        return PhysioProfileService.createProfile(
          uid: uid,
          name: _nameCtrl.text.trim(),
          certifications: _csv(_certificationsCtrl),
          specialties: _csv(_specialtiesCtrl),
          hourlyRate: num.tryParse(_hourlyRateCtrl.text.trim()) ?? 0,
        );
      case AppRole.counsellor:
        return CounsellingProfileService.createProfile(
          uid: uid,
          name: _nameCtrl.text.trim(),
          certifications: _csv(_certificationsCtrl),
          specialties: _csv(_specialtiesCtrl),
          hourlyRate: num.tryParse(_hourlyRateCtrl.text.trim()) ?? 0,
        );
      case AppRole.nutritionist:
      case AppRole.doctor:
      case AppRole.admin:
        // Unreachable: the role-select screen never routes these here (see
        // PartnerRoleSelectScreen._allSelectableRoles — Nutritionist is
        // deliberately excluded from self-registration), and the router
        // falls back to Doctor registration for AppRole.doctor.
        return Future.value();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            GradientSliverAppBar(
              headerIcon: _role.icon,
              title: '${_role.label} Registration',
              subtitle: 'A few details before our team reviews your account',
              onBack: () {
                // Reached either via go_router (brand-new account, from
                // AppRoutes.partnerRoleSelect) or via a pushed Navigator
                // route (adding a service to an existing account, from the
                // role switcher sheet) — prefer a plain pop when there's a
                // local route to pop back to, so "add a service" doesn't
                // escape into the main router stack.
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.go(AppRoutes.partnerRoleSelect);
                }
              },
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  ..._fieldsForRole(),
                  ..._documentFieldsForRole(),
                  const SizedBox(height: 30),
                  GradientButton(
                    label: 'Submit for Approval',
                    icon: Icons.send_rounded,
                    isLoading: _saving,
                    onTap: _saving ? null : _submit,
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'Your application will be reviewed by our admin team.\n'
                      'You will be notified once approved.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption,
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Each role's field set mirrors exactly what its existing
  /// `createProfile(...)` accepts — no invented fields.
  List<Widget> _fieldsForRole() {
    switch (_role) {
      case AppRole.lab:
        return [
          _field(_nameCtrl, 'Lab / Diagnostic Center Name',
              Icons.storefront_rounded),
          const SizedBox(height: 14),
          _field(_licenseCtrl, 'License / Registration Number',
              Icons.badge_outlined),
          const SizedBox(height: 14),
          _addressPickerField('Lab Address'),
          const SizedBox(height: 14),
          _field(_phoneCtrl, 'Contact Phone', Icons.call_outlined,
              keyboardType: TextInputType.phone, locked: true),
          const SizedBox(height: 14),
          _field(_emailCtrl, 'Email Address', Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 22),
          const Text('Services You Offer', style: AppTextStyles.h4),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kLabServiceCatalog.map((service) {
              final selected = _selectedServices.contains(service);
              return FilterChip(
                label: Text(service),
                selected: selected,
                onSelected: (v) => setState(() {
                  v ? _selectedServices.add(service) : _selectedServices.remove(service);
                }),
                selectedColor: AppColors.primary.withValues(alpha: 0.14),
                checkmarkColor: AppColors.primary,
                labelStyle: AppTextStyles.labelMedium.copyWith(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              );
            }).toList(),
          ),
        ];
      case AppRole.pharmacy:
        return [
          _field(_nameCtrl, 'Pharmacy Name', Icons.storefront_rounded),
          const SizedBox(height: 14),
          _field(_licenseCtrl, 'Drug License Number', Icons.badge_outlined),
          const SizedBox(height: 14),
          _addressPickerField('Pharmacy Address'),
          const SizedBox(height: 14),
          _field(_phoneCtrl, 'Contact Phone', Icons.call_outlined,
              keyboardType: TextInputType.phone, locked: true),
          const SizedBox(height: 14),
          _field(_emailCtrl, 'Email Address', Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _deliveryAvailable,
            onChanged: (v) => setState(() => _deliveryAvailable = v),
            title: Text('Home delivery available',
                style: AppTextStyles.labelLarge),
            subtitle: Text(
              'Turn off if patients must collect orders in store.',
              style: AppTextStyles.caption,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Categories You Stock', style: AppTextStyles.h4),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kPharmacyCategoryCatalog.map((category) {
              final selected = _selectedCategories.contains(category);
              return FilterChip(
                label: Text(category),
                selected: selected,
                onSelected: (v) => setState(() {
                  v ? _selectedCategories.add(category) : _selectedCategories.remove(category);
                }),
                selectedColor: AppColors.primary.withValues(alpha: 0.14),
                checkmarkColor: AppColors.primary,
                labelStyle: AppTextStyles.labelMedium.copyWith(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              );
            }).toList(),
          ),
        ];
      case AppRole.ambulance:
        return [
          _field(_plateCtrl, 'Vehicle Plate Number',
              Icons.confirmation_number_outlined),
          const SizedBox(height: 14),
          _field(_vehicleTypeCtrl, 'Vehicle Type (e.g. BLS, ALS, ICU)',
              Icons.airport_shuttle_outlined),
          const SizedBox(height: 14),
          _field(_driverNameCtrl, 'Driver Full Name', Icons.person_outline),
          const SizedBox(height: 14),
          _field(_driverPhoneCtrl, 'Driver Phone', Icons.call_outlined,
              keyboardType: TextInputType.phone, locked: true),
          const SizedBox(height: 14),
          _field(_driverLicenseCtrl, 'Driving License Number',
              Icons.badge_outlined),
          const SizedBox(height: 14),
          _field(_equipmentCtrl, 'Onboard equipment (comma separated)',
              Icons.medical_services_outlined,
              maxLines: 2, required: false),
        ];
      case AppRole.caregiver:
        return [
          _field(_nameCtrl, 'Full Name', Icons.person_outline),
          const SizedBox(height: 14),
          _field(_certificationsCtrl, 'Certifications (comma separated)',
              Icons.workspace_premium_outlined,
              maxLines: 2, required: false),
          const SizedBox(height: 14),
          _field(_specialtiesCtrl, 'Specialties (comma separated)',
              Icons.volunteer_activism_outlined,
              maxLines: 2, required: false),
          const SizedBox(height: 14),
          _field(_hourlyRateCtrl, 'Hourly Rate (₹)',
              Icons.currency_rupee_rounded,
              keyboardType: TextInputType.number),
        ];
      case AppRole.physiotherapist:
        return [
          _field(_nameCtrl, 'Full Name', Icons.person_outline),
          const SizedBox(height: 14),
          _field(_certificationsCtrl, 'Certifications (comma separated)',
              Icons.workspace_premium_outlined,
              maxLines: 2, required: false),
          const SizedBox(height: 14),
          _field(_specialtiesCtrl, 'Specialties (comma separated)',
              Icons.accessibility_new_outlined,
              maxLines: 2, required: false),
          const SizedBox(height: 14),
          _field(_hourlyRateCtrl, 'Session Rate (₹)',
              Icons.currency_rupee_rounded,
              keyboardType: TextInputType.number),
        ];
      case AppRole.counsellor:
        return [
          _field(_nameCtrl, 'Full Name', Icons.person_outline),
          const SizedBox(height: 14),
          _field(_certificationsCtrl, 'Certifications (comma separated)',
              Icons.workspace_premium_outlined,
              maxLines: 2, required: false),
          const SizedBox(height: 14),
          _field(_specialtiesCtrl, 'Specialties (comma separated)',
              Icons.psychology_outlined,
              maxLines: 2, required: false),
          const SizedBox(height: 14),
          _field(_hourlyRateCtrl, 'Session Rate (₹)',
              Icons.currency_rupee_rounded,
              keyboardType: TextInputType.number),
        ];
      case AppRole.nutritionist:
      case AppRole.doctor:
      case AppRole.admin:
        return const [];
    }
  }

  /// Verification-document upload fields for this role — same canonical
  /// `docType` set the admin panel and [PartnerDocumentsSection] use
  /// elsewhere. Returns nothing for roles with no doc requirement defined
  /// (`PartnerDocumentType.forRole` returns an empty list for those).
  List<Widget> _documentFieldsForRole() {
    final types = PartnerDocumentType.forRole(_role.firestoreValue);
    if (types.isEmpty) return const [];
    return [
      const SizedBox(height: 22),
      const Text('Verification Documents', style: AppTextStyles.h4),
      const SizedBox(height: 4),
      const Text(
        'Required for our team to verify your application.',
        style: AppTextStyles.caption,
      ),
      const SizedBox(height: 10),
      for (final type in types) ...[
        _documentPickerField(type),
        const SizedBox(height: 12),
      ],
    ];
  }

  Future<void> _pickDocument(PartnerDocumentType type) async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;
    final service = PartnerDocumentService(_role.firestoreValue, uid);

    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(type.label, style: AppTextStyles.labelLarge),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: const Text('Upload a PDF'),
              onTap: () => Navigator.pop(sheetContext, 'pdf'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final file = switch (source) {
      'camera' => await service.pickImage(source: ImageSource.camera),
      'gallery' => await service.pickImage(source: ImageSource.gallery),
      _ => await service.pickPdf(),
    };
    if (file == null || !mounted) return;
    setState(() => _pickedDocs[type.key] = file);
  }

  Widget _documentPickerField(PartnerDocumentType type) {
    return FormField<File?>(
      initialValue: _pickedDocs[type.key],
      validator: (_) =>
          _pickedDocs[type.key] == null ? '${type.label} is required' : null,
      builder: (state) {
        final file = _pickedDocs[type.key];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: state.hasError ? AppColors.error : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(type.label, style: AppTextStyles.labelLarge),
                  ),
                  if (file != null)
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.success, size: 18),
                ],
              ),
              const SizedBox(height: 10),
              if (file == null)
                InkWell(
                  onTap: () async {
                    await _pickDocument(type);
                    state.didChange(_pickedDocs[type.key]);
                    state.validate();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_upload_outlined,
                            color: AppColors.primary, size: 26),
                        SizedBox(height: 6),
                        Text('Tap to upload', style: AppTextStyles.labelMedium),
                        SizedBox(height: 2),
                        Text('Photo or PDF · max 20 MB',
                            style: AppTextStyles.caption,
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        file.path.toLowerCase().endsWith('.pdf')
                            ? Icons.picture_as_pdf_rounded
                            : Icons.image_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        file.path.split(Platform.pathSeparator).last,
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _pickedDocs[type.key] = null);
                        state.didChange(null);
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
              if (state.hasError) ...[
                const SizedBox(height: 6),
                Text(
                  state.errorText!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
    bool required = true,
    bool locked = false,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      readOnly: locked,
      enabled: !locked,
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
        // A phone number typed here would be an arbitrary, unverified
        // string that could collide with another account's number — the
        // OTP-verified number on this Firebase Auth session is the only
        // one Firestore rules and the rest of this app ever treat as this
        // account's real phone, so this field mirrors it read-only rather
        // than accepting free text.
        suffixIcon: locked
            ? const Icon(Icons.verified_rounded, color: AppColors.success, size: 18)
            : null,
        helperText: locked ? 'Verified via OTP — cannot be changed' : null,
      ),
    );
  }

  /// Opens the map picker and applies the result to [_addressCtrl] plus the
  /// coordinates persisted alongside it — replaces free-text address entry
  /// so the stored address always matches a real map location rather than
  /// whatever a partner happened to type.
  Future<void> _pickAddress() async {
    final result = await Navigator.of(context).push<PreciseAddress>(
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
          initialLat: _addressLat,
          initialLng: _addressLng,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _addressCtrl.text = result.formatted;
      _addressLat = result.lat;
      _addressLng = result.lng;
    });
  }

  Widget _addressPickerField(String label) {
    return FormField<String>(
      initialValue: _addressCtrl.text,
      validator: (_) =>
          _addressCtrl.text.trim().isEmpty ? 'Select a location on the map' : null,
      builder: (state) {
        return InkWell(
          onTap: () async {
            await _pickAddress();
            state.didChange(_addressCtrl.text);
            state.validate();
          },
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.textSecondary),
              suffixIcon: const Icon(Icons.map_outlined, color: AppColors.primary),
              errorText: state.errorText,
              helperText: 'Tap to pick your exact location on the map',
            ),
            child: Text(
              _addressCtrl.text.isEmpty ? 'Select on map' : _addressCtrl.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _addressCtrl.text.isEmpty ? AppColors.textHint : AppColors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}
