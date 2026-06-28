import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../data/doctors_data.dart';
import '../models/doctor_review.dart';
import '../services/review_service.dart';

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

class DoctorProfileScreen extends StatefulWidget {
  final String doctorId;
  const DoctorProfileScreen({super.key, required this.doctorId});
  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  late final List<DateTime> _dates;
  int _selectedDateIndex = 0;
  String? _selectedSlot;
  String _consultationType = 'Video';
  bool _booking = false;

  DocData? _doc;
  bool _loadingDoc = true;

  bool _isFavourite = false;
  bool _loadingFav = true;

  Map<String, dynamic>? _availability;
  String? _hospital;
  String? _hospitalAddress;
  List<String> _languages = [];
  List<String> _supportedModes = ['Video', 'Audio', 'In-Person', 'Chat'];

  StreamSubscription<DocumentSnapshot>? _docSub;
  StreamSubscription<DocumentSnapshot>? _favSub;
  Timer? _slotTimer;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _dates = List.generate(10, (i) => today.add(Duration(days: i)));
    _subscribeDoctor();
    _subscribeFavouriteState();
    _slotTimer = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
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
        _hospital = d['hospital'] as String? ?? d['hospitalAffiliation'] as String?;
        _hospitalAddress = d['hospitalAddress'] as String? ?? d['clinicAddress'] as String?;
        _languages = (d['languages'] as List<dynamic>?)?.cast<String>() ?? [];
        if (modes != null && modes.isNotEmpty) {
          _supportedModes = modes.cast<String>();
        }
        _loadingDoc = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loadingDoc = false);
    });
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
        '⭐ ${doc.rating} rating • ${doc.exp}+ years experience\n'
        '💊 Consultation fee: ₹${doc.fee}\n\n'
        'Book an appointment on MedNu — your trusted healthcare partner.\n'
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

  List<String> _slotsForSelectedDate() {
    final date = _dates[_selectedDateIndex];
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
      return slots;
    } catch (_) {
      return _kDefaultSlots.toList();
    }
  }

  bool _isSlotExpired(String slot) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = _dates[_selectedDateIndex];
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

    setState(() => _booking = true);

    final patient = FirebaseAuth.instance.currentUser;
    final uid = patient?.uid;
    if (uid == null) {
      setState(() => _booking = false);
      return;
    }

    final dateKey = _selectedDateKey;
    final slot    = _selectedSlot!;
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

    // ── Pre-flight: confirm the slot is still free ───────────────────────────
    try {
      final existing = await db.collection('appointments')
          .where('doctorId', isEqualTo: widget.doctorId)
          .where('date', isEqualTo: dateKey)
          .where('time', isEqualTo: slot)
          .where('status', isEqualTo: 'booked')
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) throw Exception('slot_taken');
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

    // ── Open PaymentScreen — the slot is free, now collect payment ───────────
    // PaymentScreen pops with `true` only after Razorpay verifies the payment
    // server-side (HMAC-SHA256 via Cloud Function). We write to Firestore only
    // after that confirmation so we never create a booking without a real payment.
    if (!mounted) return;
    final paid = await context.push<bool>(
      AppRoutes.payment,
      extra: {
        'amount':      doc.fee.toString(),
        'description': 'Appointment with Dr. ${doc.name} · $slot · ${DateFormat('d MMM').format(_dates[_selectedDateIndex])}',
      },
    );

    if (paid != true || !mounted) return;

    // ── Payment verified — write appointment + payment record ────────────────
    setState(() => _booking = true);
    try {
      final apptRef = db.collection('appointments').doc();
      final payRef  = db.collection('payments').doc();
      final now     = Timestamp.now();

      final batch = db.batch();
      batch.set(apptRef, {
        'doctorId':          widget.doctorId,
        'doctorName':        doc.name,
        'doctorSpecialty':   doc.spec,
        'patientId':         uid,
        'patientName':       patientName,
        'date':              dateKey,
        'time':              slot,
        'consultationType':  _consultationType,
        'fee':               doc.fee,
        'status':            'booked',
        'createdAt':         now,
        'updatedAt':         now,
      });
      batch.set(payRef, {
        'userId':        uid,
        'doctorId':      widget.doctorId,
        'appointmentId': apptRef.id,
        'amount':        doc.fee,
        'type':          'appointment',
        'status':        'paid',
        'gateway':       'razorpay',
        'createdAt':     now,
      });
      await batch.commit();

      if (mounted) {
        final bookedSlot = slot;
        final bookedDate = _dates[_selectedDateIndex];
        setState(() { _selectedSlot = null; _booking = false; });
        _showBookingConfirmation(doc, bookedSlot, bookedDate);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _booking = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment received but booking failed. Please contact support.'),
          backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating,
        ));
      }
    }
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
            const Text('Appointment Booked!',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('Your slot is confirmed', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.background,
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
              child: const Text('Done', style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
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
    super.dispose();
  }

  // ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loadingDoc) return _buildSkeleton(context);
    if (_doc == null) return _buildNotFound(context);
    final doc = _doc!;

    return Scaffold(
      backgroundColor: AppColors.background,
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
                  child: _TrustStatsRow(doc: doc, doctorId: widget.doctorId),
                ),
                const SizedBox(height: 24),

                // ── Consultation Type Cards ──────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildConsultationTypes(),
                ),
                const SizedBox(height: 24),

                // ── About Section ────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _AboutSection(about: doc.about),
                ),
                const SizedBox(height: 24),

                // ── Specialities ─────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildSpecialities(doc),
                ),
                const SizedBox(height: 24),

                // ── Hospital Card ─────────────────────────
                if (_hospital != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: _HospitalCard(name: _hospital!, address: _hospitalAddress),
                  ),

                // ── Languages ────────────────────────────
                if (_languages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: _buildLanguages(),
                  ),

                // ── Patient Reviews ───────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _ReviewsSection(doctorId: widget.doctorId),
                ),
                const SizedBox(height: 28),

                // ── Divider before booking section ────────
                Container(
                  height: 8,
                  color: const Color(0xFFF9FAFB),
                ),
                const SizedBox(height: 24),

                // ── Date Picker ───────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildDatePicker(),
                ),
                const SizedBox(height: 24),

                // ── Time Slots ────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildSlotsSection(),
                ),
                const SizedBox(height: 120),
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
      expandedHeight: 320,
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
                            icon: Icons.star_rounded,
                            label: doc.rating > 0 ? doc.rating.toStringAsFixed(1) : 'New',
                            color: Colors.amber,
                          ),
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
        _PremiumSectionTitle('Consultation Type', Icons.medical_services_rounded, AppColors.primary),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 2.9,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: sel ? Colors.white.withValues(alpha:0.2) : color.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(iconData, color: sel ? Colors.white : color, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(label, style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : const Color(0xFF1F2937),
                      ), overflow: TextOverflow.ellipsis),
                    ),
                    if (sel)
                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
        if (_consultationType == 'In-Person' && (_hospital != null || _hospitalAddress != null))
          Padding(
            padding: const EdgeInsets.only(top: 12),
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
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (_hospital != null)
                    Text(_hospital!, style: AppTextStyles.labelMedium.copyWith(color: const Color(0xFFB71C1C))),
                  if (_hospitalAddress != null) ...[
                    const SizedBox(height: 3),
                    Text(_hospitalAddress!, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ])),
              ]),
            ),
          ),
      ],
    );
  }

  // ── Specialities ──────────────────────────────────────
  Widget _buildSpecialities(DocData doc) {
    final specs = doc.specialities.where((s) => s.isNotEmpty).toList();
    if (specs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PremiumSectionTitle('Specialities', Icons.local_pharmacy_rounded, const Color(0xFF6A1B9A)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: specs.asMap().entries.map((entry) {
            final colors = [
              const Color(0xFF1565C0), const Color(0xFF2E7D32),
              const Color(0xFF6A1B9A), const Color(0xFFB71C1C),
              const Color(0xFF00897B), const Color(0xFFF57F17),
            ];
            final c = colors[entry.key % colors.length];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: c.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: c.withValues(alpha:0.25)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.local_pharmacy_rounded, size: 13, color: c),
                const SizedBox(width: 5),
                Text(entry.value, style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: c,
                )),
              ]),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Languages ─────────────────────────────────────────
  Widget _buildLanguages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PremiumSectionTitle('Languages', Icons.translate_rounded, const Color(0xFF00897B)),
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

  // ── Date Picker ───────────────────────────────────────
  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _PremiumSectionTitle('Select Date', Icons.event_rounded, AppColors.primary),
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
                      color: sel ? AppColors.primary : (!isWorking ? Colors.grey.shade200 : AppColors.border),
                      width: sel ? 1.5 : 1,
                    ),
                    boxShadow: sel
                        ? [BoxShadow(color: AppColors.primary.withValues(alpha:0.3), blurRadius: 10, offset: const Offset(0, 4))]
                        : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(
                      isToday ? 'Today' : DateFormat('EEE').format(d),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 10,
                        color: sel ? Colors.white70 : (!isWorking ? Colors.grey.shade400 : AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('d').format(d),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800,
                        color: sel ? Colors.white : (!isWorking ? Colors.grey.shade400 : AppColors.textPrimary),
                      ),
                    ),
                    Text(
                      DateFormat('MMM').format(d),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 9,
                        color: sel ? Colors.white60 : (!isWorking ? Colors.grey.shade400 : AppColors.textHint),
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
        Row(children: [
          _PremiumSectionTitle('Available Slots', Icons.access_time_rounded, AppColors.primary),
          const Spacer(),
          _LegendDot(AppColors.primary, 'Available'),
          const SizedBox(width: 14),
          _LegendDot(const Color(0xFFD1D5DB), 'Booked'),
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

  Widget _buildSlotSkeleton() => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3, childAspectRatio: 2.5, crossAxisSpacing: 10, mainAxisSpacing: 10,
    ),
    itemCount: 6,
    itemBuilder: (_, __) => Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10),
      ),
    ),
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
        Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
            textAlign: TextAlign.center),
      ]),
    );
  }

  // ── Bottom Bar ────────────────────────────────────────
  Widget _buildBottomBar(DocData doc) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x12000000), blurRadius: 24, offset: Offset(0, -6))],
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
                  '$_consultationType · ₹${doc.fee}',
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
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6), shape: BoxShape.circle,
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
                        const Icon(Icons.calendar_month_rounded, size: 19, color: Colors.white),
                        const SizedBox(width: 8),
                        Text('Book Appointment · ₹${doc.fee}',
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
            expandedHeight: 320,
            backgroundColor: AppColors.primary,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                SkeletonBox(width: double.infinity, height: 80),
                const SizedBox(height: 16),
                SkeletonBox(width: double.infinity, height: 120),
                const SizedBox(height: 16),
                SkeletonBox(width: double.infinity, height: 100),
                const SizedBox(height: 16),
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
      const SizedBox(width: 10),
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
  final String doctorId;
  const _TrustStatsRow({required this.doc, required this.doctorId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DoctorRatingSummary>(
      stream: ReviewService.ratingSummaryStream(doctorId),
      builder: (context, snap) {
        final summary = snap.data;
        final hasRating = summary != null && summary.totalReviews > 0;
        final displayRating = hasRating ? summary.averageRating.toStringAsFixed(1) : (doc.rating > 0 ? doc.rating.toStringAsFixed(1) : '—');
        final reviewCount = hasRating ? '${summary.totalReviews}' : (doc.reviews > 0 ? '${doc.reviews}' : '—');

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha:0.06), blurRadius: 20, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(children: [
            Expanded(child: _StatCell(displayRating, 'Rating', Icons.star_rounded, const Color(0xFFF59E0B))),
            _vDivider(),
            Expanded(child: _StatCell(doc.exp > 0 ? '${doc.exp}+ yrs' : 'New', 'Experience', Icons.work_history_rounded, AppColors.primary)),
            _vDivider(),
            Expanded(child: _StatCell(reviewCount, 'Reviews', Icons.people_alt_rounded, const Color(0xFF10B981))),
            _vDivider(),
            Expanded(child: _StatCell(doc.fee > 0 ? '₹${doc.fee}' : 'Free', 'Consult Fee', Icons.currency_rupee_rounded, const Color(0xFF8B5CF6))),
          ]),
        );
      },
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
      _PremiumSectionTitle('About Doctor', Icons.info_outline_rounded, AppColors.primary),
      const SizedBox(height: 10),
      AnimatedCrossFade(
        duration: const Duration(milliseconds: 250),
        crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        firstChild: Text(
          widget.about,
          maxLines: maxLines, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary, height: 1.7),
        ),
        secondChild: Text(
          widget.about,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary, height: 1.7),
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
class _HospitalCard extends StatelessWidget {
  final String name;
  final String? address;
  const _HospitalCard({required this.name, this.address});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _PremiumSectionTitle('Hospital / Clinic', Icons.local_hospital_rounded, const Color(0xFF1565C0)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1565C0).withValues(alpha:0.1)),
          boxShadow: [BoxShadow(color: const Color(0xFF1565C0).withValues(alpha:0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.local_hospital_rounded, color: Color(0xFF1565C0), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: AppTextStyles.labelLarge.copyWith(color: AppColors.textPrimary)),
            if (address != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.place_rounded, size: 12, color: AppColors.textHint),
                const SizedBox(width: 3),
                Expanded(child: Text(address!,
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis)),
              ]),
            ],
          ])),
        ]),
      ),
    ]);
  }
}

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
      Wrap(
        spacing: 8, runSpacing: 8,
        children: slots.map((slot) {
          final isBooked = booked.contains(slot);
          final isSelected = selected == slot;
          return GestureDetector(
            onTap: isBooked ? null : () => onTap(slot),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 100,
              height: 42,
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
    Expanded(child: Text(text, style: AppTextStyles.labelMedium.copyWith(color: AppColors.textPrimary))),
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

// ──────────────────────────────────────────────────────────
// REVIEWS SECTION
// ──────────────────────────────────────────────────────────
class _ReviewsSection extends StatefulWidget {
  final String doctorId;
  const _ReviewsSection({required this.doctorId});

  @override
  State<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<_ReviewsSection> {
  bool _showReviews = false;

  @override
  Widget build(BuildContext context) {
    final doctorId = widget.doctorId;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      StreamBuilder<DoctorRatingSummary>(
        stream: ReviewService.ratingSummaryStream(doctorId),
        builder: (context, snap) {
          final summary = snap.data;
          final avg = summary?.averageRating ?? 0.0;
          final total = summary?.totalReviews ?? 0;
          final dist = summary?.ratingDistribution ?? {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _PremiumSectionTitle('Patient Reviews', Icons.star_rounded, Colors.amber.shade700),
              const Spacer(),
              if (total > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.accent.withValues(alpha:0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.verified_rounded, size: 12, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Text('$total verified', style: AppTextStyles.caption.copyWith(
                        color: AppColors.accent, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
            const SizedBox(height: 14),
            if (total > 0) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha:0.1), blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: Row(children: [
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(avg.toStringAsFixed(1), style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 48, fontWeight: FontWeight.w800,
                        color: AppColors.primary, height: 1.0)),
                    const SizedBox(height: 4),
                    Row(mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (i) => Icon(
                        i < avg.floor() ? Icons.star_rounded
                            : (i < avg && avg % 1 >= 0.5) ? Icons.star_half_rounded
                            : Icons.star_outline_rounded,
                        size: 15, color: Colors.amber,
                      )),
                    ),
                    const SizedBox(height: 4),
                    Text('out of 5', style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
                  ]),
                  const SizedBox(width: 20),
                  Container(width: 1, height: 70, color: AppColors.divider),
                  const SizedBox(width: 20),
                  Expanded(child: Column(
                    children: [5, 4, 3, 2, 1].map((star) {
                      final count = dist[star] ?? 0;
                      final fraction = total > 0 ? count / total : 0.0;
                      final barColor = star >= 4 ? const Color(0xFF2E7D32)
                          : star == 3 ? Colors.amber : AppColors.error;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Text('$star', style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
                          const SizedBox(width: 3),
                          const Icon(Icons.star_rounded, size: 10, color: Colors.amber),
                          const SizedBox(width: 6),
                          Expanded(child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: fraction, minHeight: 6,
                              backgroundColor: AppColors.divider,
                              valueColor: AlwaysStoppedAnimation<Color>(barColor),
                            ),
                          )),
                          const SizedBox(width: 6),
                          SizedBox(width: 20,
                              child: Text('$count', style: AppTextStyles.caption.copyWith(color: AppColors.textHint))),
                        ]),
                      );
                    }).toList(),
                  )),
                ]),
              ),
              const SizedBox(height: 16),
              if (!_showReviews)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _showReviews = true),
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: const Text('View Reviews'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary.withValues(alpha:0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
            ],
            if (total == 0)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(children: [
                  Container(width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha:0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.rate_review_outlined, size: 28, color: Colors.amber)),
                  const SizedBox(height: 12),
                  Text('No Reviews Yet', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text('Be the first to review after your consultation',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
                      textAlign: TextAlign.center),
                ]),
              ),
          ]);
        },
      ),
      if (_showReviews)
      StreamBuilder<List<DoctorReview>>(
        stream: ReviewService.reviewsStream(doctorId, limit: 5),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Column(children: const [
              _ReviewCardSkeleton(), _ReviewCardSkeleton(), _ReviewCardSkeleton(),
            ]);
          }
          final reviews = snap.data ?? [];
          if (reviews.isEmpty) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(children: [
                Container(width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha:0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.rate_review_outlined, size: 28, color: Colors.amber)),
                const SizedBox(height: 12),
                Text('No Reviews Yet', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text('Be the first to review after your consultation',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
                    textAlign: TextAlign.center),
              ]),
            );
          }
          return Column(children: reviews.map((r) => _ReviewCard(review: r)).toList());
        },
      ),
    ]);
  }
}

class _ReviewCard extends StatelessWidget {
  final DoctorReview review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final timeAgo = _timeAgo(review.createdAt);
    final initial = review.patientName.isNotEmpty ? review.patientName[0].toUpperCase() : 'P';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary.withValues(alpha:0.8), AppColors.secondary.withValues(alpha:0.8)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(initial, style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(review.patientName, style: AppTextStyles.labelLarge.copyWith(color: AppColors.textPrimary))),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha:0.1), borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.accent.withValues(alpha:0.2)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.verified_rounded, size: 10, color: AppColors.accent),
                  const SizedBox(width: 3),
                  Text('Verified', style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.accent)),
                ]),
              ),
            ]),
            const SizedBox(height: 2),
            Text(timeAgo, style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) => Icon(
                i < review.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 14, color: Colors.amber,
              )),
            ),
            const SizedBox(height: 4),
            Text(review.rating.toStringAsFixed(1), style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.amber)),
          ]),
        ]),
        if (review.reviewText.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background, borderRadius: BorderRadius.circular(10),
            ),
            child: Text(review.reviewText, style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.textSecondary, height: 1.6)),
          ),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withValues(alpha:0.15)),
            ),
            child: Text(review.consultationType, style: AppTextStyles.caption.copyWith(
                color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 30) {
      final months = (diff.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    }
    if (diff.inDays >= 1) return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

class _ReviewCardSkeleton extends StatelessWidget {
  const _ReviewCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: const AppShimmer(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SkeletonCircle(size: 42),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SkeletonBox(width: 140, height: 13, radius: 4),
              SizedBox(height: 5),
              SkeletonBox(width: 100, height: 11, radius: 4),
            ])),
            SkeletonBox(width: 60, height: 20, radius: 6),
          ]),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 11, radius: 4),
          SizedBox(height: 5),
          SkeletonBox(width: double.infinity, height: 11, radius: 4),
          SizedBox(height: 5),
          SkeletonBox(width: 200, height: 11, radius: 4),
        ]),
      ),
    );
  }
}
