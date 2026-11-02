import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/equipment_item.dart';
import '../models/equipment_profile.dart';
import '../services/equipment_inventory_service.dart';

/// Add / edit one menu item. A stateful widget of its own (rather than a
/// builder closure) so its text controllers are disposed by the framework at
/// the right moment instead of racing the sheet's exit animation.
enum _PhotoAction { gallery, camera, remove }

class EquipmentItemSheet extends StatefulWidget {
  final String vendorId;
  final EquipmentItem? existing;

  const EquipmentItemSheet({super.key, required this.vendorId, this.existing});

  static Future<void> show(BuildContext context, {required String vendorId, EquipmentItem? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EquipmentItemSheet(vendorId: vendorId, existing: existing),
    );
  }

  @override
  State<EquipmentItemSheet> createState() => _EquipmentItemSheetState();
}

class _EquipmentItemSheetState extends State<EquipmentItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _rentCtrl;
  late final TextEditingController _buyCtrl;
  late final TextEditingController _depositCtrl;
  late final TextEditingController _stockCtrl;

  late String _category;
  late bool _offersRent;
  late bool _offersBuy;
  late bool _isAvailable;

  // Photo: a fresh id up-front so the image has a stable storage path before
  // the document exists.
  late final String _itemId;
  String _imageUrl = '';
  File? _localImage;
  bool _uploading = false;
  double _uploadProgress = 0;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _itemId = e?.id ?? EquipmentInventoryService.newItemId(widget.vendorId);
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _rentCtrl = TextEditingController(text: e != null && e.rentPricePerDay > 0 ? '${e.rentPricePerDay}' : '');
    _buyCtrl = TextEditingController(text: e != null && e.buyPrice > 0 ? '${e.buyPrice}' : '');
    _depositCtrl = TextEditingController(text: e != null && e.deposit > 0 ? '${e.deposit}' : '');
    _stockCtrl = TextEditingController(text: e != null ? '${e.stock}' : '1');
    _category = (e != null && kEquipmentCategoryCatalog.contains(e.category)) ? e.category : '';
    _offersRent = e?.offersRent ?? true;
    _offersBuy = e?.offersBuy ?? false;
    _isAvailable = e?.isAvailable ?? true;
    _imageUrl = e?.imageUrl ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _rentCtrl.dispose();
    _buyCtrl.dispose();
    _depositCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, _PhotoAction.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, _PhotoAction.camera),
            ),
            if (_imageUrl.isNotEmpty || _localImage != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: const Text('Remove photo', style: TextStyle(color: AppColors.error)),
                onTap: () => Navigator.pop(ctx, _PhotoAction.remove),
              ),
          ],
        ),
      ),
    );

    if (action == null) return; // dismissed
    if (action == _PhotoAction.remove) {
      setState(() {
        _imageUrl = '';
        _localImage = null;
      });
      return;
    }

    File? file;
    try {
      file = action == _PhotoAction.gallery
          ? await ImageUploadService.pickFromGallery()
          : await ImageUploadService.pickFromCamera();
    } catch (e) {
      if (!mounted) return;
      FeedbackService.showError(context, 'Could not open the picker.');
      return;
    }
    if (file == null || !mounted) return;

    setState(() {
      _localImage = file;
      _uploading = true;
      _uploadProgress = 0;
    });
    try {
      final url = await ImageUploadService.uploadEquipmentItemImage(
        imageFile: file,
        uid: widget.vendorId,
        itemId: _itemId,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _imageUrl = url;
        _uploading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _localImage = null;
      });
      FeedbackService.showError(context, 'Photo upload failed. Try again.');
    }
  }

  Future<void> _save() async {
    if (_saving || _uploading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final rent = num.tryParse(_rentCtrl.text.trim()) ?? 0;
    final buy = num.tryParse(_buyCtrl.text.trim()) ?? 0;
    if (!_offersRent && !_offersBuy) {
      FeedbackService.showError(context, 'Turn on Rent, Buy, or both.');
      return;
    }

    setState(() => _saving = true);
    try {
      await EquipmentInventoryService.saveItem(
        widget.vendorId,
        _itemId,
        name: _nameCtrl.text.trim(),
        category: _category,
        description: _descCtrl.text.trim(),
        imageUrl: _imageUrl,
        offersRent: _offersRent,
        offersBuy: _offersBuy,
        rentPricePerDay: _offersRent ? rent : 0,
        buyPrice: _offersBuy ? buy : 0,
        deposit: num.tryParse(_depositCtrl.text.trim()) ?? 0,
        stock: int.tryParse(_stockCtrl.text.trim()) ?? 0,
        isAvailable: _isAvailable,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      FeedbackService.showError(context, 'Could not save. Check your connection.');
    }
  }

  String? _priceValidator(String? v, {required bool required}) {
    if (!required) return null;
    final n = num.tryParse((v ?? '').trim());
    if (n == null || n <= 0) return 'Enter a price';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(_isEdit ? 'Edit equipment' : 'Add equipment', style: AppTextStyles.h4),
                const SizedBox(height: 14),
                _photoPicker(),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Equipment name (e.g. Folding Wheelchair)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category.isEmpty ? null : _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final c in kEquipmentCategoryCatalog) DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? ''),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available to rent', style: AppTextStyles.labelMedium),
                  value: _offersRent,
                  onChanged: (v) => setState(() => _offersRent = v),
                ),
                if (_offersRent)
                  TextFormField(
                    controller: _rentCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Rent per day (₹)'),
                    validator: (v) => _priceValidator(v, required: _offersRent),
                  ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available to buy', style: AppTextStyles.labelMedium),
                  value: _offersBuy,
                  onChanged: (v) => setState(() => _offersBuy = v),
                ),
                if (_offersBuy)
                  TextFormField(
                    controller: _buyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Selling price (₹)'),
                    validator: (v) => _priceValidator(v, required: _offersBuy),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _depositCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Refundable deposit (₹)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _stockCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Units in stock'),
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          return (n == null || n < 0) ? 'Enter 0 or more' : null;
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available for booking', style: AppTextStyles.labelMedium),
                  subtitle: const Text('Turn off to show as sold out', style: AppTextStyles.caption),
                  value: _isAvailable,
                  onChanged: (v) => setState(() => _isAvailable = v),
                  activeTrackColor: AppColors.success,
                ),
                const SizedBox(height: 12),
                GradientButton(
                  label: _isEdit ? 'Save changes' : 'Add to menu',
                  isLoading: _saving,
                  onTap: (_saving || _uploading) ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoPicker() {
    Widget image;
    if (_localImage != null) {
      image = Image.file(_localImage!, fit: BoxFit.cover);
    } else if (_imageUrl.isNotEmpty) {
      image = Image.network(_imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _photoPlaceholder());
    } else {
      image = _photoPlaceholder();
    }

    return GestureDetector(
      onTap: _uploading ? null : _pickPhoto,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 140,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              if (_uploading)
                Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: CircularProgressIndicator(
                      value: _uploadProgress > 0 ? _uploadProgress : null,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 6),
                        Text('Photo', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoPlaceholder() => Container(
        color: AppColors.primarySoft,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: AppColors.primary, size: 32),
            SizedBox(height: 6),
            Text('Add a photo', style: AppTextStyles.labelMedium),
          ],
        ),
      );
}
