import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/order_model.dart';
import '../services/prescription_upload_service.dart';
import '../screens/prescription_preview_screen.dart';
import 'prescription_source_sheet.dart';

/// The prescription section of the order detail screen — upload / preview /
/// replace / remove, plus the verification status once the assigned
/// pharmacy has reviewed it. All state comes from [order] (the caller's
/// realtime `orderDetailProvider` watch) — this widget never opens its own
/// Firestore listener.
class PrescriptionCard extends StatelessWidget {
  final OrderModel order;

  const PrescriptionCard({super.key, required this.order});

  Future<void> _startUploadFlow(BuildContext context) async {
    final file = await showPrescriptionSourceSheet(context);
    if (file == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrescriptionPreviewScreen(
          file: file,
          onUpload: (f, onProgress) => PrescriptionUploadService.upload(
            orderId: order.orderId,
            file: f,
            onProgress: onProgress,
          ),
        ),
      ),
    );
  }

  Future<void> _remove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Prescription'),
        content: const Text('Are you sure you want to remove this prescription? You can upload a new one anytime.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PrescriptionUploadService.remove(orderId: order.orderId, existingUrl: order.prescriptionUrl);
      if (context.mounted) FeedbackService.showSuccess(context, 'Prescription removed');
    } on PrescriptionLockedException {
      if (context.mounted) {
        FeedbackService.showError(context, 'The pharmacy has already accepted your prescription, so it can no longer be removed.');
      }
    } catch (e) {
      if (context.mounted) FeedbackService.showError(context, 'Could not remove the prescription. Please try again.');
    }
  }

  Future<void> _openFile(BuildContext context) async {
    final url = order.prescriptionUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) FeedbackService.showError(context, 'Could not open the file.');
    }
  }

  // Same mechanism prescription_viewer_screen.dart already uses for its own
  // Share/Download buttons: hand the file to the OS share sheet, which
  // offers "Save to Files/Downloads" as a target — actual on-device storage
  // download needs extra runtime permissions on Android 10+ that this app
  // deliberately avoids. Downloads the real Storage bytes to a temp file
  // first (unlike the viewer's version, which synthesizes a PDF from
  // structured data — this file already exists, it's the uploaded scan).
  Future<File> _downloadToTemp() async {
    final url = order.prescriptionUrl!;
    final ext = order.prescriptionFileType == 'pdf' ? 'pdf' : 'jpg';
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/prescription_${order.orderId}.$ext';
    await Dio().download(url, path);
    return File(path);
  }

  Future<void> _share(BuildContext context) async {
    try {
      final file = await _downloadToTemp();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: order.prescriptionFileType == 'pdf' ? 'application/pdf' : 'image/jpeg')],
        subject: 'Prescription — Order #${order.orderId}',
      );
    } catch (_) {
      if (context.mounted) FeedbackService.showError(context, 'Could not share the file. Please try again.');
    }
  }

  Future<void> _download(BuildContext context) async {
    try {
      final file = await _downloadToTemp();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: order.prescriptionFileType == 'pdf' ? 'application/pdf' : 'image/jpeg')],
        subject: 'Prescription — Order #${order.orderId}',
        text: 'Choose "Save to Files" / "Save Image" to keep a copy on this device.',
      );
    } catch (_) {
      if (context.mounted) FeedbackService.showError(context, 'Download failed. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkCard : Colors.white;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.divider),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.medical_information_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('Prescription', style: AppTextStyles.h4.copyWith(color: isDark ? Colors.white : AppColors.textPrimary)),
              const Spacer(),
              if (order.hasPrescription) _statusBadge(),
            ],
          ),
          const SizedBox(height: 12),
          if (!order.hasPrescription && order.isPrescriptionLocked)
            Text(
              'No prescription was attached to this order.',
              style: AppTextStyles.bodySmall.copyWith(color: isDark ? Colors.white70 : AppColors.textSecondary),
            )
          else if (!order.hasPrescription)
            AppEmptyState(
              icon: Icons.upload_file_rounded,
              title: 'No prescription uploaded',
              message: 'Upload a photo or PDF so the pharmacy can verify and prepare your order.',
              actionLabel: 'Upload Prescription',
              onAction: () => _startUploadFlow(context),
            )
          else ...[
            GestureDetector(
              onTap: () => _openFile(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: order.prescriptionFileType == 'pdf'
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
                    : CachedNetworkImage(
                        imageUrl: order.prescriptionUrl!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const SkeletonBox(width: double.infinity, height: 180, radius: 14),
                        errorWidget: (_, __, ___) => const AppErrorState(message: 'Could not load the image'),
                      ),
              ),
            ),
            if (order.prescriptionAttachedByPharmacy) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.local_pharmacy_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text('Attached by the pharmacy', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
                ],
              ),
            ],
            if (order.prescriptionWasRejected && order.prescriptionRejectedReason != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(order.prescriptionRejectedReason!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _share(context),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _download(context),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Driven by the realtime order stream: the moment the pharmacy
            // accepts, Replace/Remove disappear without a refresh.
            if (order.isPrescriptionLocked)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_rounded, color: AppColors.success, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order.status == 'cancelled'
                            ? 'This order is cancelled — the prescription can no longer be changed or removed.'
                            : 'Accepted by the pharmacy — this prescription can no longer be changed or removed.',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.success),
                      ),
                    ),
                  ],
                ),
              )
            else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _startUploadFlow(context),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Replace'),
                  ),
                ),
                // The pharmacy's own copy can be replaced by a fresh upload
                // but not deleted from the patient side.
                if (!order.prescriptionAttachedByPharmacy) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _remove(context),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Remove'),
                  ),
                ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge() {
    if (order.prescriptionVerified == true) {
      return const StatusBadge(label: 'Verified', color: AppColors.success, icon: Icons.check_circle_rounded);
    }
    if (order.status == 'cancelled') {
      return const StatusBadge(label: 'Order Cancelled', color: AppColors.error, icon: Icons.cancel_outlined);
    }
    if (order.prescriptionVerified == false) {
      return const StatusBadge(label: 'Action Needed', color: AppColors.error, icon: Icons.error_outline_rounded);
    }
    // No-prescription orders are accepted straight to 'verified' without a
    // formal verdict — don't leave them saying "Pending Review" forever.
    if (order.isPrescriptionLocked) {
      return const StatusBadge(label: 'Accepted', color: AppColors.success, icon: Icons.check_circle_rounded);
    }
    return const StatusBadge(label: 'Pending Review', color: AppColors.warning, icon: Icons.hourglass_top_rounded);
  }
}
