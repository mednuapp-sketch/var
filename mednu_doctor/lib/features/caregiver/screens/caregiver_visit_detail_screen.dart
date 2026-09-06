import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../../core/services/feedback_service.dart';
import '../models/visit.dart';
import '../providers/caregiver_providers.dart';
import '../services/caregiver_profile_service.dart';
import '../services/caregiver_visit_service.dart';

/// Full detail for a single visit — patient card, care-plan chips, address,
/// and a status-driven action that carries the visit from check-in through
/// to the checklist/notes/photos/completion sub-screens (matching how the
/// Ambulance and Lab modules drive their own pipelines from one place).
class CaregiverVisitDetailScreen extends ConsumerWidget {
  final String visitId;
  const CaregiverVisitDetailScreen({super.key, required this.visitId});

  Future<void> _call(BuildContext context, String phone) async {
    // launchUrl throws (ACTIVITY_NOT_FOUND) on devices with no dialer —
    // e.g. tablets/web — so this must not be an unguarded fire-and-forget.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(visitByIdProvider(visitId));

    return SharedAppShell(
      currentRoute: '',
      title: 'Visit Details',
      showBottomNav: false,
      body: visit == null
          ? const AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Visit not found',
              message: 'This visit may have been reassigned.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [visit.type.color, visit.type.color.withValues(alpha: 0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: visit.type.color.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                        child: Icon(visit.type.icon, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(visit.type.label, style: AppTextStyles.onPrimaryH2.copyWith(fontSize: 18)),
                            Text(DateFormat('EEEE, d MMM • h:mm a').format(visit.scheduledAt), style: AppTextStyles.onPrimaryBody),
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
                      SharedProfileAvatar(name: visit.patientName, size: 46),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(visit.patientName, style: AppTextStyles.labelLarge),
                            Text('${visit.patientAge} years old', style: AppTextStyles.bodySmall),
                          ],
                        ),
                      ),
                      IconButton.filled(
                        onPressed: visit.patientPhone.isEmpty ? null : () => _call(context, visit.patientPhone),
                        icon: const Icon(Icons.call_rounded),
                        style: IconButton.styleFrom(backgroundColor: AppColors.success),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PremiumCard(
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(visit.address, style: AppTextStyles.bodyMedium)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStatCard(
                        icon: Icons.timer_outlined,
                        value: '${visit.durationMinutes} min',
                        label: 'Duration',
                        onTap: null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniStatCard(
                        icon: Icons.checklist_rounded,
                        value: '${visit.completedTaskCount}/${visit.tasks.length}',
                        label: 'Tasks',
                        onTap: () => context.push(AppRoutes.caregiverTaskChecklist, extra: {'visitId': visit.id}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniStatCard(
                        icon: Icons.currency_rupee_rounded,
                        value: '${visit.fare}',
                        label: 'Visit Fee',
                        onTap: null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(AppRoutes.caregiverNotes, extra: {'visitId': visit.id}),
                        icon: const Icon(Icons.notes_rounded, size: 18),
                        label: Text('Notes (${visit.notes.length})'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(AppRoutes.caregiverUploadPhotos, extra: {'visitId': visit.id}),
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: Text('Photos (${visit.photoPaths.length})'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _PrimaryAction(visit: visit),
              ],
            ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;
  const _MiniStatCard({required this.icon, required this.value, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: 6),
          Text(value, style: AppTextStyles.labelLarge),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

/// Check-in is a single transaction-safe `CaregiverVisitService` call (it
/// also claims the visit if it was still unassigned); the realtime
/// `visitByIdProvider` stream is what updates the UI, not the action's
/// return value.
class _PrimaryAction extends ConsumerStatefulWidget {
  final Visit visit;
  const _PrimaryAction({required this.visit});

  @override
  ConsumerState<_PrimaryAction> createState() => _PrimaryActionState();
}

class _PrimaryActionState extends ConsumerState<_PrimaryAction> {
  bool _busy = false;

  Future<void> _checkIn(String visitId) async {
    if (_busy) return;
    final uid = CaregiverProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }
    setState(() => _busy = true);
    try {
      await CaregiverVisitService.checkIn(visitId, uid);
      if (mounted) FeedbackService.showSuccess(context, 'Checked in');
    } on CaregiverVisitConflictException catch (e) {
      if (mounted) FeedbackService.showError(context, e.message);
    } catch (_) {
      if (mounted) FeedbackService.showError(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visit = widget.visit;

    switch (visit.status) {
      case VisitStatus.scheduled:
        return GradientButton(
          label: 'Check In',
          icon: Icons.login_rounded,
          isLoading: _busy,
          onTap: _busy ? null : () => _checkIn(visit.id),
        );
      case VisitStatus.checkedIn:
        return GradientButton(
          label: 'Open Task Checklist',
          icon: Icons.checklist_rounded,
          onTap: () => context.push(AppRoutes.caregiverTaskChecklist, extra: {'visitId': visit.id}),
        );
      case VisitStatus.completed:
        return GradientButton(
          label: 'View Completion Summary',
          icon: Icons.summarize_rounded,
          colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
          onTap: () => context.push(AppRoutes.caregiverCompletionSummary, extra: {'visitId': visit.id}),
        );
      case VisitStatus.missed:
      case VisitStatus.cancelled:
        return const SizedBox();
    }
  }
}
