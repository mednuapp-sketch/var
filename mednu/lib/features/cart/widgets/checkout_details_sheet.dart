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
import '../../../core/widgets/recipient_location_sheet.dart';

class CheckoutDetails {
  final String name;
  final String phone;
  final String address;
  final String date;
  final String time;
  final String notes;

  /// The recipient's own location (lat/lng + address parts), set only when
  /// booking for a family member or "Someone else" and they picked a real
  /// address via [RecipientLocationSheet] — null for "Myself" bookings and
  /// for anyone who only typed the [address] field by hand. Distinct from
  /// [address], which today is always sourced from the orderer's own
  /// location/saved addresses.
  final Map<String, dynamic>? locationData;

  const CheckoutDetails({
    required this.name,
    required this.phone,
    required this.address,
    required this.date,
    required this.time,
    required this.notes,
    this.locationData,
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

  // ── Who is this for? ── -1 = self (default), -2 = someone else (manual
  // entry), >=0 = a saved family member. Payment always stays with the
  // logged-in user regardless of this choice — the server attributes the
  // charge to the authenticated uid independently of these name/phone
  // fields (see captureCartPayment in functions/index.js).
  String _selfName = '';
  String _selfPhone = '';
  List<Map<String, dynamic>> _familyMembers = [];
  int _bookingForIndex = -1;

  // Only used when _bookingForIndex != -1 — the recipient's own location,
  // picked via RecipientLocationSheet (search/map-pin), kept separate from
  // _addressCtrl's free text so a real lat/lng reaches the booking.
  PreciseAddress? _recipientLocation;

  // The orderer's own (self) address, structured — set whenever
  // _addressCtrl's text was populated from a real geocoded fix (GPS or
  // locationProvider's cached one), not hand-typed. Used only to
  // auto-save this address to the account's address book on confirm (see
  // _confirm) — "type it once, it's there next time," matching how
  // _recipientLocation already carries real coordinates for the
  // someone-else case. Never auto-saved if the visible text has since
  // diverged from it (_onAddressTextChanged clears both fields the same way).
  PreciseAddress? _selfPrecise;

  @override
  void initState() {
    super.initState();
    _prefill();
    _loadFamilyMembers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillAddress());
    // If the recipient address is hand-edited after being picked via
    // RecipientLocationSheet, the stored lat/lng would silently disagree
    // with the visible text — drop it so _confirm() falls back to the free
    // text alone rather than sending a stale location.
    _addressCtrl.addListener(_onAddressTextChanged);
  }

  void _onAddressTextChanged() {
    if (_recipientLocation != null && _addressCtrl.text != _recipientLocation!.formatted) {
      setState(() => _recipientLocation = null);
    }
    if (_selfPrecise != null && _addressCtrl.text != _selfPrecise!.formatted) {
      setState(() => _selfPrecise = null);
    }
  }

  Future<void> _prefill() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final raw = user.phoneNumber ?? '';
    _selfPhone = raw.startsWith('+91') ? raw.substring(3) : raw;
    _phoneCtrl.text = _selfPhone;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (snap.exists && mounted) {
        _selfName = snap.data()?['name'] ?? '';
        setState(() => _nameCtrl.text = _selfName);
      }
    } catch (_) {}
  }

  Future<void> _loadFamilyMembers() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final raw = snap.data()?['familyMembers'];
      if (!mounted || raw is! List) return;
      setState(() {
        _familyMembers = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } catch (_) {}
  }

  void _selectBookingFor(int index) {
    setState(() {
      _bookingForIndex = index;
      _recipientLocation = null;
      if (index == -1) {
        _nameCtrl.text = _selfName;
        _phoneCtrl.text = _selfPhone;
        _prefillAddress();
      } else if (index == -2) {
        _nameCtrl.clear();
        _phoneCtrl.clear();
        _addressCtrl.clear();
      } else {
        _nameCtrl.text = _familyMembers[index]['name'] as String? ?? '';
        _phoneCtrl.text = _familyMembers[index]['phone'] as String? ?? '';
        _addressCtrl.clear();
      }
    });
  }

  Future<void> _pickRecipientLocation() async {
    final label = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : 'Their';
    final picked = await RecipientLocationSheet.show(context, recipientLabel: label);
    if (picked == null || !mounted) return;
    setState(() {
      _recipientLocation = picked;
      _addressCtrl.text = picked.formatted;
    });
  }

  void _prefillAddress() {
    final locState = ref.read(locationProvider);
    if (locState.hasCoordinates) {
      final precise = locState.preciseAddress;
      _addressCtrl.text = precise?.formatted ?? locState.fullAddress;
      _selfPrecise = precise;
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
          setState(() {
            _addressCtrl.text = loc.preciseAddress?.formatted ?? loc.fullAddress;
            _selfPrecise = loc.preciseAddress;
          });
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

  // "Save address like Flipkart": name/phone already auto-reuse via _prefill,
  // but a freshly typed/geocoded address itself was never persisted for next
  // time — the only way into the address book was the separate, explicit
  // Address Book screen. Best-effort and fire-and-forget: checkout must not
  // wait on or fail because of this. Only for the "myself" case — a
  // someone-else/family-member delivery address isn't the account holder's
  // own address to save.
  void _maybeAutoSaveAddress() {
    if (_bookingForIndex != -1) return;
    final precise = _selfPrecise;
    if (precise == null || precise.formatted != _addressCtrl.text.trim()) return;

    final existing = ref.read(savedAddressesProvider).valueOrNull ?? [];
    final alreadySaved = existing.any((a) => a.formattedAddress == precise.formatted);
    if (alreadySaved) return;

    ref.read(savedAddressesNotifierProvider.notifier).saveAddress(
          SavedAddress(
            id: '',
            label: 'other',
            plotNo: precise.plotNo ?? '',
            building: precise.building ?? '',
            street: precise.street ?? '',
            area: precise.area ?? '',
            city: precise.city ?? '',
            state: precise.state ?? '',
            pincode: precise.pincode ?? '',
            lat: precise.lat,
            lng: precise.lng,
            isDefault: existing.isEmpty,
          ),
        );
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
    _maybeAutoSaveAddress();
    Navigator.pop(
      context,
      CheckoutDetails(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        date: _date,
        time: _time,
        notes: _notesCtrl.text.trim(),
        locationData: _recipientLocation?.toBookingMap(),
      ),
    );
  }

  @override
  void dispose() {
    _addressCtrl.removeListener(_onAddressTextChanged);
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
                    _label('Who is this for?'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _BookingForChip(
                          label: 'Myself',
                          selected: _bookingForIndex == -1,
                          color: widget.themeColor,
                          onTap: () => _selectBookingFor(-1),
                        ),
                        for (int i = 0; i < _familyMembers.length; i++)
                          _BookingForChip(
                            label: _familyMembers[i]['name'] as String? ?? 'Member',
                            selected: _bookingForIndex == i,
                            color: widget.themeColor,
                            onTap: () => _selectBookingFor(i),
                          ),
                        _BookingForChip(
                          label: 'Someone else',
                          selected: _bookingForIndex == -2,
                          color: widget.themeColor,
                          onTap: () => _selectBookingFor(-2),
                        ),
                      ],
                    ),
                    if (_bookingForIndex != -1) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "The payment is charged to your account — just enter their details below.",
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: Colors.grey[600]),
                          ),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 14),
                    _label(_bookingForIndex == -1 ? 'Your Name *' : 'Their Name *'),
                    _field(_nameCtrl, 'Enter patient name', validator: _req),
                    const SizedBox(height: 14),
                    _label(_bookingForIndex == -1 ? 'Your Phone Number *' : 'Their Phone Number *'),
                    _field(_phoneCtrl, 'Enter phone number',
                        keyboardType: TextInputType.phone,
                        formatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: _phoneValidator),
                    const SizedBox(height: 14),
                    if (_bookingForIndex == -1) ...[
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
                    ] else ...[
                      _label("Their Location *"),
                      GestureDetector(
                        onTap: _pickRecipientLocation,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(children: [
                            Icon(Icons.location_on_rounded, size: 18, color: widget.themeColor),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _recipientLocation?.formatted ?? "Set their address",
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: _recipientLocation != null ? FontWeight.w600 : FontWeight.w400,
                                  color: _recipientLocation != null ? Colors.black87 : Colors.grey[400],
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _field(_addressCtrl, 'Or type their address manually', maxLines: 2, validator: _req),
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

  String? _phoneValidator(String? v) {
    final digits = (v ?? '').trim();
    if (digits.isEmpty) return 'This field is required';
    if (digits.length != 10) return 'Enter a valid 10-digit number';
    return null;
  }
}

class _BookingForChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _BookingForChip({required this.label, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : Colors.grey[200]!),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF2D2D2D),
          ),
        ),
      ),
    );
  }
}
