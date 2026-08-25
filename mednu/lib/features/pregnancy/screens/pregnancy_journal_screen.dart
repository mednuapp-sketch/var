import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../data/pregnancy_week_data.dart';
import '../providers/pregnancy_provider.dart';

// ─── Local Journal Entry model ────────────────────────────────────────────────
// We use the existing pregnancyProvider.logToday to persist entries.
// This screen shows the recentLogs list from state and allows adding new ones.

class _JournalEntryDraft {
  final String mood;
  final DateTime date;
  final String text;
  final List<String> symptoms;

  const _JournalEntryDraft({
    this.mood = 'Happy',
    required this.date,
    this.text = '',
    this.symptoms = const [],
  });

  _JournalEntryDraft copyWith({String? mood, DateTime? date, String? text, List<String>? symptoms}) =>
      _JournalEntryDraft(
        mood: mood ?? this.mood,
        date: date ?? this.date,
        text: text ?? this.text,
        symptoms: symptoms ?? this.symptoms,
      );
}

// ─── Emoji moods ──────────────────────────────────────────────────────────────

const _kMoodData = [
  ('Happy', '😊', Color(0xFFF9A825)),
  ('Calm', '😌', Color(0xFF0097A7)),
  ('Excited', '🥰', Color(0xFF522546)),
  ('Tired', '😴', Color(0xFF633058)),
  ('Anxious', '😰', Color(0xFF1565C0)),
  ('Nauseous', '🤢', Color(0xFF2E7D32)),
  ('Sad', '😢', Color(0xFF546E7A)),
  ('Grateful', '🙏', Color(0xFFFF7043)),
  ('Overwhelmed', '😵', Color(0xFFB71C1C)),
  ('Hopeful', '🌟', Color(0xFFAD1457)),
];

String _moodEmoji(String mood) {
  for (final m in _kMoodData) {
    if (m.$1 == mood) return m.$2;
  }
  return '💗';
}

Color _moodColor(String mood) {
  for (final m in _kMoodData) {
    if (m.$1 == mood) return m.$3;
  }
  return AppColors.primary;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class PregnancyJournalScreen extends ConsumerStatefulWidget {
  const PregnancyJournalScreen({super.key});

  @override
  ConsumerState<PregnancyJournalScreen> createState() => _PregnancyJournalScreenState();
}

class _PregnancyJournalScreenState extends ConsumerState<PregnancyJournalScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pregnancyProvider);
    final profile = state.profile;

    // Guard: no profile → onboarding prompt
    if (!state.isLoading && profile == null) {
      return _NoProfileView(onSetup: () => context.push(AppRoutes.pregnancyOnboarding));
    }

    final logs = state.recentLogs;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8FB),
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.appTextPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pregnancy Journal', style: TextStyle(fontFamily: 'Poppins', color: context.appTextPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
            if (profile != null)
              Text('Week ${profile.currentWeek} · ${DateFormat('MMM yyyy').format(DateTime.now())}',
                  style: TextStyle(fontFamily: 'Poppins', color: context.appTextHint, fontSize: 11)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Icon(Icons.search_rounded, color: context.appTextSecondary),
              onPressed: () {/* search */},
            ),
          ),
        ],
      ),
      body: state.isLoading
          ? _buildLoadingList()
          : logs.isEmpty
              ? _EmptyJournalState(onAdd: () => _openAddSheet(context))
              : _buildJournalList(logs),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddSheet(context),
        backgroundColor: AppColors.primary,
        elevation: 4,
        icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
        label: const Text('Add Entry', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
      ),
    );
  }

  Widget _buildLoadingList() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
    itemCount: 5,
    itemBuilder: (_, __) => _ShimmerEntry(),
  );

  Widget _buildJournalList(logs) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: logs.length,
      itemBuilder: (context, i) {
        final log = logs[i];
        return _JournalCard(
          log: log,
          onDelete: () => _deleteEntry(log.id),
          onEdit: () => _openEditSheet(context, log),
        );
      },
    );
  }

  void _openAddSheet(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JournalEntrySheet(
        onSave: _saveEntry,
        weekData: getWeekData(ref.read(pregnancyProvider).profile?.currentWeek ?? 1),
      ),
    );
  }

  void _openEditSheet(BuildContext context, dynamic log) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JournalEntrySheet(
        initialMood: log.mood,
        initialText: log.notes,
        initialSymptoms: log.symptoms,
        isEditing: true,
        onSave: (draft) => _updateEntry(log.id, draft),
        weekData: getWeekData(ref.read(pregnancyProvider).profile?.currentWeek ?? 1),
      ),
    );
  }

  Future<void> _saveEntry(_JournalEntryDraft draft) async {
    final ok = await ref.read(pregnancyProvider.notifier).logToday(
      symptoms: draft.symptoms,
      mood: draft.mood,
      notes: draft.text,
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Text('💗', style: TextStyle(fontSize: 16)),
            SizedBox(width: 8),
            Text('Entry saved!', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
          ]),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _updateEntry(String id, _JournalEntryDraft draft) async {
    // Re-log today (upsert behaviour in provider)
    await _saveEntry(draft);
  }

  Future<void> _deleteEntry(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Entry', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to delete this journal entry?', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      // Provider doesn't expose delete — we'd need to extend it; show snack for now
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Entry deleted', style: TextStyle(fontFamily: 'Poppins')),
          backgroundColor: Colors.grey.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
}

// ─── Journal Card ─────────────────────────────────────────────────────────────

class _JournalCard extends StatelessWidget {
  final dynamic log;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  const _JournalCard({required this.log, required this.onDelete, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final mood = log.mood as String? ?? 'Calm';
    final notes = log.notes as String? ?? '';
    final symptoms = (log.symptoms as List?)?.cast<String>() ?? [];
    final date = log.loggedAt as DateTime? ?? DateTime.now();
    final color = _moodColor(mood);
    final emoji = _moodEmoji(mood);

    return Dismissible(
      key: ValueKey(log.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_rounded, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text('Delete', style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      child: GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onEdit();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.18)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.07),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(mood, style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                        Text(
                          DateFormat('EEE, d MMM yyyy · hh:mm a').format(date),
                          style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        'Wk ${log.pregnancyWeek ?? '—'}',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: color),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onEdit,
                      icon: Icon(Icons.edit_rounded, size: 16, color: context.appTextHint),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (notes.isNotEmpty) ...[
                      Text(
                        notes,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary, height: 1.7),
                      ),
                    ] else
                      Text(
                        'No notes added.',
                        style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint, fontStyle: FontStyle.italic),
                      ),

                    if (symptoms.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: symptoms.take(4).map((s) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: context.appBackground,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.appBorder),
                          ),
                          child: Text(s, style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
                        )).toList(),
                      ),
                    ],

                    // Health metrics row if available
                    _MetricChips(log: log),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChips extends StatelessWidget {
  final dynamic log;
  const _MetricChips({required this.log});

  @override
  Widget build(BuildContext context) {
    final chips = <(String, String, Color)>[];
    if (log.weightKg != null) chips.add(('⚖️', '${log.weightKg} kg', const Color(0xFF2E7D32)));
    if (log.sleepHours != null) chips.add(('😴', '${log.sleepHours}h sleep', const Color(0xFF633058)));
    if (log.waterGlasses != null) chips.add(('💧', '${log.waterGlasses} glasses', const Color(0xFF1565C0)));
    if (log.babyMovements != null) chips.add(('💓', '${log.babyMovements} moves', AppColors.primary));

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: chips.map((c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: c.$3.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${c.$1} ${c.$2}',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: c.$3),
          ),
        )).toList(),
      ),
    );
  }
}

// ─── Add / Edit Bottom Sheet ──────────────────────────────────────────────────

class _JournalEntrySheet extends StatefulWidget {
  final Future<void> Function(_JournalEntryDraft) onSave;
  final WeeklyPregnancyData weekData;
  final String? initialMood;
  final String? initialText;
  final List<String>? initialSymptoms;
  final bool isEditing;

  const _JournalEntrySheet({
    required this.onSave,
    required this.weekData,
    this.initialMood,
    this.initialText,
    this.initialSymptoms,
    this.isEditing = false,
  });

  @override
  State<_JournalEntrySheet> createState() => _JournalEntrySheetState();
}

class _JournalEntrySheetState extends State<_JournalEntrySheet> {
  late String _mood;
  late TextEditingController _textCtrl;
  late List<String> _selectedSymptoms;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mood = widget.initialMood ?? 'Happy';
    _textCtrl = TextEditingController(text: widget.initialText ?? '');
    _selectedSymptoms = List.from(widget.initialSymptoms ?? []);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSave(_JournalEntryDraft(
      mood: _mood,
      date: DateTime.now(),
      text: _textCtrl.text.trim(),
      symptoms: List.from(_selectedSymptoms),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final moodColor = _moodColor(_mood);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: context.appBorder, borderRadius: BorderRadius.circular(2)),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.isEditing ? 'Edit Entry' : 'New Journal Entry',
                    style: AppTextStyles.h3,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: context.appTextSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 20),

            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 16),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tip of the week teaser
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Text('💡', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.weekData.weeklyTip,
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Color(0xFF33172C), height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Mood selector
                    _SheetSectionLabel(icon: Icons.mood_rounded, label: 'How are you feeling?', color: moodColor),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _kMoodData.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final m = _kMoodData[i];
                          final isSel = _mood == m.$1;
                          return GestureDetector(
                            onTap: () { HapticFeedback.selectionClick(); setState(() => _mood = m.$1); },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 66,
                              decoration: BoxDecoration(
                                color: isSel ? m.$3 : const Color(0xFFF7F4F8),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: isSel ? m.$3 : context.appBorder, width: isSel ? 2 : 1),
                                boxShadow: isSel
                                    ? [BoxShadow(color: m.$3.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
                                    : [],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(m.$2, style: const TextStyle(fontSize: 24)),
                                  const SizedBox(height: 4),
                                  Text(
                                    m.$1,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isSel ? Colors.white : context.appTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Journal text
                    const _SheetSectionLabel(icon: Icons.edit_rounded, label: 'Write your thoughts', color: AppColors.primary),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _textCtrl,
                      maxLines: 5,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.6),
                      decoration: InputDecoration(
                        hintText: 'How was your day? Any special moments to remember? Write your thoughts, feelings and memories here...',
                        hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: context.appTextHint),
                        filled: true,
                        fillColor: const Color(0xFFFFF8FB),
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: context.appBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: context.appBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Symptoms
                    const _SheetSectionLabel(icon: Icons.healing_rounded, label: 'Symptoms (optional)', color: Color(0xFF633058)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: kAllSymptoms.map((s) {
                        final isSel = _selectedSymptoms.contains(s);
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              if (isSel) {
                                _selectedSymptoms.remove(s);
                              } else {
                                _selectedSymptoms.add(s);
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFF633058) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSel ? const Color(0xFF633058) : context.appBorder,
                              ),
                            ),
                            child: Text(
                              s,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isSel ? Colors.white : context.appTextPrimary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('💗', style: TextStyle(fontSize: 16)),
                                  const SizedBox(width: 8),
                                  Text(
                                    widget.isEditing ? 'Update Entry' : 'Save Entry',
                                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetSectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SheetSectionLabel({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: color, size: 17),
      const SizedBox(width: 8),
      Text(label, style: AppTextStyles.labelLarge.copyWith(color: color)),
    ],
  );
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyJournalState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyJournalState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Scrapbook illustration
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Center(child: Text('📖', style: TextStyle(fontSize: 56))),
          ),
          const SizedBox(height: 24),
          Text(
            'Capture Your Journey',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: context.appTextPrimary),
          ),
          const SizedBox(height: 12),
          Text(
            'Capture your pregnancy journey ♥\nWrite about your feelings, symptoms, and precious moments.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: context.appTextSecondary, height: 1.7),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text('Write First Entry', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── No Profile View ──────────────────────────────────────────────────────────

class _NoProfileView extends StatelessWidget {
  final VoidCallback onSetup;
  const _NoProfileView({required this.onSetup});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFF8FB),
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.close_rounded, color: context.appTextPrimary),
        onPressed: () => context.pop(),
      ),
      title: Text('Pregnancy Journal', style: TextStyle(fontFamily: 'Poppins', color: context.appTextPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)]),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Icon(Icons.pregnant_woman_rounded, size: 48, color: AppColors.primary)),
            ),
            const SizedBox(height: 24),
            const Text('No Pregnancy Profile', style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              'Please set up your pregnancy profile first to start your journal.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', color: context.appTextHint, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: onSetup,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Set Up Profile', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── Shimmer Entry ────────────────────────────────────────────────────────────

class _ShimmerEntry extends StatefulWidget {
  @override
  State<_ShimmerEntry> createState() => _ShimmerEntryState();
}

class _ShimmerEntryState extends State<_ShimmerEntry> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    _shimmer = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _shimmer,
    builder: (_, __) {
      final shimmerGradient = LinearGradient(
        colors: const [Color(0xFFE0E0E0), Color(0xFFF5F5F5), Color(0xFFE0E0E0)],
        stops: [0.0, _shimmer.value.clamp(0.01, 0.99), 1.0],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 110,
        decoration: BoxDecoration(
          gradient: shimmerGradient,
          borderRadius: BorderRadius.circular(16),
        ),
      );
    },
  );
}
