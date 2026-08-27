import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';

/// Every payment the patient has made, sourced directly from `payments/{id}`
/// — the same collection capturePayment/captureCartPayment write to (see
/// functions/index.js) — rather than any per-service-type booking
/// collection, so this one screen covers every service uniformly.
class PaymentHistoryScreen extends StatelessWidget {
  const PaymentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text('Payment History',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 18)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Please log in'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('payments')
                  .where('patientId', isEqualTo: uid)
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: 6,
                    itemBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: SkeletonListTile(),
                    ),
                  );
                }
                if (snap.hasError) {
                  return AppErrorState(onRetry: () {});
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'No Payments Yet',
                    message: 'Your completed payments will appear here.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) => _PaymentTile(doc: docs[i]),
                );
              },
            ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _PaymentTile({required this.doc});

  static const _serviceIcons = {
    'consultation': Icons.medical_services_rounded,
    'video_consultation': Icons.video_call_rounded,
    'diagnostics': Icons.biotech_rounded,
    'medicine': Icons.medication_rounded,
    'pharmacy': Icons.local_pharmacy_rounded,
    'ambulance': Icons.local_hospital_rounded,
    'caregiver': Icons.volunteer_activism_rounded,
  };

  static const _serviceLabels = {
    'consultation': 'Consultation',
    'video_consultation': 'Video Consultation',
    'diagnostics': 'Lab Test',
    'medicine': 'Medicine Order',
    'pharmacy': 'Pharmacy',
    'ambulance': 'Ambulance',
    'caregiver': 'Caregiver Visit',
  };

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final serviceType = d['serviceType'] as String? ?? '';
    final paidAmount = (d['paidAmount'] as num?) ?? 0;
    final discount = (d['discount'] as num?) ?? 0;
    final status = d['status'] as String? ?? 'completed';
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
    final dateStr = createdAt != null ? DateFormat('d MMM yyyy, h:mm a').format(createdAt) : '';
    final isRefunded = status == 'refunded';

    return GestureDetector(
      onTap: () => context.push(AppRoutes.invoice, extra: {'paymentId': doc.id}),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _serviceIcons[serviceType] ?? Icons.receipt_long_rounded,
                color: AppColors.primary, size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_serviceLabels[serviceType] ?? serviceType, style: AppTextStyles.labelLarge),
                  if (discount > 0)
                    Text('Coupon: -₹${discount.toStringAsFixed(0)}',
                        style: AppTextStyles.caption.copyWith(color: AppColors.success)),
                  Text(dateStr, style: AppTextStyles.caption),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${paidAmount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700,
                    color: isRefunded ? AppColors.error : context.appTextPrimary,
                    decoration: isRefunded ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (isRefunded)
                  Text('Refunded', style: AppTextStyles.caption.copyWith(color: AppColors.error)),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: context.appTextHint),
          ],
        ),
      ),
    );
  }
}

