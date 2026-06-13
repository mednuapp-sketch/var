import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/app_permissions_service.dart';
import '../../../core/services/appointment_reminder_service.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/services/operation_logger.dart';
import '../../../core/services/presence_service.dart';
import '../../../core/utils/r.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../location/services/doctor_location_service.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../../core/widgets/ux_widgets.dart';

int _slotToMins(String t) {
  try {
    final p = t.trim().split(' ');
    final hm = p[0].split(':');
    int h = int.parse(hm[0]);
    final m = int.parse(hm[1]);
    if (p.length > 1 && p[1].toUpperCase() == 'PM' && h != 12) h += 12;
    if (p.length > 1 && p[1].toUpperCase() == 'AM' && h == 12) h = 0;
    return h * 60 + m;
  } catch (_) {
    return 0;
  }
}

int _apptSortKey(Map<String, dynamic> d) {
  final dateStr = d['date'] as String? ?? '';
  final timeStr = d['time'] as String? ?? '';
  try {
    final date = DateTime.parse(dateStr);
    return date.millisecondsSinceEpoch + _slotToMins(timeStr) * 60000;
  } catch (_) {
    return 0;
  }
}
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  bool _isOnline = false;
  bool _locationTogglingInProgress = false;

  @override
  void initState() {
    super.initState();
    _checkApprovalStatus();
    final uid = DoctorAuthService.currentUid;
    if (uid != null) PresenceService.instance.init(uid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppPermissionsService.checkAndPrompt(context);
    });
  }

  Future<void> _checkApprovalStatus() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;
    try {
      final profile = await DoctorAuthService.getProfile(uid);
      if (!mounted) return;
      final status = profile?['status'] as String?;
      if (status != 'active') {
        context.go(profile == null ? AppRoutes.register : AppRoutes.verificationPending);
      }
    } catch (e) {
      debugPrint('[Dashboard] Approval status check failed: $e');
    }
  }

  @override
  void dispose() {
    DoctorLocationService.stopTracking();
    // Force offline and tear down presence (heartbeat + lifecycle observer).
    PresenceService.instance.setOnline(false);
    PresenceService.instance.dispose();
    super.dispose();
  }

  void _handleLocationDisabled() {
    if (!_isOnline || !mounted) return;
    _setOfflineImmediate();
    OperationLogger.log(
      action: DoctorOpAction.wentOffline,
      status: OpStatus.error,
      message: 'Auto-offline: GPS disabled by system',
    );
    FeedbackService.show(
      context,
      'Location turned off — you\'ve been set OFFLINE.',
      type: FeedbackType.error,
      duration: const Duration(seconds: 8),
      actionLabel: 'Enable GPS',
      onAction: DoctorLocationService.openLocationSettings,
      dismissible: false,
    );
  }

  Future<void> _setOfflineImmediate() async {
    setState(() => _isOnline = false);
    await DoctorLocationService.stopTracking();
    await PresenceService.instance.setOnline(false);
  }

  Future<void> _toggleOnline(bool value) async {
    if (_locationTogglingInProgress) return;

    if (value) {
      setState(() => _locationTogglingInProgress = true);
      FeedbackService.showLoading(context, 'Going online...');

      final serviceEnabled = await DoctorLocationService.isServiceEnabled();
      if (!serviceEnabled) {
        FeedbackService.dismiss(context);
        setState(() => _locationTogglingInProgress = false);
        _showLocationServiceDialog();
        return;
      }

      final hasPermission = await DoctorLocationService.checkAndRequestPermission();
      if (!hasPermission) {
        FeedbackService.dismiss(context);
        setState(() => _locationTogglingInProgress = false);
        _showLocationPermissionDialog();
        return;
      }

      setState(() {
        _isOnline = true;
        _locationTogglingInProgress = false;
      });

      try {
        final uid = DoctorAuthService.currentUid;
        if (uid != null) {
          await PresenceService.instance.setOnline(true);
          await DoctorLocationService.startTracking(
            uid: uid,
            onLocationDisabled: _handleLocationDisabled,
          );
          // Push an immediate fix so the doctor appears on patient maps right away
          DoctorLocationService.pushCurrentPosition(uid);
          await OperationLogger.logSuccess(
            action: DoctorOpAction.wentOnline,
            message: 'Doctor is now online and visible to patients',
          );
        }
        if (mounted) {
          FeedbackService.dismiss(context);
          FeedbackService.showSuccess(context, 'You are now ONLINE — patients can find you');
        }
      } catch (e) {
        await OperationLogger.logError(
          action: DoctorOpAction.wentOnline,
          errorDetails: e.toString(),
        );
        if (mounted) {
          FeedbackService.showError(context, 'Failed to go online. Check your connection.');
        }
      }
    } else {
      FeedbackService.showLoading(context, 'Going offline...');
      await _setOfflineImmediate();
      await OperationLogger.logSuccess(
        action: DoctorOpAction.wentOffline,
        message: 'Doctor went offline',
      );
      if (mounted) {
        FeedbackService.dismiss(context);
        FeedbackService.showInfo(context, 'You are now OFFLINE — no new patients will find you');
      }
    }
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.error.withValues(alpha:0.1), shape: BoxShape.circle),
            child: const Icon(Icons.location_off_rounded, color: AppColors.error, size: 24),
          ),
          const SizedBox(width: 12),
          const Text('Location Required', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        content: const Text(
          'Your GPS must be ON to go online. Patients nearby will find you based on your real-time location.\n\nPlease enable Location/GPS from settings.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textHint))),
          ElevatedButton.icon(
            icon: const Icon(Icons.my_location_rounded, size: 16),
            label: const Text('Enable GPS'),
            onPressed: () { Navigator.pop(ctx); DoctorLocationService.openLocationSettings(); },
          ),
        ],
      ),
    );
  }

  void _showLocationPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha:0.1), shape: BoxShape.circle),
            child: const Icon(Icons.location_searching_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          const Text('Allow Location', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        content: const Text(
          'MedNU Doctor needs location permission to show you to patients within 7–10 km.\n\nPlease allow "While using the app" in app settings.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textHint))),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings_rounded, size: 16),
            label: const Text('Open Settings'),
            onPressed: () { Navigator.pop(ctx); DoctorLocationService.openAppSettings(); },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _HomeTab(
            isOnline: _isOnline,
            onToggle: _toggleOnline,
            toggling: _locationTogglingInProgress,
          ),
          _AppointmentsTab(),
          _EarningsTab(),
          const _ProfileTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 20, offset: Offset(0, -4))],
    ),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(Icons.dashboard_rounded, 'Home', 0, _currentIndex, (i) => setState(() => _currentIndex = i)),
            _NavItem(Icons.calendar_month_rounded, 'Appointments', 1, _currentIndex, (i) => setState(() => _currentIndex = i)),
            _NavItem(Icons.account_balance_wallet_rounded, 'Earnings', 2, _currentIndex, (i) => setState(() => _currentIndex = i)),
            _NavItem(Icons.person_rounded, 'Profile', 3, _currentIndex, (i) => setState(() => _currentIndex = i)),
          ],
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index, currentIndex;
  final ValueChanged<int> onTap;
  const _NavItem(this.icon, this.label, this.index, this.currentIndex, this.onTap);

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;
    return GestureDetector(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withValues(alpha:0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 24, color: isActive ? AppColors.primary : AppColors.textHint),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: isActive ? AppColors.primary : AppColors.textHint,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ]),
      ),
    );
  }
}

// ── HOME TAB ─────────────────────────────────────────────
class _HomeTab extends ConsumerStatefulWidget {
  final bool isOnline;
  final bool toggling;
  final Future<void> Function(bool) onToggle;

  const _HomeTab({
    required this.isOnline,
    required this.onToggle,
    this.toggling = false,
  });

  @override
  ConsumerState<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<_HomeTab> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _upcomingStream;

  @override
  void initState() {
    super.initState();
    final uid = DoctorAuthService.currentUid ?? '';
    _upcomingStream = FirebaseFirestore.instance
        .collection('appointments')
        .where('doctorId', isEqualTo: uid)
        .where('status', isEqualTo: 'booked')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final uid = DoctorAuthService.currentUid;
    final unreadCount = ref.watch(unreadCountProvider);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: uid == null
              ? const SizedBox()
              : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: DoctorAuthService.profileStream(uid),
                  builder: (context, snap) {
                    final data = snap.data?.data();
                    final name = data?['name'] as String? ?? 'Doctor';
                    final specialty = data?['specialty'] as String? ?? 'General Physician';
                    final photoUrl = data?['photoUrl'] as String?;
                    return Row(children: [
                      _DoctorAvatar(photoUrl: photoUrl, size: 40, iconSize: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: AppTextStyles.labelLarge),
                          Text('$specialty • MCI Verified ✓',
                              style: AppTextStyles.caption.copyWith(color: AppColors.success),
                              overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                      Stack(children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_outlined, color: AppColors.textPrimary),
                          onPressed: () => context.push(AppRoutes.notifications),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: 8, top: 8,
                            child: Container(
                              width: 16, height: 16,
                              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                              child: Center(
                                child: Text(
                                  unreadCount > 9 ? '9+' : '$unreadCount',
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ]);
                  },
                ),
        ),
        SliverToBoxAdapter(
          child: Column(
            children: [
              // Online/Offline toggle
              Container(
                margin: EdgeInsets.all(R.p(context, 16)),
                padding: EdgeInsets.all(R.p(context, 18)),
                decoration: BoxDecoration(
                  gradient: widget.isOnline
                      ? AppColors.onlineGradient
                      : const LinearGradient(colors: [Color(0xFF455A64), Color(0xFF607D8B)]),
                  borderRadius: BorderRadius.circular(R.r(context, 24)),
                  boxShadow: [BoxShadow(
                    color: (widget.isOnline ? AppColors.online : AppColors.offline).withValues(alpha:0.4),
                    blurRadius: 16, offset: const Offset(0, 6),
                  )],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          widget.isOnline ? 'You are ONLINE' : 'You are OFFLINE',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 17), fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        Text(
                          widget.isOnline ? 'Accepting new consultations' : 'Not accepting consultations',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 11), color: Colors.white70),
                        ),
                        SizedBox(height: R.h(context, 8)),
                        if (widget.isOnline) ...[
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: R.p(context, 10), vertical: R.p(context, 4)),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.2), borderRadius: BorderRadius.circular(R.r(context, 10))),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(width: R.w(context, 6), height: R.w(context, 6), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                              SizedBox(width: R.p(context, 6)),
                              Flexible(child: Text('Waiting for requests...', style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 11), color: Colors.white))),
                            ]),
                          ),
                          SizedBox(height: R.h(context, 6)),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: R.p(context, 10), vertical: R.p(context, 4)),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.15), borderRadius: BorderRadius.circular(R.r(context, 10))),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.my_location_rounded, size: R.w(context, 12), color: Colors.white),
                              SizedBox(width: R.p(context, 5)),
                              Flexible(child: Text('GPS Active • Visible within 10 km', style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 10), color: Colors.white))),
                            ]),
                          ),
                        ],
                      ]),
                    ),
                    SizedBox(width: R.p(context, 12)),
                    widget.toggling
                        ? SizedBox(
                            width: R.w(context, 36), height: R.w(context, 36),
                            child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                          )
                        : GestureDetector(
                            onTap: () => widget.onToggle(!widget.isOnline),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: R.w(context, 72), height: R.h(context, 36),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha:0.2),
                                borderRadius: BorderRadius.circular(R.r(context, 20)),
                                border: Border.all(color: Colors.white.withValues(alpha:0.4), width: 2),
                              ),
                              child: Stack(alignment: Alignment.center, children: [
                                AnimatedAlign(
                                  duration: const Duration(milliseconds: 300),
                                  alignment: widget.isOnline ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.all(3),
                                    width: R.w(context, 28), height: R.w(context, 28),
                                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                  ],
                ),
              ),

              // Real-time stats
              _RealStatsRow(uid: uid),
              const SizedBox(height: 20),

              // Incoming consultation requests
              if (widget.isOnline)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('consultations')
                      .where('status', isEqualTo: 'pending')
                      .where('doctorId', isEqualTo: DoctorAuthService.currentUid ?? '')
                      .snapshots(),
                  builder: (context, snap) {
                    final count = snap.data?.docs.length ?? 0;
                    if (count == 0) return const SizedBox();
                    return GestureDetector(
                      onTap: () => context.push(AppRoutes.incomingRequest),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.primary.withValues(alpha:0.3), width: 2),
                          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha:0.1), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: Row(children: [
                          Container(
                            width: 50, height: 50,
                            decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                            child: const Icon(Icons.ring_volume_rounded, color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('$count Consultation Request${count > 1 ? 's' : ''}!',
                                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.primary)),
                            Text('Tap to view and accept', style: AppTextStyles.bodySmall),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: const BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.all(Radius.circular(10))),
                            child: const Text('View', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 20),

              // Upcoming appointments
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Upcoming Appointments', style: AppTextStyles.h4),
              ),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _upcomingStream,
                builder: (context, snap) {
                  final allDocs = snap.data?.docs ?? [];
                  final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                  final sorted = [...allDocs]
                    .where((d) => (d.data()['date'] as String? ?? '').compareTo(todayStr) >= 0)
                    .toList()
                    ..sort((a, b) {
                      final dc = (a.data()['date'] as String? ?? '').compareTo(b.data()['date'] as String? ?? '');
                      if (dc != 0) return dc;
                      return (a.data()['time'] as String? ?? '').compareTo(b.data()['time'] as String? ?? '');
                    });
                  final limited = sorted.take(5).toList();

                  if (limited.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
                        child: Column(children: [
                          const Icon(Icons.calendar_today_outlined, size: 36, color: AppColors.textHint),
                          const SizedBox(height: 8),
                          Text('No upcoming appointments', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
                        ]),
                      ),
                    );
                  }
                  return Column(
                    children: limited.map((doc) {
                      final d = doc.data();
                      final patientName = d['patientName'] as String? ?? 'Patient';
                      final patientId = d['patientId'] as String? ?? '';
                      final time = d['time'] as String? ?? '';
                      final type = d['consultationType'] as String? ?? 'Video';
                      final dateStr = d['date'] as String? ?? '';
                      String displayDate = dateStr;
                      try {
                        final dt = DateTime.parse(dateStr);
                        final today = DateTime.now();
                        if (dt.year == today.year && dt.month == today.month && dt.day == today.day) {
                          displayDate = 'Today';
                        } else {
                          displayDate = DateFormat('d MMM').format(dt);
                        }
                      } catch (_) {}
                      return GestureDetector(
                        onTap: () => context.push(
                          AppRoutes.patientDetail,
                          extra: {'patientId': patientId, 'patientName': patientName},
                        ),
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
                          child: Row(children: [
                            Container(
                              width: 46, height: 46,
                              decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                              child: Center(child: Text(
                                patientName.isNotEmpty ? patientName[0].toUpperCase() : '?',
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                              )),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(patientName, style: AppTextStyles.labelLarge),
                              Text('$displayDate • $time', style: AppTextStyles.bodySmall),
                            ])),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(type, style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                            ),
                          ]),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              // Maternity care quick-access card
              _MaternityCareCard(uid: DoctorAuthService.currentUid ?? ''),
              const SizedBox(height: 12),
              // Feedback quick-access card
              _FeedbackSummaryCard(uid: DoctorAuthService.currentUid),
              const SizedBox(height: 12),
              // Reviews quick-access card
              _ReviewsSummaryCard(uid: DoctorAuthService.currentUid),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ],
    );
  }
}

// ── MATERNITY CARE CARD ──────────────────────────────────────────────────────
class _MaternityCareCard extends StatelessWidget {
  final String uid;
  const _MaternityCareCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: uid.isEmpty
          ? const Stream.empty()
          : FirebaseFirestore.instance
              .collection('pregnancy_profiles')
              .where('assignedDoctorId', isEqualTo: uid)
              .where('isActive', isEqualTo: true)
              .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        final highRisk = snap.data?.docs
                .where((d) => (d.data() as Map<String, dynamic>)['isHighRisk'] == true)
                .length ??
            0;

        return GestureDetector(
          onTap: () => context.push(AppRoutes.pregnancyPatients),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFAD1457), Color(0xFF6A1B9A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: const Color(0xFFC2185B).withValues(alpha:0.3), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.2), shape: BoxShape.circle),
                child: const Icon(Icons.pregnant_woman_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Maternity Patients',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14)),
                Text(
                  '$count patients${highRisk > 0 ? ' • $highRisk high-risk' : ''}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                ),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.2), borderRadius: BorderRadius.circular(10)),
                child: const Text('View', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ── FEEDBACK SUMMARY CARD ────────────────────────────────────────────────────
class _FeedbackSummaryCard extends StatelessWidget {
  final String? uid;
  const _FeedbackSummaryCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('feedbacks')
          .where('doctorId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final allRatings = docs
            .map((d) => (d.data()['rating'] as int?) ?? 0)
            .where((r) => r > 0)
            .toList();
        final avg = allRatings.isEmpty
            ? null
            : allRatings.reduce((a, b) => a + b) / allRatings.length;

        return GestureDetector(
          onTap: () => context.push(AppRoutes.feedback),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.reviews_rounded, color: Color(0xFFFFA000), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Patient Feedback', style: AppTextStyles.labelLarge),
                    if (avg != null)
                      Text(
                        'Avg rating: ${avg.toStringAsFixed(1)} ⭐  •  ${docs.length} recent',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      )
                    else
                      Text('No feedback yet', style: AppTextStyles.caption.copyWith(color: AppColors.textHint)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
              ]),
              if (docs.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                ...docs.map((d) {
                  final data = d.data();
                  final name    = data['patientName'] as String? ?? 'Patient';
                  final rating  = data['rating']      as int?    ?? 0;
                  final feeling = data['feeling']      as String? ?? '';
                  final comment = data['comment']      as String? ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      if (rating > 0) ...[
                        ...List.generate(rating, (_) => const Icon(Icons.star_rounded, color: Color(0xFFFFA000), size: 12)),
                        ...List.generate(5 - rating, (_) => const Icon(Icons.star_outline_rounded, color: AppColors.textHint, size: 12)),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          comment.isNotEmpty ? '"$comment"' : feeling,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        name,
                        style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ]),
                  );
                }),
              ],
            ]),
          ),
        );
      },
    );
  }
}

// ── REVIEWS SUMMARY CARD ─────────────────────────────────────────────────────
class _ReviewsSummaryCard extends StatelessWidget {
  final String? uid;
  const _ReviewsSummaryCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid == null) return const SizedBox();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('doctor_rating_summary')
          .doc(uid)
          .snapshots(),
      builder: (context, summarySnap) {
        final sData = summarySnap.data?.data();
        final avg = (sData?['averageRating'] as num?)?.toDouble();
        final total = (sData?['totalReviews'] as num?)?.toInt() ?? 0;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('doctor_reviews')
              .where('doctorId', isEqualTo: uid)
              .where('isFlagged', isEqualTo: false)
              .orderBy('createdAt', descending: true)
              .limit(2)
              .snapshots(),
          builder: (context, reviewsSnap) {
            final recent = reviewsSnap.data?.docs ?? [];

            return GestureDetector(
              onTap: () => context.push(AppRoutes.reviews),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha:0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.star_rounded,
                          color: Colors.amber, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Patient Reviews',
                            style: AppTextStyles.labelLarge),
                        avg != null && total > 0
                            ? Text(
                                '${avg.toStringAsFixed(1)} ⭐  •  $total verified review${total != 1 ? 's' : ''}',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.textSecondary),
                              )
                            : Text('No reviews yet',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.textHint)),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.verified_rounded,
                            size: 10, color: AppColors.accent),
                        const SizedBox(width: 3),
                        Text('Verified',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.accent)),
                      ]),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textHint),
                  ]),
                  if (recent.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    ...recent.map((doc) {
                      final d = doc.data();
                      final name =
                          d['patientName'] as String? ?? 'Patient';
                      final rating =
                          (d['rating'] as num?)?.toDouble() ?? 0;
                      final text =
                          d['reviewText'] as String? ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                  5,
                                  (i) => Icon(
                                        i < rating
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                        size: 11,
                                        color: Colors.amber,
                                      ))),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(name,
                                  style: AppTextStyles.caption.copyWith(
                                      fontWeight: FontWeight.w600)),
                              if (text.isNotEmpty)
                                Text(text,
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textSecondary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                        ]),
                      );
                    }),
                  ],
                ]),
              ),
            );
          },
        );
      },
    );
  }
}

// Real-time stats row: queries today's completed appointments for earnings
class _RealStatsRow extends StatelessWidget {
  final String? uid;
  const _RealStatsRow({required this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid == null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: R.p(context, 16)),
        child: Row(children: [
          _StatCard('Today\'s Earnings', '₹0', Icons.currency_rupee_rounded, const Color(0xFF1565C0)),
          SizedBox(width: R.p(context, 10)),
          _StatCard('Consultations', '0', Icons.video_call_rounded, AppColors.secondary),
          SizedBox(width: R.p(context, 10)),
          _StatCard('Rating', '–', Icons.star_rounded, const Color(0xFFF57F17)),
        ]),
      );
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('doctorId', isEqualTo: uid)
          .where('date', isEqualTo: today)
          .where('status', isEqualTo: 'completed')
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final totalEarnings = docs.fold<num>(0, (sum, d) => sum + ((d.data()['fee'] as num?) ?? 0));
        final consultations = docs.length;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('doctor_rating_summary')
              .doc(uid)
              .snapshots(),
          builder: (context, ratingSnap) {
            final rData = ratingSnap.data?.data();
            final avg = (rData?['averageRating'] as num?)?.toDouble();
            final total = (rData?['totalReviews'] as num?)?.toInt() ?? 0;
            final ratingLabel = avg != null && total > 0
                ? '${avg.toStringAsFixed(1)} ⭐'
                : '–';
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: R.p(context, 16)),
              child: Row(children: [
                _StatCard('Today\'s Earnings', '₹$totalEarnings', Icons.currency_rupee_rounded, const Color(0xFF1565C0)),
                SizedBox(width: R.p(context, 10)),
                _StatCard('Consultations', '$consultations', Icons.video_call_rounded, AppColors.secondary),
                SizedBox(width: R.p(context, 10)),
                GestureDetector(
                  onTap: () => context.push(AppRoutes.reviews),
                  child: _StatCard(
                    total > 0 ? '$total Reviews' : 'Rating',
                    ratingLabel,
                    Icons.star_rounded,
                    const Color(0xFFF57F17),
                  ),
                ),
              ]),
            );
          },
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: EdgeInsets.all(R.p(context, 12)),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(R.r(context, 16)), border: Border.all(color: AppColors.divider)),
      child: Column(children: [
        Icon(icon, color: color, size: R.w(context, 22)),
        SizedBox(height: R.h(context, 5)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: TextStyle(fontFamily: 'Poppins', fontSize: R.sp(context, 15), fontWeight: FontWeight.w800, color: color)),
        ),
        Text(label, textAlign: TextAlign.center, style: AppTextStyles.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    ),
  );
}

/// Parses date + time-slot strings into a [DateTime].
DateTime? _parseApptSlot(String dateStr, String timeStr) {
  try {
    final date  = DateTime.parse(dateStr);
    final parts = timeStr.trim().split(' ');
    final hm    = parts[0].split(':');
    int h       = int.parse(hm[0]);
    final m     = int.parse(hm[1]);
    if (parts.length > 1 && parts[1].toUpperCase() == 'PM' && h != 12) h += 12;
    if (parts.length > 1 && parts[1].toUpperCase() == 'AM' && h == 12) h = 0;
    return DateTime(date.year, date.month, date.day, h, m);
  } catch (_) {
    return null;
  }
}

// Returns true when an appointment starts within [thresholdMinutes].
bool _isStartingSoon(String dateStr, String timeStr, {int thresholdMinutes = 5}) {
  final slot = _parseApptSlot(dateStr, timeStr);
  if (slot == null) return false;
  final diff = slot.difference(DateTime.now()).inMinutes;
  return diff >= 0 && diff <= thresholdMinutes;
}

// ── DASHBOARD SKELETON ────────────────────────────────────
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner skeleton
          AppShimmer(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              height: 110,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E8E8),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Stats row skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: List.generate(3, (i) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 2 ? 10 : 0),
                  child: const SkeletonBox(width: double.infinity, height: 78, radius: 16),
                ),
              )),
            ),
          ),
          const SizedBox(height: 20),
          // Tab bar skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SkeletonBox(width: double.infinity, height: 44, radius: 14),
          ),
          const SizedBox(height: 16),
          // Appointment card skeletons
          ...List.generate(4, (i) => const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SkeletonCard(height: 92),
          )),
        ],
      ),
    );
  }
}

// ── APPOINTMENTS TAB ──────────────────────────────────────
class _AppointmentsTab extends StatefulWidget {
  @override
  State<_AppointmentsTab> createState() => _AppointmentsTabState();
}

class _AppointmentsTabState extends State<_AppointmentsTab> with SingleTickerProviderStateMixin {
  late TabController _tab;
  Timer? _refreshTimer;
  // Tracks appointments for which the auto-connect dialog has already been shown.
  final Set<String> _autoAlertedIds = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    // Force a rebuild every 30 s so the "JOIN NOW" badge and auto-connect check
    // stay current even without a new Firestore event.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _resolveDisplayDate(String dateStr) {
    DateTime? parsed;
    try {
      parsed = DateTime.parse(dateStr);
    } catch (_) {
      for (final fmt in ['EEE, d MMM yyyy', 'd MMM yyyy', 'MMM d, yyyy', 'd MMM']) {
        try { parsed = DateFormat(fmt).parse(dateStr); break; } catch (_) {}
      }
    }
    if (parsed == null) return dateStr;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(parsed.year, parsed.month, parsed.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (d == today.add(const Duration(days: 1))) return 'Tomorrow';
    return DateFormat('EEE, d MMM').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final uid = authSnap.data?.uid ?? DoctorAuthService.currentUid;
        if (uid == null) {
          if (authSnap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: AppColors.background,
              body: _DashboardSkeleton(),
            );
          }
          return const Scaffold(body: Center(child: Text('Please log in')));
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          key: ValueKey(uid),
          stream: FirebaseFirestore.instance
              .collection('appointments')
              .where('doctorId', isEqualTo: uid)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: AppColors.background,
                body: _DashboardSkeleton(),
              );
            }
            if (snap.hasError) {
              return Scaffold(
                backgroundColor: AppColors.background,
                body: AppErrorState(message: 'Failed to load appointments'),
              );
            }
            final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(snap.data?.docs ?? []);
            final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
            // Upcoming: future/today booked appointments, closest first
            final upcoming = docs
                .where((d) => d['status'] == 'booked' &&
                    (d.data()['date'] as String? ?? '').compareTo(todayKey) >= 0)
                .toList()
              ..sort((a, b) => _apptSortKey(a.data()).compareTo(_apptSortKey(b.data())));

            // Check if any appointment just hit T=0 and auto-connect if so.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _checkAutoConnect(upcoming);
            });

            // Schedule local reminders for all upcoming appointments.
            // Idempotent: scheduling the same notification ID again just updates it.
            for (final appt in upcoming) {
              final d = appt.data();
              AppointmentReminderService.scheduleReminders(
                appointmentId: appt.id,
                patientName:   d['patientName'] as String? ?? 'Patient',
                dateStr:       d['date']        as String? ?? '',
                timeStr:       d['time']        as String? ?? '',
              );
            }

            // Completed & cancelled: most recent first (date+time DESC)
            final completed = docs
                .where((d) => d['status'] == 'completed')
                .toList()
              ..sort((a, b) => _apptSortKey(b.data()).compareTo(_apptSortKey(a.data())));
            final cancelled = docs
                .where((d) => d['status'] == 'cancelled')
                .toList()
              ..sort((a, b) => _apptSortKey(b.data()).compareTo(_apptSortKey(a.data())));

            return Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: Colors.white,
                elevation: 0,
                title: const Text(
                  'Appointments',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(52),
                  child: Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tab,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.textHint,
                      indicatorColor: AppColors.primary,
                      indicatorWeight: 3,
                      labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700),
                      unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500),
                      tabs: [
                        Tab(text: 'Upcoming (${upcoming.length})'),
                        Tab(text: 'Done (${completed.length})'),
                        const Tab(text: 'Cancelled'),
                      ],
                    ),
                  ),
                ),
              ),
              body: TabBarView(
                controller: _tab,
                children: [
                  _buildList(context, upcoming, 'booked'),
                  _buildList(context, completed, 'completed'),
                  _buildList(context, cancelled, 'cancelled'),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildList(BuildContext context, List<QueryDocumentSnapshot<Map<String, dynamic>>> appointments, String status) {
    if (appointments.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha:0.08), shape: BoxShape.circle),
            child: const Icon(Icons.calendar_month_rounded, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            status == 'booked' ? 'No upcoming appointments' :
            status == 'completed' ? 'No completed appointments' : 'No cancelled appointments',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your appointments will appear here',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textHint),
          ),
        ]),
      );
    }

    final isUpcoming  = status == 'booked';
    final isCompleted = status == 'completed';

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: appointments.length,
      itemBuilder: (_, i) {
        final data   = appointments[i].data();
        final docId  = appointments[i].id;

        final rawName   = data['patientName'] as String?;
        final patientName = (rawName != null && rawName.trim().isNotEmpty) ? rawName.trim() : 'Patient';
        final patientId   = data['patientId'] as String? ?? '';
        final time        = data['time'] as String? ?? '';
        final type        = data['consultationType'] as String? ?? 'Video';
        final feeVal      = data['fee'];
        final feeText     = feeVal != null ? '₹$feeVal' : null;
        final dateStr     = data['date'] as String? ?? '';
        final displayDate = _resolveDisplayDate(dateStr);
        final initial     = patientName[0].toUpperCase();

        final startingSoon = isUpcoming && _isStartingSoon(dateStr, time);
        final statusColor = isUpcoming
            ? (startingSoon ? AppColors.success : AppColors.primary)
            : isCompleted ? AppColors.success : AppColors.error;
        final statusLabel = isUpcoming
            ? (startingSoon ? 'JOIN NOW' : 'UPCOMING')
            : isCompleted ? 'COMPLETED' : 'CANCELLED';

        final typeIcon = type == 'Video'
            ? Icons.videocam_rounded
            : type == 'Chat'
                ? Icons.chat_bubble_rounded
                : Icons.person_rounded;

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Header row ───────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 52, height: 52,
                  decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                  child: Center(child: Text(
                    initial,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                  )),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      patientName,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(children: [
                      const Icon(Icons.access_time_rounded, size: 13, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Text(
                        '$displayDate  ·  $time',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha:0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(typeIcon, size: 12, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(type, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                        ]),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: statusColor, letterSpacing: 0.4),
                    ),
                  ),
                  if (feeText != null) ...[
                    const SizedBox(height: 6),
                    Text(feeText, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.success)),
                  ],
                ]),
              ]),
            ),

            // ── Divider ──────────────────────────────────
            if (isUpcoming || isCompleted)
              Divider(height: 1, thickness: 1, color: AppColors.divider),

            // ── Action buttons for upcoming ───────────────
            if (isUpcoming)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close_rounded, size: 15),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error.withValues(alpha:0.45)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => _cancelAppointment(docId),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha:0.3), blurRadius: 8, offset: const Offset(0, 3))],
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.videocam_rounded, size: 18),
                        label: const Text('Start Call'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        onPressed: () => _startCallForAppointment(context, docId, data),
                      ),
                    ),
                  ),
                ]),
              ),

            // ── Action buttons for completed ──────────────
            if (isCompleted)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.receipt_long_rounded, size: 15),
                      label: const Text('Prescription'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary.withValues(alpha:0.45)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => context.push(AppRoutes.prescription, extra: {
                        'patientId': patientId,
                        'patientName': patientName,
                        'appointmentId': docId,
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.person_rounded, size: 15),
                        label: const Text('Patient'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        onPressed: () => context.push(AppRoutes.patientDetail, extra: {
                          'patientId': patientId,
                          'patientName': patientName,
                        }),
                      ),
                    ),
                  ),
                ]),
              ),

            // ── Bottom padding for cancelled cards ────────
            if (!isUpcoming && !isCompleted)
              const SizedBox(height: 16),
          ]),
        );
      },
    );
  }

  void _checkAutoConnect(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> upcoming) {
    if (!mounted) return;
    final now = DateTime.now();
    for (final appt in upcoming) {
      if (_autoAlertedIds.contains(appt.id)) continue;
      final d    = appt.data();
      final slot = _parseApptSlot(d['date'] ?? '', d['time'] ?? '');
      if (slot == null) continue;
      final diffSeconds = slot.difference(now).inSeconds;
      // Window: up to 30 s before start time through 5 min after.
      if (diffSeconds >= -30 && diffSeconds <= 300) {
        _autoAlertedIds.add(appt.id);
        _showAutoConnectDialog(appt.id, d);
        return; // handle one at a time
      }
    }
  }

  void _showAutoConnectDialog(String apptId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AutoConnectDialog(
        patientName:     data['patientName'] as String? ?? 'Patient',
        appointmentTime: data['time']        as String? ?? '',
        onJoin: () => _startCallForAppointment(context, apptId, data),
      ),
    );
  }

  Future<void> _startCallForAppointment(
    BuildContext ctx,
    String appointmentId,
    Map<String, dynamic> data,
  ) async {
    // Re-use an existing consultation linked to this appointment if one exists.
    String? consultationId = data['consultationId'] as String?;

    if (consultationId == null || consultationId.isEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      FeedbackService.showLoading(ctx, 'Starting call…');
      try {
        final db          = FirebaseFirestore.instance;
        final patientId   = data['patientId']   as String? ?? '';
        final patientName = data['patientName'] as String? ?? 'Patient';
        final doctorName  = data['doctorName']  as String? ?? '';

        final consultRef = db.collection('consultations').doc();
        final now        = FieldValue.serverTimestamp();

        // Write consultation doc + patient notification atomically.
        final batch = db.batch();

        batch.set(consultRef, {
          'appointmentId':   appointmentId,
          'doctorId':        uid,
          'patientId':       patientId,
          'patientName':     patientName,
          'doctorName':      doctorName,
          'consultationType': data['consultationType'] ?? 'Video',
          'chiefComplaint':  data['chiefComplaint'] ?? '',
          'callerType':      'doctor',
          'status':          'pending',
          'createdAt':       now,
          'updatedAt':       now,
        });

        // Notify the patient so their app can surface the incoming call banner
        // even if they missed the Firestore listener (e.g. notification history).
        if (patientId.isNotEmpty) {
          final notifRef = db
              .collection('patient_notifications')
              .doc(patientId)
              .collection('items')
              .doc();
          batch.set(notifRef, {
            'type':           'incoming_doctor_call',
            'title':          'Dr. $doctorName is calling you',
            'body':           'Tap to join your scheduled consultation',
            'consultationId': consultRef.id,
            'doctorId':       uid,
            'doctorName':     doctorName,
            'isRead':         false,
            'createdAt':      now,
          });
        }

        await batch.commit();

        consultationId = consultRef.id;

        // Persist the link so future taps reuse the same consultation doc.
        await db.collection('appointments').doc(appointmentId).update({
          'consultationId': consultationId,
        });

        if (mounted) FeedbackService.dismiss(ctx);
      } catch (e) {
        if (mounted) {
          FeedbackService.dismiss(ctx);
          FeedbackService.showError(ctx, 'Failed to start call. Please try again.');
        }
        return;
      }
    }

    if (mounted) {
      ctx.push(AppRoutes.videoCall, extra: {
        'consultationId': consultationId,
        'patientName': data['patientName'] ?? 'Patient',
      });
    }
  }

  Future<void> _cancelAppointment(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Appointment?', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('The patient will be notified of the cancellation.', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep', style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Appointment', style: TextStyle(fontFamily: 'Poppins')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      FeedbackService.showLoading(context, 'Cancelling appointment...');
      try {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(docId)
            .update({
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        // Cancel the scheduled local reminders for this appointment.
        await AppointmentReminderService.cancelReminders(docId);
        await OperationLogger.logSuccess(
          action: DoctorOpAction.appointmentRejected,
          entityId: docId,
          entityType: 'appointment',
          message: 'Appointment cancelled by doctor',
        );
        if (mounted) {
          FeedbackService.dismiss(context);
          FeedbackService.showSuccess(context, 'Appointment cancelled — patient will be notified');
        }
      } catch (e) {
        await OperationLogger.logError(
          action: DoctorOpAction.appointmentRejected,
          entityId: docId,
          errorDetails: e.toString(),
        );
        if (mounted) {
          FeedbackService.showError(
            context,
            'Failed to cancel appointment. Please try again.',
          );
        }
      }
    }
  }
}

// ── EARNINGS TAB ──────────────────────────────────────────
class _EarningsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Please log in')));

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final weekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
    final weekStartStr = DateFormat('yyyy-MM-dd').format(weekStart);
    final monthStart = DateFormat('yyyy-MM-dd').format(DateTime(DateTime.now().year, DateTime.now().month, 1));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('doctorId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        final allDocs = snap.data?.docs ?? [];
        final docs = allDocs
            .where((d) => d.data()['status'] == 'completed')
            .toList();

        // Calculate earnings segments
        num todayEarnings = 0;
        num weekEarnings  = 0;
        num monthEarnings = 0;
        int totalConsultations = docs.length;

        for (final doc in docs) {
          final d = doc.data();
          final dateStr = d['date'] as String? ?? '';
          final fee = (d['fee'] as num?) ?? 0;
          if (dateStr.compareTo(monthStart) >= 0) {
            monthEarnings += fee;
            if (dateStr.compareTo(weekStartStr) >= 0) {
              weekEarnings += fee;
              if (dateStr == today) {
                todayEarnings += fee;
              }
            }
          }
        }

        // Recent 5 transactions
        final recent = [...docs]
          ..sort((a, b) {
            final aTs = (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bTs = (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return bTs.compareTo(aTs);
          });
        final recentSlice = recent.take(10).toList();

        final avgPerConsult = totalConsultations > 0
            ? (monthEarnings / totalConsultations).round()
            : 0;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Earnings')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Total earning card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(gradient: AppColors.earningGradient, borderRadius: BorderRadius.circular(20)),
                child: Column(children: [
                  const Text('Total Earnings (This Month)', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 8),
                  Text('₹$monthEarnings', style: const TextStyle(fontFamily: 'Poppins', fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _EarnStat('₹$todayEarnings', 'Today'),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _EarnStat('₹$weekEarnings', 'This Week'),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _EarnStat('$totalConsultations', 'Consultations'),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: monthEarnings > 0 ? () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Withdrawal request submitted. Processing in 3-5 business days.'),
                          behavior: SnackBarBehavior.floating,
                        ));
                      } : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary),
                      child: Text('Withdraw ₹$monthEarnings', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 20),

              // Stats row
              Row(children: [
                _QuickEarnCard('Avg/Consultation', '₹$avgPerConsult', Icons.bar_chart_rounded, const Color(0xFF1565C0)),
                const SizedBox(width: 12),
                _QuickEarnCard(
                  'Completion Rate',
                  allDocs.isNotEmpty
                      ? '${((docs.length / allDocs.length) * 100).round()}%'
                      : '–',
                  Icons.check_circle_rounded,
                  AppColors.success,
                ),
                const SizedBox(width: 12),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: DoctorAuthService.profileStream(uid),
                  builder: (context, profileSnap) {
                    final rating = (profileSnap.data?.data()?['rating'] as num?)?.toStringAsFixed(1) ?? '–';
                    return _QuickEarnCard('Patient Rating', '$rating ⭐', Icons.star_rounded, const Color(0xFFF57F17));
                  },
                ),
              ]),
              const SizedBox(height: 20),

              Text('Recent Transactions', style: AppTextStyles.h4),
              const SizedBox(height: 12),

              if (recentSlice.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
                  child: Center(child: Text('No completed consultations yet', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint))),
                )
              else
                ...recentSlice.map((doc) {
                  final d = doc.data();
                  final name = d['patientName'] as String? ?? 'Patient';
                  final type = d['consultationType'] as String? ?? 'Consultation';
                  final fee  = d['fee'] as num? ?? 0;
                  final dateStr = d['date'] as String? ?? '';
                  final time = d['time'] as String? ?? '';
                  String displayDate = dateStr;
                  try {
                    final dt = DateTime.parse(dateStr);
                    final today2 = DateTime.now();
                    final yesterday2 = today2.subtract(const Duration(days: 1));
                    if (dt.year == today2.year && dt.month == today2.month && dt.day == today2.day) {
                      displayDate = 'Today';
                    } else if (dt.year == yesterday2.year && dt.month == yesterday2.month && dt.day == yesterday2.day) {
                      displayDate = 'Yesterday';
                    } else {
                      displayDate = DateFormat('d MMM').format(dt);
                    }
                  } catch (_) {}
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
                    child: Row(children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(color: AppColors.success.withValues(alpha:0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_downward_rounded, color: AppColors.success, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: AppTextStyles.labelLarge),
                        Text(type, style: AppTextStyles.bodySmall),
                        Text('$displayDate • $time', style: AppTextStyles.caption),
                      ])),
                      Text('+₹$fee', style: AppTextStyles.labelLarge.copyWith(color: AppColors.success)),
                    ]),
                  );
                }),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }
}

class _EarnStat extends StatelessWidget {
  final String value, label;
  const _EarnStat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
    Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
  ]);
}

class _QuickEarnCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _QuickEarnCard(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        Text(label, textAlign: TextAlign.center, style: AppTextStyles.caption, maxLines: 2),
      ]),
    ),
  );
}

// ── PROFILE TAB ───────────────────────────────────────────
class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  Future<void> _pickPatientThenPrescribe(BuildContext context) async {
    final uid = DoctorAuthService.currentUid ?? '';

    // Fetch distinct patients from this doctor's appointments
    final snap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('doctorId', isEqualTo: uid)
        .orderBy('date', descending: true)
        .limit(100)
        .get();

    // Deduplicate by patientId
    final seen = <String>{};
    final patients = <Map<String, String>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final pid  = d['patientId']   as String? ?? '';
      final pname = d['patientName'] as String? ?? 'Patient';
      if (pid.isNotEmpty && seen.add(pid)) {
        patients.add({'id': pid, 'name': pname});
      }
    }

    if (!context.mounted) return;

    final selected = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PatientPickerSheet(patients: patients),
    );

    if (selected == null || !context.mounted) return;
    context.push(AppRoutes.prescription, extra: {
      'patientId':   selected['id'],
      'patientName': selected['name'],
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = DoctorAuthService.currentUid;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('My Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          uid == null
              ? const SizedBox()
              : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: DoctorAuthService.profileStream(uid),
                  builder: (context, snap) {
                    final data = snap.data?.data();
                    final name      = data?['name']     as String? ?? 'Doctor';
                    final specialty = data?['specialty'] as String? ?? '';
                    final exp       = data?['experience'] ?? '–';
                    final fee       = data?['fee']        ?? '–';
                    final total     = data?['totalConsultations']?.toString() ?? '0';
                    final photoUrl  = data?['photoUrl'] as String?;
                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('doctor_rating_summary')
                          .doc(uid)
                          .snapshots(),
                      builder: (context, rSnap) {
                        final rData = rSnap.data?.data();
                        final avg = (rData?['averageRating'] as num?)?.toDouble() ?? 0.0;
                        final reviewCount = (rData?['totalReviews'] as num?)?.toInt() ?? 0;
                        final ratingLabel = (avg > 0 && reviewCount > 0)
                            ? avg.toStringAsFixed(1)
                            : '—';
                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.all(Radius.circular(20))),
                          child: Column(children: [
                            _DoctorAvatarOnGradient(photoUrl: photoUrl, size: 80),
                            const SizedBox(height: 12),
                            Text(name, style: const TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                            Text(specialty, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white70)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.2), borderRadius: BorderRadius.circular(10)),
                              child: const Text('✓ MCI Verified', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                            ),
                            const SizedBox(height: 16),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                              GestureDetector(
                                onTap: () => context.push(AppRoutes.reviews),
                                child: _ProfStat(ratingLabel, reviewCount > 0 ? '$reviewCount Reviews' : 'Rating'),
                              ),
                              _ProfStat('${exp}yr', 'Experience'),
                              _ProfStat(total, 'Patients'),
                              _ProfStat('₹$fee', 'Per Consult'),
                            ]),
                          ]),
                        );
                      },
                    );
                  },
                ),
          const SizedBox(height: 20),

          // Menu items — prescription item handled separately so it shows patient picker
          ...[
            {'icon': Icons.person_outline_rounded,         'label': 'Edit Profile',              'route': AppRoutes.editProfile,  'color': AppColors.primary},
            {'icon': Icons.calendar_month_rounded,         'label': 'Availability Schedule',     'route': AppRoutes.schedule,     'color': const Color(0xFF1565C0)},
            {'icon': Icons.people_rounded,                 'label': 'My Patients',               'route': AppRoutes.patients,     'color': const Color(0xFF2E7D32)},
            {'icon': Icons.account_balance_wallet_rounded, 'label': 'Earnings & Analytics',      'route': AppRoutes.earnings,     'color': const Color(0xFFE65100)},
            {'icon': Icons.emergency_rounded,              'label': 'SOS Emergency Contacts',    'route': AppRoutes.sos,          'color': AppColors.error},
            {'icon': Icons.settings_rounded,               'label': 'Settings',                  'route': AppRoutes.settings,     'color': AppColors.textSecondary},
            {'icon': Icons.help_outline_rounded,           'label': 'Help & Support',            'route': AppRoutes.helpSupport,  'color': const Color(0xFF00695C)},
          ].map((item) => GestureDetector(
            onTap: () => context.push(item['route'] as String),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: (item['color'] as Color).withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(item['icon'] as IconData, color: item['color'] as Color, size: 20),
                ),
                const SizedBox(width: 14),
                Text(item['label'] as String, style: AppTextStyles.labelLarge),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
              ]),
            ),
          )),

          // Write Prescription — dedicated tile that triggers patient picker first
          GestureDetector(
            onTap: () => _pickPatientThenPrescribe(context),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: const Color(0xFF7B1FA2).withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF7B1FA2), size: 20),
                ),
                const SizedBox(width: 14),
                Text('Write Prescription', style: AppTextStyles.labelLarge),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await DoctorAuthService.signOut();
              if (context.mounted) context.go(AppRoutes.login);
            },
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
            label: const Text('Sign Out', style: TextStyle(color: AppColors.error)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _ProfStat extends StatelessWidget {
  final String value, label;
  const _ProfStat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
    Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: Colors.white70)),
  ]);
}

// ── Patient picker bottom sheet (for "Write Prescription" from profile) ──────
class _PatientPickerSheet extends StatefulWidget {
  final List<Map<String, String>> patients;
  const _PatientPickerSheet({required this.patients});

  @override
  State<_PatientPickerSheet> createState() => _PatientPickerSheetState();
}

class _PatientPickerSheetState extends State<_PatientPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.patients
        .where((p) => p['name']!.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Select Patient', style: AppTextStyles.h3),
              const SizedBox(height: 4),
              Text(
                'Choose the patient to write a prescription for',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search patient name...',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textHint),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
            ]),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.person_search_rounded, size: 48, color: AppColors.textHint),
                      const SizedBox(height: 10),
                      Text(
                        widget.patients.isEmpty
                            ? 'No patients yet.\nPatients appear after appointments.'
                            : 'No patient matches "$_query"',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
                      ),
                    ]),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      final initial = p['name']!.isNotEmpty ? p['name']![0].toUpperCase() : '?';
                      return GestureDetector(
                        onTap: () => Navigator.of(context).pop(p),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Row(children: [
                            Container(
                              width: 44, height: 44,
                              decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                              child: Center(child: Text(
                                initial,
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                              )),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(p['name']!, style: AppTextStyles.labelLarge)),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable doctor avatar widgets ────────────────────────

/// Circular avatar for use on white/light backgrounds (home tab app bar).
class _DoctorAvatar extends StatelessWidget {
  final String? photoUrl;
  final double size;
  final double iconSize;
  const _DoctorAvatar({this.photoUrl, required this.size, required this.iconSize});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    if (hasPhoto) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: size, height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => _fallback(),
          errorWidget: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        width: size, height: size,
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
        child: Icon(Icons.person_rounded, color: Colors.white, size: iconSize),
      );
}

/// Avatar for use on a gradient card — uses semi-transparent white background.
class _DoctorAvatarOnGradient extends StatelessWidget {
  final String? photoUrl;
  final double size;
  const _DoctorAvatarOnGradient({this.photoUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    if (hasPhoto) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha:0.5), width: 2),
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: photoUrl!,
            width: size, height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) => _fallback(),
            errorWidget: (_, __, ___) => _fallback(),
          ),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.2), shape: BoxShape.circle),
        child: Icon(Icons.person_rounded, size: size * 0.57, color: Colors.white),
      );
}

// ── Auto-connect dialog ───────────────────────────────────────────────────────

/// Shown when an appointment's start time is reached.  Counts down 15 s and
/// then automatically calls [onJoin]; the doctor can tap "JOIN NOW" early or
/// dismiss to handle it manually from the appointments list.
class _AutoConnectDialog extends StatefulWidget {
  final String patientName;
  final String appointmentTime;
  final VoidCallback onJoin;

  const _AutoConnectDialog({
    required this.patientName,
    required this.appointmentTime,
    required this.onJoin,
  });

  @override
  State<_AutoConnectDialog> createState() => _AutoConnectDialogState();
}

class _AutoConnectDialogState extends State<_AutoConnectDialog> {
  static const _total = 15;
  int _remaining = _total;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        _timer?.cancel();
        Navigator.of(context).pop();
        widget.onJoin();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = _remaining / _total;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 68, height: 68,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 20),
            const Text(
              'Consultation Starting!',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Your appointment with ${widget.patientName} at ${widget.appointmentTime} is starting now.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 24),
            // Countdown ring
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 64, height: 64,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 4.5,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _remaining > 8 ? AppColors.primary : AppColors.error,
                    ),
                  ),
                ),
                Text(
                  '$_remaining',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Auto-joining in $_remaining seconds',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.black38),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _timer?.cancel();
                      Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: AppColors.primary),
                    ),
                    child: const Text(
                      'Dismiss',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _timer?.cancel();
                      Navigator.of(context).pop();
                      widget.onJoin();
                    },
                    icon: const Icon(Icons.videocam_rounded, size: 18),
                    label: const Text(
                      'JOIN NOW',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
