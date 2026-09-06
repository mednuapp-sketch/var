import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../location/models/precise_address.dart';
import '../../location/screens/map_location_picker_screen.dart';
import '../providers/pharmacy_providers.dart';
import '../services/pharmacy_profile_service.dart';

class PharmacyProfileScreen extends ConsumerStatefulWidget {
  const PharmacyProfileScreen({super.key});

  @override
  ConsumerState<PharmacyProfileScreen> createState() => _PharmacyProfileScreenState();
}

class _PharmacyProfileScreenState extends ConsumerState<PharmacyProfileScreen> {
  bool _editing = false;
  bool _saving = false;
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  double? _addressLat;
  double? _addressLng;
  String _addressCity = '';
  final _phoneCtrl = TextEditingController();

  Future<void> _pickAddress() async {
    final result = await Navigator.of(context).push<PreciseAddress>(
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(initialLat: _addressLat, initialLng: _addressLng),
      ),
    );
    if (result == null) return;
    setState(() {
      _addressCtrl.text = result.formatted;
      _addressLat = result.lat;
      _addressLng = result.lng;
      _addressCity = result.city ?? '';
    });
  }

  Future<void> _save() async {
    final uid = PharmacyProfileService.currentUid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await PharmacyProfileService.updateProfile(uid, {
        'name': _nameCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        if (_addressLat != null) 'latitude': _addressLat,
        if (_addressLng != null) 'longitude': _addressLng,
        if (_addressCity.isNotEmpty) 'city': _addressCity,
        'phone': _phoneCtrl.text.trim(),
      });
      if (!mounted) return;
      FeedbackService.showSuccess(context, 'Profile updated');
      setState(() => _editing = false);
    } catch (e) {
      if (mounted) FeedbackService.showError(context, 'Could not save changes.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(pharmacyProfileProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.pharmacyProfile,
      title: 'Pharmacy Profile',
      extraActions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
          onPressed: () => context.push(AppRoutes.pharmacySettings),
          tooltip: 'Settings',
        ),
      ],
      body: profileAsync.when(
        loading: () => const PageLoadingState(),
        error: (_, __) => const NetworkErrorState(),
        data: (profile) {
          if (profile == null) {
            return const AppEmptyState(
              icon: Icons.storefront_outlined,
              title: 'Profile not found',
              message: 'Complete onboarding to set up your pharmacy profile.',
            );
          }
          if (!_editing) {
            _nameCtrl.text = profile.name;
            _addressCtrl.text = profile.address;
            _addressLat = profile.latitude;
            _addressLng = profile.longitude;
            _addressCity = profile.city;
            _phoneCtrl.text = profile.phone;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: SharedProfileAvatar(
                  name: profile.name,
                  photoUrl: profile.photoUrl,
                  size: 84,
                  isVerified: profile.isVerified,
                ),
              ),
              const SizedBox(height: 16),
              PremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _editableField('Pharmacy Name', _nameCtrl, Icons.storefront_rounded),
                    const Divider(height: 24, color: AppColors.divider),
                    _readOnlyField('License Number', profile.licenseNumber, Icons.badge_outlined),
                    const Divider(height: 24, color: AppColors.divider),
                    _editableField('Phone', _phoneCtrl, Icons.call_outlined, locked: true),
                    const Divider(height: 24, color: AppColors.divider),
                    _addressField(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Categories Offered', style: AppTextStyles.labelMedium),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: profile.categoriesOffered
                          .map((c) => InfoChip(icon: Icons.check_circle_outline_rounded, label: c))
                          .toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PartnerDocumentsSection(
                role: 'pharmacy',
                uid: profile.uid,
                documents: profile.documents,
                documentVerification: profile.documentVerification,
                locked: profile.status == 'active',
              ),
              const SizedBox(height: 24),
              if (_editing)
                GradientButton(label: 'Save Changes', isLoading: _saving, onTap: _save)
              else
                OutlinedButton.icon(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit Profile'),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _editableField(String label, TextEditingController ctrl, IconData icon, {bool locked = false}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: _editing
              ? TextField(
                  controller: ctrl,
                  readOnly: locked,
                  enabled: !locked,
                  decoration: InputDecoration(
                    labelText: label,
                    isDense: true,
                    suffixIcon: locked
                        ? const Icon(Icons.verified_rounded, color: AppColors.success, size: 18)
                        : null,
                    helperText: locked ? 'Verified via OTP — cannot be changed' : null,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.caption),
                    Text(ctrl.text.isEmpty ? '—' : ctrl.text, style: AppTextStyles.bodyLarge),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _addressField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.location_on_outlined, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: _editing
              ? InkWell(
                  onTap: _pickAddress,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      isDense: true,
                      suffixIcon: Icon(Icons.map_outlined, color: AppColors.primary, size: 20),
                    ),
                    child: Text(
                      _addressCtrl.text.isEmpty ? 'Select on map' : _addressCtrl.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Address', style: AppTextStyles.caption),
                    Text(_addressCtrl.text.isEmpty ? '—' : _addressCtrl.text, style: AppTextStyles.bodyLarge),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _readOnlyField(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              Text(value.isEmpty ? '—' : value, style: AppTextStyles.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}
