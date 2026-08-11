import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/order_model.dart';
import '../providers/order_providers.dart';
import '../widgets/prescription_card.dart';

/// New, additive per-order detail screen for medicine `orders` — the
/// collection had no reader anywhere in the app before this feature (see
/// compatibility report). Realtime via `orderDetailProvider`; hosts the
/// prescription upload/verification card alongside the order summary.
class OrderDetailScreen extends ConsumerWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBase : AppColors.background,
      body: CustomScrollView(
        slivers: [
          const GradientAppBar(title: 'Order Details'),
          SliverToBoxAdapter(
            child: orderAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Column(children: [
                  SkeletonBox(width: double.infinity, height: 120, radius: 18),
                  SizedBox(height: 16),
                  SkeletonBox(width: double.infinity, height: 220, radius: 18),
                ]),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.all(16),
                child: AppErrorState(message: 'Could not load this order.'),
              ),
              data: (order) {
                if (order == null) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: AppEmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Order not found',
                      message: 'This order may have been removed.',
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SummaryCard(order: order, isDark: isDark),
                      const SizedBox(height: 16),
                      PrescriptionCard(order: order),
                      const SizedBox(height: 16),
                      _ItemsCard(order: order, isDark: isDark),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final OrderModel order;
  final bool isDark;
  const _SummaryCard({required this.order, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Order #${order.orderId}', style: AppTextStyles.h4.copyWith(
                color: isDark ? Colors.white : AppColors.textPrimary,
              ))),
              StatusBadge(label: _statusLabel(order.status), color: _statusColor(order.status)),
            ],
          ),
          const SizedBox(height: 8),
          Text(DateFormat('d MMM y, h:mm a').format(order.createdAt), style: AppTextStyles.bodySmall),
          const SizedBox(height: 10),
          if (order.deliveryAddress.toString().isNotEmpty)
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(child: Text(order.deliveryAddress, style: AppTextStyles.bodySmall)),
            ]),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'confirmed':
        return 'Confirmed';
      case 'verified':
        return 'Verified';
      case 'prescription_required':
        return 'Needs Prescription';
      case 'packed':
        return 'Packed';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'prescription_required':
        return AppColors.warning;
      case 'out_for_delivery':
        return AppColors.info;
      default:
        return AppColors.primary;
    }
  }
}

class _ItemsCard extends StatelessWidget {
  final OrderModel order;
  final bool isDark;
  const _ItemsCard({required this.order, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Items', style: AppTextStyles.labelMedium.copyWith(color: isDark ? Colors.white : AppColors.textPrimary)),
          const SizedBox(height: 10),
          ...order.items.map<Widget>((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: AppTextStyles.bodyLarge),
                          if (item.brand.toString().isNotEmpty)
                            Text(item.brand, style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                    Text('x${item.count}', style: AppTextStyles.bodyMedium),
                  ],
                ),
              )),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: AppTextStyles.labelLarge.copyWith(color: isDark ? Colors.white : AppColors.textPrimary)),
              Text('₹${order.total}', style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }
}
