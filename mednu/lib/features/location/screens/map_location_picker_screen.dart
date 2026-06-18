import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../home/providers/location_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/places_service.dart';
import '../../../core/utils/maps_launcher.dart';

// ─── Picker phase ─────────────────────────────────────────────────────────────

enum _Phase {
  checking,
  permissionDenied,
  permissionPermanentlyDenied,
  gpsDisabled,
  offline,
  ready,
}

// ═════════════════════════════════════════════════════════════════════════════
// MapLocationPickerScreen
// ═════════════════════════════════════════════════════════════════════════════

class MapLocationPickerScreen extends ConsumerStatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const MapLocationPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
  });

  @override
  ConsumerState<MapLocationPickerScreen> createState() =>
      _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState
    extends ConsumerState<MapLocationPickerScreen> {
  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapCtrl;
  bool _mapReady = false;
  LatLng? _center;

  // ── State ────────────────────────────────────────────────────────────────
  _Phase _phase = _Phase.checking;
  bool _geocoding = false;
  bool _geocodingFailed = false;
  PreciseAddress? _picked;

  // ── Timers & cancel token ────────────────────────────────────────────────
  Timer? _debounceTimer;
  Timer? _geocodeTimeoutTimer;
  int _geocodeSeq = 0; // stale result guard

  static const double _defaultZoom = 16.5;
  static const double _fallbackLat = 17.3850; // Hyderabad
  static const double _fallbackLng = 78.4867;
  static const int _geocodeTimeoutSec = 10;

  double get _initLat => widget.initialLat ?? _fallbackLat;
  double get _initLng => widget.initialLng ?? _fallbackLng;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _preflight();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _geocodeTimeoutTimer?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ── Pre-flight: permission + GPS + connectivity ───────────────────────────

  Future<void> _preflight() async {
    if (mounted) setState(() => _phase = _Phase.checking);

    // 1. Connectivity
    final result = await Connectivity().checkConnectivity();
    final results = result is List ? result as List : [result];
    final isOnline = results.any((r) => r != ConnectivityResult.none);
    if (!isOnline) {
      if (mounted) setState(() => _phase = _Phase.offline);
      return;
    }

    // 2. Location permission
    var status = await Permission.locationWhenInUse.status;
    if (status.isPermanentlyDenied) {
      if (mounted) {
        setState(() => _phase = _Phase.permissionPermanentlyDenied);
      }
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

    // 3. GPS enabled
    final gpsOn = await Geolocator.isLocationServiceEnabled();
    if (!gpsOn) {
      if (mounted) setState(() => _phase = _Phase.gpsDisabled);
      return;
    }

    if (mounted) setState(() => _phase = _Phase.ready);
  }

  // ── Map callbacks ─────────────────────────────────────────────────────────

  void _onMapCreated(GoogleMapController ctrl) {
    _mapCtrl = ctrl;
    setState(() => _mapReady = true);

    if (widget.initialLat != null) {
      // Provided coordinates: geocode immediately
      _center = LatLng(_initLat, _initLng);
      _scheduleGeocode();
    } else {
      // No initial coords: move to user's GPS
      _moveToCurrentPos();
    }
  }

  void _onCameraMove(CameraPosition pos) {
    _center = pos.target;
    _geocodingFailed = false;
    if (!_geocoding) setState(() => _geocoding = true);
  }

  void _onCameraIdle() {
    _scheduleGeocode();
  }

  void _scheduleGeocode() {
    _debounceTimer?.cancel();
    _debounceTimer =
        Timer(const Duration(milliseconds: 600), _reverseGeocode);
  }

  // ── GPS ──────────────────────────────────────────────────────────────────

  Future<void> _moveToCurrentPos() async {
    if (!mounted) return;
    setState(() => _geocoding = true);

    try {
      // Fast coarse fix first for quick feedback
      try {
        final quick = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 4),
        );
        if (mounted && _mapCtrl != null) {
          _animateTo(LatLng(quick.latitude, quick.longitude));
        }
      } catch (_) {}

      // High-accuracy follow-up
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      if (mounted && _mapCtrl != null) {
        _animateTo(LatLng(pos.latitude, pos.longitude));
      }
    } catch (_) {
      // GPS unavailable — geocode the fallback (Hyderabad) to at least show
      // something in the address bar
      if (mounted) {
        _center = LatLng(_initLat, _initLng);
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

    // Arm 10-second safety timeout
    _geocodeTimeoutTimer?.cancel();
    _geocodeTimeoutTimer = Timer(
      const Duration(seconds: _geocodeTimeoutSec),
      () {
        if (!mounted || seq != _geocodeSeq) return;
        setState(() {
          _geocoding = false;
          _geocodingFailed = true;
          // Allow confirm with coordinates only
          _picked ??= PreciseAddress(
            lat: center.latitude,
            lng: center.longitude,
          );
        });
      },
    );

    try {
      final details =
          await placesService.reverseGeocode(center.latitude, center.longitude);
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
        // API returned nothing — allow pin-only confirmation
        setState(() {
          _picked = PreciseAddress(
            lat: center.latitude,
            lng: center.longitude,
          );
          _geocoding = false;
          _geocodingFailed = true;
        });
      }
    } catch (_) {
      if (!mounted || seq != _geocodeSeq) return;
      _geocodeTimeoutTimer?.cancel();
      setState(() {
        _picked = PreciseAddress(
          lat: center.latitude,
          lng: center.longitude,
        );
        _geocoding = false;
        _geocodingFailed = true;
      });
    }
  }

  // ── Confirm ───────────────────────────────────────────────────────────────

  void _confirm() {
    final p = _picked;
    if (p == null) return;
    ref.read(locationProvider.notifier).setPreciseAddress(p);
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
              'MedNu needs your location to find nearby doctors, hospitals, and home services.',
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
              'Please enable "Location" permission for MedNu in your device Settings > Apps.',
          primaryLabel: 'Open Settings',
          onPrimary: () async {
            await openAppSettings();
            // Re-check after user returns from settings
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

      case _Phase.ready:
        return _buildMapStack(isDark);
    }
  }

  Widget _buildMapStack(bool isDark) {
    final String barLabel;
    if (_geocoding) {
      barLabel = 'Locating…';
    } else if (_geocodingFailed) {
      barLabel = 'Tap confirm to use pin location';
    } else {
      barLabel = _picked?.short ?? 'Move map to set location';
    }

    return Stack(
      children: [
        // ── Google Map ────────────────────────────────────────────────────
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(_initLat, _initLng),
            zoom: _defaultZoom,
          ),
          onMapCreated: _onMapCreated,
          onCameraMove: _onCameraMove,
          onCameraIdle: _onCameraIdle,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
        ),

        // ── Shimmer while map tiles load ──────────────────────────────────
        if (!_mapReady) const _MapLoadingShimmer(),

        // ── Centre pin (only once map is ready) ───────────────────────────
        if (_mapReady) _CentrePin(geocoding: _geocoding),

        // ── Top bar ───────────────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _IconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  isDark: isDark,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AddressBar(
                    label: barLabel,
                    isLoading: _geocoding,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Retry geocode FAB (shown when geocoding failed) ───────────────
        if (_geocodingFailed && _mapReady)
          Positioned(
            right: 16,
            bottom: 278,
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

        // ── My location FAB ───────────────────────────────────────────────
        if (_mapReady)
          Positioned(
            right: 16,
            bottom: 218,
            child: _MapFab(
              icon: Icons.my_location_rounded,
              tooltip: 'Go to my location',
              isDark: isDark,
              onTap: _moveToCurrentPos,
            ),
          ),

        // ── Bottom confirm sheet ───────────────────────────────────────────
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

// ═════════════════════════════════════════════════════════════════════════════
// Checking view — spinner while doing pre-flight
// ═════════════════════════════════════════════════════════════════════════════

class _CheckingView extends StatelessWidget {
  const _CheckingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2.5,
          ),
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

// ═════════════════════════════════════════════════════════════════════════════
// Error gate view — shown for permission / GPS / offline errors
// ═════════════════════════════════════════════════════════════════════════════

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
            // Back button row
            Row(
              children: [
                GestureDetector(
                  onTap: onSecondary,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha:0.08)
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
            // Icon
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 42),
            ),
            const SizedBox(height: 28),
            // Title
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
            // Subtitle
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? Colors.white.withValues(alpha:0.6)
                    : Colors.grey.shade600,
                height: 1.6,
              ),
            ),
            const Spacer(),
            // Primary button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onPrimary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
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
            // Secondary button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: onSecondary,
                style: OutlinedButton.styleFrom(
                  side:
                      BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  secondaryLabel,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color:
                        isDark ? Colors.white70 : Colors.black54,
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

// ═════════════════════════════════════════════════════════════════════════════
// Map loading shimmer
// ═════════════════════════════════════════════════════════════════════════════

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
                color: AppColors.primary,
                strokeWidth: 2.5,
              ),
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

// ═════════════════════════════════════════════════════════════════════════════
// Centre pin with pulse animation while geocoding
// ═════════════════════════════════════════════════════════════════════════════

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
                    color: AppColors.primary.withValues(alpha:0.4),
                    blurRadius: 12,
                    spreadRadius: widget.geocoding ? 4 : 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            Container(
              width: 2,
              height: 14,
              color: AppColors.primary,
            ),
            Container(
              width: 10,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha:0.15),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Address bar
// ═════════════════════════════════════════════════════════════════════════════

class _AddressBar extends StatelessWidget {
  final String label;
  final bool isLoading;
  final bool isDark;

  const _AddressBar({
    required this.label,
    required this.isLoading,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardElevated : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.map_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          if (isLoading) ...[
            // Shimmer skeleton
            Container(
              width: 140,
              height: 12,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha:0.1)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ] else ...[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Top-bar icon button
// ═════════════════════════════════════════════════════════════════════════════

class _IconButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _IconButton(
      {required this.icon, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCardElevated : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
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

// ═════════════════════════════════════════════════════════════════════════════
// Floating map button
// ═════════════════════════════════════════════════════════════════════════════

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
            color: isDark ? AppColors.darkCardElevated : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha:0.15),
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

// ═════════════════════════════════════════════════════════════════════════════
// Bottom confirm sheet
// ═════════════════════════════════════════════════════════════════════════════

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

  void _openInMaps() {
    if (picked == null) return;
    MapsLauncher.openLocation(picked!.lat, picked!.lng,
        label: picked!.formatted);
  }

  bool get _canConfirm => !isLoading && picked != null;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardElevated : Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding:
          EdgeInsets.fromLTRB(20, 16, 20, bottomPad + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
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
          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.location_on_rounded,
                    color: AppColors.primary, size: 22),
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
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isLoading)
                      _ShimmerBar(isDark: isDark)
                    else if (isFailed && picked != null)
                      Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pin placed — address lookup failed',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.black54,
                            ),
                          ),
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
                      )
                    else
                      Text(
                        picked?.formatted ??
                            'Move the map to set location',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),

          // PIN / city chips
          if (!isLoading &&
              !isFailed &&
              picked?.pincode?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 54),
              child: Wrap(
                spacing: 8,
                children: [
                  _Chip(
                    icon: Icons.pin_drop_rounded,
                    label: 'PIN: ${picked!.pincode}',
                    isDark: isDark,
                  ),
                  if (picked?.city?.isNotEmpty == true)
                    _Chip(
                      icon: Icons.location_city_rounded,
                      label: picked!.city!,
                      isDark: isDark,
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Open in Maps
          if (_canConfirm && !isFailed)
            OutlinedButton.icon(
              onPressed: _openInMaps,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text(
                'Open in Google Maps',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                    color: AppColors.primary.withValues(alpha:0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 44),
              ),
            ),

          if (_canConfirm && !isFailed) const SizedBox(height: 10),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _canConfirm ? onConfirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha:0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    isFailed
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
                  ? Colors.white.withValues(alpha:_anim.value * 0.15)
                  : Colors.grey.withValues(alpha:_anim.value * 0.35),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 10,
            width: 140,
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.white.withValues(alpha:_anim.value * 0.1)
                  : Colors.grey.withValues(alpha:_anim.value * 0.25),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info chip ─────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _Chip(
      {required this.icon, required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha:0.06)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 12,
              color: isDark ? Colors.white70 : Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
