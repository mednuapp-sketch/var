import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/care_task.dart';
import '../models/visit.dart';
import '../providers/caregiver_providers.dart';
import '../services/caregiver_visit_service.dart';
import '../widgets/task_progress_ring.dart';

/// The per-visit checklist — a progress ring up top (see `TaskProgressRing`)
/// and checkable rows below with a strike-through completed state, so the
/// list reads like a real care checklist rather than a generic settings
/// list. All state lives in `CaregiverVisitsController` (mock, in-memory).
class CaregiverTaskChecklistScreen extends ConsumerWidget {
  final String visitId;
  const CaregiverTaskChecklistScreen({super.key, required this.visitId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = ref.watch(visitByIdProvider(visitId));

    return SharedAppShell(
      currentRoute: '',
      title: 'Task Checklist',
      showBottomNav: false,
      body: visit == null
          ? const AppEmptyState(icon: Icons.search_off_rounded, title: 'Visit not found', message: 'This visit may have been reassigned.')
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: visit.type.color.withValues(alpha: 0.25)),
                    boxShadow: [BoxShadow(color: visit.type.color.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 5))],
                  ),
                  child: Row(
                    children: [
                      TaskProgressRing(completed: visit.completedTaskCount, total: visit.tasks.length, color: visit.type.color),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(visit.patientName, style: AppTextStyles.labelLarge),
                            const SizedBox(height: 2),
                            Text(
                              visit.allTasksDone ? 'All tasks completed' : '${visit.tasks.length - visit.completedTaskCount} task(s) remaining',
                              style: AppTextStyles.bodySmall.copyWith(color: visit.allTasksDone ? AppColors.success : AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visit.tasks.isEmpty
                      ? const AppEmptyState(icon: Icons.checklist_rtl_rounded, title: 'No tasks for this visit', message: 'This visit has no checklist items assigned.')
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: visit.tasks.length,
                          itemBuilder: (context, i) => _TaskTile(visitId: visit.id, task: visit.tasks[i], color: visit.type.color),
                        ),
                ),
                if (visit.allTasksDone)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: GradientButton(
                      label: 'Proceed to Completion Summary',
                      icon: Icons.arrow_forward_rounded,
                      colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                      onTap: () => context.push(AppRoutes.caregiverCompletionSummary, extra: {'visitId': visit.id}),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  final String visitId;
  final CareTask task;
  final Color color;
  const _TaskTile({required this.visitId, required this.task, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      // Writes only `isDone` on the task's own subcollection doc — the
      // realtime `visitTasksProvider` stream is what re-renders this tile,
      // and `firestore.rules` rejects any write here that touches another
      // key, so the seeded checklist wording can never be altered.
      // An unawaited rejected Future is an unhandled async error, and a
      // toggle lost to a network drop would otherwise just silently revert.
      onTap: () => CaregiverVisitService.setTaskDone(visitId, task.id, !task.isDone)
          .catchError((_) {
        if (context.mounted) {
          FeedbackService.showError(
              context, 'Could not update that task. Check your connection.');
        }
      }),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: task.isDone ? color : Colors.transparent,
              border: Border.all(color: color, width: 2),
            ),
            child: task.isDone ? const Icon(Icons.check_rounded, color: Colors.white, size: 16) : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    decoration: task.isDone ? TextDecoration.lineThrough : null,
                    color: task.isDone ? AppColors.textHint : AppColors.textPrimary,
                  ),
                ),
                if (task.subtitle != null) Text(task.subtitle!, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
