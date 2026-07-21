import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../models/saved_address.dart';
import '../providers/saved_addresses_provider.dart';
import 'map_location_picker_screen.dart';
import '../../home/providers/location_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Add / Edit Address Screen
// Address type segmented button (Home/Work/Other)
// Form fields with validation, "Use My Current Location" button via
// geolocator + geocoding, map picker, keyboard-aware layout.
// ─────────────────────────────────────────────────────────────────────────────

class AddEditAddressScreen extends ConsumerStatefulWidget {
  final SavedAddress? existing;

  const AddEditAddressScreen({super.key, this.existing});

  @override
  ConsumerState<AddEditAddressScreen> createState() =>
      _AddEditAddressScreenState();
}

class _AddEditAddressScreenState extends ConsumerState<AddEditAddressScreen> {
  final _formKey = GlobalKey<FormState>();

  late String _label;
  final _customLabelCtrl = TextEditingController();
  final _line1Ctrl = TextEditingController();
  final _line2Ctrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  // Legacy fields kept for model compatibility
  final _plotCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();

  double? _lat;
  double? _lng;
  bool _isDefault = false;
  bool _saving = false;
  bool _locating = false;
  String? _locationError;

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

    // Compose line1/line2 from legacy fields for display
    final parts = [
      e?.plotNo ?? '',
      e?.building ?? '',
      e?.street ?? '',
    ].where((s) => s.isNotEmpty).toList();
    _line1Ctrl.text = parts.take(2).join(', ');
    _line2Ctrl.text = [
      if ((e?.landmark ?? '').isNotEmpty) e!.landmark,
      if ((e?.area ?? '').isNotEmpty) e?.area,
    ].whereType<String>().join(', ');

    if (e == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _prefillFromCurrent());
    }
  }

  @override
  void dispose() {
    _customLabelCtrl.dispose();
    _line1Ctrl.dispose();
    _line2Ctrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    _plotCtrl.dispose();
    _buildingCtrl.dispose();
    _streetCtrl.dispose();
    _landmarkCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  void _prefillFromCurrent() {
    final loc = ref.read(locationProvider);
    final precise = loc.preciseAddress;
    if (precise == null) return;
    setState(() {
      final parts = [
        precise.plotNo ?? '',
        precise.building ?? '',
        precise.street ?? '',
      ].where((s) => s.isNotEmpty).toList();
      _line1Ctrl.text = parts.take(2).join(', ');
      _line2Ctrl.text = [
        if ((precise.area ?? '').isNotEmpty) precise.area,
      ].whereType<String>().join(', ');
      _cityCtrl.text = precise.city ?? '';
      _stateCtrl.text = precise.state ?? '';
      _pincodeCtrl.text = precise.pincode ?? '';
      _lat = precise.lat;
      _lng = precise.lng;
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });

    try {
      // Check permission
      var status = await Permission.locationWhenInUse.status;
      if (status.isDenied) {
        status = await Permission.locationWhenInUse.request();
      }
      if (status.isPermanentlyDenied) {
        setState(() {
          _locating = false;
          _locationError =
              'Location permission denied. Enable it in Settings.';
        });
        return;
      }
      if (status.isDenied) {
        setState(() {
          _locating = false;
          _locationError = 'Location permission is required.';
        });
        return;
      }

      // Check GPS
      final gpsOn = await Geolocator.isLocationServiceEnabled();
      if (!gpsOn) {
        setState(() {
          _locating = false;
          _locationError = 'Please enable GPS / Location on your device.';
        });
        return;
      }

      // Get position
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Reverse geocode
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );

      if (!mounted) return;

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final line1 = [p.subThoroughfare, p.thoroughfare]
            .where((s) => s != null && s.isNotEmpty)
            .join(' ');
        final line2 = [p.subLocality, p.locality]
            .where((s) => s != null && s.isNotEmpty)
            .take(2)
            .join(', ');

        setState(() {
          _line1Ctrl.text = line1.isNotEmpty ? line1 : _line1Ctrl.text;
          _line2Ctrl.text = line2.isNotEmpty ? line2 : _line2Ctrl.text;
          _cityCtrl.text = p.locality ?? _cityCtrl.text;
          _stateCtrl.text =
              p.administrativeArea ?? _stateCtrl.text;
          _pincodeCtrl.text = p.postalCode ?? _pincodeCtrl.text;
          _lat = pos.latitude;
          _lng = pos.longitude;
          _locating = false;
          _locationError = null;
        });
      } else {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _locating = false;
          _locationError =
              'Could not resolve address. Coordinates saved.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locationError = 'Unable to get location. Please try again.';
      });
    }
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
      final parts = [
        result.plotNo ?? '',
        result.building ?? '',
        result.street ?? '',
      ].where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) _line1Ctrl.text = parts.take(2).join(', ');
      final area = result.area ?? '';
      if (area.isNotEmpty) _line2Ctrl.text = area;
      _cityCtrl.text = result.city ?? _cityCtrl.text;
      _stateCtrl.text = result.state ?? _stateCtrl.text;
      _pincodeCtrl.text = result.pincode ?? _pincodeCtrl.text;
      _lat = result.lat;
      _lng = result.lng;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final addr = SavedAddress(
        id: widget.existing?.id ?? '',
        label: _label,
        customLabel: _customLabelCtrl.text.trim(),
        plotNo: _line1Ctrl.text.trim(),
        building: '',
        street: _line2Ctrl.text.trim(),
        landmark: '',
        area: _line2Ctrl.text.trim(),
        city: _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim(),
        pincode: _pincodeCtrl.text.trim(),
        lat: _lat ?? 0.0,
        lng: _lng ?? 0.0,
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
          const SnackBar(
            content: Text('Failed to save address. Try again.'),
            behavior: SnackBarBehavior.floating,
          ),
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
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _isEdit ? 'Edit Address' : 'Add Address',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom +
                100,
          ),
          children: [
            // ── Address Type ──────────────────────────────────────
            _SectionCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(text: 'Address Type'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _TypeChip(
                          icon: Icons.home_rounded,
                          label: 'Home',
                          selected: _label == 'home',
                          onTap: () => setState(() => _label = 'home'),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TypeChip(
                          icon: Icons.work_rounded,
                          label: 'Work',
                          selected: _label == 'work',
                          onTap: () => setState(() => _label = 'work'),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TypeChip(
                          icon: Icons.location_on_rounded,
                          label: 'Other',
                          selected: _label == 'other',
                          onTap: () => setState(() => _label = 'other'),
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  if (_label == 'other') ...[
                    const SizedBox(height: 12),
                    _FormField(
                      controller: _customLabelCtrl,
                      hint: 'Label (e.g. Parents Home)',
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Use My Location ───────────────────────────────────
            _SectionCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _locating ? null : _useCurrentLocation,
                      icon: _locating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : const Icon(Icons.my_location_rounded,
                              size: 18, color: AppColors.primary),
                      label: Text(
                        _locating
                            ? 'Getting location...'
                            : 'Use My Current Location',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: AppColors.primary, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                      ),
                    ),
                  ),
                  if (_locationError != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 14, color: Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _locationError!,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11.5,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_lat != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            size: 14, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 6),
                        Text(
                          'Location set (${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)})',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _pickOnMap,
                          child: Text(
                            'Change on map',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _pickOnMap,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.map_rounded,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Or pick on map',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Address Details ───────────────────────────────────
            _SectionCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(text: 'Address Details'),
                  const SizedBox(height: 14),

                  _FormField(
                    controller: _line1Ctrl,
                    hint: 'Address Line 1 *',
                    isDark: isDark,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Address Line 1 is required'
                            : null,
                  ),
                  const SizedBox(height: 12),

                  _FormField(
                    controller: _line2Ctrl,
                    hint: 'Address Line 2 (optional)',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _FormField(
                          controller: _cityCtrl,
                          hint: 'City *',
                          isDark: isDark,
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'City is required'
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FormField(
                          controller: _stateCtrl,
                          hint: 'State *',
                          isDark: isDark,
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'State is required'
                                  : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _FormField(
                    controller: _pincodeCtrl,
                    hint: 'Pincode *',
                    isDark: isDark,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Pincode is required';
                      }
                      if (v.trim().length != 6) {
                        return 'Enter a valid 6-digit pincode';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Default toggle ────────────────────────────────────
            _SectionCard(
              isDark: isDark,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Set as default address',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Auto-fill this address in all bookings',
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

      // ── Save button ───────────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.5),
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
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const _SectionCard({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: child,
    );
  }
}

// ── Section title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
    );
  }
}

// ── Form field ────────────────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool isDark;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _FormField({
    required this.controller,
    required this.hint,
    required this.isDark,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 13.5,
        color: isDark ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: Colors.grey.shade400,
        ),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFF8F9FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        errorStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        isDense: true,
      ),
    );
  }
}

// ── Address type chip ─────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  const _TypeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFF2F3F7),
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? null
              : Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.shade300),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? Colors.white
                  : isDark
                      ? Colors.white60
                      : Colors.grey.shade600,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : isDark
                        ? Colors.white70
                        : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
