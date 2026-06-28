import 'dart:async';
import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class DoctorLocationService {
  static final _db = FirebaseFirestore.instance;
  static StreamSubscription<Position>? _positionSub;
  static StreamSubscription<ServiceStatus>? _serviceStatusSub;
  static String? _trackingUid;
  // Minimum gap between Firestore writes to prevent write storms on fast movement.
  static const _kMinWriteInterval = Duration(seconds: 30);
  static DateTime? _lastWriteTime;

  // ── Geohash (no external package needed) ───────────────────────────────
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
  static Future<bool> isServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  static Future<LocationPermission> getPermissionStatus() =>
      Geolocator.checkPermission();

  /// Request location permission. On Android, attempts to upgrade from
  /// whileInUse → always (needed for reliable background updates).
  static Future<bool> checkAndRequestPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return false;
    // Upgrade to "always" if we only have whileInUse
    if (perm == LocationPermission.whileInUse) {
      try {
        final upgraded = await Geolocator.requestPermission();
        if (upgraded == LocationPermission.always) {
          return true;
        }
      } catch (_) {}
      // Accept whileInUse as fallback — tracking still works while app is open
      return true;
    }
    return perm == LocationPermission.always;
  }

  static Future<void> openLocationSettings() =>
      Geolocator.openLocationSettings();
  static Future<void> openAppSettings() => Geolocator.openAppSettings();

  // ── Tracking ─────────────────────────────────────────────────────────────
  static Future<void> startTracking({
    required String uid,
    required void Function() onLocationDisabled,
  }) async {
    _trackingUid = uid;

    // Monitor GPS on/off — triggers auto-offline
    _serviceStatusSub?.cancel();
    _serviceStatusSub =
        Geolocator.getServiceStatusStream().listen((status) {
      if (status == ServiceStatus.disabled) {
        onLocationDisabled();
      } else if (status == ServiceStatus.enabled &&
          _positionSub == null) {
        // GPS re-enabled: restart position stream
        _restartPositionStream(uid, onLocationDisabled);
      }
    });

    _restartPositionStream(uid, onLocationDisabled);
  }

  static void _restartPositionStream(
      String uid, void Function() onLocationDisabled) {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30, // update every 30 m for better precision
      ),
    ).listen(
      (pos) async {
        // Rate-limit Firestore writes: skip if last write was < 30 s ago.
        final now = DateTime.now();
        if (_lastWriteTime != null &&
            now.difference(_lastWriteTime!) < _kMinWriteInterval) {
          return;
        }
        _lastWriteTime = now;
        try {
          final gh = geohash(pos.latitude, pos.longitude);
          await _db.collection('doctors').doc(uid).update({
            'location': GeoPoint(pos.latitude, pos.longitude),
            'geohash': gh,
            'geohash5': gh.substring(0, 5),
            'lastLocationUpdate': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          dev.log('[DoctorLocation] Firestore write failed: $e');
        }
      },
      onError: (e) {
        dev.log('[DoctorLocation] Position stream error: $e');
        // Attempt restart after brief delay to recover from transient errors
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
      dev.log('[DoctorLocation] getCurrentPosition failed: $e');
      return null;
    }
  }

  /// Push the current GPS fix to Firestore immediately (on-demand refresh).
  static Future<void> pushCurrentPosition(String uid) async {
    final pos = await getCurrentPosition();
    if (pos == null) return;
    try {
      final gh = geohash(pos.latitude, pos.longitude);
      await _db.collection('doctors').doc(uid).update({
        'location': GeoPoint(pos.latitude, pos.longitude),
        'geohash': gh,
        'geohash5': gh.substring(0, 5),
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      dev.log('[DoctorLocation] pushCurrentPosition failed: $e');
    }
  }
}
