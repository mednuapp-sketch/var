import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../../core/widgets/ux_widgets.dart';

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});
  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final Map<String, bool> _enabled = {
    'Mon': true, 'Tue': true, 'Wed': true, 'Thu': true, 'Fri': true,
    'Sat': false, 'Sun': false,
  };
  final Map<String, TimeOfDay> _startTimes = {
    for (var d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'])
      d: const TimeOfDay(hour: 9, minute: 0),
    'Sat': const TimeOfDay(hour: 10, minute: 0),
    'Sun': const TimeOfDay(hour: 10, minute: 0),
  };
  final Map<String, TimeOfDay> _endTimes = {
    for (var d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'])
      d: const TimeOfDay(hour: 17, minute: 0),
    'Sat': const TimeOfDay(hour: 14, minute: 0),
    'Sun': const TimeOfDay(hour: 14, minute: 0),
  };

  int _slotDuration = 30;
  bool _loading = true;
  bool _saving = false;

  late final Map<String, DateTime> _weekDates = _buildWeekDates();

  Map<String, DateTime> _buildWeekDates() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return {
      for (var i = 0; i < _days.length; i++)
        _days[i]: monday.add(Duration(days: i)),
    };
  }

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('doctors')
          .doc(uid)
          .get();
      final data = doc.data();
      final avail = data?['availability'] as Map<String, dynamic>?;
      if (avail != null) {
        _slotDuration = (avail['slotDuration'] as num?)?.toInt() ?? 30;
        final schedule = avail['schedule'] as Map<String, dynamic>?;
        if (schedule != null) {
          for (final day in _days) {
            final ds = schedule[day] as Map<String, dynamic>?;
            if (ds != null) {
              _enabled[day] = ds['enabled'] as bool? ?? false;
              final start = ds['start'] as String?;
              final end = ds['end'] as String?;
              if (start != null) _startTimes[day] = _parseTime(start);
              if (end != null) _endTimes[day] = _parseTime(end);
            }
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  TimeOfDay _parseTime(String t) {
    final parts = t.split(':');
    if (parts.length == 2) {
      return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }
    return const TimeOfDay(hour: 9, minute: 0);
  }

  String _formatTimeForStorage(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _saveAvailability() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;

    for (final day in _days) {
      if (_enabled[day] == true) {
        final start = _startTimes[day]!;
        final end = _endTimes[day]!;
        final startMins = start.hour * 60 + start.minute;
        final endMins = end.hour * 60 + end.minute;
        if (endMins <= startMins) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$day: End time must be after start time'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      final schedule = {
        for (final day in _days)
          day: {
            'enabled': _enabled[day],
            'start': _formatTimeForStorage(_startTimes[day]!),
            'end': _formatTimeForStorage(_endTimes[day]!),
          }
      };

      await FirebaseFirestore.instance
          .collection('doctors')
          .doc(uid)
          .update({
        'availability': {
          'slotDuration': _slotDuration,
          'schedule': schedule,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Availability saved successfully ✅'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to save: $e'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(String day, bool isStart) async {
    final initial =
        isStart ? _startTimes[day]! : _endTimes[day]!;
    final picked =
        await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTimes[day] = picked;
        } else {
          _endTimes[day] = picked;
        }
      });
    }
  }

  String _formatDisplay(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int _slotsForDay(String day) {
    if (_enabled[day] != true) return 0;
    final start = _startTimes[day]!;
    final end = _endTimes[day]!;
    final totalMins = (end.hour * 60 + end.minute) -
        (start.hour * 60 + start.minute);
    if (totalMins <= 0) return 0;
    return totalMins ~/ _slotDuration;
  }

  int get _totalWeeklySlots =>
      _days.fold(0, (s, d) => s + _slotsForDay(d));

  int get _workingDays =>
      _days.where((d) => _enabled[d] == true).length;

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildSkeleton();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Gradient App Bar ─────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 130,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              _saving
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: _saveAvailability,
                      icon: const Icon(Icons.save_rounded,
                          color: Colors.white, size: 16),
                      label: const Text(
                        'Save',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                          fontSize: 14,
                        ),
                      ),
                    ),
            ],
            flexibleSpace: const FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _AvailabilityHeader(),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Slot Duration Card ───────────────────
                  FadeInSlide(
                    child: _SlotDurationCard(
                      selected: _slotDuration,
                      onSelect: (v) =>
                          setState(() => _slotDuration = v),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Weekly Summary ───────────────────────
                  FadeInSlide(
                    delay: const Duration(milliseconds: 60),
                    child: _WeeklySummaryBanner(
                      totalSlots: _totalWeeklySlots,
                      workingDays: _workingDays,
                      slotDuration: _slotDuration,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Week Header ──────────────────────────
                  FadeInSlide(
                    delay: const Duration(milliseconds: 80),
                    child: Row(children: [
                      Text('Weekly Schedule', style: AppTextStyles.h4),
                      const Spacer(),
                      InfoChip(
                        icon: Icons.calendar_view_week_rounded,
                        label: DateFormat('MMM d').format(
                            _weekDates['Mon']!),
                        color: AppColors.secondary,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),

                  // ── Day Cards ────────────────────────────
                  ..._days.asMap().entries.map((entry) {
                    final i = entry.key;
                    final day = entry.value;
                    final date = _weekDates[day]!;
                    final isToday =
                        _isSameDay(date, DateTime.now());
                    return FadeInSlide(
                      delay: Duration(milliseconds: 100 + i * 40),
                      child: _DayCard(
                        day: day,
                        date: date,
                        isToday: isToday,
                        enabled: _enabled[day]!,
                        start: _startTimes[day]!,
                        end: _endTimes[day]!,
                        slotCount: _slotsForDay(day),
                        onToggle: (v) =>
                            setState(() => _enabled[day] = v),
                        onPickStart: () => _pickTime(day, true),
                        onPickEnd: () => _pickTime(day, false),
                        formatTime: _formatDisplay,
                      ),
                    );
                  }),

                  const SizedBox(height: 8),

                  // ── Save Button ──────────────────────────
                  FadeInSlide(
                    delay: const Duration(milliseconds: 420),
                    child: GradientButton(
                      label: 'Save Availability',
                      icon: Icons.save_rounded,
                      isLoading: _saving,
                      onTap: _saving ? null : _saveAvailability,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() => Scaffold(
        backgroundColor: AppColors.background,
        body: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 160, 16, 16),
          child: Column(
            children: List.generate(
              6,
              (_) => const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: SkeletonBox(
                    width: double.infinity, height: 72, radius: 16),
              ),
            ),
          ),
        ),
      );
}

// ──────────────────────────────────────────────────────────────
// Availability Header
// ──────────────────────────────────────────────────────────────

class _AvailabilityHeader extends StatelessWidget {
  const _AvailabilityHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -28,
            right: -28,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.calendar_month_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'My Availability',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'Set your weekly consultation schedule',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Slot Duration Card
// ──────────────────────────────────────────────────────────────

class _SlotDurationCard extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _SlotDurationCard(
      {required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      radius: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.timer_rounded,
                color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Appointment Slot Duration',
                style: AppTextStyles.labelLarge),
            Text('Time per consultation',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textHint)),
          ]),
        ]),
        const SizedBox(height: 14),
        Row(
          children: [15, 30, 45, 60].map((min) {
            final isSelected = selected == min;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(min),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [
                              Color(0xFFC2185B),
                              Color(0xFF7B1FA2)
                            ],
                          )
                        : null,
                    color: isSelected ? null : AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary
                                  .withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$min',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'min',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          color: isSelected
                              ? Colors.white70
                              : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Weekly Summary Banner
// ──────────────────────────────────────────────────────────────

class _WeeklySummaryBanner extends StatelessWidget {
  final int totalSlots;
  final int workingDays;
  final int slotDuration;
  const _WeeklySummaryBanner({
    required this.totalSlots,
    required this.workingDays,
    required this.slotDuration,
  });

  @override
  Widget build(BuildContext context) {
    final totalHours = (totalSlots * slotDuration) ~/ 60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded,
            color: AppColors.primary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: AppColors.primary,
              ),
              children: [
                TextSpan(
                  text: '$totalSlots slots',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: ' · $workingDays working day${workingDays == 1 ? '' : 's'}'
                      ' · ~$totalHours hr${totalHours == 1 ? '' : 's'}/week',
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Day Card
// ──────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  final String day;
  final DateTime date;
  final bool isToday;
  final bool enabled;
  final TimeOfDay start;
  final TimeOfDay end;
  final int slotCount;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final String Function(TimeOfDay) formatTime;

  const _DayCard({
    required this.day,
    required this.date,
    required this.isToday,
    required this.enabled,
    required this.start,
    required this.end,
    required this.slotCount,
    required this.onToggle,
    required this.onPickStart,
    required this.onPickEnd,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isToday
              ? AppColors.primary.withValues(alpha: 0.5)
              : enabled
                  ? AppColors.primary.withValues(alpha: 0.25)
                  : AppColors.divider,
          width: isToday ? 1.8 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: enabled
                ? AppColors.primary.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Day label with date
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(
                day,
                style: AppTextStyles.labelLarge.copyWith(
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Today',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ]),
            Text(
              DateFormat('MMM d').format(date),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: enabled
                    ? AppColors.primary.withValues(alpha: 0.8)
                    : AppColors.textHint,
              ),
            ),
          ]),
          const Spacer(),
          // Slot count badge
          if (enabled && slotCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$slotCount slots',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          // Toggle
          _DayToggle(value: enabled, onChanged: onToggle),
        ]),

        // Time pickers (only when enabled)
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: enabled
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              _TimeButton(
                label: 'Start',
                time: formatTime(start),
                icon: Icons.play_arrow_rounded,
                onTap: onPickStart,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  width: 20,
                  height: 1,
                  color: AppColors.border,
                ),
              ),
              _TimeButton(
                label: 'End',
                time: formatTime(end),
                icon: Icons.stop_rounded,
                onTap: onPickEnd,
              ),
            ]),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ]),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Day Toggle
// ──────────────────────────────────────────────────────────────

class _DayToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _DayToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 46,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          gradient: value
              ? const LinearGradient(
                  colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: value ? null : const Color(0xFFDDE1E7),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: const Color(0xFFC2185B).withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Time Button
// ──────────────────────────────────────────────────────────────

class _TimeButton extends StatelessWidget {
  final String label;
  final String time;
  final IconData icon;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.time,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => TapScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.18)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Poppins',
                ),
              ),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                ),
              ),
            ]),
          ]),
        ),
      );
}
