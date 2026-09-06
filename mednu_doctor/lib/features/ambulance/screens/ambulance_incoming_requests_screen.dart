import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/ambulance_request.dart';
import '../providers/ambulance_providers.dart';
import '../services/ambulance_profile_service.dart';
import '../services/ambulance_request_service.dart';
import '../widgets/countdown_ring.dart';

/// The dispatch queue — every pending emergency request, most urgent
/// first, each with a shrinking countdown ring instead of plain text so
/// urgency reads at a glance. Accept/Decline go through
/// `AmbulanceRequestService` as transaction-guarded Firestore writes; Accept
/// routes straight into Live Tracking since accepting an ambulance
/// request means you're now en route.
class AmbulanceIncomingRequestsScreen extends ConsumerWidget {
  const AmbulanceIncomingRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRequestsProvider);

    return SharedAppShell(
      currentRoute: AppRoutes.ambulanceIncomingRequests,
      title: 'Incoming Requests',
      body: pending.isEmpty
          ? const AppEmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No pending requests',
              message: 'New emergency requests will appear here the instant they come in.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: pending.length,
              itemBuilder: (context, i) => _RequestCard(request: pending[i]),
            ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  final AmbulanceRequest request;
  const _RequestCard({required this.request});

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _busy = false;

  /// Every action is a single transaction-safe `AmbulanceRequestService`
  /// call; the realtime `pendingRequestsProvider` stream is what actually
  /// updates the list, not the action's return value — so this card never
  /// shows a stale state even when another partner claims the same
  /// emergency a moment earlier (which is exactly what the conflict
  /// exception below reports).
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
        FeedbackService.show(context, successMessage, type: FeedbackType.info);
      }
      return true;
    } on AmbulanceRequestConflictException catch (e) {
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
    final ageMinutes = DateTime.now().difference(request.requestedAt).inMinutes;
    final remaining = (5 - ageMinutes).clamp(0, 5);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: request.type.color.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(color: request.type.color.withValues(alpha: 0.14), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: request.type.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(request.type.icon, color: request.type.color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.type.label, style: AppTextStyles.labelLarge.copyWith(color: request.type.color)),
                    Text(request.patientName, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              CountdownRing(minutes: remaining, progress: remaining / 5, color: request.type.color),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(child: Text(request.pickupAddress, style: AppTextStyles.bodySmall, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 10),
              InfoChip(icon: Icons.social_distance_rounded, label: '${request.distanceKm} km'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            (uid) => AmbulanceRequestService.reject(request.id, uid),
                            successMessage: 'Request declined',
                          ),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GradientButton(
                  label: _busy ? 'Please wait…' : 'Accept • ₹${request.fare}',
                  icon: Icons.check_rounded,
                  colors: [request.type.color, request.type.color.withValues(alpha: 0.75)],
                  onTap: _busy
                      ? null
                      : () async {
                          final router = GoRouter.of(context);
                          final ok = await _run((uid) => AmbulanceRequestService.accept(request.id, uid));
                          if (!ok || !mounted) return;
                          router.push(AppRoutes.ambulanceLiveTracking, extra: {'requestId': request.id});
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
