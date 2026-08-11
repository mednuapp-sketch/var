import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/order_model.dart';
import '../providers/order_providers.dart';

/// Entry point back to a patient's medicine orders — reachable from
/// `MyServicesScreen`'s app bar. This closes the gap where the `orders`
/// collection had no list view anywhere: previously the only way to see an
/// order was immediately after checkout, with no way back once you
/// navigated away. Purely additive — `MyServicesScreen`'s own tabs/
/// aggregation logic (which covers appointments/consultations/
/// service_requests/nutrition, not `orders`) is untouched.
class MedicineOrdersScreen extends ConsumerWidget {
  const MedicineOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myOrdersProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBase : AppColors.background,
      body: CustomScrollView(
        slivers: [
          const GradientAppBar(title: 'Medicine Orders'),
          SliverToBoxAdapter(
            child: ordersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Column(children: [
                  SkeletonListTile(),
                  SkeletonListTile(),
                  SkeletonListTile(),
                ]),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.all(16),
                child: AppErrorState(message: 'Could not load your orders.'),
              ),
              data: (orders) {
                if (orders.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: AppEmptyState(
                      icon: Icons.medication_outlined,
                      title: 'No medicine orders yet',
                      message: 'Orders you place from the Pharmacy section will show up here.',
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: Column(
                    children: orders.map((order) => _OrderTile(order: order)).toList(),
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

class _OrderTile extends StatelessWidget {
  final OrderModel order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TapScale(
        onTap: () => context.push(AppRoutes.orderDetail, extra: {'orderId': order.orderId}),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.medicineGrad,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.medication_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${order.items.length} item${order.items.length == 1 ? '' : 's'} • ₹${order.total}',
                      style: AppTextStyles.labelLarge.copyWith(color: isDark ? Colors.white : AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('d MMM y, h:mm a').format(order.createdAt),
                      style: AppTextStyles.bodySmall,
                    ),
                    if (order.needsPrescriptionDecision) ...[
                      const SizedBox(height: 4),
                      const StatusBadge(label: 'Prescription Pending Review', color: AppColors.warning),
                    ] else if (order.prescriptionWasRejected) ...[
                      const SizedBox(height: 4),
                      const StatusBadge(label: 'Prescription Needs Attention', color: AppColors.error),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}
