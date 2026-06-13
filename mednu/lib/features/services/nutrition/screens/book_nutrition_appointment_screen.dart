import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../providers/nutrition_provider.dart';
import '../../../../core/widgets/ux_widgets.dart';

class BookNutritionAppointmentScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> extra;
  const BookNutritionAppointmentScreen({super.key, required this.extra});

  @override
  ConsumerState<BookNutritionAppointmentScreen> createState() =>
      _BookNutritionAppointmentScreenState();
}

class _BookNutritionAppointmentScreenState
    extends ConsumerState<BookNutritionAppointmentScreen> {
  String _consultationType = 'online';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String? _selectedSlot;
  String _healthGoal = 'Weight Loss';
  final _notesCtrl = TextEditingController();

  static const _goals = [
    'Weight Loss', 'Weight Gain', 'Diabetes Diet',
    'Pregnancy Nutrition', 'Sports Nutrition', 'PCOS Diet',
    'Heart Healthy Diet', 'General Wellness',
  ];

  static const _defaultSlots = [
    '09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM',
    '11:00 AM', '11:30 AM', '02:00 PM', '02:30 PM',
    '03:00 PM', '03:30 PM', '04:00 PM', '04:30 PM',
    '05:00 PM', '06:00 PM',
  ];

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);
  String get _nutritionistId => widget.extra['nutritionistId'] as String? ?? '';
  String get _nutritionistName => widget.extra['nutritionistName'] as String? ?? '';
  String get _specialization => widget.extra['nutritionistSpecialization'] as String? ?? '';
  double get _fee => (widget.extra['fee'] as num?)?.toDouble() ?? 0.0;
  bool get _isOnline => widget.extra['isOnline'] as bool? ?? true;
  bool get _isInPerson => widget.extra['isInPerson'] as bool? ?? false;

  List<String> get _availableSlots {
    final slots = widget.extra['slots'] as Map<String, dynamic>?;
    if (slots == null) return _defaultSlots;
    final dayName = DateFormat('EEEE').format(_selectedDate);
    final daySlots = slots[dayName] as List?;
    return daySlots != null && daySlots.isNotEmpty
        ? List<String>.from(daySlots)
        : _defaultSlots;
  }

  @override
  void initState() {
    super.initState();
    if (!_isOnline && _isInPerson) _consultationType = 'in_person';
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF2E7D32)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedSlot = null;
      });
    }
  }

  Future<void> _confirmBooking() async {
    if (_selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a time slot'), backgroundColor: Colors.red),
      );
      return;
    }

    final success = await ref.read(nutritionBookingProvider.notifier).bookAppointment(
          nutritionistId: _nutritionistId,
          nutritionistName: _nutritionistName,
          nutritionistSpecialization: _specialization,
          consultationType: _consultationType,
          date: _dateKey,
          timeSlot: _selectedSlot!,
          notes: _notesCtrl.text.trim(),
          fee: _fee,
          healthGoal: _healthGoal,
        );

    if (!mounted) return;
    if (success) {
      _showConfirmationDialog();
    } else {
      final error = ref.read(nutritionBookingProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Booking failed. Try again.'), backgroundColor: Colors.red),
      );
    }
  }

  void _showConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Color(0xFF2E7D32), size: 36),
              ),
              const SizedBox(height: 16),
              const Text('Appointment Booked!', style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Your consultation with $_nutritionistName has been booked for ${DateFormat('MMM d, yyyy').format(_selectedDate)} at $_selectedSlot.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.5), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.pop();
                    context.pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Done', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingState = ref.watch(nutritionBookingProvider);
    final bookedSlots = ref.watch(bookedSlotsProvider((_nutritionistId, _dateKey)));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
        title: const Text('Book Consultation', style: AppTextStyles.h3),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      bottomNavigationBar: _BottomBar(
        fee: _fee,
        isLoading: bookingState.isLoading,
        onBook: _confirmBooking,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NutritionistHeader(name: _nutritionistName, specialization: _specialization, fee: _fee),
            const SizedBox(height: 20),
            if (_isOnline || _isInPerson) ...[
              _SectionHeader(title: 'Consultation Type'),
              const SizedBox(height: 10),
              _ConsultationTypeSelector(
                isOnline: _isOnline,
                isInPerson: _isInPerson,
                selected: _consultationType,
                onSelect: (v) => setState(() => _consultationType = v),
              ),
              const SizedBox(height: 20),
            ],
            _SectionHeader(title: 'Select Date'),
            const SizedBox(height: 10),
            _DateSelector(selectedDate: _selectedDate, onTap: _pickDate),
            const SizedBox(height: 20),
            _SectionHeader(title: 'Select Time Slot'),
            const SizedBox(height: 10),
            bookedSlots.when(
              loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: SkeletonBox(width: double.infinity, height: 100, radius: 16)),
              error: (_, __) => _SlotGrid(slots: _availableSlots, bookedSlots: const [], selected: _selectedSlot, onSelect: (s) => setState(() => _selectedSlot = s)),
              data: (booked) => _SlotGrid(slots: _availableSlots, bookedSlots: booked, selected: _selectedSlot, onSelect: (s) => setState(() => _selectedSlot = s)),
            ),
            const SizedBox(height: 20),
            _SectionHeader(title: 'Health Goal'),
            const SizedBox(height: 10),
            _GoalDropdown(value: _healthGoal, goals: _goals, onChanged: (v) => setState(() => _healthGoal = v ?? _healthGoal)),
            const SizedBox(height: 20),
            _SectionHeader(title: 'Notes (Optional)'),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              style: AppTextStyles.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Describe your health concerns, dietary restrictions, etc.',
                hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF2E7D32))),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NutritionistHeader extends StatelessWidget {
  final String name;
  final String specialization;
  final double fee;
  const _NutritionistHeader({required this.name, required this.specialization, required this.fee});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.labelLarge),
                Text(specialization, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                Text('₹${fee.toInt()} / session', style: AppTextStyles.labelMedium.copyWith(color: const Color(0xFF2E7D32))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: AppTextStyles.labelLarge.copyWith(color: AppColors.textPrimary));
  }
}

class _ConsultationTypeSelector extends StatelessWidget {
  final bool isOnline;
  final bool isInPerson;
  final String selected;
  final ValueChanged<String> onSelect;

  const _ConsultationTypeSelector({
    required this.isOnline,
    required this.isInPerson,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isOnline)
          Expanded(child: _TypeCard(
            icon: Icons.videocam_rounded,
            label: 'Online',
            subtitle: 'Video/Chat Consult',
            isSelected: selected == 'online',
            onTap: () => onSelect('online'),
          )),
        if (isOnline && isInPerson) const SizedBox(width: 12),
        if (isInPerson)
          Expanded(child: _TypeCard(
            icon: Icons.location_on_rounded,
            label: 'In-Person',
            subtitle: 'Visit Clinic',
            isSelected: selected == 'in_person',
            onTap: () => onSelect('in_person'),
          )),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeCard({required this.icon, required this.label, required this.subtitle, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2E7D32) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? const Color(0xFF2E7D32) : AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : AppColors.textSecondary, size: 24),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: isSelected ? Colors.white : AppColors.textPrimary)),
            Text(subtitle, style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: isSelected ? Colors.white70 : AppColors.textHint)),
          ],
        ),
      ),
    );
  }
}

class _DateSelector extends StatelessWidget {
  final DateTime selectedDate;
  final VoidCallback onTap;

  const _DateSelector({required this.selectedDate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, color: Color(0xFF2E7D32), size: 22),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('EEEE').format(selectedDate), style: AppTextStyles.labelLarge),
                Text(DateFormat('dd MMM yyyy').format(selectedDate), style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Change', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotGrid extends StatelessWidget {
  final List<String> slots;
  final List<String> bookedSlots;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _SlotGrid({required this.slots, required this.bookedSlots, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: slots.map((slot) {
        final isBooked = bookedSlots.contains(slot);
        final isSelected = selected == slot;
        return GestureDetector(
          onTap: isBooked ? null : () => onSelect(slot),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isBooked
                  ? AppColors.background
                  : isSelected
                      ? const Color(0xFF2E7D32)
                      : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isBooked
                    ? AppColors.border.withValues(alpha:0.5)
                    : isSelected
                        ? const Color(0xFF2E7D32)
                        : AppColors.border,
              ),
            ),
            child: Text(
              slot,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isBooked
                    ? AppColors.textHint
                    : isSelected
                        ? Colors.white
                        : AppColors.textPrimary,
                decoration: isBooked ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _GoalDropdown extends StatelessWidget {
  final String value;
  final List<String> goals;
  final ValueChanged<String?> onChanged;

  const _GoalDropdown({required this.value, required this.goals, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
        onChanged: onChanged,
        items: goals.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final double fee;
  final bool isLoading;
  final VoidCallback onBook;

  const _BottomBar({required this.fee, required this.isLoading, required this.onBook});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.06), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total Fee', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
              Text('₹${fee.toInt()}', style: AppTextStyles.h3.copyWith(color: const Color(0xFF2E7D32))),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: isLoading ? null : onBook,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Confirm Booking', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
