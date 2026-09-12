import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/ambulance_request.dart';
import '../models/trip.dart';
import '../providers/ambulance_providers.dart';

/// Completed trips as a connected timeline (a vertical line threading each
/// entry) rather than plain stacked cards — a deliberate departure from
/// the card-grid pattern used elsewhere in this module, since a history
/// list reads naturally as a sequence in time.
class AmbulanceTripHistoryScreen extends ConsumerWidget {
  const AmbulanceTripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripHistoryProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.ambulanceTripHistory,
      title: 'Trip History',
      body: trips.isEmpty
          ? const AppEmptyState(
              icon: Icons.history_rounded,
              title: 'No trips yet',
              message: 'Completed trips will appear here.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: trips.length,
              itemBuilder: (context, i) => _TripTimelineTile(trip: trips[i], isLast: i == trips.length - 1),
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
                        Expanded(child: Text(trip.type.label, style: AppTextStyles.labelLarge.copyWith(color: trip.type.color))),
                        Text(DateFormat('d MMM, h:mm a').format(trip.completedAt), style: AppTextStyles.caption),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(trip.patientName, style: AppTextStyles.bodyMedium),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Wrap, not a fixed Row: three InfoChips next to an
                        // unwrapped fare Text with no Flexible anywhere
                        // could exceed the card's width on narrow phones —
                        // Wrap flows to a second line instead of throwing a
                        // RenderFlex overflow, and keeps the fare amount
                        // fully visible rather than risking an ellipsis
                        // truncating money.
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
