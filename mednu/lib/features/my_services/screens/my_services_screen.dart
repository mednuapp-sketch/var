import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../models/unified_booking.dart';
import '../providers/my_services_provider.dart';
import '../../home/providers/home_nav_provider.dart';

class MyServicesScreen extends ConsumerStatefulWidget {
  const MyServicesScreen({super.key});

  @override
  ConsumerState<MyServicesScreen> createState() => _MyServicesScreenState();
}

class _MyServicesScreenState extends ConsumerState<MyServicesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  static const _tabs = ['All', 'Active', 'Completed', 'Cancelled'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, __) => [_buildAppBar(ctx, isDark)],
        body: TabBarView(
          controller: _tab,
          children: [
            _BookingsList(filter: _BookingFilter.all),
            _BookingsList(filter: _BookingFilter.active),
            _BookingsList(filter: _BookingFilter.completed),
            _BookingsList(filter: _BookingFilter.cancelled),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 160,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            ref.read(bottomNavIndexProvider.notifier).state = 0;
          }
        },
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'My Services',
                        style: AppTextStyles.h2.copyWith(color: Colors.white),
                      ),
                      const Spacer(),
                      _StatsChip(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Track and manage all your healthcare bookings',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: isDark ? AppColors.darkCard : Colors.white,
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2.5,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
      ),
    );
  }
}

// ── Stats Chip (shows active count) ──────────────────────────────────────────

class _StatsChip extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeBookingsProvider);
    final count = active.valueOrNull?.length ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha:0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white30),
      ),
      child: Text(
        '$count Active',
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ── Filter enum ───────────────────────────────────────────────────────────────

enum _BookingFilter { all, active, completed, cancelled }

// ── Bookings list ─────────────────────────────────────────────────────────────

class _BookingsList extends ConsumerWidget {
  final _BookingFilter filter;
  const _BookingsList({required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<UnifiedBooking>> async;
    switch (filter) {
      case _BookingFilter.all:
        async = ref.watch(allBookingsProvider);
        break;
      case _BookingFilter.active:
        async = ref.watch(activeBookingsProvider);
        break;
      case _BookingFilter.completed:
        async = ref.watch(completedBookingsProvider);
        break;
      case _BookingFilter.cancelled:
        async = ref.watch(cancelledBookingsProvider);
        break;
    }

    return async.when(
      loading: () => const _LoadingShimmer(),
      error: (e, _) => _ErrorState(error: e.toString()),
      data: (bookings) {
        if (bookings.isEmpty) return _EmptyState(filter: filter);
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(allBookingsProvider);
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: bookings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _BookingCard(booking: bookings[i]),
          ),
        );
      },
    );
  }
}

// ── Booking Card ──────────────────────────────────────────────────────────────

class _BookingCard extends StatelessWidget {
  final UnifiedBooking booking;
  const _BookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkCard : Colors.white;
    final info = _ServiceInfo.from(booking);

    final statusColor = _statusAccentColor(booking.status);

    return GestureDetector(
      onTap: () => context.push(
        AppRoutes.serviceDetail,
        extra: booking,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.divider,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Colored left accent border by status
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
          children: [
            // ── Card Header ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  // Service icon
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: info.gradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(info.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  // Service info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                booking.serviceType,
                                style: AppTextStyles.labelLarge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _StatusChip(status: booking.status),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          booking.providerName ?? booking.serviceName,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Divider ───────────────────────────────────────────
            Divider(
              height: 1,
              color: isDark ? AppColors.darkBorder : AppColors.divider,
            ),

            // ── Date / Time / ID row ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  _MetaItem(
                    icon: Icons.calendar_today_outlined,
                    text: _formatDate(booking.date),
                  ),
                  const SizedBox(width: 16),
                  if (booking.time.isNotEmpty) ...[
                    _MetaItem(
                      icon: Icons.access_time_rounded,
                      text: booking.time,
                    ),
                    const SizedBox(width: 16),
                  ],
                  const Spacer(),
                  Text(
                    '#${booking.id.substring(0, booking.id.length.clamp(0, 8)).toUpperCase()}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textHint,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),

            // ── Action Row (only for active bookings) ─────────────
            if (booking.isActive)
              _ActiveCardActions(booking: booking),
          ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _statusAccentColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
      case BookingStatus.requested:
        return const Color(0xFFE65100);
      case BookingStatus.confirmed:
        return const Color(0xFF1565C0);
      case BookingStatus.assigned:
        return const Color(0xFF6A1B9A);
      case BookingStatus.onTheWay:
        return const Color(0xFF2E7D32);
      case BookingStatus.inProgress:
      case BookingStatus.consultationStarted:
        return const Color(0xFF00838F);
      case BookingStatus.sampleCollected:
      case BookingStatus.delivered:
      case BookingStatus.completed:
        return AppColors.success;
      case BookingStatus.cancelled:
        return AppColors.error;
      case BookingStatus.rescheduled:
        return const Color(0xFFF57F17);
    }
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '—';
    try {
      final d = DateTime.parse(raw);
      return DateFormat('dd MMM yyyy').format(d);
    } catch (_) {
      return raw;
    }
  }
}

// ── Active card action strip ──────────────────────────────────────────────────

class _ActiveCardActions extends StatelessWidget {
  final UnifiedBooking booking;
  const _ActiveCardActions({required this.booking});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.primary.withValues(alpha:0.07)
            : AppColors.primary.withValues(alpha:0.04),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push(
                AppRoutes.serviceDetail,
                extra: booking,
              ),
              icon: const Icon(Icons.timeline_rounded, size: 14),
              label: const Text('Track'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withValues(alpha:0.4)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => context.push(
                AppRoutes.serviceDetail,
                extra: booking,
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 14),
              label: const Text('View Details'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 8),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status Chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final BookingStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  (Color, Color) _colors() {
    switch (status) {
      case BookingStatus.pending:
      case BookingStatus.requested:
        return (const Color(0xFFFFF3E0), const Color(0xFFE65100));
      case BookingStatus.confirmed:
        return (const Color(0xFFE3F2FD), const Color(0xFF1565C0));
      case BookingStatus.assigned:
        return (const Color(0xFFF3E5F5), const Color(0xFF6A1B9A));
      case BookingStatus.onTheWay:
        return (const Color(0xFFE8F5E9), const Color(0xFF2E7D32));
      case BookingStatus.inProgress:
      case BookingStatus.consultationStarted:
        return (const Color(0xFFE0F7FA), const Color(0xFF00838F));
      case BookingStatus.sampleCollected:
      case BookingStatus.delivered:
      case BookingStatus.completed:
        return (const Color(0xFFE8F5E9), AppColors.success);
      case BookingStatus.cancelled:
        return (const Color(0xFFFFEBEE), AppColors.error);
      case BookingStatus.rescheduled:
        return (const Color(0xFFFFF8E1), const Color(0xFFF57F17));
    }
  }
}

// ── Meta item (icon + label) ──────────────────────────────────────────────────

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textHint),
        const SizedBox(width: 4),
        Text(text,
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

// ── Service type info ─────────────────────────────────────────────────────────

class _ServiceInfo {
  final IconData icon;
  final LinearGradient gradient;

  const _ServiceInfo({required this.icon, required this.gradient});

  static _ServiceInfo from(UnifiedBooking b) {
    switch (b.source) {
      case BookingSource.appointment:
        return const _ServiceInfo(
            icon: Icons.medical_services_rounded,
            gradient: AppColors.appointmentGrad);
      case BookingSource.consultation:
        return const _ServiceInfo(
            icon: Icons.videocam_rounded, gradient: AppColors.consultGrad);
      case BookingSource.nutrition:
        return const _ServiceInfo(
            icon: Icons.restaurant_menu_rounded,
            gradient: AppColors.nutritionGrad);
      case BookingSource.serviceRequest:
        return _fromServiceType(b.rawData['type'] as String? ?? '');
    }
  }

  static _ServiceInfo _fromServiceType(String type) {
    switch (type.toLowerCase()) {
      case 'ambulance':
        return const _ServiceInfo(
            icon: Icons.emergency_rounded,
            gradient: AppColors.ambulanceGrad);
      case 'diagnostics':
      case 'diagnostic':
      case 'lab_test':
        return const _ServiceInfo(
            icon: Icons.biotech_rounded,
            gradient: AppColors.diagnosticGrad);
      case 'caregiver':
      case 'caregivers':
        return const _ServiceInfo(
            icon: Icons.elderly_rounded,
            gradient: AppColors.caregiverGrad);
      case 'care_assistant':
        return const _ServiceInfo(
            icon: Icons.support_agent_rounded,
            gradient: AppColors.careAssistGrad);
      case 'physiotherapy':
      case 'physio':
        return const _ServiceInfo(
            icon: Icons.accessibility_new_rounded,
            gradient: AppColors.physioGrad);
      case 'counselling':
      case 'counseling':
        return const _ServiceInfo(
            icon: Icons.psychology_rounded,
            gradient: AppColors.counselGrad);
      case 'equipment':
      case 'equipment_hiring':
        return const _ServiceInfo(
            icon: Icons.medical_information_rounded,
            gradient: AppColors.equipmentGrad);
      case 'medicine':
      case 'medicine_delivery':
        return const _ServiceInfo(
            icon: Icons.local_pharmacy_rounded,
            gradient: AppColors.medicineGrad);
      default:
        return const _ServiceInfo(
            icon: Icons.health_and_safety_rounded,
            gradient: AppColors.primaryGradient);
    }
  }
}

// ── Empty States ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final _BookingFilter filter;
  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final (icon, title, sub) = _content();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha:0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 42),
            ),
            const SizedBox(height: 24),
            Text(title,
                style: AppTextStyles.h4,
                textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(sub,
                style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary, height: 1.6),
                textAlign: TextAlign.center),
            if (filter == _BookingFilter.all) ...[
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: () => context.push(AppRoutes.home),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Book a Service'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (IconData, String, String) _content() {
    switch (filter) {
      case _BookingFilter.all:
        return (
          Icons.calendar_month_rounded,
          'No Bookings Yet',
          'Your healthcare bookings will appear here. Start by booking a doctor appointment or a service.',
        );
      case _BookingFilter.active:
        return (
          Icons.hourglass_empty_rounded,
          'No Active Bookings',
          'You have no ongoing services at the moment. Book one from our wide range of healthcare services.',
        );
      case _BookingFilter.completed:
        return (
          Icons.check_circle_outline_rounded,
          'No Completed Services',
          'Your completed appointments and services will show up here once you\'ve used them.',
        );
      case _BookingFilter.cancelled:
        return (
          Icons.cancel_outlined,
          'No Cancelled Bookings',
          'You haven\'t cancelled any services. That\'s great — keep your appointments!',
        );
    }
  }
}

// ── Error State ───────────────────────────────────────────────────────────────

class _ErrorState extends ConsumerWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.wifi_off_rounded, color: AppColors.error, size: 36),
            ),
            const SizedBox(height: 20),
            Text('Could not load bookings', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => ref.invalidate(allBookingsProvider),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Retry',
                  style: TextStyle(fontFamily: 'Poppins')),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading Shimmer ───────────────────────────────────────────────────────────

class _LoadingShimmer extends StatefulWidget {
  const _LoadingShimmer();

  @override
  State<_LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<_LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => _ShimmerCard(opacity: _anim.value),
      ),
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  final double opacity;
  const _ShimmerCard({required this.opacity});

  @override
  Widget build(BuildContext context) {
    final base = Colors.grey.withValues(alpha:opacity);
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(14))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(height: 14, width: 140, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 8),
                Container(height: 11, width: 100, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 8),
                Container(height: 10, width: 80, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(6))),
              ],
            ),
          ),
          Container(height: 24, width: 70, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(20))),
        ],
      ),
    );
  }
}
