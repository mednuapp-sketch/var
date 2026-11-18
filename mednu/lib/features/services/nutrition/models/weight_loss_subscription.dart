import 'package:cloud_firestore/cloud_firestore.dart';

/// One monthly consultation credit of a prepaid weight-loss plan.
class PlanCredit {
  final int index;
  final String windowStart; // yyyy-MM-dd
  final String windowEnd; // yyyy-MM-dd (inclusive)
  final String status; // available | booked | completed | lapsed | cancelled
  final String? appointmentId;

  const PlanCredit({
    required this.index,
    required this.windowStart,
    required this.windowEnd,
    required this.status,
    this.appointmentId,
  });

  factory PlanCredit.fromMap(Map<String, dynamic> m) => PlanCredit(
        index: (m['index'] as num?)?.toInt() ?? 0,
        windowStart: m['windowStart'] as String? ?? '',
        windowEnd: m['windowEnd'] as String? ?? '',
        status: m['status'] as String? ?? 'available',
        appointmentId: m['appointmentId'] as String?,
      );

  bool get isAvailable => status == 'available';
}

/// `nutrition_subscriptions/{id}` (server-written, read-only in the app).
class WeightLossSubscription {
  final String id;
  final String nutritionistId;
  final String nutritionistName;
  final String nutritionistSpecialization;
  final int months;
  final int monthlyPrice;
  final int baseTotal;
  final int platformFee;
  final String status; // active | cancelling | cancelled | completed
  final String paymentMode; // paid | not_required
  final String startDate;
  final String endsAtDate; // first day AFTER the last window
  final List<PlanCredit> credits;

  const WeightLossSubscription({
    required this.id,
    required this.nutritionistId,
    required this.nutritionistName,
    required this.nutritionistSpecialization,
    required this.months,
    required this.monthlyPrice,
    required this.baseTotal,
    required this.platformFee,
    required this.status,
    required this.paymentMode,
    required this.startDate,
    required this.endsAtDate,
    required this.credits,
  });

  factory WeightLossSubscription.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final list = (d['consultations'] as List?)
            ?.whereType<Map>()
            .map((e) => PlanCredit.fromMap(e.cast<String, dynamic>()))
            .toList() ??
        <PlanCredit>[];
    list.sort((a, b) => a.index.compareTo(b.index));
    return WeightLossSubscription(
      id: doc.id,
      nutritionistId: d['nutritionistId'] as String? ?? '',
      nutritionistName: d['nutritionistName'] as String? ?? '',
      nutritionistSpecialization: d['nutritionistSpecialization'] as String? ?? '',
      months: (d['months'] as num?)?.toInt() ?? list.length,
      monthlyPrice: (d['monthlyPrice'] as num?)?.toInt() ?? 0,
      baseTotal: (d['baseTotal'] as num?)?.toInt() ?? 0,
      platformFee: (d['platformFee'] as num?)?.toInt() ?? 0,
      status: d['status'] as String? ?? 'active',
      paymentMode: d['paymentMode'] as String? ?? 'paid',
      startDate: d['startDate'] as String? ?? '',
      endsAtDate: d['endsAtDate'] as String? ?? '',
      credits: list,
    );
  }

  bool get isActive => status == 'active';
  int get completedCount => credits.where((c) => c.status == 'completed').length;
  int get availableCount => credits.where((c) => c.isAvailable).length;
  bool get anyCompleted => completedCount > 0;

  /// Last day a consultation can still be used (end of the last window).
  String get lastDay => credits.isEmpty ? '' : credits.last.windowEnd;
}
