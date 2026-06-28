import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../wallet/wallet_provider.dart';

const _kRazorpayKeyId = 'rzp_test_T1Z9EVjv8paYQ2';

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

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  late final Razorpay _razorpay;
  String _selectedMethod = 'upi';
  bool _useWallet = false;
  bool _useMednuMoney = false;
  bool _isProcessing = false;
  String? _pendingOrderId;
  final TextEditingController _upiController = TextEditingController();

  final List<Map<String, dynamic>> _paymentMethods = [
    {'id': 'upi',        'name': 'UPI',                'icon': Icons.account_balance_rounded,        'color': const Color(0xFF2E7D32), 'desc': 'GPay, PhonePe, Paytm'},
    {'id': 'card',       'name': 'Credit / Debit Card', 'icon': Icons.credit_card_rounded,            'color': const Color(0xFF1565C0), 'desc': 'Visa, Mastercard, RuPay'},
    {'id': 'netbanking', 'name': 'Net Banking',          'icon': Icons.account_balance_wallet_rounded, 'color': const Color(0xFF7B1FA2), 'desc': 'All major banks supported'},
  ];

  int get _walletBalance {
    final balance = ref.watch(walletBalanceProvider);
    return balance.maybeWhen(data: (b) => b.toInt(), orElse: () => 0);
  }

  int get _mednuMoneyBalance {
    final mm = ref.watch(mednuMoneyBalanceProvider);
    return mm.maybeWhen(data: (b) => b.toInt(), orElse: () => 0);
  }

  int get _totalAmount           => int.tryParse(widget.amount) ?? 0;
  // MedNu Money is applied first (bonus credits first)
  int get _mednuMoneyDeduction   => _useMednuMoney ? _totalAmount.clamp(0, _mednuMoneyBalance) : 0;
  int get _afterMednuMoney       => (_totalAmount - _mednuMoneyDeduction).clamp(0, _totalAmount);
  int get _walletDeduction       => _useWallet ? _afterMednuMoney.clamp(0, _walletBalance) : 0;
  int get _amountAfterWallet     => (_afterMednuMoney - _walletDeduction).clamp(0, _totalAmount);

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR,   _onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    _upiController.dispose();
    super.dispose();
  }

  void _onSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    final paymentId = response.paymentId  ?? '';
    final orderId   = response.orderId    ?? _pendingOrderId ?? '';
    final signature = response.signature  ?? '';

    // Deduct MedNu Money if it was applied
    if (_mednuMoneyDeduction > 0) {
      try {
        await ref.read(walletServiceProvider).deductMednuMoney(
          amount: _mednuMoneyDeduction.toDouble(),
          title: 'MedNu Money Used',
          category: 'consultation',
          description: widget.description,
        );
      } catch (_) {}
    }

    if (orderId.isEmpty || signature.isEmpty) {
      setState(() => _isProcessing = false);
      _showSuccessSheet(paymentId.isNotEmpty
          ? paymentId
          : 'WALLET-${DateTime.now().millisecondsSinceEpoch}');
      return;
    }

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyRazorpayPayment')
          .call({
        'razorpay_order_id':   orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature':  signature,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening ${response.walletName}…')),
    );
  }

  Future<void> _openRazorpay() async {
    if (_amountAfterWallet <= 0) {
      _showSuccessSheet('WALLET-${DateTime.now().millisecondsSinceEpoch}');
      return;
    }

    setState(() => _isProcessing = true);

    String orderId;
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createRazorpayOrder')
          .call({
        'amount':   _amountAfterWallet * 100,
        'currency': 'INR',
        'receipt':  'mednu_${DateTime.now().millisecondsSinceEpoch}',
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
      'key':         _kRazorpayKeyId,
      'order_id':    orderId,
      'amount':      _amountAfterWallet * 100,
      'name':        'MedNU Healthcare',
      'description': widget.description,
      'prefill':     prefill,
      'theme':       {'color': '#C2185B'},
      'external':    {'wallets': ['paytm', 'phonepe']},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showError('Could not open payment modal: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade600),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Payment'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Order summary ──────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Order Summary', style: AppTextStyles.h4),
                  const SizedBox(height: 12),
                  Text(widget.description, style: AppTextStyles.bodyMedium),
                  const Divider(height: 20),
                  _SummaryRow('Subtotal', '₹${widget.amount}'),
                  const SizedBox(height: 6),
                  const _SummaryRow('Platform Fee', '₹0'),
                  if (_useMednuMoney && _mednuMoneyDeduction > 0) ...[
                    const SizedBox(height: 6),
                    _SummaryRow('MedNu Money', '-₹$_mednuMoneyDeduction',
                        color: const Color(0xFF6A1B9A)),
                  ],
                  if (_useWallet && _walletDeduction > 0) ...[
                    const SizedBox(height: 6),
                    _SummaryRow('Wallet Deduction', '-₹$_walletDeduction',
                        color: const Color(0xFF2E7D32)),
                  ],
                  const Divider(height: 12),
                  _SummaryRow('Total', '₹$_amountAfterWallet', isBold: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── MedNu Money toggle ────────────────────────
            if (_mednuMoneyBalance > 0) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _useMednuMoney
                      ? const Color(0xFF6A1B9A).withValues(alpha: 0.05)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _useMednuMoney
                        ? const Color(0xFF6A1B9A).withValues(alpha: 0.4)
                        : AppColors.divider,
                    width: _useMednuMoney ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.stars_rounded,
                          color: Colors.amber, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('MedNu Money',
                              style: AppTextStyles.labelLarge),
                          Text('Available: ₹$_mednuMoneyBalance  •  Bookings only',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: const Color(0xFF6A1B9A))),
                        ],
                      ),
                    ),
                    Switch(
                      value: _useMednuMoney,
                      onChanged: (v) => setState(() => _useMednuMoney = v),
                      activeThumbColor: const Color(0xFF6A1B9A),
                      activeTrackColor: const Color(0xFF6A1B9A).withValues(alpha: 0.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Wallet toggle ──────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _useWallet
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : AppColors.divider,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_balance_wallet_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('MedNU Wallet', style: AppTextStyles.labelLarge),
                        Text('Available: ₹$_walletBalance',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.accent)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _useWallet,
                    onChanged: (v) => setState(() => _useWallet = v),
                    activeThumbColor: AppColors.primary,
                    activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Payment methods ────────────────────────────
            const Text('Payment Method', style: AppTextStyles.h4),
            const SizedBox(height: 12),
            ..._paymentMethods.map((method) {
              final color    = method['color'] as Color;
              final selected = _selectedMethod == method['id'];
              return GestureDetector(
                onTap: () => setState(
                    () => _selectedMethod = method['id'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.05)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? color : AppColors.border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(method['icon'] as IconData,
                            color: color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(method['name'] as String,
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: selected
                                      ? color
                                      : AppColors.textPrimary,
                                )),
                            Text(method['desc'] as String,
                                style: AppTextStyles.bodySmall),
                          ],
                        ),
                      ),
                      Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: selected ? color : AppColors.border,
                              width: 2),
                          color: selected ? color : Colors.transparent,
                        ),
                        child: selected
                            ? const Icon(Icons.check_rounded,
                                size: 14, color: Colors.white)
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            }),

            // ── UPI ID input (shown only when UPI method selected) ─
            if (_selectedMethod == 'upi') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.account_balance_rounded,
                            size: 16, color: Color(0xFF2E7D32)),
                        SizedBox(width: 8),
                        Text('Enter UPI ID (optional)',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E7D32),
                            )),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _upiController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'yourname@upi',
                        prefixIcon: const Icon(
                            Icons.alternate_email_rounded,
                            size: 18,
                            color: Color(0xFF2E7D32)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFFE0E0E0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFFE0E0E0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFF2E7D32), width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Leave blank — Razorpay will show GPay, PhonePe & other UPI app options automatically.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Color(0xFF9E9E9E),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Secure handoff notice ──────────────────────
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.lock_rounded,
                        color: Color(0xFF1565C0), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Secure Razorpay Checkout',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1565C0),
                            )),
                        SizedBox(height: 2),
                        Text(
                          'Your payment details are entered directly in Razorpay\'s encrypted window — we never see your card or UPI credentials.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Color(0xFF374151),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── SSL notice ─────────────────────────────────
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_rounded,
                    size: 14, color: AppColors.textHint),
                SizedBox(width: 5),
                Text(
                    '100% Secure • Powered by Razorpay • SSL Encrypted',
                    style: AppTextStyles.caption),
              ],
            ),
            const SizedBox(height: 16),

            // ── Pay button ─────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _openRazorpay,
                child: _isProcessing
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text('Pay ₹$_amountAfterWallet'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showSuccessSheet(String paymentId) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 44),
            ),
            const SizedBox(height: 16),
            const Text('Payment Successful!', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            Text('₹${widget.amount} paid successfully',
                style: AppTextStyles.bodyMedium),
            Text('Transaction ID: $paymentId',
                style: AppTextStyles.caption),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.pop(true);
                },
                child: const Text('Done'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Summary row ────────────────────────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  final String label, value;
  final bool isBold;
  final Color? color;

  const _SummaryRow(this.label, this.value,
      {this.isBold = false, this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: isBold
                  ? AppTextStyles.labelLarge
                  : AppTextStyles.bodyMedium),
          Text(value,
              style: (isBold
                      ? AppTextStyles.labelLarge
                      : AppTextStyles.labelMedium)
                  .copyWith(
                      color: color ??
                          (isBold
                              ? AppColors.primary
                              : AppColors.textPrimary))),
        ],
      );
}
