import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/cart_item.dart';
import '../providers/cart_provider.dart';
import '../providers/pending_prescription_provider.dart';
import '../widgets/checkout_details_sheet.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  bool _checkingOut = false;

  Future<void> _checkout() async {
    // Guard the whole flow, not just the post-payment writes — the details
    // sheet and the payment screen are both awaited, so without this a fast
    // double-tap could open two checkout flows and charge twice.
    if (_checkingOut) return;
    final items = ref.read(cartProvider);
    if (items.isEmpty) return;

    setState(() => _checkingOut = true);

    // capturePayment/captureCartPayment (functions/index.js) create every
    // booking doc themselves once the charge is verified — nothing here
    // writes to Firestore before or after. Medicine items are bundled into
    // one `orders` item (matching the previous single combined order); every
    // other item becomes its own `service_requests` item, in the same shape
    // BookingService.createRequest used to write by hand.
    Map<String, dynamic>? result;
    try {
      final details = await CheckoutDetailsSheet.show(context, themeColor: AppColors.primary);
      if (details == null || !mounted) return;
      final d = details;

      final medicineItems = items.where((i) => i.type == 'medicine').toList();
      final serviceItems = items.where((i) => i.type != 'medicine').toList();

      final cartItems = <Map<String, dynamic>>[
        for (final item in serviceItems)
          {
            'serviceType': item.type,
            'bookingCollection': 'service_requests',
            'amount': item.totalAmount,
            'bookingData': {
              'type': item.type,
              'serviceName': item.serviceName,
              'patientName': d.name,
              'patientPhone': d.phone,
              'address': d.address,
              if (d.locationData != null) 'recipientLocation': d.locationData,
              'preferredDate': d.date,
              'preferredTime': d.time,
              'notes': d.notes,
              'serviceDetails': item.serviceDetails,
              'amount': item.totalAmount,
              'status': 'pending',
              'assignedTo': null,
            },
          },
        if (medicineItems.isNotEmpty)
          {
            'serviceType': 'medicine',
            'bookingCollection': 'orders',
            'amount': medicineItems.fold<int>(0, (s, i) => s + i.totalAmount),
            'bookingData': {
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
              'deliveryAddress': d.address,
              'deliveryName': d.name,
              'deliveryPhone': d.phone,
              if (d.locationData != null) 'recipientLocation': d.locationData,
              // The cart lock (CartNotifier.conflictFor) guarantees every
              // medicine item shares one pharmacy by checkout time, so it's
              // safe to hoist just the first item's source pharmacy here.
              // onMedicineOrderCreated (functions/index.js) reads this to pin
              // the resulting order instead of dropping it in the unclaimed
              // pool; captureCartPayment also reads it for commission
              // attribution (_PROVIDER_FIELD_BY_SERVICE.medicine).
              'pharmacyId': medicineItems.first.serviceDetails['sourcePharmacyId'],
              // Attached from the medicine browsing screen before this order
              // existed (see medicine_screen.dart's Upload Prescription
              // action) — captureCartPayment (functions/index.js) writes
              // `bookingData` verbatim onto the new orders/{orderId} doc, so
              // these land exactly like a post-purchase upload would, just
              // already there when the order is created. No
              // prescriptionUploadedAt here: FieldValue.serverTimestamp()
              // doesn't survive the callable-function JSON boundary, and
              // OrderModel treats a missing timestamp as fine (null).
              if (ref.read(pendingPrescriptionProvider) != null) ...{
                'prescriptionUrl': ref.read(pendingPrescriptionProvider)!.url,
                'prescriptionFileType': ref.read(pendingPrescriptionProvider)!.fileType,
              },
            },
          },
      ];

      result = await context.push<Map<String, dynamic>>(
        AppRoutes.payment,
        extra: {
          'amount': cartItems.fold<int>(0, (s, it) => s + (it['amount'] as int)).toString(),
          'description': 'MedNU Cart (${items.length} item${items.length == 1 ? '' : 's'})',
          'cartItems': cartItems,
        },
      );
    } finally {
      // Every abandon path above (cancelled sheet, cancelled/failed payment,
      // disposed screen) has to release the button again.
      if (mounted && result?['payments'] == null) setState(() => _checkingOut = false);
    }

    if (!mounted || result?['payments'] == null) return;

    final payments = (result!['payments'] as List).cast<Map>();
    ref.read(cartProvider.notifier).clear();
    ref.read(pendingPrescriptionProvider.notifier).state = null;
    setState(() => _checkingOut = false);
    FeedbackService.showSuccess(context, 'Order placed successfully!');

    // A placed medicine order can need a prescription — take the patient
    // straight to where they can upload one rather than the general
    // services tracker. Every other booking type keeps the existing
    // behavior unchanged.
    final medicinePayment = payments.cast<Map<String, dynamic>>().where((p) => p['serviceType'] == 'medicine');
    if (medicinePayment.isNotEmpty) {
      context.push(AppRoutes.orderDetail, extra: {'orderId': medicinePayment.first['bookingId']});
    } else {
      context.go(AppRoutes.myServices);
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
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), tooltip: 'Back', onPressed: () => context.pop()),
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

  Widget _buildEmpty() => AppEmptyState(
        icon: Icons.shopping_cart_outlined,
        title: 'Your cart is empty',
        message: 'Add medicines or services to get started',
        actionLabel: 'Browse Services',
        onAction: () => context.push(AppRoutes.home),
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
          // Was a hardcoded white, which left the checkout bar a bright slab
          // over the dark background in dark mode. Every other surface in
          // this screen already uses the theme token.
          color: context.appSurface,
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
        const SizedBox(width: 4),
        Container(
          height: 44,
          decoration: BoxDecoration(color: item.themeColor, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Tooltip(
              message: 'Decrease quantity',
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                onTap: () => ref.read(cartProvider.notifier).decrementQty(item.id),
                child: const SizedBox(width: 40, height: 44, child: Icon(Icons.remove_rounded, size: 16, color: Colors.white)),
              ),
            ),
            SizedBox(
                width: 22,
                child: Text('${item.quantity}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
            Tooltip(
              message: 'Increase quantity',
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                onTap: () => ref.read(cartProvider.notifier).incrementQty(item.id),
                child: const SizedBox(width: 40, height: 44, child: Icon(Icons.add_rounded, size: 16, color: Colors.white)),
              ),
            ),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.close_rounded, size: 18, color: context.appTextHint),
          tooltip: 'Remove item',
          onPressed: () => ref.read(cartProvider.notifier).removeItem(item.id),
        ),
      ]),
    );
  }
}
