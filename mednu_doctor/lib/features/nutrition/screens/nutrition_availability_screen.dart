import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../../shared_core/widgets/pending_review_banner.dart';
import '../services/nutrition_appointment_service.dart';
import '../services/nutritionist_profile_service.dart';
import '../utils/nutrition_slot_utils.dart';

/// Dietician "Availability": weekly schedule + slot length + consultation
/// modes (+ clinic for in-person) + per-date blocked slots, stored on
/// `nutritionist_profiles/{uid}` in the same shape as the doctor's
/// availability and mirrored to the patient-facing `nutritionists/{uid}` by
/// `onNutritionistProfileWriteForVisibility`.
class NutritionAvailabilityScreen extends StatefulWidget {
  const NutritionAvailabilityScreen({super.key});

  @override
  State<NutritionAvailabilityScreen> createState() => _NutritionAvailabilityScreenState();
}

class _NutritionAvailabilityScreenState extends State<NutritionAvailabilityScreen> {
  final Map<String, bool> _enabled = {
    for (final d in kNutritionDayKeys) d: !['Sat', 'Sun'].contains(d),
  };
  final Map<String, TimeOfDay> _start = {
    for (final d in kNutritionDayKeys) d: TimeOfDay(hour: ['Sat', 'Sun'].contains(d) ? 10 : 9, minute: 0),
  };
  final Map<String, TimeOfDay> _end = {
    for (final d in kNutritionDayKeys) d: TimeOfDay(hour: ['Sat', 'Sun'].contains(d) ? 14 : 17, minute: 0),
  };
  final Map<String, String?> _errors = {};

  int _slotDuration = 30;
  bool _online = true;
  bool _inPerson = false;
  final _clinicNameCtrl = TextEditingController();
  final _clinicAddressCtrl = TextEditingController();
  Map<String, List<String>> _blocked = {};

  // Live (approved) clinic details + profile status, used to route clinic
  // edits through admin review once the profile is active.
  String _status = 'pending';
  String _liveClinicName = '';
  String _liveClinicAddress = '';
  bool _hasPendingChanges = false;

  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clinicNameCtrl.dispose();
    _clinicAddressCtrl.dispose();
    super.dispose();
  }

  TimeOfDay _parse(String? t, TimeOfDay fallback) {
    final p = (t ?? '').split(':');
    if (p.length != 2) return fallback;
    return TimeOfDay(hour: int.tryParse(p[0]) ?? fallback.hour, minute: int.tryParse(p[1]) ?? 0);
  }

  String _store(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _display(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  Future<void> _load() async {
    final uid = NutritionistProfileService.currentUid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('nutritionist_profiles').doc(uid).get();
      final data = doc.data() ?? const <String, dynamic>{};
      _online = data['isOnlineAvailable'] as bool? ?? true;
      _inPerson = data['isInPersonAvailable'] as bool? ?? false;
      _status = data['status'] as String? ?? 'pending';
      _hasPendingChanges = data['hasPendingChanges'] as bool? ?? false;
      final avail = data['availability'] as Map<String, dynamic>?;
      _liveClinicName = (avail?['clinicName'] as String?) ?? '';
      _liveClinicAddress = (avail?['clinicAddress'] as String?) ?? '';
      // Show what the dietician last submitted if it is still awaiting review.
      final pendingAvail = (data['pendingChanges'] as Map?)?['availability'] as Map?;
      final pendingName = _hasPendingChanges ? (pendingAvail?['clinicName'] as String?) : null;
      final pendingAddress = _hasPendingChanges ? (pendingAvail?['clinicAddress'] as String?) : null;
      _clinicNameCtrl.text = pendingName ?? _liveClinicName;
      _clinicAddressCtrl.text = pendingAddress ?? _liveClinicAddress;
      if (avail != null) {
        _slotDuration = (avail['slotDuration'] as num?)?.toInt() ?? 30;
        final schedule = avail['schedule'] as Map<String, dynamic>?;
        if (schedule != null) {
          for (final d in kNutritionDayKeys) {
            final ds = schedule[d] as Map<String, dynamic>?;
            if (ds == null) continue;
            _enabled[d] = ds['enabled'] as bool? ?? false;
            _start[d] = _parse(ds['start'] as String?, _start[d]!);
            _end[d] = _parse(ds['end'] as String?, _end[d]!);
          }
        }
        final blocked = avail['blockedSlots'] as Map<String, dynamic>?;
        if (blocked != null) {
          _blocked = blocked.map((k, v) => MapEntry(k, List<String>.from(v as List? ?? const [])));
        }
      }
    } catch (_) {
      _loadFailed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  String? _validateDay(String d) {
    final s = _start[d]!.hour * 60 + _start[d]!.minute;
    final e = _end[d]!.hour * 60 + _end[d]!.minute;
    if (e <= s) return 'End time must be after start time';
    if (e - s < _slotDuration) return 'Window is shorter than one $_slotDuration-minute slot';
    return null;
  }

  int _slotsForDay(String d) => _enabled[d] == true && _validateDay(d) == null
      ? nutritionDaySlots({
          'enabled': true,
          'start': _store(_start[d]!),
          'end': _store(_end[d]!),
        }, _slotDuration)
          .length
      : 0;

  Future<void> _pickTime(String d, bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: isStart ? _start[d]! : _end[d]!);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start[d] = picked;
      } else {
        _end[d] = picked;
      }
      _errors[d] = _validateDay(d);
    });
  }

  Future<void> _save() async {
    final uid = NutritionistProfileService.currentUid;
    if (uid == null || _saving) return;
    if (!_online && !_inPerson) {
      FeedbackService.showError(context, 'Turn on at least one consultation mode.');
      return;
    }
    if (_inPerson && _clinicNameCtrl.text.trim().isEmpty) {
      FeedbackService.showError(context, 'Add your clinic name for in-person consultations.');
      return;
    }
    setState(() {
      for (final d in kNutritionDayKeys) {
        _errors[d] = _enabled[d] == true ? _validateDay(d) : null;
      }
    });
    if (_errors.values.any((e) => e != null)) {
      FeedbackService.showError(context, 'Fix the highlighted days before saving.');
      return;
    }
    if (_enabled.values.every((v) => !v)) {
      FeedbackService.showError(context, 'Enable at least one working day.');
      return;
    }
    setState(() => _saving = true);
    try {
      final newClinicName = _inPerson ? _clinicNameCtrl.text.trim() : '';
      final newClinicAddress = _inPerson ? _clinicAddressCtrl.text.trim() : '';
      final clinicChanged = newClinicName != _liveClinicName || newClinicAddress != _liveClinicAddress;
      await NutritionistProfileService.saveAvailability(
        uid,
        slotDuration: _slotDuration,
        schedule: {
          for (final d in kNutritionDayKeys)
            d: {'enabled': _enabled[d], 'start': _store(_start[d]!), 'end': _store(_end[d]!)},
        },
        isOnlineAvailable: _online,
        isInPersonAvailable: _inPerson,
        clinicName: newClinicName,
        clinicAddress: newClinicAddress,
        currentStatus: _status,
        clinicChanged: clinicChanged,
      );
      final sentForReview = _status == 'active' && clinicChanged;
      if (sentForReview) {
        _hasPendingChanges = true;
      } else if (_status != 'active') {
        _liveClinicName = newClinicName;
        _liveClinicAddress = newClinicAddress;
      }
      if (mounted) {
        FeedbackService.showSuccess(
            context,
            sentForReview
                ? 'Availability saved. Clinic details sent for admin review'
                : 'Availability saved');
      }
    } catch (_) {
      if (mounted) FeedbackService.showError(context, 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openBlockSheet() async {
    final uid = NutritionistProfileService.currentUid;
    if (uid == null) return;
    // Offer slots from the schedule currently on screen (saved or not).
    final availability = <String, dynamic>{
      'slotDuration': _slotDuration,
      'schedule': {
        for (final d in kNutritionDayKeys)
          d: {'enabled': _enabled[d], 'start': _store(_start[d]!), 'end': _store(_end[d]!)},
      },
    };
    final updated = await showModalBottomSheet<Map<String, List<String>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BlockSlotsSheet(uid: uid, availability: availability, blocked: _blocked),
    );
    if (updated != null && mounted) {
      setState(() => _blocked = updated);
      FeedbackService.showSuccess(context, 'Blocked slots updated');
    }
  }

  int get _blockedCount {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _blocked.entries.where((e) => e.key.compareTo(today) >= 0).fold(0, (s, e) => s + e.value.length);
  }

  @override
  Widget build(BuildContext context) {
    final totalSlots = kNutritionDayKeys.fold<int>(0, (s, d) => s + _slotsForDay(d));
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
        title: const Text('My Availability',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 18)),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                )
              : TextButton(
                  onPressed: _loading || _loadFailed ? null : _save,
                  child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
        ],
      ),
      body: _loading
          ? ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: List.generate(
                5,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: SkeletonBox(width: double.infinity, height: 72, radius: 16),
                ),
              ),
            )
          : _loadFailed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textHint),
                      const SizedBox(height: 12),
                      const Text('Could not load your availability.', style: AppTextStyles.bodyMedium),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _loadFailed = false;
                          });
                          _load();
                        },
                        child: const Text('Retry'),
                      ),
                    ]),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + MediaQuery.of(context).viewInsets.bottom),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (_hasPendingChanges && _status == 'active') const PendingReviewBanner(),
                    _modesCard(),
                    const SizedBox(height: 16),
                    _durationCard(),
                    const SizedBox(height: 12),
                    Container(
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
                            '$totalSlots slots / week · ${kNutritionDayKeys.where((d) => _enabled[d] == true).length} working days',
                            style: AppTextStyles.bodySmall
                                .copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    TapScale(
                      onTap: _openBlockSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.event_busy_rounded, color: AppColors.error, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Block a Slot', style: AppTextStyles.labelLarge),
                              Text(
                                _blockedCount == 0
                                    ? 'Have a sudden meeting? Block just that time.'
                                    : '$_blockedCount upcoming slot${_blockedCount == 1 ? '' : 's'} blocked',
                                style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
                              ),
                            ]),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Weekly Schedule', style: AppTextStyles.h4),
                    const SizedBox(height: 12),
                    for (final d in kNutritionDayKeys) _dayCard(d),
                    const SizedBox(height: 8),
                    GradientButton(
                      label: 'Save Availability',
                      icon: Icons.save_rounded,
                      isLoading: _saving,
                      onTap: _saving ? null : _save,
                    ),
                  ],
                ),
    );
  }

  Widget _modesCard() {
    Widget row(IconData icon, String title, String sub, bool value, ValueChanged<bool> onChanged) => Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTextStyles.labelLarge),
              Text(sub, style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
            ]),
          ),
          Switch(value: value, activeThumbColor: AppColors.primary, onChanged: onChanged),
        ]);

    return PremiumCard(
      padding: const EdgeInsets.all(16),
      radius: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Consultation Modes', style: AppTextStyles.labelLarge),
        if (_inPerson && _status == 'active')
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Clinic details are reviewed by admin before patients see changes.',
                style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
          ),
        const SizedBox(height: 12),
        row(Icons.videocam_rounded, 'Online', 'Video / chat consultations', _online,
            (v) => setState(() => _online = v)),
        const Divider(height: 20),
        row(Icons.local_hospital_rounded, 'In-person', 'Patients visit your clinic', _inPerson,
            (v) => setState(() => _inPerson = v)),
        if (_inPerson) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _clinicNameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Clinic name', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _clinicAddressCtrl,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Clinic address', border: OutlineInputBorder(), isDense: true),
          ),
        ],
      ]),
    );
  }

  Widget _durationCard() {
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      radius: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Appointment Slot Duration', style: AppTextStyles.labelLarge),
        Text('Time per consultation', style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
        const SizedBox(height: 12),
        Row(
          children: [15, 30, 45, 60].map((min) {
            final selected = _slotDuration == min;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _slotDuration = min;
                  for (final d in kNutritionDayKeys) {
                    if (_enabled[d] == true) _errors[d] = _validateDay(d);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? const LinearGradient(colors: [AppColors.primary, AppColors.secondary])
                        : null,
                    color: selected ? null : AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$min',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: selected ? Colors.white : AppColors.textPrimary)),
                    Text('min',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            color: selected ? Colors.white70 : AppColors.textHint)),
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _dayCard(String d) {
    final enabled = _enabled[d] == true;
    final count = _slotsForDay(d);
    final err = _errors[d];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: err != null
                ? AppColors.error
                : enabled
                    ? AppColors.primary.withValues(alpha: 0.25)
                    : AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(d,
              style: AppTextStyles.labelLarge
                  .copyWith(color: enabled ? AppColors.textPrimary : AppColors.textSecondary)),
          const Spacer(),
          if (enabled && count > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count slots', style: AppTextStyles.labelSmall.copyWith(color: AppColors.success)),
            ),
          Switch(
            value: enabled,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() {
              _enabled[d] = v;
              _errors[d] = v ? _validateDay(d) : null;
            }),
          ),
        ]),
        if (enabled) ...[
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: _timeButton('Start', _display(_start[d]!), () => _pickTime(d, true))),
            const SizedBox(width: 10),
            Expanded(child: _timeButton('End', _display(_end[d]!), () => _pickTime(d, false))),
          ]),
          if (err != null) ...[
            const SizedBox(height: 8),
            Text(err, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
          ],
        ],
      ]),
    );
  }

  Widget _timeButton(String label, String time, VoidCallback onTap) => TapScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textHint, fontWeight: FontWeight.w500, fontFamily: 'Inter')),
            Text(time,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
          ]),
        ),
      );
}

/// Bottom sheet to block / unblock individual slots on one date. Saves
/// straight to `availability.blockedSlots` and pops the updated map.
class _BlockSlotsSheet extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> availability;
  final Map<String, List<String>> blocked;
  const _BlockSlotsSheet({required this.uid, required this.availability, required this.blocked});

  @override
  State<_BlockSlotsSheet> createState() => _BlockSlotsSheetState();
}

class _BlockSlotsSheetState extends State<_BlockSlotsSheet> {
  late DateTime _date;
  late Map<String, List<String>> _all;
  Set<String> _pending = {};
  Set<String> _booked = {};
  bool _loadingDay = true;
  bool _saving = false;

  String get _key => DateFormat('yyyy-MM-dd').format(_date);

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _date = DateTime(n.year, n.month, n.day);
    _all = {for (final e in widget.blocked.entries) e.key: List<String>.from(e.value)};
    _loadDay();
  }

  Future<void> _loadDay() async {
    setState(() {
      _loadingDay = true;
      _pending = {...(_all[_key] ?? const [])};
    });
    var booked = <String>{};
    try {
      booked = await NutritionAppointmentService.takenSlots(widget.uid, _key);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _booked = booked;
      _loadingDay = false;
    });
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 60)),
    );
    if (picked == null) return;
    setState(() => _date = picked);
    await _loadDay();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = {..._all};
      if (_pending.isEmpty) {
        updated.remove(_key);
      } else {
        updated[_key] = _pending.toList()..sort();
      }
      await NutritionistProfileService.saveBlockedSlots(widget.uid, updated);
      if (mounted) Navigator.of(context).pop(updated);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        FeedbackService.showError(context, 'Could not save. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Schedule-only slots (blocked ones included) minus the already started.
    final schedule = widget.availability['schedule'] as Map<String, dynamic>;
    final slots = nutritionDaySlots(
      schedule[kNutritionDayKeys[_date.weekday - 1]] as Map<String, dynamic>?,
      (widget.availability['slotDuration'] as num?)?.toInt() ?? 30,
    ).where((s) => !isPastNutritionSlot(s, _date)).toList();

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 14),
        const Text('Block a Slot', style: AppTextStyles.h4),
        const SizedBox(height: 4),
        Text("Pick a date, then tap the slots to block. Patients can't book blocked slots.",
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text(DateFormat('EEEE, MMM d, yyyy').format(_date), style: AppTextStyles.labelLarge),
          ),
          TextButton(onPressed: _pickDate, child: const Text('Change date')),
        ]),
        Flexible(
          child: SingleChildScrollView(
            child: _loadingDay
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : slots.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            "No slots to block — you're not scheduled this day, or they have already passed.",
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
                          ),
                        ),
                      )
                    : Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: slots.map((s) {
                          final booked = _booked.contains(s);
                          final blocked = _pending.contains(s);
                          final fg = booked
                              ? AppColors.textHint
                              : blocked
                                  ? AppColors.error
                                  : AppColors.textPrimary;
                          return GestureDetector(
                            onTap: booked
                                ? null
                                : () => setState(() => blocked ? _pending.remove(s) : _pending.add(s)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: blocked
                                    ? AppColors.error.withValues(alpha: 0.08)
                                    : booked
                                        ? AppColors.textHint.withValues(alpha: 0.08)
                                        : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: blocked ? AppColors.error.withValues(alpha: 0.4) : AppColors.divider),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (booked || blocked) ...[
                                  Icon(booked ? Icons.event_busy_rounded : Icons.block_rounded, size: 14, color: fg),
                                  const SizedBox(width: 6),
                                ],
                                Text(s,
                                    style: TextStyle(
                                        fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Greyed slots already have an appointment.',
            style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
        const SizedBox(height: 12),
        GradientButton(
          label: 'Save Changes',
          icon: Icons.event_busy_rounded,
          isLoading: _saving,
          onTap: _saving ? null : _save,
        ),
      ]),
    );
  }
}
