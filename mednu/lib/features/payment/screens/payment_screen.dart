import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../wallet/wallet_provider.dart';

// TODO(pending): Replace with your Razorpay LIVE key before Play Store release.
// Test key  starts with rzp_test_ — will NOT charge real money.
// Live key starts with rzp_live_ — charges real money.
const _kRazorpayKeyId = 'rzp_test_REPLACE_WITH_YOUR_KEY';

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
  bool _isProcessing = false;

  final List<Map<String, dynamic>> _paymentMethods = [
    {'id': 'upi',        'name': 'UPI',                 'icon': Icons.account_balance_rounded,        'color': const Color(0xFF2E7D32), 'desc': 'GPay, PhonePe, Paytm'},
    {'id': 'card',       'name': 'Credit / Debit Card',  'icon': Icons.credit_card_rounded,            'color': const Color(0xFF1565C0), 'desc': 'Visa, Mastercard, RuPay'},
    {'id': 'netbanking', 'name': 'Net Banking',           'icon': Icons.account_balance_wallet_rounded, 'color': const Color(0xFF7B1FA2), 'desc': 'All major banks supported'},
    {'id': 'cod',        'name': 'Cash on Delivery',      'icon': Icons.money_rounded,                  'color': const Color(0xFFE65100), 'desc': 'Pay when service arrives'},
  ];

  int get _walletBalance {
    final balance = ref.watch(walletBalanceProvider);
    return balance.maybeWhen(data: (b) => b.toInt(), orElse: () => 0);
  }

  int get _totalAmount    => int.tryParse(widget.amount) ?? 0;
  int get _walletDeduction => _useWallet ? _totalAmount.clamp(0, _walletBalance) : 0;
  int get _amountAfterWallet => (_totalAmount - _walletDeduction).clamp(0, _totalAmount);

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
    super.dispose();
  }

  void _onSuccess(PaymentSuccessResponse response) {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    _showSuccessSheet(response.paymentId ?? 'TXN${DateTime.now().millisecondsSinceEpoch}');
  }

  void _onError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message ?? 'Try again'}'),
        backgroundColor: Colors.red.shade600,
      ),
    );
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('External wallet: ${response.walletName}')),
    );
  }

  void _openRazorpay() {
    // If cash on delivery, skip Razorpay
    if (_selectedMethod == 'cod') {
      _showSuccessSheet('COD-${DateTime.now().millisecondsSinceEpoch}');
      return;
    }

    // If entire amount is covered by wallet, skip gateway
    if (_amountAfterWallet <= 0) {
      _showSuccessSheet('WALLET-${DateTime.now().millisecondsSinceEpoch}');
      return;
    }

    setState(() => _isProcessing = true);

    final options = <String, dynamic>{
      'key':         _kRazorpayKeyId,
      'amount':      _amountAfterWallet * 100, // Razorpay expects paise
      'name':        'MedNU Healthcare',
      'description': widget.description,
      'prefill': {
        'contact': '',
        'email':   '',
      },
      'external': {
        'wallets': ['paytm', 'phonepe'],
      },
    };

    // Pre-select payment method in Razorpay checkout
    if (_selectedMethod == 'card') {
      options['method'] = 'card';
    } else if (_selectedMethod == 'netbanking') {
      options['method'] = 'netbanking';
    }

    try {
      _razorpay.open(options);
    } catch (e) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open payment: $e')),
      );
    }
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
                  Text('Order Summary', style: AppTextStyles.h4),
                  const SizedBox(height: 12),
                  Text(widget.description, style: AppTextStyles.bodyMedium),
                  const Divider(height: 20),
                  _SummaryRow('Subtotal', '₹${widget.amount}'),
                  const SizedBox(height: 6),
                  _SummaryRow('Platform Fee', '₹0'),
                  if (_useWallet) ...[
                    const SizedBox(height: 6),
                    _SummaryRow(
                      'Wallet Deduction',
                      '-₹$_walletDeduction',
                      color: const Color(0xFF2E7D32),
                    ),
                  ],
                  const Divider(height: 12),
                  _SummaryRow('Total', '₹$_amountAfterWallet', isBold: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Wallet toggle ──────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _useWallet
                      ? AppColors.primary.withOpacity(0.3)
                      : AppColors.divider,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.white,
                        size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MedNU Wallet', style: AppTextStyles.labelLarge),
                        Text('Available: ₹$_walletBalance',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.accent)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _useWallet,
                    onChanged: (v) => setState(() => _useWallet = v),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Payment methods ────────────────────────────
            Text('Payment Method', style: AppTextStyles.h4),
            const SizedBox(height: 12),
            ..._paymentMethods.map((method) {
              final color = method['color'] as Color;
              final selected = _selectedMethod == method['id'];
              return GestureDetector(
                onTap: () => setState(() => _selectedMethod = method['id'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: selected ? color.withOpacity(0.05) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? color : AppColors.border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
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
                            Text(
                              method['name'] as String,
                              style: AppTextStyles.labelLarge.copyWith(
                                color: selected ? color : AppColors.textPrimary,
                              ),
                            ),
                            Text(method['desc'] as String,
                                style: AppTextStyles.bodySmall),
                          ],
                        ),
                      ),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: selected ? color : AppColors.border, width: 2),
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

            // ── UPI ID field ───────────────────────────────
            if (_selectedMethod == 'upi') ...[
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Enter UPI ID (e.g. name@upi)',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],

            // ── Card fields ───────────────────────────────
            if (_selectedMethod == 'card') ...[
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Card Number',
                  prefixIcon: const Icon(Icons.credit_card_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'MM/YY',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'CVV',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // ── SSL notice ────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_rounded, size: 14, color: AppColors.textHint),
                const SizedBox(width: 5),
                Text('100% Secure • Powered by Razorpay • SSL Encrypted',
                    style: AppTextStyles.caption),
              ],
            ),
            const SizedBox(height: 16),

            // ── Pay button ────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _openRazorpay,
                child: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(_selectedMethod == 'cod'
                        ? 'Confirm Order'
                        : 'Pay ₹$_amountAfterWallet'),
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
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 44),
            ),
            const SizedBox(height: 16),
            Text('Payment Successful! 🎉', style: AppTextStyles.h3),
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
                  context.pop();
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
              style: isBold ? AppTextStyles.labelLarge : AppTextStyles.bodyMedium),
          Text(
            value,
            style: (isBold ? AppTextStyles.labelLarge : AppTextStyles.labelMedium)
                .copyWith(
                    color: color ??
                        (isBold ? AppColors.primary : AppColors.textPrimary)),
          ),
        ],
      );
}
