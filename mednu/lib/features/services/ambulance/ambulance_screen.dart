import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/booking_service.dart';
import '../../home/providers/location_provider.dart';
import '../../location/providers/saved_addresses_provider.dart';
import '../../location/models/saved_address.dart';
import '../../location/screens/map_location_picker_screen.dart';

const _kRed = Color(0xFFB71C1C);
const _kRedLight = Color(0xFFE53935);
const _kGreen = Color(0xFF2E7D32);

// ─────────────────────────────────────────────────────────────────────────────
// Ambulance types
// ─────────────────────────────────────────────────────────────────────────────
class _AmbulanceType {
  final String name;
  final String price;
  final String description;
  final IconData icon;
  final int priceNum;

  const _AmbulanceType({
    required this.name,
    required this.price,
    required this.description,
    required this.icon,
    required this.priceNum,
  });
}

const _types = [
  _AmbulanceType(
    name: 'Basic',
    price: '₹500',
    description: 'For non-critical patients & transport',
    icon: Icons.local_shipping_rounded,
    priceNum: 500,
  ),
  _AmbulanceType(
    name: 'Advanced Life Support',
    price: '₹1200',
    description: 'Critical patients with paramedic team',
    icon: Icons.medical_services_rounded,
    priceNum: 1200,
  ),
  _AmbulanceType(
    name: 'ICU Ambulance',
    price: '₹2500',
    description: 'Mobile ICU with full medical equipment',
    icon: Icons.health_and_safety_rounded,
    priceNum: 2500,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class AmbulanceScreen extends ConsumerStatefulWidget {
  const AmbulanceScreen({super.key});

  @override
  ConsumerState<AmbulanceScreen> createState() => _AmbulanceScreenState();
}

class _AmbulanceScreenState extends ConsumerState<AmbulanceScreen> {
  String _selectedType = 'Basic';
  bool _busy = false;
  bool _done = false;

  // GPS-verified location (null = not set yet)
  PreciseAddress? _location;
  bool _locationLoading = false;
  bool _providerSynced = false; // prevent repeated syncs

  final _notesCtrl = TextEditingController();
  String _patientName = '';
  String _patientPhone = '';

  @override
  void initState() {
    super.initState();
    _prefillPatient();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryProviderSync());
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Patient data from Firebase ──────────────────────────

  Future<void> _prefillPatient() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final raw = user.phoneNumber ?? '';
    if (mounted) {
      setState(() =>
          _patientPhone = raw.startsWith('+91') ? raw.substring(3) : raw);
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted) {
        setState(() => _patientName = snap.data()?['name'] ?? '');
      }
    } catch (_) {}
  }

  // ── Location init ────────────────────────────────────────

  void _tryProviderSync() {
    if (_providerSynced) return;
    _providerSynced = true;
    final locState = ref.read(locationProvider);
    // Show cached address immediately so the user sees something
    if (locState.preciseAddress != null && locState.hasCoordinates) {
      setState(() => _location = locState.preciseAddress);
    }
    // Always force a fresh GPS fix for emergency dispatch — stale coordinates
    // can send the ambulance to the wrong location.
    _fetchGPS();
  }

  Future<void> _fetchGPS() async {
    if (_locationLoading) return;
    setState(() => _locationLoading = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        if (mounted) {
          setState(() => _locationLoading = false);
          _showPermissionDeniedSnack();
        }
        return;
      }
      await ref.read(locationProvider.notifier).fetchCurrent();
      if (mounted) {
        final loc = ref.read(locationProvider);
        setState(() {
          _location = loc.preciseAddress;
          _locationLoading = false;
          _providerSynced = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  void _showPermissionDeniedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Location permission denied. Please enable in Settings.',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        backgroundColor: _kRed,
        action: SnackBarAction(
          label: 'Settings',
          textColor: Colors.white,
          onPressed: () => Geolocator.openAppSettings(),
        ),
      ),
    );
  }

  // ── Location picker bottom sheet ─────────────────────────

  void _showLocationPicker() {
    final locState = ref.read(locationProvider);
    final saved = ref.read(savedAddressesProvider).valueOrNull ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LocationPickerSheet(
        locState: locState,
        saved: saved,
        onUseGPS: () {
          Navigator.pop(context);
          final loc = ref.read(locationProvider);
          if (loc.preciseAddress != null && loc.hasCoordinates) {
            setState(() => _location = loc.preciseAddress);
          } else {
            _fetchGPS();
          }
        },
        onSavedPicked: (addr) {
          Navigator.pop(context);
          setState(() {
            _location = PreciseAddress(
              plotNo: addr.plotNo,
              building: addr.building,
              street: addr.street,
              area: addr.area,
              city: addr.city,
              state: addr.state,
              pincode: addr.pincode,
              lat: addr.lat,
              lng: addr.lng,
            );
          });
        },
        onMapPick: () async {
          Navigator.pop(context);
          final loc = ref.read(locationProvider);
          final picked = await Navigator.push<PreciseAddress>(
            context,
            MaterialPageRoute(
              builder: (_) => MapLocationPickerScreen(
                initialLat: loc.lat,
                initialLng: loc.lng,
              ),
            ),
          );
          if (picked != null && mounted) {
            setState(() => _location = picked);
          }
        },
        onRefreshGPS: () {
          Navigator.pop(context);
          _fetchGPS();
        },
      ),
    );
  }

  // ── Booking ──────────────────────────────────────────────

  bool get _hasValidLocation =>
      _location != null && (_location!.lat != 0 || _location!.lng != 0);

  Future<void> _bookNow() async {
    if (!_hasValidLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please confirm your GPS pickup location first.',
            style: TextStyle(fontFamily: 'Poppins'),
          ),
          backgroundColor: _kRed,
        ),
      );
      return;
    }

    final typeData = _types.firstWhere((t) => t.name == _selectedType,
        orElse: () => _types.first);

    setState(() => _busy = true);
    try {
      await BookingService.createRequest(
        type: 'ambulance',
        serviceName: '${typeData.name} Ambulance',
        patientName: _patientName.isNotEmpty ? _patientName : 'Emergency',
        patientPhone: _patientPhone,
        address: _location!.formatted,
        preferredDate: 'Immediate',
        preferredTime: 'Now',
        notes: _notesCtrl.text.trim(),
        serviceDetails: {
          'ambulanceType': typeData.name,
          'price': typeData.priceNum,
          'locationData': _location!.toBookingMap(),
        },
      );
      if (mounted) setState(() {
        _busy = false;
        _done = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Booking failed. Please try again.',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: _kRed,
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Update location as the fresh GPS fix arrives
    final locState = ref.watch(locationProvider);
    if (_locationLoading &&
        !locState.isDetecting &&
        locState.preciseAddress != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _location = locState.preciseAddress;
            _locationLoading = false;
          });
        }
      });
    }

    if (_done) return _buildSuccess();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLocationSection(),
                  const SizedBox(height: 24),
                  _buildTypesSection(),
                  const SizedBox(height: 24),
                  _buildNotesSection(),
                  const SizedBox(height: 110),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── App bar ──────────────────────────────────────────────

  Widget _buildAppBar() => SliverAppBar(
        pinned: true,
        expandedHeight: 160,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () => context.pop(),
        ),
        flexibleSpace: FlexibleSpaceBar(
          background: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_kRed, _kRedLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.local_shipping_rounded,
                        color: Colors.white, size: 36),
                    const SizedBox(height: 8),
                    Text('Ambulance Service',
                        style: AppTextStyles.onPrimaryH2),
                    Text('Available 24/7 • GPS Precision Dispatch',
                        style: AppTextStyles.onPrimaryBody),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  // ── Location section ──────────────────────────────────────

  Widget _buildLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.emergency_rounded, color: _kRed, size: 18),
            const SizedBox(width: 6),
            Text('Pickup Location', style: AppTextStyles.h4),
            const Spacer(),
            if (!_locationLoading)
              _smallBtn(
                icon: Icons.gps_fixed_rounded,
                label: 'Refresh GPS',
                onTap: _fetchGPS,
              ),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _locationLoading ? null : _showLocationPicker,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _hasValidLocation
                  ? const Color(0xFFFFF5F5)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hasValidLocation
                    ? _kRed.withOpacity(0.35)
                    : Colors.grey[200]!,
                width: _hasValidLocation ? 1.5 : 1,
              ),
              boxShadow: _hasValidLocation
                  ? [
                      BoxShadow(
                          color: _kRed.withOpacity(0.07),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ]
                  : null,
            ),
            child: _locationLoading
                ? _buildLocLoading()
                : _hasValidLocation
                    ? _buildLocSet()
                    : _buildLocEmpty(),
          ),
        ),
        if (_hasValidLocation) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      color: _kGreen, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'GPS: ${_location!.lat.toStringAsFixed(5)}, '
                    '${_location!.lng.toStringAsFixed(5)}',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textHint),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Builder(builder: (ctx) {
                  final age = ref.watch(locationProvider).fixAgeLabel;
                  return age.isNotEmpty
                      ? Text(age,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textHint))
                      : const SizedBox.shrink();
                }),
                const SizedBox(width: 4),
                const Icon(Icons.verified_rounded,
                    size: 13, color: _kGreen),
                const SizedBox(width: 4),
                Text('Live',
                    style: AppTextStyles.caption
                        .copyWith(color: _kGreen)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLocLoading() => Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: _kRed),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Detecting your location…',
                  style:
                      AppTextStyles.labelLarge.copyWith(color: _kRed)),
              Text('High-accuracy GPS enabled',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textHint)),
            ],
          ),
        ],
      );

  Widget _buildLocSet() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_rounded, color: _kRed, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _location!.area ??
                      _location!.city ??
                      'Location Set',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: _kRed, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  _location!.formatted,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF2D2D2D),
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _kRed.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Change',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kRed,
              ),
            ),
          ),
        ],
      );

  Widget _buildLocEmpty() => Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add_location_alt_rounded,
                    color: _kRed, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select Pickup Location',
                        style: AppTextStyles.labelLarge),
                    Text(
                      'Tap to detect GPS or pick on map',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey.shade400),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _quickBtn(
                  icon: Icons.gps_fixed_rounded,
                  label: 'Use GPS',
                  onTap: _fetchGPS,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickBtn(
                  icon: Icons.map_rounded,
                  label: 'Pick on Map',
                  onTap: () async {
                    final loc = ref.read(locationProvider);
                    final picked = await Navigator.push<PreciseAddress>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapLocationPickerScreen(
                          initialLat: loc.lat,
                          initialLng: loc.lng,
                        ),
                      ),
                    );
                    if (picked != null && mounted) {
                      setState(() => _location = picked);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      );

  Widget _quickBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _kRed.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kRed.withOpacity(0.15)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: _kRed),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _kRed,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _smallBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: _kRed),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _kRed,
              ),
            ),
          ],
        ),
      );

  // ── Ambulance type cards ──────────────────────────────────

  Widget _buildTypesSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select Ambulance Type', style: AppTextStyles.h4),
          const SizedBox(height: 12),
          ..._types.map((t) {
            final selected = _selectedType == t.name;
            return GestureDetector(
              onTap: () => setState(() => _selectedType = t.name),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFFFF5F5)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? _kRed : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selected
                            ? _kRed.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(t.icon,
                          color: selected
                              ? _kRed
                              : AppColors.textHint,
                          size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.name,
                            style: AppTextStyles.labelLarge.copyWith(
                                color: selected
                                    ? _kRed
                                    : AppColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(t.description,
                              style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ),
                    Text(t.price,
                        style: AppTextStyles.labelLarge
                            .copyWith(color: _kRed)),
                  ],
                ),
              ),
            );
          }),
        ],
      );

  // ── Notes ────────────────────────────────────────────────

  Widget _buildNotesSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Emergency Notes (Optional)', style: AppTextStyles.h4),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              hintText:
                  'Describe the emergency, condition, medical history…',
              hintStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.grey[400]),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[200]!)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[200]!)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: _kRed, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 13),
            ),
          ),
        ],
      );

  // ── Bottom action bar ─────────────────────────────────────

  Widget _buildBottomBar() {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_hasValidLocation && !_locationLoading) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 14, color: Color(0xFFE65100)),
                const SizedBox(width: 6),
                Text(
                  'GPS location required for emergency dispatch',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Colors.orange[700]),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: (_locationLoading || _busy) ? null : _bookNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kRed,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
                disabledBackgroundColor: _kRed.withOpacity(0.45),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.emergency_rounded,
                            size: 20, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          _hasValidLocation
                              ? 'Book Emergency Ambulance'
                              : 'Set Location to Continue',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Success screen ────────────────────────────────────────

  Widget _buildSuccess() {
    final bottom = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                    color: _kRed.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_rounded,
                    color: _kRed, size: 52),
              ),
              const SizedBox(height: 20),
              Text('Ambulance Booked!', style: AppTextStyles.h2),
              const SizedBox(height: 8),
              Text(
                'Emergency request received.\nAn ambulance has been dispatched to your location.',
                style: AppTextStyles.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // ETA card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _kGreen.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_rounded,
                        color: _kGreen, size: 26),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Estimated Arrival',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: _kGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '8–12 minutes',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _kGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Booking detail card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    _detailRow(Icons.local_shipping_rounded, 'Type',
                        '$_selectedType Ambulance'),
                    if (_location != null)
                      _detailRow(Icons.location_on_rounded, 'Pickup',
                          _location!.formatted),
                    if (_location != null)
                      _detailRow(
                        Icons.gps_fixed_rounded,
                        'GPS',
                        '${_location!.lat.toStringAsFixed(5)}, '
                            '${_location!.lng.toStringAsFixed(5)}',
                      ),
                    _detailRow(Icons.info_rounded, 'Status',
                        'Dispatching…'),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => context.pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRed,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              SizedBox(height: bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 16, color: _kRed),
            const SizedBox(width: 10),
            Text(
              '$label: ',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Location picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────
class _LocationPickerSheet extends StatelessWidget {
  final LocationState locState;
  final List<SavedAddress> saved;
  final VoidCallback onUseGPS;
  final void Function(SavedAddress) onSavedPicked;
  final VoidCallback onMapPick;
  final VoidCallback onRefreshGPS;

  const _LocationPickerSheet({
    required this.locState,
    required this.saved,
    required this.onUseGPS,
    required this.onSavedPicked,
    required this.onMapPick,
    required this.onRefreshGPS,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.emergency_rounded,
                    color: _kRed, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Select Pickup Location',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Safety notice
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFFF8F00).withOpacity(0.35)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xFFE65100)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Precise GPS location required for emergency dispatch. Random text addresses are not accepted.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Color(0xFFE65100),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Current GPS
                _tile(
                  context: context,
                  icon: Icons.my_location_rounded,
                  iconBg: _kRed,
                  title: 'Current GPS Location',
                  subtitle: locState.preciseAddress?.formatted.isNotEmpty ==
                          true
                      ? locState.preciseAddress!.formatted
                      : locState.hasCoordinates
                          ? locState.fullAddress
                          : 'Tap to detect current location',
                  trailing: locState.hasCoordinates
                      ? _gpsBadge()
                      : _refreshBtn(onRefreshGPS),
                  onTap: locState.hasCoordinates
                      ? onUseGPS
                      : onRefreshGPS,
                ),

                // Saved addresses
                ...saved.map(
                  (addr) => _tile(
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
                            : _kRed,
                    title: addr.displayLabel,
                    subtitle: addr.formattedAddress,
                    trailing: addr.isDefault ? _defaultBadge() : null,
                    onTap: () => onSavedPicked(addr),
                  ),
                ),

                // Map picker
                _tile(
                  context: context,
                  icon: Icons.map_rounded,
                  iconBg: const Color(0xFF1565C0),
                  title: 'Pick on Map',
                  subtitle: 'Drag pin to exact pickup point on map',
                  onTap: onMapPick,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required BuildContext context,
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconBg, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing
              else
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey.shade400, size: 18),
            ],
          ),
        ),
      );

  Widget _gpsBadge() => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _kGreen.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, size: 11, color: _kGreen),
            SizedBox(width: 3),
            Text(
              'GPS',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _kGreen,
              ),
            ),
          ],
        ),
      );

  Widget _refreshBtn(VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: _kRed,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: const Text(
          'Detect',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
        ),
      );

  Widget _defaultBadge() => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(5),
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
      );
}
