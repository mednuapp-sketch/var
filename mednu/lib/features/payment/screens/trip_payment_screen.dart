import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/payment_config.dart';
import '../../wallet/wallet_provider.dart';

/// Pay-after-trip screen for an EXISTING ambulance booking in
/// `paymentStatus: 'payment_due'`. The amount is the server-computed
/// `amountDue` on the booking (fare + platform fee); the server re-validates
/// it in `createRazorpayOrder(tripRequestId)` and `captureTripPayment`.
class TripPaymentScreen extends ConsumerStatefulWidget {
  final String requestId;
  const TripPaymentScreen({super.key, required this.requestId});

  @override
  ConsumerState<TripPaymentScreen> createState() => _TripPaymentScreenState();
}

class _TripPaymentScreenState extends ConsumerState<TripPaymentScreen> {
  late final Razorpay _razorpay;
  bool _busy = false;
  String? _orderId;
  // Stable per screen instance so a retry can never double-debit the wallet.
  final String _idempotencyKey =
      'trip-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _toast(String msg, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: error ? AppColors.error : AppColors.success,
    ));
  }

  Future<void> _capture(Map<String, dynamic> extra) async {
    try {
      await FirebaseFunctions.instance.httpsCallable('captureTripPayment').call({
        'requestId': widget.requestId,
        ...extra,
      });
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('Payment successful. Thank you!', error: false);
      Navigator.of(context).pop(true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e.message ?? 'Payment could not be recorded. Please contact support.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('Payment could not be recorded. Please contact support.');
    }
  }

  void _onSuccess(PaymentSuccessResponse r) {
    final orderId = r.orderId ?? _orderId ?? '';
    if (orderId.isEmpty || (r.signature ?? '').isEmpty || (r.paymentId ?? '').isEmpty) {
      setState(() => _busy = false);
      _toast('Payment could not be verified. Please contact support.');
      return;
    }
    _capture({
      'paymentMethod': 'razorpay',
      'razorpay_order_id': orderId,
      'razorpay_payment_id': r.paymentId,
      'razorpay_signature': r.signature,
    });
  }

  void _onError(PaymentFailureResponse r) {
    if (!mounted) return;
    setState(() => _busy = false);
    _orderId = null;
    _toast(r.message ?? 'Payment failed. Please try again.');
  }

  Future<void> _payWithWallet() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _capture({'paymentMethod': 'wallet', 'idempotencyKey': _idempotencyKey});
  }

  Future<void> _payOnline(int amountDue) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createRazorpayOrder')
          .call({'tripRequestId': widget.requestId});
      final data = (result.data as Map).cast<String, dynamic>();
      _orderId = data['order_id'] as String;
      _razorpay.open({
        'key': kRazorpayKeyId,
        'order_id': _orderId,
        'amount': data['amount'],
        'name': 'MedNU Healthcare',
        'description': 'Ambulance trip',
        'theme': {'color': '#522546'},
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e.message ?? 'Could not start payment. Please try again.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('Could not start payment. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref
        .watch(walletBalanceProvider)
        .maybeWhen(data: (v) => v.toDouble(), orElse: () => 0.0);
    return Scaffold(
      appBar: AppBar(title: const Text('Pay for your trip')),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('service_requests')
              .doc(widget.requestId)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = snap.data!.data() ?? const <String, dynamic>{};
            final status = d['paymentStatus'] as String? ?? '';
            final due = (d['amountDue'] as num?)?.toDouble() ?? 0;
            final fare = (d['fareFinal'] as num?)?.toDouble() ?? 0;
            final fee = (d['platformFee'] as num?)?.toDouble() ?? 0;
            if (status == 'paid') {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('This trip is already paid. Thank you!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 15)),
                ),
              );
            }
            if (status != 'payment_due' || due <= 0) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No payment is due for this booking.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 15)),
                ),
              );
            }
            final canWallet = balance >= due;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Trip completed',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                _row('Trip fare', fare),
                if (fee > 0) _row('Platform fee', fee),
                const Divider(height: 28),
                _row('Total to pay', due, bold: true),
                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _payOnline(due.round()),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Pay ₹${due.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: (_busy || !canWallet) ? null : _payWithWallet,
                    child: Text(
                      canWallet
                          ? 'Pay from wallet (₹${balance.toStringAsFixed(0)})'
                          : 'Wallet balance too low (₹${balance.toStringAsFixed(0)})',
                      style: const TextStyle(fontFamily: 'Poppins'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(String label, double v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: bold ? 16 : 14,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            Text('₹${v.toStringAsFixed(0)}',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: bold ? 18 : 14,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          ],
        ),
      );
}
