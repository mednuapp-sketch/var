import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../services/hospital_payment_service.dart';
import '../services/hospital_profile_service.dart';

/// The hospital billing desk's entire screen: a live list of patients who
/// have paid their bill through the MedNu patient app for this hospital.
/// Read-only by design — payment status is set server-side by the patient
/// app's payment pipeline, there is nothing for the desk to action here,
/// only to confirm.
class HospitalPaymentsScreen extends StatelessWidget {
  const HospitalPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          const GradientSliverAppBar(
            headerIcon: Icons.receipt_long_rounded,
            title: 'Bill Payments',
            subtitle: 'Live patient payment confirmations',
            expandedHeight: 110,
          ),
          SliverToBoxAdapter(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: HospitalProfileService.profileStream(uid),
              builder: (context, profileSnap) {
                final profile = profileSnap.data?.data();
                final hospitalId = profile?['hospitalId'] as String?;
                final hospitalName = profile?['hospitalName'] as String?;

                if (profileSnap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (hospitalId == null || hospitalId.isEmpty) {
                  return _NotLinkedNotice(
                    hasHospitalName: (hospitalName ?? '').isNotEmpty,
                  );
                }

                return _PaymentsList(hospitalId: hospitalId, hospitalName: hospitalName);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotLinkedNotice extends StatelessWidget {
  final bool hasHospitalName;
  const _NotLinkedNotice({required this.hasHospitalName});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 48, 20, 20),
      child: Column(
        children: [
          Icon(Icons.hourglass_top_rounded, size: 48, color: AppColors.textHint),
          SizedBox(height: 16),
          Text(
            'Awaiting hospital link',
            style: AppTextStyles.h4,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'Our team is confirming which hospital this account represents. '
            'Payment confirmations will appear here once that\'s done.',
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PaymentsList extends StatelessWidget {
  final String hospitalId;
  final String? hospitalName;
  const _PaymentsList({required this.hospitalId, required this.hospitalName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(hospitalName ?? 'Your hospital', style: AppTextStyles.sectionTitle),
        ),
        StreamBuilder<List<HospitalBillPayment>>(
          stream: HospitalPaymentService.streamForHospital(hospitalId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final payments = snap.data ?? const <HospitalBillPayment>[];
            if (payments.isEmpty) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(20, 32, 20, 20),
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textHint),
                    SizedBox(height: 12),
                    Text('No payments yet', style: AppTextStyles.h4),
                    SizedBox(height: 6),
                    Text(
                      'Patient bill payments will show up here the moment they pay.',
                      style: AppTextStyles.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                children: payments.map((p) => _PaymentCard(payment: p)).toList(),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PaymentCard extends StatefulWidget {
  final HospitalBillPayment payment;
  const _PaymentCard({required this.payment});

  @override
  State<_PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<_PaymentCard> {
  bool _isVerifying = false;

  bool get _isConfirmed =>
      widget.payment.paymentStatus == null || widget.payment.paymentStatus != 'failed';

  Future<void> _markVerified() async {
    setState(() => _isVerifying = true);
    try {
      await HospitalPaymentService.markVerified(widget.payment.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not mark this payment verified. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = widget.payment;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_rounded, color: AppColors.success, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('₹${payment.finalAmount.toStringAsFixed(0)} paid',
                            style: AppTextStyles.labelLarge),
                        if (payment.discountLabel != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(payment.discountLabel!,
                                style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
                          ),
                        ],
                      ],
                    ),
                    if (payment.billAmount != payment.finalAmount)
                      Text('Bill amount: ₹${payment.billAmount.toStringAsFixed(0)}',
                          style: AppTextStyles.bodySmall),
                    if (payment.createdAt != null)
                      Text(
                        DateFormat('d MMM yyyy, h:mm a').format(payment.createdAt!),
                        style: AppTextStyles.caption,
                      ),
                  ],
                ),
              ),
              Icon(
                _isConfirmed ? Icons.verified_rounded : Icons.error_outline_rounded,
                color: _isConfirmed ? AppColors.success : AppColors.error,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          if (payment.hospitalVerified)
            Row(
              children: [
                const Icon(Icons.task_alt_rounded, color: AppColors.success, size: 16),
                const SizedBox(width: 6),
                Text('Verified by your desk', style: AppTextStyles.labelSmall.copyWith(color: AppColors.success)),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              height: 36,
              child: OutlinedButton.icon(
                onPressed: _isVerifying ? null : _markVerified,
                icon: _isVerifying
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline_rounded, size: 16),
                label: Text(_isVerifying ? 'Verifying...' : 'Mark as Verified'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.success,
                  side: const BorderSide(color: AppColors.success),
                  textStyle: AppTextStyles.labelSmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
