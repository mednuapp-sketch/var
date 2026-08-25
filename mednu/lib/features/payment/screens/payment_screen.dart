import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../wallet/wallet_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Constants
// ─────────────────────────────────────────────────────────────────────────────

const _kRazorpayKeyId = 'rzp_test_T1Z9EVjv8paYQ2';
const _kGreen = Color(0xFF2E7D32);
const _kBlue = Color(0xFF1565C0);
const _kPurple = Color(0xFF6A1B9A);

// ─────────────────────────────────────────────────────────────────────────────
//  PaymentScreen
// ─────────────────────────────────────────────────────────────────────────────

class PaymentScreen extends ConsumerStatefulWidget {
  final String amount;
  final String description;

  const PaymentScreen({
    super.key,
    this.amount = '520',
    this.description = 'Consultation with MedNU',
  });

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
  String _promoCode = '';
  int _promoDiscount = 0;
  String? _pendingOrderId;

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

  int get _totalAmount => int.tryParse(widget.amount) ?? 0;
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

  // ── Razorpay handlers ──────────────────────────────────
  void _onSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    final paymentId = response.paymentId ?? '';
    final orderId = response.orderId ?? _pendingOrderId ?? '';
    final signature = response.signature ?? '';

    // The card/UPI leg has already been charged, so a failed in-app debit
    // can't undo anything — record it best-effort and carry on.
    await _applyBalanceDeductions();
    if (!mounted) return;

    if (orderId.isEmpty || signature.isEmpty) {
      setState(() => _isProcessing = false);
      _showSuccessSheet(
        paymentId.isNotEmpty
            ? paymentId
            : 'WALLET-${DateTime.now().millisecondsSinceEpoch}',
      );
      return;
    }

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyRazorpayPayment')
          .call({
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });
      if (!mounted) return;
      setState(() => _isProcessing = false);
      if ((result.data as Map?)?['verified'] == true) {
        _showSuccessSheet(paymentId);
      } else {
        _showError('Payment could not be verified. Please contact support.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showError('Verification failed. Contact support with ID: $paymentId');
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

    final mednuMoney = _useMednuMoney ? _afterPromo.clamp(0, mednuMoneyBalance) : 0;
    final afterMednuMoney = (_afterPromo - mednuMoney).clamp(0, _afterPromo);
    final wallet = _useWallet ? afterMednuMoney.clamp(0, walletBalance) : 0;
    final service = ref.read(walletServiceProvider);

    if (mednuMoney > 0) {
      try {
        await service.deductMednuMoney(
          amount: mednuMoney.toDouble(),
          title: 'MedNU Money Used',
          category: 'consultation',
          description: widget.description,
        );
      } catch (_) {
        return 'Could not apply your MedNU Money balance. Please try again.';
      }
    }

    if (wallet > 0) {
      try {
        await service.deductPayment(
          amount: wallet.toDouble(),
          title: 'Wallet Payment',
          category: 'payment',
          description: widget.description,
        );
      } catch (_) {
        return 'Could not debit your wallet. Please try again.';
      }
    }
    return null;
  }

  // ── Open Razorpay ──────────────────────────────────────
  Future<void> _openRazorpay() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Fully covered by wallet / MedNU Money — no gateway leg at all, so the
    // in-app debit is the *only* thing that moves money here. It must
    // succeed before we report success, or the patient gets a free order.
    if (_amountAfterWallet <= 0) {
      final error = await _applyBalanceDeductions();
      if (!mounted) return;
      setState(() => _isProcessing = false);
      if (error != null) {
        _showError(error);
        return;
      }
      _showSuccessSheet('WALLET-${DateTime.now().millisecondsSinceEpoch}');
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
      'key': _kRazorpayKeyId,
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
  void _applyPromo() {
    final code = _promoController.text.trim().toUpperCase();
    if (code == 'MEDNU100') {
      setState(() {
        _promoApplied = true;
        _promoCode = code;
        _promoDiscount = 100;
        _showPromoField = false;
      });
      _showSnackBar('Promo applied! ₹100 discount added.', _kGreen);
    } else if (code == 'FIRST50') {
      setState(() {
        _promoApplied = true;
        _promoCode = code;
        _promoDiscount = 50;
        _showPromoField = false;
      });
      _showSnackBar('Promo applied! ₹50 discount added.', _kGreen);
    } else {
      _showSnackBar('Invalid promo code. Please try again.', AppColors.error);
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
        onPressed: () => context.pop(),
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
          _SummaryRow('Subtotal', '₹${widget.amount}'),
          const SizedBox(height: 8),
          const _SummaryRow('Platform Fee', '₹0',
              valueColor: _kGreen, valueNote: 'Waived'),
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
            activeThumbColor: activeColor,
            activeTrackColor: activeColor.withValues(alpha: 0.3),
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
                          onPressed: _applyPromo,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18),
                          ),
                          child: const Text(
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
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: _isProcessing ? null : _openRazorpay,
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
                    const Icon(Icons.lock_rounded, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _amountAfterWallet <= 0
                          ? 'Complete with Wallet'
                          : 'Pay ₹$_amountAfterWallet',
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
    );
  }

  // ── Success Sheet ──────────────────────────────────────
  void _showSuccessSheet(String paymentId) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SuccessSheet(
        amount: widget.amount,
        paymentId: paymentId,
        description: widget.description,
        onDone: () => Navigator.pop(sheetContext),
      ),
    ).then((_) {
      if (mounted) context.pop(true);
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
                  'Payment Successful!',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '₹${widget.amount} paid successfully',
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
                      _ReceiptRow('Amount Paid', '₹${widget.amount}'),
                      const SizedBox(height: 8),
                      _ReceiptRow(
                        'Transaction ID',
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
  final String? valueNote;

  const _SummaryRow(
    this.label,
    this.value, {
    this.valueColor,
    this.valueNote,
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
            if (valueNote != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  valueNote!,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _kGreen,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
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
