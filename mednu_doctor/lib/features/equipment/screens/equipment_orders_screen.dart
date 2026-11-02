import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/equipment_order.dart';
import '../providers/equipment_providers.dart';
import '../widgets/equipment_order_actions.dart';

/// The vendor's order inbox, split the way a kitchen splits tickets:
/// **New** (needs a yes/no), **Active** (accepted → out for delivery →
/// delivered rentals awaiting pickup) and **History**.
class EquipmentOrdersScreen extends ConsumerWidget {
  const EquipmentOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(equipmentOrdersProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.equipmentOrders,
      title: 'Orders',
      body: ordersAsync.when(
        loading: () => const ListLoadingState(hasAvatar: false),
        error: (_, __) => const NetworkErrorState(),
        data: (orders) {
          final fresh = orders.where((o) => o.status == EquipmentOrderStatus.pending).toList();
          final active = orders
              .where((o) =>
                  o.status == EquipmentOrderStatus.accepted ||
                  o.status == EquipmentOrderStatus.outForDelivery ||
                  (o.status == EquipmentOrderStatus.delivered && o.isRent))
              .toList();
          final history = orders.where((o) => !fresh.contains(o) && !active.contains(o)).toList();

          return DefaultTabController(
            length: 3,
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  child: TabBar(
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.primary,
                    labelStyle: AppTextStyles.labelMedium,
                    tabs: [
                      Tab(text: 'New (${fresh.length})'),
                      Tab(text: 'Active (${active.length})'),
                      const Tab(text: 'History'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _OrderList(
                        orders: fresh,
                        emptyTitle: 'No new orders',
                        emptyMessage: 'New equipment bookings appear here the moment a patient books.',
                        showQuickActions: true,
                      ),
                      _OrderList(
                        orders: active,
                        emptyTitle: 'Nothing in progress',
                        emptyMessage: 'Accepted orders, deliveries and rentals out with patients show up here.',
                      ),
                      _OrderList(
                        orders: history,
                        emptyTitle: 'No past orders yet',
                        emptyMessage: 'Completed, returned and cancelled orders are kept here.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  final List<EquipmentOrder> orders;
  final String emptyTitle;
  final String emptyMessage;
  final bool showQuickActions;

  const _OrderList({
    required this.orders,
    required this.emptyTitle,
    required this.emptyMessage,
    this.showQuickActions = false,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return AppEmptyState(icon: Icons.inbox_outlined, title: emptyTitle, message: emptyMessage);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      itemCount: orders.length,
      itemBuilder: (_, i) => EquipmentOrderCard(order: orders[i], showQuickActions: showQuickActions),
    );
  }
}

/// One order ticket. Reused by the dashboard's "New orders" preview.
class EquipmentOrderCard extends StatelessWidget {
  final EquipmentOrder order;
  final bool showQuickActions;

  const EquipmentOrderCard({super.key, required this.order, this.showQuickActions = false});

  @override
  Widget build(BuildContext context) {
    final o = order;
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => context.push(AppRoutes.equipmentOrderDetail, extra: {'orderId': o.id}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: o.status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(o.isRent ? Icons.schedule_rounded : Icons.shopping_bag_outlined, color: o.status.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${o.quantity > 1 ? '${o.quantity} × ' : ''}${o.itemName}',
                      style: AppTextStyles.labelLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text('${o.patientName}  ·  ${o.modeLabel}', style: AppTextStyles.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(label: o.status.label, color: o.status.color),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('₹${o.totalAmount}', style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
              const Spacer(),
              Text(DateFormat('d MMM, h:mm a').format(o.createdAt), style: AppTextStyles.caption),
            ],
          ),
          if (showQuickActions && o.status == EquipmentOrderStatus.pending) ...[
            const SizedBox(height: 12),
            EquipmentOrderActions(order: o, compact: true),
          ],
        ],
      ),
    );
  }
}
