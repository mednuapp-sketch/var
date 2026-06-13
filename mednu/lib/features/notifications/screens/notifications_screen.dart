import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/notification_model.dart';
import '../providers/notification_provider.dart';
import '../services/notification_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Notifications Screen
// Groups notifications into Today / Yesterday / This Week / Older.
// Swipe right to delete, tap to navigate, pull-to-refresh, mark all read.
// ─────────────────────────────────────────────────────────────────────────────

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _markAllRead() async {
    await PatientNotificationService.markAllRead(_uid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All notifications marked as read'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearAllRead(List<NotificationModel> list) async {
    final readCount = list.where((n) => n.isRead).length;
    if (readCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear Read Notifications',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: Text('Remove $readCount read notification${readCount == 1 ? '' : 's'}?',
            style: const TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await PatientNotificationService.deleteAllRead(_uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifAsync = ref.watch(patientNotificationsProvider);
    final unreadAsync = ref.watch(patientUnreadCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: 140,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => context.pop(),
            ),
            actions: [
              notifAsync.when(
                data: (list) => _AppBarActions(
                  list: list,
                  uid: _uid,
                  onMarkAll: _markAllRead,
                  onClearRead: () => _clearAllRead(list),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _HeaderBackground(unreadCount: unreadAsync),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(46),
              child: Container(
                color: AppColors.primary,
                child: TabBar(
                  controller: _tab,
                  labelStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('All'),
                          if (unreadAsync > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha:0.25),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$unreadAsync',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Tab(text: 'Unread'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tab,
          children: [
            _NotifListView(uid: _uid, filterUnread: false),
            _NotifListView(uid: _uid, filterUnread: true),
          ],
        ),
      ),
    );
  }
}

// ── App bar overflow actions ──────────────────────────────────────────────────

class _AppBarActions extends StatelessWidget {
  final List<NotificationModel> list;
  final String uid;
  final VoidCallback onMarkAll;
  final VoidCallback onClearRead;

  const _AppBarActions({
    required this.list,
    required this.uid,
    required this.onMarkAll,
    required this.onClearRead,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = list.any((n) => !n.isRead);
    final hasRead   = list.any((n) => n.isRead);
    if (!hasUnread && !hasRead) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (v) {
        if (v == 'mark_all') onMarkAll();
        if (v == 'clear_read') onClearRead();
      },
      itemBuilder: (_) => [
        if (hasUnread)
          const PopupMenuItem(
            value: 'mark_all',
            child: Row(children: [
              Icon(Icons.done_all_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Mark all as read',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
            ]),
          ),
        if (hasRead)
          const PopupMenuItem(
            value: 'clear_read',
            child: Row(children: [
              Icon(Icons.delete_sweep_rounded, size: 18, color: AppColors.error),
              SizedBox(width: 10),
              Text('Clear read notifications',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
            ]),
          ),
      ],
    );
  }
}

// ── Gradient header background ────────────────────────────────────────────────

class _HeaderBackground extends StatelessWidget {
  final int unreadCount;
  const _HeaderBackground({required this.unreadCount});

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
            top: -24,
            right: -24,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha:0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: -30,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha:0.04),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 52, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha:0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.notifications_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
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
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        unreadCount > 0
                            ? '$unreadCount unread'
                            : 'All caught up',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: Colors.white70,
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

// ── Grouped list view ─────────────────────────────────────────────────────────

class _NotifListView extends ConsumerWidget {
  final String uid;
  final bool filterUnread;

  const _NotifListView({required this.uid, required this.filterUnread});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifAsync = ref.watch(patientNotificationsProvider);

    return notifAsync.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
        itemCount: 7,
        itemBuilder: (_, __) => const SkeletonNotificationTile(),
      ),
      error: (e, _) => AppErrorState(
        message: 'Unable to load notifications.\nPull down to refresh.',
        onRetry: () => ref.invalidate(patientNotificationsProvider),
      ),
      data: (all) {
        final notifications =
            filterUnread ? all.where((n) => !n.isRead).toList() : all;

        if (notifications.isEmpty) {
          return filterUnread
              ? const _AllReadState()
              : const _EmptyState();
        }

        final groups = _groupByDate(notifications);

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(patientNotificationsProvider),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              for (final group in groups) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  sliver: SliverToBoxAdapter(
                    child: _DateHeader(label: group.label),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final notif = group.items[i];
                        return Dismissible(
                          key: ValueKey(notif.id),
                          direction: DismissDirection.endToStart,
                          background: _SwipeDeleteBg(),
                          onDismissed: (_) =>
                              PatientNotificationService.deleteNotification(
                                  uid, notif.id),
                          child: FadeInSlide(
                            delay: Duration(milliseconds: i * 30),
                            child: _NotifTile(notif: notif, uid: uid),
                          ),
                        );
                      },
                      childCount: group.items.length,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(
                child: SizedBox(height: 32),
              ),
            ],
          ),
        );
      },
    );
  }

  List<_DateGroup> _groupByDate(List<NotificationModel> notifications) {
    final now = DateTime.now();
    final today     = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo   = today.subtract(const Duration(days: 7));

    final groups = <String, List<NotificationModel>>{};

    for (final n in notifications) {
      final d = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      final String label;
      if (!d.isBefore(today)) {
        label = 'Today';
      } else if (!d.isBefore(yesterday)) {
        label = 'Yesterday';
      } else if (!d.isBefore(weekAgo)) {
        label = 'This Week';
      } else {
        label = 'Older';
      }
      (groups[label] ??= []).add(n);
    }

    const order = ['Today', 'Yesterday', 'This Week', 'Older'];
    return order
        .where((l) => groups.containsKey(l))
        .map((l) => _DateGroup(label: l, items: groups[l]!))
        .toList();
  }
}

class _DateGroup {
  final String label;
  final List<NotificationModel> items;
  const _DateGroup({required this.label, required this.items});
}

// ── Date section header ───────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Divider(
            color: AppColors.divider,
            thickness: 1,
            height: 1,
          ),
        ),
      ],
    );
  }
}

// ── Swipe-to-delete background ────────────────────────────────────────────────

class _SwipeDeleteBg extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha:0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_rounded, color: AppColors.error, size: 24),
          const SizedBox(height: 4),
          Text(
            'Delete',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Notification tile ─────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  final NotificationModel notif;
  final String uid;

  const _NotifTile({required this.notif, required this.uid});

  @override
  Widget build(BuildContext context) {
    final meta = _NotifMeta.of(notif.type);

    return GestureDetector(
      onTap: () => _onTap(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: notif.isRead ? Colors.white : meta.color.withValues(alpha:0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notif.isRead
                ? AppColors.divider
                : meta.color.withValues(alpha:0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: notif.isRead
                  ? Colors.black.withValues(alpha:0.03)
                  : meta.color.withValues(alpha:0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _onTap(context),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Icon ────────────────────────────────────────────────
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: meta.color.withValues(alpha:0.13),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(meta.icon, color: meta.color, size: 22),
                  ),
                  const SizedBox(width: 12),

                  // ── Content ──────────────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                notif.title,
                                style: AppTextStyles.labelLarge.copyWith(
                                  fontWeight: notif.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (!notif.isRead)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: meta.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notif.body,
                          style: AppTextStyles.bodySmall,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Service type chip
                            if (notif.serviceType.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: meta.color.withValues(alpha:0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _serviceLabel(notif.serviceType),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: meta.color,
                                  ),
                                ),
                              ),
                            const Spacer(),
                            Text(
                              _formatTime(notif.createdAt),
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                        // CTA button for actionable notifications
                        if (_ctaLabel(notif) != null) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                PatientNotificationService.markRead(
                                    uid, notif.id);
                                _navigate(context);
                              },
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                backgroundColor: meta.color,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                                minimumSize:
                                    const Size(double.infinity, 38),
                              ),
                              child: Text(
                                _ctaLabel(notif)!,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context) {
    if (!notif.isRead) PatientNotificationService.markRead(uid, notif.id);
    _navigate(context);
  }

  void _navigate(BuildContext context) {
    final route = _routeFor(notif);
    if (route != null && context.mounted) context.push(route);
  }

  String? _routeFor(NotificationModel n) {
    switch (n.actionType) {
      case 'open_call':
        return AppRoutes.consultation;
      case 'open_prescription':
        return AppRoutes.prescriptionViewer;
      case 'open_order':
        return AppRoutes.orderTracking;
      case 'open_diagnostics':
        return AppRoutes.diagnostics;
      case 'open_ambulance':
        return AppRoutes.ambulance;
      case 'open_pregnancy':
        return AppRoutes.pregnancyCheckups;
      case 'open_appointment':
        return AppRoutes.appointment;
      case 'open_service':
        return _serviceRoute(n.serviceType);
      default:
        break;
    }

    // Fallback: route by type
    switch (n.type) {
      case PatientNotifType.consultationDone:
      case PatientNotifType.followupDay1:
      case PatientNotifType.followupDay2:
        return AppRoutes.postConsultation;
      case PatientNotifType.appointmentBooked:
      case PatientNotifType.appointmentAccepted:
      case PatientNotifType.appointmentRejected:
      case PatientNotifType.appointmentRescheduled:
      case PatientNotifType.appointmentCompleted:
      case PatientNotifType.appointmentCancelled:
      case PatientNotifType.appointmentReminder:
        return AppRoutes.appointment;
      case PatientNotifType.doctorStartedCall:
      case PatientNotifType.consultationUpdate:
      case PatientNotifType.quickConnectAccepted:
      case PatientNotifType.quickConnectStarted:
        return AppRoutes.consultation;
      case PatientNotifType.prescriptionUploaded:
        return AppRoutes.prescriptionViewer;
      case PatientNotifType.medicineAccepted:
      case PatientNotifType.medicineProcessing:
      case PatientNotifType.medicineVerified:
      case PatientNotifType.medicinePacked:
      case PatientNotifType.medicineOutForDelivery:
      case PatientNotifType.medicineDelivered:
      case PatientNotifType.medicineCancelled:
      case PatientNotifType.medicineReturned:
      case PatientNotifType.medicineRejected:
      case PatientNotifType.orderUpdate:
        return AppRoutes.orderTracking;
      case PatientNotifType.labAccepted:
      case PatientNotifType.labAssigned:
      case PatientNotifType.labInProgress:
      case PatientNotifType.labSampleCollected:
      case PatientNotifType.labProcessing:
      case PatientNotifType.labReportReady:
      case PatientNotifType.labCompleted:
      case PatientNotifType.labCancelled:
      case PatientNotifType.labRejected:
        return AppRoutes.diagnostics;
      case PatientNotifType.ambulanceAccepted:
      case PatientNotifType.ambulanceAssigned:
      case PatientNotifType.ambulanceEnRoute:
      case PatientNotifType.ambulanceReached:
      case PatientNotifType.ambulanceCompleted:
      case PatientNotifType.ambulanceCancelled:
      case PatientNotifType.ambulanceRejected:
        return AppRoutes.ambulance;
      case PatientNotifType.homecareAccepted:
      case PatientNotifType.caregiverAssigned:
      case PatientNotifType.caregiverStarted:
      case PatientNotifType.homecareCompleted:
      case PatientNotifType.homecareCancelled:
      case PatientNotifType.homecareRejected:
        return AppRoutes.caregivers;
      case PatientNotifType.physioAccepted:
      case PatientNotifType.physioAssigned:
      case PatientNotifType.physioStarted:
      case PatientNotifType.physioCompleted:
      case PatientNotifType.physioCancelled:
      case PatientNotifType.physioRejected:
        return AppRoutes.physio;
      case PatientNotifType.hospitalAccepted:
      case PatientNotifType.hospitalAssigned:
      case PatientNotifType.hospitalAdmitted:
      case PatientNotifType.hospitalDischarged:
      case PatientNotifType.hospitalCancelled:
      case PatientNotifType.hospitalRejected:
        return AppRoutes.hospitals;
      case PatientNotifType.pregnancyCheckupBooked:
      case PatientNotifType.pregnancyCheckupReminder:
      case PatientNotifType.pregnancyCheckupConfirmed:
      case PatientNotifType.pregnancyCheckupCompleted:
      case PatientNotifType.pregnancyCheckupCancelled:
        return AppRoutes.pregnancyCheckups;
      case PatientNotifType.nutritionAccepted:
      case PatientNotifType.nutritionStarted:
      case PatientNotifType.nutritionCompleted:
      case PatientNotifType.nutritionCancelled:
      case PatientNotifType.nutritionRejected:
        return AppRoutes.nutrition;
      case PatientNotifType.waterReminder:
        return AppRoutes.waterReminder;
      case PatientNotifType.periodTracker:
        return AppRoutes.periodTracker;
      case PatientNotifType.medicineReminder:
        return AppRoutes.medicine;
      case PatientNotifType.bookingAccepted:
      case PatientNotifType.bookingAssigned:
      case PatientNotifType.bookingStarted:
      case PatientNotifType.bookingCompleted:
      case PatientNotifType.bookingRejected:
      case PatientNotifType.bookingCancelled:
        return AppRoutes.myServices;
      case PatientNotifType.counsellingAccepted:
      case PatientNotifType.counsellingStarted:
      case PatientNotifType.counsellingCompleted:
      case PatientNotifType.counsellingCancelled:
        return AppRoutes.careAssistant;
      case PatientNotifType.reviewPrompt:
        return AppRoutes.submitReview;
      default:
        return null;
    }
  }

  String? _serviceRoute(String serviceType) {
    switch (serviceType.toLowerCase()) {
      case 'appointment':   return AppRoutes.appointment;
      case 'medicine':      return AppRoutes.medicine;
      case 'diagnostics':
      case 'lab':           return AppRoutes.diagnostics;
      case 'ambulance':     return AppRoutes.ambulance;
      case 'home_care':
      case 'caregiver':     return AppRoutes.caregivers;
      case 'physiotherapy': return AppRoutes.physio;
      case 'hospital':      return AppRoutes.hospitals;
      case 'pregnancy':     return AppRoutes.pregnancyCheckups;
      case 'nutrition':     return AppRoutes.nutrition;
      case 'quick_connect': return AppRoutes.consultation;
      case 'counselling':   return AppRoutes.careAssistant;
      default:              return AppRoutes.myServices;
    }
  }

  String? _ctaLabel(NotificationModel n) {
    switch (n.type) {
      case PatientNotifType.appointmentAccepted:
      case PatientNotifType.appointmentBooked:
        return 'View Appointment';
      case PatientNotifType.appointmentRescheduled:
        return 'See New Time';
      case PatientNotifType.doctorStartedCall:
      case PatientNotifType.quickConnectStarted:
        return 'Join Call Now';
      case PatientNotifType.prescriptionUploaded:
        return 'View Prescription';
      case PatientNotifType.medicineOutForDelivery:
        return 'Track Delivery';
      case PatientNotifType.medicineDelivered:
        return 'View Order';
      case PatientNotifType.labReportReady:
        return 'View Report';
      case PatientNotifType.ambulanceAccepted:
      case PatientNotifType.ambulanceAssigned:
        return 'Track Ambulance';
      case PatientNotifType.caregiverAssigned:
        return 'View Details';
      case PatientNotifType.pregnancyCheckupReminder:
        return 'View Checkup';
      case PatientNotifType.waterReminder:
        return 'Mark Done';
      case PatientNotifType.medicineReminder:
        return 'Mark Taken';
      case PatientNotifType.consultationDone:
      case PatientNotifType.followupDay1:
      case PatientNotifType.followupDay2:
        return 'View Summary';
      case PatientNotifType.reviewPrompt:
        return 'Rate Now';
      default:
        return null;
    }
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)    return '${diff.inHours}h ago';
    if (diff.inDays == 1)     return 'Yesterday';
    if (diff.inDays < 7)      return '${diff.inDays}d ago';
    return DateFormat('d MMM').format(dt);
  }

  String _serviceLabel(String svc) {
    const labels = {
      'appointment':    'Appointment',
      'medicine':       'Medicine',
      'diagnostics':    'Lab Test',
      'lab':            'Lab Test',
      'ambulance':      'Ambulance',
      'home_care':      'Home Care',
      'caregiver':      'Caregiver',
      'physiotherapy':  'Physio',
      'hospital':       'Hospital',
      'pregnancy':      'Pregnancy',
      'nutrition':      'Nutrition',
      'quick_connect':  'Quick Connect',
      'counselling':    'Counselling',
      'general':        'General',
    };
    return labels[svc.toLowerCase()] ?? svc;
  }
}

// ── Icon + colour metadata for each notification type ─────────────────────────

class _NotifMeta {
  final IconData icon;
  final Color color;

  const _NotifMeta(this.icon, this.color);

  static _NotifMeta of(PatientNotifType type) {
    switch (type) {
      // Consultation / call
      case PatientNotifType.consultationDone:
      case PatientNotifType.consultationUpdate:
      case PatientNotifType.followupDay1:
      case PatientNotifType.followupDay2:
        return const _NotifMeta(
            Icons.video_call_rounded, Color(0xFFC2185B));
      case PatientNotifType.doctorStartedCall:
      case PatientNotifType.quickConnectStarted:
        return const _NotifMeta(
            Icons.phone_in_talk_rounded, Color(0xFF1565C0));

      // Appointments
      case PatientNotifType.appointmentBooked:
      case PatientNotifType.appointmentAccepted:
        return const _NotifMeta(
            Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.appointmentRejected:
      case PatientNotifType.appointmentCancelled:
        return const _NotifMeta(
            Icons.cancel_rounded, Color(0xFFD32F2F));
      case PatientNotifType.appointmentRescheduled:
        return const _NotifMeta(
            Icons.schedule_rounded, Color(0xFFE65100));
      case PatientNotifType.appointmentCompleted:
      case PatientNotifType.appointmentReminder:
        return const _NotifMeta(
            Icons.event_available_rounded, Color(0xFF1B5E20));
      case PatientNotifType.prescriptionUploaded:
        return const _NotifMeta(
            Icons.receipt_long_rounded, Color(0xFF6A1B9A));
      case PatientNotifType.reviewPrompt:
        return const _NotifMeta(Icons.star_rounded, Color(0xFFF9A825));

      // Medicine
      case PatientNotifType.medicineReminder:
      case PatientNotifType.medicineAccepted:
      case PatientNotifType.medicineProcessing:
      case PatientNotifType.medicineVerified:
      case PatientNotifType.medicinePacked:
        return const _NotifMeta(
            Icons.medication_rounded, Color(0xFFE65100));
      case PatientNotifType.medicineOutForDelivery:
        return const _NotifMeta(
            Icons.local_shipping_rounded, Color(0xFF0277BD));
      case PatientNotifType.medicineDelivered:
      case PatientNotifType.orderUpdate:
        return const _NotifMeta(
            Icons.inventory_2_rounded, Color(0xFF2E7D32));
      case PatientNotifType.medicineRejected:
      case PatientNotifType.medicineCancelled:
      case PatientNotifType.medicineReturned:
        return const _NotifMeta(
            Icons.remove_shopping_cart_rounded, Color(0xFFD32F2F));

      // Lab / Diagnostics
      case PatientNotifType.labAccepted:
      case PatientNotifType.labAssigned:
      case PatientNotifType.labInProgress:
      case PatientNotifType.labSampleCollected:
      case PatientNotifType.labProcessing:
        return const _NotifMeta(
            Icons.science_rounded, Color(0xFF0097A7));
      case PatientNotifType.labReportReady:
        return const _NotifMeta(
            Icons.assignment_turned_in_rounded, Color(0xFF00695C));
      case PatientNotifType.labCompleted:
        return const _NotifMeta(
            Icons.biotech_rounded, Color(0xFF2E7D32));
      case PatientNotifType.labRejected:
      case PatientNotifType.labCancelled:
        return const _NotifMeta(
            Icons.cancel_rounded, Color(0xFFD32F2F));

      // Ambulance
      case PatientNotifType.ambulanceAccepted:
      case PatientNotifType.ambulanceAssigned:
      case PatientNotifType.ambulanceEnRoute:
        return const _NotifMeta(
            Icons.emergency_rounded, Color(0xFFD32F2F));
      case PatientNotifType.ambulanceReached:
        return const _NotifMeta(
            Icons.local_hospital_rounded, Color(0xFFC62828));
      case PatientNotifType.ambulanceCompleted:
        return const _NotifMeta(
            Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.ambulanceRejected:
      case PatientNotifType.ambulanceCancelled:
        return const _NotifMeta(
            Icons.cancel_rounded, Color(0xFFD32F2F));

      // Home Care / Caregiver
      case PatientNotifType.homecareAccepted:
      case PatientNotifType.caregiverAssigned:
      case PatientNotifType.caregiverStarted:
        return const _NotifMeta(
            Icons.home_rounded, Color(0xFF6A1B9A));
      case PatientNotifType.homecareCompleted:
        return const _NotifMeta(
            Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.homecareRejected:
      case PatientNotifType.homecareCancelled:
        return const _NotifMeta(
            Icons.cancel_rounded, Color(0xFFD32F2F));

      // Physiotherapy
      case PatientNotifType.physioAccepted:
      case PatientNotifType.physioAssigned:
      case PatientNotifType.physioStarted:
        return const _NotifMeta(
            Icons.accessibility_new_rounded, Color(0xFF00838F));
      case PatientNotifType.physioCompleted:
        return const _NotifMeta(
            Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.physioRejected:
      case PatientNotifType.physioCancelled:
        return const _NotifMeta(
            Icons.cancel_rounded, Color(0xFFD32F2F));

      // Hospital
      case PatientNotifType.hospitalAccepted:
      case PatientNotifType.hospitalAssigned:
      case PatientNotifType.hospitalAdmitted:
        return const _NotifMeta(
            Icons.local_hospital_rounded, Color(0xFF1565C0));
      case PatientNotifType.hospitalDischarged:
        return const _NotifMeta(
            Icons.directions_walk_rounded, Color(0xFF2E7D32));
      case PatientNotifType.hospitalRejected:
      case PatientNotifType.hospitalCancelled:
        return const _NotifMeta(
            Icons.cancel_rounded, Color(0xFFD32F2F));

      // Pregnancy
      case PatientNotifType.pregnancyCheckupBooked:
      case PatientNotifType.pregnancyCheckupConfirmed:
        return const _NotifMeta(
            Icons.pregnant_woman_rounded, Color(0xFFAD1457));
      case PatientNotifType.pregnancyCheckupReminder:
        return const _NotifMeta(
            Icons.alarm_rounded, Color(0xFFE65100));
      case PatientNotifType.pregnancyCheckupCompleted:
        return const _NotifMeta(
            Icons.favorite_rounded, Color(0xFFC2185B));
      case PatientNotifType.pregnancyCheckupCancelled:
        return const _NotifMeta(
            Icons.cancel_rounded, Color(0xFFD32F2F));

      // Nutrition
      case PatientNotifType.nutritionAccepted:
      case PatientNotifType.nutritionStarted:
        return const _NotifMeta(
            Icons.restaurant_rounded, Color(0xFF558B2F));
      case PatientNotifType.nutritionCompleted:
        return const _NotifMeta(
            Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.nutritionRejected:
      case PatientNotifType.nutritionCancelled:
        return const _NotifMeta(
            Icons.cancel_rounded, Color(0xFFD32F2F));

      // Counselling
      case PatientNotifType.counsellingAccepted:
      case PatientNotifType.counsellingStarted:
        return const _NotifMeta(
            Icons.psychology_rounded, Color(0xFF4527A0));
      case PatientNotifType.counsellingCompleted:
        return const _NotifMeta(
            Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.counsellingCancelled:
        return const _NotifMeta(
            Icons.cancel_rounded, Color(0xFFD32F2F));

      // Generic bookings
      case PatientNotifType.bookingAccepted:
      case PatientNotifType.bookingAssigned:
      case PatientNotifType.bookingStarted:
        return const _NotifMeta(
            Icons.event_note_rounded, AppColors.primary);
      case PatientNotifType.bookingCompleted:
        return const _NotifMeta(
            Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.bookingRejected:
      case PatientNotifType.bookingCancelled:
        return const _NotifMeta(
            Icons.cancel_rounded, Color(0xFFD32F2F));

      // Quick connect
      case PatientNotifType.quickConnectAccepted:
        return const _NotifMeta(
            Icons.flash_on_rounded, Color(0xFFFF6F00));
      case PatientNotifType.quickConnectCompleted:
        return const _NotifMeta(
            Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.quickConnectRejected:
      case PatientNotifType.quickConnectCancelled:
        return const _NotifMeta(
            Icons.cancel_rounded, Color(0xFFD32F2F));

      // Health
      case PatientNotifType.waterReminder:
        return const _NotifMeta(
            Icons.water_drop_rounded, Color(0xFF1565C0));
      case PatientNotifType.periodTracker:
        return const _NotifMeta(
            Icons.favorite_rounded, Color(0xFFC2185B));
      case PatientNotifType.healthTip:
        return const _NotifMeta(Icons.star_rounded, Color(0xFFF9A825));

      // Rewards
      case PatientNotifType.referralReward:
      case PatientNotifType.welcomeBonus:
        return const _NotifMeta(
            Icons.card_giftcard_rounded, Color(0xFF6A1B9A));

      default:
        return const _NotifMeta(
            Icons.notifications_rounded, AppColors.textSecondary);
    }
  }
}

// ── Empty / all-read states ───────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return FadeInSlide(
      child: AppEmptyState(
        icon: Icons.notifications_none_rounded,
        title: 'All caught up!',
        message:
            "You're all caught up!\nWe'll notify you when something needs your attention.",
      ),
    );
  }
}

class _AllReadState extends StatelessWidget {
  const _AllReadState();

  @override
  Widget build(BuildContext context) {
    return FadeInSlide(
      child: AppEmptyState(
        icon: Icons.done_all_rounded,
        title: 'No unread notifications',
        message: 'All your notifications are read. Check the All tab for history.',
      ),
    );
  }
}
