import 'package:intl/intl.dart';

/// Legacy slot list used only for dieticians who never published a schedule.
const kNutritionDefaultSlots = [
  '09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM',
  '11:00 AM', '11:30 AM', '02:00 PM', '02:30 PM',
  '03:00 PM', '03:30 PM', '04:00 PM', '04:30 PM',
  '05:00 PM', '06:00 PM',
];

/// True when [slot] ("09:30 AM") on [date] has already started.
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

/// Bookable slot labels for [date], from the dietician's mirrored listing
/// (`nutritionists/{id}`): `slots` is keyed by full day name ("Monday"),
/// `blockedSlots` by `yyyy-MM-dd`. Blocked and already-started slots are
/// removed; taken slots are greyed separately from `nutrition_slots`.
List<String> nutritionSlotsFor({
  required Map<String, dynamic>? slots,
  required bool scheduleConfigured,
  required Map<String, dynamic>? blockedSlots,
  required DateTime date,
}) {
  List<String> base;
  if (slots == null) {
    base = kNutritionDefaultSlots;
  } else {
    final daySlots = slots[DateFormat('EEEE').format(date)] as List?;
    if (daySlots != null && daySlots.isNotEmpty) {
      base = List<String>.from(daySlots);
    } else {
      base = scheduleConfigured ? const [] : kNutritionDefaultSlots;
    }
  }
  final blocked = (blockedSlots?[DateFormat('yyyy-MM-dd').format(date)] as List?)
          ?.map((e) => e.toString())
          .toSet() ??
      const <String>{};
  return base
      .where((s) => !blocked.contains(s) && !isPastNutritionSlot(s, date))
      .toList();
}
