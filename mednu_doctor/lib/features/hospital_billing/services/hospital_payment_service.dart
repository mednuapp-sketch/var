import 'package:cloud_firestore/cloud_firestore.dart';

/// One `hospital_bill_payments/{id}` doc — written by the patient app's
/// PayHospitalBillScreen (via the shared PaymentScreen/capturePayment
/// pipeline, or directly when `kRequirePayment` is false — see mednu's
/// payment_config.dart). Read-only apart from [HospitalPaymentService.
/// markVerified] — the billing desk's one available action, matching
/// firestore.rules' `hospital_bill_payments` update rule, which allows
/// touching `hospitalVerified`/`hospitalVerifiedAt` only.
class HospitalBillPayment {
  final String id;
  final String? patientId;
  final double billAmount;
  final double finalAmount;
  final String? discountLabel;
  final String? paymentStatus;
  final bool hospitalVerified;
  final DateTime? createdAt;

  const HospitalBillPayment({
    required this.id,
    required this.patientId,
    required this.billAmount,
    required this.finalAmount,
    required this.discountLabel,
    required this.paymentStatus,
    required this.hospitalVerified,
    required this.createdAt,
  });

  factory HospitalBillPayment.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    final ts = d['createdAt'];
    return HospitalBillPayment(
      id: doc.id,
      patientId: d['patientId'] as String?,
      billAmount: (d['billAmount'] as num?)?.toDouble() ?? 0,
      finalAmount: (d['finalAmount'] as num?)?.toDouble() ?? 0,
      discountLabel: d['discountLabel'] as String?,
      paymentStatus: (d['paymentStatus'] ?? d['status']) as String?,
      hospitalVerified: d['hospitalVerified'] == true,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class HospitalPaymentService {
  HospitalPaymentService._();

  static final _db = FirebaseFirestore.instance;

  /// Live-streamed so a new payment shows up on the billing desk's screen the
  /// moment a patient pays — no manual refresh needed.
  static Stream<List<HospitalBillPayment>> streamForHospital(String hospitalId) => _db
      .collection('hospital_bill_payments')
      .where('hospitalId', isEqualTo: hospitalId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(HospitalBillPayment.fromFirestore).toList());

  /// The billing desk's confirmation that a payment actually landed — shows
  /// up back on the patient's Service Tracker entry for this payment too
  /// (see UnifiedBooking.fromHospitalBillPayment in mednu).
  static Future<void> markVerified(String paymentId) => _db
      .collection('hospital_bill_payments')
      .doc(paymentId)
      .update({
        'hospitalVerified': true,
        'hospitalVerifiedAt': FieldValue.serverTimestamp(),
      });
}
