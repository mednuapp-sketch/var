import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/order_model.dart';
import '../providers/order_providers.dart';
import '../widgets/prescription_card.dart';

// A patient can cancel from any non-terminal status — the backend
// (onMedicineOrderCancelledByPatient in functions/index.js) mirrors any
// orders.status -> 'cancelled' write onto pharmacy_orders automatically, and
// firestore.rules already allow-lists 'status'/'cancelReason'/'updatedAt' as
// patient-self-updatable fields. Nothing server-side was missing — only this
// button.
const _kCancellableStatuses = {
  'confirmed', 'prescription_required', 'verified', 'packed', 'out_for_delivery',
};

Future<void> _cancelOrder(BuildContext context, String orderId) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Cancel Order',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      content: const Text(
        'Are you sure you want to cancel this order?\nThis action cannot be undone.',
        style: TextStyle(fontFamily: 'Poppins', height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep Order'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Cancel Order', style: TextStyle(fontFamily: 'Poppins')),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  FeedbackService.showLoading(context, 'Cancelling order...');
  try {
    await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
      'status': 'cancelled',
      'cancelReason': 'Cancelled by patient',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (context.mounted) {
      FeedbackService.dismiss(context);
      FeedbackService.showSuccess(context, 'Order cancelled successfully');
    }
  } catch (e) {
    if (context.mounted) {
      FeedbackService.showError(
        context,
        'Failed to cancel order. Please try again.',
        onRetry: () => _cancelOrder(context, orderId),
      );
    }
  }
}

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
          const SliverToBoxAdapter(child: GradientAppBar(title: 'Order Details')),
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
          // Only present when checkout captured a map location rather than a
          // typed address (order_model.dart's recipientLocation.{lat,lng}) —
          // no live courier position exists for medicine delivery (unlike
          // ambulance), so this is a static pin on the delivery address, not
          // a live-tracking map.
          if (order.deliveryLat != null && order.deliveryLng != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 140,
                child: IgnorePointer(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(order.deliveryLat!, order.deliveryLng!),
                      zoom: 15,
                    ),
                    liteModeEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    markers: {
                      Marker(
                        markerId: const MarkerId('delivery'),
                        position: LatLng(order.deliveryLat!, order.deliveryLng!),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                      ),
                    },
                  ),
                ),
              ),
            ),
          ],
          if (_deliveringToSomeoneElse()) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Delivering to ${order.deliveryName} · ${order.deliveryPhone}',
                  style: AppTextStyles.bodySmall,
                ),
              ),
            ]),
          ],
          if (_kCancellableStatuses.contains(order.status)) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _cancelOrder(context, order.orderId),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel Order',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Only surface this when the order was placed for someone other than the
  // account holder — compared by phone (the stable identifier in this
  // phone-auth app) rather than name, which is free text at checkout.
  bool _deliveringToSomeoneElse() {
    if (order.deliveryName.trim().isEmpty || order.deliveryPhone.trim().isEmpty) return false;
    final myPhoneRaw = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    final myPhone = myPhoneRaw.startsWith('+91') ? myPhoneRaw.substring(3) : myPhoneRaw;
    return order.deliveryPhone.trim() != myPhone;
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
