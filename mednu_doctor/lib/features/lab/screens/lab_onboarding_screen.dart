import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/documents/partner_document_models.dart';
import '../../../shared_core/documents/partner_document_service.dart';
import '../../location/models/precise_address.dart';
import '../../location/screens/map_location_picker_screen.dart';
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
  double? _addressLat;
  double? _addressLng;
  String _addressCity = '';
  final _phoneCtrl = TextEditingController();
  final _selectedServices = <String>{};
  final Map<String, File?> _pickedDocs = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Phone is already verified by OTP at this point — pre-fill and lock
    // it so this recovery screen can't be used to attach a different,
    // unverified number to the account (mirrors PartnerRoleRegisterScreen).
    _phoneCtrl.text = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
  }

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
        latitude: _addressLat,
        longitude: _addressLng,
        city: _addressCity,
        phone: _phoneCtrl.text.trim(),
        servicesOffered: _selectedServices.toList(),
      );

      // Verification documents, uploaded now that the profile exists — must
      // run after createProfile: it merge-writes into the profile doc, but
      // createProfile's own `set()` is non-merge and would clobber an
      // earlier upload.
      final docService = PartnerDocumentService('lab', uid);
      for (final type in PartnerDocumentType.lab) {
        final file = _pickedDocs[type.key];
        if (file != null) {
          await docService.uploadDocument(docType: type.key, file: file);
        }
      }

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
                  _field(
                    _nameCtrl,
                    'Lab / Diagnostic Center Name',
                    Icons.storefront_rounded,
                    validator: (v) => Validators.name(v, label: 'Lab name'),
                  ),
                  const SizedBox(height: 14),
                  _field(_licenseCtrl, 'License / Registration Number', Icons.badge_outlined),
                  const SizedBox(height: 14),
                  _field(
                    _phoneCtrl,
                    'Contact Phone',
                    Icons.call_outlined,
                    keyboardType: TextInputType.phone,
                    validator: Validators.phone,
                    locked: true,
                  ),
                  const SizedBox(height: 14),
                  _addressPickerField('Lab Address'),
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
                  const SizedBox(height: 22),
                  const Text('Verification Documents', style: AppTextStyles.h4),
                  const SizedBox(height: 4),
                  const Text(
                    'Required for our team to verify your application.',
                    style: AppTextStyles.caption,
                  ),
                  const SizedBox(height: 10),
                  for (final type in PartnerDocumentType.lab) ...[
                    _documentPickerField(type),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 8),
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
    bool locked = false,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      readOnly: locked,
      enabled: !locked,
      validator: validator ??
          (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
        suffixIcon: locked
            ? const Icon(Icons.verified_rounded, color: AppColors.success, size: 18)
            : null,
        helperText: locked ? 'Verified via OTP — cannot be changed' : null,
      ),
    );
  }

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

  Future<void> _pickDocument(PartnerDocumentType type) async {
    final uid = LabProfileService.currentUid;
    if (uid == null) return;
    final service = PartnerDocumentService('lab', uid);

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
}
