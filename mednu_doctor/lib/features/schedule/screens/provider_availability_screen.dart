import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../auth/services/doctor_auth_service.dart';

/// Read model for `<profile>.availability` — `{slotDuration, schedule,
/// blockedSlots}`, the same shape `doctors/{uid}.availability` uses. Slot
/// labels are zero-padded 'HH:MM AM' (what the patient picker and the server
/// slot index both expect).
class ProviderSchedule {
  final int slotDuration;
  final Map<String, dynamic> schedule;
  final Map<String, List<String>> blocked;

  const ProviderSchedule({
    required this.slotDuration,
    required this.schedule,
    required this.blocked,
  });

  /// Null when the provider has not published a weekly schedule.
  static ProviderSchedule? from(Map<String, dynamic>? availability) {
    if (availability == null) return null;
    final schedule = availability['schedule'];
    if (schedule is! Map) return null;
    final blockedRaw = availability['blockedSlots'];
    return ProviderSchedule(
      slotDuration: (availability['slotDuration'] as num?)?.toInt() ?? 30,
      schedule: Map<String, dynamic>.from(schedule),
      blocked: blockedRaw is Map
          ? blockedRaw.map((k, v) => MapEntry(
              k.toString(), (v as List? ?? const []).map((e) => e.toString()).toList()))
          : <String, List<String>>{},
    );
  }

  static String label(int totalMins) {
    final h = totalMins ~/ 60;
    final m = totalMins % 60;
    final period = h < 12 ? 'AM' : 'PM';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${dh.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
  }

  static int minutesOf(String slot) {
    final parts = slot.trim().split(' ');
    final hm = parts[0].split(':');
    var h = int.parse(hm[0]);
    final min = int.parse(hm[1]);
    final pm = parts.length > 1 && parts[1].toUpperCase() == 'PM';
    final am = parts.length > 1 && parts[1].toUpperCase() == 'AM';
    if (pm && h != 12) h += 12;
    if (am && h == 12) h = 0;
    return h * 60 + min;
  }

  static String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static String dayName(DateTime d) => DateFormat('EEE', 'en').format(d);

  bool isWorkingDay(DateTime d) =>
      (schedule[dayName(d)] as Map?)?['enabled'] == true;

  /// Every slot of the weekly schedule for [d] (blocked ones included).
  List<String> allSlotsFor(DateTime d) {
    final ds = schedule[dayName(d)] as Map?;
    if (ds == null || ds['enabled'] != true) return const [];
    try {
      final sp = (ds['start'] as String? ?? '09:00').split(':');
      final ep = (ds['end'] as String? ?? '17:00').split(':');
      final start = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final end = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      return [
        for (var m = start; m + slotDuration <= end; m += slotDuration) label(m),
      ];
    } catch (_) {
      return const [];
    }
  }

  Set<String> blockedFor(DateTime d) => (blocked[dateKey(d)] ?? const []).toSet();

  /// Bookable slots for [d]: schedule minus blocked minus (for today) past.
  List<String> openSlotsFor(DateTime d) {
    final blockedSet = blockedFor(d);
    final now = DateTime.now();
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    return allSlotsFor(d).where((s) {
      if (blockedSet.contains(s)) return false;
      if (isToday && minutesOf(s) <= now.hour * 60 + now.minute) return false;
      return true;
    }).toList();
  }
}

/// Weekly availability + slot length + one-off blocked slots for a
/// physiotherapist or counsellor. One screen parameterised by the profile
/// collection (`physiotherapist_profiles` / `counsellor_profiles`), in the
/// same visual style as the doctor's [AvailabilityScreen]. Saved to
/// `<collection>/{uid}.availability`; a Cloud Function mirrors it onto the
/// public listing the patient app books from.
class ProviderAvailabilityScreen extends StatefulWidget {
  final String collection;
  final String title;
  final String subtitle;
  final String noun; // 'session'
  const ProviderAvailabilityScreen({
    super.key,
    required this.collection,
    this.title = 'My Availability',
    this.subtitle = 'Set the weekly slots patients can book',
    this.noun = 'session',
  });

  @override
  State<ProviderAvailabilityScreen> createState() => _ProviderAvailabilityScreenState();
}

class _ProviderAvailabilityScreenState extends State<ProviderAvailabilityScreen> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final Map<String, bool> _enabled = {
    'Mon': true, 'Tue': true, 'Wed': true, 'Thu': true, 'Fri': true,
    'Sat': false, 'Sun': false,
  };
  final Map<String, TimeOfDay> _start = {
    for (final d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']) d: const TimeOfDay(hour: 9, minute: 0),
    'Sat': const TimeOfDay(hour: 10, minute: 0),
    'Sun': const TimeOfDay(hour: 10, minute: 0),
  };
  final Map<String, TimeOfDay> _end = {
    for (final d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']) d: const TimeOfDay(hour: 17, minute: 0),
    'Sat': const TimeOfDay(hour: 14, minute: 0),
    'Sun': const TimeOfDay(hour: 14, minute: 0),
  };
  final Map<String, String?> _dayErrors = {};
  Map<String, List<String>> _blocked = {};

  int _slotDuration = 30;
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  bool _dirty = false;

  late final Map<String, DateTime> _weekDates = () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return {for (var i = 0; i < 7; i++) _days[i]: monday.add(Duration(days: i))};
  }();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final doc = await FirebaseFirestore.instance.collection(widget.collection).doc(uid).get();
      final avail = doc.data()?['availability'] as Map<String, dynamic>?;
      final parsed = ProviderSchedule.from(avail);
      if (parsed != null) {
        _slotDuration = parsed.slotDuration;
        for (final day in _days) {
          final ds = parsed.schedule[day] as Map?;
          if (ds == null) continue;
          _enabled[day] = ds['enabled'] == true;
          final s = ds['start'] as String?;
          final e = ds['end'] as String?;
          if (s != null) _start[day] = _parse(s);
          if (e != null) _end[day] = _parse(e);
        }
        _blocked = {for (final e in parsed.blocked.entries) e.key: [...e.value]};
      }
    } catch (_) {
      _loadFailed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  TimeOfDay _parse(String t) {
    final p = t.split(':');
    if (p.length == 2) {
      return TimeOfDay(hour: int.tryParse(p[0]) ?? 9, minute: int.tryParse(p[1]) ?? 0);
    }
    return const TimeOfDay(hour: 9, minute: 0);
  }

  String _store(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _display(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  String? _validateDay(String day) {
    final base = _weekDates[day] ?? DateTime.now();
    DateTime at(TimeOfDay t) => DateTime(base.year, base.month, base.day, t.hour, t.minute);
    final err = Validators.timeRange(at(_start[day]!), at(_end[day]!));
    if (err != null) return err;
    if (_slotsForDay(day) == 0 && _enabled[day] == true) {
      return 'Window is shorter than one $_slotDuration-minute slot';
    }
    return null;
  }

  int _slotsForDay(String day) {
    if (_enabled[day] != true) return 0;
    final total = (_end[day]!.hour * 60 + _end[day]!.minute) -
        (_start[day]!.hour * 60 + _start[day]!.minute);
    return total <= 0 ? 0 : total ~/ _slotDuration;
  }

  int get _weeklySlots => _days.fold(0, (s, d) => s + _slotsForDay(d));
  int get _workingDays => _days.where((d) => _enabled[d] == true).length;

  Future<void> _pickTime(String day, bool isStart) async {
    final picked = await showTimePicker(
        context: context, initialTime: isStart ? _start[day]! : _end[day]!);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start[day] = picked;
      } else {
        _end[day] = picked;
      }
      _dirty = true;
      _dayErrors[day] = _validateDay(day);
    });
  }

  Future<void> _save() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null || _saving) return;
    setState(() {
      for (final d in _days) {
        _dayErrors[d] = _enabled[d] == true ? _validateDay(d) : null;
      }
    });
    if (_dayErrors.values.any((e) => e != null)) {
      _snack('Fix the highlighted days before saving', error: true);
      return;
    }
    if (_workingDays == 0) {
      _snack('Turn on at least one working day', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      // Drop blocked entries for past dates so the map never grows unbounded.
      final today = ProviderSchedule.dateKey(DateTime.now());
      final blocked = {
        for (final e in _blocked.entries)
          if (e.value.isNotEmpty && e.key.compareTo(today) >= 0) e.key: e.value,
      };
      await FirebaseFirestore.instance.collection(widget.collection).doc(uid).update({
        'availability.slotDuration': _slotDuration,
        'availability.schedule': {
          for (final d in _days)
            d: {'enabled': _enabled[d], 'start': _store(_start[d]!), 'end': _store(_end[d]!)},
        },
        'availability.blockedSlots': blocked,
        'availability.updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      _blocked = blocked;
      setState(() => _dirty = false);
      _snack('Availability saved. Patients can now book these slots.');
    } catch (e) {
      if (mounted) _snack('Could not save availability. Check your connection and try again.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _openBlockSheet() async {
    final result = await showModalBottomSheet<Map<String, List<String>>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BlockSlotsSheet(
        draft: ProviderSchedule(
          slotDuration: _slotDuration,
          schedule: {
            for (final d in _days)
              d: {'enabled': _enabled[d], 'start': _store(_start[d]!), 'end': _store(_end[d]!)},
          },
          blocked: _blocked,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _blocked = result;
        _dirty = true;
      });
      _snack('Blocked slots updated. Tap Save to publish.');
    }
  }

  int get _blockedCount {
    final today = ProviderSchedule.dateKey(DateTime.now());
    return _blocked.entries
        .where((e) => e.key.compareTo(today) >= 0)
        .fold(0, (s, e) => s + e.value.length);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _skeleton();
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('Your availability changes have not been saved.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
            ],
          ),
        );
        if (leave == true && mounted) {
          setState(() => _dirty = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.safeBack();
          });
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 64,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              actions: [
                _saving
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    : TextButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_rounded, color: Colors.white, size: 16),
                        label: const Text('Save',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                                fontSize: 14)),
                      ),
              ],
              flexibleSpace: _Header(title: widget.title, subtitle: widget.subtitle),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_loadFailed) ...[
                          _Notice(
                            icon: Icons.wifi_off_rounded,
                            color: AppColors.error,
                            text: 'Could not load your saved availability. Showing defaults — '
                                'pull back and retry before saving over it.',
                            action: 'Retry',
                            onAction: _load,
                          ),
                          const SizedBox(height: 16),
                        ],
                        FadeInSlide(child: _durationCard()),
                        const SizedBox(height: 16),
                        FadeInSlide(
                          delay: const Duration(milliseconds: 60),
                          child: _summary(),
                        ),
                        const SizedBox(height: 16),
                        FadeInSlide(
                          delay: const Duration(milliseconds: 70),
                          child: _blockTile(),
                        ),
                        const SizedBox(height: 20),
                        FadeInSlide(
                          delay: const Duration(milliseconds: 80),
                          child: Row(children: [
                            const Expanded(
                                child: Text('Weekly Schedule', style: AppTextStyles.h4)),
                            InfoChip(
                              icon: Icons.calendar_view_week_rounded,
                              label: DateFormat('MMM d').format(_weekDates['Mon']!),
                              color: AppColors.secondary,
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        for (var i = 0; i < _days.length; i++)
                          FadeInSlide(
                            delay: Duration(milliseconds: 100 + i * 40),
                            child: _dayCard(_days[i]),
                          ),
                        const SizedBox(height: 8),
                        GradientButton(
                          label: 'Save Availability',
                          icon: Icons.save_rounded,
                          isLoading: _saving,
                          onTap: _saving ? null : _save,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton() => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Text(widget.title),
        ),
        body: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: List.generate(
              6,
              (_) => const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: SkeletonBox(width: double.infinity, height: 72, radius: 16),
              ),
            ),
          ),
        ),
      );

  Widget _durationCard() => PremiumCard(
        padding: const EdgeInsets.all(16),
        radius: 16,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _IconBox(icon: Icons.timer_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${widget.noun[0].toUpperCase()}${widget.noun.substring(1)} Slot Duration',
                    style: AppTextStyles.labelLarge),
                Text('Time per ${widget.noun}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(
            children: [15, 30, 45, 60].map((min) {
              final sel = _slotDuration == min;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: sel,
                  label: '$min minute slots',
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _slotDuration = min;
                      _dirty = true;
                      for (final d in _days) {
                        if (_enabled[d] == true) _dayErrors[d] = _validateDay(d);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: sel
                            ? const LinearGradient(
                                colors: [AppColors.primary, AppColors.secondary])
                            : null,
                        color: sel ? null : AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('$min',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: sel ? Colors.white : AppColors.textPrimary)),
                        Text('min',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                color: sel ? Colors.white70 : AppColors.textHint)),
                      ]),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ]),
      );

  Widget _summary() {
    final hours = (_weeklySlots * _slotDuration) ~/ 60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$_weeklySlots slots · $_workingDays working day${_workingDays == 1 ? '' : 's'}'
            ' · ~$hours hr${hours == 1 ? '' : 's'}/week',
            style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary),
          ),
        ),
      ]),
    );
  }

  Widget _blockTile() => Semantics(
        button: true,
        label: 'Block specific slots',
        child: GestureDetector(
          onTap: _openBlockSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(children: [
              _IconBox(icon: Icons.event_busy_rounded, color: AppColors.error, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Block a Slot', style: AppTextStyles.labelLarge),
                  Text(
                    _blockedCount == 0
                        ? 'Have a sudden commitment? Block just that time.'
                        : '$_blockedCount upcoming slot${_blockedCount == 1 ? '' : 's'} blocked',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
            ]),
          ),
        ),
      );

  Widget _dayCard(String day) {
    final enabled = _enabled[day]!;
    final date = _weekDates[day]!;
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final count = _slotsForDay(day);
    final err = _dayErrors[day];
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
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(day,
                    style: AppTextStyles.labelLarge.copyWith(
                        color: enabled ? AppColors.textPrimary : AppColors.textSecondary)),
                if (isToday) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Today',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ],
              ]),
              Text(DateFormat('MMM d').format(date),
                  style: AppTextStyles.caption.copyWith(
                      color: enabled
                          ? AppColors.primary.withValues(alpha: 0.8)
                          : AppColors.textHint)),
            ]),
          ),
          if (enabled && count > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count slots',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.success)),
            ),
            const SizedBox(width: 10),
          ],
          Semantics(
            toggled: enabled,
            label: '$day working day',
            child: Switch.adaptive(
              value: enabled,
              activeTrackColor: AppColors.primary,
              onChanged: (v) => setState(() {
                _enabled[day] = v;
                _dirty = true;
                _dayErrors[day] = v ? _validateDay(day) : null;
              }),
            ),
          ),
        ]),
        if (enabled) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _TimeButton(
                  label: 'Start',
                  time: _display(_start[day]!),
                  icon: Icons.play_arrow_rounded,
                  onTap: () => _pickTime(day, true)),
              _TimeButton(
                  label: 'End',
                  time: _display(_end[day]!),
                  icon: Icons.stop_rounded,
                  onTap: () => _pickTime(day, false)),
            ],
          ),
          if (err != null) ...[
            const SizedBox(height: 8),
            Text(err, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
          ],
        ],
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  const _Header({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary, AppColors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 100, 0),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.2)),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _IconBox({required this.icon, required this.color, this.size = 36});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final String action;
  final VoidCallback onAction;
  const _Notice({
    required this.icon,
    required this.color,
    required this.text,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTextStyles.bodySmall)),
          TextButton(onPressed: onAction, child: Text(action)),
        ]),
      );
}

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
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Inter')),
              Text(time,
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter')),
            ]),
          ]),
        ),
      );
}

/// One-off blocked slots, edited against the in-memory (possibly unsaved)
/// weekly schedule; result is applied to the screen state and saved with the
/// rest of the availability.
class _BlockSlotsSheet extends StatefulWidget {
  final ProviderSchedule draft;
  const _BlockSlotsSheet({required this.draft});

  @override
  State<_BlockSlotsSheet> createState() => _BlockSlotsSheetState();
}

class _BlockSlotsSheetState extends State<_BlockSlotsSheet> {
  late final Map<String, List<String>> _blocked = {
    for (final e in widget.draft.blocked.entries) e.key: [...e.value],
  };
  late final List<DateTime> _dates = () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(21, (i) => today.add(Duration(days: i)));
  }();
  int _selected = 0;

  DateTime get _date => _dates[_selected];

  @override
  Widget build(BuildContext context) {
    final slots = widget.draft.allSlotsFor(_date);
    final blockedSet = (_blocked[ProviderSchedule.dateKey(_date)] ?? const <String>[]).toSet();
    final now = DateTime.now();
    final isToday = _selected == 0;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(children: [
            const Expanded(child: Text('Block slots', style: AppTextStyles.h4)),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Tap a slot to block or unblock it. Blocked slots cannot be booked.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _dates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final d = _dates[i];
              final sel = i == _selected;
              final working = widget.draft.isWorkingDay(d);
              return GestureDetector(
                onTap: () => setState(() => _selected = i),
                child: Container(
                  width: 56,
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primary : (working ? Colors.white : AppColors.background),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sel ? AppColors.primary : AppColors.divider),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(i == 0 ? 'Today' : DateFormat('EEE').format(d),
                        style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Inter',
                            color: sel ? Colors.white70 : AppColors.textHint)),
                    Text('${d.day}',
                        style: TextStyle(
                            fontSize: 18,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w800,
                            color: sel
                                ? Colors.white
                                : (working ? AppColors.textPrimary : AppColors.textHint))),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: slots.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('No working hours on this day.',
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: slots.map((s) {
                        final past = isToday &&
                            ProviderSchedule.minutesOf(s) <= now.hour * 60 + now.minute;
                        final blocked = blockedSet.contains(s);
                        return Semantics(
                          button: true,
                          selected: blocked,
                          label: '$s ${blocked ? 'blocked' : 'open'}',
                          child: GestureDetector(
                            onTap: past
                                ? null
                                : () => setState(() {
                                      final key = ProviderSchedule.dateKey(_date);
                                      final list = [...(_blocked[key] ?? const <String>[])];
                                      blocked ? list.remove(s) : list.add(s);
                                      list.sort((a, b) => ProviderSchedule.minutesOf(a)
                                          .compareTo(ProviderSchedule.minutesOf(b)));
                                      _blocked[key] = list;
                                    }),
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 92, minHeight: 44),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: blocked
                                    ? AppColors.error.withValues(alpha: 0.1)
                                    : (past ? AppColors.background : Colors.white),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: blocked ? AppColors.error : AppColors.divider),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (blocked) ...[
                                  const Icon(Icons.block_rounded,
                                      size: 13, color: AppColors.error),
                                  const SizedBox(width: 4),
                                ],
                                Text(s,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w600,
                                        color: blocked
                                            ? AppColors.error
                                            : (past ? AppColors.textHint : AppColors.textPrimary),
                                        decoration:
                                            past ? TextDecoration.lineThrough : null)),
                              ]),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(context, _blocked),
              child: const Text('Done'),
            ),
          ),
        ),
      ]),
    );
  }
}
