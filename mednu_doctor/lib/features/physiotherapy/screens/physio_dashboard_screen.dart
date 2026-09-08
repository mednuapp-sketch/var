import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/physio_presence_service.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../ambulance/widgets/status_pulse.dart';
import '../models/physio_session.dart';
import '../providers/physio_providers.dart';
import '../services/physio_profile_service.dart';

/// Physiotherapist home — an online/offline presence toggle (mirrors the
/// Doctor/Ambulance dashboards' own online card — same underlying concept:
/// patients can only find and book a physiotherapist who's online), a live
/// stats grid, and a preview of today's sessions.
class PhysioDashboardScreen extends ConsumerStatefulWidget {
  const PhysioDashboardScreen({super.key});

  @override
  ConsumerState<PhysioDashboardScreen> createState() => _PhysioDashboardScreenState();
}

class _PhysioDashboardScreenState extends ConsumerState<PhysioDashboardScreen> {
  bool _togglingInProgress = false;

  @override
  void initState() {
    super.initState();
    final uid = PhysioProfileService.currentUid;
    if (uid != null) PhysioPresenceService.instance.init(uid);
  }

  @override
  void dispose() {
    PhysioPresenceService.instance.setOnline(false);
    PhysioPresenceService.instance.dispose();
    super.dispose();
  }

  Future<void> _toggleOnline(bool value) async {
    if (_togglingInProgress) return;
    setState(() => _togglingInProgress = true);
    try {
      await PhysioPresenceService.instance.setOnline(value);
    } finally {
      if (mounted) setState(() => _togglingInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ref.watch(physioDashboardMetricsProvider);
    final today = ref.watch(todayPhysioSessionsProvider);
    final online = ref.watch(physioProfileProvider).isOnline;

    return SharedAppShell(
      currentRoute: AppRoutes.physioDashboard,
      title: 'Physiotherapy Dashboard',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _OnlineHeroCard(
            online: online,
            onChanged: _togglingInProgress ? null : _toggleOnline,
          ),
          const SizedBox(height: 20),
          staticGrid(
            crossAxisCount: R.isTablet(context) ? 4 : 2,
            children: [
              GradientStatCard(
                value: '${metrics.todaySessions}',
                label: "Today's Sessions",
                icon: Icons.event_note_rounded,
                colors: const [Color(0xFF00838F), Color(0xFF006064)],
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
              GradientStatCard(
                value: metrics.rating.toStringAsFixed(1),
                label: 'Rating',
                icon: Icons.star_rounded,
                colors: const [AppColors.primary, AppColors.secondary],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title: "Today's Sessions",
            action: today.isNotEmpty ? 'View all' : null,
            onAction: today.isNotEmpty ? () => context.push(AppRoutes.physioSessions) : null,
          ),
          if (today.isEmpty)
            const AppEmptyState(
              icon: Icons.event_available_rounded,
              title: 'No sessions scheduled today',
              message: 'New assigned sessions will appear here.',
            )
          else
            Column(children: today.take(3).map((s) => _SessionPreviewCard(session: s)).toList()),
        ],
      ),
    );
  }
}

class _OnlineHeroCard extends StatelessWidget {
  final bool online;
  final ValueChanged<bool>? onChanged;
  const _OnlineHeroCard({required this.online, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(R.p(context, 20)),
      decoration: BoxDecoration(
        gradient: online
            ? AppColors.onlineGradient
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
                  online ? 'You are ONLINE' : 'You are OFFLINE',
                  style: AppTextStyles.h3.copyWith(fontSize: R.sp(context, 18), fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  online ? 'Visible to patients • Accepting sessions' : 'Not accepting new sessions',
                  style: AppTextStyles.bodySmall.copyWith(fontSize: R.sp(context, 12), color: Colors.white70),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: online,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white38,
          ),
        ],
      ),
    );
  }
}

class _SessionPreviewCard extends StatelessWidget {
  final PhysioSession session;
  const _SessionPreviewCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(AppRoutes.physioSessionDetail, extra: {'sessionId': session.id}),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: session.status.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.accessibility_new_rounded, color: session.status.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.patientName, style: AppTextStyles.labelLarge),
                Text(
                  '${session.preferredTime} • ${session.sessionTitle}',
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          StatusBadge(label: session.status.label, color: session.status.color),
        ],
      ),
    );
  }
}
