import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/ambulance_request.dart';
import '../providers/ambulance_providers.dart';
import '../widgets/mock_map_background.dart';
import '../widgets/status_pulse.dart';

/// Full-bleed "map" (see `MockMapBackground` for why it's painted, not a
/// real SDK) with a floating driver/ETA card anchored to the bottom — the
/// live-tracking view for whichever request is currently accepted/en
/// route/arrived. Distinct, immersive layout on purpose: this is the one
/// screen in the module that should NOT look like a list of cards.
class AmbulanceLiveTrackingScreen extends ConsumerWidget {
  const AmbulanceLiveTrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeRequestProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.ambulanceLiveTracking,
      title: 'Live Tracking',
      body: active == null
          ? const AppEmptyState(
              icon: Icons.map_outlined,
              title: 'No active trip',
              message: 'Accept a request to start live tracking.',
            )
          : Stack(
              children: [
                const Positioned.fill(child: MockMapBackground()),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusPulse(color: active.type.color, size: 16),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                        ]),
                        child: const Text('Your location', style: AppTextStyles.caption),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      const _FloatingChip(icon: Icons.speed_rounded, label: '38 km/h'),
                      const SizedBox(width: 8),
                      _FloatingChip(icon: Icons.timer_outlined, label: '${active.etaMinutes} min ETA'),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _TrackingSheet(requestId: active.id),
                ),
              ],
            ),
    );
  }
}

class _FloatingChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FloatingChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.labelMedium),
        ],
      ),
    );
  }
}

class _TrackingSheet extends ConsumerWidget {
  final String requestId;
  const _TrackingSheet({required this.requestId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(requestByIdProvider(requestId));
    if (request == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 20, offset: Offset(0, -6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
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
                    Text(request.dropAddress, style: AppTextStyles.bodySmall, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              StatusBadge(label: request.status.label, color: request.status.color),
            ],
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: 'Open Turn-by-Turn Navigation',
            icon: Icons.navigation_rounded,
            onTap: () => context.push(AppRoutes.ambulanceNavigation, extra: {'requestId': request.id}),
          ),
        ],
      ),
    );
  }
}
