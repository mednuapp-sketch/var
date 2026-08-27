import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/counselling_session.dart';
import '../providers/counselling_providers.dart';

/// Counsellor home — a live stats grid and a preview of today's sessions.
/// Same shape as the Physiotherapy dashboard, in the module's own purple
/// palette.
class CounsellingDashboardScreen extends ConsumerWidget {
  const CounsellingDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(counsellingDashboardMetricsProvider);
    final today = ref.watch(todayCounsellingSessionsProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.counsellingDashboard,
      title: 'Counselling Dashboard',
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
                colors: const [Color(0xFF5E35B1), Color(0xFF4527A0)],
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
            onAction: today.isNotEmpty ? () => context.push(AppRoutes.counsellingSessions) : null,
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
  final CounsellingSession session;
  const _SessionPreviewCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(AppRoutes.counsellingSessionDetail, extra: {'sessionId': session.id}),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: session.status.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.psychology_rounded, color: session.status.color),
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
