import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/router/app_router.dart';
import '../providers/nutrition_provider.dart';
import '../../../../core/widgets/ux_widgets.dart';

// ── Nutrition theme ───────────────────────────────────────────────────────────
const _kGreen    = Color(0xFF2E7D32);
const _kGreenBg  = Color(0xFFF1F8F1);
const _kGradient = LinearGradient(
  colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class BookNutritionAppointmentScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> extra;
  const BookNutritionAppointmentScreen(
      {super.key, required this.extra});

  @override
  ConsumerState<BookNutritionAppointmentScreen> createState() =>
      _BookNutritionAppointmentScreenState();
}

class _BookNutritionAppointmentScreenState
    extends ConsumerState<BookNutritionAppointmentScreen> {
  String _consultationType = 'online';
  late DateTime _selectedDate;
  String? _selectedSlot;
  String _healthGoal = 'Weight Loss';
  final _notesCtrl = TextEditingController();

  static const _goals = [
    'Weight Loss',
    'Weight Gain',
    'Diabetes Diet',
    'Pregnancy Nutrition',
    'Sports Nutrition',
    'PCOS Diet',
    'Heart Healthy Diet',
    'General Wellness',
  ];

  static const _defaultSlots = [
    '09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM',
    '11:00 AM', '11:30 AM', '02:00 PM', '02:30 PM',
    '03:00 PM', '03:30 PM', '04:00 PM', '04:30 PM',
    '05:00 PM', '06:00 PM',
  ];

  // Derived getters ──────────────────────────────────────────────────────────
  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);
  String get _nutritionistId =>
      widget.extra['nutritionistId'] as String? ?? '';
  String get _nutritionistName =>
      widget.extra['nutritionistName'] as String? ?? '';
  String get _specialization =>
      widget.extra['nutritionistSpecialization'] as String? ?? '';
  double get _fee =>
      (widget.extra['fee'] as num?)?.toDouble() ?? 0.0;
  bool get _isOnline   => widget.extra['isOnline'] as bool? ?? true;
  bool get _isInPerson => widget.extra['isInPerson'] as bool? ?? false;

  List<String> get _availableSlots {
    final slots = widget.extra['slots'] as Map<String, dynamic>?;
    if (slots == null) return _defaultSlots;
    final dayName  = DateFormat('EEEE').format(_selectedDate);
    final daySlots = slots[dayName] as List?;
    return daySlots != null && daySlots.isNotEmpty
        ? List<String>.from(daySlots)
        : _defaultSlots;
  }

  // Calendar date range ──────────────────────────────────────────────────────
  late final List<DateTime> _dateRange;

  @override
  void initState() {
    super.initState();
    if (!_isOnline && _isInPerson) _consultationType = 'in_person';
    _selectedDate = DateTime.now().add(const Duration(days: 1));
    _dateRange = List.generate(
      30,
      (i) => DateTime.now().add(Duration(days: i + 1)),
    );
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // Booking logic ────────────────────────────────────────────────────────────
  Future<void> _confirmBooking() async {
    if (_selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a time slot'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // A ₹0 nutritionist consultation has no payment concept at all — book
    // directly, same as every other free-of-charge service in the app.
    if (_fee <= 0) {
      final success =
          await ref.read(nutritionBookingProvider.notifier).bookAppointment(
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
        _showSuccessDialog();
      } else {
        final error = ref.read(nutritionBookingProvider).error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error ?? 'Booking failed. Try again.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // ── Payment gate ──────────────────────────────────────
    // capturePayment (functions/index.js) — or, while kRequirePayment is
    // false, PaymentScreen's own no-payment path — creates the
    // nutrition_appointments doc itself. `userId` must be set explicitly
    // here (not just the auto-added `patientId`) because every other
    // nutrition query/rule keys off `userId`, not `patientId`.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final user = FirebaseAuth.instance.currentUser!;
    final result = await context.push<Map<String, dynamic>>(
      AppRoutes.payment,
      extra: {
        'amount': _fee.toInt().toString(),
        'description': 'Nutrition Consultation with $_nutritionistName',
        'serviceType': 'nutrition',
        'bookingCollection': 'nutrition_appointments',
        'bookingData': {
          'userId': uid,
          'userName': user.displayName ?? 'Patient',
          'userPhone': user.phoneNumber ?? '',
          'nutritionistId': _nutritionistId,
          'nutritionistName': _nutritionistName,
          'nutritionistSpecialization': _specialization,
          'consultationType': _consultationType,
          'date': _dateKey,
          'timeSlot': _selectedSlot,
          'status': 'pending',
          'notes': _notesCtrl.text.trim(),
          'fee': _fee,
          'healthGoal': _healthGoal,
        },
      },
    );
    if (!mounted) return;
    if (result?['bookingId'] != null) {
      _showSuccessDialog();
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: _kGreenBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded,
                    color: _kGreen, size: 42),
              ),
              const SizedBox(height: 18),
              const Text(
                'Appointment Booked!',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your consultation with $_nutritionistName is confirmed for '
                '${DateFormat('MMM d, yyyy').format(_selectedDate)} at $_selectedSlot.',
                style: AppTextStyles.bodyMedium.copyWith(
                    color: ctx.appTextSecondary, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.pop();
                    context.pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Done',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bookingState = ref.watch(nutritionBookingProvider);
    final bookedSlots =
        ref.watch(bookedSlotsProvider((_nutritionistId, _dateKey)));

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Book Consultation', style: AppTextStyles.h3),
        centerTitle: true,
        backgroundColor: context.appSurface,
        foregroundColor: context.appTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: context.appSurface,
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
            // ── Nutritionist summary header ───────────
            _NutritionistHeader(
              name: _nutritionistName,
              specialization: _specialization,
              fee: _fee,
            ),
            const SizedBox(height: 20),

            // ── Consultation type ─────────────────────
            if (_isOnline || _isInPerson) ...[
              const _SectionHeader(label: 'Consultation Type'),
              const SizedBox(height: 10),
              _ConsultationTypeSelector(
                isOnline: _isOnline,
                isInPerson: _isInPerson,
                selected: _consultationType,
                onSelect: (v) => setState(() => _consultationType = v),
              ),
              const SizedBox(height: 20),
            ],

            // ── Date picker (calendar-style strip) ────
            const _SectionHeader(label: 'Select Date'),
            const SizedBox(height: 10),
            _DateStrip(
              dates: _dateRange,
              selected: _selectedDate,
              onSelect: (d) =>
                  setState(() {
                    _selectedDate = d;
                    _selectedSlot = null;
                  }),
            ),
            const SizedBox(height: 20),

            // ── Time slots ────────────────────────────
            const _SectionHeader(label: 'Select Time Slot'),
            const SizedBox(height: 10),
            bookedSlots.when(
              loading: () => const AppShimmer(
                child: Column(
                  children: [
                    SkeletonBox(
                        width: double.infinity,
                        height: 48,
                        radius: 12),
                    SizedBox(height: 8),
                    SkeletonBox(
                        width: double.infinity,
                        height: 48,
                        radius: 12),
                  ],
                ),
              ),
              error: (_, __) => _SlotGrid(
                slots: _availableSlots,
                bookedSlots: const [],
                selected: _selectedSlot,
                onSelect: (s) => setState(() => _selectedSlot = s),
              ),
              data: (booked) => _SlotGrid(
                slots: _availableSlots,
                bookedSlots: booked,
                selected: _selectedSlot,
                onSelect: (s) => setState(() => _selectedSlot = s),
              ),
            ),
            const SizedBox(height: 20),

            // ── Health goal ───────────────────────────
            const _SectionHeader(label: 'Health Goal'),
            const SizedBox(height: 10),
            _GoalDropdown(
              value: _healthGoal,
              goals: _goals,
              onChanged: (v) =>
                  setState(() => _healthGoal = v ?? _healthGoal),
            ),
            const SizedBox(height: 20),

            // ── Notes ─────────────────────────────────
            const _SectionHeader(label: 'Additional Notes (Optional)'),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              style: AppTextStyles.bodyMedium,
              decoration: InputDecoration(
                hintText:
                    'Describe your health concerns, dietary restrictions...',
                hintStyle: AppTextStyles.bodySmall
                    .copyWith(color: context.appTextHint),
                filled: true,
                fillColor: context.appSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: context.appBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: context.appBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: _kGreen, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 20),

            // ── Booking summary card ──────────────────
            if (_selectedSlot != null)
              _SummaryCard(
                nutritionistName: _nutritionistName,
                date: _selectedDate,
                slot: _selectedSlot!,
                type: _consultationType,
                fee: _fee,
                goal: _healthGoal,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.labelLarge.copyWith(color: context.appTextPrimary),
    );
  }
}

// ── Nutritionist header card ──────────────────────────────────────────────────

class _NutritionistHeader extends StatelessWidget {
  final String name;
  final String specialization;
  final double fee;

  const _NutritionistHeader({
    required this.name,
    required this.specialization,
    required this.fee,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.person_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  specialization,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '₹${fee.toInt()} / session',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Consultation type selector ────────────────────────────────────────────────

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
          Expanded(
            child: _TypeCard(
              icon: Icons.videocam_rounded,
              label: 'Online',
              subtitle: 'Video / Chat',
              isSelected: selected == 'online',
              onTap: () => onSelect('online'),
            ),
          ),
        if (isOnline && isInPerson) const SizedBox(width: 12),
        if (isInPerson)
          Expanded(
            child: _TypeCard(
              icon: Icons.local_hospital_rounded,
              label: 'In-Person',
              subtitle: 'Visit Clinic',
              isSelected: selected == 'in_person',
              onTap: () => onSelect('in_person'),
            ),
          ),
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

  const _TypeCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? _kGreen : context.appSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _kGreen : context.appBorder,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _kGreen.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : context.appTextSecondary,
              size: 26,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : context.appTextPrimary,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color:
                    isSelected ? Colors.white70 : context.appTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Calendar date strip ───────────────────────────────────────────────────────

class _DateStrip extends StatefulWidget {
  final List<DateTime> dates;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  const _DateStrip({
    required this.dates,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<_DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<_DateStrip> {
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final idx = widget.dates
          .indexWhere((d) => _isSameDay(d, widget.selected));
      if (idx > 0 && _scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          idx * 72.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    // Month grouping label
    final currentMonth = DateFormat('MMMM yyyy').format(widget.selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Month label
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            currentMonth,
            style: AppTextStyles.labelMedium
                .copyWith(color: context.appTextSecondary),
          ),
        ),
        // Date scroll list
        SizedBox(
          height: 80,
          child: ListView.separated(
            controller: _scrollCtrl,
            scrollDirection: Axis.horizontal,
            itemCount: widget.dates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final date       = widget.dates[i];
              final isSelected = _isSameDay(date, widget.selected);
              final isToday    = _isSameDay(
                  date, DateTime.now().add(const Duration(days: 1)));

              return GestureDetector(
                onTap: () => widget.onSelect(date),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 60,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isSelected ? _kGradient : null,
                    color: isSelected ? null : context.appSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : isToday
                              ? _kGreen
                              : context.appBorder,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: _kGreen.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('EEE').format(date),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white70
                              : context.appTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('d').format(date),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : context.appTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('MMM').format(date),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 9,
                          color: isSelected
                              ? Colors.white60
                              : context.appTextHint,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Slot grid ─────────────────────────────────────────────────────────────────

class _SlotGrid extends StatelessWidget {
  final List<String> slots;
  final List<String> bookedSlots;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _SlotGrid({
    required this.slots,
    required this.bookedSlots,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: slots.map((slot) {
        final isBooked   = bookedSlots.contains(slot);
        final isSelected = selected == slot;

        return GestureDetector(
          onTap: isBooked ? null : () => onSelect(slot),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              gradient: isSelected ? _kGradient : null,
              color: isBooked
                  ? context.appBackground
                  : isSelected
                      ? null
                      : context.appSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isBooked
                    ? context.appBorder.withValues(alpha: 0.5)
                    : isSelected
                        ? Colors.transparent
                        : context.appBorder,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: _kGreen.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Text(
              slot,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isBooked
                    ? context.appTextHint
                    : isSelected
                        ? Colors.white
                        : context.appTextPrimary,
                decoration:
                    isBooked ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Goal dropdown ─────────────────────────────────────────────────────────────

class _GoalDropdown extends StatelessWidget {
  final String value;
  final List<String> goals;
  final ValueChanged<String?> onChanged;

  const _GoalDropdown({
    required this.value,
    required this.goals,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorder),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        style: AppTextStyles.bodyMedium
            .copyWith(color: context.appTextPrimary),
        icon:
            const Icon(Icons.keyboard_arrow_down_rounded, color: _kGreen),
        onChanged: onChanged,
        items: goals
            .map((g) => DropdownMenuItem(value: g, child: Text(g)))
            .toList(),
      ),
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String nutritionistName;
  final DateTime date;
  final String slot;
  final String type;
  final double fee;
  final String goal;

  const _SummaryCard({
    required this.nutritionistName,
    required this.date,
    required this.slot,
    required this.type,
    required this.fee,
    required this.goal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kGreenBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _kGreen.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_rounded,
                  color: _kGreen, size: 18),
              SizedBox(width: 8),
              Text('Booking Summary',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _kGreen,
                  )),
            ],
          ),
          const Divider(height: 20, color: Color(0xFFDCEDC8)),
          _SummaryRow(label: 'Nutritionist', value: nutritionistName),
          _SummaryRow(
            label: 'Date',
            value: DateFormat('EEE, MMM d, yyyy').format(date),
          ),
          _SummaryRow(label: 'Time', value: slot),
          _SummaryRow(
            label: 'Mode',
            value: type == 'online' ? 'Online Consultation' : 'In-Person Visit',
          ),
          _SummaryRow(label: 'Health Goal', value: goal),
          const Divider(height: 16, color: Color(0xFFDCEDC8)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Fee',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _kGreen,
                ),
              ),
              Text(
                '₹${fee.toInt()}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _kGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.appTextSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.appTextPrimary,
                      fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom bar ────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final double fee;
  final bool isLoading;
  final VoidCallback onBook;

  const _BottomBar(
      {required this.fee,
      required this.isLoading,
      required this.onBook});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
      decoration: BoxDecoration(
        color: context.appSurface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -3),
          )
        ],
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Fee',
                style: AppTextStyles.bodySmall
                    .copyWith(color: context.appTextHint),
              ),
              Text(
                '₹${fee.toInt()}',
                style: AppTextStyles.h3.copyWith(color: _kGreen),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: isLoading ? null : onBook,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                disabledBackgroundColor: _kGreen.withValues(alpha: 0.6),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Confirm Booking',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
