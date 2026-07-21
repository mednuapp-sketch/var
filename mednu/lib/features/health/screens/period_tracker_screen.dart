import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/r.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/period_tracker_provider.dart';

// ── Brand colours ─────────────────────────────────────────────────────────────
const _kPink      = Color(0xFFE91E8C);
const _kPinkDark  = Color(0xFF880E4F);
const _kPinkLight = Color(0xFFFCE4EC);
const _kPurple    = Color(0xFF7B1FA2);
const _kGreen     = Color(0xFF388E3C);
const _kGreenBg   = Color(0xFFE8F5E9);

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

class PeriodTrackerScreen extends ConsumerWidget {
  const PeriodTrackerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gender gate
    final uid       = ref.watch(currentUserProvider).value?.uid ?? '';
    final userDoc   = ref.watch(userDocProvider(uid));
    final gender    = (userDoc.value?['gender'] as String? ?? '').toLowerCase();

    if (uid.isNotEmpty && userDoc.hasValue && gender == 'male') {
      return const _NotApplicableScreen();
    }

    final state = ref.watch(periodTrackerProvider);

    if (state.isLoading) {
      return Scaffold(
        backgroundColor: context.appBackground,
        body: const Center(child: CircularProgressIndicator(color: _kPink)),
      );
    }

    if (!state.onboardingComplete) {
      return const _OnboardingScreen();
    }

    return const _CalendarScreen();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Not Applicable (male users)
// ─────────────────────────────────────────────────────────────────────────────

class _NotApplicableScreen extends StatelessWidget {
  const _NotApplicableScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Period Tracker',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [_kPinkDark, _kPink]),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(R.p(context, 32)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🚹', style: TextStyle(fontSize: 64)),
              SizedBox(height: R.h(context, 24)),
              const Text('Not applicable for your profile',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 20,
                      fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              SizedBox(height: R.h(context, 12)),
              Text(
                'The period tracker is designed for users who menstruate. '
                'Your profile is set to Male.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                    color: context.appTextSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: R.h(context, 32)),
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

// ─────────────────────────────────────────────────────────────────────────────
// 4-Step Onboarding
// ─────────────────────────────────────────────────────────────────────────────

class _OnboardingScreen extends ConsumerStatefulWidget {
  const _OnboardingScreen();

  @override
  ConsumerState<_OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<_OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  int _cycleLength = 28;
  int _periodDuration = 5;
  String _flow = 'Medium';
  bool _hasBloodClots = false;

  void _next() {
    if (_page < 3) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await ref.read(periodTrackerProvider.notifier).completeOnboarding(
          cycleLength: _cycleLength,
          periodDuration: _periodDuration,
          defaultFlow: _flow,
          hasBloodClots: _hasBloodClots,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F5),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 20), R.p(context, 20), 0),
              child: Row(
                children: [
                  if (_page > 0)
                    GestureDetector(
                      onTap: () => _controller.previousPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut),
                      child: Container(
                        width: R.w(context, 38),
                        height: R.h(context, 38),
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(R.r(context, 12)),
                          boxShadow: [BoxShadow(color: _kPink.withValues(alpha: 0.15), blurRadius: 8)],
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            size: 16, color: _kPinkDark),
                      ),
                    )
                  else
                    SizedBox(width: R.w(context, 38)),
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: R.p(context, 14), vertical: R.p(context, 6)),
                    decoration: BoxDecoration(
                      color: _kPink.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(R.r(context, 20)),
                    ),
                    child: Text('${_page + 1} / 4',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w700, color: _kPinkDark)),
                  ),
                ],
              ),
            ),
            // Progress dots
            Padding(
              padding: EdgeInsets.symmetric(vertical: R.p(context, 20)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: EdgeInsets.symmetric(horizontal: R.p(context, 4)),
                    width: active ? R.w(context, 28) : R.w(context, 8),
                    height: R.h(context, 8),
                    decoration: BoxDecoration(
                      color: active ? _kPink : _kPink.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(R.r(context, 4)),
                    ),
                  );
                }),
              ),
            ),
            // Pages
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  _OnboardingPage(
                    emoji: '🌸',
                    question: 'How many days are in your average menstrual cycle?',
                    hint: 'Count from day 1 of your period to the day before your next period',
                    child: _NumberPicker(
                      value: _cycleLength,
                      min: 21,
                      max: 45,
                      unit: 'days',
                      onChanged: (v) => setState(() => _cycleLength = v),
                    ),
                  ),
                  _OnboardingPage(
                    emoji: '📅',
                    question: 'How many days does your period usually last?',
                    hint: 'Count from when bleeding starts to when it completely stops',
                    child: _NumberPicker(
                      value: _periodDuration,
                      min: 2,
                      max: 10,
                      unit: 'days',
                      onChanged: (v) => setState(() => _periodDuration = v),
                    ),
                  ),
                  _OnboardingPage(
                    emoji: '💧',
                    question: 'How would you describe your usual flow?',
                    hint: 'This helps us understand your cycle patterns better',
                    child: _OptionPicker(
                      options: const [
                        _PickerOption('Light', '💧', 'Few pads or tampons per day'),
                        _PickerOption('Medium', '💧💧', 'Regular pad or tampon changes'),
                        _PickerOption('Heavy', '💧💧💧', 'Frequent changes needed'),
                      ],
                      selected: _flow,
                      onChanged: (v) => setState(() => _flow = v),
                    ),
                  ),
                  _OnboardingPage(
                    emoji: '🩸',
                    question: 'Do you usually experience blood clots during your period?',
                    hint: 'Small clots are common; mention to a doctor if they are large',
                    child: _OptionPicker(
                      options: const [
                        _PickerOption('Yes', '✅', 'I notice clots in my flow'),
                        _PickerOption('No', '🚫', 'I do not experience clots'),
                      ],
                      selected: _hasBloodClots ? 'Yes' : 'No',
                      onChanged: (v) => setState(() => _hasBloodClots = v == 'Yes'),
                    ),
                  ),
                ],
              ),
            ),
            // Continue button
            Padding(
              padding: EdgeInsets.fromLTRB(R.p(context, 24), 0, R.p(context, 24), R.p(context, 28)),
              child: SizedBox(
                width: double.infinity,
                height: R.h(context, 54),
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPink,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: _kPink.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.r(context, 16))),
                  ),
                  child: Text(
                    _page < 3 ? 'Continue' : 'Get Started',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final String emoji;
  final String question;
  final String hint;
  final Widget child;

  const _OnboardingPage({
    required this.emoji,
    required this.question,
    required this.hint,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: R.p(context, 24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: R.h(context, 8)),
          Text(emoji, style: const TextStyle(fontSize: 56)),
          SizedBox(height: R.h(context, 20)),
          Text(
            question,
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 20,
                fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E),
                height: 1.4),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: R.h(context, 10)),
          Text(
            hint,
            style: TextStyle(
                fontFamily: 'Poppins', fontSize: 13,
                color: context.appTextSecondary, height: 1.5),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: R.h(context, 32)),
          child,
        ],
      ),
    );
  }
}

class _PickerOption {
  final String label;
  final String icon;
  final String desc;
  const _PickerOption(this.label, this.icon, this.desc);
}

class _OptionPicker extends StatelessWidget {
  final List<_PickerOption> options;
  final String selected;
  final ValueChanged<String> onChanged;

  const _OptionPicker({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: options.map((opt) {
        final active = selected == opt.label;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(opt.label);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: EdgeInsets.only(bottom: R.p(context, 14)),
            padding: EdgeInsets.all(R.p(context, 16)),
            decoration: BoxDecoration(
              color: active ? _kPink.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(R.r(context, 16)),
              border: Border.all(
                color: active ? _kPink : context.appBorder,
                width: active ? 2 : 1,
              ),
              boxShadow: active
                  ? [BoxShadow(color: _kPink.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))]
                  : [],
            ),
            child: Row(
              children: [
                Text(opt.icon, style: const TextStyle(fontSize: 28)),
                SizedBox(width: R.w(context, 14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(opt.label,
                          style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: active ? _kPink : context.appTextPrimary)),
                      Text(opt.desc,
                          style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12,
                              color: context.appTextSecondary)),
                    ],
                  ),
                ),
                if (active)
                  const Icon(Icons.check_circle_rounded, color: _kPink, size: 22),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _NumberPicker extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final String unit;
  final ValueChanged<int> onChanged;

  const _NumberPicker({
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CircleBtn(
          icon: Icons.remove_rounded,
          onTap: value > min ? () { HapticFeedback.selectionClick(); onChanged(value - 1); } : null,
        ),
        SizedBox(width: R.w(context, 28)),
        Column(
          children: [
            Text('$value',
                style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 52,
                    fontWeight: FontWeight.w800, color: _kPink)),
            Text(unit,
                style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 14,
                    color: context.appTextSecondary, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(width: 28),
        _CircleBtn(
          icon: Icons.add_rounded,
          onTap: value < max ? () { HapticFeedback.selectionClick(); onChanged(value + 1); } : null,
        ),
      ],
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _CircleBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? _kPink : context.appBorder,
          boxShadow: enabled
              ? [BoxShadow(color: _kPink.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))]
              : [],
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Calendar Screen
// ─────────────────────────────────────────────────────────────────────────────

class _CalendarScreen extends ConsumerStatefulWidget {
  const _CalendarScreen();

  @override
  ConsumerState<_CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<_CalendarScreen> {
  DateTime _displayMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final state    = ref.watch(periodTrackerProvider);
    final notifier = ref.read(periodTrackerProvider.notifier);

    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _FloHero(state: state),
                _CalendarWidget(
                  displayMonth: _displayMonth,
                  state: state,
                  onMonthChanged: (m) => setState(() => _displayMonth = m),
                  onDayTap: (date) => _showDaySheet(context, date, state, notifier),
                ),
                _Legend(),
                _PhaseTipsCard(state: state),
                _HistorySection(state: state, notifier: notifier),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showLogSheet(context, state, notifier),
        backgroundColor: _kPink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log Period',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        elevation: 6,
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 160,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => context.pop(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.white),
          onPressed: () => _showSettingsSheet(context),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_kPinkDark, _kPink],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Text('🌸', style: TextStyle(fontSize: 30)),
                          const SizedBox(height: 4),
                          Text('Period Tracker', style: AppTextStyles.onPrimaryH2),
                          Text('Track your cycle & stay informed',
                              style: AppTextStyles.onPrimaryBody),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettingsSheet(
        state: ref.read(periodTrackerProvider),
        notifier: ref.read(periodTrackerProvider.notifier),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flo-Style Hero  (circular ring + phase badge + stat pills)
// ─────────────────────────────────────────────────────────────────────────────

class _CycleRingPainter extends CustomPainter {
  final double progress; // 0.0 – 1.0
  final Color activeColor;
  final Color trackColor;
  final double strokeWidth;

  const _CycleRingPainter({
    required this.progress,
    required this.activeColor,
    required this.trackColor,
    this.strokeWidth = 15,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth / 2;
    final rect   = Rect.fromCircle(center: center, radius: radius);

    // Track ring
    canvas.drawArc(
      rect, 0, 2 * pi, false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    // Active arc
    if (progress > 0.01) {
      canvas.drawArc(
        rect, -pi / 2, 2 * pi * progress.clamp(0.0, 1.0), false,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CycleRingPainter o) =>
      o.progress != progress || o.activeColor != activeColor;
}

class _FloHero extends StatelessWidget {
  final PeriodTrackerState state;
  const _FloHero({required this.state});

  static const _phases = {
    'Menstruation': (_kPink,   _kPink,                  _kPinkLight,             '🩸'),
    'Follicular':   (Color(0xFF1E88E5), Color(0xFF1565C0), Color(0xFFE3F2FD), '🌱'),
    'Ovulation':    (_kPurple, _kPurple,                Color(0xFFF3E5F5),      '✨'),
    'Luteal':       (Color(0xFF00897B), Color(0xFF00695C), Color(0xFFE0F2F1), '🌙'),
  };

  @override
  Widget build(BuildContext context) {
    final hasData   = state.hasCycle;
    final cycleDay  = state.cycleDay;
    final cycleLen  = state.avgCycleLength;
    final progress  = hasData ? (cycleDay / cycleLen).clamp(0.0, 1.0) : 0.0;
    final phase     = state.currentPhase;
    final daysLeft  = state.daysToNextPeriod;
    final isOnPeriod = hasData && cycleDay <= state.periodDuration;
    final isFertile  = state.isInFertileWindow;

    final (ringColor, phaseColor, phaseBg, phaseEmoji) =
        _phases[phase] ?? (_phases['Luteal']!);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: ringColor.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          // ── Circular ring ──────────────────────────────────────────────────
          SizedBox(
            width: 190,
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(190, 190),
                  painter: _CycleRingPainter(
                    progress: progress,
                    activeColor: ringColor,
                    trackColor: ringColor.withValues(alpha: 0.10),
                  ),
                ),
                if (hasData)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isOnPeriod ? '$cycleDay' : '$daysLeft',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 44,
                          fontWeight: FontWeight.w800, color: ringColor,
                        ),
                      ),
                      Text(
                        isOnPeriod
                            ? 'Day of period'
                            : (daysLeft == 0 ? 'Period today!' : 'days until\nperiod'),
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12,
                          color: context.appTextSecondary, height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                else
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🌸', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 8),
                      Text('Log your\nfirst period',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            color: context.appTextSecondary, height: 1.4,
                          ),
                          textAlign: TextAlign.center),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Phase badge ────────────────────────────────────────────────────
          if (hasData) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: phaseBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(phaseEmoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Text(
                    phase,
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w700, color: phaseColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '· Day $cycleDay of $cycleLen',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 11,
                      color: phaseColor.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Stat pills ───────────────────────────────────────────────────
            Row(
              children: [
                _HeroPill(
                  icon: Icons.water_drop_rounded,
                  label: isOnPeriod ? 'Ends in' : 'Next period',
                  value: isOnPeriod
                      ? '${state.periodDuration - cycleDay + 1}d'
                      : (state.nextPeriodDate != null
                          ? DateFormat('MMM d').format(state.nextPeriodDate!)
                          : '—'),
                  color: _kPink,
                ),
                const SizedBox(width: 8),
                _HeroPill(
                  icon: Icons.eco_rounded,
                  label: 'Fertile',
                  value: isFertile ? 'Now 🟢' : _fertileLabel(state),
                  color: _kGreen,
                ),
                const SizedBox(width: 8),
                _HeroPill(
                  icon: Icons.radio_button_checked_rounded,
                  label: 'Ovulation',
                  value: _ovulationLabel(state),
                  color: _kPurple,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _fertileLabel(PeriodTrackerState s) {
    if (s.lastPeriodStart == null) return '—';
    final today       = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final fertileStart = s.lastPeriodStart!.add(const Duration(days: 11));
    final diff = fertileStart.difference(today).inDays;
    if (diff > 0) return 'in ${diff}d';
    final nextFertile = (s.nextPeriodDate ?? today).add(const Duration(days: 11));
    final nd = nextFertile.difference(today).inDays;
    return nd > 0 ? 'in ${nd}d' : '—';
  }

  String _ovulationLabel(PeriodTrackerState s) {
    if (s.lastPeriodStart == null) return '—';
    final today     = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final ovulation = s.lastPeriodStart!.add(const Duration(days: 13));
    final diff = ovulation.difference(today).inDays;
    if (diff == 0) return 'Today!';
    if (diff > 0) return 'in ${diff}d';
    final nextOv = (s.nextPeriodDate ?? today).add(const Duration(days: 13));
    final nd = nextOv.difference(today).inDays;
    return nd > 0 ? 'in ${nd}d' : '—';
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _HeroPill({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 15),
              const SizedBox(height: 5),
              Text(value,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w700, color: color,
                  )),
              Text(label,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 9,
                    color: context.appTextSecondary,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase Tips Card
// ─────────────────────────────────────────────────────────────────────────────

const _kPhaseTips = <String, List<String>>{
  'Menstruation': [
    'Rest and be gentle with yourself — your body is working hard 💆‍♀️',
    'Iron-rich foods like spinach can help replenish what you lose',
    'Light yoga or walking can ease cramps naturally',
    'Stay extra hydrated — aim for 8+ glasses of water today',
  ],
  'Follicular': [
    'Your energy is rising — a great time to start new projects 🌱',
    'Estrogen is boosting your mood, memory and creativity this week',
    'High-intensity workouts feel easier now — make the most of it',
    'Social energy is higher: connect with friends and loved ones',
  ],
  'Ovulation': [
    'You\'re at peak energy and confidence today ⚡',
    'Estrogen and testosterone peak — your skin may glow naturally',
    'Your body temperature rises slightly by ~0.2°C during ovulation',
    'Most fertile window: days 12–16 of your cycle',
  ],
  'Luteal': [
    'Progesterone rise brings calm and introspection 🌙',
    'Craving carbs? It\'s hormonal — choose complex carbs like oats',
    'Magnesium-rich foods (dark chocolate, nuts) ease PMS symptoms',
    'Gentle exercise like pilates or yoga suits this phase best',
  ],
};

class _PhaseTipsCard extends StatelessWidget {
  final PeriodTrackerState state;
  const _PhaseTipsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    if (!state.hasCycle) return const SizedBox.shrink();
    final phase = state.currentPhase;
    final tips  = _kPhaseTips[phase];
    if (tips == null || tips.isEmpty) return const SizedBox.shrink();

    final (color, bg, emoji) = switch (phase) {
      'Menstruation' => (_kPink,                  _kPinkLight,           '🩸'),
      'Follicular'   => (const Color(0xFF1565C0), const Color(0xFFE3F2FD), '🌱'),
      'Ovulation'    => (_kPurple,                const Color(0xFFF3E5F5), '✨'),
      _              => (const Color(0xFF00695C), const Color(0xFFE0F2F1), '🌙'),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$phase Phase Insights',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 13,
                          fontWeight: FontWeight.w700, color: color,
                        )),
                    Text('Personalised for your cycle',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 11,
                          color: color.withValues(alpha: 0.65),
                        )),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: tips.map((tip) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      width: 6, height: 6,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tip,
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            color: context.appTextSecondary, height: 1.5,
                          )),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Interactive Calendar
// ─────────────────────────────────────────────────────────────────────────────

class _CalendarWidget extends StatelessWidget {
  final DateTime displayMonth;
  final PeriodTrackerState state;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDayTap;

  const _CalendarWidget({
    required this.displayMonth,
    required this.state,
    required this.onMonthChanged,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final today         = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final periodDays    = state.loggedPeriodDays;
    final predictedDays = state.predictedPeriodDays;
    final fertileDays   = state.fertileDays;
    final ovulationDays = state.ovulationDays;

    final firstDay = DateTime(displayMonth.year, displayMonth.month, 1);
    final daysInMonth = DateTime(displayMonth.year, displayMonth.month + 1, 0).day;
    // Monday-first: leading empty cells
    final leading = (firstDay.weekday - 1) % 7;
    final totalCells = leading + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Month header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                _MonthNavBtn(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => onMonthChanged(
                      DateTime(displayMonth.year, displayMonth.month - 1)),
                ),
                const Spacer(),
                Text(
                  DateFormat('MMMM yyyy').format(displayMonth),
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 17,
                      fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
                ),
                const Spacer(),
                _MonthNavBtn(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => onMonthChanged(
                      DateTime(displayMonth.year, displayMonth.month + 1)),
                ),
              ],
            ),
          ),
          // Weekday labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                  .map((d) => Expanded(
                        child: Center(
                          child: Text(d,
                              style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: context.appTextSecondary)),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Day grid
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              children: List.generate(rows, (row) {
                return Row(
                  children: List.generate(7, (col) {
                    final index = row * 7 + col;
                    final dayNum = index - leading + 1;
                    if (dayNum < 1 || dayNum > daysInMonth) {
                      return const Expanded(child: SizedBox(height: 44));
                    }
                    final date = DateTime(displayMonth.year, displayMonth.month, dayNum);
                    return Expanded(
                      child: _DayCell(
                        date: date,
                        isToday: date == today,
                        isPeriod: periodDays.contains(date),
                        isPredicted: predictedDays.contains(date),
                        isFertile: fertileDays.contains(date),
                        isOvulation: ovulationDays.contains(date),
                        onTap: () => onDayTap(date),
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthNavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MonthNavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _kPinkLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _kPinkDark, size: 22),
        ),
      );
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final bool isPeriod;
  final bool isPredicted;
  final bool isFertile;
  final bool isOvulation;
  final VoidCallback onTap;

  const _DayCell({
    required this.date,
    required this.isToday,
    required this.isPeriod,
    required this.isPredicted,
    required this.isFertile,
    required this.isOvulation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color? bg;
    Color textColor = const Color(0xFF1A1A2E);
    bool hasBorder = false;
    Color borderColor = Colors.transparent;
    Color? dotColor;

    if (isPeriod) {
      bg = _kPink;
      textColor = Colors.white;
    } else if (isOvulation) {
      bg = _kPurple;
      textColor = Colors.white;
    } else if (isFertile) {
      bg = _kGreenBg;
      textColor = _kGreen;
      dotColor = _kGreen;
    } else if (isPredicted) {
      bg = _kPinkLight;
      textColor = _kPinkDark;
      hasBorder = true;
      borderColor = _kPink.withValues(alpha: 0.4);
    }

    if (isToday && bg == null) {
      hasBorder = true;
      borderColor = _kPink;
      textColor = _kPink;
    }

    final isPast = date.isBefore(
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(11),
          border: hasBorder ? Border.all(color: borderColor, width: 1.5) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: (isToday || isPeriod || isOvulation)
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: bg == null
                    ? (isPast ? context.appTextHint : textColor)
                    : textColor,
              ),
            ),
            if (dotColor != null) ...[
              const SizedBox(height: 2),
              Container(
                width: 4, height: 4,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Legend
// ─────────────────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _LegendItem(color: _kPink, label: 'Period'),
          _LegendItem(color: _kPinkLight, label: 'Predicted', borderColor: _kPink),
          _LegendItem(color: _kGreenBg, label: 'Fertile', textColor: _kGreen),
          _LegendItem(color: _kPurple, label: 'Ovulation'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final Color? borderColor;
  final Color? textColor;
  const _LegendItem({required this.color, required this.label, this.borderColor, this.textColor});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: borderColor != null ? Border.all(color: borderColor!, width: 1.5) : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: textColor ?? context.appTextSecondary)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// History Section
// ─────────────────────────────────────────────────────────────────────────────

class _HistorySection extends StatelessWidget {
  final PeriodTrackerState state;
  final PeriodTrackerNotifier notifier;
  const _HistorySection({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    if (state.entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text('Cycle History', style: AppTextStyles.h4),
        ),
        ...state.entries.take(5).map((e) => _EntryCard(
              entry: e,
              isLatest: e == state.entries.first,
              onEdit: () => _showEditSheet(context, e, state, notifier),
              onDelete: () => _confirmDelete(context, e.id, notifier),
            )),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  final PeriodEntry entry;
  final bool isLatest;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _EntryCard({
    required this.entry,
    required this.isLatest,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final duration = entry.endDate.difference(entry.startDate).inDays + 1;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        border: isLatest ? Border.all(color: _kPink.withValues(alpha: 0.4), width: 1.5) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _kPinkLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text('🌸', style: TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      DateFormat('MMM d, yyyy').format(entry.startDate),
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                          fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)),
                    ),
                    if (isLatest) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kPink.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Latest',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                                fontWeight: FontWeight.w700, color: _kPink)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.flowLevel} flow · $duration day${duration == 1 ? '' : 's'}'
                  '${entry.hasBloodClots ? ' · Clots' : ''}',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      color: context.appTextSecondary),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: context.appTextSecondary, size: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_rounded, size: 16, color: _kPink),
                    SizedBox(width: 8),
                    Text('Edit', style: TextStyle(fontFamily: 'Poppins')),
                  ])),
              const PopupMenuItem(value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_rounded, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(fontFamily: 'Poppins', color: Colors.red)),
                  ])),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Day tap sheet (shows info about tapped date)
// ─────────────────────────────────────────────────────────────────────────────

void _showDaySheet(
    BuildContext context, DateTime date, PeriodTrackerState state, PeriodTrackerNotifier notifier) {
  final isPeriod    = state.loggedPeriodDays.contains(date);
  final isFertile   = state.fertileDays.contains(date);
  final isOvulation = state.ovulationDays.contains(date);
  final isPredicted = state.predictedPeriodDays.contains(date);

  // Find entry that covers this date
  final PeriodEntry? entry = state.entries.cast<PeriodEntry?>().firstWhere(
    (e) => e != null && !date.isBefore(e.startDate) && !date.isAfter(e.endDate),
    orElse: () => null,
  );

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: context.appBorder, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(DateFormat('EEEE, MMMM d, yyyy').format(date),
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          if (isPeriod && entry != null)
            _DayInfoChip(color: _kPink, icon: '🩸',
                text: '${entry.flowLevel} flow · Day ${date.difference(entry.startDate).inDays + 1} of period'),
          if (isOvulation)
            _DayInfoChip(color: _kPurple, icon: '🥚', text: 'Ovulation day (estimated)'),
          if (isFertile && !isOvulation)
            _DayInfoChip(color: _kGreen, icon: '🌱', text: 'Fertile window (estimated)'),
          if (isPredicted)
            _DayInfoChip(color: _kPinkDark, icon: '📅', text: 'Predicted period start'),
          if (!isPeriod && !isFertile && !isOvulation && !isPredicted)
            _DayInfoChip(color: context.appTextSecondary, icon: '📆', text: 'No events on this day'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showLogSheet(context, state, notifier, prefilledStart: date);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Log Period Starting This Date',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _DayInfoChip extends StatelessWidget {
  final Color color;
  final String icon;
  final String text;
  const _DayInfoChip({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w500, color: color)),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Log / Edit Period Sheet
// ─────────────────────────────────────────────────────────────────────────────

void _showLogSheet(
  BuildContext context,
  PeriodTrackerState state,
  PeriodTrackerNotifier notifier, {
  DateTime? prefilledStart,
  PeriodEntry? editing,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LogPeriodSheet(
      state: state,
      notifier: notifier,
      prefilledStart: prefilledStart,
      editing: editing,
    ),
  );
}

void _showEditSheet(
  BuildContext context,
  PeriodEntry entry,
  PeriodTrackerState state,
  PeriodTrackerNotifier notifier,
) {
  _showLogSheet(context, state, notifier, editing: entry);
}

void _confirmDelete(BuildContext context, String id, PeriodTrackerNotifier notifier) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Delete Entry', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      content: const Text('Are you sure you want to delete this period entry?',
          style: TextStyle(fontFamily: 'Poppins')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins'))),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            notifier.deleteEntry(id);
          },
          child: const Text('Delete', style: TextStyle(fontFamily: 'Poppins', color: Colors.red)),
        ),
      ],
    ),
  );
}

// ─── Log Sheet widget ─────────────────────────────────────────────────────────

const _kSymptoms = [
  {'name': 'Cramps',         'icon': '😣'},
  {'name': 'Bloating',       'icon': '🤰'},
  {'name': 'Mood Swings',    'icon': '😤'},
  {'name': 'Headache',       'icon': '🤕'},
  {'name': 'Fatigue',        'icon': '😴'},
  {'name': 'Acne',           'icon': '😰'},
  {'name': 'Tender Breasts', 'icon': '💗'},
  {'name': 'Nausea',         'icon': '🤢'},
  {'name': 'Back Pain',      'icon': '🦵'},
  {'name': 'Insomnia',       'icon': '🌙'},
];

const _kMoods = [
  {'mood': 'Happy',     'emoji': '😊'},
  {'mood': 'Calm',      'emoji': '😌'},
  {'mood': 'Anxious',   'emoji': '😰'},
  {'mood': 'Irritable', 'emoji': '😤'},
  {'mood': 'Sad',       'emoji': '😢'},
  {'mood': 'Energetic', 'emoji': '⚡'},
];

class _LogPeriodSheet extends StatefulWidget {
  final PeriodTrackerState state;
  final PeriodTrackerNotifier notifier;
  final DateTime? prefilledStart;
  final PeriodEntry? editing;

  const _LogPeriodSheet({
    required this.state,
    required this.notifier,
    this.prefilledStart,
    this.editing,
  });

  @override
  State<_LogPeriodSheet> createState() => _LogPeriodSheetState();
}

class _LogPeriodSheetState extends State<_LogPeriodSheet> {
  late DateTime _startDate;
  late DateTime _endDate;
  late String _flow;
  late bool _bloodClots;
  late List<String> _symptoms;
  String? _mood;
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) {
      final e = widget.editing!;
      _startDate  = e.startDate;
      _endDate    = e.endDate;
      _flow       = e.flowLevel;
      _bloodClots = e.hasBloodClots;
      _symptoms   = List.from(e.symptoms);
      _mood       = e.mood;
      _notesCtrl.text = e.notes ?? '';
    } else {
      _startDate  = widget.prefilledStart ?? DateTime.now();
      _endDate    = _startDate.add(Duration(days: widget.state.periodDuration - 1));
      _flow       = widget.state.defaultFlow;
      _bloodClots = widget.state.defaultHasBloodClots;
      _symptoms   = [];
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date must be after start date')));
      return;
    }
    setState(() => _saving = true);
    if (widget.editing != null) {
      await widget.notifier.updateEntry(
        id: widget.editing!.id,
        startDate: _startDate,
        endDate: _endDate,
        flowLevel: _flow,
        hasBloodClots: _bloodClots,
        symptoms: _symptoms,
        mood: _mood,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
    } else {
      await widget.notifier.logPeriod(
        startDate: _startDate,
        endDate: _endDate,
        flowLevel: _flow,
        hasBloodClots: _bloodClots,
        symptoms: _symptoms,
        mood: _mood,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
    }
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.editing != null ? '✅ Entry updated' : '🌸 Period logged successfully'),
        backgroundColor: _kPink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _kPink),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate.add(Duration(days: widget.state.periodDuration - 1));
        }
      } else {
        _endDate = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: context.appBorder, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Text(widget.editing != null ? 'Edit Period' : 'Log Period',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  // Dates
                  _SheetSection(
                    title: 'Period Dates',
                    child: Row(
                      children: [
                        Expanded(child: _DateTile(
                          label: 'Start Date',
                          date: _startDate,
                          onTap: () => _pickDate(true),
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _DateTile(
                          label: 'End Date',
                          date: _endDate,
                          onTap: () => _pickDate(false),
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Flow
                  _SheetSection(
                    title: 'Flow Intensity',
                    child: Row(
                      children: ['Light', 'Medium', 'Heavy'].map((f) {
                        final active = _flow == f;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () { HapticFeedback.selectionClick(); setState(() => _flow = f); },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: active ? _kPink : context.appBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: active ? _kPink : context.appBorder),
                              ),
                              child: Column(
                                children: [
                                  Text(f == 'Light' ? '💧' : f == 'Medium' ? '💧💧' : '💧💧💧',
                                      style: const TextStyle(fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(f,
                                      style: TextStyle(
                                          fontFamily: 'Poppins', fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: active ? Colors.white : context.appTextSecondary)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Blood clots
                  _SheetSection(
                    title: 'Blood Clots',
                    child: Row(
                      children: ['Yes', 'No'].map((opt) {
                        final active = _bloodClots == (opt == 'Yes');
                        return Expanded(
                          child: GestureDetector(
                            onTap: () { HapticFeedback.selectionClick(); setState(() => _bloodClots = opt == 'Yes'); },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: EdgeInsets.only(right: opt == 'Yes' ? 6 : 0),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: active ? _kPink.withValues(alpha: 0.1) : context.appBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: active ? _kPink : context.appBorder,
                                    width: active ? 2 : 1),
                              ),
                              child: Center(
                                child: Text(opt,
                                    style: TextStyle(
                                        fontFamily: 'Poppins', fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: active ? _kPink : context.appTextSecondary)),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Symptoms
                  _SheetSection(
                    title: 'Symptoms (optional)',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _kSymptoms.map((s) {
                        final name     = s['name']!;
                        final selected = _symptoms.contains(name);
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              if (selected) {
                                _symptoms.remove(name);
                              } else {
                                _symptoms.add(name);
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: selected ? _kPink.withValues(alpha: 0.1) : context.appBackground,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: selected ? _kPink : context.appBorder,
                                  width: selected ? 2 : 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(s['icon']!, style: const TextStyle(fontSize: 14)),
                                const SizedBox(width: 5),
                                Text(name,
                                    style: TextStyle(
                                        fontFamily: 'Poppins', fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: selected ? _kPink : context.appTextPrimary)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Mood
                  _SheetSection(
                    title: 'Mood (optional)',
                    child: Row(
                      children: _kMoods.map((m) {
                        final mood     = m['mood']!;
                        final selected = _mood == mood;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _mood = selected ? null : mood);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 5),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: selected ? _kPink.withValues(alpha: 0.1) : context.appBackground,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: selected ? _kPink : context.appBorder,
                                    width: selected ? 2 : 1),
                              ),
                              child: Column(
                                children: [
                                  Text(m['emoji']!, style: const TextStyle(fontSize: 18)),
                                  const SizedBox(height: 2),
                                  Text(mood,
                                      style: TextStyle(
                                          fontFamily: 'Poppins', fontSize: 8,
                                          fontWeight: FontWeight.w600,
                                          color: selected ? _kPink : context.appTextSecondary)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Notes
                  _SheetSection(
                    title: 'Notes (optional)',
                    child: TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Any additional notes…',
                        hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            color: context.appTextHint),
                        filled: true,
                        fillColor: context.appBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.appBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.appBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kPink, width: 2),
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPink,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _kPink.withValues(alpha: 0.5),
                        elevation: 4,
                        shadowColor: _kPink.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Text(
                              widget.editing != null ? 'Update Entry' : 'Save Period',
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  const _DateTile({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.appBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.appBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      color: context.appTextSecondary, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 14, color: _kPink),
                  const SizedBox(width: 6),
                  Text(DateFormat('MMM d, yyyy').format(date),
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                          fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                ],
              ),
            ],
          ),
        ),
      );
}

class _SheetSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _SheetSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                  fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 10),
          child,
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsSheet extends StatefulWidget {
  final PeriodTrackerState state;
  final PeriodTrackerNotifier notifier;
  const _SettingsSheet({required this.state, required this.notifier});

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late int _cycleLength;
  late int _periodDuration;
  late String _defaultFlow;
  late bool _bloodClots;
  late bool _reminders;
  late int _reminderDays;

  @override
  void initState() {
    super.initState();
    _cycleLength    = widget.state.avgCycleLength;
    _periodDuration = widget.state.periodDuration;
    _defaultFlow    = widget.state.defaultFlow;
    _bloodClots     = widget.state.defaultHasBloodClots;
    _reminders      = widget.state.remindersEnabled;
    _reminderDays   = widget.state.reminderDaysBefore;
  }

  Future<void> _save() async {
    await widget.notifier.saveSettings(
      cycleLength: _cycleLength,
      periodDuration: _periodDuration,
      defaultFlow: _defaultFlow,
      defaultHasBloodClots: _bloodClots,
      remindersEnabled: _reminders,
      reminderDaysBefore: _reminderDays,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: context.appBorder, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  const Text('Cycle Settings',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  _SettingRow(
                    icon: Icons.loop_rounded,
                    label: 'Cycle Length',
                    value: '$_cycleLength days',
                    onDecrease: _cycleLength > 21 ? () => setState(() => _cycleLength--) : null,
                    onIncrease: _cycleLength < 45 ? () => setState(() => _cycleLength++) : null,
                  ),
                  const SizedBox(height: 14),
                  _SettingRow(
                    icon: Icons.water_drop_rounded,
                    label: 'Period Duration',
                    value: '$_periodDuration days',
                    onDecrease: _periodDuration > 2 ? () => setState(() => _periodDuration--) : null,
                    onIncrease: _periodDuration < 10 ? () => setState(() => _periodDuration++) : null,
                  ),
                  const SizedBox(height: 20),
                  const Text('Default Flow',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Row(
                    children: ['Light', 'Medium', 'Heavy'].map((f) {
                      final active = _defaultFlow == f;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _defaultFlow = f),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: active ? _kPink : context.appBackground,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: active ? _kPink : context.appBorder),
                            ),
                            child: Center(
                              child: Text(f,
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: active ? Colors.white : context.appTextSecondary)),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.appBackground,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.notifications_rounded, color: _kPink, size: 20),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('Period Reminders',
                                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
                            ),
                            Switch(
                              value: _reminders,
                              onChanged: (v) => setState(() => _reminders = v),
                              activeTrackColor: _kPink,
                              activeThumbColor: Colors.white,
                            ),
                          ],
                        ),
                        if (_reminders) ...[
                          const Divider(height: 20),
                          Row(
                            children: [
                              const Icon(Icons.alarm_rounded, color: _kPink, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text('Remind me $_reminderDays day${_reminderDays == 1 ? '' : 's'} before',
                                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500)),
                              ),
                              DropdownButton<int>(
                                value: _reminderDays,
                                underline: const SizedBox(),
                                items: [1, 2, 3, 5, 7].map((d) => DropdownMenuItem(
                                    value: d,
                                    child: Text('$d d', style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)))).toList(),
                                onChanged: (v) => setState(() => _reminderDays = v!),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPink,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Save Settings',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  const _SettingRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onDecrease,
    this.onIncrease,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.appBackground,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: _kPink, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            ),
            _SmallBtn(icon: Icons.remove_rounded, onTap: onDecrease),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(value,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                      fontWeight: FontWeight.w700, color: _kPink)),
            ),
            _SmallBtn(icon: Icons.add_rounded, onTap: onIncrease),
          ],
        ),
      );
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _SmallBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: onTap != null ? _kPink : context.appBorder,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      );
}
