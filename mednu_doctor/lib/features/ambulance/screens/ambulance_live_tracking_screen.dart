import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/directions_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/ambulance_request.dart';
import '../providers/ambulance_providers.dart';
import '../services/ambulance_profile_service.dart';

/// Real Google Map — this driver's own live position (streamed from
/// `ambulance_profiles/{uid}.location`, written by AmbulanceLocationService
/// while online) plus the patient's pickup point, connected by an actual
/// driving route from the Directions API. Distinct, immersive layout on
/// purpose: this is the one screen in the module that should NOT look like
/// a list of cards.
class AmbulanceLiveTrackingScreen extends ConsumerStatefulWidget {
  const AmbulanceLiveTrackingScreen({super.key});

  @override
  ConsumerState<AmbulanceLiveTrackingScreen> createState() => _AmbulanceLiveTrackingScreenState();
}

class _AmbulanceLiveTrackingScreenState extends ConsumerState<AmbulanceLiveTrackingScreen> {
  GoogleMapController? _mapCtrl;
  RouteInfo? _route;
  bool _fetchingRoute = false;
  DateTime? _lastRouteFetch;
  LatLng? _lastFetchedFrom;
  bool _cameraFitted = false;

  // Created once and reused across every build — calling `.snapshots()`
  // directly inside `build()` returns a NEW Stream instance each time,
  // which makes StreamBuilder tear down and resubscribe (a visible
  // momentary loading flicker) every time this widget rebuilds for any
  // unrelated reason (e.g. `activeRequestProvider` changing upstream), not
  // just when the profile doc itself actually changes.
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _profileStream;
  String? _profileStreamUid;

  Stream<DocumentSnapshot<Map<String, dynamic>>> _streamFor(String uid) {
    if (_profileStreamUid != uid) {
      _profileStreamUid = uid;
      _profileStream = AmbulanceProfileService.profileStream(uid);
    }
    return _profileStream!;
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _maybeRefreshRoute(LatLng driverPos, LatLng pickupPos) async {
    // AmbulanceLocationService already throttles writes to >=30s apart, so a
    // new Firestore snapshot already implies real movement — this debounce
    // is just a backstop against a burst of rebuilds triggering duplicate
    // Directions calls for the same position.
    final now = DateTime.now();
    if (_fetchingRoute) return;
    if (_lastFetchedFrom == driverPos) return;
    if (_lastRouteFetch != null && now.difference(_lastRouteFetch!) < const Duration(seconds: 20)) return;

    _fetchingRoute = true;
    _lastFetchedFrom = driverPos;
    _lastRouteFetch = now;
    final route = await DirectionsService.getRoute(origin: driverPos, destination: pickupPos);
    _fetchingRoute = false;
    if (mounted && route != null) setState(() => _route = route);
  }

  void _fitCamera(LatLng driverPos, LatLng pickupPos) {
    if (_cameraFitted || _mapCtrl == null) return;
    _cameraFitted = true;
    final bounds = LatLngBounds(
      southwest: LatLng(
        driverPos.latitude < pickupPos.latitude ? driverPos.latitude : pickupPos.latitude,
        driverPos.longitude < pickupPos.longitude ? driverPos.longitude : pickupPos.longitude,
      ),
      northeast: LatLng(
        driverPos.latitude > pickupPos.latitude ? driverPos.latitude : pickupPos.latitude,
        driverPos.longitude > pickupPos.longitude ? driverPos.longitude : pickupPos.longitude,
      ),
    );
    _mapCtrl!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeRequestProvider);
    final uid = AmbulanceProfileService.currentUid;

    if (active == null || uid == null) {
      return const SharedAppShell(
        currentRoute: AppRoutes.ambulanceLiveTracking,
        title: 'Live Tracking',
        body: AppEmptyState(
          icon: Icons.map_outlined,
          title: 'No active trip',
          message: 'Accept a request to start live tracking.',
        ),
      );
    }

    return SharedAppShell(
      currentRoute: AppRoutes.ambulanceLiveTracking,
      title: 'Live Tracking',
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _streamFor(uid),
        builder: (context, snap) {
          final loc = snap.data?.data()?['location'] as GeoPoint?;
          final speedKmh = ((snap.data?.data()?['speedKmh'] as num?) ?? 0).toDouble();
          final pickupLat = active.pickupLat;
          final pickupLng = active.pickupLng;

          if (loc == null || pickupLat == null || pickupLng == null) {
            return const AppEmptyState(
              icon: Icons.satellite_alt_outlined,
              title: 'Waiting for GPS fix',
              message: 'Make sure you\'re Online on the dashboard so your live position can be shown.',
            );
          }

          final driverPos = LatLng(loc.latitude, loc.longitude);
          final pickupPos = LatLng(pickupLat, pickupLng);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _maybeRefreshRoute(driverPos, pickupPos);
            _fitCamera(driverPos, pickupPos);
          });

          final etaMinutes = _route?.durationMinutes ?? active.etaMinutes;

          return Stack(
            children: [
              Positioned.fill(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(target: driverPos, zoom: 14),
                  onMapCreated: (c) => _mapCtrl = c,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: false,
                  mapToolbarEnabled: false,
                  markers: {
                    Marker(
                      markerId: const MarkerId('driver'),
                      position: driverPos,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                      infoWindow: const InfoWindow(title: 'You'),
                    ),
                    Marker(
                      markerId: const MarkerId('pickup'),
                      position: pickupPos,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                      infoWindow: InfoWindow(title: active.patientName),
                    ),
                  },
                  polylines: {
                    if (_route != null)
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: _route!.points,
                        color: active.type.color,
                        width: 5,
                      ),
                  },
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    _FloatingChip(icon: Icons.speed_rounded, label: '${speedKmh.round()} km/h'),
                    const SizedBox(width: 8),
                    _FloatingChip(icon: Icons.timer_outlined, label: '$etaMinutes min ETA'),
                    if (_route != null) ...[
                      const SizedBox(width: 8),
                      _FloatingChip(icon: Icons.route_rounded, label: '${_route!.distanceKm.toStringAsFixed(1)} km'),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _TrackingSheet(requestId: active.id),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FloatingChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FloatingChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.labelMedium),
        ],
      ),
    );
  }
}

class _TrackingSheet extends ConsumerWidget {
  final String requestId;
  const _TrackingSheet({required this.requestId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(requestByIdProvider(requestId));
    if (request == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 20, offset: Offset(0, -6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          Row(
            children: [
              SharedProfileAvatar(name: request.patientName, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.patientName, style: AppTextStyles.labelLarge),
                    Text(request.dropAddress, style: AppTextStyles.bodySmall, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              StatusBadge(label: request.status.label, color: request.status.color),
            ],
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: 'Open Turn-by-Turn Navigation',
            icon: Icons.navigation_rounded,
            onTap: () => context.push(AppRoutes.ambulanceNavigation, extra: {'requestId': request.id}),
          ),
        ],
      ),
    );
  }
}
