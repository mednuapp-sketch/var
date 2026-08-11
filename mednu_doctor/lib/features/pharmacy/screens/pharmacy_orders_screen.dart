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

/// Two tabs: the shared, realtime "Available" queue every pharmacy partner
/// sees (unclaimed orders), and this pharmacy's own "My Orders" — paginated,
/// with a lightweight status filter.
class PharmacyOrdersScreen extends ConsumerStatefulWidget {
  const PharmacyOrdersScreen({super.key});

  @override
  ConsumerState<PharmacyOrdersScreen> createState() => _PharmacyOrdersScreenState();
}

class _PharmacyOrdersScreenState extends ConsumerState<PharmacyOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SharedAppShell(
      currentRoute: AppRoutes.pharmacyOrders,
      title: 'Orders',
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Available'),
                Tab(text: 'My Orders'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                const _AvailableTab(),
                _MyOrdersTab(
                  statusFilter: _statusFilter,
                  onFilterChanged: (v) => setState(() => _statusFilter = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableTab extends ConsumerWidget {
  const _AvailableTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(availableOrdersProvider);
    return available.when(
      loading: () => const ListLoadingState(hasAvatar: false),
      error: (_, __) => const NetworkErrorState(),
      data: (orders) {
        if (orders.isEmpty) {
          return const AppEmptyState(
            icon: Icons.inbox_outlined,
            title: 'No available orders',
            message: 'New medicine and equipment orders will appear here in realtime.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          itemBuilder: (context, i) => _OrderTile(order: orders[i]),
        );
      },
    );
  }
}

class _MyOrdersTab extends ConsumerWidget {
  final String? statusFilter;
  final ValueChanged<String?> onFilterChanged;

  const _MyOrdersTab({required this.statusFilter, required this.onFilterChanged});

  static const _filters = <String?, String>{
    null: 'All',
    'prescription_required': 'Needs Rx',
    'packed': 'Packed',
    'out_for_delivery': 'Delivering',
    'delivered': 'Delivered',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myOrdersControllerProvider(statusFilter));
    final controller = ref.read(myOrdersControllerProvider(statusFilter).notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _filters.entries.map((entry) {
                final selected = entry.key == statusFilter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: selected,
                    onSelected: (_) => onFilterChanged(entry.key),
                    selectedColor: AppColors.primary.withValues(alpha: 0.14),
                    labelStyle: AppTextStyles.labelMedium.copyWith(
                      color: selected ? AppColors.primary : AppColors.textSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: state.items.isEmpty && !state.isLoadingMore
              ? const AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No orders yet',
                  message: 'Orders you accept will show up here.',
                )
              : NotificationListener<ScrollEndNotification>(
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 200) controller.loadMore();
                    return false;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.items.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= state.items.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
                        );
                      }
                      return _OrderTile(order: state.items[i]);
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  final PharmacyOrder order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(AppRoutes.pharmacyOrderDetail, extra: {'orderId': order.id}),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              order.orderType == PharmacyOrderType.equipment
                  ? Icons.medical_services_outlined
                  : Icons.medication_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.orderType == PharmacyOrderType.equipment
                      ? 'Equipment order'
                      : '${order.itemCount} item(s)',
                  style: AppTextStyles.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  order.patientName,
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge(label: order.status.label, color: order.status.color),
        ],
      ),
    );
  }
}
