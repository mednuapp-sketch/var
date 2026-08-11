import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/pharmacy_order.dart';
import '../providers/pharmacy_providers.dart';
import '../services/pharmacy_profile_service.dart';

/// Pharmacy home. Redirects to [PharmacyOnboardingScreen] the first time an
/// account with the `pharmacy` role has no `pharmacy_profiles/{uid}`
/// document yet — same "check on entry, redirect if incomplete" pattern
/// used by both Doctor's dashboard and the Lab module.
class PharmacyDashboardScreen extends ConsumerStatefulWidget {
  const PharmacyDashboardScreen({super.key});

  @override
  ConsumerState<PharmacyDashboardScreen> createState() => _PharmacyDashboardScreenState();
}

class _PharmacyDashboardScreenState extends ConsumerState<PharmacyDashboardScreen> {
  @override
  void initState() {
    super.initState();
    _checkOnboarded();
  }

  Future<void> _checkOnboarded() async {
    final uid = PharmacyProfileService.currentUid;
    if (uid == null) return;
    final exists = await PharmacyProfileService.profileExists(uid);
    if (!mounted || exists) return;
    context.go(AppRoutes.pharmacyOnboarding);
  }

  @override
  Widget build(BuildContext context) {
    final metricsAsync = ref.watch(pharmacyDashboardMetricsProvider);
    final profileAsync = ref.watch(pharmacyProfileProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.pharmacyDashboard,
      title: 'Pharmacy Dashboard',
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(pharmacyDashboardMetricsProvider),
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
                                    profile.status == 'active' ? 'Active partner' : 'Verification pending',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: profile.status == 'active' ? AppColors.success : AppColors.warning,
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
            SharedWalletSummaryCard(onTap: () => context.push(AppRoutes.pharmacyEarnings)),
            const SizedBox(height: 20),
            metricsAsync.when(
              loading: () => const CardLoadingState(itemCount: 1, cardHeight: 280),
              error: (_, __) => const NetworkErrorState(),
              data: (m) => staticGrid(
                crossAxisCount: 2,
                children: [
                  GradientStatCard(
                    value: '${m.todayOrders}',
                    label: "Today's Orders",
                    icon: Icons.receipt_long_rounded,
                    colors: const [Color(0xFF1565C0), Color(0xFF0D47A1)],
                  ),
                  GradientStatCard(
                    value: '${m.pendingVerification}',
                    label: 'Needs Prescription',
                    icon: Icons.medical_information_rounded,
                    colors: const [Color(0xFFEF6C00), Color(0xFFE65100)],
                  ),
                  GradientStatCard(
                    value: '${m.packedAwaitingDispatch}',
                    label: 'Packed',
                    icon: Icons.inventory_2_rounded,
                    colors: const [Color(0xFF6A1B9A), Color(0xFF4A148C)],
                  ),
                  GradientStatCard(
                    value: '${m.outForDelivery}',
                    label: 'Out for Delivery',
                    icon: Icons.local_shipping_rounded,
                    colors: const [Color(0xFFF9A825), Color(0xFFF57F17)],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SectionHeader(
              title: 'Available Orders',
              action: 'View all',
              onAction: () => context.push(AppRoutes.pharmacyOrders),
            ),
            Consumer(
              builder: (context, ref, _) {
                final available = ref.watch(availableOrdersProvider);
                return available.when(
                  loading: () => const ListLoadingState(itemCount: 2, hasAvatar: false),
                  error: (_, __) => const NetworkErrorState(),
                  data: (orders) {
                    if (orders.isEmpty) {
                      return const AppEmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'No new orders',
                        message: 'New medicine and equipment orders will appear here in realtime.',
                      );
                    }
                    return Column(
                      children: orders.take(3).map((o) {
                        return PremiumCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          onTap: () => context.push(
                            AppRoutes.pharmacyOrderDetail,
                            extra: {'orderId': o.id},
                          ),
                          child: Row(
                            children: [
                              Icon(
                                o.orderType == PharmacyOrderType.equipment
                                    ? Icons.medical_services_outlined
                                    : Icons.medication_outlined,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      o.orderType == PharmacyOrderType.equipment
                                          ? 'Equipment order'
                                          : '${o.itemCount} item(s)',
                                      style: AppTextStyles.labelLarge,
                                    ),
                                    Text(o.patientName, style: AppTextStyles.bodySmall),
                                  ],
                                ),
                              ),
                              StatusBadge(label: o.status.label, color: o.status.color),
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
