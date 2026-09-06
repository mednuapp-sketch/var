import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/payment_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';

const _kOpSlots = [
  '09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM', '11:00 AM', '11:30 AM',
  '12:00 PM', '12:30 PM', '01:00 PM', '01:30 PM', '02:00 PM', '02:30 PM',
  '03:00 PM', '03:30 PM', '04:00 PM', '04:30 PM',
];

const _kSymptomOptions = [
  'Fever', 'Cough', 'Sore throat', 'Shortness of breath', 'Chest pain',
  'Abdominal pain', 'Nausea or vomiting', 'Diarrhea', 'Headache', 'Dizziness',
  'Unusual fatigue', 'Joint or body pain', 'Unexplained weight loss', 'Skin rash',
];

const _kDurations = [
  'Today', '2-3 days ago', 'About a week ago', '2-4 weeks ago',
  '1-6 months ago', 'Over 6 months ago',
];
const _kSeverities = ['Mild', 'Moderate', 'Severe'];

/// Mirrors `_generateOpRxId` in payment_screen.dart / functions/index.js —
/// same 'MN-...-YYYYMMDD-XXXXXX' shaped token, just prefixed to tell a
/// hospital OP token apart from a doctor-appointment rxId at a glance.
String _generateOpToken() {
  final now = DateTime.now();
  final date = '${now.year}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rng = Random.secure();
  final suffix = List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  return 'MN-OP-$date-$suffix';
}

/// Books a generic in-person OP (out-patient) appointment directly with a
/// MedNU-registered hospital — as opposed to a specific doctor. Hospitals
/// aren't linked to per-doctor schedules today, so availability is a fixed
/// generic OP window (Mon-Sat, 9 AM-5 PM, 30-min slots) rather than derived
/// from any real doctor's calendar. Reuses the same booking-data contract
/// PaymentScreen already understands (bookingCollection/bookingData) so no
/// payment plumbing changes were needed — see doctor_profile_screen.dart for
/// the sibling flow this mirrors.
class HospitalAppointmentBookingScreen extends StatefulWidget {
  final String hospitalId;
  final String hospitalName;
  final String hospitalAddress;
  final String hospitalPhone;

  const HospitalAppointmentBookingScreen({
    super.key,
    required this.hospitalId,
    required this.hospitalName,
    this.hospitalAddress = '',
    this.hospitalPhone = '',
  });

  @override
  State<HospitalAppointmentBookingScreen> createState() =>
      _HospitalAppointmentBookingScreenState();
}

class _HospitalAppointmentBookingScreenState
    extends State<HospitalAppointmentBookingScreen> {
  late final List<DateTime> _dates;
  int _selectedDateIndex = 0;
  String? _selectedSlot;

  List<Map<String, dynamic>> _familyMembers = [];
  int _bookingForIndex = -1; // -1 = self

  final _reasonCtrl = TextEditingController();
  final _otherSymptomsCtrl = TextEditingController();
  final Set<String> _selectedSymptoms = {};
  String? _duration;
  String? _severity;

  bool _booking = false;
  Timer? _slotTimer;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final dates = <DateTime>[];
    var d = today;
    while (dates.length < 10) {
      if (d.weekday != DateTime.sunday) dates.add(d);
      d = d.add(const Duration(days: 1));
    }
    _dates = dates;
    _loadFamilyMembers();
    _slotTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _slotTimer?.cancel();
    _reasonCtrl.dispose();
    _otherSymptomsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFamilyMembers() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final raw = snap.data()?['familyMembers'];
      if (!mounted || raw is! List) return;
      setState(() {
        _familyMembers = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } catch (_) {}
  }

  bool _isSlotExpired(String slot) {
    final date = _dates[_selectedDateIndex];
    final today = DateTime.now();
    if (date.year != today.year || date.month != today.month || date.day != today.day) {
      return false;
    }
    final parts = slot.split(' ');
    final hm = parts[0].split(':');
    int h = int.parse(hm[0]);
    final m = int.parse(hm[1]);
    if (parts[1] == 'PM' && h != 12) h += 12;
    if (parts[1] == 'AM' && h == 12) h = 0;
    final slotTime = DateTime(date.year, date.month, date.day, h, m);
    return slotTime.isBefore(today);
  }

  Future<void> _bookAppointment() async {
    if (_selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a time slot')),
      );
      return;
    }
    if (_isSlotExpired(_selectedSlot!)) {
      setState(() => _selectedSlot = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This slot has just expired. Please choose another time.'),
        backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _booking = true);

    final patient = FirebaseAuth.instance.currentUser;
    final uid = patient?.uid;
    if (uid == null) {
      setState(() => _booking = false);
      return;
    }

    final db = FirebaseFirestore.instance;
    String patientName;
    try {
      final userSnap = await db.collection('users').doc(uid).get();
      final fsName = (userSnap.data()?['name'] as String?)?.trim() ?? '';
      patientName = fsName.isNotEmpty
          ? fsName
          : patient?.displayName ?? patient?.phoneNumber ?? 'Patient';
    } catch (_) {
      patientName = patient?.displayName ?? patient?.phoneNumber ?? 'Patient';
    }
    final bookedByName = patientName;

    final bookingForMember = _bookingForIndex >= 0 && _bookingForIndex < _familyMembers.length
        ? _familyMembers[_bookingForIndex]
        : null;
    if (bookingForMember != null) {
      final memberName = (bookingForMember['name'] as String? ?? '').trim();
      if (memberName.isNotEmpty) patientName = memberName;
    }

    final dateKey = DateFormat('yyyy-MM-dd').format(_dates[_selectedDateIndex]);
    final slot = _selectedSlot!;
    final opToken = _generateOpToken();

    if (!mounted) return;
    final result = await context.push<Map<String, dynamic>>(
      AppRoutes.payment,
      extra: {
        'amount': kHospitalOpFee.toString(),
        'description':
            'OP Appointment · ${widget.hospitalName} · $slot (${DateFormat('d MMM').format(_dates[_selectedDateIndex])})',
        'serviceType': 'hospital_op',
        'bookingCollection': 'hospital_appointments',
        'bookingData': {
          'type': 'hospital_op',
          'hospitalId': widget.hospitalId,
          'hospitalName': widget.hospitalName,
          'hospitalAddress': widget.hospitalAddress,
          'hospitalPhone': widget.hospitalPhone,
          'patientName': patientName,
          'bookedByName': bookedByName,
          'date': dateKey,
          'time': slot,
          'consultationType': 'In-Person',
          'reasonForVisit': _reasonCtrl.text.trim(),
          'symptoms': _selectedSymptoms.toList(),
          'otherSymptoms': _otherSymptomsCtrl.text.trim(),
          'symptomDuration': _duration ?? '',
          'symptomSeverity': _severity ?? '',
          'fee': kHospitalOpFee,
          'status': 'booked',
          'opToken': opToken,
        },
      },
    );

    if (!mounted) return;
    setState(() => _booking = false);
    if (result?['bookingId'] == null) return;

    final bookedSlot = slot;
    final bookedDate = _dates[_selectedDateIndex];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'OP appointment confirmed for ${DateFormat('d MMM').format(bookedDate)} at $bookedSlot',
      ),
      backgroundColor: const Color(0xFF2E7D32),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
    _showBookingConfirmation(bookedSlot, bookedDate, opToken);
  }

  void _showBookingConfirmation(String slot, DateTime date, String opToken) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: const Color(0xFF4CAF50).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            Text('OP Appointment Booked!',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: context.appTextPrimary)),
            const SizedBox(height: 6),
            Text('Show this OP token at the hospital reception',
                style: AppTextStyles.bodyMedium.copyWith(color: context.appTextSecondary)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.appBackground,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                _ConfirmRow(Icons.local_hospital_rounded, widget.hospitalName, AppColors.primary),
                const SizedBox(height: 10),
                _ConfirmRow(Icons.calendar_today_rounded,
                    DateFormat('EEE, d MMM yyyy').format(date), const Color(0xFF1565C0)),
                const SizedBox(height: 10),
                _ConfirmRow(Icons.schedule_rounded, slot, const Color(0xFF2E7D32)),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: opToken));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('OP token copied')),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.confirmation_number_rounded, size: 16, color: AppColors.accentText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(opToken,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentText)),
                      ),
                      const Icon(Icons.copy_rounded, size: 15, color: AppColors.accentText),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 5))],
                ),
                child: ElevatedButton(
                  onPressed: () { Navigator.pop(ctx); if (context.mounted) context.go(AppRoutes.appointment); },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('View My Appointments', style: AppTextStyles.button),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Done', style: TextStyle(fontFamily: 'Poppins', color: context.appTextSecondary)),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: context.appBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: R.w(context, 20)),
          onPressed: () => context.pop(),
        ),
        title: Text('Book OP Appointment', style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 8), R.p(context, 16), R.p(context, 16)),
              children: [
                _buildHospitalCard(),
                SizedBox(height: R.h(context, 22)),
                const _SectionTitle('Select Date', Icons.event_rounded, AppColors.primary),
                SizedBox(height: R.h(context, 12)),
                _buildDateStrip(),
                SizedBox(height: R.h(context, 22)),
                const _SectionTitle('Select Time', Icons.schedule_rounded, Color(0xFF1565C0)),
                SizedBox(height: R.h(context, 12)),
                _buildSlotGrid(),
                SizedBox(height: R.h(context, 22)),
                const _SectionTitle('Who is this for?', Icons.family_restroom_rounded, Color(0xFF6A1B9A)),
                SizedBox(height: R.h(context, 12)),
                _buildWhoForSection(),
                SizedBox(height: R.h(context, 22)),
                const _SectionTitle('What\'s this visit for?', Icons.assignment_outlined, Color(0xFF2E7D32)),
                SizedBox(height: R.h(context, 12)),
                _buildSymptomSection(),
              ],
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHospitalCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_hospital_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.hospitalName,
                    style: AppTextStyles.h4.copyWith(color: context.appTextPrimary),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                if (widget.hospitalAddress.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(widget.hospitalAddress,
                      style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateStrip() {
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final date = _dates[i];
          final selected = i == _selectedDateIndex;
          return GestureDetector(
            onTap: () => setState(() { _selectedDateIndex = i; _selectedSlot = null; }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 54,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : context.appSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? AppColors.primary : context.appBorder),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('EEE').format(date).toUpperCase(),
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600,
                          color: selected ? Colors.white70 : context.appTextSecondary)),
                  const SizedBox(height: 3),
                  Text('${date.day}',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : context.appTextPrimary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlotGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kOpSlots.map((slot) {
        final expired = _isSlotExpired(slot);
        final selected = _selectedSlot == slot;
        return GestureDetector(
          onTap: expired ? null : () => setState(() => _selectedSlot = slot),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: expired
                  ? context.appBorder.withValues(alpha: 0.3)
                  : selected ? AppColors.primary : context.appSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: expired ? context.appBorder : (selected ? AppColors.primary : context.appBorder),
              ),
            ),
            child: Text(slot,
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: expired
                      ? context.appTextHint
                      : selected ? Colors.white : context.appTextPrimary,
                  decoration: expired ? TextDecoration.lineThrough : null,
                )),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWhoForSection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ChoiceChip(label: 'Self', selected: _bookingForIndex < 0, onTap: () => setState(() => _bookingForIndex = -1)),
        for (int i = 0; i < _familyMembers.length; i++)
          _ChoiceChip(
            label: _familyMembers[i]['name'] as String? ?? 'Member',
            selected: _bookingForIndex == i,
            onTap: () => setState(() => _bookingForIndex = i),
          ),
      ],
    );
  }

  Widget _buildSymptomSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _reasonCtrl,
          maxLines: 2,
          decoration: _inputDecoration(hint: 'Briefly describe the reason for this visit'),
        ),
        SizedBox(height: R.h(context, 14)),
        Text('Current symptoms', style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
        SizedBox(height: R.h(context, 8)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kSymptomOptions.map((s) {
            final selected = _selectedSymptoms.contains(s);
            return _ChoiceChip(
              label: s,
              selected: selected,
              onTap: () => setState(() {
                if (selected) {
                  _selectedSymptoms.remove(s);
                } else {
                  _selectedSymptoms.add(s);
                }
              }),
            );
          }).toList(),
        ),
        SizedBox(height: R.h(context, 14)),
        TextField(
          controller: _otherSymptomsCtrl,
          maxLines: 2,
          decoration: _inputDecoration(hint: 'Other symptoms not listed above'),
        ),
        SizedBox(height: R.h(context, 14)),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _duration,
              isExpanded: true,
              decoration: _inputDecoration(hint: 'Symptoms started'),
              items: _kDurations.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5)))).toList(),
              onChanged: (v) => setState(() => _duration = v),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _severity,
              isExpanded: true,
              decoration: _inputDecoration(hint: 'Severity'),
              items: _kSeverities.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)))).toList(),
              onChanged: (v) => setState(() => _severity = v),
            ),
          ),
        ]),
      ],
    );
  }

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
        filled: true,
        fillColor: context.appSurface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.appBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.appBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      );

  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 14), R.p(context, 16), R.p(context, 20)),
      decoration: BoxDecoration(
        color: context.appSurface,
        border: Border(top: BorderSide(color: context.appBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('OP registration fee', style: AppTextStyles.bodySmall.copyWith(color: context.appTextSecondary)),
                  Text('₹$kHospitalOpFee', style: AppTextStyles.h3.copyWith(color: AppColors.primary)),
                ],
              ),
            ),
            SizedBox(
              width: 190,
              height: R.h(context, 48),
              child: ElevatedButton(
                onPressed: (_booking || _selectedSlot == null) ? null : _bookAppointment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.r(context, 12))),
                ),
                child: _booking
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Book & Pay ₹$kHospitalOpFee', style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionTitle(this.title, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 15, color: color),
      ),
      const SizedBox(width: 8),
      Text(title, style: AppTextStyles.h4.copyWith(color: context.appTextPrimary)),
    ]);
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.1) : context.appSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : context.appBorder, width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : context.appTextSecondary,
            )),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ConfirmRow(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 10),
      Expanded(
        child: Text(label,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: context.appTextPrimary),
            maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}
