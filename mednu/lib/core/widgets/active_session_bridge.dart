import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../router/app_router.dart';

/// Global floating banner that surfaces a live/imminent consultation from
/// anywhere in the app — quick-connect calls in progress, the patient's own
/// scheduled waiting room, or a booked appointment starting soon. Hidden
/// (zero size, no hit-testing) whenever none of those apply.
///
/// Mounted once at the app root (see app.dart) so it survives every route
/// push/pop instead of living inside a single screen.
class ActiveSessionBridge extends ConsumerStatefulWidget {
  final GoRouter router;

  const ActiveSessionBridge({super.key, required this.router});

  @override
  ConsumerState<ActiveSessionBridge> createState() =>
      _ActiveSessionBridgeState();
}

enum _BridgeKind { none, liveCall, waitingRoom, upcoming }

class _BridgeInfo {
  final _BridgeKind kind;
  final String consultationId;
  final String doctorName;
  final String specialty;
  final String photoUrl;
  final Duration? startsIn;

  const _BridgeInfo({
    this.kind = _BridgeKind.none,
    this.consultationId = '',
    this.doctorName = '',
    this.specialty = '',
    this.photoUrl = '',
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

  // Appointment join window — mirrors _ScheduledJoinSection in
  // appointment_screen.dart so the bridge lights up exactly when that
  // screen's own "Join Now" button would.
  static const _openBeforeMin = 15;
  static const _closeAfterMin = 30;

  // Drag-to-reposition: null means "use the default bottom-anchored spot"
  // (today's fixed position, unchanged unless the patient actually drags
  // it). Once dragged, holds the card's top offset in logical pixels and it
  // stays wherever they left it for the rest of the session.
  double? _dragTop;
  static const _cardHeightEstimate = 76.0;

  void _onDragStart(double defaultTop) {
    _dragTop ??= defaultTop;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_dragTop == null) return;
    final mq = MediaQuery.of(context);
    final minTop = mq.padding.top + 8;
    final maxTop = mq.size.height - mq.padding.bottom - _cardHeightEstimate - 8;
    setState(() {
      _dragTop = (_dragTop! + details.delta.dy).clamp(minTop, maxTop);
    });
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
    // Re-evaluate the time-based window periodically even without a new
    // Firestore event (e.g. countdown ticking, window opening/closing).
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
    // This overlay lives outside the routed page tree (see the class doc),
    // so it can't read the current route via GoRouterState.of(context) —
    // listen to the router directly instead, needed to hide the "Call in
    // progress" card while the patient is already looking at that exact
    // call.
    widget.router.routerDelegate.addListener(_onRouteChanged);
  }

  void _onRouteChanged() {
    if (mounted) setState(() {});
  }

  // AppRoutes.videoCall is '/consultation/video/:id' — check the prefix
  // since the live id segment varies.
  bool get _onVideoCallScreen => widget.router.routerDelegate.currentConfiguration.uri
      .toString()
      .startsWith('/consultation/video');

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
        .where('patientId', isEqualTo: user.uid)
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
        .where('patientId', isEqualTo: user.uid)
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
          kind: status == 'scheduled_waiting' ? _BridgeKind.waitingRoom : _BridgeKind.liveCall,
          consultationId: _liveDoc!.id,
          doctorName: liveData['doctorName'] as String? ?? 'Doctor',
          specialty: liveData['doctorSpecialty'] as String? ?? '',
          photoUrl: liveData['doctorPhotoUrl'] as String? ?? '',
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
          doctorName: d['doctorName'] as String? ?? 'Doctor',
          specialty: d['doctorSpecialty'] as String? ?? '',
          photoUrl: d['doctorPhotoUrl'] as String? ?? '',
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
        router.push(
          AppRoutes.videoCall.replaceFirst(':id', info.consultationId),
          extra: {'name': info.doctorName, 'specialty': info.specialty},
        );
        break;
      case _BridgeKind.waitingRoom:
        router.push(
          AppRoutes.outgoingCall,
          extra: {
            'consultationId': info.consultationId,
            'doctorName': info.doctorName,
            'doctorSpecialty': info.specialty,
            'doctorPhotoUrl': info.photoUrl,
            'isScheduled': true,
          },
        );
        break;
      case _BridgeKind.upcoming:
        // No consultation doc yet — hand off to the appointment list, which
        // already owns the real "Join Now" logic (creates the consultation).
        router.push(AppRoutes.appointment);
        break;
      case _BridgeKind.none:
        break;
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRouteChanged);
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
    // Only the live-call case needs suppressing while already on that
    // screen — waitingRoom/upcoming still need to surface from elsewhere
    // in the app so the patient can navigate to rejoin/start them.
    final visible = info.kind != _BridgeKind.none &&
        !(info.kind == _BridgeKind.liveCall && _onVideoCallScreen);

    final mq = MediaQuery.of(context);
    // Mirrors the default Align(bottomCenter)+SafeArea(minimum: 72) spot
    // below, expressed as a top offset — only used to seed the very first
    // drag so the card doesn't jump when the patient first grabs it.
    final defaultTop = mq.size.height -
        (mq.padding.bottom > 72 ? mq.padding.bottom : 72) -
        _cardHeightEstimate;

    final draggableCard = visible
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _BridgeCard(
              info: info,
              pulse: _pulse,
              onTap: () => _onTap(info),
              onHandleDragStart: () => _onDragStart(defaultTop),
              onHandleDragUpdate: _onDragUpdate,
            ),
          )
        : const SizedBox.shrink();

    return IgnorePointer(
      ignoring: !visible,
      child: _dragTop == null
          ? Align(
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
                    child: draggableCard,
                  ),
                ),
              ),
            )
          // Once dragged, the card stays exactly where the patient left it
          // instead of snapping back to the bottom on the next rebuild.
          : Positioned(
              top: _dragTop,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: visible ? 1 : 0,
                child: draggableCard,
              ),
            ),
    );
  }
}

class _BridgeCard extends StatelessWidget {
  final _BridgeInfo info;
  final Animation<double> pulse;
  final VoidCallback onTap;
  final VoidCallback onHandleDragStart;
  final GestureDragUpdateCallback onHandleDragUpdate;

  const _BridgeCard({
    required this.info,
    required this.pulse,
    required this.onTap,
    required this.onHandleDragStart,
    required this.onHandleDragUpdate,
  });

  (IconData, String, String) _content() {
    switch (info.kind) {
      case _BridgeKind.liveCall:
        return (Icons.call_rounded, 'Call in progress', 'Dr. ${info.doctorName} • Tap to rejoin');
      case _BridgeKind.waitingRoom:
        return (Icons.hourglass_top_rounded, 'Waiting for Dr. ${info.doctorName}',
            'You left the waiting room • Tap to return');
      case _BridgeKind.upcoming:
        final s = info.startsIn;
        final title = (s == null || s <= Duration.zero)
            ? 'Appointment ready — Join now'
            : 'Starts in ${s.inMinutes < 1 ? "under a minute" : "${s.inMinutes} min"}';
        return (Icons.video_call_rounded, title,
            'Dr. ${info.doctorName}${info.specialty.isNotEmpty ? " • ${info.specialty}" : ""}');
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle — signals the card can be dragged to reposition,
              // matching this app's bottom-sheet handle convention. Only
              // this small region owns the vertical-drag gesture: earlier
              // the whole card intercepted it, which hijacked scroll swipes
              // that merely started on the card's footprint (the card would
              // fling to the top/bottom clamp and stick there instead of
              // the list underneath scrolling).
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: (_) => onHandleDragStart(),
                onVerticalDragUpdate: onHandleDragUpdate,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Row(
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
                            fontFamily: 'Poppins',
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
                            fontFamily: 'Poppins',
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
            ],
          ),
        ),
      ),
    );
  }
}
