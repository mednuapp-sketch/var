import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../../core/services/feedback_service.dart';
import '../models/ambulance_request.dart';
import '../providers/ambulance_providers.dart';
import '../services/ambulance_profile_service.dart';
import '../services/ambulance_request_service.dart';
import '../widgets/route_line.dart';

/// Full detail for a single request — patient info, the pickup/drop route
/// strip, a fare estimate, and a status-driven primary action so this one
/// screen carries a request all the way from acceptance through to
/// completion (matching how the Lab/Pharmacy detail screens drive their
/// own pipelines from one place).
class AmbulanceRequestDetailScreen extends ConsumerWidget {
  final String requestId;
  const AmbulanceRequestDetailScreen({super.key, required this.requestId});

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    // launchUrl throws (ACTIVITY_NOT_FOUND) on devices with no dialer —
    // e.g. tablets/web — so this must not be an unguarded fire-and-forget.
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      FeedbackService.showError(context, 'Could not start a call on this device.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(requestByIdProvider(requestId));

    return SharedAppShell(
      currentRoute: '',
      title: 'Request Details',
      showBottomNav: false,
      body: request == null
          ? const AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Request not found',
              message: 'This request may have been resolved already.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [request.type.color, request.type.color.withValues(alpha: 0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: request.type.color.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                        child: Icon(request.type.icon, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(request.type.label, style: AppTextStyles.onPrimaryH2.copyWith(fontSize: 18)),
                            Text('Request #${request.id}', style: AppTextStyles.onPrimaryBody),
                          ],
                        ),
                      ),
                      StatusBadge(label: request.status.label, color: Colors.white, icon: Icons.circle),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PremiumCard(
                  child: Row(
                    children: [
                      SharedProfileAvatar(name: request.patientName, size: 46),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(request.patientName, style: AppTextStyles.labelLarge),
                            Text(request.patientPhone, style: AppTextStyles.bodySmall),
                          ],
                        ),
                      ),
                      IconButton.filled(
                        onPressed: () => _call(context, request.patientPhone),
                        icon: const Icon(Icons.call_rounded),
                        style: IconButton.styleFrom(backgroundColor: AppColors.success),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PremiumCard(
                  child: RouteLine(pickupAddress: request.pickupAddress, dropAddress: request.dropAddress),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: PremiumCard(
                        child: Column(
                          children: [
                            const Icon(Icons.social_distance_rounded, color: AppColors.primary),
                            const SizedBox(height: 6),
                            Text('${request.distanceKm} km', style: AppTextStyles.labelLarge),
                            const Text('Distance', style: AppTextStyles.caption),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PremiumCard(
                        child: Column(
                          children: [
                            const Icon(Icons.timer_outlined, color: AppColors.primary),
                            const SizedBox(height: 6),
                            Text('${request.etaMinutes} min', style: AppTextStyles.labelLarge),
                            const Text('ETA', style: AppTextStyles.caption),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PremiumCard(
                        child: Column(
                          children: [
                            const Icon(Icons.currency_rupee_rounded, color: AppColors.primary),
                            const SizedBox(height: 6),
                            Text('${request.fare}', style: AppTextStyles.labelLarge),
                            const Text('Fare', style: AppTextStyles.caption),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _PrimaryAction(request: request),
              ],
            ),
    );
  }
}

/// Every status transition in the Ambulance pipeline happens here — accept,
/// start navigation, mark arrived, complete. Each is a single
/// transaction-safe `AmbulanceRequestService` call; the realtime
/// `requestByIdProvider` stream is what updates the UI, not the action's
/// return value, so this screen never goes stale even if the request changes
/// on another device.
class _PrimaryAction extends ConsumerStatefulWidget {
  final AmbulanceRequest request;
  const _PrimaryAction({required this.request});

  @override
  ConsumerState<_PrimaryAction> createState() => _PrimaryActionState();
}

class _PrimaryActionState extends ConsumerState<_PrimaryAction> {
  bool _busy = false;

  Future<bool> _run(Future<void> Function(String uid) action, {String? successMessage}) async {
    if (_busy) return false;
    final uid = AmbulanceProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return false;
    }
    setState(() => _busy = true);
    try {
      await action(uid);
      if (successMessage != null && mounted) {
        FeedbackService.showSuccess(context, successMessage);
      }
      return true;
    } on AmbulanceRequestConflictException catch (e) {
      // The realtime stream will refresh this screen to the request's actual
      // current state momentarily — this message just explains *why* the tap
      // didn't do what was expected.
      if (mounted) FeedbackService.showError(context, e.message);
      return false;
    } catch (_) {
      if (mounted) FeedbackService.showError(context, 'Something went wrong. Please try again.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;

    switch (request.status) {
      case AmbulanceRequestStatus.pending:
        return GradientButton(
          label: 'Accept Request',
          icon: Icons.check_rounded,
          isLoading: _busy,
          onTap: _busy
              ? null
              : () => _run(
                    (uid) => AmbulanceRequestService.accept(request.id, uid),
                    successMessage: 'Request accepted',
                  ),
        );
      case AmbulanceRequestStatus.accepted:
        return GradientButton(
          label: 'Start Navigation',
          icon: Icons.navigation_rounded,
          isLoading: _busy,
          onTap: _busy
              ? null
              : () async {
                  final router = GoRouter.of(context);
                  final ok = await _run(
                      (uid) => AmbulanceRequestService.startEnRoute(request.id, ambulanceId: uid));
                  if (!ok || !mounted) return;
                  router.push(AppRoutes.ambulanceNavigation, extra: {'requestId': request.id});
                },
        );
      case AmbulanceRequestStatus.enRoute:
        return GradientButton(
          label: 'Mark Arrived',
          icon: Icons.flag_rounded,
          isLoading: _busy,
          onTap: _busy
              ? null
              : () => _run(
                    (uid) => AmbulanceRequestService.markArrived(request.id, ambulanceId: uid),
                    successMessage: 'Marked as arrived',
                  ),
        );
      case AmbulanceRequestStatus.arrived:
        return GradientButton(
          label: 'Complete Trip',
          icon: Icons.task_alt_rounded,
          colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
          isLoading: _busy,
          onTap: _busy
              ? null
              : () => _run(
                    (uid) => AmbulanceRequestService.complete(request.id, ambulanceId: uid),
                    successMessage: 'Trip completed — earnings credited',
                  ),
        );
      case AmbulanceRequestStatus.completed:
      case AmbulanceRequestStatus.cancelled:
        return const SizedBox();
    }
  }
}
