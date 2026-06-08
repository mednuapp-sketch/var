import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../models/notification_model.dart';
import '../providers/notification_provider.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifAsync = ref.watch(patientNotificationsProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Gradient SliverAppBar ──────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 130,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
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
                          PatientNotificationService.markAllRead(uid),
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
                    colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
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
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.notifications_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
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

          // ── Content ──────────────────────────────────────
          notifAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.error_outline_rounded,
                          size: 32, color: AppColors.error),
                    ),
                    const SizedBox(height: 16),
                    Text('Something went wrong', style: AppTextStyles.h4),
                    const SizedBox(height: 6),
                    Text('Pull down to refresh',
                        style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
            ),
            data: (notifications) {
              if (notifications.isEmpty) {
                return const SliverFillRemaining(child: _EmptyState());
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _NotifTile(
                      notif: notifications[i],
                      uid: uid,
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
  final String uid;

  const _NotifTile({required this.notif, required this.uid});

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
              : AppColors.primary.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notif.isRead
                ? AppColors.divider
                : AppColors.primary.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: notif.isRead
                  ? Colors.black.withOpacity(0.03)
                  : AppColors.primary.withOpacity(0.06),
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
              color: meta.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(meta.icon, color: meta.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(notif.title,
                            style: AppTextStyles.labelLarge)),
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
                    Text(_formatTime(notif.deliverAt),
                        style: AppTextStyles.caption),
                    const Spacer(),
                    if (!notif.isRead)
                      GestureDetector(
                        onTap: () =>
                            PatientNotificationService.markRead(uid, notif.id),
                        child: Text(
                          'Mark read',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ]),
                  if (_ctaLabel(notif.type) != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          PatientNotificationService.markRead(uid, notif.id);
                          final route = _routeFor(notif.type);
                          if (route != null && context.mounted) {
                            context.push(route);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          backgroundColor: meta.color,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                          minimumSize: const Size(double.infinity, 36),
                        ),
                        child: Text(_ctaLabel(notif.type)!,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ]),
          ),
        ]),
      ),
    );
  }

  void _onTap(BuildContext context) {
    if (!notif.isRead) {
      PatientNotificationService.markRead(uid, notif.id);
    }
    final route = _routeFor(notif.type);
    if (route != null) context.push(route);
  }

  String? _routeFor(PatientNotifType type) {
    switch (type) {
      case PatientNotifType.consultationDone:
      case PatientNotifType.followupDay1:
      case PatientNotifType.followupDay2:
        return AppRoutes.postConsultation;
      case PatientNotifType.appointmentReminder:
        return AppRoutes.appointment;
      case PatientNotifType.waterReminder:
        return AppRoutes.waterReminder;
      case PatientNotifType.periodTracker:
        return AppRoutes.periodTracker;
      case PatientNotifType.orderUpdate:
        return AppRoutes.orderTracking;
      case PatientNotifType.medicineReminder:
      case PatientNotifType.healthTip:
      case PatientNotifType.referralReward:
      case PatientNotifType.welcomeBonus:
      case PatientNotifType.unknown:
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

  _NotifMeta _meta(PatientNotifType type) {
    switch (type) {
      case PatientNotifType.consultationDone:
      case PatientNotifType.followupDay1:
      case PatientNotifType.followupDay2:
        return _NotifMeta(Icons.favorite_rounded, const Color(0xFFC2185B));
      case PatientNotifType.appointmentReminder:
        return _NotifMeta(Icons.check_circle_rounded, AppColors.success);
      case PatientNotifType.medicineReminder:
        return _NotifMeta(Icons.medication_rounded, const Color(0xFFE65100));
      case PatientNotifType.waterReminder:
        return _NotifMeta(Icons.water_drop_rounded, const Color(0xFF1565C0));
      case PatientNotifType.periodTracker:
        return _NotifMeta(Icons.favorite_rounded, const Color(0xFFC2185B));
      case PatientNotifType.orderUpdate:
        return _NotifMeta(Icons.local_shipping_rounded, AppColors.success);
      case PatientNotifType.healthTip:
        return _NotifMeta(Icons.star_rounded, Colors.amber);
      case PatientNotifType.referralReward:
      case PatientNotifType.welcomeBonus:
        return _NotifMeta(Icons.card_giftcard_rounded, const Color(0xFF6A1B9A));
      case PatientNotifType.unknown:
        return _NotifMeta(
            Icons.notifications_rounded, AppColors.textSecondary);
    }
  }

  String? _ctaLabel(PatientNotifType type) {
    switch (type) {
      case PatientNotifType.appointmentReminder:
        return 'View Appointment';
      case PatientNotifType.waterReminder:
        return 'Mark Done';
      case PatientNotifType.medicineReminder:
        return 'Mark Taken';
      case PatientNotifType.consultationDone:
      case PatientNotifType.followupDay1:
      case PatientNotifType.followupDay2:
        return 'View Summary';
      case PatientNotifType.orderUpdate:
        return 'Track Order';
      case PatientNotifType.periodTracker:
        return 'View Tracker';
      case PatientNotifType.healthTip:
      case PatientNotifType.referralReward:
      case PatientNotifType.welcomeBonus:
      case PatientNotifType.unknown:
        return null;
    }
  }
}

class _NotifMeta {
  final IconData icon;
  final Color color;
  const _NotifMeta(this.icon, this.color);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.08),
                    AppColors.secondary.withOpacity(0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text('No notifications yet', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(
              'You\'re all caught up!\nWe\'ll notify you when something needs your attention.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
