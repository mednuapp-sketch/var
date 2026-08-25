import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../providers/ambulance_providers.dart';
import '../widgets/mock_map_background.dart';

/// Turn-by-turn navigation — deliberately its own full-screen experience
/// (not wrapped in `SharedAppShell`) since a driver mid-emergency-run
/// needs the whole screen for the map + next-turn instruction, exactly
/// like the Doctor module's video call screen opts out of the standard
/// chrome for the same reason. Reached only by pushing from Request Detail
/// / Live Tracking, never a bottom-nav destination.
class AmbulanceNavigationScreen extends ConsumerWidget {
  final String requestId;
  const AmbulanceNavigationScreen({super.key, required this.requestId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(requestByIdProvider(requestId));

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: request == null
            ? const Center(
                child: AppEmptyState(
                  icon: Icons.navigation_outlined,
                  title: 'Nothing to navigate to',
                  message: 'This request may have already been completed.',
                  iconColor: Colors.white70,
                ),
              )
            : Column(
                children: [
                  _NextTurnBanner(dropAddress: request.dropAddress),
                  Expanded(
                    child: Stack(
                      children: [
                        const Positioned.fill(child: MockMapBackground(tint: Color(0xFF1B2A3A))),
                        Center(
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.6), blurRadius: 16)],
                            ),
                            child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 26),
                          ),
                        ),
                        Positioned(
                          top: 16,
                          right: 16,
                          child: IconButton.filled(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close_rounded),
                            style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.4)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _BottomEtaBar(etaMinutes: request.etaMinutes, distanceKm: request.distanceKm),
                ],
              ),
      ),
    );
  }
}

class _NextTurnBanner extends StatelessWidget {
  final String dropAddress;
  const _NextTurnBanner({required this.dropAddress});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.turn_slight_right_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('In 300 m, turn right', style: AppTextStyles.h3.copyWith(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                Text('Toward $dropAddress', style: AppTextStyles.bodySmall.copyWith(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomEtaBar extends StatelessWidget {
  final int etaMinutes;
  final double distanceKm;
  const _BottomEtaBar({required this.etaMinutes, required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: Color(0xFF13233A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$etaMinutes min', style: AppTextStyles.h3.copyWith(color: Colors.white)),
              Text('Estimated arrival', style: AppTextStyles.caption.copyWith(color: Colors.white60)),
            ],
          ),
          Container(width: 1, height: 34, color: Colors.white24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$distanceKm km', style: AppTextStyles.h3.copyWith(color: Colors.white)),
              Text('Remaining', style: AppTextStyles.caption.copyWith(color: Colors.white60)),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Voice guidance is coming soon.'),
                behavior: SnackBarBehavior.floating,
              ),
            ),
            icon: const Icon(Icons.mic_rounded, size: 18),
            label: const Text('Voice'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}
