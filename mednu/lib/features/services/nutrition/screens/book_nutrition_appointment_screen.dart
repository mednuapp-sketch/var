import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/router/app_router.dart';
import '../models/weight_loss_plan.dart';
import '../providers/nutrition_provider.dart';
import '../services/nutrition_service.dart';
import '../utils/nutrition_slot_utils.dart';
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
  final int? _planMonths = selectedWeightLossMonths.value;
  final String? _planId = selectedWeightLossPlanId.value;
  final int? _planMonthly = selectedWeightLossMonthly.value;
  // Guards the payment hand-off against a double-tap opening two payment screens.
  bool _openingPayment = false;

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

  // Derived getters ──────────────────────────────────────────────────────────
  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);
  String get _nutritionistId =>
      widget.extra['nutritionistId'] as String? ?? '';
  String get _nutritionistName =>
      widget.extra['nutritionistName'] as String? ?? '';
  String get _specialization =>
      widget.extra['nutritionistSpecialization'] as String? ?? '';
  double get _consultFee =>
      (widget.extra['fee'] as num?)?.toDouble() ?? 0.0;
  // A prepaid weight-loss plan is charged as monthly price x months (the
  // dietician's own per-session fee is not charged); the server re-verifies it.
  double get _fee => (_planMonths != null && _planMonthly != null)
      ? (_planMonthly * _planMonths).toDouble()
      : _consultFee;
  bool get _isOnline   => widget.extra['isOnline'] as bool? ?? true;
  bool get _isInPerson => widget.extra['isInPerson'] as bool? ?? false;

  List<String> get _availableSlots => nutritionSlotsFor(
        slots: widget.extra['slots'] as Map<String, dynamic>?,
        scheduleConfigured: widget.extra['scheduleConfigured'] as bool? ?? false,
        blockedSlots: widget.extra['blockedSlots'] as Map<String, dynamic>?,
        date: _selectedDate,
      );

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

    // Re-check the slot against the server index right before booking/paying.
    if (await NutritionService.isSlotTaken(
        _nutritionistId, _dateKey, _selectedSlot!)) {
      if (!mounted) return;
      setState(() => _selectedSlot = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That slot was just booked. Please pick another time.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;

    if (_planMonths != null && _planMonthly == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The price of this plan is unavailable. Please go back and choose the plan again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // A ₹0 nutritionist consultation has no payment concept at all — book
    // directly, same as every other free-of-charge service in the app.
    // (A weight-loss plan is never free: it always goes through payment.)
    if (_fee <= 0 && _planMonths == null) {
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
                extraFields: _planMonths == null
                    ? const {}
                    : {
                        'planType': 'weight_loss',
                        'planMonths': _planMonths,
                        'planConsultations': _planMonths,
                      },
              );
      if (!mounted) return;
      if (success) {
        selectedWeightLossMonths.value = null;
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
    if (uid == null || _openingPayment) return;
    final user = FirebaseAuth.instance.currentUser!;
    _openingPayment = true;
    final Map<String, dynamic>? result;
    try {
      result = await context.push<Map<String, dynamic>>(
      AppRoutes.payment,
      extra: {
        'amount': _fee.toInt().toString(),
        'description': _planMonths != null
            ? 'Weight-loss plan ($_planMonths months) with $_nutritionistName'
            : 'Nutrition Consultation with $_nutritionistName',
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
          // Weight-loss programme chosen on the Diet Plans screen: one
          // consultation per month for `planMonths` months.
          if (_planMonths != null) ...{
            'planType': 'weight_loss',
            'planMonths': _planMonths,
            'planConsultations': _planMonths,
            // Hints only: the server reads the real price from diet_plans.
            'planContract': 2,
            if (_planId != null) 'planId': _planId,
            if (_planMonthly != null) 'planMonthlyPrice': _planMonthly,
          },
        },
      },
    );
    } finally {
      _openingPayment = false;
    }
    if (!mounted) return;
    if (result?['bookingId'] != null) {
      selectedWeightLossMonths.value = null;
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
                    context.safeBack();
                    context.safeBack();
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
          onPressed: () => context.safeBack(),
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
              fee: _planMonthly?.toDouble() ?? _consultFee,
              unit: _planMonths != null ? 'month' : 'session',
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
            NutritionDateStrip(
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
              error: (_, __) => NutritionSlotGrid(
                slots: _availableSlots,
                bookedSlots: const [],
                selected: _selectedSlot,
                onSelect: (s) => setState(() => _selectedSlot = s),
              ),
              data: (booked) => NutritionSlotGrid(
                slots: _availableSlots,
                bookedSlots: booked,
                selected: _selectedSlot,
                onSelect: (s) => setState(() => _selectedSlot = s),
              ),
            ),
            const SizedBox(height: 20),

            if (_planMonths != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kGreenBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_repeat_rounded, color: _kGreen, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Weight Loss Plan · $_planMonths months (1 consultation every month)',
                        style: AppTextStyles.bodySmall.copyWith(
                            color: _kGreen, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '$kWeightLossPlanNotice This first slot is your month 1 consultation; book the other months from My Weight-Loss Plan.',
                  style: AppTextStyles.caption
                      .copyWith(color: context.appTextSecondary, height: 1.4),
                ),
              ),
              const SizedBox(height: 20),
            ],
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
  final String unit;

  const _NutritionistHeader({
    required this.name,
    required this.specialization,
    required this.fee,
    this.unit = 'session',
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
                    '₹${fee.toInt()} / $unit',
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

class NutritionDateStrip extends StatefulWidget {
  final List<DateTime> dates;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  const NutritionDateStrip({
    super.key,
    required this.dates,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<NutritionDateStrip> createState() => _NutritionDateStripState();
}

class _NutritionDateStripState extends State<NutritionDateStrip> {
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
          height: 88,
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
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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

class NutritionSlotGrid extends StatelessWidget {
  final List<String> slots;
  final List<String> bookedSlots;
  final String? selected;
  final ValueChanged<String> onSelect;

  const NutritionSlotGrid({
    super.key,
    required this.slots,
    required this.bookedSlots,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.appBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.event_busy_rounded, color: context.appTextHint, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No time slots are available on this day. Please pick another date.',
                style: AppTextStyles.bodySmall
                    .copyWith(color: context.appTextSecondary, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }
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
          _SummaryRow(label: 'Dietician', value: nutritionistName),
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
