import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Same key as PlacesService — see the comment there.
const _kApiKey = String.fromEnvironment(
  'MAPS_API_KEY',
  defaultValue: 'AIzaSyBTt8cnzrKMOxMJpAnFgTiZxJSaqxE3aj8',
);

class RouteInfo {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMinutes;

  const RouteInfo({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
  });
}

/// Thin wrapper around the Google Directions REST API — driving route +
/// live ETA between two points. Used by the ambulance live-tracking screens
/// (both apps) to replace a hardcoded ETA/speed with the real thing.
class DirectionsService {
  static const _url = 'https://maps.googleapis.com/maps/api/directions/json';
  static final _dio = Dio();

  /// Returns null on any failure (no route found, network error, API
  /// error) — callers keep showing their last-known route/ETA rather than
  /// clearing the map, since a single failed refresh on a live-tracking
  /// screen shouldn't blank out what the user was just looking at.
  static Future<RouteInfo?> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final res = await _dio.get(_url, queryParameters: {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': 'driving',
        'key': _kApiKey,
      });
      final data = res.data as Map<String, dynamic>;
      if (data['status'] != 'OK') return null;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;
      final legs = route['legs'] as List?;
      if (legs == null || legs.isEmpty) return null;
      final leg = legs.first as Map<String, dynamic>;

      final overviewPolyline = route['overview_polyline'] as Map<String, dynamic>?;
      final encoded = overviewPolyline?['points'] as String?;
      if (encoded == null) return null;

      return RouteInfo(
        points: _decodePolyline(encoded),
        distanceKm: ((leg['distance']?['value'] as num?) ?? 0) / 1000,
        durationMinutes: (((leg['duration']?['value'] as num?) ?? 0) / 60).round(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Standard Google encoded-polyline algorithm decoder — no extra package
  /// needed for this alone.
  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      var shift = 0, result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
