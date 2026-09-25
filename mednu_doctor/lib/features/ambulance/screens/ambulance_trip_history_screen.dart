import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/ambulance_request.dart';
import '../models/trip.dart';
import '../providers/ambulance_providers.dart';

/// The ambulance partner's single job list: Active/Pending, Completed and
/// Cancelled in one real-time tabbed view (mirroring the Doctor's
/// Upcoming/Done/Cancelled appointments tab).
///
/// The class name and route (`AppRoutes.ambulanceTripHistory`) are kept as-is
/// so existing navigation keeps working; accept/decline stays on the
/// Incoming Requests screen (transaction-guarded `AmbulanceRequestService`
/// calls) and is untouched by this view.
///
/// Streams: Active <- `activeJobsProvider` (shared pool + own runs, live
/// statuses only), Completed <- `ambulanceTripsProvider` (`ambulance_trips`),
/// Cancelled <- `cancelledJobsProvider` (own requests with `cancelled`).
class AmbulanceTripHistoryScreen extends ConsumerWidget {
  const AmbulanceTripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCount = ref.watch(activeJobsProvider).valueOrNull?.length;
    final completedCount = ref.watch(ambulanceTripsProvider).valueOrNull?.length;
    final cancelledCount = ref.watch(cancelledJobsProvider).valueOrNull?.length;

    String label(String name, int? count) => count == null ? name : '$name ($count)';

    return SharedAppShell(
      currentRoute: AppRoutes.ambulanceTripHistory,
      title: 'Trip History',
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Container(
              color: Colors.white,
              child: Align(
                alignment: Alignment.centerLeft,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textHint,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500),
                  tabs: [
                    Tab(text: label('Active', activeCount)),
                    Tab(text: label('Completed', completedCount)),
                    Tab(text: label('Cancelled', cancelledCount)),
                  ],
                ),
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  _ActiveTab(),
                  _CompletedTab(),
                  _CancelledTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Active / Pending ─────────────────────────────────────────────────────

class _ActiveTab extends ConsumerWidget {
  const _ActiveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(activeJobsProvider);
    return jobs.when(
      loading: () => const _TabLoading(),
      error: (_, __) => NetworkErrorState(onRetry: () {
        ref.invalidate(availableAmbulanceRequestsProvider);
        ref.invalidate(myAmbulanceRequestsProvider);
      }),
      data: (items) => items.isEmpty
          ? const AppEmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'No active jobs',
              message: 'New and in-progress requests will appear here in real time.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: items.length,
              itemBuilder: (context, i) => _ActiveJobCard(request: items[i]),
            ),
    );
  }
}

class _ActiveJobCard extends StatelessWidget {
  final AmbulanceRequest request;
  const _ActiveJobCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final type = request.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PremiumCard(
        borderColor: type.color.withValues(alpha: 0.25),
        onTap: () => context.push(AppRoutes.ambulanceRequestDetail, extra: {'requestId': request.id}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: type.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(type.icon, color: type.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.label,
                        style: AppTextStyles.labelLarge.copyWith(color: type.color),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        request.patientName,
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: StatusBadge(label: request.status.label, color: request.status.color, dot: true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    request.pickupAddress.isEmpty ? 'Pickup location not provided' : request.pickupAddress,
                    style: AppTextStyles.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                InfoChip(icon: Icons.social_distance_rounded, label: '${request.distanceKm} km'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    DateFormat('d MMM, h:mm a').format(request.requestedAt),
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(CurrencyFormatter.format(request.fare), style: AppTextStyles.labelLarge.copyWith(color: AppColors.success)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Completed ────────────────────────────────────────────────────────────

/// Completed trips as a connected timeline (a vertical line threading each
/// entry) rather than plain stacked cards — a history list reads naturally
/// as a sequence in time.
class _CompletedTab extends ConsumerWidget {
  const _CompletedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(ambulanceTripsProvider);
    return trips.when(
      loading: () => const _TabLoading(),
      error: (_, __) => NetworkErrorState(onRetry: () => ref.invalidate(ambulanceTripsProvider)),
      data: (items) => items.isEmpty
          ? const AppEmptyState(
              icon: Icons.history_rounded,
              title: 'No trips yet',
              message: 'Completed trips will appear here.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: items.length,
              itemBuilder: (context, i) => _TripTimelineTile(trip: items[i], isLast: i == items.length - 1),
            ),
    );
  }
}

class _TripTimelineTile extends StatelessWidget {
  final Trip trip;
  final bool isLast;
  const _TripTimelineTile({required this.trip, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: trip.type.color,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: trip.type.color.withValues(alpha: 0.4), blurRadius: 5)],
                  ),
                ),
                if (!isLast) Expanded(child: Container(width: 2, color: AppColors.divider)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            trip.type.label,
                            style: AppTextStyles.labelLarge.copyWith(color: trip.type.color),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(DateFormat('d MMM, h:mm a').format(trip.completedAt), style: AppTextStyles.caption),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(trip.patientName, style: AppTextStyles.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Wrap, not a fixed Row: three InfoChips next to the
                        // fare could exceed the card's width on narrow
                        // phones — Wrap flows to a second line instead of
                        // overflowing, and keeps the fare fully visible
                        // rather than ellipsising money.
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              InfoChip(icon: Icons.social_distance_rounded, label: '${trip.distanceKm} km'),
                              InfoChip(icon: Icons.timer_outlined, label: '${trip.durationMinutes} min'),
                              InfoChip(icon: Icons.star_rounded, label: trip.rating.toStringAsFixed(1), color: AppColors.warning),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(CurrencyFormatter.format(trip.fare), style: AppTextStyles.labelLarge.copyWith(color: AppColors.success)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cancelled / declined ─────────────────────────────────────────────────

class _CancelledTab extends ConsumerWidget {
  const _CancelledTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(cancelledJobsProvider);
    return jobs.when(
      loading: () => const _TabLoading(),
      error: (_, __) => NetworkErrorState(onRetry: () => ref.invalidate(myAmbulanceRequestsProvider)),
      data: (items) => items.isEmpty
          ? const AppEmptyState(
              icon: Icons.cancel_outlined,
              title: 'No cancelled requests',
              message: 'Requests you decline or that get cancelled will be listed here.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: items.length,
              itemBuilder: (context, i) => _CancelledJobCard(request: items[i]),
            ),
    );
  }
}

class _CancelledJobCard extends StatelessWidget {
  final AmbulanceRequest request;
  const _CancelledJobCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final when = request.updatedAt ?? request.requestedAt;
    final reason = request.cancelReason;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PremiumCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.patientName,
                    style: AppTextStyles.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: StatusBadge(
                    label: request.status.label,
                    color: request.status.color,
                    icon: Icons.close_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(request.type.icon, size: 14, color: request.type.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    request.type.label,
                    style: AppTextStyles.bodySmall.copyWith(color: request.type.color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    DateFormat('d MMM, h:mm a').format(when),
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (request.pickupAddress.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      request.pickupAddress,
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (reason != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Reason: $reason',
                        style: AppTextStyles.bodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared loading placeholder for every tab — the standard skeleton list
/// inside a scroll view (the skeleton is a plain Column, see
/// `ListLoadingState`).
class _TabLoading extends StatelessWidget {
  const _TabLoading();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: ListLoadingState(itemCount: 4, hasAvatar: false),
      );
}
