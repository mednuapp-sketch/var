import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../providers/hospital_providers.dart';

/// Hospital Billing Desk's "Home" — a desk/office role tied to one
/// `hospitals/{hospitalId}` entity (not GPS/location-based, so unlike the
/// field roles there is no online/offline toggle here). Surfaces today's
/// check-in/payment workload at a glance plus quick links into the queue
/// screens this role already has (Appointments/Payments/Earnings), all
/// backed by the same live `hospital_appointments` / `hospital_bill_payments`
/// streams those screens use — see hospital_providers.dart.
class HospitalDashboardScreen extends ConsumerWidget {
  const HospitalDashboardScreen({super.key});

  static const _statusMeta = {
    'booked': (label: 'Booked', color: AppColors.info),
    'checked_in': (label: 'Checked In', color: AppColors.warning),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(hospitalProfileProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.hospitalDashboard,
      title: 'Hospital Dashboard',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(hospitalAppointmentsProvider);
          ref.invalidate(hospitalPaymentsProvider);
        },
        child: profileAsync.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [CardLoadingState(itemCount: 4, cardHeight: 90)],
          ),
          error: (_, __) => const NetworkErrorState(),
          data: (profile) {
            if (profile == null) {
              return const AppEmptyState(
                icon: Icons.local_hospital_outlined,
                title: 'Profile not found',
                message: 'Complete registration to set up your billing desk profile.',
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                PremiumCard(
                  child: Row(
                    children: [
                      SharedProfileAvatar(
                        name: profile.displayName,
                        photoUrl: profile.photoUrl,
                        size: 48,
                        isVerified: profile.isActive,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile.displayName, style: AppTextStyles.labelLarge),
                            const SizedBox(height: 2),
                            Text(
                              profile.isActive ? 'Active billing desk' : 'Verification pending',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: profile.isActive ? AppColors.success : AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusBadge(
                        label: profile.isActive ? 'Active' : 'Pending',
                        color: profile.isActive ? AppColors.success : AppColors.warning,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (!profile.isLinked) ...[
                  const AppEmptyState(
                    icon: Icons.hourglass_top_rounded,
                    title: 'Awaiting hospital link',
                    message: 'Our team is confirming which hospital this account represents. '
                        'Your dashboard will fill in once that\'s done.',
                  ),
                ] else ...[
                  SharedWalletSummaryCard(onTap: () => context.push(AppRoutes.hospitalEarnings)),
                  const SizedBox(height: 20),

                  Consumer(
                    builder: (context, ref, _) {
                      final metrics = ref.watch(hospitalDashboardMetricsProvider);
                      return staticGrid(
                        crossAxisCount: 2,
                        children: [
                          GradientStatCard(
                            value: '${metrics.todayAppointments}',
                            label: 'Today\'s Appointments',
                            icon: Icons.event_note_rounded,
                            colors: const [Color(0xFF1565C0), Color(0xFF0D47A1)],
                          ),
                          GradientStatCard(
                            value: '${metrics.pendingCheckIns}',
                            label: 'Pending Check-ins',
                            icon: Icons.how_to_reg_rounded,
                            colors: const [Color(0xFFEF6C00), Color(0xFFE65100)],
                          ),
                          GradientStatCard(
                            value: '${metrics.completedToday}',
                            label: 'Completed Today',
                            icon: Icons.task_alt_rounded,
                            colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                          ),
                          GradientStatCard(
                            value: '${metrics.pendingPayments}',
                            label: 'Pending Payments',
                            icon: Icons.receipt_long_rounded,
                            colors: const [Color(0xFF6A1B9A), AppColors.secondaryDark],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  SectionHeader(
                    title: 'Today\'s Queue',
                    action: 'View all',
                    onAction: () => context.push(AppRoutes.hospitalAppointments),
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final queue = ref.watch(hospitalTodayQueueProvider);
                      if (queue.isEmpty) {
                        return const AppEmptyState(
                          icon: Icons.event_available_outlined,
                          title: 'No pending arrivals today',
                          message: 'Booked OP tokens awaiting check-in will show up here.',
                        );
                      }
                      return Column(
                        children: queue.take(3).map((a) {
                          final meta = _statusMeta[a.status] ??
                              (label: a.status, color: AppColors.textHint);
                          return PremiumCard(
                            margin: const EdgeInsets.only(bottom: 10),
                            onTap: () => context.push(AppRoutes.hospitalAppointments),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.confirmation_number_rounded,
                                      color: AppColors.primary, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(a.patientName, style: AppTextStyles.labelLarge),
                                      Text('${a.opToken} · ${a.time}',
                                          style: AppTextStyles.caption),
                                    ],
                                  ),
                                ),
                                StatusBadge(label: meta.label, color: meta.color),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  const SectionHeader(title: 'Quick Links'),
                  _QuickLinkTile(
                    icon: Icons.event_note_rounded,
                    label: 'OP Appointments',
                    subtitle: 'Check-in, complete, or mark a no-show',
                    color: AppColors.info,
                    onTap: () => context.push(AppRoutes.hospitalAppointments),
                  ),
                  const SizedBox(height: 10),
                  _QuickLinkTile(
                    icon: Icons.receipt_long_rounded,
                    label: 'Bill Payments',
                    subtitle: 'Confirm patient payments as they land',
                    color: AppColors.success,
                    onTap: () => context.push(AppRoutes.hospitalPayments),
                  ),
                  const SizedBox(height: 10),
                  _QuickLinkTile(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Earnings',
                    subtitle: 'Settlement history across both revenue streams',
                    color: AppColors.primary,
                    onTap: () => context.push(AppRoutes.hospitalEarnings),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuickLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickLinkTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
        ],
      ),
    );
  }
}
