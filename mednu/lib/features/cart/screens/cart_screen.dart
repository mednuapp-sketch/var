import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/booking_service.dart';
import '../../../core/services/feedback_service.dart';
import '../models/cart_item.dart';
import '../providers/cart_provider.dart';
import '../widgets/checkout_details_sheet.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  bool _checkingOut = false;

  Future<void> _checkout() async {
    final items = ref.read(cartProvider);
    if (items.isEmpty) return;

    final details = await CheckoutDetailsSheet.show(context, themeColor: AppColors.primary);
    if (details == null || !mounted) return;

    final total = ref.read(cartTotalProvider);
    final paid = await context.push<bool>(
      AppRoutes.payment,
      extra: {'amount': total.toString(), 'description': 'MedNU Cart (${items.length} item${items.length == 1 ? '' : 's'})'},
    );
    if (!mounted || paid != true) return;

    setState(() => _checkingOut = true);
    FeedbackService.showLoading(context, 'Placing your order...');

    final failed = <CartItem>[];
    final medicineItems = items.where((i) => i.type == 'medicine').toList();
    final serviceItems = items.where((i) => i.type != 'medicine').toList();

    for (final item in serviceItems) {
      try {
        await BookingService.createRequest(
          type: item.type,
          serviceName: item.serviceName,
          patientName: details.name,
          patientPhone: details.phone,
          address: details.address,
          preferredDate: details.date,
          preferredTime: details.time,
          notes: details.notes,
          serviceDetails: item.serviceDetails,
          amount: item.totalAmount,
        );
      } catch (_) {
        failed.add(item);
      }
    }

    if (medicineItems.isNotEmpty) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
        if (uid.isNotEmpty) {
          await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
            'orderId': orderId,
            'patientId': uid,
            'items': medicineItems
                .map((i) => {
                      'id': i.serviceDetails['id'],
                      'name': i.serviceDetails['name'] ?? i.serviceName,
                      'brand': i.serviceDetails['brand'],
                      'price': i.unitAmount,
                      'count': i.quantity,
                    })
                .toList(),
            'total': medicineItems.fold<int>(0, (s, i) => s + i.totalAmount),
            'status': 'confirmed',
            'deliveryAddress': details.address,
            'deliveryName': details.name,
            'deliveryPhone': details.phone,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {
        failed.addAll(medicineItems);
      }
    }

    if (!mounted) return;
    FeedbackService.dismiss(context);
    setState(() => _checkingOut = false);

    if (failed.isEmpty) {
      ref.read(cartProvider.notifier).clear();
      FeedbackService.showSuccess(context, 'Order placed successfully!');
      context.go(AppRoutes.myServices);
    } else {
      for (final f in failed) {
        ref.read(cartProvider.notifier).removeItem(f.id);
      }
      FeedbackService.showError(
        context,
        '${failed.length} item${failed.length == 1 ? '' : 's'} could not be booked. They remain in your cart — please retry.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text('My Cart', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(cartProvider.notifier).clear(),
              child: const Text('Clear', style: TextStyle(fontFamily: 'Poppins', color: AppColors.error, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: items.isEmpty ? _buildEmpty() : _buildList(items),
      bottomNavigationBar: items.isEmpty ? null : _buildCheckoutBar(total),
    );
  }

  Widget _buildEmpty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shopping_cart_outlined, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('Your cart is empty', style: AppTextStyles.h4),
            const SizedBox(height: 6),
            Text(
              'Add medicines or services to get started',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );

  Widget _buildList(List<CartItem> items) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _CartItemTile(item: items[i]),
      );

  Widget _buildCheckoutBar(int total) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _checkingOut ? null : _checkout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _checkingOut
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : Text('Checkout  •  ₹$total',
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
            ),
          ),
        ),
      );
}

class _CartItemTile extends ConsumerWidget {
  final CartItem item;
  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: item.themeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.medical_services_rounded, color: item.themeColor, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.serviceName,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: context.appTextPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('₹${item.unitAmount} x ${item.quantity} = ₹${item.totalAmount}',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: context.appTextSecondary)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          height: 30,
          decoration: BoxDecoration(color: item.themeColor, borderRadius: BorderRadius.circular(9)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: () => ref.read(cartProvider.notifier).decrementQty(item.id),
              child: const SizedBox(width: 26, height: 30, child: Icon(Icons.remove_rounded, size: 15, color: Colors.white)),
            ),
            SizedBox(
                width: 20,
                child: Text('${item.quantity}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
            InkWell(
              onTap: () => ref.read(cartProvider.notifier).incrementQty(item.id),
              child: const SizedBox(width: 26, height: 30, child: Icon(Icons.add_rounded, size: 15, color: Colors.white)),
            ),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.close_rounded, size: 18, color: context.appTextHint),
          onPressed: () => ref.read(cartProvider.notifier).removeItem(item.id),
        ),
      ]),
    );
  }
}
