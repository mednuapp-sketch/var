import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../services/prescription_upload_service.dart';

/// Bottom sheet offering the three ways to attach a prescription: camera,
/// gallery, or a PDF file. Resolves with the picked [File], or `null` if
/// the sheet was dismissed without picking anything.
Future<File?> showPrescriptionSourceSheet(BuildContext context) {
  return showModalBottomSheet<File?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PrescriptionSourceSheet(),
  );
}

class _PrescriptionSourceSheet extends StatefulWidget {
  const _PrescriptionSourceSheet();

  @override
  State<_PrescriptionSourceSheet> createState() => _PrescriptionSourceSheetState();
}

class _PrescriptionSourceSheetState extends State<_PrescriptionSourceSheet> {
  bool _busy = false;

  Future<void> _pick(Future<File?> Function() picker) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await picker();
      if (mounted) Navigator.of(context).pop(file);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCardElevated : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text('Upload Prescription', style: AppTextStyles.h4.copyWith(
              color: isDark ? Colors.white : AppColors.textPrimary,
            )),
            const SizedBox(height: 4),
            const Text(
              'A clear photo or PDF of your prescription',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 18),
            AbsorbPointer(
              absorbing: _busy,
              child: AnimatedOpacity(
                opacity: _busy ? 0.5 : 1,
                duration: const Duration(milliseconds: 150),
                child: Column(
                  children: [
                    _SourceTile(
                      icon: Icons.camera_alt_rounded,
                      label: 'Take a Photo',
                      color: AppColors.primary,
                      onTap: () => _pick(PrescriptionUploadService.pickFromCamera),
                    ),
                    const SizedBox(height: 10),
                    _SourceTile(
                      icon: Icons.photo_library_rounded,
                      label: 'Choose from Gallery',
                      color: AppColors.secondary,
                      onTap: () => _pick(PrescriptionUploadService.pickFromGallery),
                    ),
                    const SizedBox(height: 10),
                    _SourceTile(
                      icon: Icons.picture_as_pdf_rounded,
                      label: 'Choose a PDF',
                      color: AppColors.accent,
                      onTap: () => _pick(PrescriptionUploadService.pickPdf),
                    ),
                  ],
                ),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 14),
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.labelLarge.copyWith(
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}
