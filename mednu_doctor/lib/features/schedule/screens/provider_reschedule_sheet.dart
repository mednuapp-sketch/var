import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import 'provider_availability_screen.dart';

/// The new date/time a provider proposes for a session. [date] is written in
/// the patient app's own `d/M/yyyy` form and [time] as a zero-padded
/// 'HH:MM AM' label — the exact strings `preferredDate`/`preferredTime` hold.
typedef RescheduleChoice = ({String date, String time});

/// Bottom sheet that lets a physiotherapist/counsellor move a session to
/// another valid slot from their own published availability (blocked, past
/// and already-booked slots are not offered). Falls back to plain date/time
/// pickers when no availability has been published yet.
Future<RescheduleChoice?> showProviderRescheduleSheet(
  BuildContext context, {
  required String profileCollection,
  required String slotCollection,
  required String providerId,
  required String currentDate,
  required String currentTime,
}) {
  return showModalBottomSheet<RescheduleChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RescheduleSheet(
      profileCollection: profileCollection,
      slotCollection: slotCollection,
      providerId: providerId,
      currentDate: currentDate,
      currentTime: currentTime,
    ),
  );
}

class _RescheduleSheet extends StatefulWidget {
  final String profileCollection;
  final String slotCollection;
  final String providerId;
  final String currentDate;
  final String currentTime;
  const _RescheduleSheet({
    required this.profileCollection,
    required this.slotCollection,
    required this.providerId,
    required this.currentDate,
    required this.currentTime,
  });

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  late final List<DateTime> _dates = () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(30, (i) => today.add(Duration(days: i)));
  }();

  ProviderSchedule? _schedule;
  bool _loading = true;
  bool _failed = false;
  int _selectedDate = 0;
  String? _slot;

  // Fallback (nothing published): free date + time.
  DateTime? _fallbackDate;
  TimeOfDay? _fallbackTime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection(widget.profileCollection)
          .doc(widget.providerId)
          .get();
      _schedule = ProviderSchedule.from(doc.data()?['availability'] as Map<String, dynamic>?);
    } catch (_) {
      _failed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  DateTime get _date => _dates[_selectedDate];

  Stream<Set<String>> _bookedStream() => FirebaseFirestore.instance
      .collection(widget.slotCollection)
      .where('providerId', isEqualTo: widget.providerId)
      .where('date', isEqualTo: ProviderSchedule.dateKey(_date))
      .snapshots()
      .map((s) => s.docs.map((d) => d.data()['time'] as String? ?? '').toSet());

  static String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  void _confirm() {
    if (_schedule != null) {
      if (_slot == null) return;
      Navigator.pop(context, (date: _fmtDate(_date), time: _slot!));
      return;
    }
    if (_fallbackDate == null || _fallbackTime == null) return;
    Navigator.pop(context, (
      date: _fmtDate(_fallbackDate!),
      time: ProviderSchedule.label(_fallbackTime!.hour * 60 + _fallbackTime!.minute),
    ));
  }

  bool get _canConfirm =>
      _schedule != null ? _slot != null : (_fallbackDate != null && _fallbackTime != null);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration:
              BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Reschedule session', style: AppTextStyles.h4),
                const SizedBox(height: 2),
                Text(
                  'Currently ${widget.currentDate}${widget.currentTime.isNotEmpty ? ' at ${widget.currentTime}' : ''}. '
                  'The patient is notified of the new time.',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Flexible(child: _body()),
        Padding(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, 16 + MediaQuery.of(context).padding.bottom),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.divider,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _canConfirm ? _confirm : null,
              icon: const Icon(Icons.event_repeat_rounded, size: 18),
              label: const Text('Confirm new time'),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.textHint, size: 32),
          const SizedBox(height: 8),
          Text('Could not load your availability.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }
    final sched = _schedule;
    if (sched == null) return _fallback();
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _dates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final d = _dates[i];
              final sel = i == _selectedDate;
              final working = sched.isWorkingDay(d);
              return Semantics(
                button: true,
                selected: sel,
                label: DateFormat('EEEE d MMMM').format(d),
                child: GestureDetector(
                  onTap: working
                      ? () => setState(() {
                            _selectedDate = i;
                            _slot = null;
                          })
                      : null,
                  child: Container(
                    width: 56,
                    decoration: BoxDecoration(
                      color: sel
                          ? AppColors.primary
                          : (working ? Colors.white : AppColors.background),
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
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: StreamBuilder<Set<String>>(
            stream: _bookedStream(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final booked = snap.data ?? const <String>{};
              final open = sched.openSlotsFor(_date);
              if (!sched.isWorkingDay(_date) || open.isEmpty) {
                return _empty(
                  Icons.event_busy_rounded,
                  'No open slots',
                  'Nothing left on this day. Choose another date.',
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: open.map((s) {
                  final taken = booked.contains(s);
                  final sel = _slot == s;
                  return Semantics(
                    button: true,
                    enabled: !taken,
                    selected: sel,
                    label: '$s ${taken ? 'booked' : 'available'}',
                    child: GestureDetector(
                      onTap: taken ? null : () => setState(() => _slot = sel ? null : s),
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 92, minHeight: 44),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColors.primary
                              : (taken ? AppColors.background : Colors.white),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: sel ? AppColors.primary : AppColors.divider),
                        ),
                        child: Text(s,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                color: sel
                                    ? Colors.white
                                    : (taken ? AppColors.textHint : AppColors.textPrimary),
                                decoration: taken ? TextDecoration.lineThrough : null)),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _empty(IconData icon, String title, String sub) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Icon(icon, size: 32, color: AppColors.textHint),
          const SizedBox(height: 8),
          Text(title, style: AppTextStyles.labelLarge),
          const SizedBox(height: 4),
          Text(sub,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
        ]),
      );

  Widget _fallback() {
    final now = DateTime.now();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warnBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You have not published availability yet, so pick any date and time. '
                'Publish your weekly slots from Settings to offer fixed slots.',
                style: AppTextStyles.bodySmall,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: Text(_fallbackDate == null
                ? 'Pick date'
                : DateFormat('EEE, d MMM').format(_fallbackDate!)),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _fallbackDate ?? now,
                firstDate: now,
                lastDate: now.add(const Duration(days: 90)),
              );
              if (d != null && mounted) setState(() => _fallbackDate = d);
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.access_time_rounded, size: 16),
            label: Text(_fallbackTime == null
                ? 'Pick time'
                : ProviderSchedule.label(_fallbackTime!.hour * 60 + _fallbackTime!.minute)),
            onPressed: () async {
              final t = await showTimePicker(
                  context: context,
                  initialTime: _fallbackTime ?? const TimeOfDay(hour: 10, minute: 0));
              if (t != null && mounted) setState(() => _fallbackTime = t);
            },
          ),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }
}
