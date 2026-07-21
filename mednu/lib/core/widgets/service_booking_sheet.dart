import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../services/booking_service.dart';
import '../services/feedback_service.dart';
import '../services/places_service.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../router/app_router.dart';
import '../../features/home/providers/location_provider.dart';
import '../../features/location/providers/saved_addresses_provider.dart';
import '../../features/location/models/saved_address.dart';
import '../../features/location/screens/map_location_picker_screen.dart';
import 'rating_feedback_sheet.dart';

class ServiceBookingSheet extends ConsumerStatefulWidget {
  final String type;
  final String serviceName;
  final Color themeColor;
  final Map<String, dynamic> serviceDetails;
  final String? priceLabel;
  final int amount;
  final String paymentDescription;

  const ServiceBookingSheet({
    super.key,
    required this.type,
    required this.serviceName,
    required this.themeColor,
    this.serviceDetails = const {},
    this.priceLabel,
    this.amount = 0,
    this.paymentDescription = '',
  });

  static Future<void> show(
    BuildContext context, {
    required String type,
    required String serviceName,
    required Color themeColor,
    Map<String, dynamic> serviceDetails = const {},
    String? priceLabel,
    int amount = 0,
    String paymentDescription = '',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProviderScope(
        parent: ProviderScope.containerOf(ctx),
        child: ServiceBookingSheet(
          type: type,
          serviceName: serviceName,
          themeColor: themeColor,
          serviceDetails: serviceDetails,
          priceLabel: priceLabel,
          amount: amount,
          paymentDescription: paymentDescription,
        ),
      ),
    );
  }

  @override
  ConsumerState<ServiceBookingSheet> createState() =>
      _ServiceBookingSheetState();
}

class _ServiceBookingSheetState extends ConsumerState<ServiceBookingSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _manualAddrCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Types that count as therapy sessions — exempt from the adult-accompaniment
  // warning shown for minors on every other consultation/service booking.
  static const _therapyTypes = {'physiotherapy', 'counselling'};

  List<Map<String, dynamic>> _familyMembers = [];
  int _bookingForIndex = -1; // -1 = self
  String _selfName = '';

  bool get _isTherapy => _therapyTypes.contains(widget.type);

  bool get _showsMinorWarning {
    if (_bookingForIndex < 0 || _bookingForIndex >= _familyMembers.length) {
      return false;
    }
    final age = _familyMembers[_bookingForIndex]['age'];
    return age is int && age > 0 && age < 18 && !_isTherapy;
  }

  String _date = '';
  String _time = '';
  bool _busy = false;
  bool _done = false;
  bool _gpsRefreshing = false;
  bool _dateError = false;
  bool _timeError = false;

  // Selected address info
  String _selectedAddr = '';
  double? _selectedLat;
  double? _selectedLng;
  Map<String, dynamic> _selectedAddrMap = {};
  bool _useManualEntry = false;

  // Address autocomplete state
  List<PlacesSuggestion> _addrSuggestions = [];
  bool _addrSearching = false;
  Timer? _addrDebounce;
  bool _addrConfirmed = false;

  bool get _hasGpsCoordinates =>
      _selectedLat != null && _selectedLng != null;

  @override
  void initState() {
    super.initState();
    _prefill();
    _manualAddrCtrl.addListener(_onAddrChanged);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _prefillAddress());
  }

  void _onAddrChanged() {
    final q = _manualAddrCtrl.text.trim();
    _addrDebounce?.cancel();
    if (_addrConfirmed) {
      setState(() {
        _addrConfirmed = false;
        _selectedLat = null;
        _selectedLng = null;
      });
    }
    if (q.length < 2) {
      setState(() {
        _addrSuggestions = [];
        _addrSearching = false;
      });
      return;
    }
    setState(() => _addrSearching = true);
    _addrDebounce =
        Timer(const Duration(milliseconds: 350), () => _runAddrSearch(q));
  }

  Future<void> _runAddrSearch(String q) async {
    if (!mounted) return;
    final suggestions = await placesService.autocomplete(q);
    if (!mounted) return;
    setState(() {
      _addrSuggestions = suggestions;
      _addrSearching = false;
    });
  }

  Future<void> _pickAddrSuggestion(PlacesSuggestion s) async {
    setState(() {
      _addrSearching = true;
      _addrSuggestions = [];
    });
    final details = await placesService.details(s.placeId);
    if (!mounted) return;
    if (details != null) {
      _manualAddrCtrl.removeListener(_onAddrChanged);
      _manualAddrCtrl.text = details.formattedAddress;
      _manualAddrCtrl.addListener(_onAddrChanged);
      setState(() {
        _selectedLat = details.lat;
        _selectedLng = details.lng;
        _selectedAddrMap = {
          'formattedAddress': details.formattedAddress,
          'lat': details.lat,
          'lng': details.lng,
          if (details.street != null) 'street': details.street!,
          if (details.area != null) 'area': details.area!,
          if (details.city != null) 'city': details.city!,
          if (details.state != null) 'state': details.state!,
          if (details.pincode != null) 'pincode': details.pincode!,
        };
        _addrConfirmed = true;
        _addrSearching = false;
      });
    } else {
      _manualAddrCtrl.removeListener(_onAddrChanged);
      _manualAddrCtrl.text = s.fullText;
      _manualAddrCtrl.addListener(_onAddrChanged);
      setState(() {
        _addrConfirmed = true;
        _addrSearching = false;
      });
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
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        if (mounted) {
          setState(() => _gpsRefreshing = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
              'Location permission denied. Enable in Settings.',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: AppColors.error,
            action: SnackBarAction(
              label: 'Settings',
              textColor: Colors.white,
              onPressed: () => Geolocator.openAppSettings(),
            ),
          ));
        }
        return;
      }
      await ref.read(locationProvider.notifier).fetchCurrent();
      if (mounted) {
        final loc = ref.read(locationProvider);
        if (loc.hasCoordinates) {
          final precise = loc.preciseAddress;
          setState(() {
            _selectedAddr = precise?.formatted ?? loc.fullAddress;
            _selectedLat = loc.lat;
            _selectedLng = loc.lng;
            _selectedAddrMap = precise?.toBookingMap() ??
                {
                  'formattedAddress': loc.fullAddress,
                  'lat': loc.lat,
                  'lng': loc.lng,
                };
            _useManualEntry = false;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _gpsRefreshing = false);
    }
  }

  Future<void> _prefill() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final raw = user.phoneNumber ?? '';
    _phoneCtrl.text = raw.startsWith('+91') ? raw.substring(3) : raw;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (snap.exists && mounted) {
        final data = snap.data();
        final rawMembers = data?['familyMembers'];
        setState(() {
          _selfName = data?['name'] ?? '';
          _nameCtrl.text = _selfName;
          _familyMembers = rawMembers is List
              ? rawMembers.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
              : <Map<String, dynamic>>[];
        });
      }
    } catch (_) {}
  }

  void _selectBookingFor(int index) {
    setState(() {
      _bookingForIndex = index;
      _nameCtrl.text = index < 0 ? _selfName : (_familyMembers[index]['name'] as String? ?? '');
    });
  }

  void _prefillAddress() {
    final locState = ref.read(locationProvider);
    if (locState.hasCoordinates) {
      final precise = locState.preciseAddress;
      setState(() {
        _selectedAddr =
            precise?.formatted ?? locState.fullAddress;
        _selectedLat = locState.lat;
        _selectedLng = locState.lng;
        _selectedAddrMap = precise?.toBookingMap() ??
            {
              'formattedAddress': locState.fullAddress,
              'lat': locState.lat,
              'lng': locState.lng,
            };
      });
    }
  }

  void _pickSaved(SavedAddress addr) {
    setState(() {
      _selectedAddr = addr.formattedAddress;
      _selectedLat = addr.lat;
      _selectedLng = addr.lng;
      _selectedAddrMap = {
        'plotNo': addr.plotNo,
        'building': addr.building,
        'street': addr.street,
        'landmark': addr.landmark,
        'area': addr.area,
        'city': addr.city,
        'state': addr.state,
        'pincode': addr.pincode,
        'lat': addr.lat,
        'lng': addr.lng,
        'formattedAddress': addr.formattedAddress,
      };
      _useManualEntry = false;
    });
    Navigator.pop(context); // close address bottom sheet
  }

  void _useCurrentLocation() {
    final locState = ref.read(locationProvider);
    if (!locState.hasCoordinates) return;
    final precise = locState.preciseAddress;
    setState(() {
      _selectedAddr = precise?.formatted ?? locState.fullAddress;
      _selectedLat = locState.lat;
      _selectedLng = locState.lng;
      _selectedAddrMap = precise?.toBookingMap() ??
          {
            'formattedAddress': locState.fullAddress,
            'lat': locState.lat,
            'lng': locState.lng,
          };
      _useManualEntry = false;
    });
    Navigator.pop(context);
  }

  Future<void> _openMapPicker() async {
    Navigator.pop(context); // close address sheet first
    final locState = ref.read(locationProvider);
    final picked = await Navigator.push<PreciseAddress>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
          initialLat: locState.lat,
          initialLng: locState.lng,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedAddr = picked.formatted;
      _selectedLat = picked.lat;
      _selectedLng = picked.lng;
      _selectedAddrMap = picked.toBookingMap();
      _useManualEntry = false;
    });
  }

  void _showAddressPicker() {
    final locState = ref.read(locationProvider);
    final savedAsync = ref.read(savedAddressesProvider);
    final saved = savedAsync.valueOrNull ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCardElevated : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha:0.15)
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  const Text(
                    'Select Address',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _useManualEntry = true);
                    },
                    child: const Text(
                      'Type manually',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // Current location
                  if (locState.hasCoordinates)
                    _addrOption(
                      context: context,
                      icon: Icons.my_location_rounded,
                      iconBg: AppColors.primary,
                      title: 'Current Location',
                      subtitle: locState.preciseAddress?.formatted ??
                          locState.fullAddress,
                      onTap: _useCurrentLocation,
                      isDark: isDark,
                    ),

                  // Saved addresses
                  ...saved.map((addr) => _addrOption(
                        context: context,
                        icon: addr.label == 'home'
                            ? Icons.home_rounded
                            : addr.label == 'work'
                                ? Icons.work_rounded
                                : Icons.location_on_rounded,
                        iconBg: addr.label == 'home'
                            ? const Color(0xFF43A047)
                            : addr.label == 'work'
                                ? const Color(0xFF1E88E5)
                                : AppColors.primary,
                        title: addr.displayLabel,
                        subtitle: addr.formattedAddress,
                        onTap: () => _pickSaved(addr),
                        isDark: isDark,
                        isDefault: addr.isDefault,
                      )),

                  // Pick on map
                  _addrOption(
                    context: context,
                    icon: Icons.map_rounded,
                    iconBg: const Color(0xFF1565C0),
                    title: 'Pick on Map',
                    subtitle: 'Drag pin to exact location',
                    onTap: _openMapPicker,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addrOption({
    required BuildContext context,
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
    bool isDefault = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconBg, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha:0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'DEFAULT',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey.shade400, size: 18),
          ],
        ),
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
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: widget.themeColor),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = '${picked.day}/${picked.month}/${picked.year}';
        _dateError = false;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: widget.themeColor),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _time = picked.format(context);
        _timeError = false;
      });
    }
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState!.validate();
    final dateValid = _date.isNotEmpty;
    final timeValid = _time.isNotEmpty;
    setState(() {
      _dateError = !dateValid;
      _timeError = !timeValid;
    });
    if (!formValid || !dateValid || !timeValid) return;

    final finalAddr = _useManualEntry
        ? _manualAddrCtrl.text.trim()
        : _selectedAddr;
    if (finalAddr.isEmpty) {
      FeedbackService.showWarning(context, 'Please select or enter your address');
      return;
    }

    // ── Payment gate ──────────────────────────────────────
    if (widget.amount > 0) {
      final desc = widget.paymentDescription.isNotEmpty
          ? widget.paymentDescription
          : 'Booking: ${widget.serviceName}';
      final paid = await context.push<bool>(
        AppRoutes.payment,
        extra: {'amount': widget.amount.toString(), 'description': desc},
      );
      if (!mounted) return;
      if (paid != true) return;
    }
    // ─────────────────────────────────────────────────────

    setState(() => _busy = true);
    FeedbackService.showLoading(context, 'Booking ${widget.serviceName}...');

    try {
      final locationData = (_useManualEntry && _addrConfirmed && _selectedAddrMap.isNotEmpty)
          ? _selectedAddrMap
          : _useManualEntry
              ? {'formattedAddress': finalAddr}
              : _selectedAddrMap.isNotEmpty
                  ? _selectedAddrMap
                  : {'formattedAddress': finalAddr};

      await BookingService.createRequest(
        type: widget.type,
        serviceName: widget.serviceName,
        patientName: _nameCtrl.text.trim(),
        patientPhone: _phoneCtrl.text.trim(),
        address: finalAddr,
        preferredDate: _date,
        preferredTime: _time,
        notes: _notesCtrl.text.trim(),
        serviceDetails: {
          ...widget.serviceDetails,
          'locationData': locationData,
        },
      );

      if (mounted) {
        FeedbackService.dismiss(context);
        setState(() { _busy = false; _done = true; });
        // Show one-time app rating prompt after a short delay so the
        // success screen is visible first. Skipped if already submitted.
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) {
            maybeShowRatingSheet(context, themeColor: widget.themeColor);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        FeedbackService.showError(
          context,
          'Booking failed. Check your connection and try again.',
          onRetry: _submit,
        );
      }
    }
  }

  @override
  void dispose() {
    _addrDebounce?.cancel();
    _manualAddrCtrl.removeListener(_onAddrChanged);
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _manualAddrCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _done ? _buildSuccess() : _buildForm(ctrl),
      ),
    );
  }

  // ── Success state ─────────────────────────────────────
  Widget _buildSuccess() => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: widget.themeColor.withValues(alpha:0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded,
                  color: widget.themeColor, size: 48),
            ),
            const SizedBox(height: 20),
            Text('Booking Confirmed!', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            Text(
              'Your request for ${widget.serviceName} has been received.\nOur team will contact you shortly.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(children: [
                _detailRow(Icons.medical_services_rounded, 'Service',
                    widget.serviceName),
                _detailRow(
                    Icons.calendar_today_rounded, 'Date', _date),
                _detailRow(
                    Icons.access_time_rounded, 'Time', _time),
                _detailRow(Icons.location_on_rounded, 'Address',
                    _useManualEntry
                        ? _manualAddrCtrl.text.trim()
                        : _selectedAddr),
                _detailRow(
                    Icons.info_rounded, 'Status', 'Pending Review'),
              ]),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.themeColor,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Done',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      );

  Widget _detailRow(IconData icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(icon, size: 16, color: widget.themeColor),
          const SizedBox(width: 10),
          Text('$label: ',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12),
                  overflow: TextOverflow.ellipsis)),
        ]),
      );

  // ── Form ──────────────────────────────────────────────
  Widget _buildForm(ScrollController ctrl) => Column(
        children: [
          Center(
              child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: widget.themeColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.calendar_today_rounded,
                    color: widget.themeColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Book ${widget.serviceName}',
                        style: AppTextStyles.h4,
                        overflow: TextOverflow.ellipsis),
                    if (widget.priceLabel != null)
                      Text(widget.priceLabel!,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: widget.themeColor)),
                  ])),
              IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 20),
          Expanded(
            child: SingleChildScrollView(
              controller: ctrl,
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 4,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  if (_familyMembers.isNotEmpty) ...[
                    _label('Booking For'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _bookingForChip(label: 'Self', selected: _bookingForIndex < 0, onTap: () => _selectBookingFor(-1)),
                        for (int i = 0; i < _familyMembers.length; i++)
                          _bookingForChip(
                            label: _familyMembers[i]['name'] as String? ?? 'Member',
                            selected: _bookingForIndex == i,
                            onTap: () => _selectBookingFor(i),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_showsMinorWarning) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        Icon(Icons.escalator_warning_rounded, size: 18, color: Colors.amber.shade800),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This patient is under 18. An adult must accompany them for this consultation.',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.amber.shade900),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _label('Patient Name *'),
                  _field(_nameCtrl, 'Enter patient name',
                      validator: _req),
                  const SizedBox(height: 14),
                  _label('Phone Number *'),
                  _field(_phoneCtrl, 'Enter phone number',
                      keyboardType: TextInputType.phone,
                      formatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      validator: _req),
                  const SizedBox(height: 14),

                  // ── Smart address selector ────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                          child: _label('Service Address *')),
                      if (!_useManualEntry && !_gpsRefreshing)
                        GestureDetector(
                          onTap: _refreshGps,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.gps_fixed_rounded,
                                  size: 13,
                                  color: widget.themeColor),
                              const SizedBox(width: 3),
                              Text(
                                'Refresh GPS',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: widget.themeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_gpsRefreshing)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.themeColor,
                          ),
                        ),
                    ],
                  ),
                  _useManualEntry
                      ? _buildAddrAutocomplete()
                      : Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            _AddressSelectorCard(
                              selectedAddress: _selectedAddr,
                              themeColor: widget.themeColor,
                              onTap: _showAddressPicker,
                            ),
                            // GPS coordinates chip
                            if (_hasGpsCoordinates) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                        color: Color(0xFF2E7D32),
                                        shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'GPS: ${_selectedLat!.toStringAsFixed(5)}, '
                                      '${_selectedLng!.toStringAsFixed(5)}',
                                      style: AppTextStyles.caption
                                          .copyWith(
                                              color: AppColors
                                                  .textHint),
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(
                                      Icons.verified_rounded,
                                      size: 12,
                                      color: Color(0xFF2E7D32)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Verified',
                                    style:
                                        AppTextStyles.caption
                                            .copyWith(
                                                color: const Color(
                                                    0xFF2E7D32)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                  const SizedBox(height: 14),

                  _label('Preferred Date & Time *'),
                  Row(children: [
                    Expanded(child: _datePicker()),
                    const SizedBox(width: 10),
                    Expanded(child: _timePicker()),
                  ]),
                  if (_dateError || _timeError) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: _dateError
                            ? const Text(
                                'Select a date',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  color: Colors.red,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _timeError
                            ? const Text(
                                'Select a time',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  color: Colors.red,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 14),
                  _label('Additional Notes (Optional)'),
                  _field(_notesCtrl,
                      'Special instructions, medical conditions...',
                      maxLines: 3),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.themeColor,
                        minimumSize:
                            const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(14)),
                        elevation: 0,
                        disabledBackgroundColor:
                            widget.themeColor.withValues(alpha:0.6),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5))
                          : const Text('Confirm Booking',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'You will receive a confirmation call/SMS shortly',
                      style: AppTextStyles.caption,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
      );

  Widget _bookingForChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? widget.themeColor : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? widget.themeColor : Colors.grey[300]!,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF2D2D2D))),
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
          hintStyle: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Colors.grey[400]),
          filled: true,
          fillColor: const Color(0xFFF8F9FA),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[200]!)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: widget.themeColor, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Colors.red)),
          focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Colors.red)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 13),
        ),
      );

  Widget _buildAddrAutocomplete() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _manualAddrCtrl,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search address…',
            hintStyle: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Colors.grey[400]),
            filled: true,
            fillColor: const Color(0xFFF8F9FA),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: widget.themeColor, width: 1.5)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red)),
            focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 13),
            prefixIcon: const Icon(Icons.search_rounded,
                color: Colors.grey, size: 18),
            suffixIcon: _manualAddrCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: Colors.grey),
                    onPressed: () {
                      _manualAddrCtrl.removeListener(_onAddrChanged);
                      _manualAddrCtrl.clear();
                      _manualAddrCtrl.addListener(_onAddrChanged);
                      setState(() {
                        _addrSuggestions = [];
                        _addrConfirmed = false;
                        _addrSearching = false;
                      });
                    },
                  )
                : null,
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Please search and select an address';
            }
            if (!_addrConfirmed) {
              return 'Please select an address from the list below';
            }
            return null;
          },
        ),
        if (_addrSearching)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: widget.themeColor,
              backgroundColor: widget.themeColor.withValues(alpha: 0.1),
            ),
          ),
        if (!_addrConfirmed && _addrSuggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  for (int i = 0; i < _addrSuggestions.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: Colors.grey[100]),
                    _AddrSuggestionTile(
                      suggestion: _addrSuggestions[i],
                      isFirst: i == 0,
                      isLast: i == _addrSuggestions.length - 1,
                      onTap: () => _pickAddrSuggestion(_addrSuggestions[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_addrConfirmed)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF81C784).withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 14, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedLat != null
                          ? 'Address confirmed with GPS coordinates'
                          : 'Address selected',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (!_addrSearching &&
            _addrSuggestions.isEmpty &&
            _manualAddrCtrl.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color:
                        const Color(0xFFFFB300).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outlined,
                      size: 14, color: Color(0xFFE65100)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No matches found. Try a different search term.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => setState(() => _useManualEntry = false),
            child: Text(
              'Use saved / GPS location',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: widget.themeColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _datePicker() => GestureDetector(
        onTap: _pickDate,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: _dateError
                ? const Color(0xFFFFEBEE)
                : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _dateError ? Colors.red : Colors.grey[200]!,
              width: _dateError ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today_rounded,
                size: 16,
                color: _dateError ? Colors.red : widget.themeColor),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
              _date.isEmpty ? 'Select Date' : _date,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: _date.isEmpty
                      ? (_dateError ? Colors.red[300] : Colors.grey[400])
                      : Colors.black87),
              overflow: TextOverflow.ellipsis,
            )),
          ]),
        ),
      );

  Widget _timePicker() => GestureDetector(
        onTap: _pickTime,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: _timeError
                ? const Color(0xFFFFEBEE)
                : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _timeError ? Colors.red : Colors.grey[200]!,
              width: _timeError ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Icon(Icons.access_time_rounded,
                size: 16,
                color: _timeError ? Colors.red : widget.themeColor),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
              _time.isEmpty ? 'Select Time' : _time,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: _time.isEmpty
                      ? (_timeError ? Colors.red[300] : Colors.grey[400])
                      : Colors.black87),
              overflow: TextOverflow.ellipsis,
            )),
          ]),
        ),
      );

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;
}

// ── Smart address selector card ───────────────────────────
class _AddressSelectorCard extends StatelessWidget {
  final String selectedAddress;
  final Color themeColor;
  final VoidCallback onTap;

  const _AddressSelectorCard({
    required this.selectedAddress,
    required this.themeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasAddr = selectedAddress.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: hasAddr
              ? themeColor.withValues(alpha:0.04)
              : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasAddr ? themeColor.withValues(alpha:0.3) : Colors.grey[200]!,
            width: hasAddr ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasAddr
                  ? Icons.location_on_rounded
                  : Icons.add_location_alt_outlined,
              size: 20,
              color: hasAddr ? themeColor : Colors.grey.shade400,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: hasAddr
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Service Location',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: themeColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          selectedAddress,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2D2D2D),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : Text(
                      'Tap to select address',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Colors.grey[400],
                      ),
                    ),
            ),
            Icon(Icons.expand_more_rounded,
                color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

class _AddrSuggestionTile extends StatelessWidget {
  final PlacesSuggestion suggestion;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;

  const _AddrSuggestionTile({
    required this.suggestion,
    required this.onTap,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(12) : Radius.zero,
        bottom: isLast ? const Radius.circular(12) : Radius.zero,
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.location_on_rounded,
                size: 16, color: Color(0xFF00897B)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.mainText,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (suggestion.secondaryText.isNotEmpty)
                    Text(
                      suggestion.secondaryText,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
