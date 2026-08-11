import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/call_notification_service.dart';

/// Full-screen incoming call UI shown to the patient when a doctor initiates
/// a consultation call. Mirrors the doctor app's IncomingRequestScreen in
/// style and behaviour — ripple animations, countdown, accept/decline.
class IncomingCallScreen extends StatefulWidget {
  final String consultationId;
  final String doctorName;
  final String doctorSpecialty;
  final String consultationType;
  final String doctorPhotoUrl;

  const IncomingCallScreen({
    super.key,
    required this.consultationId,
    required this.doctorName,
    required this.doctorSpecialty,
    this.consultationType = 'Video',
    this.doctorPhotoUrl = '',
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with TickerProviderStateMixin {
  late AnimationController _ripple1;
  late AnimationController _ripple2;
  late AnimationController _ripple3;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  int _countdown = 45;
  bool _accepted = false;
  bool _countdownActive = false;
  Timer? _hapticTimer;

  StreamSubscription<DocumentSnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    WakelockPlus.enable();
    CallNotificationService.startRinging();
    _startCountdown();
    _watchForCancellation();
    HapticFeedback.heavyImpact();
    // Repeat heavy haptic every 2 seconds while ringing
    _hapticTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _accepted) return;
      HapticFeedback.heavyImpact();
    });
  }

  void _initAnimations() {
    _ripple1 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _ripple2 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..forward(from: 0.33)
      ..repeat();
    _ripple3 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..forward(from: 0.66)
      ..repeat();

    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.94, end: 1.06).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  void _watchForCancellation() {
    _sub = FirebaseFirestore.instance
        .collection('consultations')
        .doc(widget.consultationId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted || _accepted) return;
      final status = snap.data()?['status'] as String? ?? '';
      if (status == 'cancelled' || status == 'ended') {
        _safeClose();
      }
    });
  }

  void _startCountdown() {
    if (_countdownActive) return;
    _countdownActive = true;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || _accepted) {
        _countdownActive = false;
        return false;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        _countdownActive = false;
        _declineCall();
        return false;
      }
      return true;
    });
  }

  Future<void> _acceptCall() async {
    if (_accepted) return;
    setState(() => _accepted = true);
    HapticFeedback.heavyImpact();
    await CallNotificationService.cancelAll();
    _sub?.cancel();

    try {
      await FirebaseFirestore.instance
          .collection('consultations')
          .doc(widget.consultationId)
          .update({
        'status': 'ongoing',
        'startedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[IncomingCall] Status update failed: $e');
    }

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

  Future<void> _declineCall() async {
    if (_accepted) return;
    _accepted = true;
    HapticFeedback.mediumImpact();
    await CallNotificationService.cancelAll();
    _sub?.cancel();
    try {
      await FirebaseFirestore.instance
          .collection('consultations')
          .doc(widget.consultationId)
          .update({'status': 'declined'});
    } catch (e) {
      debugPrint('[IncomingCall] Decline status update failed: $e');
    }
    if (mounted) _safeClose();
  }

  void _safeClose() {
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // This screen is often reached from a notification deep link via
    // `context.go(...)`, which replaces the whole stack — there is nothing to
    // pop back to. Combined with `PopScope(canPop: false)` above, a bare
    // `canPop()` check left the user trapped here after declining or after
    // the doctor cancelled. Fall back to home so there is always a way out.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  void dispose() {
    _ripple1.dispose();
    _ripple2.dispose();
    _ripple3.dispose();
    _pulseCtrl.dispose();
    _hapticTimer?.cancel();
    _sub?.cancel();
    CallNotificationService.stopRinging();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF050E2B), Color(0xFF0D1F4F), Color(0xFF0A1A3E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24)
                  .copyWith(top: 16, bottom: 32),
              child: Column(
                children: [
                  _buildTopBar(),
                  const Spacer(),
                  _buildAvatarWithRipples(),
                  const SizedBox(height: 24),
                  _buildDoctorInfo(),
                  const Spacer(),
                  _buildRingingLabel(),
                  const SizedBox(height: 28),
                  _buildActionButtons(),
                  const SizedBox(height: 16),
                  _buildActionLabels(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final pct = _countdown / 45;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _TypeChip(type: widget.consultationType),
        SizedBox(
          width: 54,
          height: 54,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: pct,
                strokeWidth: 3,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  pct > 0.5
                      ? Colors.greenAccent
                      : pct > 0.25
                          ? Colors.orangeAccent
                          : Colors.redAccent,
                ),
              ),
              Text(
                '$_countdown',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarWithRipples() {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _RippleRing(controller: _ripple1, delay: 0.0),
          _RippleRing(controller: _ripple2, delay: 0.33),
          _RippleRing(controller: _ripple3, delay: 0.66),
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                gradient: widget.doctorPhotoUrl.isEmpty
                    ? AppColors.primaryGradient
                    : null,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.55),
                    blurRadius: 30,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: widget.doctorPhotoUrl.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        widget.doctorPhotoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.medical_services_rounded,
                          color: Colors.white,
                          size: 52,
                        ),
                      ),
                    )
                  : const Icon(Icons.medical_services_rounded,
                      color: Colors.white, size: 52),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorInfo() {
    return Column(
      children: [
        const Text(
          'Incoming Consultation',
          style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.white54,
              letterSpacing: 1.2),
        ),
        const SizedBox(height: 8),
        Text(
          widget.doctorName,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3),
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

  Widget _buildRingingLabel() {
    return AnimatedBuilder(
      animation: _ripple1,
      builder: (_, __) {
        final opacity =
            (math.sin(_ripple1.value * math.pi * 2) * 0.4 + 0.6)
                .clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.ring_volume_rounded, color: Colors.white54, size: 13),
              SizedBox(width: 6),
              Text(
                'Incoming Call...',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Colors.white54,
                    letterSpacing: 1.0),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Decline
        _CallBtn(
          icon: Icons.call_end_rounded,
          color: const Color(0xFFE53935),
          size: 68,
          onTap: _declineCall,
        ),
        const SizedBox(width: 52),
        // Accept
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: CircularProgressIndicator(
                value: _countdown / 45,
                strokeWidth: 3.5,
                backgroundColor: Colors.white12,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
              ),
            ),
            _CallBtn(
              icon: Icons.call_rounded,
              color: const Color(0xFF00C853),
              size: 80,
              onTap: _acceptCall,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionLabels() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 68,
          child: Text('Decline',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: Colors.white38)),
        ),
        SizedBox(width: 52),
        SizedBox(
          width: 96,
          child: Text('Accept',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.white60,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _CallBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _CallBtn({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha:0.45),
              blurRadius: 22,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.43),
      ),
    );
  }
}

class _RippleRing extends StatelessWidget {
  final AnimationController controller;
  final double delay;

  const _RippleRing({required this.controller, required this.delay});

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
              color: AppColors.primary.withValues(alpha:opacity),
              width: 2.0,
            ),
          ),
        );
      },
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  IconData get _icon => type.toLowerCase().contains('audio')
      ? Icons.headset_mic_rounded
      : Icons.videocam_rounded;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha:0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha:0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, color: Colors.white70, size: 13),
          const SizedBox(width: 5),
          Text(
            type,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
