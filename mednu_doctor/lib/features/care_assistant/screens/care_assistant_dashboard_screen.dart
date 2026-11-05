import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../caregiver/providers/caregiver_providers.dart';
import '../../caregiver/services/caregiver_profile_service.dart';
import '../../caregiver/widgets/duty_pulse.dart';
import '../providers/care_assistant_providers.dart';
import '../widgets/care_job_widgets.dart';

/// Care Assistant home — duty switch, live stats, and the incoming-request
/// inbox. Everything is driven by Firestore snapshot listeners, so a booking
/// made in the patient app shows up here (and an Accept shows up there)
/// without any refresh.
class CareAssistantDashboardScreen extends ConsumerWidget {
  const CareAssistantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onDuty = ref.watch(caregiverOnDutyProvider);
    final profile = ref.watch(caregiverProfileProvider);
    final metrics = ref.watch(careAssistantMetricsProvider);
    final incoming = ref.watch(incomingCareRequestsProvider);
    final active = ref.watch(activeCareJobsProvider);
    final approved = profile.status == 'active';

    return SharedAppShell(
      currentRoute: AppRoutes.careAssistantDashboard,
      title: 'Care Assistant',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _DutyCard(onDuty: onDuty, enabled: approved),
          const SizedBox(height: 20),
          staticGrid(
            crossAxisCount: R.isTablet(context) ? 4 : 2,
            children: [
              GradientStatCard(
                value: '${metrics.newRequests}',
                label: 'New Requests',
                icon: Icons.notifications_active_rounded,
                colors: const [careAssistantTeal, Color(0xFF00695C)],
              ),
              GradientStatCard(
                value: '${metrics.activeJobs}',
                label: 'Active Jobs',
                icon: Icons.directions_walk_rounded,
                colors: const [AppColors.primary, AppColors.secondary],
              ),
              GradientStatCard(
                value: '${metrics.completedToday}',
                label: 'Completed Today',
                icon: Icons.task_alt_rounded,
                colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
              ),
              GradientStatCard(
                value: '₹${metrics.todayEarnings}',
                label: "Today's Earnings",
                icon: Icons.account_balance_wallet_rounded,
                colors: const [AppColors.accent, AppColors.accentDark],
              ),
            ],
          ),
          const SizedBox(height: 24),
          SectionHeader(
            title: 'Incoming Requests',
            action: incoming.length > 2 ? 'View all' : null,
            onAction: () => context.go(AppRoutes.careAssistantRequests),
          ),
          if (!approved)
            const AppEmptyState(
              icon: Icons.hourglass_top_rounded,
              title: 'Awaiting approval',
              message: 'You will start receiving requests once our team approves your profile.',
            )
          else if (!onDuty && incoming.isEmpty)
            const AppEmptyState(
              icon: Icons.power_settings_new_rounded,
              title: 'You are off duty',
              message: 'Go on duty to receive new care assistant requests.',
            )
          else if (incoming.isEmpty)
            const AppEmptyState(
              icon: Icons.inbox_rounded,
              title: 'No new requests',
              message: 'New requests from patients appear here instantly.',
            )
          else
            ...incoming.take(3).map((v) => CareRequestCard(visit: v)),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionHeader(
              title: 'Active Jobs',
              action: 'View all',
              onAction: () => context.go(AppRoutes.careAssistantRequests),
            ),
            ...active.take(3).map((v) => CareJobTile(visit: v)),
          ],
        ],
      ),
    );
  }
}

class _DutyCard extends StatelessWidget {
  final bool onDuty;
  final bool enabled;
  const _DutyCard({required this.onDuty, required this.enabled});

  Future<void> _toggle(BuildContext context, bool value) async {
    final uid = CaregiverProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }
    try {
      await CaregiverProfileService.updateOnDuty(uid, value);
    } catch (_) {
      if (context.mounted) {
        FeedbackService.showError(context, "Couldn't update duty status. Please try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(R.p(context, 20)),
      decoration: BoxDecoration(
        gradient: onDuty
            ? const LinearGradient(
                colors: [careAssistantTeal, Color(0xFF26A69A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)
            : const LinearGradient(
                colors: [Color(0xFF455A64), Color(0xFF607D8B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(R.r(context, 24)),
        boxShadow: [
          BoxShadow(
            color: (onDuty ? careAssistantTeal : AppColors.offline).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          DutyPulse(color: Colors.white, size: onDuty ? 12 : 8),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  onDuty ? 'You are ON DUTY' : 'You are OFF DUTY',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: R.sp(context, 18),
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  onDuty ? 'Visible to patients and receiving requests' : 'Not receiving new requests',
                  style: TextStyle(fontFamily: 'Inter', fontSize: R.sp(context, 12), color: Colors.white70),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: onDuty,
            onChanged: enabled ? (v) => _toggle(context, v) : null,
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white38,
          ),
        ],
      ),
    );
  }
}
