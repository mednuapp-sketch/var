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

/// The operational queue: bookings this lab has accepted but that still
/// need a technician assigned, or that already have one on the way. Tapping
/// through to the booking detail screen is where the actual "assign
/// technician" / "mark sample collected" actions live — this screen is the
/// dispatch-style overview the nav spec calls "Sample Collection".
class LabSampleCollectionScreen extends ConsumerWidget {
  const LabSampleCollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(sampleCollectionQueueProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.labSampleCollection,
      title: 'Sample Collection',
      body: queue.when(
        loading: () => const ListLoadingState(hasAvatar: false),
        error: (_, __) => const NetworkErrorState(),
        data: (bookings) {
          if (bookings.isEmpty) {
            return const AppEmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'Nothing to collect',
              message: 'Accepted bookings awaiting a technician will show up here.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            itemBuilder: (context, i) => _CollectionTile(booking: bookings[i]),
          );
        },
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  final DiagnosticBooking booking;
  const _CollectionTile({required this.booking});

  @override
  Widget build(BuildContext context) {
    final needsTechnician = booking.status == DiagnosticBookingStatus.accepted;
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(AppRoutes.labBookingDetail, extra: {'bookingId': booking.id}),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (needsTechnician ? AppColors.warning : AppColors.secondary).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              needsTechnician ? Icons.person_add_alt_rounded : Icons.local_shipping_rounded,
              color: needsTechnician ? AppColors.warning : AppColors.secondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.testName, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(
                  needsTechnician
                      ? '${booking.patientName} • Needs a technician'
                      : '${booking.patientName} • ${booking.technicianName ?? 'Technician assigned'}',
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          StatusBadge(label: booking.status.label, color: booking.status.color),
        ],
      ),
    );
  }
}
