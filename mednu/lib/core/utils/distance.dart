import 'package:geolocator/geolocator.dart';

/// Straight-line distance between two coordinates, in kilometres.
double distanceKm(double lat1, double lng1, double lat2, double lng2) =>
    Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;

/// Matches the "nearby" radius already used by pharmacy/diagnostics/doctors.
const double nearbyRadiusKm = 15.0;
