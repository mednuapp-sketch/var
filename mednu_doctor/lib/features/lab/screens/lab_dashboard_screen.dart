import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/diagnostic_booking.dart';
import '../providers/lab_providers.dart';
import '../services/lab_profile_service.dart';

/// Lab & Diagnostics home. Redirects to [LabOnboardingScreen] the first time
/// an account with the `lab` role has no `lab_profiles/{uid}` document yet
/// — the same "check on entry, redirect if incomplete" pattern
/// `DashboardScreen._checkApprovalStatus` already uses for Doctor.
class LabDashboardScreen extends ConsumerStatefulWidget {
  const LabDashboardScreen({super.key});

  @override
  ConsumerState<LabDashboardScreen> createState() => _LabDashboardScreenState();
}

class _LabDashboardScreenState extends ConsumerState<LabDashboardScreen> {
  @override
  void initState() {
    super.initState();
    _checkOnboarded();
  }

  Future<void> _checkOnboarded() async {
    final uid = LabProfileService.currentUid;
    if (uid == null) return;
    final exists = await LabProfileService.profileExists(uid);
    if (!mounted || exists) return;
    context.go(AppRoutes.labOnboarding);
  }

  @override
  Widget build(BuildContext context) {
    final metricsAsync = ref.watch(labDashboardMetricsProvider);
    final profileAsync = ref.watch(labProfileProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.labDashboard,
      title: 'Lab Dashboard',
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(labDashboardMetricsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            profileAsync.when(
              data: (profile) => profile == null
                  ? const SizedBox()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: PremiumCard(
                        child: Row(
                          children: [
                            SharedProfileAvatar(
                              name: profile.name,
                              photoUrl: profile.photoUrl,
                              size: 44,
                              isVerified: profile.isVerified,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(profile.name, style: AppTextStyles.labelLarge),
                                  Text(
                                    profile.status == 'active'
                                        ? 'Active partner'
                                        : 'Verification pending',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: profile.status == 'active'
                                          ? AppColors.success
                                          : AppColors.warning,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              loading: () => const CardLoadingState(itemCount: 1, cardHeight: 72),
              error: (_, __) => const SizedBox(),
            ),
            SharedWalletSummaryCard(onTap: () => context.push(AppRoutes.labEarnings)),
            const SizedBox(height: 20),
            metricsAsync.when(
              loading: () => const CardLoadingState(itemCount: 1, cardHeight: 220),
              error: (_, __) => const NetworkErrorState(),
              data: (m) => staticGrid(
                crossAxisCount: 2,
                children: [
                  GradientStatCard(
                    value: '${m.todayBookings}',
                    label: 'Today\'s Bookings',
                    icon: Icons.event_note_rounded,
                    colors: const [Color(0xFF1565C0), Color(0xFF0D47A1)],
                  ),
                  GradientStatCard(
                    value: '${m.pendingCollections}',
                    label: 'Pending Collections',
                    icon: Icons.local_shipping_rounded,
                    colors: const [Color(0xFF6A1B9A), Color(0xFF4A148C)],
                  ),
                  GradientStatCard(
                    value: '${m.processingReports}',
                    label: 'Processing Reports',
                    icon: Icons.hourglass_bottom_rounded,
                    colors: const [Color(0xFFEF6C00), Color(0xFFE65100)],
                  ),
                  GradientStatCard(
                    value: '${m.completedReports}',
                    label: 'Completed Reports',
                    icon: Icons.task_alt_rounded,
                    colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SectionHeader(
              title: 'Available Requests',
              action: 'View all',
              onAction: () => context.push(AppRoutes.labBookings),
            ),
            Consumer(
              builder: (context, ref, _) {
                final available = ref.watch(availableBookingsProvider);
                return available.when(
                  loading: () => const ListLoadingState(itemCount: 2, hasAvatar: false),
                  error: (_, __) => const NetworkErrorState(),
                  data: (bookings) {
                    if (bookings.isEmpty) {
                      return const AppEmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'No new requests',
                        message: 'New diagnostic bookings will appear here in realtime.',
                      );
                    }
                    return Column(
                      children: bookings.take(3).map((b) {
                        return PremiumCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          onTap: () => context.push(
                            AppRoutes.labBookingDetail,
                            extra: {'bookingId': b.id},
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.biotech_rounded, color: AppColors.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(b.testName, style: AppTextStyles.labelLarge),
                                    Text(b.patientName, style: AppTextStyles.bodySmall),
                                  ],
                                ),
                              ),
                              StatusBadge(label: b.status.label, color: b.status.color),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
