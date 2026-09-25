import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../ambulance/widgets/status_pulse.dart';
import '../models/nutrition_appointment.dart';
import '../providers/nutrition_providers.dart';
import '../services/nutritionist_profile_service.dart';

/// Nutritionist home — a live stats grid and a preview of today's
/// appointments. Same shape as the Physiotherapy/Counselling dashboards, in
/// the module's own green palette.
class NutritionDashboardScreen extends ConsumerStatefulWidget {
  const NutritionDashboardScreen({super.key});

  @override
  ConsumerState<NutritionDashboardScreen> createState() => _NutritionDashboardScreenState();
}

class _NutritionDashboardScreenState extends ConsumerState<NutritionDashboardScreen> {
  bool _toggling = false;

  Future<void> _toggleOnline(bool value) async {
    final uid = NutritionistProfileService.currentUid;
    if (uid == null || _toggling) return;
    setState(() => _toggling = true);
    try {
      await NutritionistProfileService.setOnlineStatus(uid, value);
    } catch (_) {
      if (mounted) {
        FeedbackService.showError(context, "Couldn't update your availability. Please try again.");
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = ref.watch(nutritionDashboardMetricsProvider);
    final today = ref.watch(todayNutritionAppointmentsProvider);
    final online = ref.watch(nutritionOnlineStatusProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.nutritionDashboard,
      title: 'Dietician Dashboard',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _OnlineHeroCard(
            online: online,
            onChanged: _toggling ? null : _toggleOnline,
          ),
          const SizedBox(height: 20),
          staticGrid(
            crossAxisCount: R.isTablet(context) ? 4 : 2,
            children: [
              GradientStatCard(
                value: '${metrics.todayAppointments}',
                label: "Today's Appointments",
                icon: Icons.event_note_rounded,
                colors: const [AppColors.primary, AppColors.secondary],
              ),
              GradientStatCard(
                value: '${metrics.completedToday}',
                label: 'Completed Today',
                icon: Icons.task_alt_rounded,
                colors: const [Color(0xFF00838F), Color(0xFF006064)],
              ),
              GradientStatCard(
                value: '₹${metrics.todayEarnings}',
                label: "Today's Earnings",
                icon: Icons.account_balance_wallet_rounded,
                colors: const [AppColors.accent, AppColors.accentDark],
              ),
              GradientStatCard(
                value: '${ref.watch(myNutritionAppointmentsProvider).valueOrNull?.length ?? 0}',
                label: 'Total Appointments',
                icon: Icons.calendar_month_rounded,
                colors: const [AppColors.primary, AppColors.secondary],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title: "Today's Appointments",
            action: today.isNotEmpty ? 'View all' : null,
            onAction: today.isNotEmpty ? () => context.push(AppRoutes.nutritionAppointments) : null,
          ),
          if (today.isEmpty)
            const AppEmptyState(
              icon: Icons.event_available_rounded,
              title: 'No appointments scheduled today',
              message: 'Patient bookings will appear here.',
            )
          else
            Column(children: today.take(3).map((a) => _AppointmentPreviewCard(appointment: a)).toList()),
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
            : const LinearGradient(
                colors: [Color(0xFF455A64), Color(0xFF607D8B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
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
                  online ? 'You are AVAILABLE' : 'You are UNAVAILABLE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h3.copyWith(
                      fontSize: R.sp(context, 18), fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  online
                      ? 'Open for video consults • Accepting new bookings'
                      : 'Not accepting new consult bookings',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall
                      .copyWith(fontSize: R.sp(context, 12), color: Colors.white70),
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

class _AppointmentPreviewCard extends StatelessWidget {
  final NutritionAppointment appointment;
  const _AppointmentPreviewCard({required this.appointment});

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(AppRoutes.nutritionAppointmentDetail, extra: {'appointmentId': appointment.id}),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: appointment.status.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.restaurant_menu_rounded, color: appointment.status.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appointment.userName, style: AppTextStyles.labelLarge),
                Text(
                  '${appointment.timeSlot} • ${appointment.consultationType}',
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          StatusBadge(label: appointment.status.label, color: appointment.status.color),
        ],
      ),
    );
  }
}
