import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/equipment_order.dart';
import '../providers/equipment_providers.dart';
import '../widgets/equipment_order_actions.dart';

class EquipmentOrderDetailScreen extends ConsumerWidget {
  final String orderId;
  const EquipmentOrderDetailScreen({super.key, required this.orderId});

  Future<void> _call(BuildContext context, String phone) async {
    if (phone.isEmpty) return;
    if (!await launchUrl(Uri.parse('tel:$phone'))) {
      if (context.mounted) FeedbackService.showError(context, 'Could not open the dialer.');
    }
  }

  Future<void> _navigate(BuildContext context, String address) async {
    if (address.isEmpty) return;
    final uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': address});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) FeedbackService.showError(context, 'Could not open Maps.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(equipmentOrderDetailProvider(orderId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Order details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.safeBack(fallbackRoute: AppRoutes.equipmentOrders),
        ),
      ),
      body: orderAsync.when(
        loading: () => const PageLoadingState(),
        error: (_, __) => const NetworkErrorState(),
        data: (o) {
          if (o == null) {
            return const AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Order not found',
              message: 'It may have been removed.',
            );
          }
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusHeader(order: o),
                const SizedBox(height: 14),
                PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Equipment', style: AppTextStyles.labelMedium),
                      const SizedBox(height: 8),
                      Text(
                        '${o.quantity > 1 ? '${o.quantity} × ' : ''}${o.itemName}',
                        style: AppTextStyles.h4,
                      ),
                      const SizedBox(height: 10),
                      _row('Type', o.modeLabel),
                      if (o.isRent && o.pricePerDay > 0) _row('Rate', '₹${o.pricePerDay} / day'),
                      if (o.deposit > 0) _row('Deposit to collect', '₹${o.deposit} (refundable)'),
                      _row('Order total', '₹${o.totalAmount}', emphasize: true),
                      _row('Placed', DateFormat('d MMM yyyy, h:mm a').format(o.createdAt)),
                      if (o.preferredDate.isNotEmpty)
                        _row('Wanted on', '${o.preferredDate}${o.preferredTime.isNotEmpty ? ' · ${o.preferredTime}' : ''}'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Deliver to', style: AppTextStyles.labelMedium),
                      const SizedBox(height: 8),
                      Text(o.patientName, style: AppTextStyles.h4),
                      if (o.deliveryAddress.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(o.deliveryAddress, style: AppTextStyles.bodyMedium),
                      ],
                      if (o.notes.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text('Note: ${o.notes}', style: AppTextStyles.bodySmall),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: o.patientPhone.isEmpty ? null : () => _call(context, o.patientPhone),
                              icon: const Icon(Icons.call_rounded, size: 18),
                              label: const Text('Call'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: o.deliveryAddress.isEmpty ? null : () => _navigate(context, o.deliveryAddress),
                              icon: const Icon(Icons.navigation_rounded, size: 18),
                              label: const Text('Navigate'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if ((o.status == EquipmentOrderStatus.cancelled || o.status == EquipmentOrderStatus.rejected) &&
                    (o.cancelReason ?? '').isNotEmpty) ...[
                  const SizedBox(height: 14),
                  PremiumCard(
                    child: Text('Reason: ${o.cancelReason}', style: AppTextStyles.bodyMedium),
                  ),
                ],
                const SizedBox(height: 20),
                EquipmentOrderActions(order: o),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasize = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: Text(label, style: AppTextStyles.bodySmall)),
            Expanded(
              flex: 6,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: emphasize ? AppTextStyles.labelLarge.copyWith(color: AppColors.primary) : AppTextStyles.labelMedium,
              ),
            ),
          ],
        ),
      );
}

/// Where the order is, as a horizontal step tracker.
class _StatusHeader extends StatelessWidget {
  final EquipmentOrder order;
  const _StatusHeader({required this.order});

  static const _rentSteps = ['Accepted', 'On the way', 'Delivered', 'Returned'];
  static const _buySteps = ['Accepted', 'On the way', 'Delivered'];

  int _stepIndex() {
    switch (order.status) {
      case EquipmentOrderStatus.accepted:
        return 0;
      case EquipmentOrderStatus.outForDelivery:
        return 1;
      case EquipmentOrderStatus.delivered:
        return order.isRent ? 2 : 2;
      case EquipmentOrderStatus.returned:
        return 3;
      case EquipmentOrderStatus.pending:
      case EquipmentOrderStatus.rejected:
      case EquipmentOrderStatus.cancelled:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = order.status;
    final failed = s == EquipmentOrderStatus.rejected || s == EquipmentOrderStatus.cancelled;
    final steps = order.isRent ? _rentSteps : _buySteps;
    final current = _stepIndex();
    // A buy order is complete once delivered; a rental once returned.
    final doneIndex = order.isRent ? 3 : 2;

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(label: s.label, color: s.color, dot: true),
              const Spacer(),
              Text('#${order.id.length > 6 ? order.id.substring(0, 6).toUpperCase() : order.id}',
                  style: AppTextStyles.caption),
            ],
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                s == EquipmentOrderStatus.rejected
                    ? 'You declined this order. The patient was refunded.'
                    : 'This order was cancelled${order.cancelledBy == 'patient' ? ' by the patient' : ''}. '
                        'Any held stock was restored.',
                style: AppTextStyles.bodySmall,
              ),
            )
          else if (s == EquipmentOrderStatus.pending)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Waiting for you. Accept to hold the stock and start fulfilment — '
                'an unanswered order is auto-cancelled and refunded.',
                style: AppTextStyles.bodySmall,
              ),
            )
          else ...[
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i <= current ? AppColors.success : AppColors.surfaceVariant,
                          ),
                          child: Icon(
                            i <= current ? Icons.check_rounded : Icons.circle,
                            size: i <= current ? 16 : 6,
                            color: i <= current ? Colors.white : AppColors.textHint,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          steps[i],
                          textAlign: TextAlign.center,
                          style: AppTextStyles.caption.copyWith(
                            color: i <= current ? AppColors.textPrimary : AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < steps.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: SizedBox(
                        width: 14,
                        child: Divider(
                          thickness: 2,
                          color: i < current ? AppColors.success : AppColors.divider,
                        ),
                      ),
                    ),
                ],
              ],
            ),
            if (current >= doneIndex)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Order complete.', style: AppTextStyles.bodySmall),
              ),
          ],
        ],
      ),
    );
  }
}
