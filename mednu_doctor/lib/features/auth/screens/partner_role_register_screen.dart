import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/models/app_role.dart';
import '../../ambulance/services/ambulance_profile_service.dart';
import '../../caregiver/services/caregiver_profile_service.dart';
import '../../lab/services/lab_profile_service.dart';
import '../../pharmacy/services/pharmacy_profile_service.dart';
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
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _deliveryAvailable = true;

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

    final uid = DoctorAuthService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'Session expired. Please login again.');
      context.go(AppRoutes.login);
      return;
    }

    setState(() => _saving = true);
    try {
      // 1 ── Base identity document, shared by every role.
      await FirebaseFirestore.instance.collection('doctors').doc(uid).set({
        'uid': uid,
        'name': _accountName,
        'phone': _accountPhone.isNotEmpty
            ? _accountPhone
            : FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
        'status': 'pending',
        'roles': [_role.firestoreValue],
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2 ── Role-specific operational profile.
      await _createRoleProfile(uid);

      if (!mounted) return;
      context.go(AppRoutes.verificationPending);
    } catch (e) {
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
          phone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
        );
      case AppRole.pharmacy:
        return PharmacyProfileService.createProfile(
          uid: uid,
          name: _nameCtrl.text.trim(),
          licenseNumber: _licenseCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          deliveryAvailable: _deliveryAvailable,
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
      case AppRole.doctor:
      case AppRole.admin:
        // Unreachable: the role-select screen never routes these here, and
        // the router falls back to Doctor registration for them.
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
              onBack: () => context.go(AppRoutes.partnerRoleSelect),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  ..._fieldsForRole(),
                  const SizedBox(height: 30),
                  GradientButton(
                    label: 'Submit for Approval',
                    icon: Icons.send_rounded,
                    isLoading: _saving,
                    onTap: _saving ? null : _submit,
                  ),
                  const SizedBox(height: 10),
                  const Center(
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
          _field(_addressCtrl, 'Lab Address', Icons.location_on_outlined,
              maxLines: 2),
          const SizedBox(height: 14),
          _field(_phoneCtrl, 'Contact Phone', Icons.call_outlined,
              keyboardType: TextInputType.phone),
          const SizedBox(height: 14),
          _field(_emailCtrl, 'Email Address', Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress),
        ];
      case AppRole.pharmacy:
        return [
          _field(_nameCtrl, 'Pharmacy Name', Icons.storefront_rounded),
          const SizedBox(height: 14),
          _field(_licenseCtrl, 'Drug License Number', Icons.badge_outlined),
          const SizedBox(height: 14),
          _field(_addressCtrl, 'Pharmacy Address', Icons.location_on_outlined,
              maxLines: 2),
          const SizedBox(height: 14),
          _field(_phoneCtrl, 'Contact Phone', Icons.call_outlined,
              keyboardType: TextInputType.phone),
          const SizedBox(height: 14),
          _field(_emailCtrl, 'Email Address', Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _deliveryAvailable,
            onChanged: (v) => setState(() => _deliveryAvailable = v),
            title: const Text('Home delivery available',
                style: AppTextStyles.labelLarge),
            subtitle: const Text(
              'Turn off if patients must collect orders in store.',
              style: AppTextStyles.caption,
            ),
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
              keyboardType: TextInputType.phone),
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
      case AppRole.doctor:
      case AppRole.admin:
        return const [];
    }
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
    bool required = true,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
      ),
    );
  }
}
