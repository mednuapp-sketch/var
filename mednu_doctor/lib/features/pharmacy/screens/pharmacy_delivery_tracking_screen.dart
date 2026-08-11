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

/// The dispatch-style operational queue: orders packed and awaiting
/// dispatch, and orders already out for delivery. Tapping through to the
/// order detail screen is where "Out for Delivery"/"Mark Delivered" live —
/// this screen is the overview the nav spec calls "Delivery Tracking".
class PharmacyDeliveryTrackingScreen extends ConsumerWidget {
  const PharmacyDeliveryTrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(deliveryQueueProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.pharmacyDeliveryTracking,
      title: 'Delivery Tracking',
      body: queue.when(
        loading: () => const ListLoadingState(hasAvatar: false),
        error: (_, __) => const NetworkErrorState(),
        data: (orders) {
          if (orders.isEmpty) {
            return const AppEmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'Nothing in transit',
              message: 'Packed orders awaiting dispatch will show up here.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, i) => _TrackingTile(order: orders[i]),
          );
        },
      ),
    );
  }
}

class _TrackingTile extends StatelessWidget {
  final PharmacyOrder order;
  const _TrackingTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final dispatched = order.status == PharmacyOrderStatus.outForDelivery;
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(AppRoutes.pharmacyOrderDetail, extra: {'orderId': order.id}),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (dispatched ? AppColors.secondary : AppColors.warning).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              dispatched ? Icons.local_shipping_rounded : Icons.inventory_2_rounded,
              color: dispatched ? AppColors.secondary : AppColors.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${order.itemCount} item(s)', style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(
                  dispatched
                      ? '${order.patientName} • ${order.deliveryPersonName ?? "Rider assigned"}'
                      : '${order.patientName} • Ready to dispatch',
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          StatusBadge(label: order.status.label, color: order.status.color),
        ],
      ),
    );
  }
}
