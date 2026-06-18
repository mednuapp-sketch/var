import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
    for (var d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']) d: const TimeOfDay(hour: 9, minute: 0),
    'Sat': const TimeOfDay(hour: 10, minute: 0),
    'Sun': const TimeOfDay(hour: 10, minute: 0),
  };
  final Map<String, TimeOfDay> _endTimes = {
    for (var d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']) d: const TimeOfDay(hour: 17, minute: 0),
    'Sat': const TimeOfDay(hour: 14, minute: 0),
    'Sun': const TimeOfDay(hour: 14, minute: 0),
  };

  int _slotDuration = 30;
  bool _loading = true;
  bool _saving = false;

  /// Real calendar date for each weekday of the current week (Mon-Sun),
  /// so the schedule always reflects "this week" in real time.
  late final Map<String, DateTime> _weekDates = _buildWeekDates();

  Map<String, DateTime> _buildWeekDates() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // DateTime.weekday: Mon=1 .. Sun=7, matching _days order.
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return {
      for (var i = 0; i < _days.length; i++) _days[i]: monday.add(Duration(days: i)),
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
      final doc = await FirebaseFirestore.instance.collection('doctors').doc(uid).get();
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
    // Stored as "HH:mm"
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

    // Validate: enabled days must have start < end
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

      await FirebaseFirestore.instance.collection('doctors').doc(uid).update({
        'availability': {
          'slotDuration': _slotDuration,
          'schedule': schedule,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Availability saved ✅'),
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
    final initial = isStart ? _startTimes[day]! : _endTimes[day]!;
    final picked = await showTimePicker(context: context, initialTime: initial);
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
    final totalMins = (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute);
    if (totalMins <= 0) return 0;
    return totalMins ~/ _slotDuration;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 160, 16, 16),
              child: Column(
                children: List.generate(5, (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: SkeletonBox(width: double.infinity, height: 72, radius: 16),
                )),
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 130,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  actions: [
                    if (_saving)
                      const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextButton(
                          onPressed: _saveAvailability,
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins',
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.pin,
                    background: Container(
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
                            top: -20,
                            right: -20,
                            child: Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha:0.06),
                              ),
                            ),
                          ),
                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha:0.18),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.calendar_month_rounded,
                                        color: Colors.white, size: 22),
                                  ),
                                  const SizedBox(width: 12),
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
                                        ),
                                      ),
                                      Text(
                                        'Set your weekly schedule',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 12,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                // Slot duration
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha:0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Appointment Slot Duration', style: AppTextStyles.labelLarge),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [15, 30, 45, 60].map((min) => ChoiceChip(
                        label: Text('$min min'),
                        selected: _slotDuration == min,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: _slotDuration == min ? Colors.white : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                        onSelected: (_) => setState(() => _slotDuration = min),
                      )).toList(),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // Weekly summary
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha:0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withValues(alpha:0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Weekly slots: ${_days.fold(0, (s, d) => s + _slotsForDay(d))} total '
                        '(${_days.where((d) => _enabled[d] == true).length} working days)',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.primary),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                Text('Weekly Schedule', style: AppTextStyles.h4),
                const SizedBox(height: 12),
                ..._days.map((day) {
                  final date = _weekDates[day]!;
                  final isToday = _isSameDay(date, DateTime.now());
                  return _DayCard(
                    day: day,
                    date: date,
                    isToday: isToday,
                    enabled: _enabled[day]!,
                    start: _startTimes[day]!,
                    end: _endTimes[day]!,
                    slotCount: _slotsForDay(day),
                    onToggle: (v) => setState(() => _enabled[day] = v),
                    onPickStart: () => _pickTime(day, true),
                    onPickEnd: () => _pickTime(day, false),
                    formatTime: _formatDisplay,
                  );
                }),
                const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled ? AppColors.primary.withValues(alpha:0.3) : AppColors.divider,
          width: isToday ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: enabled
                ? AppColors.primary.withValues(alpha:0.06)
                : Colors.black.withValues(alpha:0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                day,
                style: AppTextStyles.labelLarge.copyWith(
                  color: enabled ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                DateFormat('MMM d').format(date),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: enabled ? AppColors.primary.withValues(alpha:0.7) : AppColors.textSecondary.withValues(alpha:0.7),
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Today',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
          const Spacer(),
          if (enabled && slotCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$slotCount slots',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.success),
              ),
            ),
          GestureDetector(
            onTap: () => onToggle(!enabled),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Text(
                  enabled ? 'Available' : 'Off',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: enabled ? AppColors.success : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Switch(value: enabled, onChanged: onToggle, activeColor: AppColors.primary),
              ],
            ),
          ),
        ]),
        if (enabled) ...[
          const SizedBox(height: 8),
          Row(children: [
            _TimeButton(label: 'From', time: formatTime(start), onTap: onPickStart),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('—', style: TextStyle(color: Colors.grey)),
            ),
            _TimeButton(label: 'To', time: formatTime(end), onTap: onPickEnd),
          ]),
        ],
      ]),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;

  const _TimeButton({required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha:0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500, fontFamily: 'Poppins')),
        Text(time, style: const TextStyle(fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.w700, fontFamily: 'Poppins')),
      ]),
    ),
  );
}
