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
          SliverAppBar(
            pinned: true,
            expandedHeight: 130,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
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
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton(
                      onPressed: () =>
                          NotificationService.markAllRead(uid),
                      child: const Text(
                        'Mark all read',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
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
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF880E4F),
                      Color(0xFFC2185B),
                      Color(0xFF7B1FA2)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -20,
                      right: -20,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha:0.06),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 52, 20, 16),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha:0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                  Icons.notifications_rounded,
                                  color: Colors.white,
                                  size: 22),
                            ),
                            const SizedBox(width: 12),
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
                                  ),
                                ),
                                notifAsync.when(
                                  data: (list) {
                                    final unread =
                                        list.where((n) => !n.isRead).length;
                                    return Text(
                                      unread > 0
                                          ? '$unread unread'
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
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          notifAsync.when(
            loading: () => SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, __) => const SkeletonListTile(),
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
                return SliverFillRemaining(
                  child: FadeInSlide(
                    child: AppEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'No notifications yet',
                      message: 'You\'re all caught up!',
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => FadeInSlide(
                      delay: Duration(milliseconds: i * 40),
                      child: _NotifTile(
                        notif: notifications[i],
                        doctorUid: uid,
                      ),
                    ),
                    childCount: notifications.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notif.isRead
              ? Colors.white
              : AppColors.primary.withValues(alpha:0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notif.isRead
                ? AppColors.divider
                : AppColors.primary.withValues(alpha:0.2),
          ),
          boxShadow: notif.isRead
              ? []
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha:0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha:0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(meta.icon, color: meta.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(notif.title, style: AppTextStyles.labelLarge),
                ),
                if (!notif.isRead)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ]),
              const SizedBox(height: 3),
              Text(notif.body, style: AppTextStyles.bodySmall),
              const SizedBox(height: 6),
              Row(children: [
                Text(_formatTime(notif.createdAt), style: AppTextStyles.caption),
                const Spacer(),
                if (!notif.isRead)
                  GestureDetector(
                    onTap: () => NotificationService.markRead(doctorUid, notif.id),
                    child: Text(
                      'Mark read',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
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
      context.push(route, extra: notif.payload.isNotEmpty ? notif.payload : null);
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
      case NotifType.unknown:
        return null;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat('d MMM').format(dt);
  }

  _NotifMeta _meta(NotifType type) {
    switch (type) {
      case NotifType.consultationRequest:
      case NotifType.emergencyRequest:
        return _NotifMeta(Icons.video_call_rounded, AppColors.primary);
      case NotifType.review:
        return _NotifMeta(Icons.star_rounded, Colors.amber);
      case NotifType.payment:
        return _NotifMeta(Icons.account_balance_wallet_rounded, AppColors.success);
      case NotifType.appointment:
        return _NotifMeta(Icons.calendar_month_rounded, AppColors.secondary);
      case NotifType.summary:
        return _NotifMeta(Icons.verified_rounded, AppColors.info);
      case NotifType.patientFollowup:
        return _NotifMeta(Icons.favorite_rounded, const Color(0xFFE91E63));
      case NotifType.unknown:
        return _NotifMeta(Icons.notifications_rounded, AppColors.textSecondary);
    }
  }
}

class _NotifMeta {
  final IconData icon;
  final Color color;
  const _NotifMeta(this.icon, this.color);
}

