import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../services/pharmacy_profile_service.dart';

/// One-time profile setup for an account that already holds the `pharmacy`
/// role but has no `pharmacy_profiles/{uid}` document yet — the Pharmacy
/// module's equivalent of the Lab onboarding screen. Does not create a new
/// Firebase Auth account or touch `roles`/`activeRole`.
class PharmacyOnboardingScreen extends StatefulWidget {
  const PharmacyOnboardingScreen({super.key});

  @override
  State<PharmacyOnboardingScreen> createState() => _PharmacyOnboardingScreenState();
}

class _PharmacyOnboardingScreenState extends State<PharmacyOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _deliveryAvailable = true;
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
    final uid = PharmacyProfileService.currentUid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      await PharmacyProfileService.createProfile(
        uid: uid,
        name: _nameCtrl.text.trim(),
        licenseNumber: _licenseCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        phone: Validators.normalizePhone(_phoneCtrl.text.trim()),
        deliveryAvailable: _deliveryAvailable,
      );
      if (!mounted) return;
      context.go(AppRoutes.pharmacyDashboard);
    } catch (e) {
      if (!mounted) return;
      FeedbackService.showError(context, Validators.friendlyError(e));
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
              headerIcon: Icons.local_pharmacy_rounded,
              title: 'Set Up Your Pharmacy',
              subtitle: 'A few details before you start receiving orders',
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _field(
                    _nameCtrl,
                    'Pharmacy / Store Name',
                    Icons.storefront_rounded,
                    validator: (v) => Validators.name(v, label: 'Pharmacy / Store Name'),
                  ),
                  const SizedBox(height: 14),
                  _field(_licenseCtrl, 'Drug License Number', Icons.badge_outlined),
                  const SizedBox(height: 14),
                  _field(
                    _phoneCtrl,
                    'Contact Phone',
                    Icons.call_outlined,
                    keyboardType: TextInputType.phone,
                    validator: Validators.phone,
                  ),
                  const SizedBox(height: 14),
                  _field(_addressCtrl, 'Store Address', Icons.location_on_outlined, maxLines: 2),
                  const SizedBox(height: 14),
                  PremiumCard(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Home delivery available', style: AppTextStyles.labelLarge),
                      subtitle: const Text('Turn off if pickup-only for now', style: AppTextStyles.bodySmall),
                      value: _deliveryAvailable,
                      onChanged: (v) => setState(() => _deliveryAvailable = v),
                      activeThumbColor: AppColors.primary,
                    ),
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
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator ?? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
      ),
    );
  }
}
