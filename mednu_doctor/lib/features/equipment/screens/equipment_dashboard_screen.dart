import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/equipment_order.dart';
import '../providers/equipment_providers.dart';
import '../services/equipment_profile_service.dart';
import 'equipment_orders_screen.dart';

/// Equipment vendor home. Redirects to the onboarding recovery screen if the
/// account holds the `equipment` role but has no `equipment_profiles/{uid}`
/// document yet — the same check-on-entry pattern Lab and Pharmacy use.
class EquipmentDashboardScreen extends ConsumerStatefulWidget {
  const EquipmentDashboardScreen({super.key});

  @override
  ConsumerState<EquipmentDashboardScreen> createState() => _EquipmentDashboardScreenState();
}

class _EquipmentDashboardScreenState extends ConsumerState<EquipmentDashboardScreen> {
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarded();
  }

  Future<void> _checkOnboarded() async {
    final uid = EquipmentProfileService.currentUid;
    if (uid == null) return;
    final exists = await EquipmentProfileService.profileExists(uid);
    if (!mounted || exists) return;
    context.go(AppRoutes.equipmentOnboarding);
  }

  Future<void> _toggleOpen(bool value) async {
    final uid = EquipmentProfileService.currentUid;
    if (uid == null || _toggling) return;
    setState(() => _toggling = true);
    try {
      await EquipmentProfileService.updateAcceptingOrders(uid, value);
    } catch (_) {
      if (mounted) FeedbackService.showError(context, 'Could not update your shop status.');
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(equipmentProfileProvider);
    final metricsAsync = ref.watch(equipmentDashboardMetricsProvider);
    final ordersAsync = ref.watch(equipmentOrdersProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.equipmentDashboard,
      title: 'Equipment Dashboard',
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(equipmentOrdersProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            profileAsync.when(
              data: (profile) => profile == null
                  ? const SizedBox()
                  : Column(
                      children: [
                        PremiumCard(
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
                                    Text(profile.name, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text(
                                      profile.isActive ? 'Approved vendor' : 'Awaiting admin approval',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: profile.isActive ? AppColors.success : AppColors.warning,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ShopOpenCard(
                          open: profile.acceptingOrders,
                          live: profile.isActive,
                          onChanged: _toggling ? null : _toggleOpen,
                        ),
                      ],
                    ),
              loading: () => const CardLoadingState(itemCount: 1, cardHeight: 72),
              error: (_, __) => const SizedBox(),
            ),
            const SizedBox(height: 16),
            SharedWalletSummaryCard(onTap: () => context.push(AppRoutes.equipmentEarnings)),
            const SizedBox(height: 20),
            metricsAsync.when(
              loading: () => const CardLoadingState(itemCount: 1, cardHeight: 220),
              error: (_, __) => const NetworkErrorState(),
              data: (m) => staticGrid(
                crossAxisCount: 2,
                children: [
                  GradientStatCard(
                    value: '${m.newOrders}',
                    label: 'New Orders',
                    icon: Icons.notifications_active_rounded,
                    colors: const [Color(0xFFEF6C00), Color(0xFFE65100)],
                  ),
                  GradientStatCard(
                    value: '${m.toDeliver}',
                    label: 'To Deliver',
                    icon: Icons.local_shipping_rounded,
                    colors: const [Color(0xFF1565C0), Color(0xFF0D47A1)],
                  ),
                  GradientStatCard(
                    value: '${m.activeRentals}',
                    label: 'Rentals Out',
                    icon: Icons.schedule_rounded,
                    colors: const [Color(0xFF6A1B9A), AppColors.secondaryDark],
                  ),
                  GradientStatCard(
                    value: '${m.soldOutItems}',
                    label: 'Sold Out Items',
                    icon: Icons.remove_shopping_cart_rounded,
                    colors: const [Color(0xFFC62828), Color(0xFF8E0000)],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SectionHeader(
              title: 'New orders',
              action: 'View all',
              onAction: () => context.go(AppRoutes.equipmentOrders),
            ),
            ordersAsync.when(
              loading: () => const ListLoadingState(itemCount: 2, hasAvatar: false),
              error: (_, __) => const NetworkErrorState(),
              data: (orders) {
                final fresh = orders.where((o) => o.status == EquipmentOrderStatus.pending).take(3).toList();
                if (fresh.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'No new orders',
                    message: 'New bookings from patients appear here in realtime.',
                  );
                }
                return Column(
                  children: [
                    for (final o in fresh) EquipmentOrderCard(order: o, showQuickActions: true),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The shop's open / closed switch — the vendor's equivalent of a restaurant
/// toggling "accepting orders". Closed hides every item's Book button on the
/// patient side without touching the menu itself.
class _ShopOpenCard extends StatelessWidget {
  final bool open;
  final bool live;
  final ValueChanged<bool>? onChanged;
  const _ShopOpenCard({required this.open, required this.live, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final color = open ? AppColors.success : AppColors.textHint;
    return PremiumCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(open ? Icons.storefront_rounded : Icons.pause_circle_filled_rounded, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(open ? 'Shop open' : 'Shop closed', style: AppTextStyles.labelLarge),
                Text(
                  !live
                      ? 'Goes live for patients once approved'
                      : open
                          ? 'Patients can book your equipment'
                          : 'Your items show as unavailable',
                  style: AppTextStyles.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch.adaptive(value: open, onChanged: onChanged, activeTrackColor: AppColors.success),
        ],
      ),
    );
  }
}
