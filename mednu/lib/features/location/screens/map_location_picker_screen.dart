import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../home/providers/location_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/places_service.dart';
import '../../../core/utils/maps_launcher.dart';

class MapLocationPickerScreen extends ConsumerStatefulWidget {
  /// Initial coordinates to center the map on. If null, uses current location.
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
  GoogleMapController? _mapCtrl;
  bool _mapReady = false;

  // Reverse-geocoded address from current camera center
  PreciseAddress? _picked;
  bool _geocoding = false;

  // Exact camera center tracked via onCameraMove (more accurate than getVisibleRegion)
  LatLng? _center;

  Timer? _idleTimer;

  static const _defaultZoom = 16.5;

  @override
  void initState() {
    super.initState();
    // If no initial position provided, get device position
    if (widget.initialLat == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveToCurrentPos());
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────

  double get _initLat => widget.initialLat ?? 17.3850; // Hyderabad fallback
  double get _initLng => widget.initialLng ?? 78.4867;

  Future<void> _moveToCurrentPos() async {
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) return;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      if (!mounted) return;
      _mapCtrl?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(pos.latitude, pos.longitude),
            zoom: _defaultZoom,
          ),
        ),
      );
    } catch (_) {}
  }

  void _onCameraMove(CameraPosition pos) {
    // Track exact center from camera (more precise than getVisibleRegion)
    _center = pos.target;
    if (!_geocoding) setState(() => _geocoding = true);
  }

  void _onCameraIdle() {
    // Debounce reverse-geocoding to avoid excessive calls while user drags
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 600), _reverseGeocode);
  }

  Future<void> _reverseGeocode() async {
    final center = _center ?? LatLng(_initLat, _initLng);
    if (!mounted) return;
    try {
      // Use Google Geocoding API for precise Indian addresses
      final details = await placesService.reverseGeocode(
          center.latitude, center.longitude);
      if (!mounted) return;
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
        });
      } else {
        // Nothing resolved — clear loading so Confirm is not permanently blocked
        if (mounted) setState(() => _geocoding = false);
      }
    } catch (_) {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  void _confirm() {
    if (_picked == null) return;
    // Apply already-resolved address directly — no redundant geocoding round-trip
    ref.read(locationProvider.notifier).setPreciseAddress(_picked!);
    Navigator.pop(context, _picked);
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // ── Full-screen map ──────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(_initLat, _initLng),
              zoom: _defaultZoom,
            ),
            onMapCreated: (ctrl) {
              _mapCtrl = ctrl;
              setState(() => _mapReady = true);
              // Trigger geocode for initial position
              Future.delayed(const Duration(milliseconds: 600),
                  _reverseGeocode);
            },
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
          ),

          // ── Centre pin ──────────────────────────────────
          Center(
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
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                // Pin stem
                Container(
                  width: 2,
                  height: 14,
                  color: AppColors.primary,
                ),
                // Shadow dot
                Container(
                  width: 10,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),

          // ── Top bar ─────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _TopBarButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkCardElevated
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.map_outlined,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _geocoding
                                  ? 'Locating…'
                                  : _picked?.short ?? 'Move map to set location',
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
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Current location FAB ────────────────────────
          Positioned(
            right: 16,
            bottom: 210,
            child: _MapFab(
              icon: Icons.my_location_rounded,
              onTap: _moveToCurrentPos,
              tooltip: 'My Location',
            ),
          ),

          // ── Bottom sheet ─────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomConfirmSheet(
              picked: _picked,
              isLoading: _geocoding,
              isDark: isDark,
              onConfirm: _confirm,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Top bar icon button ────────────────────────────────────
class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopBarButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.darkCardElevated
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

// ── Floating map button ───────────────────────────────────
class _MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _MapFab(
      {required this.icon, required this.onTap, required this.tooltip});

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
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkCardElevated
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
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

// ── Bottom confirm sheet ──────────────────────────────────
class _BottomConfirmSheet extends StatelessWidget {
  final PreciseAddress? picked;
  final bool isLoading;
  final bool isDark;
  final VoidCallback onConfirm;

  const _BottomConfirmSheet({
    required this.picked,
    required this.isLoading,
    required this.isDark,
    required this.onConfirm,
  });

  void _openInMaps() {
    if (picked == null) return;
    MapsLauncher.openLocation(picked!.lat, picked!.lng,
        label: picked!.formatted);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardElevated : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).padding.bottom + 20),
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
                    ? Colors.white.withOpacity(0.15)
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
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
                    const SizedBox(height: 2),
                    if (isLoading)
                      _shimmerText(isDark)
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

          if (picked?.pincode?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 54),
              child: Row(
                children: [
                  _chip(
                      Icons.pin_drop_rounded,
                      'PIN: ${picked!.pincode}',
                      isDark),
                  if (picked?.city?.isNotEmpty == true) ...[
                    const SizedBox(width: 8),
                    _chip(Icons.location_city_rounded,
                        picked!.city!, isDark),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Open in Google Maps button
          if (picked != null && !isLoading)
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
                side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 44),
              ),
            ),

          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (isLoading || picked == null) ? null : onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
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
                  const Text(
                    'Confirm Location',
                    style: TextStyle(
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

  Widget _shimmerText(bool isDark) => Container(
        height: 16,
        width: 220,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
        ),
      );

  Widget _chip(IconData icon, String label, bool isDark) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 12,
                color: isDark
                    ? Colors.white70
                    : Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? Colors.white70
                    : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      );
}
