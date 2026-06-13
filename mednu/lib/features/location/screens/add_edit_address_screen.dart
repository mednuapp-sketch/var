import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../models/saved_address.dart';
import '../providers/saved_addresses_provider.dart';
import 'map_location_picker_screen.dart';
import '../../home/providers/location_provider.dart';

class AddEditAddressScreen extends ConsumerStatefulWidget {
  final SavedAddress? existing; // null = add new

  const AddEditAddressScreen({super.key, this.existing});

  @override
  ConsumerState<AddEditAddressScreen> createState() =>
      _AddEditAddressScreenState();
}

class _AddEditAddressScreenState extends ConsumerState<AddEditAddressScreen> {
  final _formKey = GlobalKey<FormState>();

  late String _label;
  final _customLabelCtrl = TextEditingController();
  final _plotCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  double? _lat;
  double? _lng;
  bool _isDefault = false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = e?.label ?? 'home';
    _customLabelCtrl.text = e?.customLabel ?? '';
    _plotCtrl.text = e?.plotNo ?? '';
    _buildingCtrl.text = e?.building ?? '';
    _streetCtrl.text = e?.street ?? '';
    _landmarkCtrl.text = e?.landmark ?? '';
    _areaCtrl.text = e?.area ?? '';
    _cityCtrl.text = e?.city ?? '';
    _stateCtrl.text = e?.state ?? '';
    _pincodeCtrl.text = e?.pincode ?? '';
    _lat = e?.lat;
    _lng = e?.lng;
    _isDefault = e?.isDefault ?? false;

    // Pre-fill from current location if adding new
    if (e == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFromCurrent());
    }
  }

  @override
  void dispose() {
    _customLabelCtrl.dispose();
    _plotCtrl.dispose();
    _buildingCtrl.dispose();
    _streetCtrl.dispose();
    _landmarkCtrl.dispose();
    _areaCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    super.dispose();
  }

  void _prefillFromCurrent() {
    final loc = ref.read(locationProvider);
    final precise = loc.preciseAddress;
    if (precise == null) return;
    setState(() {
      _plotCtrl.text = precise.plotNo ?? '';
      _buildingCtrl.text = precise.building ?? '';
      _streetCtrl.text = precise.street ?? '';
      _areaCtrl.text = precise.area ?? '';
      _cityCtrl.text = precise.city ?? '';
      _stateCtrl.text = precise.state ?? '';
      _pincodeCtrl.text = precise.pincode ?? '';
      _lat = precise.lat;
      _lng = precise.lng;
    });
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.push<PreciseAddress>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
          initialLat: _lat,
          initialLng: _lng,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _plotCtrl.text = result.plotNo ?? _plotCtrl.text;
      _buildingCtrl.text = result.building ?? _buildingCtrl.text;
      _streetCtrl.text = result.street ?? _streetCtrl.text;
      _areaCtrl.text = result.area ?? _areaCtrl.text;
      _cityCtrl.text = result.city ?? _cityCtrl.text;
      _stateCtrl.text = result.state ?? _stateCtrl.text;
      _pincodeCtrl.text = result.pincode ?? _pincodeCtrl.text;
      _lat = result.lat;
      _lng = result.lng;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please pick location on map or enter coordinates')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final addr = SavedAddress(
        id: widget.existing?.id ?? '',
        label: _label,
        customLabel: _customLabelCtrl.text.trim(),
        plotNo: _plotCtrl.text.trim(),
        building: _buildingCtrl.text.trim(),
        street: _streetCtrl.text.trim(),
        landmark: _landmarkCtrl.text.trim(),
        area: _areaCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim(),
        pincode: _pincodeCtrl.text.trim(),
        lat: _lat!,
        lng: _lng!,
        isDefault: _isDefault,
      );
      await ref
          .read(savedAddressesNotifierProvider.notifier)
          .saveAddress(addr);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save address. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBase : const Color(0xFFF8F9FE);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEdit ? 'Edit Address' : 'Add New Address',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom + 100,
          ),
          children: [
            // ── Label selector ──────────────────────────
            _card(
              isDark,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Address Type'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _LabelChip(
                          icon: Icons.home_rounded,
                          label: 'Home',
                          value: 'home',
                          selected: _label == 'home',
                          onTap: () => setState(() => _label = 'home')),
                      const SizedBox(width: 10),
                      _LabelChip(
                          icon: Icons.work_rounded,
                          label: 'Work',
                          value: 'work',
                          selected: _label == 'work',
                          onTap: () => setState(() => _label = 'work')),
                      const SizedBox(width: 10),
                      _LabelChip(
                          icon: Icons.location_on_rounded,
                          label: 'Other',
                          value: 'other',
                          selected: _label == 'other',
                          onTap: () => setState(() => _label = 'other')),
                    ],
                  ),
                  if (_label == 'other') ...[
                    const SizedBox(height: 12),
                    _field(
                      _customLabelCtrl,
                      'Label (e.g. Parents Home)',
                      isDark,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Map pick button ─────────────────────────
            _card(
              isDark,
              InkWell(
                onTap: _pickOnMap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.map_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pick precise location on map',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _lat != null
                                  ? 'Lat: ${_lat!.toStringAsFixed(5)}, Lng: ${_lng!.toStringAsFixed(5)}'
                                  : 'Tap to open Google Maps',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Address fields ──────────────────────────
            _card(
              isDark,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Address Details'),
                  const SizedBox(height: 12),
                  _field(_plotCtrl, 'Plot / House No.', isDark),
                  const SizedBox(height: 10),
                  _field(_buildingCtrl, 'Building / Apartment Name', isDark),
                  const SizedBox(height: 10),
                  _field(_streetCtrl, 'Street / Road Name', isDark),
                  const SizedBox(height: 10),
                  _field(_landmarkCtrl, 'Landmark (optional)', isDark),
                  const SizedBox(height: 10),
                  _field(_areaCtrl, 'Area / Locality *', isDark,
                      required: true),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: _field(_cityCtrl, 'City *', isDark,
                              required: true)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 110,
                        child: _field(_pincodeCtrl, 'Pincode', isDark,
                            keyboardType: TextInputType.number),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _field(_stateCtrl, 'State', isDark),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Default toggle ──────────────────────────
            _card(
              isDark,
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Set as default address',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Auto-fill in all bookings',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _isDefault,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setState(() => _isDefault = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // ── Save button ───────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(
                      _isEdit ? 'Update Address' : 'Save Address',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(bool isDark, Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: child,
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      );

  Widget _field(
    TextEditingController ctrl,
    String hint,
    bool isDark, {
    bool required = false,
    TextInputType? keyboardType,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: Colors.grey.shade400),
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha:0.05)
              : const Color(0xFFF8F9FA),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha:0.08)
                      : Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.red)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
      );
}

// ── Label chip ─────────────────────────────────────────────
class _LabelChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _LabelChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha:0.06)
                  : const Color(0xFFF2F3F7),
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? null
              : Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
