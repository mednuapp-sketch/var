import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/r.dart';
import '../../core/widgets/ux_widgets.dart';
import 'partner_document_models.dart';
import 'partner_document_service.dart';

/// The "Documents" section every partner profile screen shows — one
/// [PartnerDocumentUploadCard] per canonical docType for that role.
///
/// Responsive per the app's 600 dp tablet breakpoint (`R.isTablet`): a single
/// column on phones, two columns on tablet/web, laid out with a [Wrap] so it
/// never introduces a nested scrollable inside the host `ListView`.
class PartnerDocumentsSection extends StatelessWidget {
  /// 'lab' | 'pharmacy' | 'ambulance' | 'caregiver'.
  final String role;
  final String uid;

  /// Raw `documents` / `documentVerification` maps straight off
  /// `{role}_profiles/{uid}` — passed in so this widget reuses the profile
  /// stream each screen already watches instead of opening a second listener.
  final Map<String, dynamic> documents;
  final Map<String, dynamic> documentVerification;

  const PartnerDocumentsSection({
    super.key,
    required this.role,
    required this.uid,
    required this.documents,
    required this.documentVerification,
  });

  @override
  Widget build(BuildContext context) {
    final types = PartnerDocumentType.forRole(role);
    if (types.isEmpty) return const SizedBox.shrink();

    final verifiedCount = types.where((t) {
      final meta = PartnerDocumentMeta.fromMap(documents[t.key]);
      return PartnerDocumentVerification.fromMap(
            documentVerification[t.key],
            hasDocument: meta != null,
            uploadedAt: meta?.uploadedAt,
          ).status ==
          PartnerDocumentStatus.verified;
    }).length;

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Flexible(
                child: Text('Documents', style: AppTextStyles.labelMedium),
              ),
              const Spacer(),
              StatusBadge(
                label: '$verifiedCount/${types.length} verified',
                color: verifiedCount == types.length
                    ? AppColors.success
                    : AppColors.warning,
                icon: verifiedCount == types.length
                    ? Icons.verified_rounded
                    : Icons.pending_outlined,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Uploaded documents are reviewed by the MedNu team. '
            'Only an admin can mark a document verified.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoUp = constraints.maxWidth >= 600;
              final itemWidth =
                  twoUp ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: types.map((type) {
                  final meta = PartnerDocumentMeta.fromMap(documents[type.key]);
                  return SizedBox(
                    width: itemWidth,
                    child: PartnerDocumentUploadCard(
                      role: role,
                      uid: uid,
                      type: type,
                      meta: meta,
                      verification: PartnerDocumentVerification.fromMap(
                        documentVerification[type.key],
                        hasDocument: meta != null,
                        uploadedAt: meta?.uploadedAt,
                      ),
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

/// A single document slot: empty ➜ uploading (with progress) ➜ uploaded
/// (thumbnail / PDF icon + View / Replace / Remove) ➜ error (with Retry).
///
/// The picked [File] is kept in local state until the upload succeeds so
/// "Retry" re-attempts the same pick instead of making the partner choose the
/// file again.
class PartnerDocumentUploadCard extends StatefulWidget {
  final String role;
  final String uid;
  final PartnerDocumentType type;
  final PartnerDocumentMeta? meta;
  final PartnerDocumentVerification verification;

  const PartnerDocumentUploadCard({
    super.key,
    required this.role,
    required this.uid,
    required this.type,
    required this.meta,
    required this.verification,
  });

  @override
  State<PartnerDocumentUploadCard> createState() =>
      _PartnerDocumentUploadCardState();
}

class _PartnerDocumentUploadCardState extends State<PartnerDocumentUploadCard> {
  File? _pending;
  bool _busy = false;
  double _progress = 0;
  String _uploadStatus = '';
  String? _error;

  PartnerDocumentService get _service =>
      PartnerDocumentService(widget.role, widget.uid);

  // ── Source sheet ─────────────────────────────────────────────────────────

  Future<void> _showSourceSheet() async {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(widget.type.label,
                      style: AppTextStyles.labelLarge),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded),
                  title: const Text('Take a Photo'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndUpload(source: ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Choose from Gallery'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndUpload(source: ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_rounded),
                  title: const Text('Upload a PDF'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndUpload(pdf: true);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _pickAndUpload({ImageSource? source, bool pdf = false}) async {
    final file = pdf
        ? await _service.pickPdf()
        : await _service.pickImage(source: source ?? ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() {
      _pending = file;
      _error = null;
    });
    await _upload(file);
  }

  Future<void> _upload(File file) async {
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
      _uploadStatus = 'Uploading ${widget.type.label}…';
    });
    try {
      await _service.uploadDocument(
        docType: widget.type.key,
        file: file,
        previousStoragePath: widget.meta?.storagePath,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pending = null;
        _uploadStatus = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _uploadStatus = '';
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _replace() async {
    final ok = await _confirm(
      title: 'Replace this document?',
      message: 'The previous file will be removed.',
      confirmLabel: 'Replace',
    );
    if (ok != true) return;
    await _showSourceSheet();
  }

  Future<void> _remove() async {
    final ok = await _confirm(
      title: 'Remove this document?',
      message:
          'It will be deleted and this slot will go back to "Not submitted".',
      confirmLabel: 'Remove',
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _uploadStatus = 'Removing…';
      _error = null;
    });
    try {
      await _service.removeDocument(
        docType: widget.type.key,
        storagePath: widget.meta?.storagePath,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pending = null;
        _uploadStatus = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _uploadStatus = '';
        _error = 'Could not remove this document. Please try again.';
      });
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _view() async {
    final meta = widget.meta;
    if (meta == null) return;

    // No in-app PDF renderer is bundled (and none may be added), so a PDF
    // opens in the device's external viewer/browser via its download URL.
    if (meta.isPdf) {
      final uri = Uri.tryParse(meta.url);
      var opened = false;
      if (uri != null) {
        try {
          opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          // No activity/handler for the URL — surfaced to the user below
          // instead of failing silently.
          opened = false;
        }
      }
      if (!opened && mounted) {
        setState(() => _error =
            'No app available to open this PDF. Install a PDF viewer or browser and try again.');
      }
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.network(
                  meta.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Could not load this document.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Status chip ──────────────────────────────────────────────────────────

  ({String label, Color color, IconData icon}) get _badge {
    switch (widget.verification.status) {
      case PartnerDocumentStatus.verified:
        return (
          label: 'Verified',
          color: AppColors.success,
          icon: Icons.verified_rounded
        );
      case PartnerDocumentStatus.rejected:
        return (
          label: 'Rejected',
          color: AppColors.error,
          icon: Icons.cancel_outlined
        );
      case PartnerDocumentStatus.pending:
        return (
          label: 'Pending review',
          color: AppColors.warning,
          icon: Icons.hourglass_bottom_rounded
        );
      case PartnerDocumentStatus.notSubmitted:
        return (
          label: 'Not submitted',
          color: AppColors.textSecondary,
          icon: Icons.upload_file_outlined
        );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final badge = _badge;

    return Container(
      padding: EdgeInsets.all(R.p(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(R.r(context, 14)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.type.label,
                  style: AppTextStyles.labelLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(
                  label: badge.label, color: badge.color, icon: badge.icon),
            ],
          ),
          const SizedBox(height: 10),
          if (_busy)
            _buildBusy()
          else if (_error != null)
            _buildError()
          else if (meta != null)
            _buildUploaded(meta)
          else
            _buildEmpty(),
          if (widget.verification.status == PartnerDocumentStatus.rejected &&
              (widget.verification.reason ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Reason: ${widget.verification.reason}',
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBusy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            minHeight: 6,
            backgroundColor: AppColors.divider,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Flexible(
              child: Text(
                _uploadStatus,
                style: AppTextStyles.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text('${(_progress * 100).round()}%',
                style: AppTextStyles.caption),
          ],
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 16, color: AppColors.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _error ?? 'Upload failed.',
                style: AppTextStyles.caption.copyWith(color: AppColors.error),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (_pending != null)
              TextButton.icon(
                onPressed: () => _upload(_pending!),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            TextButton.icon(
              onPressed: _showSourceSheet,
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: const Text('Choose another file'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return InkWell(
      onTap: _showSourceSheet,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_outlined,
                color: AppColors.primary, size: 26),
            SizedBox(height: 6),
            Text('Tap to upload', style: AppTextStyles.labelMedium),
            SizedBox(height: 2),
            Text('Photo or PDF · max 20 MB',
                style: AppTextStyles.caption, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildUploaded(PartnerDocumentMeta meta) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _thumbnail(meta),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    meta.fileName.isEmpty
                        ? (meta.isPdf ? 'Document.pdf' : 'Document.jpg')
                        : meta.fileName,
                    style: AppTextStyles.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _uploadedSubtitle(meta),
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 0,
          children: [
            TextButton.icon(
              onPressed: _view,
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('View'),
            ),
            TextButton.icon(
              onPressed: _replace,
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: const Text('Replace'),
            ),
            TextButton.icon(
              onPressed: _remove,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }

  String _uploadedSubtitle(PartnerDocumentMeta meta) {
    final size = meta.sizeBytes > 0
        ? '${(meta.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : null;
    final at = meta.uploadedAt;
    final when = at == null
        ? null
        : 'Uploaded ${at.day.toString().padLeft(2, '0')}/'
            '${at.month.toString().padLeft(2, '0')}/${at.year}';
    return [when, size].whereType<String>().join(' · ');
  }

  Widget _thumbnail(PartnerDocumentMeta meta) {
    const side = 46.0;
    if (meta.isPdf) {
      return Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.picture_as_pdf_rounded,
            color: AppColors.error, size: 22),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        meta.url,
        width: side,
        height: side,
        fit: BoxFit.cover,
        // A 46 dp thumbnail must not decode a full-resolution document scan
        // into the image cache — one card per docType would otherwise hold
        // several multi-megapixel bitmaps at once.
        cacheWidth:
            (side * MediaQuery.devicePixelRatioOf(context)).round(),
        cacheHeight:
            (side * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, __, ___) => Container(
          width: side,
          height: side,
          color: AppColors.divider,
          child: const Icon(Icons.image_not_supported_outlined,
              size: 20, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
