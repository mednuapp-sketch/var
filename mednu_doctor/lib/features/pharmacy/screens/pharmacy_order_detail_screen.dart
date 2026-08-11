import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/pharmacy_order.dart';
import '../providers/pharmacy_providers.dart';
import '../services/pharmacy_order_service.dart';
import '../services/pharmacy_profile_service.dart';

/// Every status transition in the Pharmacy module's pipeline happens from
/// this one screen — accept/cancel, verify prescription (with optional
/// photo attach), pack, dispatch, deliver. Same shape as the Lab module's
/// booking detail screen: each action is a single `PharmacyOrderService`
/// call, and the realtime `orderDetailProvider`/`orderItemsProvider`
/// streams are what actually update the UI.
class PharmacyOrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const PharmacyOrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<PharmacyOrderDetailScreen> createState() => _PharmacyOrderDetailScreenState();
}

class _PharmacyOrderDetailScreenState extends ConsumerState<PharmacyOrderDetailScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? successMessage}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (successMessage != null && mounted) {
        FeedbackService.showSuccess(context, successMessage);
      }
    } on PharmacyOrderConflictException catch (e) {
      if (mounted) FeedbackService.showError(context, e.message);
    } catch (e) {
      if (mounted) FeedbackService.showError(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadPrescription(PharmacyOrder order) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    final uid = PharmacyProfileService.currentUid;
    if (uid == null) return;

    await _run(
      () => PharmacyOrderService.uploadPrescriptionPhoto(
        orderId: order.id,
        pharmacyId: uid,
        file: File(path),
      ),
      successMessage: 'Prescription attached',
    );
  }

  Future<void> _rejectPrescription(PharmacyOrder order, String uid) async {
    final reason = await _reasonDialog(
      title: 'Reject Prescription',
      hint: 'e.g. Prescription is expired / for a different medicine',
      confirmLabel: 'Reject & Cancel Order',
      confirmColor: AppColors.error,
    );
    if (reason == null || reason.isEmpty) return;
    await _run(
      () => PharmacyOrderService.rejectPrescription(order.id, pharmacyId: uid, reason: reason),
      successMessage: 'Prescription rejected — order cancelled',
    );
  }

  Future<void> _requestClearerPrescription(PharmacyOrder order, String uid) async {
    final reason = await _reasonDialog(
      title: 'Request a Clearer Prescription',
      hint: 'e.g. The photo is blurry — please retake in good lighting',
      confirmLabel: 'Request Re-upload',
      confirmColor: AppColors.warning,
    );
    if (reason == null || reason.isEmpty) return;
    await _run(
      () => PharmacyOrderService.requestClearerPrescription(order.id, pharmacyId: uid, reason: reason),
      successMessage: 'Asked the patient for a clearer prescription',
    );
  }

  Future<String?> _reasonDialog({
    required String title,
    required String hint,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint, labelText: 'Reason (shown to the patient)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(dialogContext, text);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _markOutForDelivery(PharmacyOrder order, String uid) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Out for Delivery'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Delivery person name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || ctrl.text.trim().isEmpty) return;

    await _run(
      () => PharmacyOrderService.markOutForDelivery(
        order.id,
        pharmacyId: uid,
        deliveryPersonName: ctrl.text.trim(),
      ),
      successMessage: 'Order is out for delivery',
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderId));
    final uid = PharmacyProfileService.currentUid;

    return SharedAppShell(
      currentRoute: '',
      title: 'Order Details',
      showBottomNav: false,
      body: orderAsync.when(
        loading: () => const PageLoadingState(),
        error: (_, __) => const NetworkErrorState(),
        data: (order) {
          if (order == null) {
            return const AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Order not found',
              message: 'This order may have been removed.',
            );
          }
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              order.orderType == PharmacyOrderType.equipment
                                  ? 'Equipment Order'
                                  : 'Medicine Order',
                              style: AppTextStyles.h4,
                            ),
                          ),
                          StatusBadge(label: order.status.label, color: order.status.color),
                        ],
                      ),
                      const SizedBox(height: 12),
                      InfoChip(icon: Icons.person_outline_rounded, label: order.patientName),
                      const SizedBox(height: 8),
                      if (order.patientPhone.isNotEmpty)
                        InfoChip(icon: Icons.call_outlined, label: order.patientPhone),
                      const SizedBox(height: 8),
                      if (order.deliveryAddress.isNotEmpty)
                        InfoChip(icon: Icons.location_on_outlined, label: order.deliveryAddress),
                      const SizedBox(height: 8),
                      InfoChip(
                        icon: Icons.currency_rupee_rounded,
                        label: CurrencyFormatter.format(order.totalAmount),
                      ),
                      if (order.deliveryPersonName != null) ...[
                        const SizedBox(height: 8),
                        InfoChip(
                          icon: Icons.local_shipping_outlined,
                          label: 'Delivery: ${order.deliveryPersonName}',
                          color: AppColors.secondary,
                        ),
                      ],
                      if (order.requiresPrescription) ...[
                        const SizedBox(height: 8),
                        InfoChip(
                          icon: Icons.medical_information_outlined,
                          label: order.prescriptionUrl != null
                              ? 'Prescription attached'
                              : 'Prescription required — not attached',
                          color: order.prescriptionUrl != null ? AppColors.success : AppColors.warning,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ItemsCard(orderId: order.id, orderType: order.orderType),
                const SizedBox(height: 20),
                ..._buildActions(order, uid),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildActions(PharmacyOrder order, String? uid) {
    if (uid == null) return const [];
    final isMine = order.pharmacyId == uid;

    switch (order.status) {
      case PharmacyOrderStatus.pending:
        return [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _run(() => PharmacyOrderService.cancelOrder(order.id, uid)),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientButton(
                  label: 'Accept Order',
                  isLoading: _busy,
                  onTap: () => _run(
                    () => PharmacyOrderService.acceptOrder(order.id, uid),
                    successMessage: 'Order accepted',
                  ),
                ),
              ),
            ],
          ),
        ];
      case PharmacyOrderStatus.prescriptionRequired:
        return isMine
            ? [
                if (order.hasPrescription) ...[
                  _PrescriptionPreview(order: order),
                  const SizedBox(height: 16),
                ],
                OutlinedButton.icon(
                  onPressed: () => _uploadPrescription(order),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(order.hasPrescription ? 'Attach a Different Copy' : 'Attach Prescription'),
                ),
                const SizedBox(height: 12),
                GradientButton(
                  label: 'Mark Verified',
                  icon: Icons.check_circle_outline_rounded,
                  isLoading: _busy,
                  onTap: order.hasPrescription
                      ? () => _run(
                            () => PharmacyOrderService.verifyPrescription(order.id, pharmacyId: uid),
                            successMessage: 'Prescription verified',
                          )
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: order.hasPrescription ? () => _requestClearerPrescription(order, uid) : null,
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning),
                        child: const Text('Request Clearer Copy'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: order.hasPrescription ? () => _rejectPrescription(order, uid) : null,
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                        child: const Text('Reject'),
                      ),
                    ),
                  ],
                ),
              ]
            : const [];
      case PharmacyOrderStatus.verified:
        return isMine
            ? [
                GradientButton(
                  label: 'Mark Packed',
                  icon: Icons.inventory_2_outlined,
                  isLoading: _busy,
                  onTap: () => _run(
                    () => PharmacyOrderService.markPacked(order.id, pharmacyId: uid),
                    successMessage: 'Order marked as packed',
                  ),
                ),
              ]
            : const [];
      case PharmacyOrderStatus.packed:
        return isMine
            ? [
                GradientButton(
                  label: 'Out for Delivery',
                  icon: Icons.local_shipping_outlined,
                  isLoading: _busy,
                  onTap: () => _markOutForDelivery(order, uid),
                ),
              ]
            : const [];
      case PharmacyOrderStatus.outForDelivery:
        return isMine
            ? [
                GradientButton(
                  label: 'Mark Delivered',
                  icon: Icons.task_alt_rounded,
                  isLoading: _busy,
                  onTap: () => _run(
                    () => PharmacyOrderService.markDelivered(order.id, pharmacyId: uid),
                    successMessage: 'Order delivered',
                  ),
                ),
              ]
            : const [];
      case PharmacyOrderStatus.delivered:
      case PharmacyOrderStatus.cancelled:
      case PharmacyOrderStatus.unknown:
        return const [];
    }
  }
}

class _ItemsCard extends ConsumerWidget {
  final String orderId;
  final PharmacyOrderType orderType;
  const _ItemsCard({required this.orderId, required this.orderType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(orderItemsProvider(orderId));
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(orderType == PharmacyOrderType.equipment ? 'Equipment' : 'Items', style: AppTextStyles.labelMedium),
          const SizedBox(height: 10),
          itemsAsync.when(
            loading: () => const ListLoadingState(itemCount: 2, hasAvatar: false),
            error: (_, __) => const NetworkErrorState(),
            data: (items) {
              if (items.isEmpty) {
                return const Text('No items found.', style: AppTextStyles.bodySmall);
              }
              return Column(
                children: items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name, style: AppTextStyles.bodyLarge),
                              if (item.brand.isNotEmpty)
                                Text(item.brand, style: AppTextStyles.caption),
                            ],
                          ),
                        ),
                        Text('x${item.count}', style: AppTextStyles.bodyMedium),
                        const SizedBox(width: 10),
                        Text(CurrencyFormatter.format(item.subtotal), style: AppTextStyles.labelMedium),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The patient-uploaded (or pharmacy-attached) prescription — a zoomable
/// image preview via [InteractiveViewer]/full-screen viewer, or an "Open
/// PDF" tile that hands off to the device's PDF viewer via `url_launcher`
/// (same pattern already used by the Lab module's Reports screen).
class _PrescriptionPreview extends StatelessWidget {
  final PharmacyOrder order;
  const _PrescriptionPreview({required this.order});

  Future<void> _openPdf(BuildContext context) async {
    final url = order.prescriptionUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null) {
      // launchUrl *throws* (ACTIVITY_NOT_FOUND) when no viewer/browser is
      // installed rather than returning false.
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && context.mounted) {
      FeedbackService.showError(context, 'Could not open the file.');
    }
  }

  void _openZoomViewer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ZoomImageViewer(imageUrl: order.prescriptionUrl!),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPdf = order.prescriptionFileType == 'pdf';
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: GestureDetector(
        onTap: () => isPdf ? _openPdf(context) : _openZoomViewer(context),
        child: isPdf
            ? Container(
                height: 140,
                width: double.infinity,
                color: AppColors.surfaceVariant,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf_rounded, size: 40, color: AppColors.error),
                      SizedBox(height: 6),
                      Text('Tap to open PDF', style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
              )
            : Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CachedNetworkImage(
                    imageUrl: order.prescriptionUrl!,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const SkeletonBox(width: double.infinity, height: 220, radius: 14),
                    errorWidget: (_, __, ___) => const NetworkErrorState(),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ZoomImageViewer extends StatelessWidget {
  final String imageUrl;
  const _ZoomImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 6,
          child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
