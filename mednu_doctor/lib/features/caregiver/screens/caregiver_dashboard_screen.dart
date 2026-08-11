import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/visit.dart';
import '../providers/caregiver_providers.dart';
import '../widgets/duty_pulse.dart';

/// Caregiver home — an on-duty hero card, live stats grid, and a preview
/// of the next scheduled visit. Same shape as the Doctor/Ambulance
/// dashboards (hero + stat grid + preview list) but in the module's own
/// warm teal/amber palette rather than a reskinned copy.
class CaregiverDashboardScreen extends ConsumerWidget {
  const CaregiverDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onDuty = ref.watch(caregiverOnDutyProvider);
    final metrics = ref.watch(caregiverDashboardMetricsProvider);
    final today = ref.watch(todayVisitsProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.caregiverDashboard,
      title: 'Caregiver Dashboard',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _DutyHeroCard(onDuty: onDuty),
          const SizedBox(height: 20),
          staticGrid(
            crossAxisCount: R.isTablet(context) ? 4 : 2,
            children: [
              GradientStatCard(
                value: '${metrics.todayVisits}',
                label: "Today's Visits",
                icon: Icons.event_note_rounded,
                colors: const [Color(0xFF00695C), Color(0xFF004D40)],
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
                colors: const [Color(0xFFEF6C00), Color(0xFFE65100)],
              ),
              GradientStatCard(
                value: metrics.rating.toStringAsFixed(1),
                label: 'Caregiver Rating',
                icon: Icons.star_rounded,
                colors: const [Color(0xFF6A1B9A), Color(0xFF4A148C)],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title: "Today's Visits",
            action: today.isNotEmpty ? 'View all' : null,
            onAction: today.isNotEmpty ? () => context.push(AppRoutes.caregiverAssignedVisits) : null,
          ),
          if (today.isEmpty)
            const AppEmptyState(
              icon: Icons.event_available_rounded,
              title: 'No visits scheduled today',
              message: 'New assigned visits will appear here.',
            )
          else
            Column(children: today.take(3).map((v) => _VisitPreviewCard(visit: v)).toList()),
        ],
      ),
    );
  }
}

class _DutyHeroCard extends ConsumerWidget {
  final bool onDuty;
  const _DutyHeroCard({required this.onDuty});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.all(R.p(context, 20)),
      decoration: BoxDecoration(
        gradient: onDuty
            ? const LinearGradient(colors: [Color(0xFF00695C), Color(0xFF00897B)], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : const LinearGradient(colors: [Color(0xFF455A64), Color(0xFF607D8B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (onDuty ? AppColors.accent : AppColors.offline).withValues(alpha: 0.35),
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
                  style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 18), fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  onDuty ? 'Visible for new visit assignments' : 'Not receiving new assignments',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 12), color: Colors.white70),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: onDuty,
            onChanged: (v) => ref.read(caregiverOnDutyProvider.notifier).state = v,
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white38,
          ),
        ],
      ),
    );
  }
}

class _VisitPreviewCard extends StatelessWidget {
  final Visit visit;
  const _VisitPreviewCard({required this.visit});

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(AppRoutes.caregiverVisitDetail, extra: {'visitId': visit.id}),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: visit.type.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(visit.type.icon, color: visit.type.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(visit.patientName, style: AppTextStyles.labelLarge),
                Text('${DateFormat('h:mm a').format(visit.scheduledAt)} • ${visit.type.label}', style: AppTextStyles.bodySmall, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          StatusBadge(label: visit.status.label, color: visit.status.color),
        ],
      ),
    );
  }
}
