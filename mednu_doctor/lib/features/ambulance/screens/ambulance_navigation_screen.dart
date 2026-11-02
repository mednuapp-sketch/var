import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/ambulance_request.dart';
import '../providers/ambulance_providers.dart';
import '../widgets/ambulance_trip_map.dart';

/// Full-screen drive view — deliberately its own immersive screen (not wrapped
/// in `SharedAppShell`), since a driver mid-run needs the whole screen for the
/// map. Shows the real route and live position for the current leg of the
/// trip; for spoken turn-by-turn it hands off to Google Maps, which is the
/// navigation app drivers already trust (this app does not ship its own
/// navigation engine). Reached only by pushing from Request Detail.
class AmbulanceNavigationScreen extends ConsumerWidget {
  final String requestId;
  const AmbulanceNavigationScreen({super.key, required this.requestId});

  static const _barClearance = 130.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(requestByIdProvider(requestId));
    final live = request != null &&
        (request.status == AmbulanceRequestStatus.accepted ||
            request.status == AmbulanceRequestStatus.enRoute ||
            request.status == AmbulanceRequestStatus.arrived);

    return Scaffold(
      backgroundColor: Colors.white,
      body: !live
          ? SafeArea(
              child: Stack(
                children: [
                  const Center(
                    child: AppEmptyState(
                      icon: Icons.navigation_outlined,
                      title: 'Nothing to navigate to',
                      message: 'This trip has ended or is no longer active.',
                    ),
                  ),
                  Positioned(top: 8, left: 8, child: BackButton(onPressed: () => Navigator.of(context).maybePop())),
                ],
              ),
            )
          : Stack(
              children: [
                Positioned.fill(child: AmbulanceTripMap(request: request, bottomPadding: _barClearance)),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 56, right: 12),
                      child: IconButton.filled(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                ),
                Positioned(left: 0, right: 0, bottom: 0, child: _BottomBar(request: request)),
              ],
            ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final AmbulanceRequest request;
  const _BottomBar({required this.request});

  @override
  Widget build(BuildContext context) {
    final dest = TripDestination.of(request);
    final headingTo = request.status == AmbulanceRequestStatus.arrived
        ? (request.dropAddress.isEmpty ? 'Drop-off' : request.dropAddress)
        : (request.pickupAddress.isEmpty ? request.patientName : request.pickupAddress);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF13233A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(dest?.label ?? 'Destination',
                      style: AppTextStyles.caption.copyWith(color: Colors.white60)),
                  const SizedBox(height: 2),
                  Text(headingTo,
                      style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: dest == null
                  ? null
                  : () async {
                      if (!await dest.openNavigation() && context.mounted) {
                        FeedbackService.showError(context, 'Could not open Google Maps.');
                      }
                    },
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('Google Maps'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 46),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
