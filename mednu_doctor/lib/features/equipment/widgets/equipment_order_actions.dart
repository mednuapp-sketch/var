import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/mednu_components.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/equipment_order.dart';
import '../services/equipment_order_service.dart';

/// The action buttons for one order, driven entirely by its status — the
/// single place the vendor moves an order through its lifecycle. Used both
/// inline on an order card (`compact`, New tab) and on the detail screen.
class EquipmentOrderActions extends StatefulWidget {
  final EquipmentOrder order;
  final bool compact;

  const EquipmentOrderActions({super.key, required this.order, this.compact = false});

  @override
  State<EquipmentOrderActions> createState() => _EquipmentOrderActionsState();
}

class _EquipmentOrderActionsState extends State<EquipmentOrderActions> {
  bool _busy = false;

  EquipmentOrder get order => widget.order;

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && success != null) FeedbackService.showSuccess(context, success);
    } on InsufficientStockException catch (e) {
      if (mounted) {
        FeedbackService.showError(
          context,
          'Not enough stock — you have ${e.available}, the order needs ${e.requested}. '
          'Update your units or decline the order.',
        );
      }
    } on OrderNoLongerActionableException catch (e) {
      if (mounted) FeedbackService.showError(context, 'This order is already ${e.currentStatus.replaceAll('_', ' ')}.');
    } catch (_) {
      if (mounted) FeedbackService.showError(context, 'Could not update the order. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason(String title, String hint) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 2,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ).whenComplete(() {
      // Deferred: the dialog's TextField is still mid-exit-animation here.
      Future.delayed(const Duration(milliseconds: 400), ctrl.dispose);
    });
  }

  Future<void> _decline() async {
    final reason = await _askReason('Decline this order?', 'Reason for the patient (optional)');
    if (reason == null || !mounted) return;
    await _run(() => EquipmentOrderService.reject(order.id, reason: reason),
        success: 'Order declined — the patient will be refunded.');
  }

  Future<void> _cancel() async {
    final reason = await _askReason('Cancel this order?', 'Why can\'t you fulfil it? (optional)');
    if (reason == null || !mounted) return;
    await _run(() => EquipmentOrderService.cancel(order.id, reason: reason),
        success: 'Order cancelled — stock restored and the patient refunded.');
  }

  Future<void> _confirm(String title, String message, String label, Future<void> Function() action, String success) async {
    final ok = await MedNuConfirmationDialog.show(context, title: title, message: message, confirmLabel: label);
    if (!ok || !mounted) return;
    await _run(action, success: success);
  }

  @override
  Widget build(BuildContext context) {
    final id = order.id;

    Widget primary(String label, IconData icon, VoidCallback onTap) =>
        GradientButton(label: label, icon: icon, isLoading: _busy, onTap: _busy ? null : onTap);

    Widget secondary(String label, VoidCallback onTap, {Color color = AppColors.error}) => OutlinedButton(
          onPressed: _busy ? null : onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.5)),
            minimumSize: const Size.fromHeight(46),
          ),
          child: Text(label),
        );

    switch (order.status) {
      case EquipmentOrderStatus.pending:
        final accept = primary('Accept', Icons.check_rounded, () => _run(() => EquipmentOrderService.accept(id), success: 'Order accepted'));
        final decline = secondary('Decline', _decline);
        return widget.compact
            ? Row(children: [Expanded(child: decline), const SizedBox(width: 10), Expanded(child: accept)])
            : Column(children: [accept, const SizedBox(height: 10), decline]);

      case EquipmentOrderStatus.accepted:
        return Column(children: [
          primary('Mark out for delivery', Icons.local_shipping_rounded,
              () => _run(() => EquipmentOrderService.markOutForDelivery(id), success: 'Marked out for delivery')),
          const SizedBox(height: 10),
          secondary('Cancel order', _cancel),
        ]);

      case EquipmentOrderStatus.outForDelivery:
        return Column(children: [
          primary(
            'Mark delivered',
            Icons.inventory_rounded,
            () => _confirm(
              'Confirm delivery',
              order.isRent
                  ? 'The patient has the equipment${order.deposit > 0 ? ' and you collected the ₹${order.deposit} deposit' : ''}. '
                      'This credits your earnings.'
                  : 'The patient has received the equipment. This credits your earnings.',
              'Delivered',
              () => EquipmentOrderService.markDelivered(id),
              'Delivered — earnings credited',
            ),
          ),
          const SizedBox(height: 10),
          secondary('Cancel order', _cancel),
        ]);

      case EquipmentOrderStatus.delivered:
        if (!order.isRent) return const SizedBox.shrink();
        return primary(
          'Mark returned',
          Icons.assignment_return_rounded,
          () => _confirm(
            'Rental returned?',
            'The equipment is back with you${order.deposit > 0 ? '. Remember to refund the ₹${order.deposit} deposit' : ''}. '
                'The unit goes back on your menu.',
            'Returned',
            () => EquipmentOrderService.markReturned(id),
            'Marked returned — back on your menu',
          ),
        );

      case EquipmentOrderStatus.returned:
      case EquipmentOrderStatus.rejected:
      case EquipmentOrderStatus.cancelled:
        return const SizedBox.shrink();
    }
  }
}
