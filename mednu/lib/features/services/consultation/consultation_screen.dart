import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';

class ConsultationScreen extends ConsumerStatefulWidget {
  const ConsultationScreen({super.key});

  @override
  ConsumerState<ConsultationScreen> createState() =>
      _ConsultationScreenState();
}

class _ConsultationScreenState extends ConsumerState<ConsultationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedDateIndex = 0;
  int _selectedTimeIndex = -1;
  String _selectedType = 'Video';

  // Dynamic dates: today + next 6 days
  late final List<DateTime> _dateTimes;

  static const _kDefaultSlots = [
    '09:00 AM', '10:00 AM', '11:00 AM', '12:00 PM',
    '02:00 PM', '03:00 PM', '04:00 PM', '05:00 PM', '06:00 PM',
  ];

  List<Map<String, dynamic>> _onlineDoctors = [];
  List<Map<String, dynamic>> _allDoctors = [];
  StreamSubscription<QuerySnapshot>? _doctorSub;
  StreamSubscription<QuerySnapshot>? _onlineDoctorSub;
  bool _quickConnectLoading = true;

  Map<String, dynamic>? _selectedDoctor;
  String _scheduleSearch = '';

  // Dynamic slots derived from the selected doctor's Firestore availability.
  Map<String, dynamic>? _selectedDoctorAvailability;
  List<String> _scheduleSlots = [];

  // Realtime booked slots for the Schedule tab's selected doctor + date.
  Set<String> _bookedScheduleTimes = {};
  StreamSubscription<QuerySnapshot>? _bookedScheduleSub;
  // Fires every minute so expired slots vanish without waiting for a Firestore event.
  Timer? _scheduleSlotTimer;

  @override
  void initState() {
    super.initState();
    _dateTimes = List.generate(7, (i) => DateTime.now().add(Duration(days: i)));
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) setState(() {});
    });
    _subscribeDoctors();
    _scheduleSlotTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) { if (mounted) setState(() {}); },
    );
  }

  void _subscribeDoctors() {
    // Capped at 150 so we never pull the whole collection in one snapshot.
    // Firestore serves docs in insertion order here; re-order client-side as
    // needed or add an .orderBy('name') index if alphabetical sort matters.
    _doctorSub = FirebaseFirestore.instance
        .collection('doctors')
        .where('status', isEqualTo: 'active')
        .limit(150)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final all = snap.docs.map((doc) => _docToMap(doc)).toList();
      // Avoid triggering a rebuild when the data hasn't actually changed.
      if (_allDoctors.length == all.length &&
          _allDoctors.isNotEmpty &&
          all.isNotEmpty &&
          _allDoctors.first['uid'] == all.first['uid']) return;
      final wasNull = _selectedDoctor == null;
      setState(() {
        _allDoctors = all;
        _selectedDoctor ??= all.isNotEmpty ? all.first : null;
      });
      if (wasNull && _selectedDoctor != null) {
        _subscribeBookedScheduleSlots();
        _fetchDoctorAvailability(_selectedDoctor!['uid'] as String);
      }
    });

    // includeMetadataChanges: true so we can detect cache vs server.
    // We skip the first cache emission entirely — only trust server results
    // so a doctor who toggled offline is never shown as available.
    _onlineDoctorSub = FirebaseFirestore.instance
        .collection('doctors')
        .where('status', isEqualTo: 'active')
        .where('isOnline', isEqualTo: true)
        .limit(50)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      if (!mounted) return;
      if (snap.metadata.isFromCache) return; // ignore stale local cache
      // _docToMap already folds the heartbeat-freshness check into 'available',
      // so this list and the Schedule tab's _allDoctors agree on who's online.
      final fresh = snap.docs
          .map((doc) => _docToMap(doc))
          .where((doc) => doc['available'] == true)
          .toList();
      setState(() {
        _onlineDoctors = fresh;
        _quickConnectLoading = false;
      });
    });
  }

  Map<String, dynamic> _docToMap(QueryDocumentSnapshot<Object?> doc) {
    final d = doc.data() as Map<String, dynamic>;
    final specialty = d['specialty'] as String? ?? 'General Physician';
    final lastHeartbeat = d['lastHeartbeat'];
    // A doctor only counts as online if the flag is set AND their heartbeat
    // is fresh — computed once here so every tab agrees on the same status.
    final isOnline = d['isOnline'] == true && _hasFreshHeartbeat(lastHeartbeat);
    // Use Firestore waitTime field if present; otherwise derive a pseudo-random
    // but stable wait time from the doc ID so it doesn't flicker on rebuilds.
    String waitLabel;
    if (isOnline) {
      final firestoreWait = d['waitTime'];
      if (firestoreWait != null) {
        waitLabel = '~${firestoreWait} min wait';
      } else {
        // Stable pseudo-random 2-8 min based on doc id hash
        final seed = doc.id.codeUnits.fold(0, (a, b) => a + b) % 7;
        waitLabel = '~${seed + 2} min wait';
      }
    } else {
      waitLabel = 'Offline';
    }
    return {
      'uid': doc.id,
      'name': d['name'] as String? ?? 'Doctor',
      'specialty': specialty,
      'photoUrl': d['photoUrl'] as String? ?? '',
      'rating': (d['rating'] as num?)?.toDouble() ?? 0.0,
      'experience': '${d['experience'] ?? '–'} yrs',
      'fee': '₹${d['fee'] ?? '0'}',
      'available': isOnline,
      'wait': waitLabel,
      'icon': Icons.person_rounded,
      'color': _colorForSpecialty(specialty),
      'lastHeartbeat': lastHeartbeat, // Timestamp? — used for staleness check
    };
  }

  /// Returns true if the heartbeat timestamp is within the last 3 minutes,
  /// or if there's no heartbeat field yet (doctor just toggled online).
  bool _hasFreshHeartbeat(dynamic ts) {
    if (ts == null) return true;
    try {
      final heartbeat = (ts as dynamic).toDate() as DateTime;
      return DateTime.now().difference(heartbeat).inMinutes < 3;
    } catch (_) {
      return true; // parse failure → give benefit of the doubt
    }
  }

  /// Returns true if the given time slot has already passed today.
  bool _isScheduleSlotExpired(String slot) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = _dateTimes[_selectedDateIndex];
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
    } catch (_) {
      return false;
    }
  }

  /// Subscribes to booked appointments for the currently selected doctor + date.
  /// Re-called whenever doctor selection or date selection changes.
  void _subscribeBookedScheduleSlots() {
    _bookedScheduleSub?.cancel();
    final doc = _selectedDoctor;
    if (doc == null) return;
    _updateScheduleSlots();
    final dateKey = DateFormat('yyyy-MM-dd').format(_dateTimes[_selectedDateIndex]);
    _bookedScheduleSub = FirebaseFirestore.instance
        .collection('appointments')
        .where('doctorId', isEqualTo: doc['uid'])
        .where('date', isEqualTo: dateKey)
        .where('status', isEqualTo: 'booked')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _bookedScheduleTimes = snap.docs
            .map((d) => d.data()['time'] as String? ?? '')
            .where((t) => t.isNotEmpty)
            .toSet();
      });
    });
  }

  /// Fetches the selected doctor's availability from Firestore and refreshes slots.
  Future<void> _fetchDoctorAvailability(String doctorId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('doctors')
          .doc(doctorId)
          .get();
      final avail = snap.data()?['availability'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() => _selectedDoctorAvailability = avail);
      _updateScheduleSlots();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectedDoctorAvailability = null;
        _scheduleSlots = _kDefaultSlots.toList();
      });
    }
  }

  /// Regenerates _scheduleSlots for the currently selected date + doctor availability.
  void _updateScheduleSlots() {
    final slots = _slotsForDate(_dateTimes[_selectedDateIndex]);
    if (mounted) setState(() => _scheduleSlots = slots);
  }

  /// Generates time slots from the doctor's availability config for [date].
  List<String> _slotsForDate(DateTime date) {
    final avail = _selectedDoctorAvailability;
    if (avail == null) return _kDefaultSlots.toList();
    final slotDuration = (avail['slotDuration'] as num?)?.toInt() ?? 30;
    final schedule = avail['schedule'] as Map<String, dynamic>?;
    if (schedule == null) return _kDefaultSlots.toList();
    final dayName = DateFormat('EEE').format(date);
    final ds = schedule[dayName] as Map<String, dynamic>?;
    if (ds == null || ds['enabled'] != true) return [];
    final startStr = ds['start'] as String? ?? '09:00';
    final endStr = ds['end'] as String? ?? '18:00';
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
        slots.add(
            '${displayH.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')} $period');
      }
      return slots;
    } catch (_) {
      return _kDefaultSlots.toList();
    }
  }

  bool _isDoctorWorkingDay(DateTime date) {
    final avail = _selectedDoctorAvailability;
    if (avail == null) return true;
    final schedule = avail['schedule'] as Map<String, dynamic>?;
    if (schedule == null) return true;
    final dayName = DateFormat('EEE').format(date);
    final ds = schedule[dayName] as Map<String, dynamic>?;
    return ds?['enabled'] == true;
  }

  Color _colorForSpecialty(String specialty) {
    if (specialty.contains('Gynaecology') || specialty.contains('Obstetrics')) {
      return const Color(0xFFE91E8C);
    } else if (specialty.contains('Cardiology')) {
      return const Color(0xFFE53935);
    } else if (specialty.contains('Dermatology')) {
      return const Color(0xFF6A1B9A);
    } else if (specialty.contains('Paediatrics')) {
      return const Color(0xFF2E7D32);
    } else if (specialty.contains('Orthopaedics')) {
      return const Color(0xFF795548);
    } else if (specialty.contains('Neurology')) {
      return const Color(0xFF00695C);
    } else if (specialty.contains('Psychiatry')) {
      return const Color(0xFF37474F);
    }
    return const Color(0xFF1565C0);
  }

  @override
  void dispose() {
    _doctorSub?.cancel();
    _onlineDoctorSub?.cancel();
    _bookedScheduleSub?.cancel();
    _scheduleSlotTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: AppSpacing.headerHeight(context),
            pinned: true,
            forceElevated: innerBoxIsScrolled,
            backgroundColor: AppColors.primaryDark,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // The TabBar below is pinned on top of the last 48px of this
                      // FlexibleSpaceBar's area, so the centered title/subtitle must
                      // be constrained to the space above it — otherwise they sink
                      // down and get visually covered by the tab bar.
                      const tabBarHeight = 48.0;
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              minHeight: constraints.maxHeight - tabBarHeight),
                          child: Padding(
                            padding: AppSpacing.headerPaddingWithBottomWidget(context),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Consultation', style: AppTextStyles.onPrimaryH2),
                                SizedBox(height: R.h(context, 4)),
                                Text('Connect instantly or book in advance',
                                    style: AppTextStyles.onPrimaryBody),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: AppColors.primaryDark,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500),
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bolt_rounded, size: 16),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Quick Connect',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_month_rounded, size: 16),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Schedule',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildQuickConnect(),
            _buildSchedule(),
          ],
        ),
      ),
      bottomNavigationBar: _tabController.index == 1 && _selectedDoctor != null
          ? _buildBookButton()
          : null,
    );
  }

  // ── Quick Connect Tab ─────────────────────────────────────
  Widget _buildQuickConnect() {
    final hasOnline = !_quickConnectLoading && _onlineDoctors.isNotEmpty;
    return SingleChildScrollView(
      padding: AppSpacing.page(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Real-time available doctor count banner
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: hasOnline
                  ? const LinearGradient(
                      colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                    )
                  : LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.08),
                        AppColors.secondary.withValues(alpha: 0.05),
                      ],
                    ),
              borderRadius: BorderRadius.circular(16),
              border: hasOnline
                  ? null
                  : Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
              boxShadow: hasOnline
                  ? [BoxShadow(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: hasOnline
                        ? Colors.white.withValues(alpha: 0.2)
                        : AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    hasOnline ? Icons.circle : Icons.bolt_rounded,
                    color: hasOnline ? const Color(0xFF69F0AE) : AppColors.primary,
                    size: hasOnline ? 18 : 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _quickConnectLoading
                          ? Text(
                              'Checking availability...',
                              style: AppTextStyles.labelLarge.copyWith(
                                color: AppColors.primary,
                              ),
                            )
                          : Text(
                              hasOnline
                                  ? '${_onlineDoctors.length} Doctor${_onlineDoctors.length == 1 ? '' : 's'} Available Now'
                                  : 'No Doctors Online',
                              style: AppTextStyles.labelLarge.copyWith(
                                color: hasOnline ? Colors.white : AppColors.primary,
                              ),
                            ),
                      const SizedBox(height: 2),
                      Text(
                        hasOnline
                            ? 'Skip the wait — connect in seconds'
                            : 'Try scheduling an appointment instead',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: hasOnline
                              ? Colors.white.withValues(alpha: 0.8)
                              : context.appTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasOnline)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Available Now', style: AppTextStyles.h4),
          const SizedBox(height: 12),
          if (_quickConnectLoading) ...[
            AppShimmer(
              child: Column(
                children: List.generate(3, (_) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  height: 90,
                  decoration: BoxDecoration(
                    color: context.appSurface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                )),
              ),
            ),
          ] else if (_onlineDoctors.isEmpty) ...[
            const SizedBox(height: 8),
            AppEmptyState(
              icon: Icons.hourglass_empty_rounded,
              title: 'No doctors online right now',
              message: 'Ask a doctor to go online, or schedule an appointment instead.',
              iconColor: context.appTextSecondary,
              actionLabel: 'Schedule Appointment',
              onAction: () => _tabController.animateTo(1),
            ),
          ] else
            ..._onlineDoctors.map((doctor) => _QuickConnectCard(
                  doctor: doctor,
                  onConnect: () => _startQuickCall(context, doctor),
                )),
        ],
      ),
    );
  }

  void _startQuickCall(BuildContext context, Map<String, dynamic> doctor) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Fetch patient's stored FCM token from 'users' collection.
    String patientFcmToken = '';
    try {
      final patSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      patientFcmToken = patSnap.data()?['fcmToken'] as String? ?? '';
    } catch (_) {}

    final ref = FirebaseFirestore.instance.collection('consultations').doc();
    final now = FieldValue.serverTimestamp();
    try {
      final fee = (doctor['fee'] as String? ?? '')
          .replaceAll('₹', '')
          .trim();
      await ref.set({
        'channelName': ref.id,
        'status': 'pending',
        'callerType': 'patient',
        'patientId': user.uid,
        'patientName': user.displayName ?? user.email ?? 'Patient',
        'patientFcmToken': patientFcmToken,
        'doctorId': doctor['uid'] ?? '',
        'doctorName': doctor['name'],
        'doctorSpecialty': doctor['specialty'],
        'doctorPhotoUrl': doctor['photoUrl'] ?? '',
        'consultationType': 'Video',
        'fee': int.tryParse(fee) ?? 0,
        'chiefComplaint': '',
        'createdAt': now,
        'updatedAt': now,
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not connect: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    context.push(
      AppRoutes.outgoingCall,
      extra: {
        'consultationId': ref.id,
        'doctorName': doctor['name'] as String? ?? 'Doctor',
        'doctorSpecialty': doctor['specialty'] as String? ?? '',
        'doctorPhotoUrl': doctor['photoUrl'] as String? ?? '',
      },
    );
  }

  // ── Schedule Tab ──────────────────────────────────────────
  Widget _buildSchedule() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Consultation type selector
          Padding(
            padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 20), R.p(context, 20), 0),
            child: Row(
              children: ['Video', 'In-Person', 'Chat'].map((type) {
                final selected = _selectedType == type;
                return GestureDetector(
                  onTap: () => setState(() => _selectedType = type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: selected ? AppColors.primaryGradient : null,
                      color: selected ? null : context.appSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: selected ? null : Border.all(color: context.appBorder),
                      boxShadow: selected
                          ? [BoxShadow(color: AppColors.primary.withValues(alpha:0.3),
                              blurRadius: 8, offset: const Offset(0, 3))]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          type == 'Video' ? Icons.video_call_rounded
                              : type == 'In-Person' ? Icons.person_rounded
                              : Icons.chat_rounded,
                          size: 14,
                          color: selected ? Colors.white : context.appTextSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(type,
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : context.appTextSecondary,
                            )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // In-Person location note
          if (_selectedType == 'In-Person')
            Padding(
              padding: EdgeInsets.symmetric(horizontal: R.p(context, 20)),
              child: GestureDetector(
                onTap: () => context.push('/doctors?mode=inperson'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha:0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha:0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.location_on_rounded,
                        color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'In-Person visits are location-based. Tap to browse nearby doctors.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.orange, size: 18),
                  ]),
                ),
              ),
            ),

          // Search
          Padding(
            padding: AppSpacing.page(context),
            child: TextField(
              onChanged: (v) =>
                  setState(() => _scheduleSearch = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search doctor by name or specialty…',
                prefixIcon: Icon(Icons.search_rounded,
                    color: context.appTextHint),
                filled: true,
                fillColor: context.appSurface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          // Doctors List
          Padding(
            padding: AppSpacing.pageHorizontal(context),
            child: Text('Available Doctors', style: AppTextStyles.h4),
          ),
          SizedBox(height: AppSpacing.cardGap(context)),
          Builder(builder: (_) {
            // Filter doctors for Video vs In-Person type
            // For Video: show all doctors
            // For In-Person: show all doctors too but location note shown above
            var filtered = List<Map<String, dynamic>>.from(_allDoctors);

            if (_scheduleSearch.isNotEmpty) {
              filtered = filtered.where((d) {
                final name = (d['name'] as String? ?? '').toLowerCase();
                final spec =
                    (d['specialty'] as String? ?? '').toLowerCase();
                return name.contains(_scheduleSearch) ||
                    spec.contains(_scheduleSearch);
              }).toList();
            }

            if (filtered.isEmpty) {
              return Padding(
                padding: AppSpacing.page(context),
                child: Center(
                  child: Text('No doctors found.',
                      style: TextStyle(color: context.appTextSecondary)),
                ),
              );
            }
            return Column(
              children: filtered
                  .map((doctor) => _DoctorCard(
                        doctor: doctor,
                        isSelected:
                            _selectedDoctor?['uid'] == doctor['uid'],
                        onTap: () {
                          setState(() {
                            _selectedDoctor = doctor;
                            _selectedTimeIndex = -1;
                            _bookedScheduleTimes = {};
                            _selectedDoctorAvailability = null;
                            _scheduleSlots = _kDefaultSlots.toList();
                          });
                          _fetchDoctorAvailability(doctor['uid'] as String);
                          _subscribeBookedScheduleSlots();
                        },
                      ))
                  .toList(),
            );
          }),
          SizedBox(height: AppSpacing.sectionGap(context)),

          if (_selectedDoctor != null) ...[
            // Date picker
            Padding(
              padding: AppSpacing.pageHorizontal(context),
              child: Text('Select Date', style: AppTextStyles.h4),
            ),
            SizedBox(height: AppSpacing.cardGap(context)),
            SizedBox(
              height: R.h(context, 80),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: AppSpacing.pageHorizontal(context),
                itemCount: _dateTimes.length,
                itemBuilder: (_, i) {
                  final d = _dateTimes[i];
                  final selected = _selectedDateIndex == i;
                  final isToday = i == 0;
                  final isWorkingDay = _isDoctorWorkingDay(d);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedDateIndex = i;
                        _selectedTimeIndex = -1;
                        _bookedScheduleTimes = {};
                      });
                      _updateScheduleSlots();
                      _subscribeBookedScheduleSlots();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        gradient: selected ? AppColors.primaryGradient : null,
                        color: selected ? null : (isWorkingDay ? context.appSurface : const Color(0xFFF5F5F5)),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: selected
                            ? [BoxShadow(color: AppColors.primary.withValues(alpha:0.3),
                                blurRadius: 10, offset: const Offset(0, 4))]
                            : null,
                        border: selected ? null : Border.all(
                          color: isWorkingDay ? context.appBorder : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isToday ? 'Today' : DateFormat('EEE').format(d),
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 10,
                              color: selected
                                  ? Colors.white70
                                  : (isWorkingDay ? context.appTextSecondary : context.appTextHint),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('d').format(d),
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? Colors.white
                                  : (isWorkingDay ? context.appTextPrimary : context.appTextHint),
                            ),
                          ),
                          Text(
                            DateFormat('MMM').format(d),
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 9,
                              color: selected ? Colors.white60 : context.appTextHint,
                            ),
                          ),
                          if (!selected && !isWorkingDay)
                            Container(
                              width: 4, height: 4,
                              decoration: const BoxDecoration(
                                color: Color(0xFFBDBDBD),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: AppSpacing.sectionGap(context)),

            // Time picker
            Padding(
              padding: AppSpacing.pageHorizontal(context),
              child: Text('Select Time', style: AppTextStyles.h4),
            ),
            SizedBox(height: AppSpacing.cardGap(context)),
            if (_scheduleSlots.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: R.p(context, 20), vertical: R.p(context, 16)),
                child: Container(
                  padding: EdgeInsets.all(AppSpacing.cardPadding(context)),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha:0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.withValues(alpha:0.25)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.event_busy_rounded, color: Colors.orange, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Doctor is not available on this day.\nPlease select a different date.',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 13, color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
            Padding(
              padding: AppSpacing.pageHorizontal(context),
              child: staticGrid(
                crossAxisCount: 3,
                aspectRatio: 2.2,
                children: List.generate(_scheduleSlots.length, (i) {
                  final time = _scheduleSlots[i];
                  final isExpired = _isScheduleSlotExpired(time);
                  final isBooked = _bookedScheduleTimes.contains(time);
                  final isDisabled = isExpired || isBooked;
                  final selected = _selectedTimeIndex == i && !isDisabled;
                  Color bgColor;
                  Color textColor;
                  if (selected) {
                    bgColor = Colors.transparent;
                    textColor = Colors.white;
                  } else if (isBooked) {
                    bgColor = const Color(0xFFFFEBEE);
                    textColor = const Color(0xFFE57373);
                  } else if (isExpired) {
                    bgColor = const Color(0xFFF5F5F5);
                    textColor = context.appTextHint;
                  } else {
                    bgColor = context.appSurface;
                    textColor = context.appTextPrimary;
                  }
                  return GestureDetector(
                    onTap: isDisabled ? null : () => setState(() => _selectedTimeIndex = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        gradient: selected ? AppColors.primaryGradient : null,
                        color: selected ? null : bgColor,
                        borderRadius: BorderRadius.circular(10),
                        border: selected
                            ? null
                            : Border.all(
                                color: isBooked
                                    ? const Color(0xFFEF9A9A)
                                    : isExpired
                                        ? Colors.transparent
                                        : context.appBorder,
                              ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(time,
                                style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                )),
                            if (isBooked)
                              Text('Booked',
                                  style: TextStyle(
                                    fontFamily: 'Poppins', fontSize: 9,
                                    color: textColor.withValues(alpha:0.8),
                                  )),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            SizedBox(height: R.h(context, 24)),

            // Fee
            Padding(
              padding: AppSpacing.pageHorizontal(context),
              child: Container(
                padding: EdgeInsets.all(AppSpacing.cardPadding(context)),
                decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius(context)),
                  border: Border.all(color: context.appBorder),
                ),
                child: Column(
                  children: [
                    _FeeRow('Consultation Fee', _selectedDoctor!['fee']),
                    const Divider(height: 20),
                    _FeeRow('Platform Fee', '₹20'),
                    const Divider(height: 20),
                    _FeeRow(
                      'Total',
                      '₹${(int.tryParse(_selectedDoctor!['fee'].replaceAll('₹', '').trim()) ?? 0) + 20}',
                      isBold: true,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: R.h(context, 100)),
          ],
        ],
      ),
    );
  }

  Widget _buildBookButton() {
    return Container(
      padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 12), R.p(context, 20), R.p(context, 30)),
      decoration: BoxDecoration(
        color: context.appSurface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: (_selectedTimeIndex == -1 ||
                _scheduleSlots.isEmpty ||
                _selectedTimeIndex >= _scheduleSlots.length ||
                (_selectedTimeIndex >= 0 &&
                    (_isScheduleSlotExpired(_scheduleSlots[_selectedTimeIndex]) ||
                     _bookedScheduleTimes.contains(_scheduleSlots[_selectedTimeIndex]))))
            ? null
            : () => _confirmBooking(context),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _selectedType == 'Video' ? Icons.video_call_rounded : Icons.calendar_month_rounded,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text('Book $_selectedType Consultation'),
          ],
        ),
      ),
    );
  }

  void _confirmBooking(BuildContext context) {
    final selectedDate = _dateTimes[_selectedDateIndex];
    final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BookingConfirmSheet(
        doctor: _selectedDoctor!,
        date: dateKey,
        displayDate: DateFormat('EEE, d MMM yyyy').format(selectedDate),
        time: _scheduleSlots[_selectedTimeIndex],
        type: _selectedType,
      ),
    );
  }
}

// ── Quick Connect Doctor Card ─────────────────────────────
class _QuickConnectCard extends StatelessWidget {
  final Map<String, dynamic> doctor;
  final VoidCallback onConnect;

  const _QuickConnectCard({required this.doctor, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final doctorColor = doctor['color'] as Color;
    final name = doctor['name'] as String? ?? 'Doctor';
    final photoUrl = doctor['photoUrl'] as String? ?? '';
    // Build initials from name for avatar fallback
    final initials = name.trim().split(' ').take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          // Avatar with online dot
          Stack(
            children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: doctorColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: photoUrl.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              initials,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: doctorColor,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: doctorColor,
                          ),
                        ),
                      ),
              ),
              Positioned(
                bottom: 2, right: 2,
                child: Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                    border: Border.all(color: context.appSurface, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(doctor['specialty'] as String? ?? '',
                    style: AppTextStyles.bodySmall),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                    const SizedBox(width: 3),
                    Text('${doctor['rating']}', style: AppTextStyles.labelSmall),
                    const SizedBox(width: 10),
                    // Estimated wait time badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 10, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 3),
                          Text(
                            doctor['wait'] as String? ?? 'Ready',
                            style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 10,
                              fontWeight: FontWeight.w600, color: Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Prominent green "Connect Now" button
          GestureDetector(
            onTap: onConnect,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.video_call_rounded, color: Colors.white, size: 22),
                  SizedBox(height: 3),
                  Text('Connect Now',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 9,
                        fontWeight: FontWeight.w700, color: Colors.white,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Connecting Sheet ──────────────────────────────────────
class _ConnectingSheet extends StatefulWidget {
  final Map<String, dynamic> doctor;
  final VoidCallback onConnected;

  const _ConnectingSheet({required this.doctor, required this.onConnected});

  @override
  State<_ConnectingSheet> createState() => _ConnectingSheetState();
}

class _ConnectingSheetState extends State<_ConnectingSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _progress;
  int _step = 0;

  final _steps = [
    'Finding available doctor...',
    'Verifying credentials...',
    'Establishing secure connection...',
    'Connected!',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..forward();
    _progress = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.addListener(() {
      final s = (_ctrl.value * (_steps.length - 1)).floor().clamp(0, _steps.length - 1);
      if (s != _step && mounted) setState(() => _step = s);
    });
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 300), widget.onConnected);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: context.appBorder, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 28),
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha:0.35),
                  blurRadius: 24, spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.video_call_rounded, color: Colors.white, size: 42),
          ),
          const SizedBox(height: 20),
          Text('Connecting to ${widget.doctor['name']}',
              style: AppTextStyles.h3, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(widget.doctor['specialty'],
              style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _progress,
            builder: (_, __) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress.value,
                minHeight: 6,
                backgroundColor: context.appDivider,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _steps[_step],
              key: ValueKey(_step),
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Schedule: Doctor Card ─────────────────────────────────
class _DoctorCard extends StatelessWidget {
  final Map<String, dynamic> doctor;
  final bool isSelected;
  final VoidCallback onTap;

  const _DoctorCard({required this.doctor, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.primary : context.appBorder,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primary.withValues(alpha:0.15),
                  blurRadius: 16, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: (doctor['color'] as Color).withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(doctor['icon'] as IconData, size: 36, color: doctor['color'] as Color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(doctor['name'], style: AppTextStyles.labelLarge),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: doctor['available']
                              ? AppColors.accent.withValues(alpha:0.1)
                              : Colors.grey.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          doctor['available'] ? 'Available' : 'Offline',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600,
                            color: doctor['available'] ? AppColors.accent : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(doctor['specialty'], style: AppTextStyles.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                      const SizedBox(width: 3),
                      Text('${doctor['rating']}', style: AppTextStyles.labelSmall),
                      const SizedBox(width: 12),
                      Icon(Icons.work_outline_rounded, size: 14, color: context.appTextHint),
                      const SizedBox(width: 3),
                      Text(doctor['experience'], style: AppTextStyles.labelSmall),
                      const Spacer(),
                      Text(doctor['fee'],
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Fee Row ───────────────────────────────────────────────
class _FeeRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _FeeRow(this.label, this.value, {this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: isBold ? AppTextStyles.labelLarge : AppTextStyles.bodyMedium),
        Text(value,
            style: isBold
                ? AppTextStyles.labelLarge.copyWith(color: AppColors.primary)
                : AppTextStyles.labelLarge),
      ],
    );
  }
}

// ── Booking Confirm Sheet ─────────────────────────────────
class _BookingConfirmSheet extends StatefulWidget {
  final Map<String, dynamic> doctor;
  final String date;        // ISO format YYYY-MM-DD stored to Firestore
  final String displayDate; // Human-readable for UI
  final String time;
  final String type;

  const _BookingConfirmSheet({
    required this.doctor,
    required this.date,
    required this.displayDate,
    required this.time,
    required this.type,
  });

  @override
  State<_BookingConfirmSheet> createState() => _BookingConfirmSheetState();
}

class _BookingConfirmSheetState extends State<_BookingConfirmSheet> {
  bool _isLoading = false;
  final _chiefComplaintCtrl = TextEditingController();

  @override
  void dispose() {
    _chiefComplaintCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmAndPay() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      if (uid == null) throw Exception('Not authenticated');

      // Parse fee robustly — handles int and double values stored in Firestore
      final feeStr = widget.doctor['fee']?.toString().replaceAll('₹', '').trim() ?? '0';
      final consultFee = int.tryParse(feeStr) ?? (double.tryParse(feeStr)?.toInt() ?? 0);
      final totalFee = consultFee + 20;

      final db = FirebaseFirestore.instance;
      final apptRef = db.collection('appointments').doc();
      final payRef  = db.collection('payments').doc();
      final now = Timestamp.now();

      // Resolve patient name from Firestore (phone-auth users have no displayName)
      String patientName = user?.displayName ?? user?.phoneNumber ?? 'Patient';
      try {
        final userSnap = await db.collection('users').doc(uid).get();
        final fsName = (userSnap.data()?['name'] as String?)?.trim() ?? '';
        if (fsName.isNotEmpty) patientName = fsName;
      } catch (_) {}

      final batch = db.batch();
      batch.set(apptRef, {
        'doctorId': widget.doctor['uid'] ?? '',
        'doctorName': widget.doctor['name'],
        'doctorSpecialty': widget.doctor['specialty'],
        'patientId': uid,
        'patientName': patientName,
        'date': widget.date,
        'time': widget.time,
        'consultationType': widget.type,
        'fee': totalFee,
        'status': 'booked',
        'chiefComplaint': _chiefComplaintCtrl.text.trim(),
        'createdAt': now,
        'updatedAt': now,
      });
      batch.set(payRef, {
        'userId': uid,
        'doctorId': widget.doctor['uid'] ?? '',
        'appointmentId': apptRef.id,
        'amount': totalFee,
        'type': 'appointment',
        'status': 'paid',
        'createdAt': Timestamp.now(),
      });
      await batch.commit();

      if (!mounted) return;
      // Capture messenger and router BEFORE Navigator.pop() — after pop the
      // sheet's context is deactivated and ScaffoldMessenger.of() would throw,
      // which would be silently caught and shown as a booking failure.
      final messenger = ScaffoldMessenger.of(context);
      final router = GoRouter.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Appointment booked successfully!'),
            ],
          ),
          backgroundColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      router.go(AppRoutes.appointment);
    } catch (e) {
      debugPrint('Booking error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking failed. Please try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: context.appBorder, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 16),
          Text('Confirm Booking', style: AppTextStyles.h3),
          const SizedBox(height: 24),
          _ConfirmRow(Icons.person_rounded, 'Doctor', widget.doctor['name']),
          _ConfirmRow(Icons.medical_services_rounded, 'Specialty', widget.doctor['specialty']),
          _ConfirmRow(Icons.calendar_today_rounded, 'Date', widget.displayDate),
          _ConfirmRow(Icons.access_time_rounded, 'Time', widget.time),
          _ConfirmRow(Icons.video_call_rounded, 'Type', '${widget.type} Consultation'),
          _ConfirmRow(Icons.currency_rupee_rounded, 'Total',
              '₹${(int.tryParse(widget.doctor['fee'].replaceAll('₹', '').trim()) ?? 0) + 20}'),
          const SizedBox(height: 16),
          TextField(
            controller: _chiefComplaintCtrl,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Reason for visit (optional)',
              hintText: 'e.g. Fever for 2 days, headache...',
              prefixIcon: const Icon(Icons.notes_rounded),
              filled: true,
              fillColor: context.appBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _confirmAndPay,
              child: _isLoading
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Confirm & Pay'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ConfirmRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Text(label, style: AppTextStyles.bodyMedium),
          const Spacer(),
          Text(value, style: AppTextStyles.labelMedium.copyWith(color: context.appTextPrimary)),
        ],
      ),
    );
  }
}
