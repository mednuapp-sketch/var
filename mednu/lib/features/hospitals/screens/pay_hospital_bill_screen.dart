import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mednu/core/constants/app_colors.dart';
import 'package:mednu/core/constants/app_text_styles.dart';
import 'package:mednu/core/router/app_router.dart';
import 'package:mednu/core/services/feedback_service.dart';
import 'package:mednu/core/utils/r.dart';
import '../services/hospital_discount_service.dart';

class PayHospitalBillScreen extends StatefulWidget {
  final String hospitalId;
  final String hospitalName;

  const PayHospitalBillScreen({
    super.key,
    required this.hospitalId,
    required this.hospitalName,
  });

  @override
  State<PayHospitalBillScreen> createState() => _PayHospitalBillScreenState();
}

class _PayHospitalBillScreenState extends State<PayHospitalBillScreen> {
  final _amountController = TextEditingController();
  double _billAmount = 0;
  String? _selectedDiscountId;
  bool _isPaying = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double _finalAmount(List<HospitalBillDiscount> discounts) {
    final selected = _selected(discounts);
    if (selected == null) return _billAmount;
    return (_billAmount - selected.discountFor(_billAmount)).clamp(0, _billAmount);
  }

  HospitalBillDiscount? _selected(List<HospitalBillDiscount> discounts) {
    if (_selectedDiscountId == null) return null;
    for (final d in discounts) {
      if (d.id == _selectedDiscountId) return d;
    }
    return null;
  }

  Future<void> _pay(List<HospitalBillDiscount> discounts) async {
    if (_billAmount <= 0) {
      FeedbackService.show(context, 'Enter the bill amount first', type: FeedbackType.warning);
      return;
    }
    final selected = _selected(discounts);
    final finalAmount = _finalAmount(discounts);

    setState(() => _isPaying = true);
    Map<String, dynamic>? result;
    try {
      result = await context.push<Map<String, dynamic>>(
        AppRoutes.payment,
        extra: {
          'amount': finalAmount.toStringAsFixed(0),
          'description': 'Bill payment — ${widget.hospitalName}',
          'serviceType': 'hospital_bill',
          'bookingCollection': 'hospital_bill_payments',
          'bookingData': {
            'hospitalId': widget.hospitalId,
            'hospitalName': widget.hospitalName,
            'billAmount': _billAmount,
            'discountId': selected?.id,
            'discountLabel': selected?.label,
            'discountType': selected == null
                ? null
                : selected.type == DiscountType.flat ? 'flat' : 'percent',
            'discountValue': selected?.value,
            'finalAmount': finalAmount,
          },
        },
      );
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
    if (!mounted || result?['bookingId'] == null) return;
    context.pushReplacement(AppRoutes.hospitalBillPaymentSuccess, extra: {
      'hospitalName': widget.hospitalName,
      'billAmount': _billAmount,
      'finalAmount': finalAmount,
      'discountLabel': selected?.label,
      'transactionId': (result?['paymentId'] as String?) ?? (result?['bookingId'] as String?) ?? '',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: R.w(context, 20)),
          onPressed: () => context.pop(),
        ),
        title: Text('Pay Bill', style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
      ),
      body: StreamBuilder<List<HospitalBillDiscount>>(
        stream: HospitalDiscountService.streamActive(),
        builder: (context, snap) {
          final discounts = snap.data ?? const <HospitalBillDiscount>[];
          final finalAmount = _finalAmount(discounts);
          final selected = _selected(discounts);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                      R.p(context, 16), R.p(context, 16), R.p(context, 16), R.p(context, 16)),
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_hospital_rounded, color: AppColors.primary, size: R.w(context, 20)),
                        SizedBox(width: R.p(context, 8)),
                        Expanded(
                          child: Text(
                            widget.hospitalName,
                            style: AppTextStyles.h4.copyWith(color: context.appTextPrimary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: R.h(context, 20)),

                    Text('Bill amount', style: AppTextStyles.labelLarge.copyWith(color: context.appTextSecondary)),
                    SizedBox(height: R.h(context, 8)),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: false),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: AppTextStyles.h3.copyWith(color: context.appTextPrimary),
                      onChanged: (v) => setState(() => _billAmount = double.tryParse(v) ?? 0),
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        prefixStyle: AppTextStyles.h3.copyWith(color: context.appTextPrimary),
                        hintText: '0',
                        filled: true,
                        fillColor: context.appSurface,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: R.p(context, 16), vertical: R.p(context, 14)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.r(context, 14)),
                          borderSide: BorderSide(color: context.appBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.r(context, 14)),
                          borderSide: BorderSide(color: context.appBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.r(context, 14)),
                          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5), width: 1.5),
                        ),
                      ),
                    ),

                    SizedBox(height: R.h(context, 24)),
                    Text('Available discounts', style: AppTextStyles.labelLarge.copyWith(color: context.appTextSecondary)),
                    SizedBox(height: R.h(context, 8)),

                    if (discounts.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: R.p(context, 12)),
                        child: Text(
                          'No discounts available right now.',
                          style: AppTextStyles.bodyMedium.copyWith(color: context.appTextHint),
                        ),
                      )
                    else
                      ...discounts.map((d) {
                        final eligible = d.appliesTo(_billAmount);
                        final isSelected = _selectedDiscountId == d.id;
                        return Padding(
                          padding: EdgeInsets.only(bottom: R.p(context, 10)),
                          child: _DiscountTile(
                            discount: d,
                            eligible: eligible,
                            selected: isSelected,
                            onTap: eligible
                                ? () => setState(() =>
                                    _selectedDiscountId = isSelected ? null : d.id)
                                : null,
                          ),
                        );
                      }),
                  ],
                ),
              ),

              // ── Sticky summary + pay button ──────────────────────────────
              Container(
                padding: EdgeInsets.fromLTRB(
                    R.p(context, 16), R.p(context, 14), R.p(context, 16), R.p(context, 20)),
                decoration: BoxDecoration(
                  color: context.appSurface,
                  border: Border(top: BorderSide(color: context.appBorder)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Bill amount', style: AppTextStyles.bodyMedium.copyWith(color: context.appTextSecondary)),
                          Text('₹${_billAmount.toStringAsFixed(0)}',
                              style: AppTextStyles.bodyMedium.copyWith(color: context.appTextPrimary)),
                        ],
                      ),
                      if (selected != null) ...[
                        SizedBox(height: R.h(context, 4)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(selected.label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.success)),
                            Text('− ₹${selected.discountFor(_billAmount).toStringAsFixed(0)}',
                                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.success)),
                          ],
                        ),
                      ],
                      SizedBox(height: R.h(context, 8)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('You pay', style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
                          Text('₹${finalAmount.toStringAsFixed(0)}',
                              style: AppTextStyles.h3.copyWith(color: AppColors.primary)),
                        ],
                      ),
                      SizedBox(height: R.h(context, 14)),
                      SizedBox(
                        width: double.infinity,
                        height: R.h(context, 48),
                        child: ElevatedButton(
                          onPressed: (_isPaying || _billAmount <= 0) ? null : () => _pay(discounts),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 12))),
                          ),
                          child: _isPaying
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text('Pay ₹${finalAmount.toStringAsFixed(0)}',
                                  style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DiscountTile extends StatelessWidget {
  final HospitalBillDiscount discount;
  final bool eligible;
  final bool selected;
  final VoidCallback? onTap;

  const _DiscountTile({
    required this.discount,
    required this.eligible,
    required this.selected,
    required this.onTap,
  });

  String get _valueLabel => discount.type == DiscountType.flat
      ? 'Flat ₹${discount.value.toStringAsFixed(0)} off'
      : '${discount.value.toStringAsFixed(0)}% off';

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : context.appBorder;
    return Opacity(
      opacity: eligible ? 1 : 0.45,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: R.p(context, 14), vertical: R.p(context, 12)),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.06) : context.appSurface,
            borderRadius: BorderRadius.circular(R.r(context, 14)),
            border: Border.all(color: color, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.primary : context.appTextHint,
                size: R.w(context, 22),
              ),
              SizedBox(width: R.p(context, 10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(discount.label, style: AppTextStyles.bodyLarge.copyWith(color: context.appTextPrimary)),
                    Text(
                      eligible
                          ? _valueLabel
                          : 'Min bill ₹${discount.minBillAmount!.toStringAsFixed(0)} required',
                      style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
