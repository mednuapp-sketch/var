import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum FeedbackType { success, error, warning, info, loading, syncing }

class FeedbackService {
  FeedbackService._();

  // ── Snackbar helpers ────────────────────────────────────────────────────────

  static void show(
    BuildContext context,
    String message, {
    FeedbackType type = FeedbackType.info,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
    bool dismissible = true,
  }) {
    if (!context.mounted) return;
    // hideCurrentSnackBar (animated exit) instead of clearSnackBars (instant
    // removal) so back-to-back show() calls don't hard-cut into each other.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              _icon(type),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: _bgColor(type),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: duration,
          dismissDirection:
              dismissible ? DismissDirection.horizontal : DismissDirection.none,
          action: actionLabel != null && onAction != null
              ? SnackBarAction(
                  label: actionLabel,
                  textColor: Colors.white,
                  onPressed: onAction,
                )
              : null,
        ),
      );
  }

  static void showSuccess(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) =>
      show(context, message, type: FeedbackType.success, duration: duration);

  static void showError(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
    Duration duration = const Duration(seconds: 5),
  }) =>
      show(
        context,
        message,
        type: FeedbackType.error,
        duration: duration,
        actionLabel: onRetry != null ? 'Retry' : null,
        onAction: onRetry,
        dismissible: false,
      );

  static void showWarning(BuildContext context, String message) =>
      show(context, message, type: FeedbackType.warning, duration: const Duration(seconds: 4));

  static void showInfo(BuildContext context, String message) =>
      show(context, message, type: FeedbackType.info);

  static void showLoading(BuildContext context, String message) =>
      show(
        context,
        message,
        type: FeedbackType.loading,
        duration: const Duration(seconds: 30),
        dismissible: false,
      );

  static void showSyncing(BuildContext context, String message) =>
      show(
        context,
        message,
        type: FeedbackType.syncing,
        duration: const Duration(seconds: 10),
        dismissible: false,
      );

  static void dismiss(BuildContext context) {
    if (!context.mounted) return;
    // Animated exit — see the note in show() above.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  // ── Confirmation dialog ─────────────────────────────────────────────────────

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    Color confirmColor = AppColors.primary,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            height: 1.55,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelLabel,
                style: const TextStyle(
                    fontFamily: 'Poppins', color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: destructive ? AppColors.error : confirmColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(confirmLabel,
                style: const TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  static Color _bgColor(FeedbackType type) {
    switch (type) {
      case FeedbackType.success:  return const Color(0xFF1B5E20);
      case FeedbackType.error:    return const Color(0xFFC62828);
      case FeedbackType.warning:  return const Color(0xFFE65100);
      case FeedbackType.info:     return const Color(0xFF1565C0);
      case FeedbackType.loading:  return const Color(0xFF1A1A2E);
      case FeedbackType.syncing:  return const Color(0xFF00695C);
    }
  }

  static Widget _icon(FeedbackType type) {
    switch (type) {
      case FeedbackType.success:
        return const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20);
      case FeedbackType.error:
        return const Icon(Icons.error_rounded, color: Colors.white, size: 20);
      case FeedbackType.warning:
        return const Icon(Icons.warning_rounded, color: Colors.white, size: 20);
      case FeedbackType.info:
        return const Icon(Icons.info_rounded, color: Colors.white, size: 20);
      case FeedbackType.loading:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        );
      case FeedbackType.syncing:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        );
    }
  }
}
