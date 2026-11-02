import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/directions_service.dart';
import '../../../core/utils/map_marker_icons.dart';
import '../models/ambulance_request.dart';
import '../services/ambulance_location_service.dart';
import '../services/ambulance_trip_tracker.dart';

/// Where this trip is heading right now: the patient's pickup point until the
/// driver has arrived, then the drop-off (a hospital name/address — only text
/// is stored for it, so it is resolved by the Directions API itself).
class TripDestination {
  final String label;
  final LatLng? latLng;
  final String? address;
  const TripDestination._(this.label, this.latLng, this.address);

  static TripDestination? of(AmbulanceRequest r) {
    if (r.status == AmbulanceRequestStatus.arrived) {
      final drop = r.dropAddress.trim();
      return drop.isEmpty ? null : TripDestination._('Drop-off', null, drop);
    }
    final lat = r.pickupLat, lng = r.pickupLng;
    if (lat != null && lng != null) return TripDestination._('Pickup', LatLng(lat, lng), null);
    final addr = r.pickupAddress.trim();
    return addr.isEmpty ? null : TripDestination._('Pickup', null, addr);
  }

  /// Google Maps "directions + start navigation" link for this destination.
  Uri get navigationUri => Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': latLng != null ? '${latLng!.latitude},${latLng!.longitude}' : address!,
        'travelmode': 'driving',
        'dir_action': 'navigate',
      });

  Future<bool> openNavigation() => launchUrl(navigationUri, mode: LaunchMode.externalApplication);
}

/// The driver's live map for an open trip: own position updating every GPS
/// fix (straight from [AmbulanceTripTracker], no Firestore round trip), the
/// driving route to the current destination, ETA and speed. Follows the
/// vehicle until the driver pans the map, then offers a Re-centre button.
class AmbulanceTripMap extends StatefulWidget {
  final AmbulanceRequest request;

  /// Extra map padding at the bottom so Google's logo / controls clear an
  /// overlaid sheet.
  final double bottomPadding;

  const AmbulanceTripMap({super.key, required this.request, this.bottomPadding = 0});

  @override
  State<AmbulanceTripMap> createState() => _AmbulanceTripMapState();
}

class _AmbulanceTripMapState extends State<AmbulanceTripMap> {
  GoogleMapController? _ctrl;
  StreamSubscription<Position>? _sub;
  BitmapDescriptor? _icon;

  LatLng? _pos;
  double _heading = 0;
  double _speedKmh = 0;

  RouteInfo? _route;
  String? _routeFor; // destination signature the current _route belongs to
  LatLng? _routeOrigin;
  DateTime? _routeAt;
  bool _fetching = false;

  bool _following = true;

  @override
  void initState() {
    super.initState();
    MapMarkerIcons.ambulance(color: widget.request.type.color).then((i) {
      if (mounted) setState(() => _icon = i);
    });

    final latest = AmbulanceTripTracker.latest;
    if (latest != null) _apply(latest);
    _sub = AmbulanceTripTracker.positions.listen(_apply);
    if (latest == null) {
      // First frame before the tracker has a fix: show a one-shot position so
      // the map isn't blank.
      AmbulanceLocationService.getCurrentPosition().then((p) {
        if (p != null && mounted && _pos == null) _apply(p);
      });
    }
  }

  @override
  void didUpdateWidget(AmbulanceTripMap old) {
    super.didUpdateWidget(old);
    // Status moved (e.g. arrived → now heading to the drop-off).
    if (old.request.status != widget.request.status && _pos != null) _maybeRefreshRoute(force: true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  void _apply(Position p) {
    if (!mounted) return;
    final next = LatLng(p.latitude, p.longitude);
    // Heading is only meaningful while moving; at a standstill keep the last.
    var heading = _heading;
    if (p.heading.isFinite && p.heading >= 0 && p.speed > 1) {
      heading = p.heading;
    } else if (_pos != null && Geolocator.distanceBetween(_pos!.latitude, _pos!.longitude, next.latitude, next.longitude) > 8) {
      heading = MapMarkerIcons.bearing(_pos!, next);
    }
    setState(() {
      _pos = next;
      _heading = heading;
      _speedKmh = p.speed > 0 ? p.speed * 3.6 : 0;
    });
    if (_following) {
      _ctrl?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: next, zoom: 16, bearing: 0)));
    }
    _maybeRefreshRoute();
  }

  Future<void> _maybeRefreshRoute({bool force = false}) async {
    final dest = TripDestination.of(widget.request);
    final origin = _pos;
    if (dest == null || origin == null || _fetching) return;

    final sig = dest.latLng != null ? '${dest.latLng!.latitude},${dest.latLng!.longitude}' : dest.address!;
    final destinationChanged = sig != _routeFor;
    if (!force && !destinationChanged && _routeOrigin != null && _routeAt != null) {
      final moved = Geolocator.distanceBetween(_routeOrigin!.latitude, _routeOrigin!.longitude, origin.latitude, origin.longitude);
      final age = DateTime.now().difference(_routeAt!);
      // Re-route when the vehicle has really moved, but never more than once
      // every 15 s — Directions calls are billed.
      if (moved < 60 || age < const Duration(seconds: 15)) return;
    }

    _fetching = true;
    final route = await DirectionsService.getRoute(
      origin: origin,
      destination: dest.latLng,
      destinationAddress: dest.address,
    );
    _fetching = false;
    _routeOrigin = origin;
    _routeAt = DateTime.now();
    if (!mounted) return;
    // A failed refresh keeps the last route on screen rather than blanking it.
    setState(() {
      _routeFor = sig;
      if (route != null) _route = route;
    });
  }

  void _recenter() {
    setState(() => _following = true);
    final p = _pos;
    if (p != null) _ctrl?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: p, zoom: 16)));
  }

  @override
  Widget build(BuildContext context) {
    final pos = _pos;
    if (pos == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.satellite_alt_outlined, size: 48, color: AppColors.textHint),
              SizedBox(height: 12),
              Text('Waiting for GPS fix', style: AppTextStyles.labelLarge),
              SizedBox(height: 6),
              Text('Make sure device location is on and permission is granted.',
                  style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    final dest = TripDestination.of(widget.request);
    final destPoint = dest?.latLng ?? ((_route?.points.isNotEmpty ?? false) ? _route!.points.last : null);
    final eta = _route?.durationMinutes ?? widget.request.etaMinutes;

    return Stack(
      children: [
        Positioned.fill(
          // Any touch on the map means the driver wants to look around.
          child: Listener(
            onPointerDown: (_) {
              if (_following) setState(() => _following = false);
            },
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: pos, zoom: 16),
              onMapCreated: (c) => _ctrl = c,
              padding: EdgeInsets.only(bottom: widget.bottomPadding),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              markers: {
                Marker(
                  markerId: const MarkerId('driver'),
                  position: pos,
                  icon: _icon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                  rotation: _icon != null ? _heading : 0,
                  flat: true,
                  anchor: const Offset(0.5, 0.5),
                  zIndexInt: 2,
                  infoWindow: const InfoWindow(title: 'You'),
                ),
                if (destPoint != null)
                  Marker(
                    markerId: const MarkerId('destination'),
                    position: destPoint,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        dest?.label == 'Drop-off' ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed),
                    infoWindow: InfoWindow(title: dest?.label ?? 'Destination'),
                  ),
              },
              polylines: {
                if (_route != null)
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: _route!.points,
                    color: widget.request.type.color,
                    width: 6,
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
              _Chip(icon: Icons.flag_rounded, label: dest?.label ?? 'No destination'),
              _Chip(icon: Icons.timer_outlined, label: '$eta min'),
              if (_route != null) _Chip(icon: Icons.route_rounded, label: '${_route!.distanceKm.toStringAsFixed(1)} km'),
              _Chip(icon: Icons.speed_rounded, label: '${_speedKmh.round()} km/h'),
            ],
          ),
        ),
        if (!_following)
          Positioned(
            right: 12,
            bottom: 12 + widget.bottomPadding,
            child: FloatingActionButton.small(
              heroTag: 'ambulance-recenter',
              onPressed: _recenter,
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location_rounded, color: AppColors.primary),
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
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
