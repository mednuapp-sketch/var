import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../providers/nutrition_provider.dart';
import '../services/nutrition_service.dart';
import '../utils/nutrition_slot_utils.dart';
import 'book_nutrition_appointment_screen.dart'
    show NutritionDateStrip, NutritionSlotGrid;

const _kGreen = Color(0xFF2E7D32);
const _kGreenBg = Color(0xFFF1F8F1);

/// Patient-side reschedule of a pending/confirmed nutrition appointment.
/// Reuses the booking screen's date strip + slot grid; the slot list comes
/// from the dietician's published schedule (`nutritionists/{id}`), minus
/// blocked, taken (`nutrition_slots`) and already-started slots. Pops `true`
/// after a successful write. Push with `Navigator.push(MaterialPageRoute)`.
class RescheduleNutritionAppointmentScreen extends ConsumerStatefulWidget {
  final String appointmentId;
  final String nutritionistId;
  final String nutritionistName;
  final String currentDate; // yyyy-MM-dd
  final String currentTimeSlot;

  const RescheduleNutritionAppointmentScreen({
    super.key,
    required this.appointmentId,
    required this.nutritionistId,
    required this.nutritionistName,
    required this.currentDate,
    required this.currentTimeSlot,
  });

  @override
  ConsumerState<RescheduleNutritionAppointmentScreen> createState() =>
      _RescheduleNutritionAppointmentScreenState();
}

class _RescheduleNutritionAppointmentScreenState
    extends ConsumerState<RescheduleNutritionAppointmentScreen> {
  late DateTime _selectedDate;
  late final List<DateTime> _dateRange;
  String? _selectedSlot;
  bool _saving = false;

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = List.generate(30, (i) => now.add(Duration(days: i + 1)));
    _selectedDate = _dateRange.first;
  }

  Future<void> _confirm() async {
    final slot = _selectedSlot;
    if (slot == null || _saving) return;
    setState(() => _saving = true);
    try {
      if (await NutritionService.isSlotTaken(
          widget.nutritionistId, _dateKey, slot,
          exceptAppointmentId: widget.appointmentId)) {
        if (!mounted) return;
        setState(() {
          _selectedSlot = null;
          _saving = false;
        });
        _snack('That slot was just booked. Please pick another time.', true);
        return;
      }
      await NutritionService.rescheduleAppointment(
          widget.appointmentId, _dateKey, slot);
      if (!mounted) return;
      _snack(
          'Appointment rescheduled to '
          '${DateFormat('MMM d').format(_selectedDate)} at $slot.',
          false);
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Could not reschedule. Please try again.', true);
    }
  }

  void _snack(String msg, bool error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : _kGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final nutritionist =
        ref.watch(nutritionistDetailProvider(widget.nutritionistId));
    final booked = ref
        .watch(bookedSlotsProvider((widget.nutritionistId, _dateKey)))
        .valueOrNull;
    final n = nutritionist.valueOrNull;
    final slots = n == null
        ? const <String>[]
        : nutritionSlotsFor(
            slots: n.slots,
            scheduleConfigured: n.scheduleConfigured,
            blockedSlots: n.blockedSlots,
            date: _selectedDate,
          );
    final isCurrent = _dateKey == widget.currentDate &&
        _selectedSlot == widget.currentTimeSlot;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Reschedule', style: AppTextStyles.h3),
        centerTitle: true,
        backgroundColor: context.appSurface,
        foregroundColor: context.appTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: context.appSurface,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: (_selectedSlot == null || isCurrent || _saving)
                  ? null
                  : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                disabledBackgroundColor: _kGreen.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Confirm New Time',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.white,
                      )),
            ),
          ),
        ),
      ),
      body: nutritionist.hasError
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'Could not load available times. Please check your connection and try again.',
                    textAlign: TextAlign.center),
              ),
            )
          : n == null
              ? const Center(child: CircularProgressIndicator(color: _kGreen))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _kGreenBg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_repeat_rounded,
                                color: _kGreen, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Currently ${widget.currentDate} at ${widget.currentTimeSlot} '
                                'with ${widget.nutritionistName}',
                                style: AppTextStyles.bodySmall.copyWith(
                                    color: _kGreen,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Select Date',
                          style: AppTextStyles.labelLarge
                              .copyWith(color: context.appTextPrimary)),
                      const SizedBox(height: 10),
                      NutritionDateStrip(
                        dates: _dateRange,
                        selected: _selectedDate,
                        onSelect: (d) => setState(() {
                          _selectedDate = d;
                          _selectedSlot = null;
                        }),
                      ),
                      const SizedBox(height: 20),
                      Text('Select Time Slot',
                          style: AppTextStyles.labelLarge
                              .copyWith(color: context.appTextPrimary)),
                      const SizedBox(height: 10),
                      NutritionSlotGrid(
                        slots: slots,
                        bookedSlots: booked ?? const [],
                        selected: _selectedSlot,
                        onSelect: (s) => setState(() => _selectedSlot = s),
                      ),
                    ],
                  ),
                ),
    );
  }
}
