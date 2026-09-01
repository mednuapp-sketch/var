import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/directions_service.dart';

/// Real-time map for a patient's own ambulance request: the assigned
/// ambulance's live position — streamed straight from
/// `ambulance_profiles/{ambulanceId}.location`, which is public-read while
/// that ambulance is `active` (see firestore.rules) — the patient's own
/// pickup point, and an actual driving route + ETA between them via the
/// Directions API. `ambulanceId` isn't trusted as fixed: it's re-read from
/// the live `service_requests` doc on every rebuild, since the
/// stale-assignment sweep (functions/index.js,
/// `reassignStaleAmbulanceAssignments`) can hand a request to a different
/// driver if the first one doesn't respond in time.
class AmbulanceLiveTrackingScreen extends StatefulWidget {
  final String requestId;
  const AmbulanceLiveTrackingScreen({super.key, required this.requestId});

  @override
  State<AmbulanceLiveTrackingScreen> createState() => _AmbulanceLiveTrackingScreenState();
}

class _AmbulanceLiveTrackingScreenState extends State<AmbulanceLiveTrackingScreen> {
  GoogleMapController? _mapCtrl;
  RouteInfo? _route;
  bool _fetchingRoute = false;
  DateTime? _lastRouteFetch;
  LatLng? _lastFetchedFrom;
  bool _cameraFitted = false;

  // Created once in initState rather than inline in build()'s `stream:`
  // param — `.snapshots()` returns a NEW Stream instance every call, so
  // building it inline makes StreamBuilder tear down and resubscribe (a
  // visible loading flicker) on every rebuild, including every rebuild THIS
  // widget causes itself via the `setState` calls in `_maybeRefreshRoute`/
  // route updates every ~20s during an active trip. `widget.requestId`
  // never changes for a given screen instance, so this only needs creating
  // once.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _requestStream =
      FirebaseFirestore.instance.collection('service_requests').doc(widget.requestId).snapshots();

  // The assigned ambulance CAN change (a stale-assignment reassignment), so
  // this one is cached keyed by ambulanceId rather than created once.
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _ambulanceStream;
  String? _ambulanceStreamId;

  Stream<DocumentSnapshot<Map<String, dynamic>>> _ambulanceStreamFor(String ambulanceId) {
    if (_ambulanceStreamId != ambulanceId) {
      _ambulanceStreamId = ambulanceId;
      _ambulanceStream =
          FirebaseFirestore.instance.collection('ambulance_profiles').doc(ambulanceId).snapshots();
    }
    return _ambulanceStream!;
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _maybeRefreshRoute(LatLng driverPos, LatLng pickupPos) async {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking', style: AppTextStyles.h4),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _requestStream,
        builder: (context, requestSnap) {
          final data = requestSnap.data?.data();
          if (data == null) {
            return const _CenteredMessage(
              icon: Icons.search_off_rounded,
              title: 'Request not found',
              message: 'This booking may have been removed.',
            );
          }

          final ambulanceId = data['assignedTo'] as String?;
          final locationData = data['serviceDetails']?['locationData'] as Map<String, dynamic>?;
          final pickupLat = (locationData?['lat'] as num?)?.toDouble();
          final pickupLng = (locationData?['lng'] as num?)?.toDouble();

          if (ambulanceId == null || pickupLat == null || pickupLng == null) {
            return const _CenteredMessage(
              icon: Icons.hourglass_top_rounded,
              title: 'Finding your ambulance…',
              message: 'This screen updates automatically the moment one is assigned.',
            );
          }

          final pickupPos = LatLng(pickupLat, pickupLng);

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _ambulanceStreamFor(ambulanceId),
            builder: (context, ambulanceSnap) {
              final ambulanceData = ambulanceSnap.data?.data();
              final loc = ambulanceData?['location'] as GeoPoint?;
              final speedKmh = ((ambulanceData?['speedKmh'] as num?) ?? 0).toDouble();
              final driverName = (ambulanceData?['driverName'] as String? ?? '').trim();
              final plateNumber = (ambulanceData?['plateNumber'] as String? ?? '').trim();

              if (loc == null) {
                return const _CenteredMessage(
                  icon: Icons.satellite_alt_outlined,
                  title: 'Connecting to your ambulance…',
                  message: 'Live position will appear here as soon as it comes online.',
                );
              }

              final driverPos = LatLng(loc.latitude, loc.longitude);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _maybeRefreshRoute(driverPos, pickupPos);
                _fitCamera(driverPos, pickupPos);
              });

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
                          markerId: const MarkerId('ambulance'),
                          position: driverPos,
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                          infoWindow: InfoWindow(title: driverName.isNotEmpty ? driverName : 'Ambulance'),
                        ),
                        Marker(
                          markerId: const MarkerId('pickup'),
                          position: pickupPos,
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                          infoWindow: const InfoWindow(title: 'Your location'),
                        ),
                      },
                      polylines: {
                        if (_route != null)
                          Polyline(
                            polylineId: const PolylineId('route'),
                            points: _route!.points,
                            color: AppColors.error,
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
                        _FloatingChip(
                          icon: Icons.timer_outlined,
                          label: '${_route?.durationMinutes ?? (data['etaMinutes'] as num?)?.toInt() ?? '—'} min away',
                        ),
                        if (_route != null) ...[
                          const SizedBox(width: 8),
                          _FloatingChip(icon: Icons.route_rounded, label: '${_route!.distanceKm.toStringAsFixed(1)} km'),
                        ],
                        if (speedKmh > 0) ...[
                          const SizedBox(width: 8),
                          _FloatingChip(icon: Icons.speed_rounded, label: '${speedKmh.round()} km/h'),
                        ],
                      ],
                    ),
                  ),
                  if (driverName.isNotEmpty || plateNumber.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                          boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 20, offset: Offset(0, -6))],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.local_shipping_rounded, color: AppColors.error),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (driverName.isNotEmpty) Text(driverName, style: AppTextStyles.labelLarge),
                                  if (plateNumber.isNotEmpty) Text(plateNumber, style: AppTextStyles.bodySmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
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
          Icon(icon, size: 16, color: AppColors.error),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.labelMedium),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _CenteredMessage({required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(title, style: AppTextStyles.labelLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
