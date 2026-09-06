import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../../core/widgets/ux_widgets.dart';

/// Lets a doctor mark specific slots on a specific date as unavailable
/// (e.g. a sudden offline meeting), without touching the recurring weekly
/// schedule managed by [AvailabilityScreen]. Blocked slots are stored at
/// doctors/{uid}.availability.blockedSlots["yyyy-MM-dd"] = [time, ...] and
/// the patient app's slot picker filters them out the same way it filters
/// already-booked slots.
class BlockSlotsScreen extends StatefulWidget {
  const BlockSlotsScreen({super.key});
  @override
  State<BlockSlotsScreen> createState() => _BlockSlotsScreenState();
}

class _BlockSlotsScreenState extends State<BlockSlotsScreen> {
  static const _dayKeys = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _schedule;
  int _slotDuration = 30;
  Map<String, List<String>> _blockedByDate = {};
  Set<String> _pendingBlocked = {};
  Set<String> _bookedForDate = {};

  bool _loading = true;
  bool _loadingDay = false;
  bool _saving = false;

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc =
          await FirebaseFirestore.instance.collection('doctors').doc(uid).get();
      final avail = doc.data()?['availability'] as Map<String, dynamic>?;
      _schedule = avail?['schedule'] as Map<String, dynamic>?;
      _slotDuration = (avail?['slotDuration'] as num?)?.toInt() ?? 30;
      final blocked = avail?['blockedSlots'] as Map<String, dynamic>?;
      if (blocked != null) {
        _blockedByDate = blocked.map(
            (k, v) => MapEntry(k, (v as List).cast<String>()));
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    await _loadDay();
  }

  Future<void> _loadDay() async {
    final uid = DoctorAuthService.currentUid;
    setState(() {
      _loadingDay = true;
      _pendingBlocked = {...(_blockedByDate[_dateKey] ?? const [])};
    });
    var booked = <String>{};
    if (uid != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('appointments')
            .where('doctorId', isEqualTo: uid)
            .where('date', isEqualTo: _dateKey)
            .where('status', isEqualTo: 'booked')
            .get();
        booked = snap.docs.map((d) => d['time'] as String? ?? '').toSet();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _bookedForDate = booked;
      _loadingDay = false;
    });
  }

  /// Mirrors the slot-generation formula in the patient app's doctor profile
  /// screen exactly, so the time strings line up when compared for equality.
  List<String> _slotsForDate(DateTime date) {
    final dayName = _dayKeys[date.weekday - 1];
    final ds = _schedule?[dayName] as Map<String, dynamic>?;
    if (ds == null || ds['enabled'] != true) return [];
    final startStr = ds['start'] as String? ?? '09:00';
    final endStr = ds['end'] as String? ?? '17:00';
    try {
      final sp = startStr.split(':');
      final ep = endStr.split(':');
      final startMins = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final endMins = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      final slots = <String>[];
      for (int m = startMins; m + _slotDuration <= endMins; m += _slotDuration) {
        final h = m ~/ 60;
        final min = m % 60;
        final period = h < 12 ? 'AM' : 'PM';
        final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
        slots.add(
            '${displayH.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')} $period');
      }
      return slots;
    } catch (_) {
      return [];
    }
  }

  bool _isPast(String slot, DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d.isAfter(today)) return false;
    if (d.isBefore(today)) return true;
    try {
      final parts = slot.trim().split(' ');
      final hm = parts[0].split(':');
      int h = int.parse(hm[0]);
      final min = int.parse(hm[1]);
      if (parts[1].toUpperCase() == 'PM' && h != 12) h += 12;
      if (parts[1].toUpperCase() == 'AM' && h == 12) h = 0;
      return DateTime(now.year, now.month, now.day, h, min).isBefore(now);
    } catch (_) {
      return false;
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _loadDay();
    }
  }

  Future<void> _save() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      final updated = Map<String, List<String>>.from(_blockedByDate);
      if (_pendingBlocked.isEmpty) {
        updated.remove(_dateKey);
      } else {
        updated[_dateKey] = _pendingBlocked.toList()..sort();
      }
      await FirebaseFirestore.instance.collection('doctors').doc(uid).update({
        'availability.blockedSlots': updated,
        'availability.updatedAt': FieldValue.serverTimestamp(),
      });
      _blockedByDate = updated;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Slots updated ✅'),
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

  @override
  Widget build(BuildContext context) {
    final slots = _slotsForDate(_selectedDate)
        .where((s) => !_isPast(s, _selectedDate))
        .toList();
    final isToday = _isSameDay(_selectedDate, DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.safeBack(),
        ),
        title: const Text('Block a Slot',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text('Save',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(
                  "Pick a date, then tap the slots you want to block. "
                  "Patients won't be able to book blocked slots.",
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                PremiumCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.calendar_today_rounded,
                          color: AppColors.primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              isToday
                                  ? 'Today'
                                  : DateFormat('EEEE').format(_selectedDate),
                              style: AppTextStyles.labelLarge),
                          Text(
                              DateFormat('MMM d, yyyy').format(_selectedDate),
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textHint)),
                        ],
                      ),
                    ),
                    TextButton(onPressed: _pickDate, child: const Text('Change')),
                  ]),
                ),
                const SizedBox(height: 20),
                if (_loadingDay)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (slots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        isToday
                            ? "No slots left to block today — they're either "
                                "past or you're not scheduled to work today."
                            : "You're not scheduled to work this day, so "
                                "there's nothing to block.",
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textHint),
                      ),
                    ),
                  )
                else ...[
                  Row(children: [
                    const Text('Tap to block / unblock', style: AppTextStyles.h4),
                    const Spacer(),
                    InfoChip(
                      icon: Icons.block_rounded,
                      label: '${_pendingBlocked.length} blocked',
                      color: AppColors.error,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: slots.map((slot) {
                      final isBooked = _bookedForDate.contains(slot);
                      final isBlocked = _pendingBlocked.contains(slot);
                      return _SlotChip(
                        label: slot,
                        state: isBooked
                            ? _SlotState.booked
                            : isBlocked
                                ? _SlotState.blocked
                                : _SlotState.open,
                        onTap: isBooked
                            ? null
                            : () => setState(() {
                                  if (isBlocked) {
                                    _pendingBlocked.remove(slot);
                                  } else {
                                    _pendingBlocked.add(slot);
                                  }
                                }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Row(children: [
                      _Legend(color: AppColors.divider, label: 'Open'),
                      SizedBox(width: 14),
                      _Legend(color: AppColors.error, label: 'Blocked'),
                      SizedBox(width: 14),
                      _Legend(color: AppColors.textHint, label: 'Already booked'),
                    ]),
                  ),
                ],
                const SizedBox(height: 28),
                GradientButton(
                  label: 'Save Changes',
                  icon: Icons.event_busy_rounded,
                  isLoading: _saving,
                  onTap: _saving ? null : _save,
                ),
              ],
            ),
    );
  }
}

enum _SlotState { open, blocked, booked }

class _SlotChip extends StatelessWidget {
  final String label;
  final _SlotState state;
  final VoidCallback? onTap;
  const _SlotChip({required this.label, required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    late final Color bg, border, fg;
    IconData? icon;
    switch (state) {
      case _SlotState.open:
        bg = Colors.white;
        border = AppColors.divider;
        fg = AppColors.textPrimary;
        break;
      case _SlotState.blocked:
        bg = AppColors.error.withValues(alpha: 0.08);
        border = AppColors.error.withValues(alpha: 0.4);
        fg = AppColors.error;
        icon = Icons.block_rounded;
        break;
      case _SlotState.booked:
        bg = AppColors.textHint.withValues(alpha: 0.08);
        border = AppColors.divider;
        fg = AppColors.textHint;
        icon = Icons.event_busy_rounded;
        break;
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
        ],
        Text(label,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg)),
      ]),
    );

    return onTap == null ? chip : TapScale(onTap: onTap, child: chip);
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color),
        ),
      ),
      const SizedBox(width: 5),
      Text(label,
          style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
    ]);
  }
}
