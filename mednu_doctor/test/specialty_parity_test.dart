import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mednu_doctor/core/utils/specialty_utils.dart';

// Shares shared/fee_cases.json with functions/test/unit/fee_parity.test.js.
void main() {
  test('isDentalSpecialty matches shared cases', () {
    final cases =
        jsonDecode(File('../shared/fee_cases.json').readAsStringSync())
            as Map<String, dynamic>;
    for (final c in cases['isDentalSpecialty'] as List) {
      expect(isDentalSpecialty(c['input'] as String?), c['expected'],
          reason: 'input ${c['input']}');
    }
  });
}
