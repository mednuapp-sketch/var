import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../intake/services/doctor_booking_flow.dart';
import '../data/doctors_data.dart';

const _kDefaultSlots = [
  '09:00 AM', '10:00 AM', '11:00 AM', '12:00 PM',
  '02:00 PM', '03:00 PM', '04:00 PM', '05:00 PM', '06:00 PM',
];

// ── Consultation type metadata ────────────────────────────
const _kConsultMeta = {
  'Video':     {'icon': Icons.videocam_rounded,         'color': Color(0xFF1565C0), 'label': 'Video Call',     'desc': 'Secure HD video'},
  'Audio':     {'icon': Icons.phone_in_talk_rounded,    'color': Color(0xFF2E7D32), 'label': 'Audio Call',     'desc': 'Voice consultation'},
  'Chat':      {'icon': Icons.chat_bubble_rounded,      'color': Color(0xFF6A1B9A), 'label': 'Chat',           'desc': 'Text & media'},
  'In-Person': {'icon': Icons.local_hospital_rounded,   'color': Color(0xFFB71C1C), 'label': 'In-Person',      'desc': 'Visit clinic'},
};

// Session durations patients can pick when booking, in minutes.
// Fees scale linearly off the doctor's listed fee, which is the 30-min rate.
const _kSessionDurations = [15, 30, 45, 60];

int _feeForDuration(int baseFee, int minutes) =>
    baseFee <= 0 ? 0 : ((baseFee * minutes) / 30).round();

class DoctorProfileScreen extends StatefulWidget {
  final String doctorId;
  final int? initialDuration;
  // 'video' | 'inperson' — carried from the Find Doctors tab the patient
  // booked from, so the consultation type here matches what they chose.
  final String? initialMode;
  // When set, this screen is rescheduling an existing appointment rather than
  // creating a new one: booking is locked to this doctor, no payment is
  // collected, and confirming just moves the existing appointment's slot.
  final String? rescheduleAppointmentId;
  final String? rescheduleType;
  const DoctorProfileScreen({
    super.key,
    required this.doctorId,
    this.initialDuration,
    this.initialMode,
    this.rescheduleAppointmentId,
    this.rescheduleType,
  });
  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  late final List<DateTime> _dates;
  int _selectedDateIndex = 0;
  String? _selectedSlot;
  String _consultationType = 'Video';
  late int _selectedDuration;
  bool _booking = false;
  // Quick Connect (from the doctor-list card) used to be indistinguishable
  // from Book Now — same screen, same blank slot picker — because the
  // 'quickConnect' mode was passed via `extra`, which this route never reads
  // (see doctors_list_screen.dart). Now that the mode actually arrives, this
  // pre-picks the soonest open slot so the patient just confirms instead of
  // choosing a time — a real difference, not a fake label, and it reuses the
  // exact same booking/payment path Book Now uses (no shortcut around
  // payment or doctor acceptance).
  bool _quickConnectAutoPicked = false;

  DocData? _doc;
  bool _loadingDoc = true;

  bool _isFavourite = false;
  bool _loadingFav = true;

  Map<String, dynamic>? _availability;
  String? _hospital;
  String? _hospitalAddress;
  List<String> _languages = [];
  List<String> _supportedModes = ['Video', 'In-Person'];

  // ── Who is this for? ── -1 = self. Picking a family member lets the
  // patient optionally attach that member's phone so a "Share join link"
  // button (on the appointment screen, once booked) can let them join the
  // actual call themselves — same pattern as the Consultation booking flow.
  List<Map<String, dynamic>> _familyMembers = [];
  int _bookingForIndex = -1;
  final _guestPhoneCtrl = TextEditingController();

  static String? _nonEmpty(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  StreamSubscription<DocumentSnapshot>? _docSub;
  StreamSubscription<DocumentSnapshot>? _favSub;
  Timer? _slotTimer;

  bool get _isRescheduling => widget.rescheduleAppointmentId != null;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _dates = List.generate(10, (i) => today.add(Duration(days: i)));
    _selectedDuration = _kSessionDurations.contains(widget.initialDuration)
        ? widget.initialDuration!
        : 30;
    if (_isRescheduling && _kConsultMeta.containsKey(widget.rescheduleType)) {
      _consultationType = widget.rescheduleType!;
    } else if (widget.initialMode == 'inperson') {
      _consultationType = 'In-Person';
    } else if (widget.initialMode == 'quickConnect') {
      _consultationType = 'Video';
    }
    _subscribeDoctor();
    _subscribeFavouriteState();
    _loadFamilyMembers();
    _slotTimer = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
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

  void _selectBookingFor(int index) {
    setState(() {
      _bookingForIndex = index;
      if (index >= 0) {
        final phone = _familyMembers[index]['phone'] as String? ?? '';
        _guestPhoneCtrl.text = phone;
      } else {
        _guestPhoneCtrl.clear();
      }
    });
  }

  // ── Realtime doctor subscription ──────────────────────
  void _subscribeDoctor() {
    _docSub = FirebaseFirestore.instance
        .collection('doctors')
        .doc(widget.doctorId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      if (!snap.exists) {
        setState(() => _loadingDoc = false);
        return;
      }
      final d = snap.data()!;
      final feeRaw = d['fee'];
      final fee = feeRaw is int ? feeRaw : int.tryParse(feeRaw?.toString() ?? '0') ?? 0;
      final expRaw = d['experience'];
      final exp = expRaw is int ? expRaw : int.tryParse(expRaw?.toString() ?? '0') ?? 0;

      final modes = d['consultationModes'] as List<dynamic>?;

      setState(() {
        _doc = DocData(
          id: widget.doctorId,
          name: d['name'] as String? ?? 'Doctor',
          spec: d['specialty'] as String? ?? '',
          qual: d['qualifications'] as String? ?? 'MBBS',
          rating: (d['rating'] as num?)?.toDouble() ?? 0.0,
          reviews: (d['totalReviews'] as num?)?.toInt() ??
              (d['totalConsultations'] as num?)?.toInt() ?? 0,
          exp: exp,
          online: d['isOnline'] as bool? ?? false,
          fee: fee,
          img: d['photoUrl'] as String? ?? '',
          about: d['about'] as String? ?? 'Experienced doctor available for consultation.',
          specialities: (d['specialities'] as List<dynamic>?)?.cast<String>() ??
              [d['specialty'] as String? ?? ''],
        );
        _availability = d['availability'] as Map<String, dynamic>?;
        _hospital = _nonEmpty(d['hospital'] as String?) ?? _nonEmpty(d['clinicName'] as String?) ?? _nonEmpty(d['hospitalAffiliation'] as String?);
        _hospitalAddress = _nonEmpty(d['hospitalAddress'] as String?) ?? _nonEmpty(d['clinicAddress'] as String?);
        _languages = (d['languages'] as List<dynamic>?)?.cast<String>() ?? [];
        if (modes != null && modes.isNotEmpty) {
          final allowed = modes.cast<String>().where((m) => m == 'Video' || m == 'In-Person').toList();
          if (allowed.isNotEmpty) _supportedModes = allowed;
        }
        _loadingDoc = false;
      });
      _maybeAutoPickQuickConnectSlot();
    }, onError: (_) {
      if (mounted) setState(() => _loadingDoc = false);
    });
  }

  void _maybeAutoPickQuickConnectSlot() {
    if (_quickConnectAutoPicked || widget.initialMode != 'quickConnect') return;
    if (_isRescheduling || _selectedSlot != null) return;
    for (var i = 0; i < _dates.length; i++) {
      final date = _dates[i];
      if (!_isDoctorWorkingDay(date)) continue;
      final slots = _slotsForDate(date)
          .where((s) => !_isSlotExpiredForDate(date, s))
          .toList();
      if (slots.isEmpty) continue;
      setState(() {
        _selectedDateIndex = i;
        _selectedSlot = slots.first;
        _quickConnectAutoPicked = true;
      });
      return;
    }
    // No open slot in the visible window — leave it to manual selection.
    _quickConnectAutoPicked = true;
  }

  // ── Realtime favourite-state subscription ─────────────
  void _subscribeFavouriteState() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loadingFav = false); return; }
    _favSub = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('favourite_doctors').doc(widget.doctorId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      setState(() { _isFavourite = doc.exists; _loadingFav = false; });
    }, onError: (_) {
      if (mounted) setState(() => _loadingFav = false);
    });
  }

  Future<void> _toggleFavourite() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('favourite_doctors').doc(widget.doctorId);
    if (_isFavourite) {
      await ref.delete();
      if (mounted) {
        setState(() => _isFavourite = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Removed from favourites'), behavior: SnackBarBehavior.floating,
        ));
      }
    } else {
      await ref.set({
        'doctorId': widget.doctorId,
        'doctorName': _doc?.name ?? '',
        'specialty': _doc?.spec ?? '',
        'photoUrl': _doc?.img ?? '',
        'fee': _doc?.fee ?? 0,
        'rating': _doc?.rating ?? 0.0,
        'savedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() => _isFavourite = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Added to favourites'),
          backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _shareDoctor() async {
    final doc = _doc;
    if (doc == null) return;
    final text = '👨‍⚕️ ${doc.name}\n'
        '${doc.spec} • ${doc.qual}\n'
        '${doc.exp}+ years experience\n'
        '💊 Consultation fee: ₹${doc.fee}\n\n'
        'Book an appointment on MedNU — your trusted healthcare partner.\n'
        'Download: https://play.google.com/store/apps/details?id=com.mednu.app';
    await Share.share(text, subject: 'Doctor Profile – ${doc.name}');
  }

  String get _selectedDateKey =>
      DateFormat('yyyy-MM-dd').format(_dates[_selectedDateIndex]);

  Stream<Set<String>> _bookedSlotsStream() =>
      FirebaseFirestore.instance
          .collection('appointments')
          .where('doctorId', isEqualTo: widget.doctorId)
          .where('date', isEqualTo: _selectedDateKey)
          .where('status', isEqualTo: 'booked')
          .snapshots()
          .map((s) => s.docs.map((d) => d['time'] as String? ?? '').toSet());

  bool _isDoctorWorkingDay(DateTime date) {
    final avail = _availability;
    if (avail == null) return true;
    final schedule = avail['schedule'] as Map<String, dynamic>?;
    if (schedule == null) return true;
    final dayName = DateFormat('EEE').format(date);
    final ds = schedule[dayName] as Map<String, dynamic>?;
    return ds?['enabled'] == true;
  }

  List<String> _slotsForSelectedDate() => _slotsForDate(_dates[_selectedDateIndex]);

  List<String> _slotsForDate(DateTime date) {
    final avail = _availability;
    if (avail == null) return _kDefaultSlots.toList();
    final slotDuration = (avail['slotDuration'] as num?)?.toInt() ?? 30;
    final schedule = avail['schedule'] as Map<String, dynamic>?;
    if (schedule == null) return _kDefaultSlots.toList();
    final dayName = DateFormat('EEE').format(date);
    final ds = schedule[dayName] as Map<String, dynamic>?;
    if (ds == null || ds['enabled'] != true) return [];
    final startStr = ds['start'] as String? ?? '09:00';
    final endStr = ds['end'] as String? ?? '17:00';
    try {
      final sp = startStr.split(':');
      final ep = endStr.split(':');
      final startMins = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final endMins = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      final slots = <String>[];
      for (int m = startMins; m + slotDuration <= endMins; m += slotDuration) {
        final h = m ~/ 60;
        final min = m % 60;
        final period = h < 12 ? 'AM' : 'PM';
        final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
        slots.add('${displayH.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')} $period');
      }
      final blocked = _blockedSlotsForDate(date);
      return blocked.isEmpty ? slots : slots.where((s) => !blocked.contains(s)).toList();
    } catch (_) {
      return _kDefaultSlots.toList();
    }
  }

  // Slots the doctor has manually blocked for this date (e.g. a sudden
  // meeting), separate from the recurring weekly schedule — see the doctor
  // app's Block a Slot screen, which writes availability.blockedSlots.
  Set<String> _blockedSlotsForDate(DateTime date) {
    final avail = _availability;
    if (avail == null) return const {};
    final blockedByDate = avail['blockedSlots'] as Map<String, dynamic>?;
    if (blockedByDate == null) return const {};
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final list = blockedByDate[dateKey] as List?;
    return list?.cast<String>().toSet() ?? const {};
  }

  bool _isSlotExpired(String slot) =>
      _isSlotExpiredForDate(_dates[_selectedDateIndex], slot);

  bool _isSlotExpiredForDate(DateTime selectedDay, String slot) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selDate = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    if (selDate.isAfter(today)) return false;
    if (selDate.isBefore(today)) return true;
    try {
      final parts = slot.trim().split(' ');
      final hm = parts[0].split(':');
      int h = int.parse(hm[0]);
      final min = int.parse(hm[1]);
      if (parts.length > 1 && parts[1].toUpperCase() == 'PM' && h != 12) h += 12;
      if (parts.length > 1 && parts[1].toUpperCase() == 'AM' && h == 12) h = 0;
      return DateTime(now.year, now.month, now.day, h, min).isBefore(now);
    } catch (_) { return false; }
  }

  Future<void> _bookSlot(DocData doc) async {
    if (_selectedSlot == null) return;
    if (_isSlotExpired(_selectedSlot!)) {
      setState(() => _selectedSlot = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This slot has just expired. Please choose another time.'),
          backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    // Re-check against the doctor's blocked slots in case they blocked this
    // exact time after the list was first rendered.
    if (_blockedSlotsForDate(_dates[_selectedDateIndex]).contains(_selectedSlot)) {
      setState(() => _selectedSlot = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This slot is no longer available. Please choose another time.'),
          backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    setState(() => _booking = true);

    final patient = FirebaseAuth.instance.currentUser;
    final uid = patient?.uid;
    if (uid == null) {
      setState(() => _booking = false);
      return;
    }

    final dateKey = _selectedDateKey;
    final slot    = _selectedSlot!;
    final duration = _selectedDuration;
    final amount  = _feeForDuration(doc.fee, duration);
    final db      = FirebaseFirestore.instance;

    // ── Resolve patient name ─────────────────────────────────────────────────
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

    // Always the account holder's own name, kept distinct from patientName
    // below (which may get overridden to a family member's name) — the call
    // screens use this to label the booking account holder's own video tile.
    final bookedByName = patientName;

    // Booking for a family member: show the doctor who they're actually
    // treating, and carry the guest phone number so a join link can be
    // generated later (only if one was entered — unchanged for "Self").
    final bookingForMember = _bookingForIndex >= 0 && _bookingForIndex < _familyMembers.length
        ? _familyMembers[_bookingForIndex]
        : null;
    if (bookingForMember != null) {
      final memberName = (bookingForMember['name'] as String? ?? '').trim();
      if (memberName.isNotEmpty) patientName = memberName;
    }
    final guestPhone = _guestPhoneCtrl.text.trim();

    // ── Pre-flight: confirm the slot is still free ───────────────────────────
    try {
      final existing = await db.collection('appointments')
          .where('doctorId', isEqualTo: widget.doctorId)
          .where('date', isEqualTo: dateKey)
          .where('time', isEqualTo: slot)
          .where('status', isEqualTo: 'booked')
          .limit(2)
          .get();
      final clash = existing.docs
          .where((d) => d.id != widget.rescheduleAppointmentId)
          .isNotEmpty;
      if (clash) throw Exception('slot_taken');
    } catch (e) {
      if (!mounted) return;
      setState(() => _booking = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().contains('slot_taken')
            ? 'This slot was just taken. Please choose another time.'
            : 'Could not verify slot. Please try again.'),
        backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _booking = false);

    // ── Reschedule mode: move the existing appointment, no payment ───────────
    // The patient already paid for this appointment, so rescheduling only
    // updates its date/time/type — it never opens PaymentScreen or creates a
    // new appointment/payment record.
    if (_isRescheduling) {
      setState(() => _booking = true);
      try {
        await db.collection('appointments').doc(widget.rescheduleAppointmentId).update({
          'date':             dateKey,
          'time':             slot,
          'consultationType': _consultationType,
          'status':           'booked',
          'updatedAt':        Timestamp.now(),
        });
        if (mounted) {
          final bookedSlot = slot;
          final bookedDate = _dates[_selectedDateIndex];
          setState(() { _selectedSlot = null; _booking = false; });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              'Appointment rescheduled to ${DateFormat('d MMM').format(bookedDate)} at $bookedSlot',
            ),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ));
          _showBookingConfirmation(doc, bookedSlot, bookedDate);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _booking = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not reschedule. Please try again.'),
            backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating,
          ));
        }
      }
      return;
    }

    // ── Pre-consultation form — before payment, not after ───────────────────
    // Mandatory (see PreConsultationFormScreen's PopScope) — a null result
    // means the patient cancelled the booking outright, not "skip and book
    // anyway". No appointment exists yet at this point, so the answers are
    // just held in memory and attached once payment succeeds and a real
    // appointmentId exists (see submitIntake below) — see DoctorBookingFlow's
    // class doc for why.
    if (!mounted) return;
    final formData = await DoctorBookingFlow.collectIntake(
      context,
      doctorId: widget.doctorId,
      doctorName: doc.name,
      doctorSpecialty: doc.spec,
    );
    if (formData == null || !mounted) {
      setState(() => _booking = false);
      return;
    }

    // ── Open PaymentScreen — the slot is free, now collect payment ───────────
    // PaymentScreen pops with the newly-created appointment/payment ids only
    // after capturePayment verifies the charge server-side (HMAC-SHA256) and
    // creates the appointment doc itself — see functions/index.js. Nothing
    // here writes to Firestore directly, so a booking can never exist without
    // a real, server-verified payment behind it.
    final result = await context.push<Map<String, dynamic>>(
      AppRoutes.payment,
      extra: {
        'amount':      amount.toString(),
        'description': 'Appointment with Dr. ${doc.name} · $slot ($duration min) · ${DateFormat('d MMM').format(_dates[_selectedDateIndex])}',
        'serviceType': _consultationType == 'Video' ? 'video_consultation' : 'consultation',
        'bookingCollection': 'appointments',
        'bookingData': {
          'doctorId':         widget.doctorId,
          'doctorName':       doc.name,
          'doctorSpecialty':  doc.spec,
          'patientName':      patientName,
          'bookedByName':     bookedByName,
          'date':             dateKey,
          'time':             slot,
          'consultationType': _consultationType,
          'duration':         duration,
          'fee':              amount,
          'status':           'booked',
          // Lets records_screen.dart's per-family-member Records tab filter
          // (`.where('memberId', isEqualTo: ...)`) actually find prescriptions/
          // reports born from this consultation — see write_prescription_screen.dart,
          // which copies this straight from the appointment doc.
          if (bookingForMember != null) 'memberId': bookingForMember['id'] as String? ?? '',
          if (bookingForMember != null && guestPhone.isNotEmpty) 'guestPhone': guestPhone,
        },
      },
    );

    if (!mounted) return;
    final bookedSlot = slot;
    final bookedDate = _dates[_selectedDateIndex];
    final bookingId = result?['bookingId'] as String?;

    if (bookingId == null) {
      setState(() => _booking = false);
      await DoctorBookingFlow.showSummary(
        context,
        success: false,
        doctorName: doc.name,
        doctorSpecialty: doc.spec,
        failureReason: 'Your payment wasn\'t completed, so this slot was not booked. You can try again anytime.',
      );
      return;
    }

    await DoctorBookingFlow.submitIntake(
      appointmentId: bookingId,
      doctorId: widget.doctorId,
      doctorName: doc.name,
      data: formData,
    );
    if (!mounted) return;

    setState(() { _selectedSlot = null; _booking = false; });
    await DoctorBookingFlow.showSummary(
      context,
      success: true,
      doctorName: doc.name,
      doctorSpecialty: doc.spec,
      date: DateFormat('EEE, d MMM yyyy').format(bookedDate),
      time: bookedSlot,
      consultationType: '$_consultationType · $duration min',
      fee: amount.toString(),
      formData: formData,
    );
  }

  void _showBookingConfirmation(DocData doc, String slot, DateTime date) {
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
                boxShadow: [BoxShadow(color: const Color(0xFF4CAF50).withValues(alpha:0.3), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            Text(_isRescheduling ? 'Appointment Rescheduled!' : 'Appointment Booked!',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: context.appTextPrimary)),
            const SizedBox(height: 6),
            Text(_isRescheduling ? 'Your new slot is confirmed' : 'Your slot is confirmed', style: AppTextStyles.bodyMedium.copyWith(color: context.appTextSecondary)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.appBackground,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                _ConfirmRow(Icons.person_rounded, doc.name, AppColors.primary),
                const SizedBox(height: 10),
                _ConfirmRow(Icons.calendar_today_rounded,
                    DateFormat('EEE, d MMM yyyy').format(date), const Color(0xFF1565C0)),
                const SizedBox(height: 10),
                _ConfirmRow(Icons.schedule_rounded, slot, const Color(0xFF2E7D32)),
                const SizedBox(height: 10),
                _ConfirmRow(Icons.videocam_rounded, _consultationType, const Color(0xFF6A1B9A)),
                if (!_isRescheduling) ...[
                  const SizedBox(height: 10),
                  _ConfirmRow(Icons.timer_outlined,
                      '$_selectedDuration min · ₹${_feeForDuration(doc.fee, _selectedDuration)}',
                      const Color(0xFFF9943B)),
                ],
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
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha:0.3), blurRadius: 12, offset: const Offset(0, 5))],
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
  void dispose() {
    _docSub?.cancel();
    _favSub?.cancel();
    _slotTimer?.cancel();
    _guestPhoneCtrl.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loadingDoc) return _buildSkeleton(context);
    if (_doc == null) return _buildNotFound(context);
    final doc = _doc!;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: CustomScrollView(
        slivers: [
          _buildHeroHeader(doc),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Quick Trust Stats ───────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _TrustStatsRow(doc: doc),
                ),
                const SizedBox(height: 24),

                // ── Consultation Type Cards ──────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildConsultationTypes(),
                ),
                const SizedBox(height: 24),

                // ── Session Duration ─────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildDurationSelector(doc),
                ),
                const SizedBox(height: 24),

                // ── About Section ────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _AboutSection(about: doc.about),
                ),
                const SizedBox(height: 24),

                // ── Languages ────────────────────────────
                if (_languages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: _buildLanguages(),
                  ),

                // ── Divider before booking section ────────
                Container(
                  height: 8,
                  color: const Color(0xFFF9FAFB),
                ),
                const SizedBox(height: 24),

                // ── Date Picker ───────────────────────────
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: R.p(context, 20)),
                  child: _buildDatePicker(),
                ),
                SizedBox(height: R.h(context, 24)),

                // ── Time Slots ────────────────────────────
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: R.p(context, 20)),
                  child: _buildSlotsSection(),
                ),
                SizedBox(height: R.h(context, 24)),

                // ── Who is this for? ─────────────────────
                if (_familyMembers.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: R.p(context, 20)),
                    child: _buildBookingForSection(),
                  ),
                SizedBox(height: R.h(context, 120)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(doc),
    );
  }

  // ── Hero Header ───────────────────────────────────────
  SliverAppBar _buildHeroHeader(DocData doc) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: R.h(context, 320),
      elevation: 0,
      backgroundColor: AppColors.primary,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha:0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 4, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _loadingFav
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: Icon(
                    _isFavourite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: _isFavourite ? Colors.red.shade300 : Colors.white, size: 20,
                  ),
                  tooltip: _isFavourite ? 'Remove from favourites' : 'Add to favourites',
                  onPressed: _toggleFavourite,
                ),
        ),
        Container(
          margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white, size: 20),
            tooltip: 'Share',
            onPressed: _shareDoctor,
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(top: -50, right: -50,
                child: Container(width: 200, height: 200, decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white.withValues(alpha:0.06)))),
              Positioned(bottom: -20, left: -40,
                child: Container(width: 140, height: 140, decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white.withValues(alpha:0.05)))),
              Positioned(top: 80, right: 30,
                child: Container(width: 60, height: 60, decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.white.withValues(alpha:0.04)))),

              Positioned.fill(
                child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 48), // room for app bar

                      // ── Doctor Photo ──────────────────────
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 110, height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Colors.white, Color(0xFFE0E0E0)],
                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                              ),
                              boxShadow: [BoxShadow(
                                color: Colors.black.withValues(alpha:0.2),
                                blurRadius: 20, offset: const Offset(0, 8),
                              )],
                            ),
                            padding: const EdgeInsets.all(3),
                            child: ClipOval(
                              child: doc.img.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: doc.img, width: 104, height: 104, fit: BoxFit.cover,
                                      placeholder: (_, __) => const SkeletonCircle(size: 104),
                                      errorWidget: (_, __, ___) => Container(
                                        color: AppColors.primary.withValues(alpha:0.1),
                                        child: const Icon(Icons.person_rounded, size: 58, color: AppColors.primary),
                                      ))
                                  : Container(
                                      color: Colors.white.withValues(alpha:0.15),
                                      child: const Icon(Icons.person_rounded, size: 58, color: Colors.white),
                                    ),
                            ),
                          ),
                          // Verification badge
                          Positioned(
                            bottom: 4, right: 4,
                            child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1565C0),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [BoxShadow(color: const Color(0xFF1565C0).withValues(alpha:0.4), blurRadius: 8)],
                              ),
                              child: const Icon(Icons.verified_rounded, color: Colors.white, size: 14),
                            ),
                          ),
                          // Online pulse
                          if (doc.online)
                            Positioned(
                              top: 4, right: 4,
                              child: _OnlinePulseDot(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // ── Name ──────────────────────────────
                      Text(doc.name,
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 22,
                              fontWeight: FontWeight.w800, color: Colors.white,
                              letterSpacing: -0.3),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text('${doc.spec}${doc.qual.isNotEmpty ? ' · ${doc.qual}' : ''}',
                          style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 12.5, color: Colors.white70),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 14),

                      // ── Inline stat chips ─────────────────
                      Wrap(
                        spacing: 8, runSpacing: 6,
                        alignment: WrapAlignment.center,
                        children: [
                          _HeaderChip(
                            icon: Icons.work_rounded,
                            label: doc.exp > 0 ? '${doc.exp}+ yrs' : 'Resident',
                            color: const Color(0xFF81D4FA),
                          ),
                          _HeaderChip(
                            icon: Icons.currency_rupee_rounded,
                            label: doc.fee > 0 ? '₹${doc.fee}' : 'Free',
                            color: const Color(0xFFA5D6A7),
                          ),
                          _HeaderChip(
                            icon: doc.online ? Icons.circle : Icons.circle_outlined,
                            label: doc.online ? 'Online Now' : 'Offline',
                            color: doc.online ? const Color(0xFF81C784) : Colors.white54,
                          ),
                        ],
                      ),
                    ],
                  ),
                        ),
                      ),
                    );
                  },
                ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Consultation Type Cards ────────────────────────────
  Widget _buildConsultationTypes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PremiumSectionTitle('Consultation Type', Icons.medical_services_rounded, AppColors.primary),
        const SizedBox(height: 14),
        staticGrid(
          crossAxisCount: 2,
          aspectRatio: 2.15,
          children: _supportedModes.map((t) {
            final meta = _kConsultMeta[t] ?? _kConsultMeta['Video']!;
            final sel = _consultationType == t;
            final iconData = meta['icon'] as IconData;
            final color = meta['color'] as Color;
            final label = meta['label'] as String;
            return GestureDetector(
              onTap: () => setState(() => _consultationType = t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  gradient: sel ? AppColors.primaryGradient : null,
                  color: sel ? null : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: sel ? Colors.transparent : const Color(0xFFE5E7EB),
                    width: 1.5,
                  ),
                  boxShadow: sel
                    ? [BoxShadow(color: AppColors.primary.withValues(alpha:0.28), blurRadius: 14, offset: const Offset(0, 5))]
                    : [const BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: sel ? Colors.white.withValues(alpha:0.2) : color.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(iconData, color: sel ? Colors.white : color, size: 17),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(label, maxLines: 1, style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : const Color(0xFF1F2937),
                          height: 1.2,
                        ), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Text(meta['desc'] as String, maxLines: 1, style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w400,
                          color: sel ? Colors.white70 : const Color(0xFF9CA3AF),
                          height: 1.2,
                        ), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                    ),
                    if (sel) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                    ],
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
        if (_consultationType == 'In-Person') ...[
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'In-person visit required — you\'ll need to travel to the hospital/clinic below for this consultation.',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w500,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFB71C1C).withValues(alpha:0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFB71C1C).withValues(alpha:0.15)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.place_rounded, size: 18, color: Color(0xFFB71C1C)),
                const SizedBox(width: 10),
                Expanded(child: (_hospital != null || _hospitalAddress != null)
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (_hospital != null)
                        Text(_hospital!, style: AppTextStyles.labelMedium.copyWith(color: const Color(0xFFB71C1C))),
                      if (_hospitalAddress != null) ...[
                        const SizedBox(height: 3),
                        Text(_hospitalAddress!, style: AppTextStyles.caption.copyWith(color: context.appTextSecondary)),
                      ],
                    ])
                  : Text(
                      'Clinic location not added by the doctor yet. Please confirm the address with the clinic before your visit.',
                      style: AppTextStyles.caption.copyWith(color: context.appTextSecondary),
                    ),
                ),
              ]),
            ),
          ),
        ],
      ],
    );
  }

  // ── Session Duration ───────────────────────────────────
  Widget _buildDurationSelector(DocData doc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PremiumSectionTitle('Session Duration', Icons.timer_outlined, Color(0xFFF9943B)),
        const SizedBox(height: 14),
        Row(
          children: _kSessionDurations.map((mins) {
            final sel = _selectedDuration == mins;
            final price = _feeForDuration(doc.fee, mins);
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedDuration = mins),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: sel ? AppColors.primaryGradient : null,
                    color: sel ? null : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sel ? Colors.transparent : const Color(0xFFE5E7EB),
                      width: 1.5,
                    ),
                    boxShadow: sel
                        ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 5))]
                        : null,
                  ),
                  child: Column(children: [
                    Text('$mins min', style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : const Color(0xFF1F2937),
                    )),
                    const SizedBox(height: 3),
                    Text(
                      doc.fee > 0 ? '₹$price' : 'Free',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w500,
                        color: sel ? Colors.white70 : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(Icons.lightbulb_outline_rounded, size: 16, color: Colors.amber.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Longer sessions are recommended for better results',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w500,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }


  // ── Languages ─────────────────────────────────────────
  Widget _buildLanguages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PremiumSectionTitle('Languages', Icons.translate_rounded, Color(0xFFF9943B)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _languages.map((lang) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.teal.withValues(alpha:0.25)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.language_rounded, size: 13, color: Colors.teal),
              const SizedBox(width: 5),
              Text(lang, style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.teal,
              )),
            ]),
          )).toList(),
        ),
      ],
    );
  }

  // ── Who is this for? ───────────────────────────────────
  Widget _buildBookingForSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PremiumSectionTitle('Who is this for?', Icons.family_restroom_rounded, Color(0xFF6A1B9A)),
        SizedBox(height: R.h(context, 14)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _BookingForChip(
              label: 'Self',
              selected: _bookingForIndex < 0,
              onTap: () => _selectBookingFor(-1),
            ),
            for (int i = 0; i < _familyMembers.length; i++)
              _BookingForChip(
                label: _familyMembers[i]['name'] as String? ?? 'Member',
                selected: _bookingForIndex == i,
                onTap: () => _selectBookingFor(i),
              ),
          ],
        ),
        if (_bookingForIndex >= 0) ...[
          SizedBox(height: R.h(context, 14)),
          TextField(
            controller: _guestPhoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: "${_familyMembers[_bookingForIndex]['name'] ?? 'Their'}'s phone (optional)",
              hintText: 'So they can join the call themselves',
              prefixIcon: const Icon(Icons.phone_iphone_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          SizedBox(height: R.h(context, 6)),
          Text(
            "Add their number and, once booked, you can share a link so they can join the video call directly from their own phone — you don't need to be with them.",
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: context.appTextSecondary, height: 1.4),
          ),
        ],
      ],
    );
  }

  // ── Date Picker ───────────────────────────────────────
  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const _PremiumSectionTitle('Select Date', Icons.event_rounded, AppColors.primary),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              DateFormat('MMMM yyyy').format(_dates[_selectedDateIndex]),
              style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 82,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _dates.length,
            itemBuilder: (_, i) {
              final d = _dates[i];
              final sel = _selectedDateIndex == i;
              final isToday = i == 0;
              final isWorking = _isDoctorWorkingDay(d);
              return GestureDetector(
                onTap: isWorking
                    ? () => setState(() { _selectedDateIndex = i; _selectedSlot = null; })
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 60,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    gradient: sel ? AppColors.primaryGradient : null,
                    color: sel ? null : (!isWorking ? Colors.grey.shade100 : Colors.white),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: sel ? AppColors.primary : (!isWorking ? Colors.grey.shade200 : context.appBorder),
                      width: sel ? 1.5 : 1,
                    ),
                    boxShadow: sel
                        ? [BoxShadow(color: AppColors.primary.withValues(alpha:0.3), blurRadius: 10, offset: const Offset(0, 4))]
                        : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(
                      isToday ? 'Today' : (i == 1 ? 'Tmrw' : DateFormat('EEE').format(d)),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 10,
                        color: sel ? Colors.white70 : (!isWorking ? Colors.grey.shade400 : context.appTextSecondary),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('d').format(d),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800,
                        color: sel ? Colors.white : (!isWorking ? Colors.grey.shade400 : context.appTextPrimary),
                      ),
                    ),
                    Text(
                      DateFormat('MMM').format(d),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 9,
                        color: sel ? Colors.white60 : (!isWorking ? Colors.grey.shade400 : context.appTextHint),
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Time Slots ────────────────────────────────────────
  Widget _buildSlotsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          _PremiumSectionTitle('Available Slots', Icons.access_time_rounded, AppColors.primary),
          Spacer(),
          _LegendDot(AppColors.primary, 'Available'),
          SizedBox(width: 14),
          _LegendDot(Color(0xFFD1D5DB), 'Booked'),
        ]),
        const SizedBox(height: 16),
        StreamBuilder<Set<String>>(
          stream: _bookedSlotsStream(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return _buildSlotSkeleton();
            }
            final booked = snap.data ?? {};
            final selectedDate = _dates[_selectedDateIndex];
            if (!_isDoctorWorkingDay(selectedDate)) {
              return _buildSlotEmpty(
                Icons.event_busy_rounded, 'Not Available',
                'Doctor is off on this day. Please select another date.',
                Colors.grey,
              );
            }
            final allSlots = _slotsForSelectedDate();
            final slots = allSlots.where((s) => !_isSlotExpired(s)).toList();
            if (slots.isEmpty) {
              return _buildSlotEmpty(
                Icons.schedule_rounded, 'No Slots Available',
                'All slots for today have passed.\nPlease select a future date.',
                Colors.orange,
              );
            }
            // Section by time of day
            final morning   = slots.where((s) => _slotHour(s) < 12).toList();
            final afternoon = slots.where((s) => _slotHour(s) >= 12 && _slotHour(s) < 17).toList();
            final evening   = slots.where((s) => _slotHour(s) >= 17).toList();

            return Column(children: [
              if (morning.isNotEmpty) ...[
                _SlotSection(label: 'Morning', icon: Icons.wb_sunny_outlined, color: Colors.orange,
                    slots: morning, booked: booked, selected: _selectedSlot,
                    onTap: (s) => setState(() => _selectedSlot = _selectedSlot == s ? null : s)),
                const SizedBox(height: 14),
              ],
              if (afternoon.isNotEmpty) ...[
                _SlotSection(label: 'Afternoon', icon: Icons.wb_cloudy_outlined, color: const Color(0xFF1565C0),
                    slots: afternoon, booked: booked, selected: _selectedSlot,
                    onTap: (s) => setState(() => _selectedSlot = _selectedSlot == s ? null : s)),
                const SizedBox(height: 14),
              ],
              if (evening.isNotEmpty)
                _SlotSection(label: 'Evening', icon: Icons.nights_stay_outlined, color: const Color(0xFF6A1B9A),
                    slots: evening, booked: booked, selected: _selectedSlot,
                    onTap: (s) => setState(() => _selectedSlot = _selectedSlot == s ? null : s)),
            ]);
          },
        ),
      ],
    );
  }

  int _slotHour(String slot) {
    try {
      final parts = slot.trim().split(' ');
      final hm = parts[0].split(':');
      int h = int.parse(hm[0]);
      if (parts.length > 1 && parts[1].toUpperCase() == 'PM' && h != 12) h += 12;
      if (parts.length > 1 && parts[1].toUpperCase() == 'AM' && h == 12) h = 0;
      return h;
    } catch (_) { return 0; }
  }

  Widget _buildSlotSkeleton() => staticGrid(
    crossAxisCount: 3,
    aspectRatio: 2.5,
    children: List.generate(6, (_) => Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10),
      ),
    )),
  );

  Widget _buildSlotEmpty(IconData icon, String title, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha:0.2)),
      ),
      child: Column(children: [
        Icon(icon, size: 36, color: color.withValues(alpha:0.7)),
        const SizedBox(height: 10),
        Text(title, style: AppTextStyles.labelLarge.copyWith(color: color)),
        const SizedBox(height: 4),
        Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: context.appTextHint),
            textAlign: TextAlign.center),
      ]),
    );
  }

  // ── Bottom Bar ────────────────────────────────────────
  Widget _buildBottomBar(DocData doc) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 24, offset: Offset(0, -6))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2),
        )),
        const SizedBox(height: 14),
        if (_selectedSlot != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withValues(alpha:0.12), width: 1.5),
            ),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.event_available_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${DateFormat('EEE, d MMM').format(_dates[_selectedDateIndex])} · $_selectedSlot',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isRescheduling
                      ? '$_consultationType · $_selectedDuration min'
                      : '$_consultationType · $_selectedDuration min · ₹${_feeForDuration(doc.fee, _selectedDuration)}',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 11.5, color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ])),
              GestureDetector(
                onTap: () => setState(() => _selectedSlot = null),
                child: Container(
                  width: 28, height: 28,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF3F4F6), shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF9CA3AF)),
                ),
              ),
            ]),
          ),
        ],
        SizedBox(
          width: double.infinity,
          height: 54,
          child: _booking
              ? Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                    SizedBox(width: 12),
                    Text('Confirming...', style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white,
                    )),
                  ]),
                )
              : _selectedSlot == null
                ? Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Select a time slot to continue',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600,
                          color: Color(0xFFD1D5DB),
                        )),
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(
                        color: AppColors.primary.withValues(alpha:0.35), blurRadius: 18, offset: const Offset(0, 7),
                      )],
                    ),
                    child: ElevatedButton(
                      onPressed: () => _bookSlot(doc),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(
                          _isRescheduling
                              ? Icons.edit_calendar_rounded
                              : widget.initialMode == 'quickConnect'
                                  ? Icons.flash_on_rounded
                                  : Icons.calendar_month_rounded,
                          size: 19, color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(_isRescheduling
                            ? 'Confirm Reschedule'
                            : widget.initialMode == 'quickConnect'
                                ? 'Connect Now · ₹${_feeForDuration(doc.fee, _selectedDuration)}'
                                : 'Book Appointment · ₹${_feeForDuration(doc.fee, _selectedDuration)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white,
                          )),
                      ]),
                    ),
                  ),
        ),
      ]),
    );
  }

  // ── Skeleton Loading ──────────────────────────────────
  Widget _buildSkeleton(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: R.h(context, 320),
            backgroundColor: AppColors.primary,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              tooltip: 'Back',
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
                child: SafeArea(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(height: 48),
                    AppShimmer(
                      child: Container(width: 110, height: 110,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha:0.3), shape: BoxShape.circle)),
                    ),
                    const SizedBox(height: 14),
                    AppShimmer(
                      child: Container(width: 180, height: 18,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha:0.3),
                            borderRadius: BorderRadius.circular(9))),
                    ),
                    const SizedBox(height: 8),
                    AppShimmer(
                      child: Container(width: 120, height: 13,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha:0.2),
                            borderRadius: BorderRadius.circular(6))),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(children: [
                SkeletonBox(width: double.infinity, height: 80),
                SizedBox(height: 16),
                SkeletonBox(width: double.infinity, height: 120),
                SizedBox(height: 16),
                SkeletonBox(width: double.infinity, height: 100),
                SizedBox(height: 16),
                SkeletonBox(width: double.infinity, height: 180),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Not Found ─────────────────────────────────────────
  Widget _buildNotFound(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
      ),
      body: AppEmptyState(
        icon: Icons.person_off_rounded,
        title: 'Doctor not found',
        message: 'This doctor profile is no longer available.',
        actionLabel: 'Go Back',
        onAction: () => context.pop(),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ──────────────────────────────────────────────────────────

// ── Animated online pulse dot ─────────────────────────────
class _OnlinePulseDot extends StatefulWidget {
  @override
  State<_OnlinePulseDot> createState() => _OnlinePulseDotState();
}

class _OnlinePulseDotState extends State<_OnlinePulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
        ..repeat(reverse: true);
    _scale = Tween(begin: 0.85, end: 1.3).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: Container(
      width: 16, height: 16,
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [BoxShadow(color: const Color(0xFF4CAF50).withValues(alpha:0.5), blurRadius: 8)],
      ),
    ),
  );
}

// ── Header stat chip ──────────────────────────────────────
class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _HeaderChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha:0.18),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha:0.25), width: 1),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: Colors.white),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(
        fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white,
        letterSpacing: 0.1,
      )),
    ]),
  );
}

// ── Section title ─────────────────────────────────────────
class _BookingForChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _BookingForChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.primaryGradient : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFFE5E7EB),
            width: 1.5,
          ),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF1F2937),
          ),
        ),
      ),
    );
  }
}

class _PremiumSectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _PremiumSectionTitle(this.title, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        width: 4, height: 20,
        decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 14),
      Text(title, style: const TextStyle(
        fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700,
        color: Color(0xFF111827), letterSpacing: -0.2,
      )),
    ],
  );
}

// ── Trust stats row ───────────────────────────────────────
class _TrustStatsRow extends StatelessWidget {
  final DocData doc;
  const _TrustStatsRow({required this.doc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha:0.06), blurRadius: 20, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(children: [
        Expanded(child: _StatCell(doc.exp > 0 ? '${doc.exp}+ yrs' : 'New', 'Experience', Icons.work_history_rounded, AppColors.primary)),
        _vDivider(),
        Expanded(child: _StatCell(doc.fee > 0 ? '₹${doc.fee}' : 'Free', 'Consult Fee', Icons.currency_rupee_rounded, const Color(0xFF8B5CF6))),
      ]),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _StatCell(this.value, this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
      const SizedBox(height: 8),
      Text(value, textAlign: TextAlign.center, style: const TextStyle(
        fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w800,
        color: Color(0xFF111827),
      )),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center, style: const TextStyle(
        fontFamily: 'Poppins', fontSize: 10.5, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500,
      )),
    ],
  );
}

Widget _vDivider() => Container(width: 1, height: 52, color: const Color(0xFFF3F4F6));

// ── About section with expand ─────────────────────────────
class _AboutSection extends StatefulWidget {
  final String about;
  const _AboutSection({required this.about});
  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const maxLines = 3;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _PremiumSectionTitle('About Doctor', Icons.info_outline_rounded, AppColors.primary),
      const SizedBox(height: 10),
      AnimatedCrossFade(
        duration: const Duration(milliseconds: 250),
        crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        firstChild: Text(
          widget.about,
          maxLines: maxLines, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: context.appTextSecondary, height: 1.7),
        ),
        secondChild: Text(
          widget.about,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: context.appTextSecondary, height: 1.7),
        ),
      ),
      if (widget.about.length > 120) ...[
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Text(
            _expanded ? 'Show less' : 'Read more',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w700, color: AppColors.primary),
          ),
        ),
      ],
    ]);
  }
}

// ── Hospital card ─────────────────────────────────────────
// ── Slot Section (Morning / Afternoon / Evening) ──────────
class _SlotSection extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final List<String> slots;
  final Set<String> booked;
  final String? selected;
  final ValueChanged<String> onTap;

  const _SlotSection({
    required this.label, required this.icon, required this.color,
    required this.slots, required this.booked,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final available = slots.where((s) => !booked.contains(s)).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 4, height: 16,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
          fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: color,
        )),
        const SizedBox(width: 8),
        Text('$available available', style: TextStyle(
          fontFamily: 'Poppins', fontSize: 11,
          color: color.withValues(alpha:0.6), fontWeight: FontWeight.w500,
        )),
      ]),
      const SizedBox(height: 10),
      staticGrid(
        crossAxisCount: 3,
        aspectRatio: 2.3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: slots.map((slot) {
          final isBooked = booked.contains(slot);
          final isSelected = selected == slot;
          return GestureDetector(
            onTap: isBooked ? null : () => onTap(slot),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: isSelected ? AppColors.primaryGradient : null,
                color: isBooked
                    ? const Color(0xFFF9FAFB)
                    : isSelected ? null : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isBooked
                      ? const Color(0xFFE5E7EB)
                      : isSelected ? Colors.transparent : const Color(0xFFE5E7EB),
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: AppColors.primary.withValues(alpha:0.28), blurRadius: 10, offset: const Offset(0, 4))]
                    : null,
              ),
              child: Text(slot, style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600,
                color: isBooked
                    ? const Color(0xFFD1D5DB)
                    : isSelected ? Colors.white : const Color(0xFF111827),
              )),
            ),
          );
        }).toList(),
      ),
    ]);
  }
}

// ── Booking confirmation row ──────────────────────────────
class _ConfirmRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _ConfirmRow(this.icon, this.text, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 32, height: 32, decoration: BoxDecoration(
      color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, size: 16, color: color)),
    const SizedBox(width: 10),
    Expanded(child: Text(text, style: AppTextStyles.labelMedium.copyWith(color: context.appTextPrimary))),
  ]);
}

// ── Legend dot ────────────────────────────────────────────
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot(this.color, this.label);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 8, height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(
      fontFamily: 'Poppins', fontSize: 11, color: Color(0xFF6B7280), fontWeight: FontWeight.w500,
    )),
  ]);
}
