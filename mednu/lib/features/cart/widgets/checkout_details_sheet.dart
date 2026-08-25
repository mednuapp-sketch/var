import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../home/providers/location_provider.dart';
import '../../location/providers/saved_addresses_provider.dart';
import '../../location/models/saved_address.dart';

class CheckoutDetails {
  final String name;
  final String phone;
  final String address;
  final String date;
  final String time;
  final String notes;

  const CheckoutDetails({
    required this.name,
    required this.phone,
    required this.address,
    required this.date,
    required this.time,
    required this.notes,
  });
}

/// One shared name/phone/address/date/time/notes form collected once for the
/// whole cart at checkout, instead of per item.
class CheckoutDetailsSheet extends ConsumerStatefulWidget {
  final Color themeColor;
  const CheckoutDetailsSheet({super.key, this.themeColor = AppColors.primary});

  static Future<CheckoutDetails?> show(BuildContext context, {Color themeColor = AppColors.primary}) {
    return showModalBottomSheet<CheckoutDetails>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProviderScope(
        child: CheckoutDetailsSheet(themeColor: themeColor),
      ),
    );
  }

  @override
  ConsumerState<CheckoutDetailsSheet> createState() => _CheckoutDetailsSheetState();
}

class _CheckoutDetailsSheetState extends ConsumerState<CheckoutDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _date = '';
  String _time = '';
  bool _dateError = false;
  bool _timeError = false;
  bool _gpsRefreshing = false;

  @override
  void initState() {
    super.initState();
    _prefill();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillAddress());
  }

  Future<void> _prefill() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final raw = user.phoneNumber ?? '';
    _phoneCtrl.text = raw.startsWith('+91') ? raw.substring(3) : raw;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (snap.exists && mounted) {
        setState(() => _nameCtrl.text = snap.data()?['name'] ?? '');
      }
    } catch (_) {}
  }

  void _prefillAddress() {
    final locState = ref.read(locationProvider);
    if (locState.hasCoordinates) {
      final precise = locState.preciseAddress;
      _addressCtrl.text = precise?.formatted ?? locState.fullAddress;
    }
  }

  Future<void> _refreshGps() async {
    if (_gpsRefreshing) return;
    setState(() => _gpsRefreshing = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        return;
      }
      await ref.read(locationProvider.notifier).fetchCurrent();
      if (mounted) {
        final loc = ref.read(locationProvider);
        if (loc.hasCoordinates) {
          setState(() => _addressCtrl.text = loc.preciseAddress?.formatted ?? loc.fullAddress);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _gpsRefreshing = false);
    }
  }

  void _pickSavedAddress(SavedAddress addr) {
    setState(() => _addressCtrl.text = addr.formattedAddress);
    Navigator.pop(context);
  }

  void _showSavedAddresses() {
    final saved = ref.read(savedAddressesProvider).valueOrNull ?? [];
    if (saved.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: saved
            .map((a) => ListTile(
                  leading: const Icon(Icons.location_on_rounded, color: AppColors.primary),
                  title: Text(a.displayLabel, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                  subtitle: Text(a.formattedAddress, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  onTap: () => _pickSavedAddress(a),
                ))
            .toList(),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = '${picked.day}/${picked.month}/${picked.year}';
        _dateError = false;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 0));
    if (picked != null && mounted) {
      setState(() {
        _time = picked.format(context);
        _timeError = false;
      });
    }
  }

  void _confirm() {
    final formValid = _formKey.currentState!.validate();
    final dateValid = _date.isNotEmpty;
    final timeValid = _time.isNotEmpty;
    setState(() {
      _dateError = !dateValid;
      _timeError = !timeValid;
    });
    if (!formValid || !dateValid || !timeValid) return;
    Navigator.pop(
      context,
      CheckoutDetails(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        date: _date,
        time: _time,
        notes: _notesCtrl.text.trim(),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(children: [
                const Expanded(child: Text('Checkout Details', style: AppTextStyles.h4)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Divider(height: 20),
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                padding: EdgeInsets.only(left: 20, right: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
                child: Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _label('Patient Name *'),
                    _field(_nameCtrl, 'Enter patient name', validator: _req),
                    const SizedBox(height: 14),
                    _label('Phone Number *'),
                    _field(_phoneCtrl, 'Enter phone number',
                        keyboardType: TextInputType.phone,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: _req),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: _label('Delivery / Service Address *')),
                      if (!_gpsRefreshing)
                        GestureDetector(
                          onTap: _refreshGps,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.gps_fixed_rounded, size: 13, color: widget.themeColor),
                            const SizedBox(width: 3),
                            Text('Use GPS',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: widget.themeColor)),
                          ]),
                        )
                      else
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: widget.themeColor)),
                    ]),
                    const SizedBox(height: 6),
                    _field(_addressCtrl, 'Enter full address', maxLines: 2, validator: _req),
                    if ((ref.watch(savedAddressesProvider).valueOrNull ?? []).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _showSavedAddresses,
                        child: Text('Choose from saved addresses',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: widget.themeColor)),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _label('Preferred Date & Time *'),
                    Row(children: [
                      Expanded(child: _datePicker()),
                      const SizedBox(width: 10),
                      Expanded(child: _timePicker()),
                    ]),
                    const SizedBox(height: 14),
                    _label('Additional Notes (Optional)'),
                    _field(_notesCtrl, 'Special instructions...', maxLines: 3),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.themeColor,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: const Text('Continue to Payment',
                            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF2D2D2D))),
      );

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        validator: validator,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.grey[400]),
          filled: true,
          fillColor: const Color(0xFFF8F9FA),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
          focusedBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: widget.themeColor, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
      );

  Widget _datePicker() => GestureDetector(
        onTap: _pickDate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: _dateError ? const Color(0xFFFFEBEE) : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _dateError ? Colors.red : Colors.grey[200]!, width: _dateError ? 1.5 : 1),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today_rounded, size: 16, color: _dateError ? Colors.red : widget.themeColor),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_date.isEmpty ? 'Select Date' : _date,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: _date.isEmpty ? Colors.grey[400] : Colors.black87),
                    overflow: TextOverflow.ellipsis)),
          ]),
        ),
      );

  Widget _timePicker() => GestureDetector(
        onTap: _pickTime,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: _timeError ? const Color(0xFFFFEBEE) : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _timeError ? Colors.red : Colors.grey[200]!, width: _timeError ? 1.5 : 1),
          ),
          child: Row(children: [
            Icon(Icons.access_time_rounded, size: 16, color: _timeError ? Colors.red : widget.themeColor),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_time.isEmpty ? 'Select Time' : _time,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: _time.isEmpty ? Colors.grey[400] : Colors.black87),
                    overflow: TextOverflow.ellipsis)),
          ]),
        ),
      );

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'This field is required' : null;
}
