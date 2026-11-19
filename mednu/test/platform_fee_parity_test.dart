import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mednu/core/providers/platform_fee_provider.dart';

// Shares shared/fee_cases.json with functions/test/unit/fee_parity.test.js.
void main() {
  final cases = jsonDecode(File('../shared/fee_cases.json').readAsStringSync())
      as Map<String, dynamic>;

  test('normalizeFeeServiceType matches shared cases', () {
    for (final c in cases['normalizeFeeServiceType'] as List) {
      expect(normalizeFeeServiceType(c['input'] as String?), c['expected'],
          reason: 'input ${c['input']}');
    }
  });

  test('platform fee resolution matches shared cases', () {
    for (final c in cases['platformFeeFor'] as List) {
      final cfg = parsePlatformFeeConfig(
          Map<String, dynamic>.from(c['cfg'] as Map));
      expect(
          cfg.feeFor(c['serviceType'] as String?,
              providerId: c['providerId'] as String?),
          c['expected'],
          reason: c['name'] as String);
    }
  });

  test('feeProviderIdFor matches shared cases', () {
    for (final c in cases['feeProviderIdFor'] as List) {
      expect(
          feeProviderIdFor(c['serviceType'] as String?, c['bookingData'] as Map?),
          c['expected'],
          reason: c['name'] as String);
    }
  });
}
