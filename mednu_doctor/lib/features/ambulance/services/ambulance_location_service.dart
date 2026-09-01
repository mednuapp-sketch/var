import 'dart:async';
import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

/// Streams this ambulance partner's live GPS position into
/// `ambulance_profiles/{uid}` while they're online — the same pattern as
/// `DoctorLocationService`, just targeting a different collection. This is
/// what `_findNearestOnlineAmbulance` (functions/index.js) reads to match a
/// new request to the nearest available driver instead of dropping every
/// request into the shared unclaimed pool.
class AmbulanceLocationService {
  static final _db = FirebaseFirestore.instance;
  static StreamSubscription<Position>? _positionSub;
  static StreamSubscription<ServiceStatus>? _serviceStatusSub;
  static String? _trackingUid;
  // Minimum gap between Firestore writes to prevent write storms on fast movement.
  static const _kMinWriteInterval = Duration(seconds: 30);
  static DateTime? _lastWriteTime;

  // ── Geohash (no external package needed) — same algorithm as
  // DoctorLocationService.geohash, kept for schema consistency even though
  // the nearest-match Cloud Function currently compares raw GeoPoints rather
  // than geohash ranges.
  static String geohash(double lat, double lng, {int precision = 9}) {
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    var minLat = -90.0, maxLat = 90.0;
    var minLng = -180.0, maxLng = 180.0;
    var hash = '';
    var bits = 0, hashValue = 0;
    var isEven = true;

    while (hash.length < precision) {
      if (isEven) {
        final mid = (minLng + maxLng) / 2;
        if (lng >= mid) {
          hashValue = (hashValue << 1) + 1;
          minLng = mid;
        } else {
          hashValue = hashValue << 1;
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (lat >= mid) {
          hashValue = (hashValue << 1) + 1;
          minLat = mid;
        } else {
          hashValue = hashValue << 1;
          maxLat = mid;
        }
      }
      isEven = !isEven;
      bits++;
      if (bits == 5) {
        hash += base32[hashValue];
        bits = 0;
        hashValue = 0;
      }
    }
    return hash;
  }

  // ── Permission & Service checks ─────────────────────────────────────────
  static Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  static Future<LocationPermission> getPermissionStatus() => Geolocator.checkPermission();

  static Future<bool> checkAndRequestPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return false;
    if (perm == LocationPermission.whileInUse) {
      try {
        final upgraded = await Geolocator.requestPermission();
        if (upgraded == LocationPermission.always) return true;
      } catch (_) {}
      return true; // whileInUse still works while the app/foreground service is alive.
    }
    return perm == LocationPermission.always;
  }

  static Future<void> openLocationSettings() => Geolocator.openLocationSettings();
  static Future<void> openAppSettings() => Geolocator.openAppSettings();

  // ── Tracking ─────────────────────────────────────────────────────────────
  static Future<void> startTracking({
    required String uid,
    required void Function() onLocationDisabled,
  }) async {
    _trackingUid = uid;

    _serviceStatusSub?.cancel();
    _serviceStatusSub = Geolocator.getServiceStatusStream().listen((status) {
      if (status == ServiceStatus.disabled) {
        onLocationDisabled();
      } else if (status == ServiceStatus.enabled && _positionSub == null) {
        _restartPositionStream(uid, onLocationDisabled);
      }
    });

    _restartPositionStream(uid, onLocationDisabled);
  }

  static void _restartPositionStream(String uid, void Function() onLocationDisabled) {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
      ),
    ).listen(
      (pos) async {
        final now = DateTime.now();
        if (_lastWriteTime != null && now.difference(_lastWriteTime!) < _kMinWriteInterval) {
          return;
        }
        _lastWriteTime = now;
        try {
          final gh = geohash(pos.latitude, pos.longitude);
          await _db.collection('ambulance_profiles').doc(uid).update({
            'location': GeoPoint(pos.latitude, pos.longitude),
            'geohash': gh,
            'geohash5': gh.substring(0, 5),
            // Geolocator's Position.speed is metres/second, GPS-derived —
            // negative/near-zero readings happen when the fix is poor or the
            // vehicle is stationary, so this is clamped rather than trusted
            // blindly. Read by the live-tracking screen instead of a
            // hardcoded placeholder speed.
            'speedKmh': pos.speed > 0 ? (pos.speed * 3.6) : 0,
            'lastLocationUpdate': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          dev.log('[AmbulanceLocation] Firestore write failed: $e');
        }
      },
      onError: (e) {
        dev.log('[AmbulanceLocation] Position stream error: $e');
        Future.delayed(const Duration(seconds: 5), () {
          if (_trackingUid == uid) {
            _restartPositionStream(uid, onLocationDisabled);
          }
        });
      },
      cancelOnError: true,
    );
  }

  static Future<void> stopTracking() async {
    _trackingUid = null;
    _lastWriteTime = null;
    await _positionSub?.cancel();
    await _serviceStatusSub?.cancel();
    _positionSub = null;
    _serviceStatusSub = null;
  }

  // ── One-shot current position ────────────────────────────────────────────
  static Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      dev.log('[AmbulanceLocation] getCurrentPosition failed: $e');
      return null;
    }
  }

  /// Push the current GPS fix to Firestore immediately (on-demand refresh —
  /// used right after going online so the driver is matchable before the
  /// first 30 m movement triggers the position stream).
  static Future<void> pushCurrentPosition(String uid) async {
    final pos = await getCurrentPosition();
    if (pos == null) return;
    try {
      final gh = geohash(pos.latitude, pos.longitude);
      await _db.collection('ambulance_profiles').doc(uid).update({
        'location': GeoPoint(pos.latitude, pos.longitude),
        'geohash': gh,
        'geohash5': gh.substring(0, 5),
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      dev.log('[AmbulanceLocation] pushCurrentPosition failed: $e');
    }
  }
}
