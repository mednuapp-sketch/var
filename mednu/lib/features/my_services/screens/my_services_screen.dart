import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../home/providers/home_nav_provider.dart'
    show bottomNavIndexProvider;
import '../models/unified_booking.dart';
import '../providers/my_services_provider.dart';
import '../services/my_services_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MyServicesScreen
// ─────────────────────────────────────────────────────────────────────────────

class MyServicesScreen extends ConsumerStatefulWidget {
  const MyServicesScreen({super.key});

  @override
  ConsumerState<MyServicesScreen> createState() => _MyServicesScreenState();
}

class _MyServicesScreenState extends ConsumerState<MyServicesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  static const _tabLabels = ['Active', 'Upcoming', 'Completed', 'Cancelled'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabLabels.length, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text(
          'My Services',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () {
            // When embedded as the Home shell's "Services" bottom-nav tab
            // (see HomeScreen's IndexedStack), there's nothing on the
            // navigator stack to pop, so fall back to switching to the
            // Home tab instead of a no-op pop.
            if (context.canPop()) {
              context.pop();
            } else {
              ref.read(bottomNavIndexProvider.notifier).state = 0;
            }
          },
        ),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.medicineOrders),
            icon: const Icon(Icons.medication_outlined, color: Colors.white),
            tooltip: 'Medicine Orders',
          ),
          IconButton(
            onPressed: () => ref.invalidate(allBookingsProvider),
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          tabs: _tabLabels
              .map(
                (t) => Tab(
                  child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _BookingsList(filter: _BookingFilter.active),
          _BookingsList(filter: _BookingFilter.upcoming),
          _BookingsList(filter: _BookingFilter.completed),
          _BookingsList(filter: _BookingFilter.cancelled),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Filter enum
// ─────────────────────────────────────────────────────────────────────────────

enum _BookingFilter { active, upcoming, completed, cancelled }

// ─────────────────────────────────────────────────────────────────────────────
//  Booking list per tab
// ─────────────────────────────────────────────────────────────────────────────

class _BookingsList extends ConsumerWidget {
  final _BookingFilter filter;
  const _BookingsList({required this.filter});

  static const _upcomingStatuses = {
    BookingStatus.pending,
    BookingStatus.requested,
    BookingStatus.confirmed,
    BookingStatus.rescheduled,
  };

  List<UnifiedBooking> _filtered(List<UnifiedBooking> all) {
    switch (filter) {
      case _BookingFilter.active:
        return all
            .where((b) => b.isActive && !_upcomingStatuses.contains(b.status))
            .toList();
      case _BookingFilter.upcoming:
        return all.where((b) => _upcomingStatuses.contains(b.status)).toList();
      case _BookingFilter.completed:
        return all.where((b) => b.isCompleted).toList();
      case _BookingFilter.cancelled:
        return all.where((b) => b.isCancelled).toList();
    }
  }

  String get _emptyTitle {
    switch (filter) {
      case _BookingFilter.active:
        return 'No Active Services';
      case _BookingFilter.upcoming:
        return 'No Upcoming Bookings';
      case _BookingFilter.completed:
        return 'No Completed Services';
      case _BookingFilter.cancelled:
        return 'No Cancelled Bookings';
    }
  }

  String get _emptyMessage {
    switch (filter) {
      case _BookingFilter.active:
        return 'Services currently in progress will appear here.';
      case _BookingFilter.upcoming:
        return 'Schedule a service to see upcoming bookings.';
      case _BookingFilter.completed:
        return 'Your completed services will show up here.';
      case _BookingFilter.cancelled:
        return 'You have no cancelled bookings.';
    }
  }

  IconData get _emptyIcon {
    switch (filter) {
      case _BookingFilter.active:
        return Icons.local_hospital_rounded;
      case _BookingFilter.upcoming:
        return Icons.calendar_today_rounded;
      case _BookingFilter.completed:
        return Icons.check_circle_outline_rounded;
      case _BookingFilter.cancelled:
        return Icons.cancel_outlined;
    }
  }

  bool get _showBrowseAction =>
      filter == _BookingFilter.active || filter == _BookingFilter.upcoming;

  void _browseServices(BuildContext context, WidgetRef ref) {
    ref.read(bottomNavIndexProvider.notifier).state = 0;
    // When this screen was pushed on top of the Home shell (e.g. from the
    // Profile menu's "My Services" tracker), switching the tab index alone
    // is invisible — it changes the IndexedStack underneath this route.
    // Pop back to the shell so the Home tab is actually shown.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allBookingsProvider);
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => ref.invalidate(allBookingsProvider),
      child: async.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 4,
          itemBuilder: (_, __) => const _LoadingShimmer(),
        ),
        error: (e, _) =>
            _ErrorState(onRetry: () => ref.invalidate(allBookingsProvider)),
        data: (all) {
          final items = _filtered(all);
          if (items.isEmpty) {
            return LayoutBuilder(
              builder: (context, constraints) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: AppEmptyState(
                        icon: _emptyIcon,
                        title: _emptyTitle,
                        message: _emptyMessage,
                        actionLabel: _showBrowseAction
                            ? 'Browse Services'
                            : null,
                        onAction: _showBrowseAction
                            ? () => _browseServices(context, ref)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: items.length,
            itemBuilder: (_, i) => _BookingCard(booking: items[i]),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Booking Card
// ─────────────────────────────────────────────────────────────────────────────

class _BookingCard extends StatelessWidget {
  final UnifiedBooking booking;
  const _BookingCard({required this.booking});

  IconData _iconForService(String? type) {
    switch (type?.toLowerCase()) {
      case 'nursing':
        return Icons.medical_services_rounded;
      case 'doctor':
        return Icons.medical_services_rounded;
      case 'lab':
      case 'diagnostic':
        return Icons.biotech_rounded;
      case 'pharmacy':
        return Icons.local_pharmacy_rounded;
      case 'physiotherapy':
        return Icons.sports_gymnastics_rounded;
      default:
        return Icons.healing_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusInfo = _resolveStatusInfo(booking.status);

    return GestureDetector(
      onTap: () => context.push(AppRoutes.serviceDetail, extra: booking),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            // Note: a single-sided Border (bottom only) combined with
            // borderRadius throws "A borderRadius can only be given on
            // borders with uniform colors" — BorderSide.none on the other
            // three sides makes the border non-uniform. Draw the divider as
            // a separate 1px Container instead of via `border:`.
            Container(
              decoration: BoxDecoration(
                color: statusInfo.color.withValues(alpha: 0.04),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _iconForService(booking.serviceType),
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                booking.serviceName,
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: context.appTextPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                booking.providerName ?? booking.serviceType,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: context.appTextSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        _StatusChip(info: statusInfo),
                      ],
                    ),
                  ),
                  Container(height: 1, color: context.appBorder),
                ],
              ),
            ),

            // Details + actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      _InfoCell(
                        icon: Icons.calendar_today_outlined,
                        label: 'Date',
                        value: booking.date.isNotEmpty
                            ? booking.date
                            : 'Not scheduled',
                      ),
                      const SizedBox(width: 12),
                      _InfoCell(
                        icon: Icons.access_time_rounded,
                        label: 'Time',
                        value: booking.time.isNotEmpty ? booking.time : '—',
                      ),
                      const SizedBox(width: 12),
                      _InfoCell(
                        icon: Icons.currency_rupee_rounded,
                        label: 'Amount',
                        value: '₹${(booking.amount ?? 0).toStringAsFixed(0)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CardActions(booking: booking),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Info cell
// ─────────────────────────────────────────────────────────────────────────────

class _InfoCell extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoCell({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: context.appTextHint),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: context.appTextHint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.appTextPrimary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Card actions
// ─────────────────────────────────────────────────────────────────────────────

class _CardActions extends StatelessWidget {
  final UnifiedBooking booking;
  const _CardActions({required this.booking});

  @override
  Widget build(BuildContext context) {
    final status = booking.status;
    final canTrack = const {
      BookingStatus.assigned,
      BookingStatus.onTheWay,
      BookingStatus.inProgress,
      BookingStatus.consultationStarted,
    }.contains(status);
    final canRate =
        status == BookingStatus.completed &&
        !(booking.rawData['isRated'] as bool? ?? false);
    final canCancel = const {
      BookingStatus.pending,
      BookingStatus.requested,
      BookingStatus.confirmed,
    }.contains(status);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () =>
                context.push(AppRoutes.serviceDetail, extra: booking),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'View Details',
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (canTrack) ...[
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => context.push(
                AppRoutes.orderTracking,
                extra: {
                  'orderId': booking.id,
                  'serviceType': booking.serviceType,
                  'serviceName': booking.serviceName,
                },
              ),
              icon: const Icon(Icons.location_on_rounded, size: 15),
              label: const Text(
                'Track',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        if (canRate) ...[
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => context.push(
                AppRoutes.submitReview,
                extra: {
                  'appointmentId': booking.id,
                  'doctorId': booking.rawData['doctorId'] as String? ?? '',
                  'doctorName': booking.providerName ?? '',
                  'doctorSpecialty': booking.providerSpecialty ?? '',
                  'consultationType':
                      booking.source == BookingSource.consultation
                      ? 'Video'
                      : 'In-person',
                },
              ),
              icon: const Icon(Icons.star_rounded, size: 15),
              label: const Text(
                'Rate',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        if (canCancel) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _showCancelDialog(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              // Theme's default OutlinedButtonThemeData forces
              // minimumSize: Size(double.infinity, 52) for full-width
              // buttons; this one is icon-only and sits as a bare (non-
              // Expanded) Row child, so it must override that back to a
              // finite size or layout throws "BoxConstraints forces an
              // infinite width."
              minimumSize: const Size(44, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ],
    );
  }

  Future<void> _showCancelDialog(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cancel Booking',
          style: AppTextStyles.h4.copyWith(color: context.appTextPrimary),
        ),
        content: Text(
          'Are you sure you want to cancel this service?\n'
          'Cancellation charges may apply.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: context.appTextSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Keep Booking',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: context.appTextSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Yes, Cancel',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    FeedbackService.showLoading(context, 'Cancelling booking...');
    try {
      await MyServicesService.updateStatus(booking, 'cancelled');
      if (context.mounted) {
        FeedbackService.dismiss(context);
        FeedbackService.showSuccess(context, 'Booking cancelled successfully');
      }
    } catch (e) {
      if (context.mounted) {
        FeedbackService.showError(
          context,
          'Failed to cancel booking. Please try again.',
          onRetry: () => _showCancelDialog(context),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Status chip
// ─────────────────────────────────────────────────────────────────────────────

class _StatusMeta {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusMeta(this.label, this.color, this.icon);
}

_StatusMeta _resolveStatusInfo(BookingStatus status) {
  switch (status) {
    case BookingStatus.pending:
    case BookingStatus.requested:
      return _StatusMeta(
        status.label,
        AppColors.warning,
        Icons.schedule_rounded,
      );
    case BookingStatus.confirmed:
    case BookingStatus.rescheduled:
    case BookingStatus.verified:
      return _StatusMeta(status.label, AppColors.primary, Icons.check_rounded);
    case BookingStatus.assigned:
    case BookingStatus.packed:
      return _StatusMeta(
        status.label,
        Colors.blue.shade700,
        Icons.person_pin_rounded,
      );
    case BookingStatus.onTheWay:
    case BookingStatus.inProgress:
    case BookingStatus.consultationStarted:
    case BookingStatus.outForDelivery:
      return _StatusMeta(
        status.label,
        AppColors.accent,
        Icons.play_circle_rounded,
      );
    case BookingStatus.sampleCollected:
    case BookingStatus.delivered:
    case BookingStatus.completed:
      return _StatusMeta(
        status.label,
        AppColors.success,
        Icons.check_circle_rounded,
      );
    case BookingStatus.cancelled:
      return _StatusMeta(status.label, AppColors.error, Icons.cancel_rounded);
  }
}

class _StatusChip extends StatelessWidget {
  final _StatusMeta info;
  const _StatusChip({required this.info});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: info.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(info.icon, size: 11, color: info.color),
          const SizedBox(width: 4),
          Text(
            info.label,
            style: AppTextStyles.labelSmall.copyWith(color: info.color),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Loading / Error states
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingShimmer extends StatelessWidget {
  const _LoadingShimmer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppShimmer(
        child: Container(
          height: 155,
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 56,
              color: AppColors.error.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: AppTextStyles.h4.copyWith(color: context.appTextSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Could not load your bookings.\nCheck your connection and try again.',
              style: AppTextStyles.bodySmall.copyWith(
                color: context.appTextHint,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'Retry',
                style: TextStyle(fontFamily: 'Poppins'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
