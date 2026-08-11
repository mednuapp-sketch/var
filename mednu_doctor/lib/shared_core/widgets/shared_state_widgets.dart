import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/ux_widgets.dart';

/// Scenario-specific loading/error/empty states, built on top of the
/// existing shimmer/empty/error primitives in `core/widgets/ux_widgets.dart`
/// rather than duplicating them. Use these instead of a bare
/// `CircularProgressIndicator()` or a raw `Text('Error')` wherever a shared
/// module needs one of these exact scenarios.

/// Full-page loading placeholder (e.g. while the initial role/profile
/// stream resolves).
class PageLoadingState extends StatelessWidget {
  final String? message;
  const PageLoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(message!, style: AppTextStyles.bodyMedium),
            ],
          ],
        ),
      );
}

/// Vertical list of skeleton rows — wraps [SkeletonListTile].
class ListLoadingState extends StatelessWidget {
  final int itemCount;
  final bool hasAvatar;
  const ListLoadingState({super.key, this.itemCount = 6, this.hasAvatar = true});

  @override
  // A plain Column, not a shrink-wrapped ListView: this skeleton is always
  // rendered inside a host scrollable, and a nested scrollable installs a
  // competing drag recognizer that stalls the outer scroll.
  Widget build(BuildContext context) => Column(
        children: List.generate(
          itemCount,
          (_) => SkeletonListTile(hasAvatar: hasAvatar),
        ),
      );
}

/// Vertical stack of skeleton cards — wraps [SkeletonCard].
class CardLoadingState extends StatelessWidget {
  final int itemCount;
  final double cardHeight;
  const CardLoadingState({super.key, this.itemCount = 3, this.cardHeight = 100});

  @override
  Widget build(BuildContext context) => Column(
        children: List.generate(
          itemCount,
          (_) => SkeletonCard(height: cardHeight),
        ),
      );
}

/// No internet connection — distinct copy/icon from a generic server error
/// so users know to check their own connection first.
class OfflineState extends StatelessWidget {
  final VoidCallback? onRetry;
  const OfflineState({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'You\'re offline',
        message: 'Check your internet connection. We\'ll keep trying to sync automatically.',
        actionLabel: onRetry != null ? 'Retry now' : null,
        onAction: onRetry,
        iconColor: AppColors.textSecondary,
      );
}

/// Generic network failure while a request was in flight.
class NetworkErrorState extends StatelessWidget {
  final VoidCallback? onRetry;
  const NetworkErrorState({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => AppErrorState(
        message: 'We couldn\'t reach the server. Please check your connection and try again.',
        onRetry: onRetry,
      );
}

/// 5xx / backend failure, distinct from a connectivity problem.
class ServerErrorState extends StatelessWidget {
  final VoidCallback? onRetry;
  const ServerErrorState({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => AppErrorState(
        message: 'Something went wrong on our end. Our team has been notified — please try again shortly.',
        onRetry: onRetry,
      );
}

/// A retryable failure with a caller-supplied reason (e.g. a specific
/// Firestore exception message surfaced for support/debug purposes).
class RetryState extends StatelessWidget {
  final String reason;
  final VoidCallback onRetry;
  const RetryState({super.key, required this.reason, required this.onRetry});

  @override
  Widget build(BuildContext context) => AppErrorState(
        message: reason,
        onRetry: onRetry,
      );
}

/// Firestore/Storage rules rejected the request — never auto-retryable, so
/// no retry action is offered.
class PermissionDeniedState extends StatelessWidget {
  final String? message;
  const PermissionDeniedState({super.key, this.message});

  @override
  Widget build(BuildContext context) => AppEmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Access restricted',
        message: message ??
            'You don\'t have permission to view this. If you think this is a mistake, contact support.',
        iconColor: AppColors.warning,
      );
}
