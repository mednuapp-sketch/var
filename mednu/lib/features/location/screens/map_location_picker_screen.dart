import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../home/providers/location_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/places_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Map Location Picker Screen
// Full-screen Google Map with a draggable center-pin.
// Search bar at top, current-location FAB, reverse-geocode on camera idle,
// persistent bottom sheet (180px) with address + Confirm button.
// Handles permission denied, GPS off, offline gracefully.
// ─────────────────────────────────────────────────────────────────────────────

enum _Phase {
  checking,
  permissionDenied,
  permissionPermanentlyDenied,
  gpsDisabled,
  offline,
  ready,
  mapLoadFailed,
}

class MapLocationPickerScreen extends ConsumerStatefulWidget {
  final double? initialLat;
  final double? initialLng;

  /// Whether confirming a pin also overwrites the app-wide "my current
  /// location" (`locationProvider`). Defaults to true, matching every
  /// existing call site. Pass false when picking a location for someone
  /// else (e.g. a family member's delivery address) so the orderer's own
  /// saved location isn't silently overwritten by the recipient's pin.
  final bool updateGlobalLocation;

  const MapLocationPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.updateGlobalLocation = true,
  });

  @override
  ConsumerState<MapLocationPickerScreen> createState() =>
      _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState
    extends ConsumerState<MapLocationPickerScreen> {
  // Map
  GoogleMapController? _mapCtrl;
  bool _mapReady = false;
  LatLng? _center;

  // Search
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<PlacesSuggestion> _searchSuggestions = [];
  Timer? _searchDebounce;
  bool _suppressSearchListener = false;
  // State
  _Phase _phase = _Phase.checking;
  bool _geocoding = false;
  bool _geocodingFailed = false;
  PreciseAddress? _picked;

  // Timers & cancel token
  Timer? _debounceTimer;
  Timer? _geocodeTimeoutTimer;
  Timer? _mapLoadTimer;
  int _geocodeSeq = 0;
  Key _mapKey = UniqueKey();
  bool _userMovedMap = false;

  static const double _defaultZoom = 16.5;
  static const double _fallbackLat = 17.3850; // Hyderabad
  static const double _fallbackLng = 78.4867;
  static const int _geocodeTimeoutSec = 10;
  static const int _mapLoadTimeoutSec = 8;

  // Bottom sheet height constant
  static const double _sheetHeight = 200;

  double get _initLat => widget.initialLat ?? _fallbackLat;
  double get _initLng => widget.initialLng ?? _fallbackLng;

  @override
  void initState() {
    super.initState();
    _preflight();
    _searchCtrl.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _geocodeTimeoutTimer?.cancel();
    _mapLoadTimer?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchTextChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ── Pre-flight ────────────────────────────────────────────────────────────

  Future<void> _preflight() async {
    if (mounted) setState(() => _phase = _Phase.checking);

    // Connectivity
    final result = await Connectivity().checkConnectivity();
    final results = result is List ? result as List : [result];
    final isOnline = results.any((r) => r != ConnectivityResult.none);
    if (!isOnline) {
      if (mounted) setState(() => _phase = _Phase.offline);
      return;
    }

    // Location permission
    var status = await Permission.locationWhenInUse.status;
    if (status.isPermanentlyDenied) {
      if (mounted) setState(() => _phase = _Phase.permissionPermanentlyDenied);
      return;
    }
    if (status.isDenied) {
      status = await Permission.locationWhenInUse.request();
      if (!mounted) return;
      if (status.isPermanentlyDenied) {
        setState(() => _phase = _Phase.permissionPermanentlyDenied);
        return;
      }
      if (status.isDenied) {
        setState(() => _phase = _Phase.permissionDenied);
        return;
      }
    }

    // GPS
    final gpsOn = await Geolocator.isLocationServiceEnabled();
    if (!gpsOn) {
      if (mounted) setState(() => _phase = _Phase.gpsDisabled);
      return;
    }

    if (mounted) {
      setState(() => _phase = _Phase.ready);
      _startMapLoadTimeout();
    }
  }

  void _startMapLoadTimeout() {
    _mapLoadTimer?.cancel();
    _mapLoadTimer = Timer(const Duration(seconds: _mapLoadTimeoutSec), () {
      if (!mounted || _mapReady) return;
      setState(() => _phase = _Phase.mapLoadFailed);
    });
  }

  void _retryMapLoad() {
    setState(() {
      _mapKey = UniqueKey();
      _mapReady = false;
      _phase = _Phase.ready;
    });
    _startMapLoadTimeout();
  }

  // ── Map callbacks ─────────────────────────────────────────────────────────

  void _onMapCreated(GoogleMapController ctrl) {
    _mapLoadTimer?.cancel();
    _mapCtrl = ctrl;
    setState(() => _mapReady = true);

    if (widget.initialLat != null) {
      _center = LatLng(_initLat, _initLng);
      // Force a camera move so the map's bottom `padding` (which keeps the
      // pin clear of the bottom sheet) is applied to this initial position too —
      // `initialCameraPosition` alone renders centered in the full widget,
      // ignoring padding, which visually offsets the pin from the true target
      // until the user drags the map.
      _mapCtrl!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _center!, zoom: _defaultZoom),
        ),
      );
      _scheduleGeocode();
    } else {
      _moveToCurrentPos();
    }
  }

  void _onCameraMoveStarted() => _userMovedMap = true;

  void _onCameraMove(CameraPosition pos) {
    _center = pos.target;
    _geocodingFailed = false;
    if (!_geocoding) setState(() => _geocoding = true);
  }

  void _onCameraIdle() => _scheduleGeocode();

  void _scheduleGeocode() {
    _debounceTimer?.cancel();
    _debounceTimer =
        Timer(const Duration(milliseconds: 600), _reverseGeocode);
  }

  // ── Address search ───────────────────────────────────────────────────────

  void _onSearchTextChanged() {
    if (_suppressSearchListener) return;
    final q = _searchCtrl.text.trim();
    _searchDebounce?.cancel();
    if (q.length < 2) {
      setState(() => _searchSuggestions = []);
      return;
    }
    setState(() {}); // reflect the clear button as the user types
    _searchDebounce =
        Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (!mounted) return;
    final results = await placesService.autocomplete(
      q,
      lat: _center?.latitude,
      lng: _center?.longitude,
    );
    if (!mounted || _searchCtrl.text.trim() != q) return;
    setState(() => _searchSuggestions = results);
  }

  Future<void> _selectSuggestion(PlacesSuggestion s) async {
    _searchFocus.unfocus();
    _searchDebounce?.cancel();
    _suppressSearchListener = true;
    setState(() {
      _searchSuggestions = [];
      _searchCtrl.text = s.fullText;
    });
    _suppressSearchListener = false;
    if (_mapCtrl == null) return;
    final details = await placesService.details(s.placeId);
    if (!mounted || details == null) return;
    _userMovedMap = true;
    _animateTo(LatLng(details.lat, details.lng));
  }

  // ── GPS ───────────────────────────────────────────────────────────────────

  Future<void> _moveToCurrentPos() async {
    if (!mounted) return;
    _userMovedMap = false;
    setState(() => _geocoding = true);

    try {
      // Fast coarse fix
      try {
        final quick = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 4),
        );
        if (mounted && _mapCtrl != null && !_userMovedMap) {
          _animateTo(LatLng(quick.latitude, quick.longitude));
        }
      } catch (_) {}

      // High-accuracy
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      if (mounted && _mapCtrl != null && !_userMovedMap) {
        _animateTo(LatLng(pos.latitude, pos.longitude));
      }
    } catch (_) {
      if (mounted && _mapCtrl != null && !_userMovedMap) {
        _center = LatLng(_initLat, _initLng);
        // Same padding fix as _onMapCreated: force a camera move to the
        // fallback position so it's rendered padding-aware instead of at
        // the raw (unpadded) initialCameraPosition.
        _mapCtrl!.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _center!, zoom: _defaultZoom),
          ),
        );
        _scheduleGeocode();
      }
    }
  }

  void _animateTo(LatLng pos) {
    _mapCtrl!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: pos, zoom: _defaultZoom),
      ),
    );
  }

  // ── Geocoding ─────────────────────────────────────────────────────────────

  Future<void> _reverseGeocode() async {
    final seq = ++_geocodeSeq;
    final center = _center ?? LatLng(_initLat, _initLng);

    _geocodeTimeoutTimer?.cancel();
    _geocodeTimeoutTimer = Timer(
      const Duration(seconds: _geocodeTimeoutSec),
      () {
        if (!mounted || seq != _geocodeSeq) return;
        setState(() {
          _geocoding = false;
          _geocodingFailed = true;
          _picked ??= PreciseAddress(lat: center.latitude, lng: center.longitude);
        });
      },
    );

    try {
      final details = await placesService.reverseGeocode(
          center.latitude, center.longitude);
      if (!mounted || seq != _geocodeSeq) return;
      _geocodeTimeoutTimer?.cancel();

      if (details != null) {
        setState(() {
          _picked = PreciseAddress(
            plotNo: details.plotNo,
            building: details.building,
            street: details.street,
            area: details.area,
            city: details.city,
            state: details.state,
            pincode: details.pincode,
            lat: center.latitude,
            lng: center.longitude,
          );
          _geocoding = false;
          _geocodingFailed = false;
        });
      } else {
        setState(() {
          _picked = PreciseAddress(lat: center.latitude, lng: center.longitude);
          _geocoding = false;
          _geocodingFailed = true;
        });
      }
    } catch (_) {
      if (!mounted || seq != _geocodeSeq) return;
      _geocodeTimeoutTimer?.cancel();
      setState(() {
        _picked = PreciseAddress(lat: center.latitude, lng: center.longitude);
        _geocoding = false;
        _geocodingFailed = true;
      });
    }
  }

  // ── Confirm ───────────────────────────────────────────────────────────────

  void _confirm() {
    final p = _picked;
    if (p == null) return;
    if (widget.updateGlobalLocation) {
      ref.read(locationProvider.notifier).setPreciseAddress(p);
    }
    Navigator.pop(context, p);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBase : const Color(0xFFF5F5F5),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    switch (_phase) {
      case _Phase.checking:
        return const _CheckingView();

      case _Phase.permissionDenied:
        return _ErrorGateView(
          icon: Icons.location_off_rounded,
          iconColor: AppColors.primary,
          title: 'Location Permission Required',
          subtitle:
              'MedNU needs your location to find nearby doctors, hospitals, and home services.',
          primaryLabel: 'Grant Permission',
          onPrimary: () async {
            final s = await Permission.locationWhenInUse.request();
            if (s.isGranted) _preflight();
          },
          secondaryLabel: 'Go Back',
          onSecondary: () => Navigator.pop(context),
        );

      case _Phase.permissionPermanentlyDenied:
        return _ErrorGateView(
          icon: Icons.location_disabled_rounded,
          iconColor: Colors.red,
          title: 'Location Access Blocked',
          subtitle:
              'Please enable "Location" permission for MedNU in your device Settings > Apps.',
          primaryLabel: 'Open Settings',
          onPrimary: () async {
            await openAppSettings();
            if (mounted) _preflight();
          },
          secondaryLabel: 'Go Back',
          onSecondary: () => Navigator.pop(context),
        );

      case _Phase.gpsDisabled:
        return _ErrorGateView(
          icon: Icons.gps_off_rounded,
          iconColor: Colors.orange,
          title: 'GPS is Turned Off',
          subtitle:
              'Enable Location / GPS on your device to pin your address on the map.',
          primaryLabel: 'Enable GPS',
          onPrimary: () async {
            await Geolocator.openLocationSettings();
            if (mounted) _preflight();
          },
          secondaryLabel: 'Go Back',
          onSecondary: () => Navigator.pop(context),
        );

      case _Phase.offline:
        return _ErrorGateView(
          icon: Icons.wifi_off_rounded,
          iconColor: Colors.blueGrey,
          title: 'No Internet Connection',
          subtitle:
              'An internet connection is required to load the map and resolve your address.',
          primaryLabel: 'Retry',
          onPrimary: _preflight,
          secondaryLabel: 'Go Back',
          onSecondary: () => Navigator.pop(context),
        );

      case _Phase.mapLoadFailed:
        return _ErrorGateView(
          icon: Icons.map_outlined,
          iconColor: Colors.red,
          title: 'Map Failed to Load',
          subtitle:
              'We couldn\'t load Google Maps on this device. Check your internet connection and Google Play Services, then try again.',
          primaryLabel: 'Retry',
          onPrimary: _retryMapLoad,
          secondaryLabel: 'Go Back',
          onSecondary: () => Navigator.pop(context),
        );

      case _Phase.ready:
        return _buildMapStack(isDark);
    }
  }

  Widget _buildMapStack(bool isDark) {
    final String addressText;
    if (_geocoding) {
      addressText = 'Finding address...';
    } else if (_geocodingFailed) {
      addressText = 'Unable to determine address';
    } else {
      addressText = _picked?.short ?? 'Move map to set location';
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Google Map ─────────────────────────────────────────────────────
        Positioned.fill(
          child: GoogleMap(
            key: _mapKey,
            initialCameraPosition: CameraPosition(
              target: LatLng(_initLat, _initLng),
              zoom: _defaultZoom,
            ),
            onMapCreated: _onMapCreated,
            onCameraMoveStarted: _onCameraMoveStarted,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            padding: const EdgeInsets.only(bottom: _sheetHeight),
          ),
        ),

        // ── Map loading shimmer ────────────────────────────────────────────
        if (!_mapReady) const _MapLoadingShimmer(),

        // ── Centre pin ─────────────────────────────────────────────────────
        if (_mapReady)
          Positioned.fill(
            bottom: _sheetHeight,
            child: _CentrePin(geocoding: _geocoding),
          ),

        // ── Search bar (top, floating over map) + suggestions ───────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _MapIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        isDark: isDark,
                        onTap: () => context.pop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SearchBar(
                          controller: _searchCtrl,
                          focusNode: _searchFocus,
                          isDark: isDark,
                          addressText: addressText,
                          isLoading: _geocoding,
                          onSearchActive: (_) {},
                          onClear: () =>
                              setState(() => _searchSuggestions = []),
                        ),
                      ),
                    ],
                  ),
                  if (_searchSuggestions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 52),
                      child: _SearchSuggestionsList(
                        suggestions: _searchSuggestions,
                        isDark: isDark,
                        onTap: _selectSuggestion,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // ── Retry geocode FAB ──────────────────────────────────────────────
        if (_geocodingFailed && _mapReady)
          Positioned(
            right: 16,
            bottom: _sheetHeight + 66,
            child: _MapFab(
              icon: Icons.refresh_rounded,
              tooltip: 'Retry address lookup',
              isDark: isDark,
              onTap: () {
                setState(() {
                  _geocoding = true;
                  _geocodingFailed = false;
                });
                _reverseGeocode();
              },
            ),
          ),

        // ── My location FAB ────────────────────────────────────────────────
        if (_mapReady)
          Positioned(
            right: 16,
            bottom: _sheetHeight + 12,
            child: _MapFab(
              icon: Icons.my_location_rounded,
              tooltip: 'Go to my location',
              isDark: isDark,
              onTap: _moveToCurrentPos,
            ),
          ),

        // ── Bottom confirm sheet (persistent 180px) ────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomConfirmSheet(
            picked: _picked,
            isLoading: _geocoding,
            isFailed: _geocodingFailed,
            isDark: isDark,
            onConfirm: _confirm,
          ),
        ),
      ],
    );
  }
}

// ── Checking view ─────────────────────────────────────────────────────────────

class _CheckingView extends StatelessWidget {
  const _CheckingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2.5),
          SizedBox(height: 16),
          Text(
            'Checking location access…',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error gate view ───────────────────────────────────────────────────────────

class _ErrorGateView extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  const _ErrorGateView({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: onSecondary,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 18),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 42),
            ),
            const SizedBox(height: 28),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.6)
                    : Colors.grey.shade600,
                height: 1.6,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onPrimary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  primaryLabel,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: onSecondary,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  secondaryLabel,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Map loading shimmer ───────────────────────────────────────────────────────

class _MapLoadingShimmer extends StatefulWidget {
  const _MapLoadingShimmer();

  @override
  State<_MapLoadingShimmer> createState() => _MapLoadingShimmerState();
}

class _MapLoadingShimmerState extends State<_MapLoadingShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        color: Color.lerp(
          const Color(0xFFE8E8E8),
          const Color(0xFFF5F5F5),
          _anim.value,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2.5),
              const SizedBox(height: 14),
              Text(
                'Loading map…',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Centre pin with pulse animation ──────────────────────────────────────────

class _CentrePin extends StatefulWidget {
  final bool geocoding;
  const _CentrePin({required this.geocoding});

  @override
  State<_CentrePin> createState() => _CentrePinState();
}

class _CentrePinState extends State<_CentrePin>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Transform.scale(
          scale: widget.geocoding ? _pulse.value : 1.0,
          child: child,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: widget.geocoding ? 4 : 2,
                  ),
                ],
              ),
              child: const Icon(Icons.location_on_rounded,
                  color: Colors.white, size: 26),
            ),
            Container(width: 2, height: 14, color: AppColors.primary),
            Container(
              width: 10,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search bar (floating over map) ────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final String addressText;
  final bool isLoading;
  final ValueChanged<bool> onSearchActive;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.isDark,
    required this.addressText,
    required this.isLoading,
    required this.onSearchActive,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onTap: () => onSearchActive(true),
        onSubmitted: (_) => onSearchActive(false),
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: isLoading ? 'Finding address...' : addressText,
          hintStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: isDark ? Colors.white60 : Colors.grey.shade500,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: isLoading ? AppColors.primary : Colors.grey.shade500,
          ),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 18,
                      color: isDark ? Colors.white60 : Colors.grey.shade500),
                  onPressed: () {
                    controller.clear();
                    onClear();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}

// ── Search suggestions dropdown ────────────────────────────────────────────

class _SearchSuggestionsList extends StatelessWidget {
  final List<PlacesSuggestion> suggestions;
  final bool isDark;
  final ValueChanged<PlacesSuggestion> onTap;

  const _SearchSuggestionsList({
    required this.suggestions,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.shade100,
        ),
        itemBuilder: (context, i) {
          final s = suggestions[i];
          return InkWell(
            onTap: () => onTap(s),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 18,
                      color: isDark ? Colors.white60 : Colors.grey.shade500),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.mainText.isNotEmpty ? s.mainText : s.fullText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        if (s.secondaryText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            s.secondaryText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11.5,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Map icon button ───────────────────────────────────────────────────────────

class _MapIconButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _MapIconButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon,
            size: 20,
            color: isDark ? Colors.white : Colors.black87),
      ),
    );
  }
}

// ── Floating map button ───────────────────────────────────────────────────────

class _MapFab extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onTap;

  const _MapFab({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
      ),
    );
  }
}

// ── Bottom confirm sheet (persistent 180px) ───────────────────────────────────

class _BottomConfirmSheet extends StatelessWidget {
  final PreciseAddress? picked;
  final bool isLoading;
  final bool isFailed;
  final bool isDark;
  final VoidCallback onConfirm;

  const _BottomConfirmSheet({
    required this.picked,
    required this.isLoading,
    required this.isFailed,
    required this.isDark,
    required this.onConfirm,
  });

  bool get _canConfirm => !isLoading && picked != null;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, bottomPad + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Address row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected Location',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (isLoading)
                      _ShimmerBar(isDark: isDark)
                    else if (isFailed)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Unable to determine location',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          if (picked != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${picked!.lat.toStringAsFixed(5)}, ${picked!.lng.toStringAsFixed(5)}',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ],
                      )
                    else
                      Text(
                        picked?.formatted ?? 'Move the map to set location',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _canConfirm ? onConfirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.check_circle_outline_rounded,
                        color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    isLoading
                        ? 'Locating...'
                        : isFailed
                            ? 'Confirm Pin Location'
                            : 'Confirm Location',
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
}

// ── Shimmer skeleton bar ──────────────────────────────────────────────────────

class _ShimmerBar extends StatefulWidget {
  final bool isDark;
  const _ShimmerBar({required this.isDark});

  @override
  State<_ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<_ShimmerBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.8).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 13,
            width: 220,
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.white.withValues(alpha: _anim.value * 0.15)
                  : Colors.grey.withValues(alpha: _anim.value * 0.35),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 10,
            width: 140,
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.white.withValues(alpha: _anim.value * 0.1)
                  : Colors.grey.withValues(alpha: _anim.value * 0.25),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }
}
