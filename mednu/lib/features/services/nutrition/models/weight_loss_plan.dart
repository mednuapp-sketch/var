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

/// The `diet_plans` doc id of the plan being bought (null when the built-in
/// fallback card was used). Only a hint: the server re-reads the real price.
final ValueNotifier<String?> selectedWeightLossPlanId = ValueNotifier<String?>(null);

/// Monthly price (rupees) shown to the patient for the chosen plan. Only used to
/// display the total and to prefill the payment amount; the server verifies it.
final ValueNotifier<int?> selectedWeightLossMonthly = ValueNotifier<int?>(null);

/// Shown before payment (duration sheet + booking summary).
const String kWeightLossPlanNotice =
    'Pay once, one consultation per month. Unused consultations expire at the '
    'end of the plan and are not refunded. The platform fee is non-refundable.';

bool isWeightLossPlan(String title) =>
    title.toLowerCase().contains('weight loss');

/// Pulls the monthly amount out of a display price like "₹1,200/month".
/// Returns null when no number is present.
int? monthlyAmountFromPrice(String price) {
  final match = RegExp(r'[\d,]+').firstMatch(price);
  if (match == null) return null;
  return int.tryParse(match.group(0)!.replaceAll(',', ''));
}
