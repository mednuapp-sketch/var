import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../models/notification_model.dart';
import '../providers/notification_provider.dart';
import '../services/notification_service.dart';
import '../../../core/widgets/ux_widgets.dart';

class DoctorNotificationsScreen extends ConsumerWidget {
  const DoctorNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifAsync = ref.watch(notificationsProvider);
    final uid = DoctorAuthService.currentUid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Gradient App Bar ─────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 130,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              notifAsync.when(
                data: (list) {
                  final hasUnread = list.any((n) => !n.isRead);
                  if (!hasUnread) return const SizedBox.shrink();
                  return TextButton.icon(
                    onPressed: () => NotificationService.markAllRead(uid),
                    icon: const Icon(Icons.done_all_rounded,
                        color: Colors.white, size: 16),
                    label: const Text(
                      'All read',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _NotifHeader(notifAsync: notifAsync),
            ),
          ),

          // ── Content ──────────────────────────────────────
          notifAsync.when(
            loading: () => SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SkeletonCard(height: 72),
                  ),
                  childCount: 7,
                ),
              ),
            ),
            error: (e, _) => SliverFillRemaining(
              child: AppErrorState(
                onRetry: () => ref.invalidate(notificationsProvider),
              ),
            ),
            data: (notifications) {
              if (notifications.isEmpty) {
                return const SliverFillRemaining(
                  child: FadeInSlide(
                    child: AppEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'All caught up!',
                      message:
                          "You're up to date. New alerts will appear here.",
                    ),
                  ),
                );
              }

              // Group by date label
              final grouped = _groupByDate(notifications);

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final item = grouped[i];
                      if (item is String) {
                        return FadeInSlide(
                          delay: Duration(milliseconds: i * 30),
                          child: DateSectionLabel(label: item),
                        );
                      }
                      final notif = item as NotificationModel;
                      return FadeInSlide(
                        delay: Duration(milliseconds: i * 30),
                        child: _NotifTile(
                          notif: notif,
                          doctorUid: uid,
                        ),
                      );
                    },
                    childCount: grouped.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<Object> _groupByDate(List<NotificationModel> notifications) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeek = today.subtract(const Duration(days: 7));

    final result = <Object>[];
    String? lastLabel;

    for (final n in notifications) {
      final d = DateTime(
          n.createdAt.year, n.createdAt.month, n.createdAt.day);
      final String label;
      if (d == today) {
        label = 'Today';
      } else if (d == yesterday) {
        label = 'Yesterday';
      } else if (d.isAfter(thisWeek)) {
        label = 'This Week';
      } else {
        label = 'Earlier';
      }
      if (label != lastLabel) {
        result.add(label);
        lastLabel = label;
      }
      result.add(n);
    }
    return result;
  }
}

// ──────────────────────────────────────────────────────────────
// Gradient Header Widget
// ──────────────────────────────────────────────────────────────

class _NotifHeader extends StatelessWidget {
  final AsyncValue<List<NotificationModel>> notifAsync;

  const _NotifHeader({required this.notifAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -28,
            right: -28,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.notifications_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Notifications',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      notifAsync.when(
                        data: (list) {
                          final unread =
                              list.where((n) => !n.isRead).length;
                          return Text(
                            unread > 0
                                ? '$unread unread message${unread > 1 ? 's' : ''}'
                                : 'All caught up',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const Spacer(),
                  notifAsync.when(
                    data: (list) {
                      final unread = list.where((n) => !n.isRead).length;
                      if (unread == 0) return const SizedBox.shrink();
                      return Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
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

// ──────────────────────────────────────────────────────────────
// Notification Tile
// ──────────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  final NotificationModel notif;
  final String doctorUid;

  const _NotifTile({required this.notif, required this.doctorUid});

  @override
  Widget build(BuildContext context) {
    final meta = _meta(notif.type);

    return GestureDetector(
      onTap: () => _onTap(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notif.isRead
              ? Colors.white
              : AppColors.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notif.isRead
                ? AppColors.divider
                : AppColors.primary.withValues(alpha: 0.18),
            width: notif.isRead ? 1 : 1.2,
          ),
          boxShadow: notif.isRead
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  )
                ],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Icon badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(meta.icon, color: meta.color, size: 22),
              ),
              if (!notif.isRead)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                notif.title,
                style: notif.isRead
                    ? AppTextStyles.labelMedium
                    : AppTextStyles.labelLarge,
              ),
              const SizedBox(height: 3),
              Text(
                notif.body,
                style: AppTextStyles.bodySmall.copyWith(height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.access_time_rounded,
                    size: 11, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text(
                  _formatTime(notif.createdAt),
                  style: AppTextStyles.caption,
                ),
                const Spacer(),
                if (!notif.isRead)
                  GestureDetector(
                    onTap: () =>
                        NotificationService.markRead(doctorUid, notif.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Mark read',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  void _onTap(BuildContext context) {
    if (!notif.isRead) {
      NotificationService.markRead(doctorUid, notif.id);
    }
    final route = _routeFor(notif);
    if (route != null) {
      context.push(route,
          extra:
              notif.payload.isNotEmpty ? notif.payload : null);
    }
  }

  String? _routeFor(NotificationModel n) {
    switch (n.type) {
      case NotifType.consultationRequest:
        return AppRoutes.incomingRequest;
      case NotifType.payment:
        return AppRoutes.earnings;
      case NotifType.appointment:
        return AppRoutes.schedule;
      case NotifType.emergencyRequest:
        return AppRoutes.incomingRequest;
      case NotifType.review:
      case NotifType.summary:
      case NotifType.patientFollowup:
      case NotifType.accountApproved:
      case NotifType.accountRejected:
      case NotifType.unknown:
        return null;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM').format(dt);
  }

  _NotifMeta _meta(NotifType type) {
    switch (type) {
      case NotifType.consultationRequest:
      case NotifType.emergencyRequest:
        return _NotifMeta(Icons.video_call_rounded, AppColors.primary);
      case NotifType.review:
        return _NotifMeta(Icons.star_rounded, Colors.amber.shade600);
      case NotifType.payment:
        return _NotifMeta(
            Icons.account_balance_wallet_rounded, AppColors.success);
      case NotifType.appointment:
        return _NotifMeta(
            Icons.calendar_month_rounded, AppColors.secondary);
      case NotifType.summary:
        return _NotifMeta(Icons.verified_rounded, AppColors.info);
      case NotifType.patientFollowup:
        return _NotifMeta(
            Icons.favorite_rounded, const Color(0xFFE91E63));
      case NotifType.accountApproved:
        return _NotifMeta(Icons.verified_rounded, AppColors.success);
      case NotifType.accountRejected:
        return _NotifMeta(Icons.cancel_rounded, AppColors.error);
      case NotifType.unknown:
        return _NotifMeta(
            Icons.notifications_rounded, AppColors.textSecondary);
    }
  }
}

class _NotifMeta {
  final IconData icon;
  final Color color;
  const _NotifMeta(this.icon, this.color);
}
