import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/ambulance_request.dart';
import '../providers/ambulance_providers.dart';
import '../widgets/ambulance_trip_map.dart';

/// The driver's live map for the trip in progress. The vehicle moves with
/// every GPS fix (see `AmbulanceTripTracker`), the route runs to the patient
/// until the driver has arrived and to the drop-off after that, and the same
/// position is being streamed to the patient's phone at the same time.
class AmbulanceLiveTrackingScreen extends ConsumerWidget {
  const AmbulanceLiveTrackingScreen({super.key});

  /// Roughly the height of [_TrackingSheet], so the map's own controls and
  /// logo sit above it rather than underneath.
  static const _sheetClearance = 210.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeRequestProvider);

    if (active == null) {
      return const SharedAppShell(
        currentRoute: AppRoutes.ambulanceLiveTracking,
        title: 'Live Tracking',
        body: AppEmptyState(
          icon: Icons.map_outlined,
          title: 'No active trip',
          message: 'Accept a request to start live tracking.',
        ),
      );
    }

    return SharedAppShell(
      currentRoute: AppRoutes.ambulanceLiveTracking,
      title: 'Live Tracking',
      body: Stack(
        children: [
          Positioned.fill(child: AmbulanceTripMap(request: active, bottomPadding: _sheetClearance)),
          Positioned(left: 0, right: 0, bottom: 0, child: _TrackingSheet(request: active)),
        ],
      ),
    );
  }
}

class _TrackingSheet extends StatelessWidget {
  final AmbulanceRequest request;
  const _TrackingSheet({required this.request});

  String get _phaseText {
    switch (request.status) {
      case AmbulanceRequestStatus.accepted:
        return 'Accepted — start navigation when you leave.';
      case AmbulanceRequestStatus.enRoute:
        return 'Heading to the patient. Sharing your live location.';
      case AmbulanceRequestStatus.arrived:
        return request.dropAddress.trim().isEmpty
            ? 'At the patient. No drop-off address was given.'
            : 'Patient on board — take them to ${request.dropAddress}.';
      case AmbulanceRequestStatus.pending:
      case AmbulanceRequestStatus.completed:
      case AmbulanceRequestStatus.cancelled:
        return '';
    }
  }

  Future<void> _navigate(BuildContext context) async {
    final dest = TripDestination.of(request);
    if (dest == null) {
      FeedbackService.showError(context, 'No destination to navigate to yet.');
      return;
    }
    if (!await dest.openNavigation() && context.mounted) {
      FeedbackService.showError(context, 'Could not open Google Maps.');
    }
  }

  Future<void> _callPatient(BuildContext context) async {
    if (request.patientPhone.isEmpty) return;
    if (!await launchUrl(Uri.parse('tel:${request.patientPhone}')) && context.mounted) {
      FeedbackService.showError(context, 'Could not open the dialer.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 20, offset: Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Row(
              children: [
                SharedProfileAvatar(name: request.patientName, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.patientName, style: AppTextStyles.labelLarge),
                      Text(
                        request.status == AmbulanceRequestStatus.arrived ? request.dropAddress : request.pickupAddress,
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                StatusBadge(label: request.status.label, color: request.status.color),
              ],
            ),
            if (_phaseText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_phaseText, style: AppTextStyles.bodySmall),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GradientButton(
                    label: 'Navigate',
                    icon: Icons.navigation_rounded,
                    onTap: () => _navigate(context),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Call patient',
                  onPressed: request.patientPhone.isEmpty ? null : () => _callPatient(context),
                  icon: const Icon(Icons.call_rounded),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Trip details',
                  onPressed: () => context.push(AppRoutes.ambulanceRequestDetail, extra: {'requestId': request.id}),
                  icon: const Icon(Icons.assignment_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
