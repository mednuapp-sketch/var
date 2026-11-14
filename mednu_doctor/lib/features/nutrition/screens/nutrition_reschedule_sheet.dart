import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../models/nutrition_appointment.dart';
import '../services/nutrition_appointment_service.dart';
import '../utils/nutrition_slot_utils.dart';

/// Provider-side reschedule: propose a new date/slot taken from the
/// dietician's own published availability (minus blocked, already-booked and
/// already-started slots). Returns true once the move is written.
Future<bool> showNutritionRescheduleSheet(
  BuildContext context, {
  required NutritionAppointment appointment,
  required String nutritionistId,
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RescheduleSheet(appointment: appointment, nutritionistId: nutritionistId),
  );
  return done == true;
}

class _RescheduleSheet extends StatefulWidget {
  final NutritionAppointment appointment;
  final String nutritionistId;
  const _RescheduleSheet({required this.appointment, required this.nutritionistId});

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  late final List<DateTime> _dates;
  late DateTime _date;
  Map<String, dynamic>? _availability;
  Set<String> _taken = {};
  String? _slot;
  bool _loadingProfile = true;
  bool _profileFailed = false;
  bool _loadingDay = false;
  bool _saving = false;

  String get _key => DateFormat('yyyy-MM-dd').format(_date);

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    _dates = List.generate(30, (i) => today.add(Duration(days: i)));
    _date = _dates.first;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('nutritionist_profiles')
          .doc(widget.nutritionistId)
          .get();
      _availability = doc.data()?['availability'] as Map<String, dynamic>?;
      _profileFailed = false;
    } catch (_) {
      _profileFailed = true;
    }
    if (!mounted) return;
    setState(() => _loadingProfile = false);
    if (!_profileFailed) await _loadDay();
  }

  Future<void> _loadDay() async {
    setState(() {
      _loadingDay = true;
      _slot = null;
    });
    var taken = <String>{};
    try {
      taken = await NutritionAppointmentService.takenSlots(widget.nutritionistId, _key,
          exceptAppointmentId: widget.appointment.id);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _taken = taken;
      _loadingDay = false;
    });
  }

  Future<void> _confirm() async {
    final slot = _slot;
    if (slot == null || _saving) return;
    setState(() => _saving = true);
    try {
      await NutritionAppointmentService.reschedule(widget.appointment.id, _key, slot);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      FeedbackService.showError(context, 'Could not reschedule. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = nutritionOfferedSlots(_availability, _date)
        .where((s) => !isPastNutritionSlot(s, _date))
        .toList();
    final isCurrent = _key == widget.appointment.date && _slot == widget.appointment.timeSlot;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
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
        const Text('Reschedule Appointment', style: AppTextStyles.h4),
        const SizedBox(height: 4),
        Text(
          'Currently ${widget.appointment.date} · ${widget.appointment.timeSlot}. '
          '${widget.appointment.userName} will be notified of the new time.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        if (_loadingProfile)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_profileFailed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Could not load your availability.', style: AppTextStyles.bodyMedium),
                TextButton(
                  onPressed: () {
                    setState(() => _loadingProfile = true);
                    _loadProfile();
                  },
                  child: const Text('Retry'),
                ),
              ]),
            ),
          )
        else ...[
          SizedBox(
            height: 70,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _dates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final d = _dates[i];
                final selected = d == _date;
                return GestureDetector(
                  onTap: () {
                    setState(() => _date = d);
                    _loadDay();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 56,
                    decoration: BoxDecoration(
                      gradient: selected
                          ? const LinearGradient(colors: [AppColors.primary, AppColors.secondary])
                          : null,
                      color: selected ? null : AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(DateFormat('EEE').format(d),
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: selected ? Colors.white70 : AppColors.textHint)),
                        Text(DateFormat('d').format(d),
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: selected ? Colors.white : AppColors.textPrimary)),
                        Text(DateFormat('MMM').format(d),
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                color: selected ? Colors.white70 : AppColors.textHint)),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: _loadingDay
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : slots.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              "You have no open slots on this day. Pick another date, or update your Availability.",
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
                            ),
                          ),
                        )
                      : Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: slots.map((s) {
                            final taken = _taken.contains(s);
                            final selected = _slot == s;
                            return GestureDetector(
                              onTap: taken ? null : () => setState(() => _slot = s),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  gradient: selected
                                      ? const LinearGradient(colors: [AppColors.primary, AppColors.secondary])
                                      : null,
                                  color: selected
                                      ? null
                                      : taken
                                          ? AppColors.background
                                          : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: selected ? Colors.transparent : AppColors.divider),
                                ),
                                child: Text(s,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? Colors.white
                                          : taken
                                              ? AppColors.textHint
                                              : AppColors.textPrimary,
                                      decoration: taken ? TextDecoration.lineThrough : null,
                                    )),
                              ),
                            );
                          }).toList(),
                        ),
            ),
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: 'Confirm New Time',
            icon: Icons.event_repeat_rounded,
            isLoading: _saving,
            onTap: (_slot == null || isCurrent || _saving) ? null : _confirm,
          ),
        ],
      ]),
    );
  }
}
