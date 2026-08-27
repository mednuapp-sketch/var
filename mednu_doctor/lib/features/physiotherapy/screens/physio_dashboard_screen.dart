import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/physio_session.dart';
import '../providers/physio_providers.dart';

/// Physiotherapist home — a live stats grid and a preview of today's
/// sessions. Same shape as the Caregiver dashboard (stat grid + preview
/// list) in the module's own teal palette.
class PhysioDashboardScreen extends ConsumerWidget {
  const PhysioDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(physioDashboardMetricsProvider);
    final today = ref.watch(todayPhysioSessionsProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.physioDashboard,
      title: 'Physiotherapy Dashboard',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
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
