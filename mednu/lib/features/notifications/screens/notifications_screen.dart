import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mednu/core/constants/app_colors.dart';
import 'package:mednu/core/constants/app_text_styles.dart';
import 'package:mednu/core/router/app_router.dart';
import 'package:mednu/core/widgets/ux_widgets.dart';
import '../../health/providers/water_tracker_provider.dart';
import '../models/notification_model.dart';
import '../providers/notification_provider.dart';
import '../services/notification_service.dart';
import 'package:mednu/core/utils/r.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Notifications Screen
// Tabs: All / Appointments / Health / Promotions
// Groups by Today / Yesterday / Earlier
// Shimmer loading, swipe-to-dismiss, pull-to-refresh, mark-all-read
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

  static const _tabs = ['All', 'Appointments', 'Health', 'Promotions'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
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
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.done_all_rounded,
                color: Colors.white,
                size: R.w(context, 18),
              ),
              SizedBox(width: R.w(context, 10)),
              const Text(
                'All notifications marked as read',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.r(context, 12)),
          ),
          margin: EdgeInsets.all(R.p(context, 16)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearAllRead(List<NotificationModel> list) async {
    final readCount = list.where((n) => n.isRead).length;
    if (readCount == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.r(dialogCtx, 20)),
        ),
        title: const Text(
          'Clear Read Notifications',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Remove $readCount read notification${readCount == 1 ? '' : 's'}?',
          style: const TextStyle(fontFamily: 'Poppins'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(R.r(dialogCtx, 10)),
              ),
            ),
            child: const Text(
              'Clear',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
            ),
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
    final unreadCount = ref.watch(patientUnreadCountProvider);

    return Scaffold(
      backgroundColor: context.appBackground,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: R.h(context, 196),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: R.w(context, 20),
              ),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go(AppRoutes.home),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (unreadCount > 0) ...[
                  SizedBox(width: R.w(context, 8)),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: R.p(context, 7),
                      vertical: R.p(context, 2),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(R.r(context, 10)),
                    ),
                    child: Text(
                      '$unreadCount',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              notifAsync.when(
                data: (list) {
                  final hasUnread = list.any((n) => !n.isRead);
                  final hasRead = list.any((n) => n.isRead);
                  if (!hasUnread && !hasRead) return const SizedBox.shrink();
                  return PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: Colors.white,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(R.r(context, 14)),
                    ),
                    onSelected: (v) {
                      if (v == 'mark_all') _markAllRead();
                      if (v == 'clear_read') _clearAllRead(list);
                    },
                    itemBuilder: (menuCtx) => [
                      if (hasUnread)
                        PopupMenuItem(
                          value: 'mark_all',
                          child: Row(
                            children: [
                              Icon(
                                Icons.done_all_rounded,
                                size: R.w(menuCtx, 18),
                                color: AppColors.primary,
                              ),
                              SizedBox(width: R.w(menuCtx, 10)),
                              const Text(
                                'Mark all as read',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (hasRead)
                        PopupMenuItem(
                          value: 'clear_read',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_sweep_rounded,
                                size: R.w(menuCtx, 18),
                                color: AppColors.error,
                              ),
                              SizedBox(width: R.w(menuCtx, 10)),
                              const Text(
                                'Clear read',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _HeaderBackground(unreadCount: unreadCount),
            ),
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(R.h(context, 44)),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                ),
                child: TabBar(
                  controller: _tab,
                  labelStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: _tabs
                      .map(
                        (t) => Tab(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: R.p(context, 4),
                            ),
                            child: Text(t),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tab,
          children: [
            _NotifListView(uid: _uid, filter: _TabFilter.all),
            _NotifListView(uid: _uid, filter: _TabFilter.appointments),
            _NotifListView(uid: _uid, filter: _TabFilter.health),
            _NotifListView(uid: _uid, filter: _TabFilter.promotions),
          ],
        ),
      ),
    );
  }
}

// ── Tab filter enum ────────────────────────────────────────────────────────────

enum _TabFilter { all, appointments, health, promotions }

// ── Gradient header background ────────────────────────────────────────────────

class _HeaderBackground extends StatelessWidget {
  final int unreadCount;
  const _HeaderBackground({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryDark,
            AppColors.primary,
            AppColors.secondary,
          ],
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
              width: R.w(context, 130),
              height: R.h(context, 130),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 44,
            left: -30,
            child: Container(
              width: R.w(context, 90),
              height: R.h(context, 90),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // No Scrollable here: this background sits inside the outer
                // NestedScrollView's SliverAppBar, and a nested Scrollable
                // (even a non-scrolling one) installs a drag recognizer that
                // competes with the outer scroll in the gesture arena, causing
                // stuttering/stalling swipes. Content is fixed-size and fits
                // well within expandedHeight, so ConstrainedBox alone (no
                // scroll safety-net) is enough to vertically center it.
                return ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      R.p(context, 20),
                      R.p(context, 24),
                      R.p(context, 20),
                      R.p(context, 16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: R.w(context, 44),
                          height: R.h(context, 44),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(
                              R.r(context, 14),
                            ),
                          ),
                          child: Icon(
                            Icons.notifications_rounded,
                            color: Colors.white,
                            size: R.w(context, 24),
                          ),
                        ),
                        SizedBox(width: R.w(context, 14)),
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
                                  ? '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}'
                                  : 'Stay updated',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        if (unreadCount > 0) ...[
                          const Spacer(),
                          Container(
                            width: R.w(context, 46),
                            height: R.h(context, 46),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '$unreadCount',
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
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
  final _TabFilter filter;

  const _NotifListView({required this.uid, required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifAsync = ref.watch(patientNotificationsProvider);

    return notifAsync.when(
      loading: () => _ShimmerList(),
      error: (e, _) => AppErrorState(
        message: 'Unable to load notifications.\nPull down to refresh.',
        onRetry: () => ref.invalidate(patientNotificationsProvider),
      ),
      data: (all) {
        final notifications = _applyFilter(all, filter);

        if (notifications.isEmpty) {
          return _EmptyState(filter: filter);
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
                  padding: EdgeInsets.fromLTRB(
                    R.p(context, 16),
                    R.p(context, 16),
                    R.p(context, 16),
                    R.p(context, 4),
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _DateHeader(label: group.label),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    R.p(context, 16),
                    0,
                    R.p(context, 16),
                    0,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((_, i) {
                      final notif = group.items[i];
                      return Dismissible(
                        key: ValueKey(notif.id),
                        direction: DismissDirection.endToStart,
                        background: const _SwipeDeleteBg(),
                        onDismissed: (_) =>
                            PatientNotificationService.deleteNotification(
                              uid,
                              notif.id,
                            ),
                        child: FadeInSlide(
                          delay: Duration(milliseconds: i * 30),
                          child: _NotifTile(notif: notif, uid: uid),
                        ),
                      );
                    }, childCount: group.items.length),
                  ),
                ),
              ],
              SliverToBoxAdapter(child: SizedBox(height: R.h(context, 32))),
            ],
          ),
        );
      },
    );
  }

  List<NotificationModel> _applyFilter(
    List<NotificationModel> all,
    _TabFilter filter,
  ) {
    switch (filter) {
      case _TabFilter.all:
        return all;
      case _TabFilter.appointments:
        return all.where((n) => _appointmentTypes.contains(n.type)).toList();
      case _TabFilter.health:
        return all.where((n) => _healthTypes.contains(n.type)).toList();
      case _TabFilter.promotions:
        return all.where((n) => _promotionTypes.contains(n.type)).toList();
    }
  }

  static const _appointmentTypes = {
    PatientNotifType.appointmentBooked,
    PatientNotifType.appointmentAccepted,
    PatientNotifType.appointmentRejected,
    PatientNotifType.appointmentRescheduled,
    PatientNotifType.appointmentCompleted,
    PatientNotifType.appointmentCancelled,
    PatientNotifType.appointmentReminder,
    PatientNotifType.consultationDone,
    PatientNotifType.consultationUpdate,
    PatientNotifType.followupDay1,
    PatientNotifType.followupDay2,
    PatientNotifType.doctorStartedCall,
    PatientNotifType.quickConnectAccepted,
    PatientNotifType.quickConnectStarted,
    PatientNotifType.quickConnectCompleted,
    PatientNotifType.quickConnectRejected,
    PatientNotifType.quickConnectCancelled,
    PatientNotifType.prescriptionUploaded,
    PatientNotifType.reviewPrompt,
  };

  static const _healthTypes = {
    PatientNotifType.waterReminder,
    PatientNotifType.periodTracker,
    PatientNotifType.medicineReminder,
    PatientNotifType.healthTip,
    PatientNotifType.nutritionAccepted,
    PatientNotifType.nutritionStarted,
    PatientNotifType.nutritionCompleted,
    PatientNotifType.nutritionCancelled,
    PatientNotifType.nutritionRejected,
    PatientNotifType.pregnancyCheckupBooked,
    PatientNotifType.pregnancyCheckupReminder,
    PatientNotifType.pregnancyCheckupConfirmed,
    PatientNotifType.pregnancyCheckupCompleted,
    PatientNotifType.pregnancyCheckupCancelled,
  };

  static const _promotionTypes = {
    PatientNotifType.referralReward,
    PatientNotifType.welcomeBonus,
  };

  List<_DateGroup> _groupByDate(List<NotificationModel> notifications) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final groups = <String, List<NotificationModel>>{};

    for (final n in notifications) {
      final d = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      final String label;
      if (!d.isBefore(today)) {
        label = 'Today';
      } else if (!d.isBefore(yesterday)) {
        label = 'Yesterday';
      } else {
        label = 'Earlier';
      }
      (groups[label] ??= []).add(n);
    }

    const order = ['Today', 'Yesterday', 'Earlier'];
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

// ── Shimmer loading list ───────────────────────────────────────────────────────

class _ShimmerList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          R.p(context, 16),
          R.p(context, 20),
          R.p(context, 16),
          R.p(context, 32),
        ),
        itemCount: 5,
        separatorBuilder: (_, __) => SizedBox(height: R.h(context, 12)),
        itemBuilder: (_, __) => Container(
          padding: EdgeInsets.all(R.p(context, 14)),
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(R.r(context, 16)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonCircle(size: R.w(context, 46)),
              SizedBox(width: R.w(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(
                      width: R.w(context, 160),
                      height: R.h(context, 13),
                      radius: R.r(context, 6),
                    ),
                    SizedBox(height: R.h(context, 8)),
                    SkeletonBox(
                      width: double.infinity,
                      height: R.h(context, 11),
                      radius: R.r(context, 5),
                    ),
                    SizedBox(height: R.h(context, 6)),
                    SkeletonBox(
                      width: R.w(context, 180),
                      height: R.h(context, 11),
                      radius: R.r(context, 5),
                    ),
                    SizedBox(height: R.h(context, 10)),
                    SkeletonBox(
                      width: R.w(context, 70),
                      height: R.h(context, 20),
                      radius: R.r(context, 8),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.appTextSecondary,
            letterSpacing: 0.8,
          ),
        ),
        SizedBox(width: R.w(context, 10)),
        Expanded(
          child: Divider(color: context.appDivider, thickness: 1, height: 1),
        ),
      ],
    );
  }
}

// ── Swipe-to-delete background ────────────────────────────────────────────────

class _SwipeDeleteBg extends StatelessWidget {
  const _SwipeDeleteBg();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: R.p(context, 10)),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.r(context, 16)),
      ),
      alignment: Alignment.centerRight,
      padding: EdgeInsets.only(right: R.p(context, 20)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.delete_rounded,
            color: AppColors.error,
            size: R.w(context, 24),
          ),
          SizedBox(height: R.h(context, 4)),
          Text(
            'Delete',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.error),
          ),
        ],
      ),
    );
  }
}

// ── Notification tile ─────────────────────────────────────────────────────────

class _NotifTile extends ConsumerWidget {
  final NotificationModel notif;
  final String uid;

  const _NotifTile({required this.notif, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = _NotifMeta.of(notif.type);

    return GestureDetector(
      onTap: () => _onTap(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: R.p(context, 10)),
        decoration: BoxDecoration(
          color: notif.isRead
              ? context.appSurface
              : meta.color.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(R.r(context, 16)),
          // Border must stay uniform (same width+color on all sides) whenever
          // borderRadius is set, or BoxDecoration.paint() throws "A borderRadius
          // can only be given on borders with uniform colors." The unread accent
          // is drawn separately below as a clipped left stripe instead.
          border: Border.all(
            color: notif.isRead
                ? context.appBorder
                : meta.color.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: notif.isRead
                  ? Colors.black.withValues(alpha: 0.03)
                  : meta.color.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(R.r(context, 16)),
          // IntrinsicHeight lets the stripe stretch to the content's natural
          // height even though this tile is height-unconstrained (sized by
          // its content inside a sliver list).
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: R.w(context, 3.5),
                  color: notif.isRead ? Colors.transparent : meta.color,
                ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _onTap(context),
                      child: Padding(
                        padding: EdgeInsets.all(R.p(context, 14)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Icon with colored background
                            Container(
                              width: R.w(context, 46),
                              height: R.h(context, 46),
                              decoration: BoxDecoration(
                                color: meta.color.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(
                                  R.r(context, 13),
                                ),
                              ),
                              child: Icon(
                                meta.icon,
                                color: meta.color,
                                size: R.w(context, 22),
                              ),
                            ),
                            SizedBox(width: R.w(context, 12)),

                            // Content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          notif.title,
                                          style: AppTextStyles.labelLarge
                                              .copyWith(
                                                fontWeight: notif.isRead
                                                    ? FontWeight.w600
                                                    : FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      SizedBox(width: R.w(context, 6)),
                                      if (!notif.isRead)
                                        Container(
                                          width: R.w(context, 8),
                                          height: R.h(context, 8),
                                          margin: EdgeInsets.only(
                                            top: R.p(context, 4),
                                          ),
                                          decoration: BoxDecoration(
                                            color: meta.color,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: R.h(context, 4)),
                                  Text(
                                    notif.body,
                                    style: AppTextStyles.bodySmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: R.h(context, 8)),
                                  Row(
                                    children: [
                                      if (notif.serviceType.isNotEmpty)
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: R.p(context, 8),
                                            vertical: R.p(context, 3),
                                          ),
                                          decoration: BoxDecoration(
                                            color: meta.color.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              R.r(context, 8),
                                            ),
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
                                        style: AppTextStyles.caption.copyWith(
                                          color: context.appTextHint,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_ctaLabel(notif) != null) ...[
                                    SizedBox(height: R.h(context, 10)),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: () async {
                                          PatientNotificationService.markRead(
                                            uid,
                                            notif.id,
                                          );
                                          // "Mark Done" used to just open the
                                          // water tracker screen without
                                          // logging anything — this actually
                                          // logs the glass, same call
                                          // home_widgets.dart's own Mark Done
                                          // button makes.
                                          if (notif.type == PatientNotifType.waterReminder) {
                                            await ref.read(waterTrackerProvider.notifier).logWater();
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Nice! Water intake logged.')),
                                              );
                                            }
                                            return;
                                          }
                                          _navigate(context);
                                        },
                                        style: ElevatedButton.styleFrom(
                                          padding: EdgeInsets.symmetric(
                                            vertical: R.p(context, 10),
                                          ),
                                          backgroundColor: meta.color,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              R.r(context, 10),
                                            ),
                                          ),
                                          elevation: 0,
                                          minimumSize: Size(
                                            double.infinity,
                                            R.h(context, 38),
                                          ),
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
              ],
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

  // Medicine/pharmacy order events — including the prescription-decision
  // types, which are updates on the same `orders` doc — carry a real order
  // id in `bookingId` (functions/index.js sets `bookingId: orderId`). Without
  // this, they fell back to either a fake generic tracker (_routeFor's bare
  // AppRoutes.orderTracking) or the medicine shopping catalogue
  // (_serviceRoute('medicine') for actionType open_service), never the order
  // itself — the concrete reason "upload prescription" felt unreachable from
  // a pharmacy_prescription_required push.
  static const _medicineOrderTypes = {
    PatientNotifType.medicineAccepted,
    PatientNotifType.medicineProcessing,
    PatientNotifType.medicineVerified,
    PatientNotifType.medicinePacked,
    PatientNotifType.medicineOutForDelivery,
    PatientNotifType.medicineDelivered,
    PatientNotifType.medicineCancelled,
    PatientNotifType.medicineReturned,
    PatientNotifType.medicineRejected,
    PatientNotifType.orderUpdate,
    PatientNotifType.prescriptionRequired,
    PatientNotifType.prescriptionVerified,
    PatientNotifType.prescriptionRejected,
    PatientNotifType.prescriptionReuploadRequested,
  };

  void _navigate(BuildContext context) {
    // Prescription notifications need a real Firestore fetch before we can
    // navigate — PrescriptionViewerScreen has no fetch-by-id fallback, so
    // pushing its plain route (as _routeFor would) renders a blank RX-0000
    // placeholder instead of the actual prescription.
    if (notif.actionType == 'open_prescription' ||
        notif.type == PatientNotifType.prescriptionUploaded) {
      _openPrescription(context);
      return;
    }
    if ((_medicineOrderTypes.contains(notif.type) ||
            notif.actionType == 'open_order' ||
            (notif.actionType == 'open_service' &&
                notif.serviceType == 'medicine')) &&
        notif.bookingId.isNotEmpty) {
      context.push(AppRoutes.orderDetail, extra: {'orderId': notif.bookingId});
      return;
    }
    final route = _routeFor(notif);
    if (route != null && context.mounted) context.push(route);
  }

  Future<void> _openPrescription(BuildContext context) async {
    Map<String, dynamic>? rx;
    if (notif.bookingId.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('prescriptions')
            .where('appointmentId', isEqualTo: notif.bookingId)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          rx = {...snap.docs.first.data(), 'id': snap.docs.first.id};
        }
      } catch (_) {}
    }
    if (!context.mounted) return;
    if (rx != null) {
      context.push(AppRoutes.prescriptionViewer, extra: rx);
    } else {
      context.push(AppRoutes.records);
    }
  }

  String? _routeFor(NotificationModel n) {
    switch (n.actionType) {
      case 'open_call':
        return AppRoutes.consultation;
      case 'open_prescription':
        return AppRoutes.prescriptionViewer;
      case 'open_order':
        // Fallback only (no bookingId) — _navigate handles the real order
        // case first.
        return AppRoutes.medicineOrders;
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
      case PatientNotifType.prescriptionRequired:
      case PatientNotifType.prescriptionVerified:
      case PatientNotifType.prescriptionRejected:
      case PatientNotifType.prescriptionReuploadRequested:
        // Fallback only — _navigate handles these first with the real
        // orderId when bookingId is present. This is the real orders list,
        // not the fake tracker AppRoutes.orderTracking used to point to.
        return AppRoutes.medicineOrders;
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
        // There is no per-dose intake log in this app (unlike water, which
        // waterTrackerProvider actually tracks) — AppRoutes.medicine was the
        // shopping catalogue, not even a relevant screen for "did you take
        // it". This is the user's own medicine list instead.
        return AppRoutes.myMedicines;
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
      case 'appointment':
        return AppRoutes.appointment;
      case 'medicine':
        // The real orders list, not the shopping catalogue — a medicine
        // order-status push (e.g. pharmacy_prescription_required) means
        // "look at your order," not "browse medicines." _navigate handles
        // the common case (bookingId present) by going straight to the
        // specific order; this is only the no-bookingId fallback.
        return AppRoutes.medicineOrders;
      case 'diagnostics':
      case 'lab':
        return AppRoutes.diagnostics;
      case 'ambulance':
        return AppRoutes.ambulance;
      case 'home_care':
      case 'caregiver':
        return AppRoutes.caregivers;
      case 'physiotherapy':
        return AppRoutes.physio;
      case 'hospital':
        return AppRoutes.hospitals;
      case 'pregnancy':
        return AppRoutes.pregnancyCheckups;
      case 'nutrition':
        return AppRoutes.nutrition;
      case 'quick_connect':
        return AppRoutes.consultation;
      case 'counselling':
        return AppRoutes.careAssistant;
      default:
        return AppRoutes.myServices;
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
      case PatientNotifType.prescriptionRequired:
      case PatientNotifType.prescriptionReuploadRequested:
        return 'Upload Prescription';
      case PatientNotifType.prescriptionVerified:
        return 'View Order';
      case PatientNotifType.prescriptionRejected:
        return 'View Details';
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
        // Not "Mark Taken" — there's no dose-intake log for this button to
        // write to, so a label implying one would be a second dead action.
        return 'View Medicines';
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
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM').format(dt);
  }

  String _serviceLabel(String svc) {
    const labels = {
      'appointment': 'Appointment',
      'medicine': 'Pharmacy',
      'diagnostics': 'Lab Test',
      'lab': 'Lab Test',
      'ambulance': 'Ambulance',
      'home_care': 'Home Care',
      'caregiver': 'Caregiver',
      'physiotherapy': 'Physio',
      'hospital': 'Hospital',
      'pregnancy': 'Pregnancy',
      'nutrition': 'Nutrition',
      'quick_connect': 'Quick Connect',
      'counselling': 'Counselling',
      'general': 'General',
    };
    return labels[svc.toLowerCase()] ?? svc;
  }
}

// ── Icon + colour metadata ─────────────────────────────────────────────────────

class _NotifMeta {
  final IconData icon;
  final Color color;

  const _NotifMeta(this.icon, this.color);

  static _NotifMeta of(PatientNotifType type) {
    switch (type) {
      case PatientNotifType.consultationDone:
      case PatientNotifType.consultationUpdate:
      case PatientNotifType.followupDay1:
      case PatientNotifType.followupDay2:
        return const _NotifMeta(Icons.video_call_rounded, Color(0xFF522546));
      case PatientNotifType.doctorStartedCall:
      case PatientNotifType.quickConnectStarted:
        return const _NotifMeta(Icons.phone_in_talk_rounded, Color(0xFF1565C0));
      case PatientNotifType.appointmentBooked:
      case PatientNotifType.appointmentAccepted:
        return const _NotifMeta(Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.appointmentRejected:
      case PatientNotifType.appointmentCancelled:
        return const _NotifMeta(Icons.cancel_rounded, Color(0xFFD32F2F));
      case PatientNotifType.appointmentRescheduled:
        return const _NotifMeta(Icons.schedule_rounded, Color(0xFFE65100));
      case PatientNotifType.appointmentCompleted:
      case PatientNotifType.appointmentReminder:
        return const _NotifMeta(
          Icons.event_available_rounded,
          Color(0xFF1B5E20),
        );
      case PatientNotifType.prescriptionUploaded:
        return const _NotifMeta(Icons.receipt_long_rounded, Color(0xFF6A1B9A));
      case PatientNotifType.reviewPrompt:
        return const _NotifMeta(Icons.star_rounded, Color(0xFFF9A825));
      case PatientNotifType.medicineReminder:
      case PatientNotifType.medicineAccepted:
      case PatientNotifType.medicineProcessing:
      case PatientNotifType.medicineVerified:
      case PatientNotifType.medicinePacked:
        return const _NotifMeta(Icons.medication_rounded, Color(0xFFE65100));
      case PatientNotifType.medicineOutForDelivery:
        return const _NotifMeta(
          Icons.local_shipping_rounded,
          Color(0xFF0277BD),
        );
      case PatientNotifType.medicineDelivered:
      case PatientNotifType.orderUpdate:
        return const _NotifMeta(Icons.inventory_2_rounded, Color(0xFF2E7D32));
      case PatientNotifType.medicineRejected:
      case PatientNotifType.medicineCancelled:
      case PatientNotifType.medicineReturned:
        return const _NotifMeta(
          Icons.remove_shopping_cart_rounded,
          Color(0xFFD32F2F),
        );
      case PatientNotifType.labAccepted:
      case PatientNotifType.labAssigned:
      case PatientNotifType.labInProgress:
      case PatientNotifType.labSampleCollected:
      case PatientNotifType.labProcessing:
        return const _NotifMeta(Icons.science_rounded, Color(0xFF0097A7));
      case PatientNotifType.labReportReady:
        return const _NotifMeta(
          Icons.assignment_turned_in_rounded,
          Color(0xFF00695C),
        );
      case PatientNotifType.labCompleted:
        return const _NotifMeta(Icons.biotech_rounded, Color(0xFF2E7D32));
      case PatientNotifType.labRejected:
      case PatientNotifType.labCancelled:
        return const _NotifMeta(Icons.cancel_rounded, Color(0xFFD32F2F));
      case PatientNotifType.ambulanceAccepted:
      case PatientNotifType.ambulanceAssigned:
      case PatientNotifType.ambulanceEnRoute:
        return const _NotifMeta(Icons.emergency_rounded, Color(0xFFD32F2F));
      case PatientNotifType.ambulanceReached:
        return const _NotifMeta(
          Icons.local_hospital_rounded,
          Color(0xFFC62828),
        );
      case PatientNotifType.ambulanceCompleted:
        return const _NotifMeta(Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.ambulanceRejected:
      case PatientNotifType.ambulanceCancelled:
        return const _NotifMeta(Icons.cancel_rounded, Color(0xFFD32F2F));
      case PatientNotifType.homecareAccepted:
      case PatientNotifType.caregiverAssigned:
      case PatientNotifType.caregiverStarted:
        return const _NotifMeta(Icons.home_rounded, Color(0xFF6A1B9A));
      case PatientNotifType.homecareCompleted:
        return const _NotifMeta(Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.homecareRejected:
      case PatientNotifType.homecareCancelled:
        return const _NotifMeta(Icons.cancel_rounded, Color(0xFFD32F2F));
      case PatientNotifType.physioAccepted:
      case PatientNotifType.physioAssigned:
      case PatientNotifType.physioStarted:
        return const _NotifMeta(
          Icons.accessibility_new_rounded,
          Color(0xFF00838F),
        );
      case PatientNotifType.physioCompleted:
        return const _NotifMeta(Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.physioRejected:
      case PatientNotifType.physioCancelled:
        return const _NotifMeta(Icons.cancel_rounded, Color(0xFFD32F2F));
      case PatientNotifType.hospitalAccepted:
      case PatientNotifType.hospitalAssigned:
      case PatientNotifType.hospitalAdmitted:
        return const _NotifMeta(
          Icons.local_hospital_rounded,
          Color(0xFF1565C0),
        );
      case PatientNotifType.hospitalDischarged:
        return const _NotifMeta(
          Icons.directions_walk_rounded,
          Color(0xFF2E7D32),
        );
      case PatientNotifType.hospitalRejected:
      case PatientNotifType.hospitalCancelled:
        return const _NotifMeta(Icons.cancel_rounded, Color(0xFFD32F2F));
      case PatientNotifType.pregnancyCheckupBooked:
      case PatientNotifType.pregnancyCheckupConfirmed:
        return const _NotifMeta(
          Icons.pregnant_woman_rounded,
          Color(0xFFAD1457),
        );
      case PatientNotifType.pregnancyCheckupReminder:
        return const _NotifMeta(Icons.alarm_rounded, Color(0xFFE65100));
      case PatientNotifType.pregnancyCheckupCompleted:
        return const _NotifMeta(Icons.favorite_rounded, Color(0xFF522546));
      case PatientNotifType.pregnancyCheckupCancelled:
        return const _NotifMeta(Icons.cancel_rounded, Color(0xFFD32F2F));
      case PatientNotifType.nutritionAccepted:
      case PatientNotifType.nutritionStarted:
        return const _NotifMeta(Icons.restaurant_rounded, Color(0xFF558B2F));
      case PatientNotifType.nutritionCompleted:
        return const _NotifMeta(Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.nutritionRejected:
      case PatientNotifType.nutritionCancelled:
        return const _NotifMeta(Icons.cancel_rounded, Color(0xFFD32F2F));
      case PatientNotifType.counsellingAccepted:
      case PatientNotifType.counsellingStarted:
        return const _NotifMeta(Icons.psychology_rounded, Color(0xFF4527A0));
      case PatientNotifType.counsellingCompleted:
        return const _NotifMeta(Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.counsellingCancelled:
        return const _NotifMeta(Icons.cancel_rounded, Color(0xFFD32F2F));
      case PatientNotifType.bookingAccepted:
      case PatientNotifType.bookingAssigned:
      case PatientNotifType.bookingStarted:
        return const _NotifMeta(Icons.event_note_rounded, AppColors.primary);
      case PatientNotifType.bookingCompleted:
        return const _NotifMeta(Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.bookingRejected:
      case PatientNotifType.bookingCancelled:
        return const _NotifMeta(Icons.cancel_rounded, Color(0xFFD32F2F));
      case PatientNotifType.quickConnectAccepted:
        return const _NotifMeta(Icons.flash_on_rounded, Color(0xFFFF6F00));
      case PatientNotifType.quickConnectCompleted:
        return const _NotifMeta(Icons.check_circle_rounded, Color(0xFF2E7D32));
      case PatientNotifType.quickConnectRejected:
      case PatientNotifType.quickConnectCancelled:
        return const _NotifMeta(Icons.cancel_rounded, Color(0xFFD32F2F));
      case PatientNotifType.waterReminder:
        return const _NotifMeta(Icons.water_drop_rounded, Color(0xFF1565C0));
      case PatientNotifType.periodTracker:
        return const _NotifMeta(Icons.favorite_rounded, Color(0xFF522546));
      case PatientNotifType.healthTip:
        return const _NotifMeta(Icons.star_rounded, Color(0xFFF9A825));
      case PatientNotifType.referralReward:
      case PatientNotifType.welcomeBonus:
        return const _NotifMeta(Icons.card_giftcard_rounded, Color(0xFF6A1B9A));
      default:
        return const _NotifMeta(
          Icons.notifications_rounded,
          AppColors.textSecondary,
        );
    }
  }
}

// ── Empty state per tab ───────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final _TabFilter filter;
  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (filter) {
      _TabFilter.all => (
        Icons.notifications_none_rounded,
        'All caught up!',
        "You're all caught up!\nWe'll notify you when something needs attention.",
      ),
      _TabFilter.appointments => (
        Icons.calendar_today_outlined,
        'No appointment notifications',
        'Appointment updates and reminders\nwill appear here.',
      ),
      _TabFilter.health => (
        Icons.favorite_border_rounded,
        'No health notifications',
        'Water reminders, period tracker alerts,\nand health tips will appear here.',
      ),
      _TabFilter.promotions => (
        Icons.local_offer_outlined,
        'No promotions',
        'Rewards, referral bonuses, and\nspecial offers will appear here.',
      ),
    };

    return FadeInSlide(
      child: AppEmptyState(icon: icon, title: title, message: message),
    );
  }
}
