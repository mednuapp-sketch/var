import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

/// A provider's published availability — `{slotDuration, schedule,
/// blockedSlots}`, the same shape as `doctors/{uid}.availability`, mirrored
/// by Cloud Functions onto `physiotherapists/{id}` / `counsellors/{id}`.
/// Slot labels are zero-padded 'HH:MM AM'.
class ProviderAvailability {
  final int slotDuration;
  final Map<String, dynamic> schedule;
  final Map<String, List<String>> blocked;

  const ProviderAvailability._(this.slotDuration, this.schedule, this.blocked);

  /// Null when the provider has not published a schedule (callers then keep
  /// the free-text date/time fallback).
  static ProviderAvailability? from(Object? raw) {
    if (raw is! Map) return null;
    final schedule = raw['schedule'];
    if (schedule is! Map) return null;
    final days = Map<String, dynamic>.from(schedule);
    if (!days.values.any((v) => v is Map && v['enabled'] == true)) return null;
    final blockedRaw = raw['blockedSlots'];
    return ProviderAvailability._(
      (raw['slotDuration'] as num?)?.toInt() ?? 30,
      days,
      blockedRaw is Map
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
    try {
      final parts = slot.trim().split(' ');
      final hm = parts[0].split(':');
      var h = int.parse(hm[0]);
      final min = int.parse(hm[1]);
      final pm = parts.length > 1 && parts[1].toUpperCase() == 'PM';
      final am = parts.length > 1 && parts[1].toUpperCase() == 'AM';
      if (pm && h != 12) h += 12;
      if (am && h == 12) h = 0;
      return h * 60 + min;
    } catch (_) {
      return 0;
    }
  }

  static String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  bool isWorkingDay(DateTime d) =>
      (schedule[DateFormat('EEE', 'en').format(d)] as Map?)?['enabled'] == true;

  /// Bookable slots for [d]: weekly schedule minus blocked minus (for today)
  /// slots that already started. Taken slots are filtered by the picker from
  /// the live slot index.
  List<String> openSlotsFor(DateTime d) {
    final ds = schedule[DateFormat('EEE', 'en').format(d)] as Map?;
    if (ds == null || ds['enabled'] != true) return const [];
    try {
      final sp = (ds['start'] as String? ?? '09:00').split(':');
      final ep = (ds['end'] as String? ?? '17:00').split(':');
      final start = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final end = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      final blockedSet = (blocked[dateKey(d)] ?? const <String>[]).toSet();
      final now = DateTime.now();
      final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
      final nowMins = now.hour * 60 + now.minute;
      final out = <String>[];
      for (var m = start; m + slotDuration <= end; m += slotDuration) {
        final l = label(m);
        if (blockedSet.contains(l)) continue;
        if (isToday && m <= nowMins) continue;
        out.add(l);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

/// Which Firestore collections back a therapy provider type.
class TherapySlots {
  TherapySlots._();

  static bool supports(String type) => type == 'physiotherapy' || type == 'counselling';

  static String listingCollection(String type) =>
      type == 'physiotherapy' ? 'physiotherapists' : 'counsellors';

  static String slotCollection(String type) =>
      type == 'physiotherapy' ? 'physio_slots' : 'counselling_slots';

  /// `preferredDate` as the whole app writes/reads it.
  static String formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  static Future<ProviderAvailability?> loadAvailability(String type, String providerId) async {
    final doc = await FirebaseFirestore.instance
        .collection(listingCollection(type))
        .doc(providerId)
        .get();
    return ProviderAvailability.from(doc.data()?['availability']);
  }

  /// Same key the server builds (`_slotKey` in functions/index.js).
  static String slotDocId(String providerId, DateTime date, String slot) =>
      '${providerId}_${ProviderAvailability.dateKey(date)}_${slot.replaceAll(RegExp(r'[^A-Za-z0-9]'), '-')}';

  /// Cheap pre-flight right before booking/rescheduling. The server index is
  /// still the final arbiter if two patients race.
  static Future<bool> isSlotFree(String type, String providerId, DateTime date, String slot) async {
    final snap = await FirebaseFirestore.instance
        .collection(slotCollection(type))
        .doc(slotDocId(providerId, date, slot))
        .get();
    return !snap.exists;
  }
}

/// Date strip + slot grid built from a provider's published availability.
/// Reports the selection through [onChanged] (`null`/`null` = nothing chosen).
class ProviderSlotPicker extends StatefulWidget {
  final String type; // 'physiotherapy' | 'counselling'
  final String providerId;
  final ProviderAvailability availability;
  final Color color;
  final bool hasError;
  final void Function(DateTime? date, String? slot) onChanged;

  const ProviderSlotPicker({
    super.key,
    required this.type,
    required this.providerId,
    required this.availability,
    required this.color,
    required this.onChanged,
    this.hasError = false,
  });

  @override
  State<ProviderSlotPicker> createState() => _ProviderSlotPickerState();
}

class _ProviderSlotPickerState extends State<ProviderSlotPicker> {
  static const _horizonDays = 21;
  late final List<DateTime> _dates = () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(_horizonDays, (i) => today.add(Duration(days: i)));
  }();

  int _selectedDate = 0;
  String? _slot;

  @override
  void initState() {
    super.initState();
    // Land on the first day that actually has bookable slots.
    final first = _dates.indexWhere((d) => widget.availability.openSlotsFor(d).isNotEmpty);
    _selectedDate = first < 0 ? 0 : first;
  }

  DateTime get _date => _dates[_selectedDate];

  Stream<Set<String>> _takenStream() => FirebaseFirestore.instance
      .collection(TherapySlots.slotCollection(widget.type))
      .where('providerId', isEqualTo: widget.providerId)
      .where('date', isEqualTo: ProviderAvailability.dateKey(_date))
      .snapshots()
      .map((s) => s.docs.map((d) => d.data()['time'] as String? ?? '').toSet());

  void _select(int i) {
    setState(() {
      _selectedDate = i;
      _slot = null;
    });
    widget.onChanged(null, null);
  }

  @override
  Widget build(BuildContext context) {
    final avail = widget.availability;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _dates.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final d = _dates[i];
            final sel = i == _selectedDate;
            final working = avail.isWorkingDay(d);
            return Semantics(
              button: true,
              selected: sel,
              enabled: working,
              label: DateFormat('EEEE d MMMM').format(d) + (working ? '' : ', not available'),
              child: GestureDetector(
                onTap: working ? () => _select(i) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 58,
                  decoration: BoxDecoration(
                    color: sel
                        ? widget.color
                        : (working ? Colors.white : const Color(0xFFF3F4F6)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sel ? widget.color : (widget.hasError && _slot == null
                          ? Colors.red.shade200
                          : const Color(0xFFE5E7EB)),
                    ),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(
                      i == 0 ? 'Today' : (i == 1 ? 'Tmrw' : DateFormat('EEE').format(d)),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: sel ? Colors.white70 : (working ? AppColors.textSecondary : AppColors.textHint),
                      ),
                    ),
                    Text(
                      '${d.day}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: sel ? Colors.white : (working ? AppColors.textPrimary : AppColors.textHint),
                      ),
                    ),
                    Text(
                      DateFormat('MMM').format(d),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 9,
                        color: sel ? Colors.white60 : AppColors.textHint,
                      ),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 14),
      StreamBuilder<Set<String>>(
        stream: _takenStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const SizedBox(
              height: 72,
              child: Center(child: SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          final taken = snap.data ?? const <String>{};
          final slots = avail.openSlotsFor(_date);
          if (slots.isEmpty) {
            return _emptyBox(
              Icons.event_busy_rounded,
              avail.isWorkingDay(_date) ? 'No slots left' : 'Not available',
              avail.isWorkingDay(_date)
                  ? 'All slots for this day are over or blocked. Pick another date.'
                  : 'The provider is off on this day. Pick another date.',
            );
          }
          if (slots.every(taken.contains)) {
            return _emptyBox(Icons.event_busy_rounded, 'Fully booked',
                'Every slot on this day is taken. Pick another date.');
          }
          return LayoutBuilder(builder: (context, c) {
            const gap = 8.0;
            final cols = c.maxWidth >= 420 ? 4 : 3;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: slots.map((s) {
                final isTaken = taken.contains(s);
                final sel = _slot == s;
                return Semantics(
                  button: true,
                  enabled: !isTaken,
                  selected: sel,
                  label: '$s ${isTaken ? 'booked' : 'available'}',
                  child: GestureDetector(
                    onTap: isTaken
                        ? null
                        : () {
                            final next = sel ? null : s;
                            setState(() => _slot = next);
                            widget.onChanged(next == null ? null : _date, next);
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: w,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel
                            ? widget.color
                            : (isTaken ? const Color(0xFFF3F4F6) : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel ? widget.color : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          s,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: sel
                                ? Colors.white
                                : (isTaken ? AppColors.textHint : AppColors.textPrimary),
                            decoration: isTaken ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          });
        },
      ),
    ]);
  }

  Widget _emptyBox(IconData icon, String title, String sub) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(children: [
          Icon(icon, size: 28, color: AppColors.textHint),
          const SizedBox(height: 8),
          Text(title, style: AppTextStyles.labelLarge),
          const SizedBox(height: 2),
          Text(sub,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
        ]),
      );
}

/// Patient-side reschedule of a pending/accepted physiotherapy or counselling
/// booking. Writes only the keys the firestore.rules whitelist allows; the
/// Cloud Function mirrors it to the session, moves the slot-index entry and
/// notifies the provider (and reverts + tells the patient if the slot was taken).
/// Returns true when the request was updated.
Future<bool> showTherapyRescheduleSheet(
  BuildContext context, {
  required String requestId,
  required String type,
  required String? providerId,
  required String currentDate,
  required String currentTime,
  required Color color,
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RescheduleSheet(
      requestId: requestId,
      type: type,
      providerId: providerId,
      currentDate: currentDate,
      currentTime: currentTime,
      color: color,
    ),
  );
  return done == true;
}

class _RescheduleSheet extends StatefulWidget {
  final String requestId;
  final String type;
  final String? providerId;
  final String currentDate;
  final String currentTime;
  final Color color;
  const _RescheduleSheet({
    required this.requestId,
    required this.type,
    required this.providerId,
    required this.currentDate,
    required this.currentTime,
    required this.color,
  });

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  ProviderAvailability? _avail;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  DateTime? _date;
  String? _slot; // slot label, or free-text time in fallback mode
  TimeOfDay? _fallbackTime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.providerId;
    if (id != null && id.isNotEmpty) {
      try {
        _avail = await TherapySlots.loadAvailability(widget.type, id);
      } catch (_) {
        _avail = null;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get _canConfirm =>
      !_saving && _date != null && (_avail != null ? _slot != null : _fallbackTime != null);

  Future<void> _confirm() async {
    final date = _date;
    if (date == null) return;
    final time = _avail != null
        ? _slot
        : (_fallbackTime == null
            ? null
            : ProviderAvailability.label(_fallbackTime!.hour * 60 + _fallbackTime!.minute));
    if (time == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = widget.providerId;
      if (_avail != null && id != null) {
        final free = await TherapySlots.isSlotFree(widget.type, id, date, time);
        if (!free) {
          if (mounted) {
            setState(() {
              _saving = false;
              _slot = null;
              _error = 'That slot was just booked. Please pick another.';
            });
          }
          return;
        }
      }
      await FirebaseFirestore.instance.collection('service_requests').doc(widget.requestId).update({
        'preferredDate': TherapySlots.formatDate(date),
        'preferredTime': time,
        'rescheduledAt': FieldValue.serverTimestamp(),
        'rescheduledBy': 'patient',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not reschedule. Check your connection, or the booking may have already started.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Reschedule booking', style: AppTextStyles.h4),
                const SizedBox(height: 2),
                Text(
                  'Currently ${widget.currentDate}${widget.currentTime.isNotEmpty ? ' · ${widget.currentTime}' : ''}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Flexible(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()))
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _avail != null
                      ? ProviderSlotPicker(
                          type: widget.type,
                          providerId: widget.providerId!,
                          availability: _avail!,
                          color: widget.color,
                          onChanged: (d, s) => setState(() {
                            _date = d;
                            _slot = s;
                            _error = null;
                          }),
                        )
                      : _fallback(),
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(_error!,
                style: AppTextStyles.caption.copyWith(color: AppColors.error)),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              20, 14, 20, 16 + MediaQuery.of(context).padding.bottom),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _canConfirm ? _confirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.color,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE5E7EB),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm new time',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _fallback() {
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Pick a new date and time. Your provider will be notified.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_rounded, size: 16),
          label: Text(_date == null ? 'Select date' : DateFormat('EEE, d MMM').format(_date!)),
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _date ?? now.add(const Duration(days: 1)),
              firstDate: now,
              lastDate: now.add(const Duration(days: 60)),
            );
            if (d != null && mounted) setState(() => _date = d);
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.access_time_rounded, size: 16),
          label: Text(_fallbackTime == null
              ? 'Select time'
              : ProviderAvailability.label(_fallbackTime!.hour * 60 + _fallbackTime!.minute)),
          onPressed: () async {
            final t = await showTimePicker(
                context: context,
                initialTime: _fallbackTime ?? const TimeOfDay(hour: 10, minute: 0));
            if (t != null && mounted) setState(() => _fallbackTime = t);
          },
        ),
      ]),
      const SizedBox(height: 8),
    ]);
  }
}
