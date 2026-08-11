import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/shared_core.dart';
import '../models/care_note.dart';
import '../providers/caregiver_providers.dart';
import '../services/caregiver_visit_service.dart';

/// Care notes as a journal-style timeline with an add-note composer
/// anchored to the bottom — deliberately distinct from the checklist's
/// tap-to-toggle rows, since notes are free-text observations, not
/// binary tasks.
class CaregiverNotesScreen extends ConsumerStatefulWidget {
  final String visitId;
  const CaregiverNotesScreen({super.key, required this.visitId});

  @override
  ConsumerState<CaregiverNotesScreen> createState() => _CaregiverNotesScreenState();
}

class _CaregiverNotesScreenState extends ConsumerState<CaregiverNotesScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    // Append-only: the note lands in the visit's `notes` subcollection and
    // comes back through the realtime `visitNotesProvider` stream. Fired
    // without awaiting so the composer clears instantly — but the failure
    // must still be caught (an unawaited rejected Future is an unhandled
    // async error) and surfaced, otherwise a note lost to a network drop
    // disappears with no signal at all.
    CaregiverVisitService.addNote(widget.visitId, text).catchError((_) {
      if (!mounted) return;
      FeedbackService.showError(
          context, 'Could not save that note. Check your connection and try again.');
    });
    _ctrl.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final visit = ref.watch(visitByIdProvider(widget.visitId));

    return SharedAppShell(
      currentRoute: '',
      title: 'Care Notes',
      showBottomNav: false,
      body: visit == null
          ? const AppEmptyState(icon: Icons.search_off_rounded, title: 'Visit not found', message: 'This visit may have been reassigned.')
          : Column(
              children: [
                Expanded(
                  child: visit.notes.isEmpty
                      ? const AppEmptyState(
                          icon: Icons.notes_rounded,
                          title: 'No notes yet',
                          message: 'Observations you add during the visit will appear here.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: visit.notes.length,
                          itemBuilder: (context, i) => _NoteBubble(note: visit.notes[visit.notes.length - 1 - i]),
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -3))],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            minLines: 1,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Add a care note…',
                              filled: true,
                              fillColor: AppColors.surfaceVariant,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _submit,
                          icon: const Icon(Icons.send_rounded),
                          style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _NoteBubble extends StatelessWidget {
  final CareNote note;
  const _NoteBubble({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(note.text, style: AppTextStyles.bodyLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 12, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(DateFormat('d MMM, h:mm a').format(note.createdAt), style: AppTextStyles.caption),
            ],
          ),
        ],
      ),
    );
  }
}
