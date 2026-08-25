import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../providers/water_tracker_provider.dart';
import '../services/health_notification_service.dart'
    show HealthNotificationService;
import '../../../core/utils/r.dart';

class WaterReminderScreen extends ConsumerWidget {
  const WaterReminderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(waterTrackerProvider);
    final notifier = ref.read(waterTrackerProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFFE3F2FD),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, state),
          SliverToBoxAdapter(
            child: state.isLoading
                ? const _LoadingBody()
                : _Body(state: state, notifier: notifier),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context, WaterTrackerState state) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: R.h(context, 210),
      backgroundColor: const Color(0xFF1565C0),
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => ctx.canPop() ? ctx.pop() : ctx.go(AppRoutes.healthDashboard),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF42A5F5)],
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
                    child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: R.h(context, 16)),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: R.w(context, 140),
                      height: R.h(context, 140),
                      child: CustomPaint(
                        painter: _WaterArcPainter(
                          progress: state.progress.clamp(0.0, 1.0),
                          trackColor: Colors.white.withValues(alpha: 0.18),
                          fillColors: const [
                            Color(0xFF42A5F5),
                            Color(0xFFE3F2FD),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: R.w(context, 108),
                      height: R.h(context, 108),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('💧', style: TextStyle(fontSize: R.sp(context, 20))),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${state.glassesLogged}/${state.goalGlasses}',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: R.sp(context, 20),
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            'glasses',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: R.sp(context, 10),
                                color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: R.h(context, 8)),
                Text(
                  '${state.totalMl} ml of ${state.goalMl} ml goal',
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                ),
                if (state.goalReached)
                  Padding(
                    padding: EdgeInsets.only(top: R.h(context, 4)),
                    child: const Text(
                      '🎉 Daily goal reached!',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
              ],
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
}

// ─── Water Arc Painter ────────────────────────────────────────────────────────

class _WaterArcPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final List<Color> fillColors;
  const _WaterArcPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.width / 2) - 8;
    const strokeWidth = 10.0;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // Track arc
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi, false, trackPaint);

    if (progress <= 0) return;

    // Gradient fill arc
    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: fillColors,
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + (2 * math.pi * progress),
        tileMode: TileMode.clamp,
      ).createShader(rect);
    canvas.drawArc(
        rect, -math.pi / 2, 2 * math.pi * progress, false, fillPaint);
  }

  @override
  bool shouldRepaint(_WaterArcPainter old) => old.progress != progress;
}

// ─── Loading ──────────────────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: R.h(context, 80)),
        child: const Center(
            child: CircularProgressIndicator(color: Color(0xFF1565C0))),
      );
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final WaterTrackerState state;
  final WaterTrackerNotifier notifier;

  const _Body({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(R.p(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LogButton(state: state, notifier: notifier),
          SizedBox(height: R.h(context, 14)),
          // Quick-add buttons
          _QuickAddButtons(notifier: notifier, state: state),
          SizedBox(height: R.h(context, 20)),
          // Reminder time picker tile
          _ReminderTimeTile(state: state, notifier: notifier),
          SizedBox(height: R.h(context, 20)),
          _SettingsCard(state: state, notifier: notifier),
          SizedBox(height: R.h(context, 20)),
          const Text("Today's Log", style: AppTextStyles.h4),
          SizedBox(height: R.h(context, 12)),
          _TodayLogList(state: state),
          SizedBox(height: R.h(context, 40)),
        ],
      ),
    );
  }
}

// ─── Log Button ───────────────────────────────────────────────────────────────

class _LogButton extends StatelessWidget {
  final WaterTrackerState state;
  final WaterTrackerNotifier notifier;
  const _LogButton({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: state.goalReached
          ? null
          : () async {
              await notifier.logWater();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('💧 ${state.glassSizeMl} ml logged!'),
                    backgroundColor: const Color(0xFF1565C0),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.r(context, 12))),
                  ),
                );
              }
            },
      child: AnimatedOpacity(
        opacity: state.goalReached ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(R.p(context, 20)),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF42A5F5)]),
            borderRadius: BorderRadius.circular(R.r(context, 20)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('💧', style: TextStyle(fontSize: 28)),
              SizedBox(width: R.w(context, 12)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.goalReached ? 'Goal Reached Today!' : 'Tap to Log Water',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  Text(
                    '${state.glassSizeMl} ml per glass',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Quick Add Buttons ────────────────────────────────────────────────────────

class _QuickAddButtons extends StatelessWidget {
  final WaterTrackerState state;
  final WaterTrackerNotifier notifier;
  const _QuickAddButtons({required this.state, required this.notifier});

  static const _amounts = [150, 250, 350];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Add',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1565C0),
          ),
        ),
        SizedBox(height: R.h(context, 8)),
        Row(
          children: _amounts.map((ml) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    right: ml != _amounts.last ? R.w(context, 8) : 0),
                child: GestureDetector(
                  onTap: state.goalReached
                      ? null
                      : () async {
                          HapticFeedback.mediumImpact();
                          // Calculate how many glasses match this ml and log
                          final glassSize = state.glassSizeMl > 0
                              ? state.glassSizeMl
                              : 250;
                          final count =
                              (ml / glassSize).ceil().clamp(1, 3);
                          for (int i = 0; i < count; i++) {
                            await notifier.logWater();
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('💧 ${ml}ml added!'),
                                backgroundColor: const Color(0xFF1565C0),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 1),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(R.r(context, 12))),
                              ),
                            );
                          }
                        },
                  child: AnimatedOpacity(
                    opacity: state.goalReached ? 0.4 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: R.p(context, 10), vertical: R.p(context, 11)),
                      decoration: BoxDecoration(
                        color: context.appSurface,
                        borderRadius: BorderRadius.circular(R.r(context, 14)),
                        border: Border.all(
                            color: const Color(0xFF1565C0)
                                .withValues(alpha: 0.35)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1565C0)
                                .withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.water_drop_rounded,
                              color: Color(0xFF1565C0), size: 20),
                          SizedBox(height: R.h(context, 4)),
                          Text(
                            '${ml}ml',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1565C0),
                            ),
                          ),
                        ],
                      ),
                    ),
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

// ─── Reminder Time Tile ───────────────────────────────────────────────────────

class _ReminderTimeTile extends StatelessWidget {
  final WaterTrackerState state;
  final WaterTrackerNotifier notifier;
  const _ReminderTimeTile({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final next = HealthNotificationService.nextReminderTime(
      state.reminderIntervalHours,
      startHour: state.reminderStartHour,
      startMinute: state.reminderStartMinute,
    );
    final displayTime = next != null ? DateFormat('h:mm a').format(next) : '--';

    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime:
              TimeOfDay(hour: state.reminderStartHour, minute: state.reminderStartMinute),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF1565C0),
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) {
          await notifier.setReminderStartTime(picked.hour, picked.minute);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: R.p(context, 16), vertical: R.p(context, 14)),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(R.r(context, 14)),
          border:
              Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1565C0).withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            width: R.w(context, 38),
            height: R.h(context, 38),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(R.r(context, 10)),
            ),
            child: const Icon(Icons.alarm_rounded,
                color: Color(0xFF1565C0), size: 20),
          ),
          SizedBox(width: R.w(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Next Reminder',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1565C0),
                  ),
                ),
                Text(
                  displayTime,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: Color(0xFF1565C0), size: 20),
        ]),
      ),
    );
  }
}

// ─── Notification Permission Banner ───────────────────────────────────────────

class _NotifStatusBanner extends StatefulWidget {
  const _NotifStatusBanner();

  @override
  State<_NotifStatusBanner> createState() => _NotifStatusBannerState();
}

class _NotifStatusBannerState extends State<_NotifStatusBanner> {
  bool? _notifGranted;

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    final n = await HealthNotificationService.hasNotificationPermission();
    if (mounted) {
      setState(() {
        _notifGranted = n;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_notifGranted == null) return const SizedBox.shrink();
    if (_notifGranted!) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.only(bottom: R.h(context, 12)),
      padding: EdgeInsets.all(R.p(context, 14)),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(R.r(context, 14)),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.orange.shade700, size: 20),
            SizedBox(width: R.w(context, 8)),
            const Expanded(
              child: Text('Action needed for reminders',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ]),
          SizedBox(height: R.h(context, 8)),
          const _IssueItem('Notification permission denied — reminders cannot fire.'),
          SizedBox(height: R.h(context, 10)),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await HealthNotificationService.requestNotificationPermission();
                await _checkAll();
              },
              icon: Icon(Icons.settings_rounded, color: Colors.orange.shade700),
              label: Text('Fix now',
                  style: TextStyle(
                      color: Colors.orange.shade700, fontFamily: 'Poppins')),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.orange.shade400),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.r(context, 10))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueItem extends StatelessWidget {
  final String text;
  const _IssueItem(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: R.h(context, 4)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12)),
            ),
          ],
        ),
      );
}

// ─── Settings Card ────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final WaterTrackerState state;
  final WaterTrackerNotifier notifier;
  const _SettingsCard({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Settings', style: AppTextStyles.h4),
        SizedBox(height: R.h(context, 12)),

        // Show warning banner only when reminders are meant to be on
        if (state.remindersEnabled) const _NotifStatusBanner(),

        Container(
          padding: EdgeInsets.all(R.p(context, 16)),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(R.r(context, 16))),
          child: Column(
            children: [
              // Daily goal
              _SettingsRow(
                icon: Icons.flag_rounded,
                label: 'Daily Goal',
                trailing: _GoalPicker(state: state, notifier: notifier),
              ),
              Divider(height: R.h(context, 20)),

              // Reminders toggle
              Row(children: [
                const Icon(Icons.notifications_rounded,
                    color: Color(0xFF1565C0)),
                SizedBox(width: R.w(context, 12)),
                const Expanded(
                  child: Text('Reminders',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600)),
                ),
                Switch(
                  value: state.remindersEnabled,
                  onChanged: (v) async {
                    final ok = await notifier.setRemindersEnabled(v);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text(
                            '⚠️ Notification permission denied. Please enable in Settings.'),
                        backgroundColor: Colors.red.shade700,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ));
                    }
                  },
                  activeThumbColor: const Color(0xFF1565C0),
                ),
              ]),

              if (state.remindersEnabled) ...[
                const Divider(height: 20),
                // Interval
                Row(children: [
                  const Icon(Icons.access_time_rounded,
                      color: Color(0xFF1565C0)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Remind every ${state.reminderIntervalHours == 1 ? '1 hour' : '${state.reminderIntervalHours} hours'}',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                    ),
                  ),
                  DropdownButton<int>(
                    value: state.reminderIntervalHours,
                    underline: const SizedBox(),
                    items: [1, 2, 3]
                        .map((h) => DropdownMenuItem(
                            value: h,
                            child: Text(h == 1 ? '1 hour' : '$h hours',
                                style: const TextStyle(
                                    fontFamily: 'Poppins', fontSize: 13))))
                        .toList(),
                    onChanged: (v) => notifier.setReminderInterval(v!),
                  ),
                ]),
                // Next reminder time chip
                Builder(builder: (_) {
                  final next = HealthNotificationService.nextReminderTime(
                    state.reminderIntervalHours,
                    startHour: state.reminderStartHour,
                    startMinute: state.reminderStartMinute,
                  );
                  if (next == null) return const SizedBox.shrink();
                  final label = DateFormat('h:mm a').format(next);
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      const Icon(Icons.alarm_rounded,
                          size: 16, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        'Next reminder at $label',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.w500),
                      ),
                    ]),
                  );
                }),
              ],

              const Divider(height: 20),

              // Glass size
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.local_drink_rounded,
                        color: Color(0xFF1565C0)),
                    const SizedBox(width: 12),
                    Text(
                      'Glass size: ${state.glassSizeMl} ml',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                    ),
                  ]),
                  Slider(
                    value: state.glassSizeMl.toDouble(),
                    min: 150,
                    max: 500,
                    divisions: 7,
                    label: '${state.glassSizeMl} ml',
                    activeColor: const Color(0xFF1565C0),
                    onChanged: (v) => notifier.setGlassSizeMl(v.round()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Reusable setting row ──────────────────────────────────────────────────────

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget trailing;
  const _SettingsRow(
      {required this.icon, required this.label, required this.trailing});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: const Color(0xFF1565C0)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
        ),
        trailing,
      ]);
}

class _GoalPicker extends StatelessWidget {
  final WaterTrackerState state;
  final WaterTrackerNotifier notifier;
  const _GoalPicker({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) => DropdownButton<int>(
        value: state.goalGlasses,
        underline: const SizedBox(),
        items: [6, 7, 8, 9, 10, 12]
            .map((g) => DropdownMenuItem(
                value: g,
                child: Text('$g glasses',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 13))))
            .toList(),
        onChanged: (v) => notifier.setGoalGlasses(v!),
      );
}

// ─── Today's Log ──────────────────────────────────────────────────────────────

class _TodayLogList extends StatelessWidget {
  final WaterTrackerState state;
  const _TodayLogList({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.todayLogs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Center(
          child: Column(children: [
            const Text('💧', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Text(
              "No water logged today yet.\nTap the button above to start!",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: context.appTextHint),
            ),
          ]),
        ),
      );
    }

    final timeFmt = DateFormat('h:mm a');
    return Container(
      decoration:
          BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: state.todayLogs.asMap().entries.map((e) {
          final log = e.value;
          final isLast = e.key == state.todayLogs.length - 1;
          return Column(children: [
            ListTile(
              leading: const Text('💧', style: TextStyle(fontSize: 22)),
              title: Text(timeFmt.format(log.loggedAt),
                  style: AppTextStyles.labelLarge),
              subtitle: Text('${log.amountMl} ml logged',
                  style: AppTextStyles.bodySmall),
              trailing: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF1565C0)),
            ),
            if (!isLast) const Divider(height: 1, indent: 16, endIndent: 16),
          ]);
        }).toList(),
      ),
    );
  }
}
