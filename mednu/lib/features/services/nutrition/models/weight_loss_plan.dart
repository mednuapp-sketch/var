import 'package:flutter/foundation.dart';

/// Weight-loss programme durations. Every plan includes one dietician
/// consultation per month, so a plan of N months = N consultations.
class WeightLossPlanOption {
  final int months;
  final bool recommended;
  const WeightLossPlanOption(this.months, {this.recommended = false});

  int get consultations => months;
}

const weightLossPlanOptions = <WeightLossPlanOption>[
  WeightLossPlanOption(2),
  WeightLossPlanOption(4),
  WeightLossPlanOption(6, recommended: true),
];

/// The duration the patient picked on the Diet Plans screen. Read (and
/// cleared) by the booking screen so the choice is stored on the appointment.
final ValueNotifier<int?> selectedWeightLossMonths = ValueNotifier<int?>(null);

bool isWeightLossPlan(String title) =>
    title.toLowerCase().contains('weight loss');

/// Pulls the monthly amount out of a display price like "₹1,200/month".
/// Returns null when no number is present.
int? monthlyAmountFromPrice(String price) {
  final match = RegExp(r'[\d,]+').firstMatch(price);
  if (match == null) return null;
  return int.tryParse(match.group(0)!.replaceAll(',', ''));
}
