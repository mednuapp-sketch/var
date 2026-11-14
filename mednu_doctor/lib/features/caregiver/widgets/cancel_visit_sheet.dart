import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../models/visit.dart';
import '../services/caregiver_profile_service.dart';
import '../services/caregiver_visit_service.dart';

const _cancelReasons = <String>[
  'I am unwell',
  'Emergency / personal reason',
  'Schedule clash',
  'Unable to reach the location',
  'Other',
];

/// Whether the provider may still cancel [v]: accepted by them, not started.
bool canCancelAcceptedVisit(Visit v, String? uid) =>
    uid != null &&
    v.caregiverId == uid &&
    v.status == VisitStatus.scheduled &&
    v.acceptedAt != null;

/// Reason picker + confirmation, then releases the accepted visit back to the
/// open pool (see [CaregiverVisitService.cancelAccepted]). Shared by the Nurse
/// and Care Assistant detail screens. Returns true if the visit was released.
Future<bool> cancelAcceptedVisitFlow(BuildContext context, Visit visit) async {
  final uid = CaregiverProfileService.currentUid;
  if (uid == null) {
    FeedbackService.showError(context, 'You are not signed in.');
    return false;
  }
  final who = visit.isCareAssistantJob ? 'care assistant' : 'nurse';
  final reason = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _ReasonSheet(),
  );
  if (reason == null || !context.mounted) return false;

  final confirmed = await FeedbackService.confirm(
    context,
    title: 'Cancel this visit?',
    message:
        'The patient will be told their $who cancelled and we will find them another one. '
        'This visit will not be offered to you again.',
    confirmLabel: 'Cancel visit',
    cancelLabel: 'Keep visit',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return false;

  try {
    await CaregiverVisitService.cancelAccepted(visit.id, uid, reason: reason);
    if (context.mounted) {
      FeedbackService.showInfo(context, 'Visit cancelled — it has been released');
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

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet();

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why are you cancelling?', style: AppTextStyles.h4),
            const SizedBox(height: 4),
            Text('Pick a reason. You can only cancel before the visit starts.',
                style: AppTextStyles.bodySmall),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v),
              child: Column(
                children: [
                  for (final r in _cancelReasons)
                    RadioListTile<String>(
                      value: r,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.primary,
                      title: Text(r, style: AppTextStyles.bodyMedium),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
