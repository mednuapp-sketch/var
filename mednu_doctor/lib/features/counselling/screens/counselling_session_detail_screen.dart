import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/counselling_session.dart';
import '../providers/counselling_providers.dart';
import '../services/counselling_profile_service.dart';
import '../services/counselling_session_service.dart';

/// Full detail for a single session — patient card, schedule, address, and a
/// status-driven action bar that carries the session from claim through to
/// completion. Mirrors the Physiotherapy module's Session Detail shape.
class CounsellingSessionDetailScreen extends ConsumerWidget {
  final String sessionId;
  const CounsellingSessionDetailScreen({super.key, required this.sessionId});

  Future<void> _call(BuildContext context, String phone) async {
    if (phone.isEmpty) {
      FeedbackService.showError(context, 'No phone number on file for this patient.');
      return;
    }
    var opened = false;
    try {
      opened = await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      FeedbackService.showError(context, 'Could not start a call on this device.');
    }
  }

  void _startVideoSession(BuildContext context, CounsellingSession session) {
    if (session.patientId.isEmpty) {
      FeedbackService.showError(context, 'Patient details are still loading — try again in a moment.');
      return;
    }
    context.push(AppRoutes.providerOutgoingCall, extra: {
      'providerRole': 'counsellor',
      'patientId': session.patientId,
      'patientName': session.patientName,
      'sessionId': session.id,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(counsellingSessionDocProvider(sessionId)).valueOrNull;

    return SharedAppShell(
      currentRoute: '',
      title: 'Session Details',
      showBottomNav: false,
      body: session == null
          ? const AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Session not found',
              message: 'This session may have been reassigned or removed.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [session.status.color, session.status.color.withValues(alpha: 0.72)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(color: session.status.color.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(session.sessionTitle, style: AppTextStyles.onPrimaryH2.copyWith(fontSize: 18), overflow: TextOverflow.ellipsis),
                            Text(
                              session.preferredDate.isNotEmpty
                                  ? '${session.preferredDate} • ${session.preferredTime}'
                                  : session.preferredTime,
                              style: AppTextStyles.onPrimaryBody,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PremiumCard(
                  child: Row(
                    children: [
                      SharedProfileAvatar(name: session.patientName, size: 46),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(session.patientName, style: AppTextStyles.labelLarge),
                            Text(session.status.label, style: AppTextStyles.bodySmall.copyWith(color: session.status.color)),
                          ],
                        ),
                      ),
                      IconButton.filled(
                        onPressed: () => _startVideoSession(context, session),
                        icon: const Icon(Icons.videocam_rounded),
                        style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () => _call(context, session.patientPhone),
                        icon: const Icon(Icons.call_rounded),
                        style: IconButton.styleFrom(backgroundColor: AppColors.success),
                      ),
                    ],
                  ),
                ),
                if (session.address.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  PremiumCard(
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text(session.address, style: AppTextStyles.bodyMedium)),
                      ],
                    ),
                  ),
                ],
                if (session.notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  PremiumCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notes_rounded, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text(session.notes, style: AppTextStyles.bodyMedium)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                PremiumCard(
                  child: Row(
                    children: [
                      const Icon(Icons.currency_rupee_rounded, color: AppColors.primary),
                      const SizedBox(width: 10),
                      const Text('Session Fee', style: AppTextStyles.bodyMedium),
                      const Spacer(),
                      Text(
                        CurrencyFormatter.format(session.amount),
                        style: AppTextStyles.labelLarge.copyWith(color: AppColors.success),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _PrimaryActions(session: session),
              ],
            ),
    );
  }
}

class _PrimaryActions extends ConsumerStatefulWidget {
  final CounsellingSession session;
  const _PrimaryActions({required this.session});

  @override
  ConsumerState<_PrimaryActions> createState() => _PrimaryActionsState();
}

class _PrimaryActionsState extends ConsumerState<_PrimaryActions> {
  bool _busy = false;

  String? get _uid => CounsellingProfileService.currentUid;

  Future<void> _run(Future<void> Function(String uid) action, String successMessage) async {
    if (_busy) return;
    final uid = _uid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }
    setState(() => _busy = true);
    try {
      await action(uid);
      if (mounted) FeedbackService.showSuccess(context, successMessage);
    } on CounsellingSessionConflictException catch (e) {
      if (mounted) FeedbackService.showError(context, e.message);
    } catch (_) {
      if (mounted) FeedbackService.showError(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final id = session.id;

    switch (session.status) {
      case CounsellingSessionStatus.pending:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run((uid) => CounsellingSessionService.decline(id, uid), 'Session declined'),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Decline'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                label: 'Accept Session',
                icon: Icons.check_rounded,
                isLoading: _busy,
                onTap: _busy
                    ? null
                    : () => _run((uid) => CounsellingSessionService.claim(id, uid), 'Session accepted'),
              ),
            ),
          ],
        );
      case CounsellingSessionStatus.accepted:
        return Column(
          children: [
            GradientButton(
              label: 'Start Session',
              icon: Icons.play_arrow_rounded,
              isLoading: _busy,
              onTap: _busy
                  ? null
                  : () => _run((uid) => CounsellingSessionService.start(id, counsellorId: uid), 'Session started'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run((uid) => CounsellingSessionService.cancel(id, counsellorId: uid), 'Session cancelled'),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('Cancel Session'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
            ),
          ],
        );
      case CounsellingSessionStatus.inProgress:
        return GradientButton(
          label: 'Complete Session',
          icon: Icons.task_alt_rounded,
          colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
          isLoading: _busy,
          onTap: _busy
              ? null
              : () => _run((uid) => CounsellingSessionService.complete(id, counsellorId: uid), 'Session completed'),
        );
      case CounsellingSessionStatus.completed:
      case CounsellingSessionStatus.cancelled:
      case CounsellingSessionStatus.expired:
        return const SizedBox();
    }
  }
}
