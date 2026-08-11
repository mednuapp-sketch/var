import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/visit.dart';
import '../providers/caregiver_providers.dart';
import '../services/caregiver_profile_service.dart';
import '../services/caregiver_visit_service.dart';

/// A receipt-style end-of-visit summary — checklist recap, duration, photo
/// count, and a submit action that marks the visit completed. Visually
/// distinct from every other screen in the module on purpose: this is a
/// "close out" moment, so it reads like a signed report, not another list.
class CaregiverCompletionSummaryScreen extends ConsumerWidget {
  final String visitId;
  const CaregiverCompletionSummaryScreen({super.key, required this.visitId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(visitByIdProvider(visitId));

    return SharedAppShell(
      currentRoute: '',
      title: 'Completion Summary',
      showBottomNav: false,
      body: visit == null
          ? const AppEmptyState(icon: Icons.search_off_rounded, title: 'Visit not found', message: 'This visit may have been reassigned.')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.divider),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)]),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.task_alt_rounded, color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: 14),
                      Text(visit.patientName, style: AppTextStyles.h3),
                      Text(visit.type.label, style: AppTextStyles.bodyMedium.copyWith(color: visit.type.color)),
                      const SizedBox(height: 18),
                      const Divider(height: 1),
                      const SizedBox(height: 18),
                      _SummaryRow(label: 'Tasks completed', value: '${visit.completedTaskCount} / ${visit.tasks.length}'),
                      _SummaryRow(label: 'Duration', value: '${visit.durationMinutes} min'),
                      _SummaryRow(label: 'Notes recorded', value: '${visit.notes.length}'),
                      _SummaryRow(label: 'Photos attached', value: '${visit.photoPaths.length}'),
                      _SummaryRow(label: 'Visit fee', value: CurrencyFormatter.format(visit.fare), highlight: true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider, style: BorderStyle.solid),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Care summary note', style: AppTextStyles.labelMedium),
                      const SizedBox(height: 6),
                      Text(
                        visit.notes.isEmpty
                            ? 'No notes were recorded for this visit.'
                            : visit.notes.last.text,
                        style: AppTextStyles.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (visit.status == VisitStatus.completed)
                  const Center(
                    child: StatusBadge(label: 'Visit report submitted', color: AppColors.success, icon: Icons.check_circle_rounded),
                  )
                else
                  _SubmitReportAction(visitId: visit.id),
              ],
            ),
    );
  }
}

/// Stateful so the submit action carries a busy guard + loading state, like
/// every other terminal transition in this module (`_PrimaryAction` on the
/// visit detail screen). Without it a fast double-tap ran the transaction
/// twice and — worse — called `router.pop()` twice, popping the caller off
/// the stack as well.
class _SubmitReportAction extends ConsumerStatefulWidget {
  final String visitId;
  const _SubmitReportAction({required this.visitId});

  @override
  ConsumerState<_SubmitReportAction> createState() => _SubmitReportActionState();
}

class _SubmitReportActionState extends ConsumerState<_SubmitReportAction> {
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    final uid = CaregiverProfileService.currentUid;
    if (uid == null) {
      FeedbackService.showError(context, 'You are not signed in.');
      return;
    }
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    try {
      await CaregiverVisitService.complete(widget.visitId, caregiverId: uid);
      if (!mounted) return;
      FeedbackService.showSuccess(context, 'Visit report submitted');
      router.pop();
    } on CaregiverVisitConflictException catch (e) {
      if (mounted) FeedbackService.showError(context, e.message);
    } catch (_) {
      if (mounted) {
        FeedbackService.showError(context, 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Completing the visit is what triggers the Cloud Function's
    // one-and-only `caregiver_transactions` ledger credit (and the patient's
    // "service completed" notification), so it goes through the
    // transaction-safe service rather than a local state mutation.
    return GradientButton(
      label: 'Submit Visit Report',
      icon: Icons.send_rounded,
      colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
      isLoading: _busy,
      onTap: _busy ? null : _submit,
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _SummaryRow({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMedium),
          Text(
            value,
            style: highlight
                ? AppTextStyles.labelLarge.copyWith(color: AppColors.success)
                : AppTextStyles.labelMedium,
          ),
        ],
      ),
    );
  }
}
