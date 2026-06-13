import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/period_tracker_provider.dart';

class PeriodTrackerScreen extends ConsumerWidget {
  const PeriodTrackerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ── Gender gate ─────────────────────────────────────────────────────────
    final userAsync = ref.watch(currentUserProvider);
    final uid = userAsync.value?.uid ?? '';
    final userDocAsync = ref.watch(userDocProvider(uid));
    final gender = (userDocAsync.value?['gender'] as String? ?? '').toLowerCase();

    if (uid.isNotEmpty && userDocAsync.hasValue && gender == 'male') {
      return _NotApplicableScreen();
    }

    final state = ref.watch(periodTrackerProvider);
    final notifier = ref.read(periodTrackerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(
            child: state.isLoading
                ? const _LoadingBody()
                : _Body(state: state, notifier: notifier),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 180,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => context.pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF880E4F), Color(0xFFE91E8C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🌸', style: TextStyle(fontSize: 36)),
                  const SizedBox(height: 8),
                  Text('Period Tracker', style: AppTextStyles.onPrimaryH2),
                  Text('Track your cycle & symptoms', style: AppTextStyles.onPrimaryBody),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Not Applicable (male user) ──────────────────────────────────────────────

class _NotApplicableScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Period Tracker',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF880E4F), Color(0xFFE91E8C)],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🚹', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 24),
              const Text(
                'Not applicable for your profile',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'The period tracker is designed for users who menstruate. '
                'Your profile is set to Male.',
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 14, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFFE91E8C))),
      );
}

// ─── Main Body ───────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final PeriodTrackerState state;
  final PeriodTrackerNotifier notifier;

  const _Body({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!state.hasCycle) _SetupPrompt(notifier: notifier),
          if (state.hasCycle) ...[
            _CycleCard(state: state),
            const SizedBox(height: 20),
            _ActionRow(state: state, notifier: notifier),
            const SizedBox(height: 20),
            _SymptomsSection(state: state, notifier: notifier),
            const SizedBox(height: 20),
            _MoodSection(state: state, notifier: notifier),
            const SizedBox(height: 20),
            _InsightsSection(state: state),
            const SizedBox(height: 20),
            _SettingsSection(state: state, notifier: notifier),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─── Setup Prompt (no cycle logged yet) ──────────────────────────────────────

class _SetupPrompt extends StatelessWidget {
  final PeriodTrackerNotifier notifier;
  const _SetupPrompt({required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF880E4F), Color(0xFFE91E8C)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Text('🌸', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text(
            'Start Tracking Your Cycle',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Log your first period start date to begin tracking your cycle, symptoms, and get personalized insights.',
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 13, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _showLogPeriodSheet(context, notifier),
            icon: const Icon(Icons.add_rounded, color: Color(0xFFE91E8C)),
            label: const Text('Log Period Start',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE91E8C))),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Cycle Card ──────────────────────────────────────────────────────────────

class _CycleCard extends StatelessWidget {
  final PeriodTrackerState state;
  const _CycleCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF880E4F), Color(0xFFE91E8C)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CycleStat('Day', '${state.cycleDay}', 'of ${state.avgCycleLength}'),
              Container(width: 1, height: 50, color: Colors.white.withValues(alpha:0.3)),
              _CycleStat('Phase', state.currentPhase, 'window'),
              Container(width: 1, height: 50, color: Colors.white.withValues(alpha:0.3)),
              _CycleStat('Next Period', '${state.daysToNextPeriod}', 'days away'),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Menstruation',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: Colors.white70)),
                  Text('Follicular',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: Colors.white70)),
                  Text('Ovulation',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: Colors.white70)),
                  Text('Luteal',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: state.cycleDay / state.avgCycleLength,
                  minHeight: 14,
                  backgroundColor: Colors.white.withValues(alpha:0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.currentCycle != null)
            Text(
              'Started: ${DateFormat('MMM d, yyyy').format(state.currentCycle!.startDate)}  •  ${state.currentCycle!.flowLevel} flow',
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: Colors.white70),
            ),
        ],
      ),
    );
  }
}

class _CycleStat extends StatelessWidget {
  final String label, value, sub;
  const _CycleStat(this.label, this.value, this.sub);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          Text(sub,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 10, color: Colors.white70)),
        ],
      );
}

// ─── Action Row ──────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final PeriodTrackerState state;
  final PeriodTrackerNotifier notifier;
  const _ActionRow({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _showLogPeriodSheet(context, notifier),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Log Period Start'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE91E8C)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showCycleHistory(context, state),
            icon: const Icon(Icons.calendar_month_rounded,
                color: Color(0xFFE91E8C)),
            label: const Text('View History',
                style: TextStyle(color: Color(0xFFE91E8C))),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE91E8C))),
          ),
        ),
      ],
    );
  }
}

// ─── Symptoms ────────────────────────────────────────────────────────────────

const _kSymptoms = [
  {'name': 'Cramps', 'icon': '😣'},
  {'name': 'Bloating', 'icon': '🤰'},
  {'name': 'Mood Swings', 'icon': '😤'},
  {'name': 'Headache', 'icon': '🤕'},
  {'name': 'Fatigue', 'icon': '😴'},
  {'name': 'Acne', 'icon': '😰'},
  {'name': 'Tender Breasts', 'icon': '💗'},
  {'name': 'Nausea', 'icon': '🤢'},
  {'name': 'Back Pain', 'icon': '🦵'},
  {'name': 'Insomnia', 'icon': '🌙'},
];

class _SymptomsSection extends StatelessWidget {
  final PeriodTrackerState state;
  final PeriodTrackerNotifier notifier;
  const _SymptomsSection({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Today\'s Symptoms', style: AppTextStyles.h4),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _kSymptoms.map((s) {
            final name = s['name']!;
            final selected = state.todaySymptoms.contains(name);
            return GestureDetector(
              onTap: () => notifier.toggleSymptom(name),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFE91E8C).withValues(alpha:0.1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFE91E8C)
                        : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s['icon']!, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      name,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? const Color(0xFFE91E8C)
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        if (state.todaySymptoms.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${state.todaySymptoms.length} symptom${state.todaySymptoms.length == 1 ? '' : 's'} logged today',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: const Color(0xFFE91E8C),
                  fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }
}

// ─── Mood ────────────────────────────────────────────────────────────────────

const _kMoods = [
  {'mood': 'Happy', 'emoji': '😊'},
  {'mood': 'Calm', 'emoji': '😌'},
  {'mood': 'Anxious', 'emoji': '😰'},
  {'mood': 'Irritable', 'emoji': '😤'},
  {'mood': 'Sad', 'emoji': '😢'},
  {'mood': 'Energetic', 'emoji': '⚡'},
];

class _MoodSection extends StatelessWidget {
  final PeriodTrackerState state;
  final PeriodTrackerNotifier notifier;
  const _MoodSection({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Today\'s Mood', style: AppTextStyles.h4),
        const SizedBox(height: 12),
        Row(
          children: _kMoods.map((m) {
            final mood = m['mood']!;
            final selected = state.todayMood == mood;
            return Expanded(
              child: GestureDetector(
                onTap: () => notifier.setMood(mood),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFE91E8C).withValues(alpha:0.1)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? const Color(0xFFE91E8C) : AppColors.border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(m['emoji']!, style: const TextStyle(fontSize: 20)),
                      const SizedBox(height: 2),
                      Text(
                        mood,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? const Color(0xFFE91E8C)
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── Insights ────────────────────────────────────────────────────────────────

class _InsightsSection extends StatelessWidget {
  final PeriodTrackerState state;
  const _InsightsSection({required this.state});

  List<Map<String, dynamic>> _buildInsights() {
    final phase = state.currentPhase;
    return [
      {
        'icon': '🌸',
        'title': 'Fertile Window',
        'desc': state.isInFertileWindow
            ? 'You are currently in your fertile window (days 12-16).'
            : 'Your fertile window is around days 12-16 of your cycle.',
        'color': const Color(0xFFE91E8C),
      },
      {
        'icon': '💊',
        'title': 'PMS Alert',
        'desc': phase == 'Luteal'
            ? 'You\'re in the luteal phase — PMS symptoms may appear soon.'
            : 'PMS symptoms typically begin around day ${state.avgCycleLength - 7} of your cycle.',
        'color': const Color(0xFF7B1FA2),
      },
      {
        'icon': '🏃',
        'title': 'Energy Level',
        'desc': phase == 'Follicular'
            ? 'High energy phase — ideal for intense workouts!'
            : phase == 'Ovulation'
                ? 'Peak energy! Great time for challenging activities.'
                : phase == 'Menstruation'
                    ? 'Rest and gentle movement recommended.'
                    : 'Energy may dip as your period approaches.',
        'color': const Color(0xFF2E7D32),
      },
      if (state.nextPeriodDate != null)
        {
          'icon': '📅',
          'title': 'Next Period',
          'desc':
              'Expected around ${DateFormat('MMM d').format(state.nextPeriodDate!)} (in ${state.daysToNextPeriod} days).',
          'color': const Color(0xFF1565C0),
        },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cycle Insights', style: AppTextStyles.h4),
        const SizedBox(height: 12),
        ..._buildInsights().map(
          (insight) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Text(insight['icon'] as String,
                    style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        insight['title'] as String,
                        style: AppTextStyles.labelLarge
                            .copyWith(color: insight['color'] as Color),
                      ),
                      Text(insight['desc'] as String,
                          style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Settings ────────────────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  final PeriodTrackerState state;
  final PeriodTrackerNotifier notifier;
  const _SettingsSection({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cycle Settings', style: AppTextStyles.h4),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              // Average cycle length
              Row(
                children: [
                  const Icon(Icons.loop_rounded, color: Color(0xFFE91E8C)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Avg Cycle Length: ${state.avgCycleLength} days',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                    ),
                  ),
                  DropdownButton<int>(
                    value: state.avgCycleLength.clamp(21, 35),
                    underline: const SizedBox(),
                    items: List.generate(15, (i) => i + 21)
                        .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text('$d d',
                                style: const TextStyle(
                                    fontFamily: 'Poppins', fontSize: 13))))
                        .toList(),
                    onChanged: (v) => notifier.setCycleLength(v!),
                  ),
                ],
              ),
              const Divider(height: 20),

              // Reminders toggle
              Row(
                children: [
                  const Icon(Icons.notifications_rounded,
                      color: Color(0xFFE91E8C)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Period Reminders',
                        style: TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                  ),
                  Switch(
                    value: state.remindersEnabled,
                    onChanged: (v) => notifier.setRemindersEnabled(v),
                    activeColor: const Color(0xFFE91E8C),
                  ),
                ],
              ),

              if (state.remindersEnabled) ...[
                const Divider(height: 20),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        color: Color(0xFFE91E8C)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Remind ${state.reminderDaysBefore} day${state.reminderDaysBefore == 1 ? '' : 's'} before',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                      ),
                    ),
                    DropdownButton<int>(
                      value: state.reminderDaysBefore,
                      underline: const SizedBox(),
                      items: [1, 2, 3, 5, 7]
                          .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text('$d day${d == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 13))))
                          .toList(),
                      onChanged: (v) => notifier.setReminderDaysBefore(v!),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Shared bottom sheets ────────────────────────────────────────────────────

void _showLogPeriodSheet(BuildContext context, PeriodTrackerNotifier notifier) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text('🌸', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 8),
          const Text('Log Period Start',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Select your flow level for today',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _FlowOption('Light', '💧', const Color(0xFFE3F2FD),
                  const Color(0xFF1565C0), notifier, context),
              _FlowOption('Medium', '💧💧', const Color(0xFFFCE4EC),
                  const Color(0xFFE91E8C), notifier, context),
              _FlowOption('Heavy', '💧💧💧', const Color(0xFF880E4F).withValues(alpha:0.1),
                  const Color(0xFF880E4F), notifier, context),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

class _FlowOption extends StatelessWidget {
  final String label, emoji;
  final Color bg, border;
  final PeriodTrackerNotifier notifier;
  final BuildContext parentContext;

  const _FlowOption(
      this.label, this.emoji, this.bg, this.border, this.notifier, this.parentContext);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        Navigator.pop(context);
        await notifier.logPeriodStart(label);
        if (parentContext.mounted) {
          ScaffoldMessenger.of(parentContext).showSnackBar(
            SnackBar(
              content: Text('🌸 Period logged — $label flow'),
              backgroundColor: const Color(0xFFE91E8C),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border.withValues(alpha:0.4), width: 1.5),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: border)),
          ],
        ),
      ),
    );
  }
}

void _showCycleHistory(BuildContext context, PeriodTrackerState state) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.85,
      minChildSize: 0.35,
      builder: (_, ctrl) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('Cycle History',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            if (state.recentCycles.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('No cycles recorded yet.',
                      style: TextStyle(fontFamily: 'Poppins', color: AppColors.textHint)),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: ctrl,
                  itemCount: state.recentCycles.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = state.recentCycles[i];
                    return ListTile(
                      leading: const Text('🌸', style: TextStyle(fontSize: 22)),
                      title: Text(
                        DateFormat('MMM d, yyyy').format(c.startDate),
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('${c.flowLevel} flow',
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                      trailing: i == 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE91E8C).withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Current',
                                  style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFE91E8C))),
                            )
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
