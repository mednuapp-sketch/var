import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/nutrition_appointment.dart';
import '../providers/nutrition_providers.dart';

/// Nutritionist home — a live stats grid and a preview of today's
/// appointments. Same shape as the Physiotherapy/Counselling dashboards, in
/// the module's own green palette.
class NutritionDashboardScreen extends ConsumerWidget {
  const NutritionDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(nutritionDashboardMetricsProvider);
    final today = ref.watch(todayNutritionAppointmentsProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.nutritionDashboard,
      title: 'Nutrition Dashboard',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          staticGrid(
            crossAxisCount: R.isTablet(context) ? 4 : 2,
            children: [
              GradientStatCard(
                value: '${metrics.todayAppointments}',
                label: "Today's Appointments",
                icon: Icons.event_note_rounded,
                colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
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
