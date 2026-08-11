import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/lab_profile.dart';
import '../services/lab_profile_service.dart';

/// One-time profile setup for an account that already holds the `lab` role
/// but has no `lab_profiles/{uid}` document yet. This is the Lab module's
/// equivalent of the Doctor register screen — it does **not** create a new
/// Firebase Auth account or touch `roles`/`activeRole`; the account and its
/// roles already exist, this only fills in the operational profile a lab
/// booking needs (name, license, address, service catalog).
class LabOnboardingScreen extends StatefulWidget {
  const LabOnboardingScreen({super.key});

  @override
  State<LabOnboardingScreen> createState() => _LabOnboardingScreenState();
}

class _LabOnboardingScreenState extends State<LabOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _selectedServices = <String>{};
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _licenseCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedServices.isEmpty) {
      FeedbackService.showError(context, 'Select at least one service you offer.');
      return;
    }
    final uid = LabProfileService.currentUid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      await LabProfileService.createProfile(
        uid: uid,
        name: _nameCtrl.text.trim(),
        licenseNumber: _licenseCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        servicesOffered: _selectedServices.toList(),
      );
      if (!mounted) return;
      context.go(AppRoutes.labDashboard);
    } catch (e) {
      if (!mounted) return;
      FeedbackService.showError(context, 'Could not save your lab profile. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            const GradientSliverAppBar(
              headerIcon: Icons.biotech_rounded,
              title: 'Set Up Your Lab',
              subtitle: 'A few details before you start receiving bookings',
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _field(_nameCtrl, 'Lab / Diagnostic Center Name', Icons.storefront_rounded),
                  const SizedBox(height: 14),
                  _field(_licenseCtrl, 'License / Registration Number', Icons.badge_outlined),
                  const SizedBox(height: 14),
                  _field(_phoneCtrl, 'Contact Phone', Icons.call_outlined,
                      keyboardType: TextInputType.phone),
                  const SizedBox(height: 14),
                  _field(_addressCtrl, 'Lab Address', Icons.location_on_outlined, maxLines: 2),
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
                  const SizedBox(height: 30),
                  GradientButton(
                    label: 'Save & Continue',
                    isLoading: _saving,
                    onTap: _saving ? null : _submit,
                  ),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text(
                      'Verification typically takes 1-2 business days.',
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

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
      ),
    );
  }
}
