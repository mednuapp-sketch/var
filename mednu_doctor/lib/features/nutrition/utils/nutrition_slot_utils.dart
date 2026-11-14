import 'package:intl/intl.dart';

/// Weekday keys used in `nutritionist_profiles/{uid}.availability.schedule`
/// (same as the doctor's `doctors/{uid}.availability.schedule`).
const kNutritionDayKeys = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Legacy list the patient app falls back to when no schedule is published.
const kNutritionDefaultSlots = [
  '09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM',
  '11:00 AM', '11:30 AM', '02:00 PM', '02:30 PM',
  '03:00 PM', '03:30 PM', '04:00 PM', '04:30 PM',
  '05:00 PM', '06:00 PM',
];

/// Zero-padded "HH:MM AM" label — identical to the doctor flow and to the
/// server mirror (`_nutritionSlotLabel` in functions/index.js).
String nutritionSlotLabel(int mins) {
  final h = mins ~/ 60;
  final m = mins % 60;
  final period = h < 12 ? 'AM' : 'PM';
  final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  return '${dh.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
}

int? _minutesOf(String? hhmm) {
  final p = (hhmm ?? '').split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Slot labels generated from one day's schedule entry
/// `{enabled, start: 'HH:MM', end: 'HH:MM'}`.
List<String> nutritionDaySlots(Map<String, dynamic>? day, int slotDuration) {
  if (day == null || day['enabled'] != true) return const [];
  final start = _minutesOf(day['start'] as String?) ?? 9 * 60;
  final end = _minutesOf(day['end'] as String?) ?? 17 * 60;
  final dur = slotDuration >= 5 ? slotDuration : 30;
  final out = <String>[];
  for (var m = start; m + dur <= end; m += dur) {
    out.add(nutritionSlotLabel(m));
  }
  return out;
}

bool isPastNutritionSlot(String slot, DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  if (d.isAfter(today)) return false;
  if (d.isBefore(today)) return true;
  try {
    final parts = slot.trim().split(' ');
    final hm = parts[0].split(':');
    var h = int.parse(hm[0]);
    final min = int.parse(hm[1]);
    if (parts[1].toUpperCase() == 'PM' && h != 12) h += 12;
    if (parts[1].toUpperCase() == 'AM' && h == 12) h = 0;
    return DateTime(now.year, now.month, now.day, h, min).isBefore(now);
  } catch (_) {
    return false;
  }
}

/// Every slot the dietician offers on [date] before taken/past filtering:
/// the weekly schedule minus blocked slots (legacy defaults if no schedule).
List<String> nutritionOfferedSlots(Map<String, dynamic>? availability, DateTime date) {
  final schedule = availability?['schedule'] as Map<String, dynamic>?;
  List<String> base;
  if (schedule == null) {
    base = kNutritionDefaultSlots;
  } else {
    final dayKey = kNutritionDayKeys[date.weekday - 1];
    base = nutritionDaySlots(
      schedule[dayKey] as Map<String, dynamic>?,
      (availability?['slotDuration'] as num?)?.toInt() ?? 30,
    );
  }
  final blocked = ((availability?['blockedSlots'] as Map<String, dynamic>?)?[
              DateFormat('yyyy-MM-dd').format(date)] as List?)
          ?.map((e) => e.toString())
          .toSet() ??
      const <String>{};
  return base.where((s) => !blocked.contains(s)).toList();
}
