import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../shared_core/services/pending_profile_edit_service.dart';

/// Mirrors `LabProfileService` for the Ambulance role: a thin static-method
/// wrapper around `ambulance_profiles/{uid}`. This never touches the
/// `doctors` collection or Firebase Auth itself — an ambulance partner is
/// the same signed-in account as any other role, just with an additional
/// profile document. That document's existence is also what
/// `firestore.rules`' `isAmbulancePartner()` checks to decide who may read
/// the shared, unclaimed dispatch queue.
class AmbulanceProfileService {
  AmbulanceProfileService._();

  static final _db = FirebaseFirestore.instance;

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  static Future<bool> profileExists(String uid) async {
    final doc = await _db.collection('ambulance_profiles').doc(uid).get();
    return doc.exists;
  }

  static Future<Map<String, dynamic>?> getProfile(String uid) async {
    final doc = await _db.collection('ambulance_profiles').doc(uid).get();
    return doc.data();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> profileStream(String uid) =>
      _db.collection('ambulance_profiles').doc(uid).snapshots();

  static Future<void> createProfile({
    required String uid,
    required String plateNumber,
    required String vehicleType,
    String? vehicleTypeKey,
    required String driverName,
    required String driverPhone,
    required String driverLicense,
    List<String> equipment = const [],
  }) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 5));
    } catch (_) {}

    await _db.collection('ambulance_profiles').doc(uid).set({
      'uid': uid,
      'plateNumber': plateNumber,
      'vehicleType': vehicleType,
      if (vehicleTypeKey != null) 'vehicleTypeKey': vehicleTypeKey,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'driverLicense': driverLicense,
      'equipment': equipment,
      'documentsVerified': false,
      'status': 'pending',
      'isVerified': false,
      'rating': 0.0,
      'totalReviews': 0,
      'totalTrips': 0,
      'createdAt': FieldValue.serverTimestamp(),
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
  }

  /// `status`/`isVerified`/`rating`/`totalReviews`/`totalTrips` are rejected
  /// by `firestore.rules` for a self-update — a partner can't self-approve or
  /// inflate its own stats. Once `currentStatus` is 'active', this doesn't
  /// touch the live fields at all — see [PendingProfileEditService].
  static Future<void> updateProfile(String uid, Map<String, dynamic> data, {required String currentStatus}) =>
      PendingProfileEditService.apply(
        ref: _db.collection('ambulance_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: data,
      );

  /// Persists the vehicle/driver avatar URL after an upload or removal.
  /// Once `currentStatus` is 'active', this doesn't touch the live
  /// `photoUrl` at all — see [PendingProfileEditService].
  static Future<void> updatePhotoUrl(String uid, String photoUrl, {required String currentStatus}) =>
      PendingProfileEditService.apply(
        ref: _db.collection('ambulance_profiles').doc(uid),
        currentStatus: currentStatus,
        fields: {'photoUrl': photoUrl},
      );

  /// Canonical vehicle types (keys of `app_config/ambulance_rates.types`) with
  /// the fallback labels used when that config is missing.
  static const Map<String, String> defaultVehicleTypeLabels = {
    'basic': 'Basic',
    'als': 'Advanced Life Support',
    'icu': 'ICU Ambulance',
  };

  /// key -> label for the vehicle-type pick-list, using the labels the admin
  /// rates carry in `app_config/ambulance_rates` (defaults when absent).
  static Future<Map<String, String>> fetchVehicleTypeLabels() async {
    final labels = Map<String, String>.from(defaultVehicleTypeLabels);
    try {
      final snap = await _db.collection('app_config').doc('ambulance_rates').get();
      final types = snap.data()?['types'] as Map?;
      if (types != null) {
        for (final k in labels.keys.toList()) {
          final l = (types[k] as Map?)?['label'];
          if (l is String && l.trim().isNotEmpty) labels[k] = l.trim();
        }
      }
    } catch (_) {}
    return labels;
  }

  /// Rate-config key for a profile: the canonical `vehicleTypeKey` when it is
  /// valid, otherwise the legacy keyword guess on the free-text `vehicleType`.
  /// Null when unrecognised.
  static String? rateKeyForVehicleType(String vehicleType, {String? typeKey}) {
    if (typeKey != null && defaultVehicleTypeLabels.containsKey(typeKey)) return typeKey;
    final s = vehicleType.toLowerCase();
    if (s.contains('icu')) return 'icu';
    if (s.contains('advanced') || s.contains('als')) return 'als';
    if (s.contains('basic') || s.contains('bls')) return 'basic';
    return null;
  }

  /// Admin-defined rate range for a type key, falling back to the previous
  /// hardcoded prices (min == max) when `app_config/ambulance_rates` is
  /// missing or lacks that type. Returns {min, max} or null for unknown keys.
  static Future<({double min, double max})?> fetchRateRange(String? key) async {
    const defaults = {'basic': 500.0, 'als': 1200.0, 'icu': 2500.0};
    if (key == null || !defaults.containsKey(key)) return null;
    try {
      final snap = await _db.collection('app_config').doc('ambulance_rates').get();
      final t = (snap.data()?['types'] as Map?)?[key] as Map?;
      final mn = (t?['min'] as num?)?.toDouble();
      final mx = (t?['max'] as num?)?.toDouble();
      if (mn != null && mx != null && mn >= 0 && mx >= mn) return (min: mn, max: mx);
    } catch (_) {}
    return (min: defaults[key]!, max: defaults[key]!);
  }

  /// Saves the driver's own rate. A direct write (not a pending-review edit):
  /// `ratePerTrip` is in firestore.rules' active-profile whitelist.
  static Future<void> setRatePerTrip(String uid, double rate) =>
      _db.collection('ambulance_profiles').doc(uid).update({
        'ratePerTrip': rate,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
