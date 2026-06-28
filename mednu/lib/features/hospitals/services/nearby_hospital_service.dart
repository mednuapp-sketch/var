import 'dart:math';
import 'package:dio/dio.dart';
import 'hospital_service.dart';

const _kApiKey = String.fromEnvironment(
  'MAPS_API_KEY',
  defaultValue: 'AIzaSyBTt8cnzrKMOxMJpAnFgTiZxJSaqxE3aj8',
);

class NearbyHospital {
  final String id;
  final String name;
  final String address;
  final String phone;
  final String mapsUrl;
  final bool isEmergency;
  final bool isMednu;
  final double? lat;
  final double? lng;
  final double? distanceKm;
  final double? rating;
  final int? userRatingsTotal;

  const NearbyHospital({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.mapsUrl,
    required this.isEmergency,
    required this.isMednu,
    this.lat,
    this.lng,
    this.distanceKm,
    this.rating,
    this.userRatingsTotal,
  });
}

class NearbyHospitalService {
  static const _nearbyUrl =
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Fetches raw hospital results from Google Places Nearby Search.
  /// Throws on network or server errors so callers can surface them.
  Future<List<Map<String, dynamic>>> fetchRawGoogle({
    required double userLat,
    required double userLng,
    int radiusMeters = 15000,
  }) async {
    final res = await _dio.get(_nearbyUrl, queryParameters: {
      'location': '$userLat,$userLng',
      'radius': radiusMeters,
      'type': 'hospital',
      'key': _kApiKey,
    });
    final status = res.data['status'] as String? ?? '';
    if (status != 'OK' && status != 'ZERO_RESULTS') return [];
    return (res.data['results'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  /// Merges raw Google Places results with MedNu Firestore hospitals.
  /// Google hospitals matched to a MedNu hospital get isMednu = true.
  /// MedNu hospitals not found in Google results are appended at the end.
  List<NearbyHospital> mergeResults({
    required double userLat,
    required double userLng,
    required List<Map<String, dynamic>> rawGooglePlaces,
    required List<Hospital> mednuHospitals,
  }) {
    final results = <NearbyHospital>[];
    final matchedMednuIds = <String>{};

    for (final place in rawGooglePlaces) {
      final name = place['name'] as String? ?? '';
      final matched = _matchMednu(name, mednuHospitals);
      if (matched != null) matchedMednuIds.add(matched.id);

      final geo = place['geometry']?['location'];
      final lat = (geo?['lat'] as num?)?.toDouble();
      final lng = (geo?['lng'] as num?)?.toDouble();
      final placeId = place['place_id'] as String? ?? '';

      results.add(NearbyHospital(
        id: placeId.isNotEmpty ? placeId : name,
        name: name,
        address: place['vicinity'] as String? ?? matched?.address ?? '',
        phone: matched?.phone ?? '',
        mapsUrl: placeId.isNotEmpty
            ? 'https://www.google.com/maps/place/?q=place_id:$placeId'
            : matched?.mapsUrl ?? '',
        isEmergency: matched?.isEmergency ?? false,
        isMednu: matched != null,
        lat: lat,
        lng: lng,
        distanceKm: (lat != null && lng != null)
            ? _haversine(userLat, userLng, lat, lng)
            : null,
        rating: (place['rating'] as num?)?.toDouble(),
        userRatingsTotal: place['user_ratings_total'] as int?,
      ));
    }

    // Append MedNu-only hospitals not found in Google results
    for (final h in mednuHospitals) {
      if (!matchedMednuIds.contains(h.id)) {
        results.add(NearbyHospital(
          id: h.id,
          name: h.name,
          address: h.address,
          phone: h.phone,
          mapsUrl: h.mapsUrl,
          isEmergency: h.isEmergency,
          isMednu: true,
        ));
      }
    }

    // Sort: distance asc, then MedNu before others, then undistanced
    results.sort((a, b) {
      if (a.distanceKm != null && b.distanceKm != null) {
        return a.distanceKm!.compareTo(b.distanceKm!);
      }
      if (a.distanceKm != null) return -1;
      if (b.distanceKm != null) return 1;
      if (a.isMednu && !b.isMednu) return -1;
      if (!a.isMednu && b.isMednu) return 1;
      return 0;
    });

    return results;
  }

  Hospital? _matchMednu(String placeName, List<Hospital> mednuHospitals) {
    final norm = _normalize(placeName);
    if (norm.isEmpty) return null;
    for (final h in mednuHospitals) {
      final hn = _normalize(h.name);
      if (hn.isEmpty) continue;
      if (norm == hn || norm.contains(hn) || hn.contains(norm)) return h;
    }
    return null;
  }

  String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(
          RegExp(
              r'\b(hospital|medical|centre|center|clinic|care|health|pvt|ltd|private|limited)\b'),
          '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _deg2rad(double deg) => deg * pi / 180;
}

final nearbyHospitalService = NearbyHospitalService();
