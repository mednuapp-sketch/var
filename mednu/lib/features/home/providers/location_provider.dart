import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/places_service.dart';

class LocationSuggestion {
  final String displayName;
  final String shortName;
  final double lat;
  final double lng;

  const LocationSuggestion({
    required this.displayName,
    required this.shortName,
    required this.lat,
    required this.lng,
  });
}

// Full precise address components extracted from Placemark
class PreciseAddress {
  final String? plotNo;    // subThoroughfare — house/plot number
  final String? building;  // name — building / POI name
  final String? street;    // thoroughfare — street name
  final String? area;      // subLocality — neighbourhood
  final String? city;      // locality — city
  final String? state;     // administrativeArea
  final String? pincode;   // postalCode
  final double lat;
  final double lng;

  const PreciseAddress({
    this.plotNo,
    this.building,
    this.street,
    this.area,
    this.city,
    this.state,
    this.pincode,
    required this.lat,
    required this.lng,
  });

  // Full formatted address like delivery apps
  String get formatted {
    final parts = <String>[];
    if (plotNo?.isNotEmpty == true) parts.add(plotNo!);
    if (building?.isNotEmpty == true && building != street) parts.add(building!);
    if (street?.isNotEmpty == true) parts.add(street!);
    if (area?.isNotEmpty == true) parts.add(area!);
    if (city?.isNotEmpty == true) parts.add(city!);
    if (pincode?.isNotEmpty == true) parts.add(pincode!);
    return parts.isEmpty ? (city ?? 'Current Location') : parts.join(', ');
  }

  // Short label for app bar display
  String get short =>
      area?.isNotEmpty == true
          ? area!
          : city?.isNotEmpty == true
              ? city!
              : 'Current Location';

  Map<String, dynamic> toBookingMap() => {
        'plotNo': plotNo ?? '',
        'building': building ?? '',
        'street': street ?? '',
        'area': area ?? '',
        'city': city ?? '',
        'state': state ?? '',
        'pincode': pincode ?? '',
        'lat': lat,
        'lng': lng,
        'formattedAddress': formatted,
      };
}

enum LocationStatus { idle, detecting, error, set }

class LocationState {
  final String displayName;
  final String fullAddress;
  final double? lat;
  final double? lng;
  final bool isLoading;
  final bool isDetecting;
  final LocationStatus status;
  final List<LocationSuggestion> recentLocations;
  final PreciseAddress? preciseAddress; // detailed components
  /// Epoch ms when coordinates were last confirmed from GPS (0 = unknown)
  final int lastFixMs;

  const LocationState({
    required this.displayName,
    this.fullAddress = '',
    this.lat,
    this.lng,
    this.isLoading = false,
    this.isDetecting = false,
    this.status = LocationStatus.idle,
    this.recentLocations = const [],
    this.preciseAddress,
    this.lastFixMs = 0,
  });

  bool get hasCoordinates => lat != null && lng != null;

  /// Human-readable "updated X min ago" label; empty when unknown.
  String get fixAgeLabel {
    if (lastFixMs == 0) return '';
    final mins =
        (DateTime.now().millisecondsSinceEpoch - lastFixMs) ~/ 60000;
    if (mins < 1) return 'just now';
    if (mins == 1) return '1 min ago';
    if (mins < 60) return '$mins min ago';
    final hrs = mins ~/ 60;
    return hrs == 1 ? '1 hr ago' : '$hrs hrs ago';
  }

  LocationState copyWith({
    String? displayName,
    String? fullAddress,
    double? lat,
    double? lng,
    bool? isLoading,
    bool? isDetecting,
    LocationStatus? status,
    List<LocationSuggestion>? recentLocations,
    PreciseAddress? preciseAddress,
    int? lastFixMs,
  }) =>
      LocationState(
        displayName: displayName ?? this.displayName,
        fullAddress: fullAddress ?? this.fullAddress,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        isLoading: isLoading ?? this.isLoading,
        isDetecting: isDetecting ?? this.isDetecting,
        status: status ?? this.status,
        recentLocations: recentLocations ?? this.recentLocations,
        preciseAddress: preciseAddress ?? this.preciseAddress,
        lastFixMs: lastFixMs ?? this.lastFixMs,
      );
}

class LocationNotifier extends StateNotifier<LocationState> {
  LocationNotifier()
      : super(const LocationState(
          displayName: 'Detecting…',
          isLoading: true,
          isDetecting: true,
          status: LocationStatus.detecting,
        )) {
    _initLocation();
  }

  static const _kDisplayName = 'loc_display_name';
  static const _kFullAddress = 'loc_full_address';
  static const _kLat = 'loc_lat';
  static const _kLng = 'loc_lng';
  static const _kRecent = 'loc_recent';
  static const _kTimestamp = 'loc_timestamp';

  // Cached location older than this will be silently refreshed in background.
  static const _kSoftStaleMs = 5 * 60 * 1000; // 5 min → background refresh
  // Cached location older than this will be discarded and re-detected visibly.
  static const _kHardStaleMs = 30 * 60 * 1000; // 30 min → foreground refresh

  StreamSubscription<Position>? _positionSub;

  Future<void> _initLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kDisplayName);
    final savedTs = prefs.getInt(_kTimestamp) ?? 0;
    final ageMs =
        DateTime.now().millisecondsSinceEpoch - savedTs;
    final recent = _loadRecent(prefs);

    if (saved != null) {
      final lat = prefs.getDouble(_kLat);
      final lng = prefs.getDouble(_kLng);

      if (ageMs >= _kHardStaleMs) {
        // Hard stale: show cached address but immediately trigger foreground re-detect
        state = LocationState(
          displayName: saved,
          fullAddress: prefs.getString(_kFullAddress) ?? saved,
          lat: lat,
          lng: lng,
          isLoading: true,
          isDetecting: true,
          status: LocationStatus.detecting,
          recentLocations: recent,
        );
        await fetchCurrent();
      } else {
        // Fresh or soft-stale: use cached immediately
        state = LocationState(
          displayName: saved,
          fullAddress: prefs.getString(_kFullAddress) ?? saved,
          lat: lat,
          lng: lng,
          isLoading: false,
          status: LocationStatus.set,
          recentLocations: recent,
        );
        if (ageMs >= _kSoftStaleMs) {
          // Soft stale: silently refresh in background without blocking the UI
          _backgroundRefresh();
        }
      }
    } else {
      state = state.copyWith(recentLocations: recent);
      await fetchCurrent();
    }
  }

  /// Apply a [PlaceDetails] response directly to state.
  void _applyDetails(PlaceDetails d, {required bool persist}) {
    final precise = PreciseAddress(
      plotNo: d.plotNo,
      building: d.building,
      street: d.street,
      area: d.area,
      city: d.city,
      state: d.state,
      pincode: d.pincode,
      lat: d.lat,
      lng: d.lng,
    );
    state = state.copyWith(
      displayName: precise.short,
      fullAddress: precise.formatted,
      lat: d.lat,
      lng: d.lng,
      isLoading: false,
      isDetecting: false,
      status: LocationStatus.set,
      preciseAddress: precise,
      lastFixMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (persist) _persist();
  }

  /// Reverse-geocode [lat],[lng] using Google API, falling back to native geocoding.
  Future<void> _reverseGeocodeAndApply(double lat, double lng,
      {required bool persist}) async {
    // Try Google Geocoding API first (much more precise for Indian addresses)
    final details = await placesService.reverseGeocode(lat, lng);
    if (details != null && mounted) {
      _applyDetails(details, persist: persist);
      return;
    }
    // Fallback to native geocoding
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isNotEmpty && mounted) {
        _applyPlacemark(marks.first, lat, lng, persist: persist);
      }
    } catch (_) {}
  }

  /// Silently re-fetch GPS and update state without showing the loading spinner.
  Future<void> _backgroundRefresh() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (mounted) await _reverseGeocodeAndApply(pos.latitude, pos.longitude, persist: true);
    } catch (_) {}
  }

  /// Force an immediate fresh GPS fix regardless of cache.
  /// Call this before any safety-critical service (ambulance, etc.).
  Future<void> forceRefresh() => fetchCurrent();

  List<LocationSuggestion> _loadRecent(SharedPreferences prefs) {
    final raw = prefs.getStringList(_kRecent) ?? [];
    return raw.map((s) {
      final p = s.split('|');
      if (p.length != 4) return null;
      return LocationSuggestion(
        shortName: p[0],
        displayName: p[1],
        lat: double.tryParse(p[2]) ?? 0,
        lng: double.tryParse(p[3]) ?? 0,
      );
    }).whereType<LocationSuggestion>().toList();
  }

  Future<void> fetchCurrent() async {
    state = state.copyWith(
      displayName: 'Detecting…',
      isLoading: true,
      isDetecting: true,
      status: LocationStatus.detecting,
    );
    try {
      // Check connectivity first — skip GPS if offline
      final connResult = await Connectivity().checkConnectivity();
      final connList = connResult is List ? connResult as List : [connResult];
      final isOnline = connList.any((r) => r != ConnectivityResult.none);

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        state = state.copyWith(
          displayName: 'Location off',
          isLoading: false,
          isDetecting: false,
          status: LocationStatus.error,
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        state = state.copyWith(
          displayName: 'Select location',
          isLoading: false,
          isDetecting: false,
          status: LocationStatus.error,
        );
        return;
      }

      // Fast low-accuracy fix for quick UX
      try {
        final quick = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 3),
        );
        if (mounted) {
          if (isOnline) {
            await _reverseGeocodeAndApply(quick.latitude, quick.longitude,
                persist: false);
          } else {
            // Offline: show coordinates as address
            _applyOfflinePosition(quick.latitude, quick.longitude,
                persist: false);
          }
        }
      } catch (_) {}

      // High-accuracy follow-up
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 15),
      );
      if (mounted) {
        if (isOnline) {
          await _reverseGeocodeAndApply(pos.latitude, pos.longitude,
              persist: true);
        } else {
          _applyOfflinePosition(pos.latitude, pos.longitude, persist: true);
        }
      }
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          displayName: state.displayName == 'Detecting…'
              ? 'Select location'
              : state.displayName,
          isLoading: false,
          isDetecting: false,
          status: LocationStatus.error,
        );
      }
    }
  }

  void _applyOfflinePosition(double lat, double lng,
      {required bool persist}) {
    final precise = PreciseAddress(lat: lat, lng: lng);
    state = state.copyWith(
      displayName: 'Current location',
      fullAddress:
          '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      lat: lat,
      lng: lng,
      isLoading: false,
      isDetecting: false,
      status: LocationStatus.set,
      preciseAddress: precise,
      lastFixMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (persist) _persist();
  }

  void _applyPlacemark(Placemark pm, double lat, double lng,
      {required bool persist}) {
    final precise = PreciseAddress(
      plotNo: pm.subThoroughfare?.isNotEmpty == true ? pm.subThoroughfare : null,
      building: _extractBuilding(pm),
      street: pm.thoroughfare?.isNotEmpty == true ? pm.thoroughfare : null,
      area: pm.subLocality?.isNotEmpty == true ? pm.subLocality : null,
      city: pm.locality?.isNotEmpty == true
          ? pm.locality
          : pm.administrativeArea,
      state: pm.administrativeArea?.isNotEmpty == true
          ? pm.administrativeArea
          : null,
      pincode: pm.postalCode?.isNotEmpty == true ? pm.postalCode : null,
      lat: lat,
      lng: lng,
    );

    final short = precise.short;
    final full = precise.formatted;

    state = state.copyWith(
      displayName: short,
      fullAddress: full,
      lat: lat,
      lng: lng,
      isLoading: false,
      isDetecting: false,
      status: LocationStatus.set,
      preciseAddress: precise,
      lastFixMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (persist) _persist();
  }

  // Extract building name from Placemark — 'name' often contains the POI/building
  String? _extractBuilding(Placemark pm) {
    final name = pm.name?.trim() ?? '';
    final street = pm.thoroughfare?.trim() ?? '';
    // 'name' is meaningful only if it differs from the street name
    if (name.isNotEmpty && name != street) return name;
    return null;
  }

  /// Reverse-geocode arbitrary coordinates (used when dragging a map pin).
  Future<void> setFromCoordinates(double lat, double lng) async {
    state = state.copyWith(isDetecting: true);
    try {
      await _reverseGeocodeAndApply(lat, lng, persist: true);
    } catch (_) {
      if (mounted) state = state.copyWith(isDetecting: false);
    }
  }

  /// Directly apply an already-resolved [PreciseAddress] (e.g. from map picker).
  Future<void> setPreciseAddress(PreciseAddress addr) async {
    state = state.copyWith(
      displayName: addr.short,
      fullAddress: addr.formatted,
      lat: addr.lat,
      lng: addr.lng,
      isLoading: false,
      isDetecting: false,
      status: LocationStatus.set,
      preciseAddress: addr,
      lastFixMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _addRecent(LocationSuggestion(
      shortName: addr.short,
      displayName: addr.formatted,
      lat: addr.lat,
      lng: addr.lng,
    ));
    await _persist();
  }

  Future<void> setFromSuggestion(LocationSuggestion s) async {
    state = LocationState(
      displayName: s.shortName,
      fullAddress: s.displayName,
      lat: s.lat,
      lng: s.lng,
      isLoading: false,
      status: LocationStatus.set,
      recentLocations: state.recentLocations,
    );
    await _addRecent(s);
    await _persist();
    // Fetch precise address in background
    _enrichFromCoordinates(s.lat, s.lng);
  }

  // Enrich state with precise address components after setting from suggestion
  Future<void> _enrichFromCoordinates(double lat, double lng) async {
    try {
      final details = await placesService.reverseGeocode(lat, lng);
      if (details != null && mounted) {
        final precise = PreciseAddress(
          plotNo: details.plotNo,
          building: details.building,
          street: details.street,
          area: details.area,
          city: details.city,
          state: details.state,
          pincode: details.pincode,
          lat: lat,
          lng: lng,
        );
        if (mounted) state = state.copyWith(preciseAddress: precise);
      }
    } catch (_) {}
  }

  /// Enrich the current location state with precise details from Google Places API.
  void applyPlacesDetails(PlaceDetails details) {
    if (!mounted) return;
    final precise = PreciseAddress(
      plotNo: details.plotNo,
      building: details.building,
      street: details.street,
      area: details.area,
      city: details.city,
      state: details.state,
      pincode: details.pincode,
      lat: details.lat,
      lng: details.lng,
    );
    state = state.copyWith(
      lat: details.lat,
      lng: details.lng,
      preciseAddress: precise,
    );
  }

  Future<void> setCity(String city) async {
    state = LocationState(
      displayName: city,
      fullAddress: city,
      isLoading: false,
      status: LocationStatus.set,
      recentLocations: state.recentLocations,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDisplayName, city);
    await prefs.setString(_kFullAddress, city);
    await prefs.remove(_kLat);
    await prefs.remove(_kLng);
  }

  Future<void> _addRecent(LocationSuggestion s) async {
    final updated = [
      s,
      ...state.recentLocations.where((r) => r.displayName != s.displayName),
    ].take(5).toList();
    state = state.copyWith(recentLocations: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kRecent,
      updated
          .map((r) => '${r.shortName}|${r.displayName}|${r.lat}|${r.lng}')
          .toList(),
    );
  }

  Future<void> clearRecent() async {
    state = state.copyWith(recentLocations: []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRecent);
  }

  /// Start streaming live location updates.
  void startLiveTracking() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
      ),
    ).listen((pos) async {
      if (!mounted) return;
      await _reverseGeocodeAndApply(pos.latitude, pos.longitude, persist: true);
    });
  }

  void stopLiveTracking() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDisplayName, state.displayName);
    await prefs.setString(_kFullAddress, state.fullAddress);
    if (state.lat != null) await prefs.setDouble(_kLat, state.lat!);
    if (state.lng != null) await prefs.setDouble(_kLng, state.lng!);
    await prefs.setInt(
        _kTimestamp, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }
}

final locationProvider =
    StateNotifierProvider<LocationNotifier, LocationState>(
  (ref) => LocationNotifier(),
);
