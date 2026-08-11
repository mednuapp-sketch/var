import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/ambulance_request.dart';
import '../providers/ambulance_providers.dart';
import '../widgets/status_pulse.dart';

/// Ambulance home — a hero online/offline toggle (mirrors the Doctor
/// dashboard's own online card, since dispatch availability is the same
/// core concept), a live stats grid, and a preview of incoming requests.
/// All data comes from the mock providers — no Firestore yet.
class AmbulanceDashboardScreen extends ConsumerWidget {
  const AmbulanceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(ambulanceOnlineProvider);
    final metrics = ref.watch(ambulanceDashboardMetricsProvider);
    final pending = ref.watch(pendingRequestsProvider);
    final active = ref.watch(activeRequestProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.ambulanceDashboard,
      title: 'Dispatch Dashboard',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _OnlineHeroCard(online: online),
          const SizedBox(height: 20),
          if (active != null) ...[
            _ActiveTripBanner(request: active),
            const SizedBox(height: 20),
          ],
          staticGrid(
            crossAxisCount: R.isTablet(context) ? 4 : 2,
            children: [
              GradientStatCard(
                value: '${metrics.todayTrips}',
                label: "Today's Trips",
                icon: Icons.route_rounded,
                colors: const [Color(0xFF1565C0), Color(0xFF0D47A1)],
              ),
              GradientStatCard(
                value: '₹${metrics.todayEarnings}',
                label: "Today's Earnings",
                icon: Icons.account_balance_wallet_rounded,
                colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
              ),
              GradientStatCard(
                value: '${metrics.pendingCount}',
                label: 'Pending Requests',
                icon: Icons.notifications_active_rounded,
                colors: const [Color(0xFFEF6C00), Color(0xFFE65100)],
              ),
              GradientStatCard(
                value: metrics.rating.toStringAsFixed(1),
                label: 'Driver Rating',
                icon: Icons.star_rounded,
                colors: const [Color(0xFF6A1B9A), Color(0xFF4A148C)],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Incoming Requests',
            action: pending.isNotEmpty ? 'View all' : null,
            onAction: pending.isNotEmpty ? () => context.push(AppRoutes.ambulanceIncomingRequests) : null,
          ),
          if (pending.isEmpty)
            const AppEmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'All caught up',
              message: 'New emergency requests will appear here in realtime.',
            )
          else
            Column(
              children: pending.take(2).map((r) => _RequestPreviewCard(request: r)).toList(),
            ),
        ],
      ),
    );
  }
}

class _OnlineHeroCard extends ConsumerWidget {
  final bool online;
  const _OnlineHeroCard({required this.online});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.all(R.p(context, 20)),
      decoration: BoxDecoration(
        gradient: online
            ? const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF43A047)], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : const LinearGradient(colors: [Color(0xFF455A64), Color(0xFF607D8B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (online ? AppColors.online : AppColors.offline).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          StatusPulse(color: Colors.white, size: online ? 12 : 8),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  online ? 'You are ON DUTY' : 'You are OFF DUTY',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 18), fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  online ? 'Visible to dispatch • Accepting emergencies' : 'Not receiving new requests',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 12), color: Colors.white70),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: online,
            onChanged: (v) => ref.read(ambulanceOnlineProvider.notifier).state = v,
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white38,
          ),
        ],
      ),
    );
  }
}

class _ActiveTripBanner extends StatelessWidget {
  final AmbulanceRequest request;
  const _ActiveTripBanner({required this.request});

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: () => context.push(AppRoutes.ambulanceLiveTracking, extra: {'requestId': request.id}),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: request.status.color.withValues(alpha: 0.35), width: 1.5),
          boxShadow: [BoxShadow(color: request.status.color.withValues(alpha: 0.15), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
              child: const Icon(Icons.local_shipping_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Trip in progress', style: AppTextStyles.labelLarge),
                  Text(request.patientName, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            StatusBadge(label: request.status.label, color: request.status.color),
          ],
        ),
      ),
    );
  }
}

class _RequestPreviewCard extends StatelessWidget {
  final AmbulanceRequest request;
  const _RequestPreviewCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(AppRoutes.ambulanceRequestDetail, extra: {'requestId': request.id}),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: request.type.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(request.type.icon, color: request.type.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.type.label, style: AppTextStyles.labelLarge),
                Text('${request.distanceKm} km away • ${request.patientName}', style: AppTextStyles.bodySmall, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
        ],
      ),
    );
  }
}
