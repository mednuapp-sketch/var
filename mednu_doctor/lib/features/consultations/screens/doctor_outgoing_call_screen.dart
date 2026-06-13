import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';

/// Shown to the doctor after they tap "Call Patient".
/// Creates the consultation document, then watches its status:
///   pending  → ringing (patient hasn't responded yet)
///   ongoing  → patient accepted → navigate to DoctorVideoCallScreen
///   declined → patient declined → show feedback + close
///   cancelled → close
class DoctorOutgoingCallScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

  const DoctorOutgoingCallScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<DoctorOutgoingCallScreen> createState() =>
      _DoctorOutgoingCallScreenState();
}

class _DoctorOutgoingCallScreenState extends State<DoctorOutgoingCallScreen>
    with TickerProviderStateMixin {
  late AnimationController _ripple1;
  late AnimationController _ripple2;
  late AnimationController _ripple3;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _dotsCtrl;

  _CallState _callState = _CallState.calling;
  String? _consultationId;
  bool _navigated = false;
  int _callSeconds = 0;
  Timer? _elapsedTimer;
  StreamSubscription<DocumentSnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initAnimations();
    WakelockPlus.enable();
    HapticFeedback.mediumImpact();
    _createAndWatch();
    _startElapsedTimer();
  }

  void _initAnimations() {
    _ripple1 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _ripple2 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _ripple3 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..forward(from: 0.33)
      ..repeat();

    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.94, end: 1.06).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _dotsCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  Future<void> _createAndWatch() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) context.pop();
      return;
    }

    // Load doctor's own profile to get name and specialty
    String doctorName = 'Doctor';
    String doctorSpecialty = '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('doctors')
          .doc(uid)
          .get();
      doctorName = doc.data()?['name'] as String? ?? 'Doctor';
      doctorSpecialty = doc.data()?['specialty'] as String? ?? '';
    } catch (_) {}

    // Fetch patient FCM token (for Cloud Function to notify patient).
    // Check patients collection first, fall back to users collection.
    String patientFcmToken = '';
    try {
      final db = FirebaseFirestore.instance;
      var patSnap = await db.collection('patients').doc(widget.patientId).get();
      patientFcmToken = patSnap.data()?['fcmToken'] as String? ?? '';
      if (patientFcmToken.isEmpty) {
        final userSnap = await db.collection('users').doc(widget.patientId).get();
        patientFcmToken = userSnap.data()?['fcmToken'] as String? ?? '';
      }
    } catch (_) {}

    // Create the consultation document
    final ref = FirebaseFirestore.instance.collection('consultations').doc();
    try {
      await ref.set({
        'channelName': ref.id,
        'status': 'pending',
        'callerType': 'doctor',
        'doctorId': uid,
        'doctorName': doctorName,
        'doctorSpecialty': doctorSpecialty,
        'patientId': widget.patientId,
        'patientName': widget.patientName,
        'patientFcmToken': patientFcmToken,
        'consultationType': 'Video',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[DoctorOutgoing] Failed to create consultation: $e');
      if (mounted) context.pop();
      return;
    }

    _consultationId = ref.id;
    _watchStatus();
  }

  void _watchStatus() {
    if (_consultationId == null) return;
    _sub = FirebaseFirestore.instance
        .collection('consultations')
        .doc(_consultationId!)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted || _navigated) return;
      final status = snap.data()?['status'] as String? ?? '';
      _handleStatus(status);
    });
  }

  void _handleStatus(String status) {
    switch (status) {
      case 'ongoing':
        // Patient accepted — go to call screen
        if (_navigated) return;
        _navigated = true;
        _sub?.cancel();
        if (!mounted) return;
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        context.pushReplacement(AppRoutes.videoCall, extra: {
          'consultationId': _consultationId!,
          'patientName': widget.patientName,
        });
        break;
      case 'declined':
        if (_callState != _CallState.declined) {
          setState(() => _callState = _CallState.declined);
          HapticFeedback.heavyImpact();
          _autoClose();
        }
        break;
      case 'cancelled':
      case 'ended':
      case 'missed':
        if (!_navigated) _safeClose();
        break;
    }
  }

  void _startElapsedTimer() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _callSeconds++);
    });
  }

  String get _elapsedLabel {
    final m = _callSeconds ~/ 60;
    final s = _callSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _cancelCall() async {
    if (_navigated) return;
    HapticFeedback.mediumImpact();
    _navigated = true;
    _sub?.cancel();
    if (_consultationId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('consultations')
            .doc(_consultationId!)
            .update({
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
    if (mounted) _safeClose();
  }

  void _autoClose() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_navigated) _safeClose();
    });
  }

  void _safeClose() {
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (context.canPop()) context.pop();
  }

  @override
  void dispose() {
    _ripple1.dispose();
    _ripple2.dispose();
    _ripple3.dispose();
    _pulseCtrl.dispose();
    _dotsCtrl.dispose();
    _elapsedTimer?.cancel();
    _sub?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (_) async => _cancelCall(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF050E2B), Color(0xFF0D2050), Color(0xFF071030)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                _buildStatusLabel(),
                const Spacer(),
                _buildAvatarWithRipples(),
                const SizedBox(height: 28),
                _buildPatientInfo(),
                const SizedBox(height: 12),
                _buildTimer(),
                const Spacer(),
                if (_callState == _CallState.calling) _buildCancelButton(),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusLabel() {
    final label = switch (_callState) {
      _CallState.calling  => 'Calling...',
      _CallState.declined => 'Call Declined',
    };
    final color = switch (_callState) {
      _CallState.declined => const Color(0xFFE53935),
      _CallState.calling  => Colors.white70,
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Row(
        key: ValueKey(_callState),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_callState == _CallState.calling)
            _DotsIndicator(controller: _dotsCtrl),
          if (_callState == _CallState.calling) const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarWithRipples() {
    final glowColor = _callState == _CallState.declined
        ? const Color(0xFFE53935)
        : AppColors.primary;

    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_callState == _CallState.calling) ...[
            _RippleRing(controller: _ripple1, delay: 0.0, color: glowColor),
            _RippleRing(controller: _ripple2, delay: 0.33, color: glowColor),
            _RippleRing(controller: _ripple3, delay: 0.66, color: glowColor),
          ],
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                gradient: _callState == _CallState.calling
                    ? AppColors.primaryGradient
                    : RadialGradient(colors: [
                        glowColor.withValues(alpha:0.9),
                        glowColor.withValues(alpha:0.5),
                      ]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withValues(alpha:0.55),
                    blurRadius: 32,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Icon(
                _callState == _CallState.declined
                    ? Icons.call_end_rounded
                    : Icons.person_rounded,
                color: Colors.white,
                size: 52,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientInfo() {
    return Column(
      children: [
        Text(
          widget.patientName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_rounded, color: Colors.white38, size: 13),
            SizedBox(width: 5),
            Text(
              'Video Consultation',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: Colors.white54),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimer() {
    return Text(
      _elapsedLabel,
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 14,
        color: Colors.white30,
        letterSpacing: 2,
      ),
    );
  }

  Widget _buildCancelButton() {
    return Column(
      children: [
        GestureDetector(
          onTap: _cancelCall,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE53935).withValues(alpha:0.5),
                  blurRadius: 24,
                  spreadRadius: 6,
                ),
              ],
            ),
            child:
                const Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Cancel',
          style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12, color: Colors.white38),
        ),
      ],
    );
  }
}

enum _CallState { calling, declined }

class _RippleRing extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  final Color color;

  const _RippleRing({
    required this.controller,
    required this.delay,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final progress = ((controller.value + delay) % 1.0);
        final size = 110.0 + 90.0 * progress;
        final opacity = (1.0 - progress) * 0.35;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha:opacity),
              width: 2.0,
            ),
          ),
        );
      },
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  final AnimationController controller;
  const _DotsIndicator({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (controller.value - i * 0.2).clamp(0.0, 1.0);
            final scale = 0.6 + 0.4 * math.sin(phase * math.pi * 2).abs();
            return Transform.scale(
              scale: scale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Colors.white60,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
