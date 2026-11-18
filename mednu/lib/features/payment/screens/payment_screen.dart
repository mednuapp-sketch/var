import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/payment_config.dart';
import '../../../core/services/booking_service.dart';
import '../../wallet/wallet_provider.dart';
import '../../../core/providers/platform_fee_provider.dart';

import '../../../core/router/app_router.dart';
// ─────────────────────────────────────────────────────────────────────────────
//  Constants
// ─────────────────────────────────────────────────────────────────────────────

const _kGreen = Color(0xFF2E7D32);
const _kBlue = Color(0xFF1565C0);
const _kPurple = Color(0xFF6A1B9A);

/// Mirrors `_generateOpRxId` in functions/index.js and `_generateRxId` in
/// the doctor app's write_prescription_screen.dart — same 'MN-YYYYMMDD-
/// XXXXXX' format. Needed here too because `_confirmWithoutPayment` below
/// writes the booking doc directly from the client (whenever
/// kRequirePayment is false) instead of going through the capturePayment
/// Cloud Function where the server-side generator normally runs.
String _generateOpRxId() {
  final now = DateTime.now();
  final date = '${now.year}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rng = Random.secure();
  final suffix =
      List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  return 'MN-$date-$suffix';
}

// ─────────────────────────────────────────────────────────────────────────────
//  PaymentScreen
// ─────────────────────────────────────────────────────────────────────────────

class PaymentScreen extends ConsumerStatefulWidget {
  final String amount;
  final String description;

  /// Single-booking mode (most callers): passed straight through to the
  /// `capturePayment` Cloud Function, which creates the booking doc itself
  /// once the charge is verified — see functions/index.js.
  /// `bookingCollection` is which collection to create it in
  /// (`appointments`, `service_requests`, `orders`, ...); `bookingData` is
  /// written verbatim as that doc's fields (patientId/paymentId/status are
  /// added server-side, don't include them here). Required unless [cartItems]
  /// is set.
  final String? serviceType;
  final String? bookingCollection;
  final Map<String, dynamic>? bookingData;

  /// Cart mode (cart_screen.dart): one charge funding several different
  /// bookings at once. Each entry is shaped like `{ serviceType,
  /// bookingCollection, bookingData, amount }` — [amount]/[serviceType]/
  /// [bookingCollection]/[bookingData] above are ignored when this is set,
  /// and `captureCartPayment` is called instead of `capturePayment`. The
  /// displayed total is the sum of each item's `amount`.
  final List<Map<String, dynamic>>? cartItems;

  const PaymentScreen({
    super.key,
    this.amount = '520',
    this.description = 'Consultation with MedNU',
    this.serviceType,
    this.bookingCollection,
    this.bookingData,
    this.cartItems,
  }) : assert(
         cartItems != null ||
             (serviceType != null && bookingCollection != null && bookingData != null),
         'Either cartItems, or serviceType + bookingCollection + bookingData, is required.',
       );

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen>
    with SingleTickerProviderStateMixin {
  late final Razorpay _razorpay;
  late final AnimationController _successCtrl;

  String _selectedMethod = 'upi';
  bool _useWallet = false;
  bool _useMednuMoney = false;
  bool _isProcessing = false;
  bool _showPromoField = false;
  bool _promoApplied = false;
  bool _promoValidating = false;
  String _promoCode = '';
  int _promoDiscount = 0;
  String? _pendingOrderId;

  // Stable for this screen instance's lifetime — reused across retries of
  // the same payment attempt so a flaky-network retry can never double-book
  // or double-charge (capturePayment dedupes on this exact string).
  // (Non-final only so a successful wallet refund can start a fresh attempt.)
  String _idempotencyKey = DateTime.now().microsecondsSinceEpoch.toString();

  // In-app balance legs already debited for this payment attempt (null = not
  // yet). Lets a retry after a failed capture reuse them instead of debiting
  // again or, worse, sending the customer to the gateway for money they have
  // already paid.
  int? _settledMednuMoney;
  int? _settledWallet;
  int get _settledTotal => (_settledMednuMoney ?? 0) + (_settledWallet ?? 0);

  final _upiController = TextEditingController();
  final _promoController = TextEditingController();

  // ── Payment methods ────────────────────────────────────
  static const _paymentMethods = [
    _PayMethod(
      id: 'upi',
      name: 'UPI',
      desc: 'GPay, PhonePe, Paytm & more',
      icon: Icons.account_balance_rounded,
      color: _kGreen,
    ),
    _PayMethod(
      id: 'card',
      name: 'Credit / Debit Card',
      desc: 'Visa, Mastercard, RuPay',
      icon: Icons.credit_card_rounded,
      color: _kBlue,
    ),
    _PayMethod(
      id: 'netbanking',
      name: 'Net Banking',
      desc: 'All major banks supported',
      icon: Icons.account_balance_wallet_rounded,
      color: _kPurple,
    ),
  ];

  // ── Computed balances ──────────────────────────────────
  int get _walletBalance {
    final b = ref.watch(walletBalanceProvider);
    return b.maybeWhen(data: (v) => v.toInt(), orElse: () => 0);
  }

  int get _mednuMoneyBalance {
    final b = ref.watch(mednuMoneyBalanceProvider);
    return b.maybeWhen(data: (v) => v.toInt(), orElse: () => 0);
  }

  // ── Platform fee (central; per service, admin-controlled) ──
  // The callers pass BASE prices only. Free (<= 0) bookings never get a fee.
  int _baseOf(num? v) => (v ?? 0).round();
  // [bookingData] lets the fee honour a partner-specific override (the
  // provider id is derived exactly as the server does in capturePayment).
  int _feeForBase(int base, String? serviceType, [Map? bookingData]) => base <= 0
      ? 0
      : platformFeeFor(ref, serviceType,
          providerId: feeProviderIdFor(serviceType, bookingData));
  Map? _itemBookingData(Map it) =>
      it['bookingData'] is Map ? it['bookingData'] as Map : null;

  int get _baseAmount => widget.cartItems != null
      ? widget.cartItems!.fold<int>(0, (s, it) => s + _baseOf(num.tryParse(it['amount'].toString())))
      : int.tryParse(widget.amount) ?? 0;

  /// Platform fee for the whole order (one fee per cart entry in cart mode).
  int get _platformFee => widget.cartItems != null
      ? widget.cartItems!.fold<int>(
          0,
          (s, it) =>
              s +
              _feeForBase(_baseOf(num.tryParse(it['amount'].toString())),
                  it['serviceType']?.toString(), _itemBookingData(it)))
      : _feeForBase(_baseAmount, widget.serviceType, widget.bookingData);

  /// Cart entries with the platform fee folded into each item's `amount`, so
  /// captureCartPayment's sum / coupon proration covers base + fee.
  List<Map<String, dynamic>> get _cartItemsWithFee => [
        for (final it in widget.cartItems!)
          {
            ...it,
            'amount': _baseOf(num.tryParse(it['amount'].toString())) +
                _feeForBase(_baseOf(num.tryParse(it['amount'].toString())),
                    it['serviceType']?.toString(), _itemBookingData(it)),
          },
      ];

  int get _totalAmount => _baseAmount + _platformFee;
  int get _afterPromo => (_totalAmount - _promoDiscount).clamp(0, _totalAmount);
  int get _mednuMoneyDeduction =>
      _useMednuMoney ? _afterPromo.clamp(0, _mednuMoneyBalance) : 0;
  int get _afterMednuMoney =>
      (_afterPromo - _mednuMoneyDeduction).clamp(0, _afterPromo);
  int get _walletDeduction =>
      _useWallet ? _afterMednuMoney.clamp(0, _walletBalance) : 0;
  int get _amountAfterWallet =>
      (_afterMednuMoney - _walletDeduction).clamp(0, _totalAmount);

  // ── Lifecycle ──────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _razorpay.clear();
    _upiController.dispose();
    _promoController.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  // ── Capture (single-booking or cart mode) ──────────────
  // Calls `capturePayment` (single booking) or `captureCartPayment` (this
  // screen was opened with [cartItems]) — same verification/coupon contract
  // either way, see functions/index.js.
  Future<Map<String, dynamic>> _capture({
    required String paymentMethod,
    required int walletPortionAmount,
    String? razorpayOrderId,
    String? razorpayPaymentId,
    String? razorpaySignature,
    String? idempotencyKey,
  }) async {
    final isCart = widget.cartItems != null;
    final payload = <String, dynamic>{
      if (_promoApplied) 'couponCode': _promoCode,
      'paymentMethod': paymentMethod,
      'walletPortionAmount': walletPortionAmount,
      if (razorpayOrderId != null) 'razorpay_order_id': razorpayOrderId,
      if (razorpayPaymentId != null) 'razorpay_payment_id': razorpayPaymentId,
      if (razorpaySignature != null) 'razorpay_signature': razorpaySignature,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
      // Razorpay + wallet portion: lets the server prove the claimed wallet
      // portion from the `$_idempotencyKey-mm` / `-w` ledger debits.
      if (paymentMethod == 'razorpay') 'walletDebitKey': _idempotencyKey,
    };
    if (isCart) {
      payload['items'] = _cartItemsWithFee;
    } else {
      payload['serviceType'] = widget.serviceType;
      payload['bookingCollection'] = widget.bookingCollection;
      payload['bookingData'] = widget.bookingData;
      payload['originalAmount'] = _totalAmount;
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable(isCart ? 'captureCartPayment' : 'capturePayment')
        .call(payload);
    return ((result.data as Map?) ?? const {}).cast<String, dynamic>();
  }

  // ── Booking without a real charge ───────────────────────
  // Used unconditionally whenever `kRequirePayment` is false (see
  // payment_config.dart), and also wired to the debug-only "Skip Payment"
  // button so QA can still bypass a live gateway once `kRequirePayment` is
  // flipped back on. Writes the booking doc(s) directly, deliberately
  // WITHOUT a paymentId, so the settlement engine (which only acts on
  // payments a paymentId points to) never sees these — no fake
  // payments/wallet_ledger/commission entries, nothing for the real
  // Settlement Dashboard to pick up. The doc shape otherwise matches exactly
  // what `capturePayment` writes server-side (functions/index.js), so it
  // reflects in MedNU Doctor/Service the same way a paid booking would.
  Future<void> _confirmWithoutPayment() async {
    if (_isProcessing) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showError('Sign in to continue.');
      return;
    }
    setState(() => _isProcessing = true);
    try {
      // Switch ON: firestore.rules deny client creates of booking docs, so a
      // free booking is created by the `createFreeBooking` callable, which
      // verifies the real price is zero (a priced booking is refused with
      // "This booking requires payment."). The keys are stable per screen
      // instance, so a retry returns the same booking(s) instead of duplicating.
      if (PaymentConfig.requirePayment) {
        if (widget.cartItems != null) {
          final payments = <Map<String, dynamic>>[];
          var i = 0;
          for (final item in widget.cartItems!) {
            final id = await BookingService.createFreeBooking(
              serviceType: item['serviceType'].toString(),
              bookingCollection: item['bookingCollection'] as String,
              bookingData: (item['bookingData'] as Map).cast<String, dynamic>(),
              idempotencyKey: 'pay-$_idempotencyKey-${i++}',
            );
            payments.add({
              'bookingId': id,
              'bookingCollection': item['bookingCollection'],
              'serviceType': item['serviceType'],
              'paidAmount': 0,
            });
          }
          if (!mounted) return;
          setState(() => _isProcessing = false);
          _showSuccessSheet('NOPAY-$_idempotencyKey', cartPayments: payments);
        } else {
          final id = await BookingService.createFreeBooking(
            serviceType: widget.serviceType!,
            bookingCollection: widget.bookingCollection!,
            bookingData: widget.bookingData!,
            idempotencyKey: 'pay-$_idempotencyKey',
          );
          if (!mounted) return;
          setState(() => _isProcessing = false);
          _showSuccessSheet('NOPAY-$_idempotencyKey', bookingId: id);
        }
        return;
      }
      final db = FirebaseFirestore.instance;
      if (widget.cartItems != null) {
        final payments = <Map<String, dynamic>>[];
        // One atomic batch: a failure part-way through must not leave some of
        // the cart's bookings created (the patient would see an error, retry
        // and end up with duplicates of the ones that did go through).
        final batch = db.batch();
        for (final item in widget.cartItems!) {
          final itemBookingData = (item['bookingData'] as Map).cast<String, dynamic>();
          final isInPersonAppointment = item['bookingCollection'] == 'appointments' &&
              itemBookingData['consultationType'] == 'In-Person';
          final itemBase = _baseOf(num.tryParse(item['amount'].toString()));
          final itemFee = _feeForBase(itemBase, item['serviceType']?.toString(), itemBookingData);
          final ref = db.collection(item['bookingCollection'] as String).doc();
          batch.set(ref, {
            ...itemBookingData,
            // `amount` stays the BASE price (provider earnings read it); the
            // platform's fee is recorded separately.
            'platformFee': itemFee,
            'baseAmount': itemBase,
            if (isInPersonAppointment) 'rxId': _generateOpRxId(),
            'patientId': uid,
            'paymentStatus': 'not_required',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          payments.add({
            'bookingId': ref.id,
            'bookingCollection': item['bookingCollection'],
            'serviceType': item['serviceType'],
            'paidAmount': itemBase + itemFee,
          });
        }
        await batch.commit();
        if (!mounted) return;
        setState(() => _isProcessing = false);
        _showSuccessSheet('NOPAY-$_idempotencyKey', cartPayments: payments);
      } else {
        final isInPersonAppointment = widget.bookingCollection == 'appointments' &&
            widget.bookingData!['consultationType'] == 'In-Person';
        final ref = db.collection(widget.bookingCollection!).doc();
        await ref.set({
          ...widget.bookingData!,
          // `amount` stays the BASE price (provider earnings read it); the
          // platform's fee is recorded separately.
          'platformFee': _platformFee,
          'baseAmount': _baseAmount,
          if (isInPersonAppointment) 'rxId': _generateOpRxId(),
          'patientId': uid,
          'paymentStatus': 'not_required',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (!mounted) return;
        setState(() => _isProcessing = false);
        _showSuccessSheet('NOPAY-$_idempotencyKey', bookingId: ref.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showError(
          'Could not confirm booking: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  // ── Razorpay handlers ──────────────────────────────────
  void _onSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    final paymentId = response.paymentId ?? '';
    final orderId = response.orderId ?? _pendingOrderId ?? '';
    final signature = response.signature ?? '';

    if (orderId.isEmpty || signature.isEmpty || paymentId.isEmpty) {
      setState(() => _isProcessing = false);
      _showError('Payment could not be verified. Please contact support.');
      return;
    }

    // The gateway leg has already been charged, so a failed in-app debit
    // can't undo it — record it best-effort, and if it genuinely failed,
    // tell capturePayment nothing was actually covered from the wallet
    // (rather than claiming an amount that never moved) so its own
    // gateway-order cross-check can catch the shortfall instead of silently
    // under-recording what was collected.
    final intendedWalletPortion = _mednuMoneyDeduction + _walletDeduction;
    final balanceError = await _applyBalanceDeductions();
    if (!mounted) return;
    final walletPortion = balanceError == null ? intendedWalletPortion : 0;

    try {
      final data = await _capture(
        paymentMethod: 'razorpay',
        walletPortionAmount: walletPortion,
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId,
        razorpaySignature: signature,
      );
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSuccessSheet(
        paymentId,
        bookingId: data['bookingId'] as String?,
        capturedPaymentId: data['paymentId'] as String?,
        cartPayments: (data['payments'] as List?)?.cast<Map>().map((m) => m.cast<String, dynamic>()).toList(),
      );
    } on FirebaseFunctionsException catch (e) {
      final refunded = await _refundSettledDebits(e, razorpayPaymentId: paymentId);
      if (!mounted) return;
      setState(() => _isProcessing = false);
      // The server refunds a gateway charge it could not book (see
      // _withCaptureRefund). Signature / ownership rejections are not refund
      // cases, so those keep the server's own message.
      final notRefundCase =
          e.code == 'unauthenticated' || e.code == 'permission-denied';
      final msg = notRefundCase
          ? (e.message ?? _paymentNotCompletedMsg)
          : _paymentNotCompletedMsg;
      _showError(refunded ? '$msg $_walletRefundedNote' : msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showError(_paymentNotCompletedMsg);
    }
  }

  void _onError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    _pendingOrderId = null;
    _showError(response.message ?? 'Payment failed. Please try again.');
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    _showSnackBar('Opening ${response.walletName}…', AppColors.info);
  }

  // ── In-app balance debits ──────────────────────────────
  /// Debits whichever in-app balances the patient chose to apply to this
  /// payment. Both balances were only ever *subtracted from the amount
  /// charged* before — they were never actually taken off the user's
  /// balance for the wallet, and not at all on the wallet-only path, so the
  /// same balance could be spent over and over. Returns an error message on
  /// failure, or null on success.
  Future<String?> _applyBalanceDeductions() async {
    // Read (not watch) the balances here — this runs outside build, from the
    // Razorpay callback.
    final mednuMoneyBalance = ref
        .read(mednuMoneyBalanceProvider)
        .maybeWhen(data: (v) => v.toInt(), orElse: () => 0);
    final walletBalance = ref
        .read(walletBalanceProvider)
        .maybeWhen(data: (v) => v.toInt(), orElse: () => 0);

    // A leg that was already debited on an earlier attempt of this same
    // payment (capture failed afterwards) keeps its amount and is NOT debited
    // again — the live balances have already dropped by it, so recomputing
    // from them would be wrong.
    final mednuMoney = _settledMednuMoney ??
        (_useMednuMoney ? _afterPromo.clamp(0, mednuMoneyBalance) : 0);
    final afterMednuMoney = (_afterPromo - mednuMoney).clamp(0, _afterPromo);
    final wallet = _settledWallet ??
        (_useWallet ? afterMednuMoney.clamp(0, walletBalance) : 0);
    final service = ref.read(walletServiceProvider);

    if (mednuMoney > 0 && _settledMednuMoney == null) {
      try {
        await service.deductMednuMoney(
          amount: mednuMoney.toDouble(),
          title: 'MedNU Money Used',
          category: 'consultation',
          description: widget.description,
          idempotencyKey: '$_idempotencyKey-mm',
        );
        _settledMednuMoney = mednuMoney;
      } catch (_) {
        return 'Could not apply your MedNU Money balance. Please try again.';
      }
    }

    if (wallet > 0 && _settledWallet == null) {
      try {
        await service.deductPayment(
          amount: wallet.toDouble(),
          title: 'Wallet Payment',
          category: 'payment',
          description: widget.description,
          idempotencyKey: '$_idempotencyKey-w',
        );
        _settledWallet = wallet;
      } catch (_) {
        return 'Could not debit your wallet. Please try again.';
      }
    }
    return null;
  }

  static const String _paymentNotCompletedMsg =
      'Your payment could not be completed. If money was deducted it will be '
      'refunded to your original payment method automatically.';

  static const String _walletRefundedNote =
      'We refunded the amount taken from your wallet.';

  /// Capture failed after wallet / MedNU Money legs were debited: ask the
  /// server (`refundWalletSpend`) to credit them back exactly once. Only done
  /// for a DEFINITE failure — an ambiguous one (timeout / network) may have
  /// recorded the booking, so those keep the safe "tap Pay again" retry path.
  /// Returns true when the money was returned; false keeps the existing
  /// retry message (including when the refund call itself fails).
  Future<bool> _refundSettledDebits(
    FirebaseFunctionsException e, {
    String? razorpayPaymentId,
  }) async {
    if (_settledTotal <= 0) return false;
    const ambiguous = {
      'unavailable', 'deadline-exceeded', 'unknown', 'cancelled', 'internal', 'aborted',
    };
    if (ambiguous.contains(e.code)) return false;
    try {
      await FirebaseFunctions.instance.httpsCallable('refundWalletSpend').call({
        'idempotencyKey': _idempotencyKey,
        if (razorpayPaymentId != null) 'razorpayPaymentId': razorpayPaymentId,
      });
      // Those debits are reversed: start a fresh attempt so a retry debits
      // again under new keys instead of reusing the (reversed) ones.
      _settledMednuMoney = null;
      _settledWallet = null;
      _idempotencyKey = DateTime.now().microsecondsSinceEpoch.toString();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// When part of the payment was already debited from the in-app balances
  /// and the booking could not be recorded, tell the customer plainly that
  /// retrying is safe (same idempotency keys -> no second debit/booking).
  String _debitedNote(String base) => _settledTotal > 0
      ? '$base ₹$_settledTotal was already taken from your wallet balance for '
          'this booking; tap Pay again to finish it — you will not be charged twice. '
          'If it keeps failing, contact support.'
      : base;

  // ── Open Razorpay ──────────────────────────────────────
  Future<void> _openRazorpay() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Fully covered by wallet / MedNU Money — no gateway leg at all, so the
    // in-app debit is the *only* thing that moves money here. It must
    // succeed before we report success, or the patient gets a free order.
    final alreadyDebitedInFull = _settledTotal > 0 && _settledTotal >= _afterPromo;
    if (_amountAfterWallet <= 0 || alreadyDebitedInFull) {
      final walletPortion = _afterPromo;

      // Wallet-only (no MedNU Money leg, nothing debited yet): let
      // capturePayment/captureCartPayment debit the main wallet itself,
      // atomically in the same transaction that creates the booking — there
      // is no window where money is taken but no booking exists.
      final atomicWallet = _useWallet &&
          _afterPromo > 0 &&
          _mednuMoneyDeduction == 0 &&
          _settledTotal == 0 &&
          _walletDeduction >= _afterPromo;

      if (!atomicWallet) {
        final error = await _applyBalanceDeductions();
        if (!mounted) return;
        if (error != null) {
          setState(() => _isProcessing = false);
          _showError(error);
          return;
        }
      }

      try {
        final data = await _capture(
          paymentMethod: atomicWallet ? 'wallet' : 'already_settled',
          walletPortionAmount: walletPortion,
          idempotencyKey: _idempotencyKey,
        );
        if (!mounted) return;
        setState(() => _isProcessing = false);
        _showSuccessSheet(
          'WALLET-$_idempotencyKey',
          bookingId: data['bookingId'] as String?,
          capturedPaymentId: data['paymentId'] as String?,
          cartPayments: (data['payments'] as List?)?.cast<Map>().map((m) => m.cast<String, dynamic>()).toList(),
        );
      } on FirebaseFunctionsException catch (e) {
        final refunded = await _refundSettledDebits(e);
        if (!mounted) return;
        setState(() => _isProcessing = false);
        final msg = e.message ?? 'Could not complete payment. Please try again.';
        _showError(refunded ? '$msg $_walletRefundedNote' : _debitedNote(msg));
      } catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);
        _showError(_debitedNote('Could not complete payment. Please try again.'));
      }
      return;
    }

    String orderId;
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createRazorpayOrder')
          .call({
        'amount': _amountAfterWallet * 100,
        'currency': 'INR',
        // Checkout leg, not a wallet top-up — the server records the purpose on
        // the order so verifyRazorpayPayment knows not to credit the wallet.
        'purpose': 'checkout',
        'receipt': 'mednu_${DateTime.now().millisecondsSinceEpoch}',
        // Booking context so the server can reject a stale/tampered price
        // BEFORE the customer is charged (see createRazorpayOrder).
        if (widget.cartItems != null)
          'items': _cartItemsWithFee
        else ...{
          'serviceType': widget.serviceType,
          'bookingCollection': widget.bookingCollection,
          'bookingData': widget.bookingData,
          'originalAmount': _totalAmount,
        },
      });
      orderId = (result.data as Map)['order_id'] as String;
      _pendingOrderId = orderId;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showError('Could not initiate payment. Please try again.');
      return;
    }

    final prefill = <String, dynamic>{'contact': '', 'email': ''};
    if (_selectedMethod == 'upi') {
      final vpa = _upiController.text.trim();
      if (vpa.isNotEmpty) prefill['vpa'] = vpa;
    }

    final options = <String, dynamic>{
      'key': kRazorpayKeyId,
      'order_id': orderId,
      'amount': _amountAfterWallet * 100,
      'name': 'MedNU Healthcare',
      'description': widget.description,
      'prefill': prefill,
      'theme': {'color': '#522546'},
      'external': {
        'wallets': ['paytm', 'phonepe']
      },
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showError('Could not open payment modal: $e');
    }
  }

  // ── Promo code ─────────────────────────────────────────
  // Server-validated via the `validateCoupon` callable (functions/index.js) —
  // the discount shown here is a live preview only; capturePayment
  // re-validates and re-computes it independently at the moment of payment,
  // so a coupon that expires or hits its usage limit between the preview
  // and the actual charge is caught there, not trusted from this call.
  Future<void> _applyPromo() async {
    final code = _promoController.text.trim().toUpperCase();
    if (code.isEmpty || _promoValidating) return;
    setState(() => _promoValidating = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('validateCoupon')
          .call({
        'couponCode': code,
        // Cart mode has no single serviceType (it was null here, so any coupon
        // restricted to specific services was wrongly rejected at preview).
        // _applyCoupon accepts an array and requires every item be covered —
        // the same check captureCartPayment applies at charge time.
        'serviceType': widget.cartItems != null
            ? widget.cartItems!.map((it) => it['serviceType']).toSet().toList()
            : widget.serviceType,
        'orderAmount': _totalAmount,
      });
      if (!mounted) return;
      final data = (result.data as Map?) ?? const {};
      final discount = ((data['discount'] as num?) ?? 0).round();
      setState(() {
        _promoApplied = true;
        _promoCode = code;
        _promoDiscount = discount;
        _showPromoField = false;
        _promoValidating = false;
      });
      _showSnackBar('Coupon applied! ₹$discount discount added.', _kGreen);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _promoValidating = false);
      _showSnackBar(e.message ?? 'Invalid coupon code.', AppColors.error);
    } catch (e) {
      if (!mounted) return;
      setState(() => _promoValidating = false);
      _showSnackBar('Could not validate coupon. Please try again.', AppColors.error);
    }
  }

  void _removePromo() {
    setState(() {
      _promoApplied = false;
      _promoCode = '';
      _promoDiscount = 0;
      _promoController.clear();
    });
  }

  // ── Helpers ────────────────────────────────────────────
  void _showError(String message) {
    if (!mounted) return;
    _showSnackBar(message, AppColors.error);
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Keep the fee live (admin can change it while this screen is open).
    ref.watch(platformFeeConfigProvider);
    // Rebuild when the real-payments switch (app_config/payments) flips.
    ref.watch(requirePaymentProvider);
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOrderSummary(),
                const SizedBox(height: 16),
                if (!PaymentConfig.requirePayment) ...[
                  _buildNoPaymentNote(),
                ] else ...[
                  if (_mednuMoneyBalance > 0) ...[
                    _buildBalanceToggle(
                      label: 'MedNU Money',
                      subLabel:
                          'Available: ₹$_mednuMoneyBalance  •  Bookings only',
                      icon: Icons.stars_rounded,
                      iconColor: Colors.amber,
                      gradient: const LinearGradient(
                        colors: [_kPurple, Color(0xFFAB47BC)],
                      ),
                      active: _useMednuMoney,
                      activeColor: _kPurple,
                      onChanged: (v) => setState(() => _useMednuMoney = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildBalanceToggle(
                    label: 'MedNU Wallet',
                    subLabel: 'Available: ₹$_walletBalance',
                    icon: Icons.account_balance_wallet_rounded,
                    iconColor: Colors.white,
                    gradient: AppColors.primaryGradient,
                    active: _useWallet,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setState(() => _useWallet = v),
                  ),
                  const SizedBox(height: 16),
                  _buildPromoSection(),
                  const SizedBox(height: 20),
                  const Text('Payment Method', style: AppTextStyles.h4),
                  const SizedBox(height: 12),
                  ..._paymentMethods.map(_buildMethodTile),
                  if (_selectedMethod == 'upi') ...[
                    const SizedBox(height: 10),
                    _buildUpiInput(),
                  ],
                  const SizedBox(height: 12),
                  _buildSecurityNote(),
                  const SizedBox(height: 20),
                  _buildSecureFooter(),
                ],
              ],
            ),
          ),

          // ── Sticky pay button ──────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildPayButton(),
          ),

          // ── Full-screen processing overlay ─────────────
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: const Center(
                child: _ProcessingIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: const Text('Secure Payment',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            fontWeight: FontWeight.w700,
          )),
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        tooltip: 'Back',
        onPressed: () => context.safeBack(),
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: 14, color: _kGreen),
              SizedBox(width: 4),
              Text(
                'SSL',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _kGreen,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Order Summary ──────────────────────────────────────
  Widget _buildOrderSummary() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.appBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Order Summary', style: AppTextStyles.h4),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.medical_services_rounded,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.description,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: context.appTextPrimary,
                      )),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SummaryRow('Subtotal', '₹$_baseAmount'),
          if (_platformFee > 0) ...[
            const SizedBox(height: 8),
            _SummaryRow('Platform fee', '₹$_platformFee'),
          ],
          if (_promoApplied) ...[
            const SizedBox(height: 8),
            _SummaryRow(
              'Promo ($_promoCode)',
              '-₹$_promoDiscount',
              valueColor: _kGreen,
            ),
          ],
          if (_useMednuMoney && _mednuMoneyDeduction > 0) ...[
            const SizedBox(height: 8),
            _SummaryRow(
              'MedNU Money',
              '-₹$_mednuMoneyDeduction',
              valueColor: _kPurple,
            ),
          ],
          if (_useWallet && _walletDeduction > 0) ...[
            const SizedBox(height: 8),
            _SummaryRow(
              'Wallet',
              '-₹$_walletDeduction',
              valueColor: _kGreen,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Payable',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  )),
              Text(
                '₹$_amountAfterWallet',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          if (_amountAfterWallet < _totalAmount) ...[
            const SizedBox(height: 4),
            Text(
              'You save ₹${_totalAmount - _amountAfterWallet} on this order',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: _kGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Balance Toggle ─────────────────────────────────────
  Widget _buildBalanceToggle({
    required String label,
    required String subLabel,
    required IconData icon,
    required Color iconColor,
    required Gradient gradient,
    required bool active,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active ? activeColor.withValues(alpha: 0.04) : context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? activeColor.withValues(alpha: 0.4)
              : context.appBorder,
          width: active ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(
                  subLabel,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: active ? activeColor : context.appTextSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: active,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: activeColor,
          ),
        ],
      ),
    );
  }

  // ── Promo Section ──────────────────────────────────────
  Widget _buildPromoSection() {
    if (_promoApplied) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kGreen.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_offer_rounded,
                  color: _kGreen, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Promo "$_promoCode" applied',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kGreen,
                    ),
                  ),
                  Text(
                    '₹$_promoDiscount discount applied to total',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: _kGreen,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _removePromo,
              style:
                  TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text(
                'Remove',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _showPromoField = !_showPromoField),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _showPromoField
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : context.appBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.local_offer_outlined,
                  color: _showPromoField
                      ? AppColors.primary
                      : context.appTextSecondary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Have a promo code?',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: _showPromoField
                          ? AppColors.primary
                          : context.appTextSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  _showPromoField
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: context.appTextHint,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _showPromoField
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _promoController,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter code',
                            hintStyle: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              letterSpacing: 0,
                              fontWeight: FontWeight.w400,
                            ),
                            prefixIcon: const Icon(
                                Icons.confirmation_number_rounded,
                                size: 18,
                                color: AppColors.primary),
                            filled: true,
                            fillColor: context.appSurface,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: context.appBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: context.appBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: AppColors.primary, width: 2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _promoValidating ? null : _applyPromo,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18),
                          ),
                          child: _promoValidating
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Text(
                                  'Apply',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── Method tile ────────────────────────────────────────
  Widget _buildMethodTile(_PayMethod method) {
    final selected = _selectedMethod == method.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              selected ? method.color.withValues(alpha: 0.05) : context.appSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? method.color : context.appBorder,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: method.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(method.icon, color: method.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.name,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? method.color
                          : context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(method.desc, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? method.color : context.appBorder,
                  width: 2,
                ),
                color: selected ? method.color : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── UPI Input ──────────────────────────────────────────
  Widget _buildUpiInput() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGreen.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_rounded, size: 15, color: _kGreen),
              SizedBox(width: 8),
              Text(
                'Enter UPI ID (optional)',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _kGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _upiController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'yourname@upi',
              prefixIcon: const Icon(Icons.alternate_email_rounded,
                  size: 18, color: _kGreen),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.appBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.appBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kGreen, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Leave blank — Razorpay shows GPay, PhonePe & other options automatically.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              color: context.appTextHint,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── No-payment-required note ────────────────────────────
  Widget _buildNoPaymentNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGreen.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.verified_rounded, color: _kGreen, size: 18),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No payment required right now',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _kGreen,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Confirm to complete your booking instantly.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: Color(0xFF374151),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Security Note ──────────────────────────────────────
  Widget _buildSecurityNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBlue.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.lock_rounded, color: _kBlue, size: 18),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure Razorpay Checkout',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _kBlue,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Your payment details are entered directly in Razorpay\'s encrypted window — we never see your card or UPI credentials.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: Color(0xFF374151),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Secure Footer ──────────────────────────────────────
  Widget _buildSecureFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_rounded, size: 12, color: context.appTextHint),
        const SizedBox(width: 5),
        Text(
          '100% Secure · Powered by Razorpay · SSL Encrypted',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 10,
            color: context.appTextHint,
          ),
        ),
      ],
    );
  }

  // ── Pay Button ─────────────────────────────────────────
  Widget _buildPayButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      decoration: BoxDecoration(
        color: context.appSurface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isProcessing
                  ? null
                  : (PaymentConfig.requirePayment && _totalAmount > 0
                      ? _openRazorpay
                      : _confirmWithoutPayment),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PaymentConfig.requirePayment ? Icons.lock_rounded : Icons.check_circle_rounded,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          (!PaymentConfig.requirePayment || _totalAmount <= 0)
                              ? 'Confirm Booking'
                              : (_amountAfterWallet <= 0
                                  ? 'Complete with Wallet'
                                  : 'Pay ₹$_amountAfterWallet'),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          // Debug-only shortcut for QA once PaymentConfig.requirePayment is flipped back
          // on — kDebugMode is compiled out entirely in release builds, so
          // this button is physically absent from anything shipped to a real
          // user or app store. When PaymentConfig.requirePayment is already false the
          // main button above does the same thing, so this stays hidden.
          if (PaymentConfig.requirePayment && kDebugMode) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: _isProcessing ? null : _confirmWithoutPayment,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  side: BorderSide(color: AppColors.warning.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  '🧪 Skip Payment (Test Mode — Debug Builds Only)',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Success Sheet ──────────────────────────────────────
  // Pops with the newly-created booking/payment ids (capturePayment creates
  // the booking doc itself — see PaymentScreen's class doc) so the caller can
  // navigate straight to it instead of re-deriving it from a local write.
  void _showSuccessSheet(
    String paymentId, {
    String? bookingId,
    String? capturedPaymentId,
    List<Map<String, dynamic>>? cartPayments,
  }) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SuccessSheet(
        amount: _totalAmount.toString(),
        paymentId: paymentId,
        description: widget.description,
        onDone: () => Navigator.pop(sheetContext),
      ),
    ).then((_) {
      if (mounted) {
        context.pop({
          'bookingId': bookingId,
          'paymentId': capturedPaymentId ?? paymentId,
          if (cartPayments != null) 'payments': cartPayments,
        });
      }
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Payment method model
// ─────────────────────────────────────────────────────────────────────────────

class _PayMethod {
  final String id, name, desc;
  final IconData icon;
  final Color color;
  const _PayMethod({
    required this.id,
    required this.name,
    required this.desc,
    required this.icon,
    required this.color,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Processing Indicator
// ─────────────────────────────────────────────────────────────────────────────

class _ProcessingIndicator extends StatelessWidget {
  const _ProcessingIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 56, height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Processing Payment',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.appTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Please do not close this screen',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: context.appTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Success Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SuccessSheet extends StatefulWidget {
  final String amount, paymentId, description;
  final VoidCallback onDone;
  const _SuccessSheet({
    required this.amount,
    required this.paymentId,
    required this.description,
    required this.onDone,
  });

  @override
  State<_SuccessSheet> createState() => _SuccessSheetState();
}

class _SuccessSheetState extends State<_SuccessSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  // Nothing was charged: test mode, or a real-payments booking whose total is 0
  // (e.g. a 100% coupon). Shown as 'Booking Confirmed', never 'Payment Successful'.
  bool get _noCharge =>
      !PaymentConfig.requirePayment || (double.tryParse(widget.amount) ?? 1) <= 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),

          // Animated checkmark
          ScaleTransition(
            scale: _scale,
            child: Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 48),
            ),
          ),

          const SizedBox(height: 20),
          FadeTransition(
            opacity: _fade,
            child: Column(
              children: [
                Text(
                  !_noCharge ? 'Payment Successful!' : 'Booking Confirmed!',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  !_noCharge
                      ? '₹${widget.amount} paid successfully'
                      : 'Your booking is confirmed',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: context.appTextSecondary,
                  ),
                ),
                const SizedBox(height: 24),

                // Receipt card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.appBackground,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _ReceiptRow('Service', widget.description),
                      const SizedBox(height: 8),
                      _ReceiptRow(
                        !_noCharge ? 'Amount Paid' : 'Amount',
                        !_noCharge
                            ? '₹${widget.amount}'
                            : (PaymentConfig.requirePayment ? 'No charge' : 'No charge (test mode)'),
                      ),
                      const SizedBox(height: 8),
                      _ReceiptRow(
                        !_noCharge ? 'Transaction ID' : 'Booking reference',
                        widget.paymentId.length > 16
                            ? '${widget.paymentId.substring(0, 16)}…'
                            : widget.paymentId,
                      ),
                      const SizedBox(height: 8),
                      _ReceiptRow(
                        'Date',
                        _formatDate(DateTime.now()),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: widget.onDone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label, value;
  const _ReceiptRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: context.appTextSecondary,
            )),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.appTextPrimary,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Summary row
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;

  const _SummaryRow(
    this.label,
    this.value, {
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodyMedium),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: AppTextStyles.labelMedium.copyWith(
                color: valueColor ?? context.appTextPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
