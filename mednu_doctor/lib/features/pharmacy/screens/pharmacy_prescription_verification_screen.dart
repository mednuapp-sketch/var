import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/pharmacy_order.dart';
import '../providers/pharmacy_providers.dart';

/// The pharmacist's review queue: every order this pharmacy has accepted
/// that is waiting on a prescription check before it can be packed. The
/// patient uploads directly from MedNu Patient (Patient Prescription
/// Upload feature) — the pharmacy's own manual-attach action on the order
/// detail screen remains available as a fallback (e.g. a phone-in order).
/// This screen is the triage list that gets a pharmacist to either one.
class PharmacyPrescriptionVerificationScreen extends ConsumerWidget {
  const PharmacyPrescriptionVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(prescriptionVerificationQueueProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.pharmacyPrescriptionVerification,
      title: 'Prescription Verification',
      body: queue.when(
        loading: () => const ListLoadingState(hasAvatar: false),
        error: (_, __) => const NetworkErrorState(),
        data: (orders) {
          if (orders.isEmpty) {
            return const AppEmptyState(
              icon: Icons.medical_information_outlined,
              title: 'Nothing to verify',
              message: 'Orders that need a prescription check will show up here.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, i) => _VerificationTile(order: orders[i]),
          );
        },
      ),
    );
  }
}

class _VerificationTile extends StatelessWidget {
  final PharmacyOrder order;
  const _VerificationTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final hasPrescription = order.hasPrescription;
    final isPdf = order.prescriptionFileType == 'pdf';
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(AppRoutes.pharmacyOrderDetail, extra: {'orderId': order.id}),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: hasPrescription && !isPdf
                ? CachedNetworkImage(
                    imageUrl: order.prescriptionUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const SkeletonCircle(size: 44),
                    errorWidget: (_, __, ___) => _fallbackIcon(hasPrescription, isPdf),
                  )
                : _fallbackIcon(hasPrescription, isPdf),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${order.itemCount} item(s)', style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(
                  hasPrescription ? '${order.patientName} • Ready to verify' : '${order.patientName} • Needs prescription',
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
        ],
      ),
    );
  }

  Widget _fallbackIcon(bool hasPrescription, bool isPdf) {
    final color = !hasPrescription ? AppColors.warning : (isPdf ? AppColors.error : AppColors.success);
    final icon = !hasPrescription
        ? Icons.upload_file_rounded
        : (isPdf ? Icons.picture_as_pdf_rounded : Icons.fact_check_outlined);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: color),
    );
  }
}
