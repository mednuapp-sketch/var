import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mednu/core/constants/app_colors.dart';
import 'package:mednu/core/constants/app_text_styles.dart';
import 'package:mednu/core/router/app_router.dart';
import 'package:mednu/core/utils/r.dart';

/// Shown after PayHospitalBillScreen's payment succeeds — the generic
/// PaymentScreen already shows its own brief animated confirmation sheet
/// (same one every other paid service in the app uses), this is the richer,
/// hospital-bill-specific receipt with the details that sheet doesn't carry:
/// which hospital, the original bill vs. discount vs. what was actually paid,
/// and the transaction id to quote if there's ever a dispute.
class HospitalBillPaymentSuccessScreen extends StatefulWidget {
  final String hospitalName;
  final double billAmount;
  final double finalAmount;
  final String? discountLabel;
  final String transactionId;

  const HospitalBillPaymentSuccessScreen({
    super.key,
    required this.hospitalName,
    required this.billAmount,
    required this.finalAmount,
    required this.discountLabel,
    required this.transactionId,
  });

  @override
  State<HospitalBillPaymentSuccessScreen> createState() =>
      _HospitalBillPaymentSuccessScreenState();
}

class _HospitalBillPaymentSuccessScreenState
    extends State<HospitalBillPaymentSuccessScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  final DateTime _paidAt = DateTime.now();

  double get _discount => (widget.billAmount - widget.finalAmount).clamp(0, widget.billAmount);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(AppRoutes.home);
      },
      child: Scaffold(
        backgroundColor: context.appBackground,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: R.p(context, 20)),
            child: Column(
              children: [
                SizedBox(height: R.h(context, 32)),
                ScaleTransition(
                  scale: _scale,
                  child: Container(
                    width: R.w(context, 84),
                    height: R.w(context, 84),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_rounded, color: AppColors.success, size: R.w(context, 48)),
                  ),
                ),
                SizedBox(height: R.h(context, 20)),
                Text('Payment Successful',
                    style: AppTextStyles.h2.copyWith(color: context.appTextPrimary)),
                SizedBox(height: R.h(context, 6)),
                Text(
                  'Your bill payment to ${widget.hospitalName} was confirmed.',
                  style: AppTextStyles.bodyMedium.copyWith(color: context.appTextSecondary),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: R.h(context, 28)),

                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(R.p(context, 18)),
                  decoration: BoxDecoration(
                    color: context.appSurface,
                    borderRadius: BorderRadius.circular(R.r(context, 18)),
                    border: Border.all(color: context.appBorder),
                  ),
                  child: Column(
                    children: [
                      _DetailRow(label: 'Hospital', value: widget.hospitalName),
                      _DetailRow(
                          label: 'Bill Amount', value: '₹${widget.billAmount.toStringAsFixed(0)}'),
                      if (_discount > 0)
                        _DetailRow(
                          label: widget.discountLabel ?? 'Discount',
                          value: '− ₹${_discount.toStringAsFixed(0)}',
                          valueColor: AppColors.success,
                        ),
                      const Divider(height: 24),
                      _DetailRow(
                        label: 'Amount Paid',
                        value: '₹${widget.finalAmount.toStringAsFixed(0)}',
                        bold: true,
                        valueColor: AppColors.primary,
                      ),
                      const Divider(height: 24),
                      _DetailRow(label: 'Transaction ID', value: widget.transactionId, mono: true),
                      _DetailRow(
                        label: 'Date & Time',
                        value: DateFormat('d MMM yyyy, h:mm a').format(_paidAt),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                SizedBox(
                  width: double.infinity,
                  height: R.h(context, 48),
                  child: OutlinedButton(
                    onPressed: () => context.go(AppRoutes.myServices),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(R.r(context, 12))),
                    ),
                    child: Text('View in Service Tracker',
                        style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
                  ),
                ),
                SizedBox(height: R.h(context, 10)),
                SizedBox(
                  width: double.infinity,
                  height: R.h(context, 48),
                  child: ElevatedButton(
                    onPressed: () => context.go(AppRoutes.home),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(R.r(context, 12))),
                    ),
                    child: Text('Done', style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
                  ),
                ),
                SizedBox(height: R.h(context, 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool mono;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.mono = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMedium.copyWith(color: context.appTextSecondary)),
          SizedBox(width: R.p(context, 12)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: (bold ? AppTextStyles.h4 : AppTextStyles.bodyMedium).copyWith(
                color: valueColor ?? context.appTextPrimary,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
