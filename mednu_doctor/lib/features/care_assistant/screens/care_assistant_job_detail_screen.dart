import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/utils/maps_launcher.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../caregiver/models/visit.dart';
import '../../caregiver/providers/caregiver_providers.dart';
import '../../caregiver/services/caregiver_profile_service.dart';
import '../../caregiver/services/caregiver_visit_service.dart';
import '../../caregiver/widgets/cancel_visit_sheet.dart';
import '../widgets/care_job_widgets.dart';

/// One care-assistant job, end to end: review the request → Accept/Decline →
/// Start → checklist / notes / photos → Complete. The header, status and
/// actions all follow the live visit document, so they stay in step with what
/// the patient sees in their app.
class CareAssistantJobDetailScreen extends ConsumerStatefulWidget {
  final String visitId;
  const CareAssistantJobDetailScreen({super.key, required this.visitId});

  @override
  ConsumerState<CareAssistantJobDetailScreen> createState() => _CareAssistantJobDetailScreenState();
}

class _CareAssistantJobDetailScreenState extends ConsumerState<CareAssistantJobDetailScreen> {
  bool _busy = false;

  Future<void> _call(String phone) async {
    var opened = false;
    try {
      opened = await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      FeedbackService.showError(context, 'Could not start a call on this device.');
    }
  }

  Future<void> _run(Future<void> Function(String uid) action, {String? success}) async {
    if (_busy) return;
    final uid = CaregiverProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }
    setState(() => _busy = true);
    try {
      await action(uid);
      if (mounted && success != null) FeedbackService.showSuccess(context, success);
    } on CaregiverVisitConflictException catch (e) {
      if (mounted) FeedbackService.showError(context, e.message);
    } catch (_) {
      if (mounted) FeedbackService.showError(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond(Visit visit, bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await respondToCareRequest(context, visit, accept: accept);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && !accept) context.pop();
  }

  Future<void> _cancelAccepted(Visit visit) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await cancelAcceptedVisitFlow(context, visit);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final visit = ref.watch(visitByIdProvider(widget.visitId));
    final uid = CaregiverProfileService.currentUid;

    return SharedAppShell(
      currentRoute: '',
      title: 'Job Details',
      showBottomNav: false,
      body: visit == null
          ? const AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Job not found',
              message: 'This request may have been taken by another assistant.',
            )
          : _body(context, visit, uid),
    );
  }

  Widget _body(BuildContext context, Visit visit, String? uid) {
    final mine = uid != null && visit.caregiverId == uid;
    final awaiting = (visit.isOpenRequest && !visit.declinedBy.contains(uid)) ||
        (uid != null && visit.awaitingResponseFrom(uid));
    final accepted = mine && visit.status == VisitStatus.scheduled && visit.acceptedAt != null;
    final inProgress = mine && visit.status == VisitStatus.checkedIn;
    final done = mine && visit.status == VisitStatus.completed;
    final taken = !mine && visit.caregiverId != null;
    final shownStatus = awaiting
        ? ('Awaiting your response', careAssistantTeal)
        : taken
            ? ('Taken by another assistant', AppColors.textSecondary)
            : accepted
                ? ('Accepted', careAssistantTeal)
                : (visit.status.label, visit.status.color);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [careAssistantTeal, Color(0xFF26A69A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                  color: careAssistantTeal.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shownStatus.$1,
                        style: AppTextStyles.onPrimaryH2.copyWith(fontSize: 18),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(DateFormat('EEEE, d MMM • h:mm a').format(visit.scheduledAt),
                        style: AppTextStyles.onPrimaryBody),
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
                    Text(
                      mine ? 'Patient' : 'Contact details are shared after you accept',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              if (mine)
                IconButton.filled(
                  onPressed: visit.patientPhone.isEmpty ? null : () => _call(visit.patientPhone),
                  icon: const Icon(Icons.call_rounded),
                  style: IconButton.styleFrom(backgroundColor: AppColors.success),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PremiumCard(
          onTap: mine && visit.address.isNotEmpty ? () => openAddressInMaps(context, visit.address) : null,
          child: Row(
            children: [
              const Icon(Icons.location_on_outlined, color: careAssistantTeal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  visit.address.isEmpty ? 'Address shared after you accept' : visit.address,
                  style: AppTextStyles.bodyMedium,
                ),
              ),
              if (mine && visit.address.isNotEmpty)
                const Icon(Icons.directions_rounded, color: careAssistantTeal),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _MiniStat(icon: Icons.timer_outlined, value: visit.durationLabel, label: 'Duration')),
            const SizedBox(width: 12),
            Expanded(
                child: _MiniStat(
                    icon: Icons.currency_rupee_rounded,
                    value: CurrencyFormatter.format(visit.fare),
                    label: 'You earn')),
            if (mine) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  icon: Icons.checklist_rounded,
                  value: '${visit.completedTaskCount}/${visit.tasks.length}',
                  label: 'Tasks',
                  onTap: () => context.push(AppRoutes.caregiverTaskChecklist, extra: {'visitId': visit.id}),
                ),
              ),
            ],
          ],
        ),
        if (mine && (accepted || inProgress || done)) ...[
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
        ],
        const SizedBox(height: 24),
        if (awaiting)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _respond(visit, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GradientButton(
                  label: 'Accept Request',
                  icon: Icons.check_circle_outline_rounded,
                  isLoading: _busy,
                  colors: const [careAssistantTeal, Color(0xFF00695C)],
                  onTap: _busy ? null : () => _respond(visit, true),
                ),
              ),
            ],
          )
        else if (accepted)
          Column(
            children: [
              GradientButton(
                label: 'Start Job',
                icon: Icons.play_arrow_rounded,
                isLoading: _busy,
                colors: const [careAssistantTeal, Color(0xFF00695C)],
                onTap: _busy
                    ? null
                    : () => _run((uid) => CaregiverVisitService.checkIn(visit.id, uid),
                        success: 'Job started — the patient has been notified'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _cancelAccepted(visit),
                icon: const Icon(Icons.event_busy_rounded, size: 18),
                label: const Text('Cancel job'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          )
        else if (inProgress)
          GradientButton(
            label: visit.allTasksDone ? 'Complete Job' : 'Open Task Checklist',
            icon: visit.allTasksDone ? Icons.task_alt_rounded : Icons.checklist_rounded,
            colors: visit.allTasksDone
                ? const [Color(0xFF2E7D32), Color(0xFF1B5E20)]
                : const [careAssistantTeal, Color(0xFF00695C)],
            onTap: () => context.push(
              visit.allTasksDone ? AppRoutes.caregiverCompletionSummary : AppRoutes.caregiverTaskChecklist,
              extra: {'visitId': visit.id},
            ),
          )
        else if (done)
          GradientButton(
            label: 'View Completion Summary',
            icon: Icons.summarize_rounded,
            colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
            onTap: () => context.push(AppRoutes.caregiverCompletionSummary, extra: {'visitId': visit.id}),
          ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;
  const _MiniStat({required this.icon, required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: careAssistantTeal),
          const SizedBox(height: 6),
          Text(value,
              style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}
