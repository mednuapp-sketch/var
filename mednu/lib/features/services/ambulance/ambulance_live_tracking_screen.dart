import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/directions_service.dart';
import '../../../core/utils/map_marker_icons.dart';

/// Uber-style live map for a patient's own ambulance request.
///
/// The position comes from `ambulance_live/{requestId}`: the driver's phone
/// writes a fresh GPS fix there every few seconds for the length of the trip
/// (firestore.rules: readable only by this patient and that driver). Between
/// fixes the marker is glided to the new spot and turned to the vehicle's
/// heading, so it moves continuously instead of jumping. The camera follows
/// the ambulance until the patient pans the map.
///
/// `ambulance_profiles/{ambulanceId}` is still streamed, but only for the
/// driver's name / plate / phone — and as a coarse position fallback while a
/// driver on an older app version (which doesn't publish the live feed) is
/// assigned. `ambulanceId` isn't trusted as fixed: it's re-read from the live
/// `service_requests` doc, since the stale-assignment sweep can hand a request
/// to a different driver.
class AmbulanceLiveTrackingScreen extends StatefulWidget {
  final String requestId;
  const AmbulanceLiveTrackingScreen({super.key, required this.requestId});

  @override
  State<AmbulanceLiveTrackingScreen> createState() => _AmbulanceLiveTrackingScreenState();
}

class _AmbulanceLiveTrackingScreenState extends State<AmbulanceLiveTrackingScreen>
    with SingleTickerProviderStateMixin {
  // A fix older than this is shown as "weak signal" rather than as live.
  static const _staleAfter = Duration(seconds: 25);

  GoogleMapController? _mapCtrl;
  BitmapDescriptor? _icon;

  // ── Marker animation ──
  // Repaints are capped at ~15 fps: pushing a new marker position to the
  // native map every display frame is wasted work for something this slow.
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))
        ..addListener(() {
          final now = DateTime.now();
          if (now.difference(_lastTick).inMilliseconds >= 66 || _anim.isCompleted) {
            _lastTick = now;
            if (mounted) setState(() {});
          }
        });
  LatLng? _from;
  LatLng? _to;
  double _fromHeading = 0;
  double _toHeading = 0;
  GeoPoint? _lastFix; // identity of the fix currently animated towards

  // ── Route to the pickup point ──
  RouteInfo? _route;
  bool _fetchingRoute = false;
  DateTime? _lastRouteFetch;
  LatLng? _lastRouteFrom;

  bool _following = true;
  Timer? _staleTicker;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _requestStream =
      FirebaseFirestore.instance.collection('service_requests').doc(widget.requestId).snapshots();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _liveStream =
      FirebaseFirestore.instance.collection('ambulance_live').doc(widget.requestId).snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _ambulanceStream;
  String? _ambulanceStreamId;

  Stream<DocumentSnapshot<Map<String, dynamic>>> _ambulanceStreamFor(String id) {
    if (_ambulanceStreamId != id) {
      _ambulanceStreamId = id;
      _ambulanceStream = FirebaseFirestore.instance.collection('ambulance_profiles').doc(id).snapshots();
    }
    return _ambulanceStream!;
  }

  @override
  void initState() {
    super.initState();
    MapMarkerIcons.ambulance().then((i) {
      if (mounted) setState(() => _icon = i);
    });
    // Re-evaluates "last seen Xs ago" without needing a new Firestore event.
    _staleTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _staleTicker?.cancel();
    _anim.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ── Animation helpers ────────────────────────────────────────────────────

  LatLng? get _currentPos {
    final to = _to;
    if (to == null) return null;
    final from = _from ?? to;
    final t = Curves.linear.transform(_anim.value);
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  double get _currentHeading {
    // Shortest way round the compass, so 350° → 10° doesn't spin the long way.
    var delta = ((_toHeading - _fromHeading + 540) % 360) - 180;
    if (delta.isNaN) delta = 0;
    return (_fromHeading + delta * _anim.value + 360) % 360;
  }

  /// Called with every new fix. Glides from wherever the marker is *now* to
  /// the new point, so back-to-back fixes never snap.
  void _onFix(GeoPoint fix, double heading) {
    if (_lastFix != null && _lastFix!.latitude == fix.latitude && _lastFix!.longitude == fix.longitude) return;
    final next = LatLng(fix.latitude, fix.longitude);
    final now = _currentPos;

    if (_to == null) {
      _from = next;
      _to = next;
      _fromHeading = heading;
      _toHeading = heading;
      _anim.value = 1;
    } else {
      _fromHeading = _currentHeading;
      _from = now;
      _to = next;
      // -1 means "device couldn't tell" — keep facing the way it was, or fall
      // back to the direction of travel.
      if (heading >= 0) {
        _toHeading = heading;
      } else if (now != null && (now.latitude != next.latitude || now.longitude != next.longitude)) {
        _toHeading = MapMarkerIcons.bearing(now, next);
      } else {
        _toHeading = _fromHeading;
      }
      _anim.forward(from: 0);
    }
    _lastFix = fix;

    if (_following) {
      _mapCtrl?.animateCamera(CameraUpdate.newLatLng(next));
    }
  }

  // ── Route to pickup ──────────────────────────────────────────────────────

  Future<void> _maybeRefreshRoute(LatLng driverPos, LatLng pickupPos) async {
    if (_fetchingRoute) return;
    final now = DateTime.now();
    if (_lastRouteFetch != null && now.difference(_lastRouteFetch!) < const Duration(seconds: 20)) return;
    if (_lastRouteFrom != null) {
      final moved = _approxMeters(_lastRouteFrom!, driverPos);
      if (moved < 40) return;
    }
    _fetchingRoute = true;
    _lastRouteFetch = now;
    _lastRouteFrom = driverPos;
    final route = await DirectionsService.getRoute(origin: driverPos, destination: pickupPos);
    _fetchingRoute = false;
    if (mounted && route != null) setState(() => _route = route);
  }

  static double _approxMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180 * math.cos(a.latitude * math.pi / 180);
    return math.sqrt(dLat * dLat + dLng * dLng) * r;
  }

  void _fitCameraOnce(LatLng driverPos, LatLng pickupPos) {
    if (_fitted || _mapCtrl == null) return;
    _fitted = true;
    final bounds = LatLngBounds(
      southwest: LatLng(math.min(driverPos.latitude, pickupPos.latitude), math.min(driverPos.longitude, pickupPos.longitude)),
      northeast: LatLng(math.max(driverPos.latitude, pickupPos.latitude), math.max(driverPos.longitude, pickupPos.longitude)),
    );
    _mapCtrl!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 90));
  }

  bool _fitted = false;

  void _recenter() {
    setState(() => _following = true);
    final p = _currentPos;
    if (p != null) _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(p, 16));
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    await launchUrl(Uri.parse('tel:$phone'));
  }

  // ── Build ────────────────────────────────────────────────────────────────

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

          final status = (data['status'] as String?) ?? 'pending';
          final ambulanceId = data['assignedTo'] as String?;
          final locationData = data['serviceDetails']?['locationData'] as Map<String, dynamic>?;
          final pickupLat = (locationData?['lat'] as num?)?.toDouble();
          final pickupLng = (locationData?['lng'] as num?)?.toDouble();

          if (status == 'cancelled' || status == 'rejected') {
            return const _CenteredMessage(
              icon: Icons.cancel_outlined,
              title: 'Request cancelled',
              message: 'This ambulance request is no longer active.',
            );
          }
          if (status == 'completed') {
            return const _CenteredMessage(
              icon: Icons.task_alt_rounded,
              title: 'Trip completed',
              message: 'Your ambulance trip has ended. Stay safe!',
            );
          }
          if (ambulanceId == null) {
            return const _CenteredMessage(
              icon: Icons.hourglass_top_rounded,
              title: 'Finding your ambulance…',
              message: 'This screen updates automatically the moment one is assigned.',
            );
          }

          final pickupPos = (pickupLat != null && pickupLng != null) ? LatLng(pickupLat, pickupLng) : null;

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _ambulanceStreamFor(ambulanceId),
            builder: (context, ambulanceSnap) {
              final profile = ambulanceSnap.data?.data();
              final driverName = (profile?['driverName'] as String? ?? '').trim();
              final plateNumber = (profile?['plateNumber'] as String? ?? '').trim();
              final driverPhone = (profile?['driverPhone'] as String? ?? '').trim();

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _liveStream,
                builder: (context, liveSnap) {
                  final live = liveSnap.data?.data();
                  var fix = live?['location'] as GeoPoint?;
                  var heading = ((live?['heading'] as num?) ?? -1).toDouble();
                  var speedKmh = ((live?['speedKmh'] as num?) ?? 0).toDouble();
                  final updatedAt = (live?['updatedAt'] as Timestamp?)?.toDate();
                  final isLiveFeed = fix != null;

                  // Driver on an older app build: no live feed, fall back to the
                  // coarse profile position (updates every ~30 s).
                  if (fix == null) {
                    fix = profile?['location'] as GeoPoint?;
                    heading = -1;
                    speedKmh = ((profile?['speedKmh'] as num?) ?? 0).toDouble();
                  }

                  if (fix == null) {
                    return const _CenteredMessage(
                      icon: Icons.satellite_alt_outlined,
                      title: 'Connecting to your ambulance…',
                      message: 'Live position will appear here as soon as the driver starts the trip.',
                    );
                  }

                  // Feed the animation outside of build's synchronous pass.
                  final f = fix;
                  final h = heading;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _onFix(f, h);
                    final pos = _currentPos;
                    if (pos != null && pickupPos != null && status != 'arrived') {
                      _maybeRefreshRoute(pos, pickupPos);
                      _fitCameraOnce(pos, pickupPos);
                    }
                  });

                  final pos = _currentPos ?? LatLng(fix.latitude, fix.longitude);
                  final arrived = status == 'arrived';
                  final ageSeconds = (isLiveFeed && updatedAt != null) ? DateTime.now().difference(updatedAt).inSeconds : null;
                  final stale = ageSeconds != null && ageSeconds > _staleAfter.inSeconds;

                  final headline = switch (status) {
                    'arrived' => 'Your ambulance has arrived',
                    'in_progress' => 'Ambulance is on the way',
                    _ => 'Ambulance assigned — getting ready to leave',
                  };

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Listener(
                          onPointerDown: (_) {
                            if (_following) setState(() => _following = false);
                          },
                          child: GoogleMap(
                            initialCameraPosition: CameraPosition(target: pos, zoom: 15),
                            onMapCreated: (c) => _mapCtrl = c,
                            padding: const EdgeInsets.only(bottom: 150),
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            compassEnabled: false,
                            mapToolbarEnabled: false,
                            markers: {
                              Marker(
                                markerId: const MarkerId('ambulance'),
                                position: pos,
                                icon: _icon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                                rotation: _icon != null ? _currentHeading : 0,
                                flat: true,
                                anchor: const Offset(0.5, 0.5),
                                zIndexInt: 2,
                                infoWindow: InfoWindow(title: driverName.isNotEmpty ? driverName : 'Ambulance'),
                              ),
                              if (pickupPos != null)
                                Marker(
                                  markerId: const MarkerId('pickup'),
                                  position: pickupPos,
                                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                                  infoWindow: const InfoWindow(title: 'Your location'),
                                ),
                            },
                            polylines: {
                              if (_route != null && !arrived)
                                Polyline(
                                  polylineId: const PolylineId('route'),
                                  points: _route!.points,
                                  color: AppColors.error,
                                  width: 5,
                                ),
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (!arrived)
                              _FloatingChip(
                                icon: Icons.timer_outlined,
                                label: '${_route?.durationMinutes ?? (data['etaMinutes'] as num?)?.toInt() ?? '—'} min away',
                              ),
                            if (_route != null && !arrived)
                              _FloatingChip(icon: Icons.route_rounded, label: '${_route!.distanceKm.toStringAsFixed(1)} km'),
                            if (speedKmh >= 1) _FloatingChip(icon: Icons.speed_rounded, label: '${speedKmh.round()} km/h'),
                            if (stale)
                              _FloatingChip(
                                icon: Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
                                label: 'Weak signal · seen ${ageSeconds}s ago',
                                color: const Color(0xFFE65100),
                              ),
                          ],
                        ),
                      ),
                      if (!_following)
                        Positioned(
                          right: 12,
                          bottom: 170,
                          child: FloatingActionButton.small(
                            heroTag: 'patient-recenter',
                            onPressed: _recenter,
                            backgroundColor: Colors.white,
                            child: const Icon(Icons.my_location_rounded, color: AppColors.primary),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                            boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 20, offset: Offset(0, -6))],
                          ),
                          child: SafeArea(
                            top: false,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(headline, style: AppTextStyles.h4),
                                const SizedBox(height: 12),
                                Row(
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
                                          Text(driverName.isNotEmpty ? driverName : 'Your driver', style: AppTextStyles.labelLarge),
                                          if (plateNumber.isNotEmpty) Text(plateNumber, style: AppTextStyles.bodySmall),
                                        ],
                                      ),
                                    ),
                                    if (driverPhone.isNotEmpty)
                                      IconButton.filled(
                                        tooltip: 'Call driver',
                                        onPressed: () => _call(driverPhone),
                                        icon: const Icon(Icons.call_rounded),
                                        style: IconButton.styleFrom(backgroundColor: AppColors.success),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
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
  final Color color;
  const _FloatingChip({required this.icon, required this.label, this.color = AppColors.error});

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
          Icon(icon, size: 16, color: color),
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
