// ============================================================
//  MedNu Component Library
//  Buttons · TextFields · AppBar/Scaffold · Dialogs · BottomSheet
//  Timeline · Status Chip
//
//  Builds on top of the primitives in ux_widgets.dart (PremiumCard,
//  GradientButton, StatusBadge, AppEmptyState, AppErrorState, ...).
//  Prefer these MedNuXxx names in new/redesigned screens; the
//  ux_widgets.dart primitives remain for existing call sites.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_text_styles.dart';
import 'ux_widgets.dart';

// ── Aliases — same widget, MedNu-prefixed name per design system §83 ──
typedef MedNuCard = PremiumCard;
typedef MedNuGradientButton = GradientButton;
typedef MedNuStatusChip = StatusBadge;
typedef MedNuSectionHeader = SectionHeader;
typedef MedNuEmptyState = AppEmptyState;
typedef MedNuErrorState = AppErrorState;

// ──────────────────────────────────────────────────────────────
// BUTTONS
// ──────────────────────────────────────────────────────────────

/// Solid primary button. Use for the one dominant action on a screen.
class MedNuButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final double height;
  final double? width;

  const MedNuButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.height = 52,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    return SizedBox(
      height: height,
      width: width ?? double.infinity,
      child: ElevatedButton(
        onPressed: disabled ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

/// Secondary/tertiary action button — outline style.
class MedNuOutlinedButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final double? width;

  const MedNuOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
    this.width,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: width ?? double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
              Text(label),
            ],
          ),
        ),
      );
}

// ──────────────────────────────────────────────────────────────
// TEXT FIELDS
// ──────────────────────────────────────────────────────────────

/// Standard MedNu form field: floating label, inline error, correct
/// keyboard type, focus/disabled states driven by the shared InputDecorationTheme.
class MedNuTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? errorText;
  final TextInputType keyboardType;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int maxLines;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  const MedNuTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.errorText,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.enabled = true,
    this.onChanged,
    this.textInputAction,
    this.inputFormatters,
    this.focusNode,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLines: obscureText ? 1 : maxLines,
          enabled: enabled,
          onChanged: onChanged,
          textInputAction: textInputAction,
          inputFormatters: inputFormatters,
          onSubmitted: (_) => onSubmitted?.call(),
          style: AppTextStyles.body,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}

/// Debounced search field with clear button.
class MedNuSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final Duration debounce;

  const MedNuSearchField({
    super.key,
    this.hint = 'Search',
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 350),
  });

  @override
  State<MedNuSearchField> createState() => _MedNuSearchFieldState();
}

class _MedNuSearchFieldState extends State<MedNuSearchField> {
  final _controller = TextEditingController();
  Object? _debounceToken;

  void _handleChange(String value) {
    final token = Object();
    _debounceToken = token;
    Future.delayed(widget.debounce, () {
      if (_debounceToken == token && mounted) widget.onChanged(value);
    });
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      onChanged: _handleChange,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// APP BAR / SCAFFOLD
// ──────────────────────────────────────────────────────────────

/// Clean white app bar used on non-hero screens.
class MedNuAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;
  final Widget? leading;

  const MedNuAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBack = true,
    this.leading,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
        title: Text(title),
        leading: leading ?? (showBack && Navigator.of(context).canPop()
            ? const BackButton()
            : null),
        actions: actions,
      );
}

/// Scaffold wrapper standardizing background + safe padding for MedNu screens.
class MedNuScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool safeArea;

  const MedNuScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.safeArea = false,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        body: safeArea ? SafeArea(child: body) : body,
      );
}

// ──────────────────────────────────────────────────────────────
// STAT CARD (non-gradient — for grids where a gradient card would
// be one-too-many gradients on screen; see design system §4/§14)
// ──────────────────────────────────────────────────────────────

class MedNuStatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color? accentColor;

  const MedNuStatCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = accentColor ?? AppColors.primary;
    return PremiumCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: c, size: 18),
          ),
          const SizedBox(height: AppSpacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: AppTextStyles.statistic),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.statisticLabel),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// LOADING
// ──────────────────────────────────────────────────────────────

class MedNuLoading extends StatelessWidget {
  final String? message;
  const MedNuLoading({super.key, this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(message!, style: AppTextStyles.bodySmall),
            ],
          ],
        ),
      );
}

class MedNuProgressIndicator extends StatelessWidget {
  final double value;
  final Color? color;

  const MedNuProgressIndicator({super.key, required this.value, this.color});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1),
          minHeight: 6,
          backgroundColor: AppColors.divider,
          valueColor: AlwaysStoppedAnimation(color ?? AppColors.primary),
        ),
      );
}

// ──────────────────────────────────────────────────────────────
// DIALOG / CONFIRMATION / BOTTOM SHEET
// ──────────────────────────────────────────────────────────────

/// Confirmation dialog — reserve for destructive/irreversible/financially
/// significant actions (design system §56). Do not use for routine actions.
class MedNuConfirmationDialog {
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: destructive ? AppColors.error : AppColors.primary,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class MedNuBottomSheet {
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    String? title,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                if (title != null) ...[
                  Text(title, style: AppTextStyles.h4),
                  const SizedBox(height: AppSpacing.lg),
                ],
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// TIMELINE — sequential workflow steps (e.g. caregiver visit flow,
// lab sample collection, order status)
// ──────────────────────────────────────────────────────────────

class MedNuTimelineStep {
  final String label;
  final String? subtitle;
  final bool isDone;
  final bool isActive;

  const MedNuTimelineStep({
    required this.label,
    this.subtitle,
    this.isDone = false,
    this.isActive = false,
  });
}

class MedNuTimeline extends StatelessWidget {
  final List<MedNuTimelineStep> steps;
  const MedNuTimeline({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(step: steps[i], isLast: i == steps.length - 1),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final MedNuTimelineStep step;
  final bool isLast;
  const _TimelineRow({required this.step, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color = step.isDone
        ? AppColors.success
        : step.isActive
            ? AppColors.primary
            : AppColors.textHint;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: step.isDone || step.isActive ? color : Colors.white,
                  border: Border.all(color: color, width: 2),
                ),
                child: step.isDone
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: step.isDone ? AppColors.success : AppColors.divider,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.label,
                      style: (step.isActive ? AppTextStyles.labelLarge : AppTextStyles.body)
                          .copyWith(color: step.isActive ? AppColors.primary : null)),
                  if (step.subtitle != null)
                    Text(step.subtitle!, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
