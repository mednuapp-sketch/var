import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../providers/water_tracker_provider.dart';
import '../services/health_notification_service.dart'
    show HealthNotificationService;

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
          _buildAppBar(state),
          SliverToBoxAdapter(
            child: state.isLoading
                ? const _LoadingBody()
                : _Body(state: state, notifier: notifier),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(WaterTrackerState state) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 210,
      backgroundColor: const Color(0xFF1565C0),
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => ctx.pop(),
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CircularProgressIndicator(
                        value: state.progress,
                        strokeWidth: 10,
                        backgroundColor: Colors.white.withValues(alpha:0.2),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('💧', style: TextStyle(fontSize: 26)),
                        Text(
                          '${state.glassesLogged}/${state.goalGlasses}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const Text(
                          'glasses',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${state.totalMl} ml of ${state.goalMl} ml goal',
                  style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                ),
                if (state.goalReached)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
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
        ),
      ),
    );
  }
}

// ─── Loading ──────────────────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LogButton(state: state, notifier: notifier),
          const SizedBox(height: 20),
          _SettingsCard(state: state, notifier: notifier),
          const SizedBox(height: 20),
          Text("Today's Log", style: AppTextStyles.h4),
          const SizedBox(height: 12),
          _TodayLogList(state: state),
          const SizedBox(height: 40),
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
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
      child: AnimatedOpacity(
        opacity: state.goalReached ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF42A5F5)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('💧', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
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

// ─── Notification Permission Banner ───────────────────────────────────────────

class _NotifStatusBanner extends StatefulWidget {
  const _NotifStatusBanner();

  @override
  State<_NotifStatusBanner> createState() => _NotifStatusBannerState();
}

class _NotifStatusBannerState extends State<_NotifStatusBanner> {
  bool? _notifGranted;
  bool? _exactAlarm;

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    final n = await HealthNotificationService.hasNotificationPermission();
    final e = await HealthNotificationService.hasExactAlarmPermission();
    if (mounted) {
      setState(() {
        _notifGranted = n;
        _exactAlarm = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_notifGranted == null) return const SizedBox.shrink();
    final allGood = _notifGranted! && (_exactAlarm ?? true);
    if (allGood) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.orange.shade700, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Action needed for reminders',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 8),
          if (!(_notifGranted ?? true))
            _IssueItem('Notification permission denied — reminders cannot fire.'),
          if (!(_exactAlarm ?? true))
            _IssueItem('Exact alarm permission missing — reminders may fire late.'),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                if (!(_notifGranted ?? true)) {
                  await HealthNotificationService.requestNotificationPermission();
                }
                if (!(_exactAlarm ?? true)) {
                  await HealthNotificationService.requestExactAlarmPermission();
                }
                await _checkAll();
              },
              icon: Icon(Icons.settings_rounded, color: Colors.orange.shade700),
              label: Text('Fix now',
                  style: TextStyle(
                      color: Colors.orange.shade700, fontFamily: 'Poppins')),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.orange.shade400),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
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
        padding: const EdgeInsets.only(bottom: 4),
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
        Text('Settings', style: AppTextStyles.h4),
        const SizedBox(height: 12),

        // Show warning banner only when reminders are meant to be on
        if (state.remindersEnabled) const _NotifStatusBanner(),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              // Daily goal
              _SettingsRow(
                icon: Icons.flag_rounded,
                label: 'Daily Goal',
                trailing: _GoalPicker(state: state, notifier: notifier),
              ),
              const Divider(height: 20),

              // Reminders toggle
              Row(children: [
                const Icon(Icons.notifications_rounded,
                    color: Color(0xFF1565C0)),
                const SizedBox(width: 12),
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
                  activeColor: const Color(0xFF1565C0),
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
                      state.reminderIntervalHours);
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
        child: const Center(
          child: Column(children: [
            Text('💧', style: TextStyle(fontSize: 32)),
            SizedBox(height: 8),
            Text(
              "No water logged today yet.\nTap the button above to start!",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: AppColors.textHint),
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
