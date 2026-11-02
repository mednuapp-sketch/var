import 'dart:async';
import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Publishes this driver's GPS to `ambulance_live/{requestId}` every few
/// seconds for as long as a trip is open (accepted → en route → arrived), so
/// the patient sees the ambulance move in real time.
///
/// Deliberately separate from [AmbulanceLocationService] (the coarse
/// 30-second "I'm online and matchable" heartbeat on the profile): that one is
/// owned by the dashboard's Online switch and is torn down when the dashboard
/// screen is disposed, which a bottom-nav tab switch does. A trip feed must
/// not depend on which screen the driver happens to be looking at, so this is
/// driven from the app root (see `ambulanceTripTrackingProvider`).
///
/// On Android it runs as a foreground service of type "location" (with a
/// persistent notification), so the feed survives the driver switching to
/// Google Maps for turn-by-turn. The feed stops the moment the trip ends —
/// the backend also deletes the live document then.
class AmbulanceTripTracker {
  AmbulanceTripTracker._();

  static final _db = FirebaseFirestore.instance;

  /// Minimum gap between Firestore writes. Together with the 5 m distance
  /// filter this gives a smooth marker without a write storm.
  static const _minWriteInterval = Duration(seconds: 3);

  static StreamSubscription<Position>? _sub;
  static String? _requestId;
  static String? _ambulanceId;
  static String? _patientId;
  static String _status = 'accepted';
  static DateTime? _lastWrite;
  static bool _stopping = false;

  static final _positions = StreamController<Position>.broadcast();
  static Position? _latest;

  /// Every GPS fix while a trip is being tracked — lets the driver's own map
  /// move smoothly without a Firestore round trip.
  static Stream<Position> get positions => _positions.stream;

  /// Most recent fix, or null before the first one arrives.
  static Position? get latest => _latest;

  static bool get isTracking => _sub != null;

  /// Starts (or retargets) tracking for [requestId]. Safe to call repeatedly:
  /// calling it again for the same trip only refreshes the status.
  static Future<void> start({
    required String requestId,
    required String ambulanceId,
    required String patientId,
    required String status,
  }) async {
    _status = status;
    if (_sub != null && _requestId == requestId) return;

    await stop();
    _stopping = false;
    _requestId = requestId;
    _ambulanceId = ambulanceId;
    _patientId = patientId;
    _lastWrite = null;

    if (!await Geolocator.isLocationServiceEnabled()) {
      dev.log('[AmbulanceTrip] location services off — feed not started');
      _requestId = null;
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      dev.log('[AmbulanceTrip] location permission missing — feed not started');
      _requestId = null;
      return;
    }

    _listen();
  }

  static LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'MedNU — ambulance trip active',
          notificationText: 'Sharing your live location with the patient.',
          notificationChannelName: 'Ambulance trip tracking',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 5);
  }

  static void _listen() {
    _sub?.cancel();
    final requestId = _requestId;
    _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(
      (pos) {
        _latest = pos;
        if (!_positions.isClosed) _positions.add(pos);
        _publish(pos);
      },
      onError: (Object e) {
        dev.log('[AmbulanceTrip] position stream error: $e');
        // Retry only if the same trip is still being tracked.
        Future.delayed(const Duration(seconds: 5), () {
          if (!_stopping && _requestId == requestId && requestId != null) _listen();
        });
      },
      cancelOnError: true,
    );
  }

  static Future<void> _publish(Position pos) async {
    final requestId = _requestId;
    final ambulanceId = _ambulanceId;
    final patientId = _patientId;
    if (requestId == null || ambulanceId == null || patientId == null) return;

    final now = DateTime.now();
    if (_lastWrite != null && now.difference(_lastWrite!) < _minWriteInterval) return;
    _lastWrite = now;

    try {
      await _db.collection('ambulance_live').doc(requestId).set({
        'requestId': requestId,
        'ambulanceId': ambulanceId,
        'patientId': patientId,
        'location': GeoPoint(pos.latitude, pos.longitude),
        // Compass heading in degrees (0 = north); -1 when the device can't
        // tell (stationary / no fix), which the patient app treats as "keep
        // the last heading".
        'heading': pos.heading.isFinite && pos.heading >= 0 ? pos.heading : -1,
        'speedKmh': pos.speed > 0 ? pos.speed * 3.6 : 0,
        'accuracy': pos.accuracy,
        'status': _status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // A dropped write is fine — the next fix replaces it. Rules reject
      // writes once the trip has ended.
      dev.log('[AmbulanceTrip] publish failed: $e');
    }
  }

  /// Stops the feed. The backend deletes the live document when the trip
  /// reaches completed / cancelled, so nothing is cleaned up from here.
  static Future<void> stop() async {
    _stopping = true;
    _requestId = null;
    _ambulanceId = null;
    _patientId = null;
    _lastWrite = null;
    _latest = null;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
  }
}
