import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../services/prescription_upload_service.dart';

/// Shown after picking a file, before it's actually uploaded — the patient
/// gets one more look (with pinch-to-zoom for images, a real PDF render
/// for PDFs) and an explicit "Upload" confirmation, plus a "Retake"/"Choose
/// Different File" way back out. Performs the upload itself and reports
/// progress inline; pops `true` on success so the caller's realtime
/// `orderDetailProvider` listener picks up the result — no local order
/// state duplicated here.
class PrescriptionPreviewScreen extends StatefulWidget {
  final String orderId;
  final File file;

  const PrescriptionPreviewScreen({super.key, required this.orderId, required this.file});

  @override
  State<PrescriptionPreviewScreen> createState() => _PrescriptionPreviewScreenState();
}

class _PrescriptionPreviewScreenState extends State<PrescriptionPreviewScreen> {
  bool _uploading = false;
  double _progress = 0;

  bool get _isPdf => PrescriptionUploadService.fileTypeFor(widget.file) == 'pdf';

  Future<void> _confirmUpload() async {
    setState(() {
      _uploading = true;
      _progress = 0;
    });
    try {
      await PrescriptionUploadService.upload(
        orderId: widget.orderId,
        file: widget.file,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      FeedbackService.showSuccess(context, 'Prescription uploaded');
      Navigator.of(context).pop(true);
    } on PrescriptionTooLargeException {
      if (mounted) {
        FeedbackService.showError(context, 'That file is over the 20 MB limit. Please choose a smaller one.');
      }
    } catch (e) {
      if (mounted) FeedbackService.showError(context, 'Upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Review Prescription'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isPdf
                ? PDFView(filePath: widget.file.path)
                : InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Center(
                      child: Image.file(widget.file, fit: BoxFit.contain),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              color: const Color(0xFF121212),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_uploading) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        minHeight: 6,
                        backgroundColor: Colors.white24,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Uploading… ${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: AppTextStyles.bodySmall.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _uploading ? null : () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                          child: const Text('Choose Different File'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: 'Upload',
                          isLoading: _uploading,
                          onPressed: _uploading ? null : _confirmUpload,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
