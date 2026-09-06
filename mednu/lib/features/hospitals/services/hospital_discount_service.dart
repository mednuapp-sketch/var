import 'package:cloud_firestore/cloud_firestore.dart';

enum DiscountType { percent, flat }

class HospitalBillDiscount {
  final String id;
  final String label;
  final DiscountType type;
  final double value;
  final double? maxDiscountAmount;
  final double? minBillAmount;

  const HospitalBillDiscount({
    required this.id,
    required this.label,
    required this.type,
    required this.value,
    this.maxDiscountAmount,
    this.minBillAmount,
  });

  factory HospitalBillDiscount.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return HospitalBillDiscount(
      id: doc.id,
      label: (d['label'] as String?) ?? '',
      type: (d['type'] as String?) == 'flat' ? DiscountType.flat : DiscountType.percent,
      value: (d['value'] as num?)?.toDouble() ?? 0,
      maxDiscountAmount: (d['maxDiscountAmount'] as num?)?.toDouble(),
      minBillAmount: (d['minBillAmount'] as num?)?.toDouble(),
    );
  }

  /// Whether this discount can be applied to a bill of [billAmount].
  bool appliesTo(double billAmount) =>
      minBillAmount == null || billAmount >= minBillAmount!;

  /// Rupee amount knocked off [billAmount] by this discount, capped by
  /// [maxDiscountAmount] when set and never more than the bill itself.
  double discountFor(double billAmount) {
    if (!appliesTo(billAmount)) return 0;
    var discount = type == DiscountType.flat ? value : billAmount * value / 100;
    if (maxDiscountAmount != null && discount > maxDiscountAmount!) {
      discount = maxDiscountAmount!;
    }
    return discount.clamp(0, billAmount);
  }
}

class HospitalDiscountService {
  static final _db = FirebaseFirestore.instance;

  /// Live-streamed so admin changes to the discount catalog show up in the
  /// patient app immediately, with no app update or manual refresh needed.
  static Stream<List<HospitalBillDiscount>> streamActive() => _db
      .collection('hospital_bill_discounts')
      .where('isEnabled', isEqualTo: true)
      .snapshots()
      .map((s) => s.docs.map(HospitalBillDiscount.fromFirestore).toList());
}
