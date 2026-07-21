import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';

/// Outgoing call screen for both quick-connect and scheduled appointments.
///
/// Quick-connect status flow:
///   pending   → "Calling..."  |  ongoing → "Connecting"  |  active → VideoCall
///   declined/missed → feedback then pop  |  cancelled/ended → pop
///
/// Scheduled appointment status flow:
///   scheduled_waiting → "Waiting for doctor"  |  active → VideoCall
///   pending (doctor re-initiated) → "Doctor joining"  |  active → VideoCall
///   cancelled/ended → pop
class OutgoingCallScreen extends StatefulWidget {
  final String consultationId;
  final String doctorName;
  final String doctorSpecialty;
  final String doctorPhotoUrl;
  /// True when this is a scheduled appointment join (not an instant call).
  final bool isScheduled;

  const OutgoingCallScreen({
    super.key,
    required this.consultationId,
    required this.doctorName,
    required this.doctorSpecialty,
    this.doctorPhotoUrl = '',
    this.isScheduled = false,
  });

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ─────────────────────────────────────────────────
  late AnimationController _ripple1;
  late AnimationController _ripple2;
  late AnimationController _ripple3;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _dotsCtrl;

  // ── Call state ────────────────────────────────────────────────────────────
  _OutgoingState _callState = _OutgoingState.calling;
  bool _navigated = false;
  int _callSeconds = 0;
  Timer? _elapsedTimer;
  Timer? _timeoutTimer;
  // Scheduled appointments wait up to 15 min; quick-connect times out at 60 s.
  int get _timeoutSeconds => widget.isScheduled ? 900 : 60;

  StreamSubscription<DocumentSnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initAnimations();
    WakelockPlus.enable();
    _watchConsultation();
    _startElapsedTimer();
    _startTimeoutTimer();
    HapticFeedback.mediumImpact();
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

  void _watchConsultation() {
    _sub = FirebaseFirestore.instance
        .collection('consultations')
        .doc(widget.consultationId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted || _navigated) return;
      final status = snap.data()?['status'] as String? ?? '';
      _handleStatus(status, snap.data());
    });
  }

  void _handleStatus(String status, Map<String, dynamic>? data) {
    switch (status) {
      // ── Scheduled: patient is waiting, doctor hasn't joined yet ────────────
      case 'scheduled_waiting':
        if (_callState != _OutgoingState.calling) {
          setState(() => _callState = _OutgoingState.calling);
        }
        break;
      // ── Quick-connect: waiting for doctor to see the request ────────────────
      case 'pending':
        if (_callState != _OutgoingState.calling) {
          setState(() => _callState = _OutgoingState.calling);
        }
        break;
      // ── Doctor accepted (quick-connect) or doctor initiated (scheduled) ─────
      case 'ongoing':
        if (_callState != _OutgoingState.ringing) {
          setState(() => _callState = _OutgoingState.ringing);
          HapticFeedback.lightImpact();
        }
        break;
      // ── Both sides ready — navigate to video ───────────────────────────────
      case 'active':
        if (_navigated) return;
        _navigated = true;
        _timeoutTimer?.cancel();
        _sub?.cancel();
        _navigateToCall();
        break;
      case 'declined':
      case 'rejected':
        if (_callState != _OutgoingState.declined) {
          setState(() => _callState = _OutgoingState.declined);
          HapticFeedback.heavyImpact();
          _autoClose();
        }
        break;
      case 'missed':
        if (_callState != _OutgoingState.missed) {
          setState(() => _callState = _OutgoingState.missed);
          _autoClose();
        }
        break;
      case 'cancelled':
      case 'ended':
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

  void _startTimeoutTimer() {
    _timeoutTimer = Timer(Duration(seconds: _timeoutSeconds), () {
      if (!mounted || _navigated ||
          _callState == _OutgoingState.declined ||
          _callState == _OutgoingState.missed) { return; }
      setState(() => _callState = _OutgoingState.missed);
      _markNoAnswer();
      _autoClose();
    });
  }

  Future<void> _markNoAnswer() async {
    try {
      await FirebaseFirestore.instance
          .collection('consultations')
          .doc(widget.consultationId)
          .update({
        'status': 'missed',
        'missedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  String get _elapsedLabel {
    if (_callState == _OutgoingState.calling) {
      if (widget.isScheduled) {
        // Show elapsed wait time for scheduled, not a countdown
        final m = _callSeconds ~/ 60;
        final s = _callSeconds % 60;
        return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      }
      final remaining = (_timeoutSeconds - _callSeconds).clamp(0, _timeoutSeconds);
      final m = remaining ~/ 60;
      final s = remaining % 60;
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    final m = _callSeconds ~/ 60;
    final s = _callSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _navigateToCall() {
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    context.pushReplacement(
      AppRoutes.videoCall.replaceFirst(':id', widget.consultationId),
      extra: {
        'name': widget.doctorName,
        'specialty': widget.doctorSpecialty,
      },
    );
  }

  void _autoClose() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_navigated) _safeClose();
    });
  }

  Future<void> _cancelCall() async {
    HapticFeedback.mediumImpact();
    _navigated = true;
    _timeoutTimer?.cancel();
    _sub?.cancel();
    try {
      await FirebaseFirestore.instance
          .collection('consultations')
          .doc(widget.consultationId)
          .update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[OutgoingCall] Cancel status update failed: $e');
    }
    if (mounted) _safeClose();
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
    _timeoutTimer?.cancel();
    _sub?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _cancelCall(); },
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
                _buildDoctorInfo(),
                const SizedBox(height: 12),
                _buildCallTimer(),
                const Spacer(),
                _buildCancelButton(),
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
      _OutgoingState.calling  => widget.isScheduled
          ? 'Waiting for doctor to join...'
          : 'Connecting you to Dr. ${widget.doctorName}...',
      _OutgoingState.ringing  => 'Doctor is joining the call...',
      _OutgoingState.declined => 'Call Declined',
      _OutgoingState.missed   => 'No Answer',
    };
    final color = switch (_callState) {
      _OutgoingState.declined => const Color(0xFFE53935),
      _OutgoingState.missed   => Colors.orange,
      _OutgoingState.ringing  => Colors.greenAccent,
      _                       => Colors.white70,
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Row(
        key: ValueKey(_callState),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_callState == _OutgoingState.calling)
            _DotsIndicator(controller: _dotsCtrl),
          if (_callState == _OutgoingState.calling) const SizedBox(width: 8),
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
    final glowColor = switch (_callState) {
      _OutgoingState.ringing  => const Color(0xFF00C853),
      _OutgoingState.declined => const Color(0xFFE53935),
      _OutgoingState.missed   => Colors.orange,
      _                       => AppColors.primary,
    };

    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_callState == _OutgoingState.calling ||
              _callState == _OutgoingState.ringing) ...[
            _RippleRing(controller: _ripple1, delay: 0.0, color: glowColor),
            _RippleRing(controller: _ripple2, delay: 0.33, color: glowColor),
            _RippleRing(controller: _ripple3, delay: 0.66, color: glowColor),
          ],
          ScaleTransition(
            scale: _pulseAnim,
            child: _buildAvatarCircle(glowColor),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarCircle(Color glowColor) {
    final isActive = _callState == _OutgoingState.calling ||
        _callState == _OutgoingState.ringing;
    final IconData fallbackIcon = _callState == _OutgoingState.declined
        ? Icons.call_end_rounded
        : _callState == _OutgoingState.missed
            ? Icons.phone_missed_rounded
            : Icons.person_rounded;

    final hasPhoto = widget.doctorPhotoUrl.isNotEmpty &&
        _callState != _OutgoingState.declined &&
        _callState != _OutgoingState.missed;

    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        gradient: hasPhoto
            ? null
            : isActive
                ? AppColors.primaryGradient
                : RadialGradient(colors: [
                    glowColor.withValues(alpha: 0.9),
                    glowColor.withValues(alpha: 0.5),
                  ]),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.55),
            blurRadius: 32,
            spreadRadius: 10,
          ),
        ],
      ),
      child: hasPhoto
          ? ClipOval(
              child: Image.network(
                widget.doctorPhotoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: isActive ? AppColors.primaryGradient : null,
                    color: isActive ? null : glowColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(fallbackIcon, color: Colors.white, size: 52),
                ),
              ),
            )
          : Icon(fallbackIcon, color: Colors.white, size: 52),
    );
  }

  Widget _buildDoctorInfo() {
    return Column(
      children: [
        Text(
          widget.doctorName,
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_hospital_rounded,
                color: Colors.white38, size: 13),
            const SizedBox(width: 5),
            Text(
              widget.doctorSpecialty,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: Colors.white54),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCallTimer() {
    final isCountdown = _callState == _OutgoingState.calling;
    // Scheduled appointments show elapsed wait time without a countdown bar.
    final showProgressBar = isCountdown && !widget.isScheduled;
    return Column(
      children: [
        Text(
          _elapsedLabel,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            color: isCountdown ? Colors.white38 : Colors.white30,
            letterSpacing: 2,
          ),
        ),
        if (widget.isScheduled && isCountdown) ...[
          const SizedBox(height: 6),
          Text(
            'Your doctor will join shortly',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: Colors.white24,
            ),
          ),
        ],
        if (showProgressBar) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              value: (_timeoutSeconds - _callSeconds).clamp(0, _timeoutSeconds) / _timeoutSeconds,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                _callSeconds < 40 ? Colors.white30 : Colors.orangeAccent,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCancelButton() {
    if (_callState == _OutgoingState.declined ||
        _callState == _OutgoingState.missed) {
      return const SizedBox.shrink();
    }
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
            child: const Icon(Icons.call_end_rounded,
                color: Colors.white, size: 32),
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

// ── Call state enum ───────────────────────────────────────────────────────────

enum _OutgoingState { calling, ringing, declined, missed }

// ── Reusable widgets ──────────────────────────────────────────────────────────

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

/// Three animated dots for "Calling..." indicator.
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
