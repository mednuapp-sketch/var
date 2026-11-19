import 'package:flutter_test/flutter_test.dart';
import 'package:mednu/features/services/nutrition/models/weight_loss_plan.dart';

void main() {
  group('monthlyAmountFromPrice', () {
    test('parses plain and formatted prices', () {
      expect(monthlyAmountFromPrice('₹1,200/month'), 1200);
      expect(monthlyAmountFromPrice('Rs. 500'), 500);
      expect(monthlyAmountFromPrice('750'), 750);
    });

    test('returns null when there is no number', () {
      expect(monthlyAmountFromPrice(''), isNull);
      expect(monthlyAmountFromPrice('Free'), isNull);
    });
  });

  group('weight loss plans', () {
    test('options are 2/4/6 months with one consultation per month', () {
      expect(weightLossPlanOptions.map((o) => o.months), [2, 4, 6]);
      for (final o in weightLossPlanOptions) {
        expect(o.consultations, o.months);
      }
      expect(weightLossPlanOptions.where((o) => o.recommended).single.months, 6);
    });

    test('isWeightLossPlan is case-insensitive', () {
      expect(isWeightLossPlan('Weight Loss Programme'), isTrue);
      expect(isWeightLossPlan('Diabetes care'), isFalse);
    });
  });
}
