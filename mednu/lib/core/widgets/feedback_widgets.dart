import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

// ── Operation Status Banner ───────────────────────────────────────────────────
// Inline animated banner shown within a screen during/after an operation.

enum BannerStatus { loading, success, error, warning, syncing, idle }

class OperationBanner extends StatefulWidget {
  final BannerStatus status;
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const OperationBanner({
    super.key,
    required this.status,
    required this.message,
    this.onRetry,
    this.onDismiss,
  });

  @override
  State<OperationBanner> createState() => _OperationBannerState();
}

class _OperationBannerState extends State<OperationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _slide = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.status == BannerStatus.idle) return const SizedBox.shrink();

    return SlideTransition(
      position:
          Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
              .animate(_slide),
      child: FadeTransition(
        opacity: _slide,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _bgColor.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _bgColor.withValues(alpha:0.3)),
          ),
          child: Row(
            children: [
              _buildIcon(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.message,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: _fgColor,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onRetry,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _bgColor.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Retry',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _fgColor)),
                  ),
                ),
              ],
              if (widget.onDismiss != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: Icon(Icons.close_rounded, size: 16, color: _fgColor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    switch (widget.status) {
      case BannerStatus.loading:
      case BannerStatus.syncing:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: _fgColor),
        );
      case BannerStatus.success:
        return Icon(Icons.check_circle_rounded, size: 18, color: _fgColor);
      case BannerStatus.error:
        return Icon(Icons.error_rounded, size: 18, color: _fgColor);
      case BannerStatus.warning:
        return Icon(Icons.warning_rounded, size: 18, color: _fgColor);
      case BannerStatus.idle:
        return const SizedBox.shrink();
    }
  }

  Color get _bgColor {
    switch (widget.status) {
      case BannerStatus.loading:  return AppColors.info;
      case BannerStatus.syncing:  return AppColors.accent;
      case BannerStatus.success:  return AppColors.success;
      case BannerStatus.error:    return AppColors.error;
      case BannerStatus.warning:  return AppColors.warning;
      case BannerStatus.idle:     return Colors.transparent;
    }
  }

  Color get _fgColor {
    switch (widget.status) {
      case BannerStatus.loading:  return AppColors.info;
      case BannerStatus.syncing:  return AppColors.accent;
      case BannerStatus.success:  return AppColors.success;
      case BannerStatus.error:    return AppColors.error;
      case BannerStatus.warning:  return AppColors.warning;
      case BannerStatus.idle:     return AppColors.textPrimary;
    }
  }
}

// ── Action State Button ───────────────────────────────────────────────────────
// A button that shows loading/success/error states inline.

enum ActionButtonState { idle, loading, success, error }

class ActionStateButton extends StatelessWidget {
  final ActionButtonState state;
  final String idleLabel;
  final String loadingLabel;
  final String successLabel;
  final String errorLabel;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;
  final bool outlined;

  const ActionStateButton({
    super.key,
    required this.state,
    required this.idleLabel,
    this.loadingLabel = 'Saving...',
    this.successLabel = 'Saved!',
    this.errorLabel = 'Failed',
    this.onPressed,
    this.color = AppColors.primary,
    this.icon,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final isLoading = state == ActionButtonState.loading;
    final isSuccess = state == ActionButtonState.success;
    final isError   = state == ActionButtonState.error;

    final bgColor = isSuccess
        ? AppColors.success
        : isError
            ? AppColors.error
            : color;

    final label = isLoading
        ? loadingLabel
        : isSuccess
            ? successLabel
            : isError
                ? errorLabel
                : idleLabel;

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLoading)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white),
          )
        else if (isSuccess)
          const Icon(Icons.check_rounded, size: 16, color: Colors.white)
        else if (isError)
          const Icon(Icons.error_outline_rounded, size: 16, color: Colors.white)
        else if (icon != null)
          Icon(icon, size: 16, color: outlined ? bgColor : Colors.white)
        else
          const SizedBox.shrink(),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: outlined && !isLoading && !isSuccess && !isError
                ? bgColor
                : Colors.white,
          ),
        ),
      ],
    );

    final style = outlined
        ? OutlinedButton.styleFrom(
            foregroundColor: bgColor,
            side: BorderSide(color: bgColor.withValues(alpha:0.6)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          )
        : ElevatedButton.styleFrom(
            backgroundColor: bgColor,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      child: outlined
          ? OutlinedButton(
              onPressed: isLoading ? null : onPressed,
              style: style,
              child: child,
            )
          : ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: style,
              child: child,
            ),
    );
  }
}

// ── Loading Overlay ───────────────────────────────────────────────────────────

class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final String message;
  final Widget child;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message = 'Please wait...',
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha:0.45),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha:0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppColors.primary),
                      const SizedBox(height: 16),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Retry Card ────────────────────────────────────────────────────────────────

class RetryCard extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final IconData icon;

  const RetryCard({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    required this.onRetry,
    this.icon = Icons.wifi_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withValues(alpha:0.2)),
        boxShadow: [
          BoxShadow(
              color: AppColors.error.withValues(alpha:0.06),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha:0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: AppColors.error),
          ),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary, height: 1.5)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: const TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sync Status Row ───────────────────────────────────────────────────────────

class SyncStatusRow extends StatefulWidget {
  final bool isSyncing;
  final String? lastSyncedLabel;

  const SyncStatusRow({
    super.key,
    required this.isSyncing,
    this.lastSyncedLabel,
  });

  @override
  State<SyncStatusRow> createState() => _SyncStatusRowState();
}

class _SyncStatusRowState extends State<SyncStatusRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isSyncing) ...[
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.accent
                    .withValues(alpha:0.5 + _pulse.value * 0.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('Syncing...',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.accent, fontWeight: FontWeight.w600)),
        ] else ...[
          const Icon(Icons.cloud_done_rounded,
              size: 13, color: AppColors.success),
          const SizedBox(width: 5),
          Text(
            widget.lastSyncedLabel ?? 'Up to date',
            style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
          ),
        ],
      ],
    );
  }
}

// ── Operation Progress Card ───────────────────────────────────────────────────
// Multi-step progress card for complex operations (e.g., booking creation).

class OperationStep {
  final String label;
  final bool completed;
  final bool active;
  const OperationStep({
    required this.label,
    this.completed = false,
    this.active = false,
  });
}

class OperationProgressCard extends StatelessWidget {
  final String title;
  final List<OperationStep> steps;

  const OperationProgressCard({
    super.key,
    required this.title,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha:0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.labelLarge),
          const SizedBox(height: 12),
          ...steps.asMap().entries.map((e) {
            final step = e.value;
            final isLast = e.key == steps.length - 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    _stepDot(step),
                    if (!isLast)
                      Container(
                          width: 2,
                          height: 28,
                          color: step.completed
                              ? AppColors.success
                              : AppColors.border),
                  ],
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: EdgeInsets.only(top: 4, bottom: isLast ? 0 : 10),
                  child: Text(
                    step.label,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: step.completed
                          ? AppColors.success
                          : step.active
                              ? AppColors.primary
                              : AppColors.textHint,
                      fontWeight: step.active
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _stepDot(OperationStep step) {
    if (step.completed) {
      return Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
            color: AppColors.success, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
      );
    }
    if (step.active) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha:0.15), shape: BoxShape.circle),
        child: const Padding(
          padding: EdgeInsets.all(5),
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.primary),
        ),
      );
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border, width: 2),
      ),
    );
  }
}
