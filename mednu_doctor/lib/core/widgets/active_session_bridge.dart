import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../router/app_router.dart';

/// Global floating banner that surfaces a live/imminent consultation from
/// anywhere in the app — quick-connect calls in progress, a patient waiting
/// on this doctor, or a booked appointment starting soon. Hidden (zero
/// size, no hit-testing) whenever none of those apply.
///
/// Mounted once at the app root (see main.dart) so it survives every route
/// push/pop instead of living inside a single screen. Never performs
/// Firestore writes itself — it only navigates into screens (video call, or
/// the dashboard) that already own the real join/accept logic, so it can't
/// diverge from or duplicate that behaviour.
class ActiveSessionBridge extends ConsumerStatefulWidget {
  const ActiveSessionBridge({super.key});

  @override
  ConsumerState<ActiveSessionBridge> createState() =>
      _ActiveSessionBridgeState();
}

enum _BridgeKind { none, liveCall, patientWaiting, upcoming }

class _BridgeInfo {
  final _BridgeKind kind;
  final String consultationId;
  final String patientName;
  final Duration? startsIn;

  const _BridgeInfo({
    this.kind = _BridgeKind.none,
    this.consultationId = '',
    this.patientName = '',
    this.startsIn,
  });

  static const none = _BridgeInfo();
}

class _ActiveSessionBridgeState extends ConsumerState<ActiveSessionBridge>
    with SingleTickerProviderStateMixin {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _liveSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _apptSub;
  Timer? _ticker;
  late final AnimationController _pulse;

  QueryDocumentSnapshot<Map<String, dynamic>>? _liveDoc;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _upcomingAppts = const [];

  // Appointment window — mirrors _checkAutoConnect in dashboard_screen.dart
  // (30s before through 5min after) widened slightly so the bridge lights
  // up a little ahead of the auto-connect dialog, per the requested 15-min
  // lead time.
  static const _openBeforeMin = 15;
  static const _closeAfterMin = 30;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onAuthChanged(User? user) {
    _liveSub?.cancel();
    _apptSub?.cancel();
    if (mounted) {
      setState(() {
        _liveDoc = null;
        _upcomingAppts = const [];
      });
    }
    if (user == null) return;

    final db = FirebaseFirestore.instance;

    _liveSub = db
        .collection('consultations')
        .where('doctorId', isEqualTo: user.uid)
        .where('status', whereIn: ['ongoing', 'active', 'scheduled_waiting'])
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _liveDoc = snap.docs.isEmpty ? null : snap.docs.first);
    });

    final today = DateTime.now();
    _apptSub = db
        .collection('appointments')
        .where('doctorId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'booked')
        .where('date', whereIn: [_dateStr(today), _dateStr(today.add(const Duration(days: 1)))])
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _upcomingAppts = snap.docs);
    });
  }

  static String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseSlot(String dateStr, String timeStr) {
    if (dateStr.isEmpty || timeStr.isEmpty) return null;
    try {
      final date = DateTime.parse(dateStr);
      final parts = timeStr.trim().split(' ');
      final hm = parts[0].split(':');
      int h = int.parse(hm[0]);
      final m = int.parse(hm[1]);
      if (parts.length > 1 && parts[1].toUpperCase() == 'PM' && h != 12) h += 12;
      if (parts.length > 1 && parts[1].toUpperCase() == 'AM' && h == 12) h = 0;
      return DateTime(date.year, date.month, date.day, h, m);
    } catch (_) {
      return null;
    }
  }

  _BridgeInfo _computeInfo() {
    final liveData = _liveDoc?.data();
    if (liveData != null) {
      final status = liveData['status'] as String? ?? '';
      if (status == 'ongoing' || status == 'active' || status == 'scheduled_waiting') {
        return _BridgeInfo(
          kind: status == 'scheduled_waiting' ? _BridgeKind.patientWaiting : _BridgeKind.liveCall,
          consultationId: _liveDoc!.id,
          patientName: liveData['patientName'] as String? ?? 'Patient',
        );
      }
    }

    final now = DateTime.now();
    for (final doc in _upcomingAppts) {
      final d = doc.data();
      final slot = _parseSlot(d['date'] as String? ?? '', d['time'] as String? ?? '');
      if (slot == null) continue;
      final diff = slot.difference(now);
      if (diff.inMinutes <= _openBeforeMin && diff.inMinutes >= -_closeAfterMin) {
        return _BridgeInfo(
          kind: _BridgeKind.upcoming,
          consultationId: (d['consultationId'] as String?) ?? '',
          patientName: d['patientName'] as String? ?? 'Patient',
          startsIn: diff.isNegative ? Duration.zero : diff,
        );
      }
    }
    return _BridgeInfo.none;
  }

  void _onTap(_BridgeInfo info) {
    final router = ref.read(appRouterProvider);
    switch (info.kind) {
      case _BridgeKind.liveCall:
        // Re-tap after a brief disconnect — same safe, write-free path the
        // dashboard already uses for this exact scenario.
        router.push(AppRoutes.videoCall, extra: {
          'consultationId': info.consultationId,
          'patientName': info.patientName,
        });
        break;
      case _BridgeKind.patientWaiting:
      case _BridgeKind.upcoming:
        // Starting/accepting the call writes to Firestore — hand off to the
        // dashboard's appointment card, which already owns that logic.
        router.go(AppRoutes.dashboard);
        break;
      case _BridgeKind.none:
        break;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _liveSub?.cancel();
    _apptSub?.cancel();
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _computeInfo();
    final visible = info.kind != _BridgeKind.none;

    return IgnorePointer(
      ignoring: !visible,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 72),
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            offset: visible ? Offset.zero : const Offset(0, 0.4),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: visible ? 1 : 0,
              child: visible
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _BridgeCard(
                        info: info,
                        pulse: _pulse,
                        onTap: () => _onTap(info),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

class _BridgeCard extends StatelessWidget {
  final _BridgeInfo info;
  final Animation<double> pulse;
  final VoidCallback onTap;

  const _BridgeCard({required this.info, required this.pulse, required this.onTap});

  (IconData, String, String) _content() {
    switch (info.kind) {
      case _BridgeKind.liveCall:
        return (Icons.call_rounded, 'Call in progress', '${info.patientName} • Tap to rejoin');
      case _BridgeKind.patientWaiting:
        return (Icons.hourglass_top_rounded, '${info.patientName} is waiting',
            'Patient is in the waiting room • Tap to join');
      case _BridgeKind.upcoming:
        final s = info.startsIn;
        final title = (s == null || s <= Duration.zero)
            ? 'Appointment ready — Start now'
            : 'Starts in ${s.inMinutes < 1 ? "under a minute" : "${s.inMinutes} min"}';
        return (Icons.video_call_rounded, title, 'With ${info.patientName}');
      case _BridgeKind.none:
        return (Icons.circle, '', '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = _content();
    final isLive = info.kind == _BridgeKind.liveCall;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  if (isLive)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: AnimatedBuilder(
                        animation: pulse,
                        builder: (_, child) => Opacity(
                          opacity: 0.5 + pulse.value * 0.5,
                          child: child,
                        ),
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
