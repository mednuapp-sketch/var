import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../../caregiver/models/visit.dart';
import '../../caregiver/services/caregiver_profile_service.dart';
import '../../caregiver/services/caregiver_visit_service.dart';

const careAssistantTeal = Color(0xFF00897B);

/// Accept / decline plumbing shared by the request card and the detail
/// screen, so both react identically and surface the same conflict message
/// when another assistant gets there first.
Future<bool> respondToCareRequest(BuildContext context, Visit visit, {required bool accept}) async {
  final uid = CaregiverProfileService.currentUid;
  if (uid == null) {
    FeedbackService.showError(context, 'You are not signed in.');
    return false;
  }
  try {
    if (accept) {
      await CaregiverVisitService.accept(visit.id, uid);
      if (context.mounted) {
        FeedbackService.showSuccess(context, 'Request accepted — the patient has been notified');
      }
    } else {
      await CaregiverVisitService.decline(visit.id, uid);
      if (context.mounted) FeedbackService.showInfo(context, 'Request declined');
    }
    return true;
  } on CaregiverVisitConflictException catch (e) {
    if (context.mounted) FeedbackService.showError(context, e.message);
  } catch (_) {
    if (context.mounted) {
      FeedbackService.showError(context, 'Something went wrong. Please try again.');
    }
  }
  return false;
}

/// A live incoming request with one-tap Accept / Decline.
class CareRequestCard extends StatefulWidget {
  final Visit visit;
  const CareRequestCard({super.key, required this.visit});

  @override
  State<CareRequestCard> createState() => _CareRequestCardState();
}

class _CareRequestCardState extends State<CareRequestCard> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    await respondToCareRequest(context, widget.visit, accept: accept);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.visit;
    final uid = CaregiverProfileService.currentUid;
    final direct = uid != null && v.caregiverId == uid;
    final specialty = (v.serviceDetails['specialty'] as String?)?.trim() ?? '';
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 12),
      borderColor: careAssistantTeal.withValues(alpha: 0.35),
      onTap: () => context.push(AppRoutes.careAssistantJobDetail, extra: {'visitId': v.id}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: careAssistantTeal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.support_agent_rounded, color: careAssistantTeal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.patientName,
                        style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      specialty.isNotEmpty ? specialty : 'Care assistance',
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(
                label: direct ? 'For you' : 'New',
                color: direct ? AppColors.primary : careAssistantTeal,
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              InfoChip(icon: Icons.schedule_rounded, label: DateFormat('d MMM, h:mm a').format(v.scheduledAt)),
              InfoChip(icon: Icons.timer_outlined, label: v.durationLabel),
              if (v.address.isNotEmpty) InfoChip(icon: Icons.location_on_outlined, label: v.address),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(CurrencyFormatter.format(v.fare),
                    style: AppTextStyles.h4.copyWith(color: AppColors.success),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _busy ? null : () => _respond(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size(88, 44),
                ),
                child: const Text('Decline'),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _busy ? null : () => _respond(true),
                style: FilledButton.styleFrom(
                  backgroundColor: careAssistantTeal,
                  minimumSize: const Size(96, 44),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Accept'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact row for an accepted / in-progress / past job.
class CareJobTile extends StatelessWidget {
  final Visit visit;
  const CareJobTile({super.key, required this.visit});

  @override
  Widget build(BuildContext context) {
    final v = visit;
    final accepted = v.status == VisitStatus.scheduled;
    final statusLabel = accepted ? 'Accepted' : v.status.label;
    final statusColor = accepted ? careAssistantTeal : v.status.color;
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => context.push(AppRoutes.careAssistantJobDetail, extra: {'visitId': v.id}),
      child: Row(
        children: [
          SharedProfileAvatar(name: v.patientName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.patientName,
                    style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('d MMM, h:mm a').format(v.scheduledAt)} • ${v.durationLabel}',
                  style: AppTextStyles.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(label: statusLabel, color: statusColor),
              const SizedBox(height: 6),
              Text(CurrencyFormatter.format(v.fare),
                  style: AppTextStyles.labelMedium.copyWith(color: AppColors.success)),
            ],
          ),
        ],
      ),
    );
  }
}
