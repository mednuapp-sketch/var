import 'package:dio/dio.dart';

// Shared with the mednu (patient) app's key — Google allows attaching
// multiple Android package+SHA-1 / iOS bundle-id identities to one API key,
// so this key must also have com.mednu.mednu_doctor (and this app's iOS
// bundle id) added to its allowed apps in Google Cloud Console; it will
// return REQUEST_DENIED for this app's calls until that's done.
// Injected via --dart-define=MAPS_API_KEY=... at build time.
const _kApiKey = String.fromEnvironment(
  'MAPS_API_KEY',
  defaultValue: 'AIzaSyBTt8cnzrKMOxMJpAnFgTiZxJSaqxE3aj8',
);

class PlacesSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final String fullText;

  const PlacesSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.fullText,
  });
}

class PlaceDetails {
  final double lat;
  final double lng;
  final String formattedAddress;
  final String? plotNo;
  final String? building;
  final String? street;
  final String? area;
  final String? city;
  final String? state;
  final String? pincode;

  const PlaceDetails({
    required this.lat,
    required this.lng,
    required this.formattedAddress,
    this.plotNo,
    this.building,
    this.street,
    this.area,
    this.city,
    this.state,
    this.pincode,
  });
}

/// Thin wrapper around the Google Places/Geocoding REST APIs — mirrors the
/// mednu (patient) app's `PlacesService` so both apps parse address
/// components the same way.
class PlacesService {
  static const _autocompleteUrl =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const _detailsUrl =
      'https://maps.googleapis.com/maps/api/place/details/json';

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  Future<List<PlacesSuggestion>> autocomplete(String input,
      {double? lat, double? lng}) async {
    if (input.trim().length < 2) return [];
    try {
      final params = <String, dynamic>{
        'input': input.trim(),
        'key': _kApiKey,
        'components': 'country:in',
        'language': 'en',
        'types': 'geocode|establishment',
      };
      if (lat != null && lng != null) {
        params['location'] = '$lat,$lng';
        params['radius'] = '50000';
      }
      final res = await _dio.get(_autocompleteUrl, queryParameters: params);
      if (res.data['status'] != 'OK' &&
          res.data['status'] != 'ZERO_RESULTS') {
        return [];
      }
      final predictions = res.data['predictions'] as List? ?? [];
      return predictions.map((p) {
        final structured =
            p['structured_formatting'] as Map<String, dynamic>? ?? {};
        return PlacesSuggestion(
          placeId: p['place_id'] as String? ?? '',
          mainText: structured['main_text'] as String? ?? '',
          secondaryText: structured['secondary_text'] as String? ?? '',
          fullText: p['description'] as String? ?? '',
        );
      }).where((s) => s.placeId.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<PlaceDetails?> details(String placeId) async {
    try {
      final res = await _dio.get(_detailsUrl, queryParameters: {
        'place_id': placeId,
        'key': _kApiKey,
        'fields': 'geometry,formatted_address,address_components,name',
        'language': 'en',
      });
      if (res.data['status'] != 'OK') return null;
      final result = res.data['result'] as Map<String, dynamic>? ?? {};
      final geo = result['geometry'] as Map? ?? {};
      final loc = geo['location'] as Map? ?? {};
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      final components = result['address_components'] as List? ?? [];
      String? plotNo, building, street, area, city, state, pincode;

      for (final comp in components) {
        final types = (comp['types'] as List).cast<String>();
        final long = comp['long_name'] as String? ?? '';
        if (long.isEmpty) continue;
        if (types.contains('subpremise') || types.contains('street_number')) plotNo ??= long;
        if (types.contains('premise')) building ??= long;
        if (types.contains('route')) street = long;
        if (types.contains('sublocality_level_1') ||
            types.contains('sublocality') ||
            types.contains('neighborhood')) {
          area ??= long;
        }
        if (types.contains('locality')) city = long;
        if (types.contains('administrative_area_level_1')) state = long;
        if (types.contains('postal_code')) pincode = long;
      }

      final formatted = result['formatted_address'] as String? ?? '';

      return PlaceDetails(
        lat: lat,
        lng: lng,
        formattedAddress: formatted,
        plotNo: plotNo?.isNotEmpty == true ? plotNo : null,
        building: building?.isNotEmpty == true ? building : null,
        street: street?.isNotEmpty == true ? street : null,
        area: area?.isNotEmpty == true ? area : null,
        city: city?.isNotEmpty == true ? city : null,
        state: state?.isNotEmpty == true ? state : null,
        pincode: pincode?.isNotEmpty == true ? pincode : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Reverse-geocode coordinates using Google Geocoding API.
  Future<PlaceDetails?> reverseGeocode(double lat, double lng) async {
    try {
      final res = await _dio.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '$lat,$lng',
          'key': _kApiKey,
          'language': 'en',
        },
      );
      if (res.data['status'] != 'OK') return null;
      final results = res.data['results'] as List? ?? [];
      if (results.isEmpty) return null;

      // Prefer the most precise result type
      Map<String, dynamic>? best;
      for (final r in results) {
        final types = (r['types'] as List? ?? []).cast<String>();
        if (types.any((t) =>
            t == 'street_address' || t == 'premise' || t == 'subpremise')) {
          best = r as Map<String, dynamic>;
          break;
        }
      }
      best ??= results.first as Map<String, dynamic>;

      final comps = best['address_components'] as List? ?? [];
      String? plotNo, building, street, area, city, state, pincode;

      for (final c in comps) {
        final types = (c['types'] as List).cast<String>();
        final name = c['long_name'] as String? ?? '';
        if (name.isEmpty) continue;
        if (types.contains('subpremise') || types.contains('street_number')) plotNo ??= name;
        if (types.contains('premise')) building ??= name;
        if (types.contains('route')) street = name;
        if (types.contains('sublocality_level_1') ||
            types.contains('sublocality') ||
            types.contains('neighborhood')) {
          area ??= name;
        }
        if (types.contains('locality')) city = name;
        if (types.contains('administrative_area_level_1')) state = name;
        if (types.contains('postal_code')) pincode = name;
      }

      return PlaceDetails(
        lat: lat,
        lng: lng,
        formattedAddress: best['formatted_address'] as String? ?? '',
        plotNo: plotNo,
        building: building,
        street: street,
        area: area,
        city: city,
        state: state,
        pincode: pincode,
      );
    } catch (_) {
      return null;
    }
  }
}

final placesService = PlacesService();
