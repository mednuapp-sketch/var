import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Admin-controlled, PER-SERVICE platform fee read from Firestore
/// `app_config/platform_fee`:
/// `{enabled: bool, defaultAmount: number, services: {<serviceType>: number},
///   updatedAt, updatedBy}` (legacy `amount` == `defaultAmount`).
///
/// `providers: {<providerId>: {amount, label?}}` overrides the fee for one
/// partner profile.
///
/// Fee for a booking = enabled
///   ? (providers[providerId] ?? services[type] ?? defaultAmount ?? 0) : 0.
/// A missing/invalid doc, or a loading/error state, resolves to 0 so booking
/// is never blocked.
class PlatformFeeConfig {
  final bool enabled;
  final int defaultAmount;
  final Map<String, int> services;
  final Map<String, int> providers;
  const PlatformFeeConfig({
    this.enabled = false,
    this.defaultAmount = 0,
    this.services = const {},
    this.providers = const {},
  });

  static const PlatformFeeConfig none = PlatformFeeConfig();

  int feeFor(String? serviceType, {String? providerId}) {
    if (!enabled) return 0;
    final pid = providerId?.trim();
    if (pid != null && pid.isNotEmpty) {
      final p = providers[pid];
      if (p != null) return p < 0 ? 0 : p;
    }
    final key = normalizeFeeServiceType(serviceType);
    final v = (key != null ? services[key] : null) ?? defaultAmount;
    return v < 0 ? 0 : v;
  }
}

/// Maps the aliases used across the app onto the admin's service keys.
String? normalizeFeeServiceType(String? raw) {
  if (raw == null) return null;
  final t = raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  switch (t) {
    case 'lab_tests':
    case 'lab_test':
    case 'labtest':
    case 'diagnostic':
    case 'diagnostics':
      return 'diagnostics';
    case 'nursing':
    case 'home_care':
    case 'homecare':
    case 'caregiver':
      return 'caregiver';
    case 'medicine':
    case 'medicines':
    case 'pharmacy':
      return 'medicine';
    case 'physio':
    case 'physiotherapy':
      return 'physiotherapy';
    case 'counseling':
    case 'counselling':
      return 'counselling';
    case 'video':
    case 'video_consultation':
      return 'video_consultation';
    default:
      return t;
  }
}

int? _asFee(dynamic raw) {
  final n = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
  if (n == null || n.isNaN || n < 0) return null;
  return n.round();
}

PlatformFeeConfig parsePlatformFeeConfig(Map<String, dynamic>? data) {
  if (data == null) return PlatformFeeConfig.none;
  final services = <String, int>{};
  final rawServices = data['services'];
  if (rawServices is Map) {
    rawServices.forEach((k, v) {
      final fee = _asFee(v);
      final key = normalizeFeeServiceType(k.toString());
      if (fee != null && key != null) services[key] = fee;
    });
  }
  final providers = <String, int>{};
  final rawProviders = data['providers'];
  if (rawProviders is Map) {
    rawProviders.forEach((k, v) {
      final fee = _asFee(v is Map ? v['amount'] : v);
      final id = k.toString().trim();
      if (fee != null && id.isNotEmpty) providers[id] = fee;
    });
  }
  return PlatformFeeConfig(
    providers: providers,
    enabled: data['enabled'] == true,
    defaultAmount: _asFee(data['defaultAmount'] ?? data['amount']) ?? 0,
    services: services,
  );
}

/// Last config seen from Firestore, so synchronous reads (button handlers,
/// freshly-built screens) don't flash 0 while the stream re-subscribes.
PlatformFeeConfig _cachedConfig = PlatformFeeConfig.none;

/// Live config stream (changes made in the admin panel apply immediately).
final platformFeeConfigProvider = StreamProvider<PlatformFeeConfig>((ref) {
  return FirebaseFirestore.instance
      .collection('app_config')
      .doc('platform_fee')
      .snapshots()
      .map((snap) => _cachedConfig = parsePlatformFeeConfig(snap.data()))
      .handleError((_) {});
});

/// Platform fee in whole rupees for [serviceType]. Pass `watch: true` from
/// `build` so the UI rebuilds when the admin changes the fee; use the default
/// (read) inside button handlers. Always 0 until the config is available.
///
/// [providerId] (optional) applies a partner-specific override; null/unknown
/// falls back to the service / default fee.
int platformFeeFor(WidgetRef ref, String? serviceType,
    {bool watch = false, String? providerId}) {
  final async = watch
      ? ref.watch(platformFeeConfigProvider)
      : ref.read(platformFeeConfigProvider);
  final cfg = async.valueOrNull ?? _cachedConfig;
  return cfg.feeFor(serviceType, providerId: providerId);
}

const _kFeeProviderKeys = <String, List<String>>{
  'consultation': ['doctorId'],
  'video_consultation': ['doctorId'],
  'diagnostics': ['sd.sourceLabId', 'labId'],
  'lab_tests': ['sd.sourceLabId', 'labId'],
  'medicine': ['pharmacyId'],
  'pharmacy': ['pharmacyId'],
  'equipment': ['sd.sourceVendorId', 'vendorId'],
  'equipment_hiring': ['sd.sourceVendorId', 'vendorId'],
  'caregiver': ['sd.sourceCaregiverId', 'caregiverId'],
  'caregivers': ['sd.sourceCaregiverId', 'caregiverId'],
  'nursing': ['sd.sourceCaregiverId', 'caregiverId'],
  'home_care': ['sd.sourceCaregiverId', 'caregiverId'],
  'care_assistant': ['sd.assistantId', 'assistantId'],
  'physiotherapy': ['physiotherapistId'],
  'counselling': ['counsellorId'],
  'nutrition': ['nutritionistId'],
  'hospital_bill': ['hospitalId'],
  'hospital_op': ['hospitalId'],
  'ambulance': <String>[],
};
const _kFeeProviderFallback = [
  'doctorId', 'nutritionistId', 'physiotherapistId', 'counsellorId',
  'pharmacyId', 'hospitalId', 'providerId',
];

/// Provider id used for the partner-specific fee. MUST stay identical to
/// `feeProviderIdFor` in functions/price_helpers.js (the server recomputes the
/// fee from the same booking data and rejects mismatches).
String? feeProviderIdFor(String? serviceType, Map? bookingData) {
  if (bookingData == null) return null;
  final sdRaw = bookingData['serviceDetails'];
  final sd = sdRaw is Map ? sdRaw : const {};
  final t = (serviceType ?? '').trim().toLowerCase();
  final keys = _kFeeProviderKeys[t] ?? _kFeeProviderFallback;
  for (final k in keys) {
    final v = k.startsWith('sd.') ? sd[k.substring(3)] : bookingData[k];
    if (v is String) {
      final s = v.trim();
      if (s.isNotEmpty && !s.contains('/') && v.length < 400) return s;
    }
  }
  return null;
}
