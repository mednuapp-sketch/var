import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/nutrition_appointment.dart';
import '../providers/nutrition_providers.dart';

/// Appointments as an "Upcoming"/"History" toggle over one shared timeline
/// list — same visual language as the Physiotherapy/Counselling modules'
/// Sessions screens.
class NutritionAppointmentsScreen extends ConsumerStatefulWidget {
  const NutritionAppointmentsScreen({super.key});

  @override
  ConsumerState<NutritionAppointmentsScreen> createState() => _NutritionAppointmentsScreenState();
}

class _NutritionAppointmentsScreenState extends ConsumerState<NutritionAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SharedAppShell(
      currentRoute: AppRoutes.nutritionAppointments,
      title: 'Appointments',
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tab,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [Tab(text: 'Upcoming'), Tab(text: 'History')],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [_AppointmentTimeline(upcoming: true), _AppointmentTimeline(upcoming: false)],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentTimeline extends ConsumerWidget {
  final bool upcoming;
  const _AppointmentTimeline({required this.upcoming});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointments = upcoming
        ? ref.watch(upcomingNutritionAppointmentsProvider)
        : ref.watch(nutritionAppointmentHistoryProvider);

    if (appointments.isEmpty) {
      return AppEmptyState(
        icon: upcoming ? Icons.event_available_rounded : Icons.history_rounded,
        title: upcoming ? 'No upcoming appointments' : 'No appointment history yet',
        message: upcoming
            ? 'New patient bookings will appear here.'
            : 'Completed and cancelled appointments will show up here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: appointments.length,
      itemBuilder: (context, i) =>
          _TimelineTile(appointment: appointments[i], isLast: i == appointments.length - 1),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final NutritionAppointment appointment;
  final bool isLast;
  const _TimelineTile({required this.appointment, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: appointment.status.color,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: appointment.status.color.withValues(alpha: 0.4), blurRadius: 5)],
                  ),
                ),
                if (!isLast) Expanded(child: Container(width: 2, color: AppColors.divider)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PremiumCard(
                onTap: () => context.push(AppRoutes.nutritionAppointmentDetail, extra: {'appointmentId': appointment.id}),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            appointment.consultationType,
                            style: AppTextStyles.labelLarge.copyWith(color: appointment.status.color),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        StatusBadge(label: appointment.status.label, color: appointment.status.color),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(appointment.userName, style: AppTextStyles.bodyMedium),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InfoChip(
                            icon: Icons.schedule_rounded,
                            label: appointment.date.isNotEmpty
                                ? '${appointment.date}, ${appointment.timeSlot}'
                                : appointment.timeSlot,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          CurrencyFormatter.format(appointment.fee),
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.success),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
