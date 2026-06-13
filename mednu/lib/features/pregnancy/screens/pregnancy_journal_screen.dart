import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../data/pregnancy_week_data.dart';
import '../providers/pregnancy_provider.dart';

class PregnancyJournalScreen extends ConsumerStatefulWidget {
  const PregnancyJournalScreen({super.key});

  @override
  ConsumerState<PregnancyJournalScreen> createState() =>
      _PregnancyJournalScreenState();
}

class _PregnancyJournalScreenState
    extends ConsumerState<PregnancyJournalScreen> {
  final List<String> _symptoms = [];
  String _mood = 'Calm';
  final _weightCtrl    = TextEditingController();
  final _bpSCtrl       = TextEditingController();
  final _bpDCtrl       = TextEditingController();
  final _sugarCtrl     = TextEditingController();
  final _movementsCtrl = TextEditingController();
  final _sleepCtrl     = TextEditingController();
  final _waterCtrl     = TextEditingController();
  final _notesCtrl     = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _weightCtrl.dispose();
    _bpSCtrl.dispose();
    _bpDCtrl.dispose();
    _sugarCtrl.dispose();
    _movementsCtrl.dispose();
    _sleepCtrl.dispose();
    _waterCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await ref.read(pregnancyProvider.notifier).logToday(
      symptoms: List.from(_symptoms),
      weightKg: double.tryParse(_weightCtrl.text),
      bpSystolic: _bpSCtrl.text.trim().isEmpty ? null : _bpSCtrl.text.trim(),
      bpDiastolic: _bpDCtrl.text.trim().isEmpty ? null : _bpDCtrl.text.trim(),
      sugarLevel: double.tryParse(_sugarCtrl.text),
      babyMovements: int.tryParse(_movementsCtrl.text),
      mood: _mood,
      sleepHours: double.tryParse(_sleepCtrl.text),
      waterGlasses: int.tryParse(_waterCtrl.text),
      notes: _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Journal saved successfully! 💗'),
          backgroundColor: AppColors.primary,
        ),
      );
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save. Check your connection and try again.'),
          backgroundColor: Color(0xFFEF5350),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pregnancyProvider);
    final profile = state.profile;

    // Guard: no profile → redirect to onboarding
    if (!state.isLoading && profile == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFF0F5),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
            onPressed: () => context.pop(),
          ),
          title: const Text('Today\'s Journal',
              style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w700, fontSize: 16)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.pregnant_woman_rounded,
                    size: 64, color: AppColors.primary),
                const SizedBox(height: 16),
                const Text('No Pregnancy Profile',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                  'Set up your pregnancy profile first to start logging your daily health journal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textHint, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.push(AppRoutes.pregnancyOnboarding),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Set Up Profile',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final week = profile?.currentWeek ?? 1;
    final weekData = getWeekData(week);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Today\'s Journal',
                style: TextStyle(
                    color: Color(0xFF1A1A2E), fontWeight: FontWeight.w700, fontSize: 16)),
            Text('Week $week',
                style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const Text('Save',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Weekly tip
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFCE4EC), Color(0xFFF3E5F5)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Text('💡', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(weekData.weeklyTip,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF880E4F), height: 1.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Mood
            _sectionLabel('How are you feeling today?', Icons.mood_rounded, AppColors.primary),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kAllMoods.map((m) {
                final sel = m == _mood;
                return GestureDetector(
                  onTap: () => setState(() => _mood = m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: sel ? AppColors.primary : AppColors.border),
                    ),
                    child: Text(
                      '${_moodEmoji(m)} $m',
                      style: TextStyle(
                        fontSize: 12,
                        color: sel ? Colors.white : AppColors.textPrimary,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Symptoms
            _sectionLabel('Symptoms Today', Icons.healing_rounded, const Color(0xFF7B1FA2)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kAllSymptoms.map((s) {
                final sel = _symptoms.contains(s);
                return FilterChip(
                  label: Text(s,
                      style: TextStyle(
                        fontSize: 11,
                        color: sel ? Colors.white : AppColors.textPrimary,
                      )),
                  selected: sel,
                  selectedColor: const Color(0xFF7B1FA2),
                  backgroundColor: Colors.white,
                  checkmarkColor: Colors.white,
                  side: BorderSide(
                      color: sel ? const Color(0xFF7B1FA2) : AppColors.border),
                  onSelected: (v) => setState(() {
                    if (v) { _symptoms.add(s); } else { _symptoms.remove(s); }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Health Metrics
            _sectionLabel('Health Metrics', Icons.monitor_heart_rounded, const Color(0xFFEF5350)),
            const SizedBox(height: 10),
            _metricsCard(),
            const SizedBox(height: 20),

            // Baby Movements
            _sectionLabel('Baby Movements', Icons.child_care_rounded, const Color(0xFFFFA726)),
            const SizedBox(height: 10),
            _field(
              ctrl: _movementsCtrl,
              label: 'Movements felt (count)',
              keyboardType: TextInputType.number,
              prefix: const Icon(Icons.favorite_rounded, size: 18, color: Color(0xFFC2185B)),
            ),
            const SizedBox(height: 20),

            // Lifestyle
            _sectionLabel('Lifestyle', Icons.self_improvement_rounded, const Color(0xFF26C6DA)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _field(
                    ctrl: _sleepCtrl,
                    label: 'Sleep (hours)',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    ctrl: _waterCtrl,
                    label: 'Water (glasses)',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Notes
            _sectionLabel('Personal Notes', Icons.edit_note_rounded, const Color(0xFF66BB6A)),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Write your thoughts, feelings, or anything you want to remember...',
                hintStyle: const TextStyle(fontSize: 13),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _metricsCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
    ),
    child: Column(
      children: [
        Row(children: [
          Expanded(
            child: _field(
              ctrl: _weightCtrl,
              label: 'Weight (kg)',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _field(
              ctrl: _sugarCtrl,
              label: 'Sugar (mg/dL)',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _field(
              ctrl: _bpSCtrl,
              label: 'BP Systolic',
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _field(
              ctrl: _bpDCtrl,
              label: 'BP Diastolic',
              keyboardType: TextInputType.number,
            ),
          ),
        ]),
      ],
    ),
  );

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    TextInputType? keyboardType,
    Widget? prefix,
  }) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          prefixIcon: prefix,
          filled: true,
          fillColor: const Color(0xFFF7F4F8),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      );

  Widget _sectionLabel(String title, IconData icon, Color color) => Row(
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 8),
      Text(title,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color)),
    ],
  );

  String _moodEmoji(String mood) {
    const map = {
      'Happy': '😊', 'Calm': '😌', 'Anxious': '😰', 'Excited': '🥰',
      'Tired': '😴', 'Irritable': '😤', 'Sad': '😢', 'Hopeful': '🌟',
      'Overwhelmed': '😵', 'Grateful': '🙏',
    };
    return map[mood] ?? '💗';
  }
}
