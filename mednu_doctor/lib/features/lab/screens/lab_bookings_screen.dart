import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/diagnostic_booking.dart';
import '../providers/lab_providers.dart';

/// Two tabs: the shared, realtime "Available" queue every lab partner sees
/// (unclaimed bookings), and this lab's own "My Bookings" — paginated, with
/// a lightweight status filter.
class LabBookingsScreen extends ConsumerStatefulWidget {
  const LabBookingsScreen({super.key});

  @override
  ConsumerState<LabBookingsScreen> createState() => _LabBookingsScreenState();
}

class _LabBookingsScreenState extends ConsumerState<LabBookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SharedAppShell(
      currentRoute: AppRoutes.labBookings,
      title: 'Bookings',
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Available'),
                Tab(text: 'My Bookings'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                const _AvailableTab(),
                _MyBookingsTab(
                  statusFilter: _statusFilter,
                  onFilterChanged: (v) => setState(() => _statusFilter = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableTab extends ConsumerWidget {
  const _AvailableTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(availableBookingsProvider);
    return available.when(
      loading: () => const ListLoadingState(hasAvatar: false),
      error: (_, __) => const NetworkErrorState(),
      data: (bookings) {
        if (bookings.isEmpty) {
          return const AppEmptyState(
            icon: Icons.inbox_outlined,
            title: 'No available requests',
            message: 'New diagnostic bookings will appear here in realtime.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (context, i) => _BookingTile(booking: bookings[i]),
        );
      },
    );
  }
}

class _MyBookingsTab extends ConsumerWidget {
  final String? statusFilter;
  final ValueChanged<String?> onFilterChanged;

  const _MyBookingsTab({required this.statusFilter, required this.onFilterChanged});

  static const _filters = <String?, String>{
    null: 'All',
    'accepted': 'Active',
    'completed': 'Completed',
    'rejected': 'Rejected',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myBookingsControllerProvider(statusFilter));
    final controller = ref.read(myBookingsControllerProvider(statusFilter).notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _filters.entries.map((entry) {
                final selected = entry.key == statusFilter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: selected,
                    onSelected: (_) => onFilterChanged(entry.key),
                    selectedColor: AppColors.primary.withValues(alpha: 0.14),
                    labelStyle: AppTextStyles.labelMedium.copyWith(
                      color: selected ? AppColors.primary : AppColors.textSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: state.items.isEmpty && !state.isLoadingMore
              ? const AppEmptyState(
                  icon: Icons.event_note_outlined,
                  title: 'No bookings yet',
                  message: 'Bookings you accept will show up here.',
                )
              : NotificationListener<ScrollEndNotification>(
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 200) controller.loadMore();
                    return false;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.items.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= state.items.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
                        );
                      }
                      return _BookingTile(booking: state.items[i]);
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _BookingTile extends ConsumerWidget {
  final DiagnosticBooking booking;
  const _BookingTile({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(AppRoutes.labBookingDetail, extra: {'bookingId': booking.id}),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.biotech_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.testName, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(
                  '${booking.patientName} • ${booking.preferredDate}',
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge(label: booking.status.label, color: booking.status.color),
        ],
      ),
    );
  }
}
