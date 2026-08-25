import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/call_notification_service.dart';
import '../../../shared_core/providers/role_providers.dart';
import '../../auth/services/doctor_auth_service.dart';

class IncomingRequestScreen extends StatefulWidget {
  const IncomingRequestScreen({super.key});
  @override
  State<IncomingRequestScreen> createState() => _IncomingRequestScreenState();
}

class _IncomingRequestScreenState extends State<IncomingRequestScreen>
    with TickerProviderStateMixin {
  // ── Animations ──────────────────────────────────────────────────────────
  late AnimationController _ripple1;
  late AnimationController _ripple2;
  late AnimationController _ripple3;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ── State ────────────────────────────────────────────────────────────────
  int _countdown = 30;
  bool _accepted = false;
  bool _loading = true;
  bool _countdownActive = false;
  bool _alerted = false;

  String? _consultationId;
  String _patientName = 'Patient';
  String _patientPhotoUrl = '';
  String _chiefComplaint = '';
  String _consultationType = 'Video';

  StreamSubscription<QuerySnapshot>? _sub;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initAnimations();
    WakelockPlus.enable();
    _listenForPendingConsultation();
  }

  void _initAnimations() {
    // Three staggered ripple rings expanding outward
    _ripple1 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _ripple2 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..forward()
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _ripple2.repeat();
      });
    _ripple3 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..forward(from: 0.33)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _ripple3.repeat();
      });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _ripple2.forward(from: 0.33);
    });

    // Avatar gentle pulse
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.94, end: 1.06).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  // Maximum age for a pending consultation to be considered fresh.
  // Anything older was from a previous session / already timed out patient-side.
  static const _kFreshWindowSeconds = 90;

  void _listenForPendingConsultation() {
    final uid = DoctorAuthService.currentUid;
    var query = FirebaseFirestore.instance
        .collection('consultations')
        .where('status', isEqualTo: 'pending');
    if (uid != null) {
      query = query.where('doctorId', isEqualTo: uid);
    }
    _sub = query
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      if (!mounted || _accepted) return;

      // Skip local-cache emissions to avoid showing stale data from prior sessions.
      if (snap.metadata.isFromCache) return;

      if (snap.docs.isEmpty) {
        // No pending consultations — if we were showing one it was cancelled/expired.
        if (!_loading) {
          CallNotificationService.stopRinging();
          setState(() {
            _loading = true;
            _consultationId = null;
            _countdown = 30;
            _alerted = false;
          });
        }
        return;
      }

      final doc  = snap.docs.first;
      final data = doc.data();

      // Age guard: reject stale pending consultations that survived from a
      // previous session. Auto-mark them missed so Firestore is cleaned up.
      final createdAt = data['createdAt'];
      if (createdAt != null) {
        try {
          final created = (createdAt as Timestamp).toDate();
          if (DateTime.now().difference(created).inSeconds > _kFreshWindowSeconds) {
            // Auto-expire: mark missed so the patient sees "No Answer".
            FirebaseFirestore.instance
                .collection('consultations')
                .doc(doc.id)
                .update({
              'status': 'missed',
              'missedAt': FieldValue.serverTimestamp(),
            }).catchError((_) {});
            setState(() => _loading = true);
            return;
          }
        } catch (_) {}
      }

      final isNewCall = _consultationId != doc.id;
      setState(() {
        _consultationId = doc.id;
        _patientName = data['patientName'] as String? ?? 'Patient';
        _patientPhotoUrl = data['patientPhotoUrl'] as String? ?? '';
        _chiefComplaint = data['chiefComplaint'] as String? ?? '';
        _consultationType = data['consultationType'] as String? ?? 'Video';
        _loading = false;
        if (isNewCall) {
          _countdown = 30;
          _alerted = false;
        }
      });

      if (isNewCall && !_alerted) {
        _alerted = true;
        // Ring via the service (handles OS notification + system ringtone).
        CallNotificationService.startRinging();
      }
      _startCountdown();
    }, onError: (e) {
      debugPrint('[IncomingRequest] Consultation stream error: $e');
      if (mounted) setState(() => _loading = true);
    });
  }

  void _startCountdown() {
    if (_countdownActive) return;
    _countdownActive = true;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || _accepted || _consultationId == null) {
        _countdownActive = false;
        return false;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        _countdownActive = false;
        await _markMissed();
        _safeClose();
        return false;
      }
      return true;
    });
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _acceptCall() async {
    if (_consultationId == null) return;
    setState(() => _accepted = true);
    // Block role switching from the moment the doctor accepts through the
    // handoff into DoctorVideoCallScreen (which owns this flag for the rest
    // of the call — see its initState/dispose).
    ProviderScope.containerOf(context, listen: false)
        .read(criticalOperationInProgressProvider.notifier)
        .state = true;
    HapticFeedback.heavyImpact();
    await CallNotificationService.cancelAll();
    // Set status to 'ongoing' so the patient's OutgoingCallScreen knows
    // the doctor has accepted and is about to join Agora.
    // DoctorVideoCallScreen will update to 'active' once Agora is joined.
    await FirebaseFirestore.instance
        .collection('consultations')
        .doc(_consultationId!)
        .update({
      'status': 'ongoing',
      'ringingAt': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    context.push(AppRoutes.videoCall, extra: {
      'consultationId': _consultationId!,
      'patientName': _patientName,
    });
  }

  Future<void> _declineCall() async {
    if (_accepted) return;
    _accepted = true;
    HapticFeedback.mediumImpact();
    await CallNotificationService.cancelAll();
    if (_consultationId != null) {
      await FirebaseFirestore.instance
          .collection('consultations')
          .doc(_consultationId!)
          .update({
        'status': 'declined',
        'declinedAt': FieldValue.serverTimestamp(),
      });
    }
    _safeClose();
  }

  Future<void> _markMissed() async {
    if (_consultationId == null || _accepted) return;
    await FirebaseFirestore.instance
        .collection('consultations')
        .doc(_consultationId!)
        .update({
      'status': 'missed',
      'missedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Leaves this screen safely.
  ///
  /// This screen is routed to with `context.go(AppRoutes.incomingRequest)`
  /// from the FCM tap handler and the global call listener in `main.dart`,
  /// both of which replace the whole navigation stack. A bare `context.pop()`
  /// then has nothing to pop and throws, leaving the doctor stranded on the
  /// request screen after declining/missing a call. Fall back to the
  /// dashboard in that case.
  void _safeClose() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.dashboard);
    }
  }

  @override
  void dispose() {
    _ripple1.dispose();
    _ripple2.dispose();
    _ripple3.dispose();
    _pulseCtrl.dispose();
    _sub?.cancel();
    CallNotificationService.stopRinging();
    WakelockPlus.disable();
    // Safety net for the decline/missed/error paths, which pop this screen
    // without ever reaching DoctorVideoCallScreen. When accept *does*
    // succeed, DoctorVideoCallScreen's own dispose is what actually clears
    // this by the time the call ends — re-clearing it here afterwards is
    // harmless.
    ProviderScope.containerOf(context, listen: false)
        .read(criticalOperationInProgressProvider.notifier)
        .state = false;
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF050E2B), Color(0xFF0D1F4F), Color(0xFF0A1A3E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: _loading ? _buildWaiting() : _buildIncomingCall(),
      ),
    );
  }

  // ── Waiting state ────────────────────────────────────────────────────────

  Widget _buildWaiting() {
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _PulsingDot(),
          const SizedBox(height: 28),
          Text(
            'Waiting for patient requests...',
            style: AppTextStyles.body.copyWith(
                color: Colors.white60, letterSpacing: 0.2),
          ),
          const SizedBox(height: 40),
          TextButton.icon(
            onPressed: _safeClose,
            icon: const Icon(Icons.arrow_back_rounded,
                color: Colors.white38, size: 18),
            label: Text('Go Back',
                style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 13, color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  // ── Incoming call UI ─────────────────────────────────────────────────────

  Widget _buildIncomingCall() {
    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 24).copyWith(top: 16, bottom: 32),
        child: Column(
          children: [
            _buildTopBar(),
            const Spacer(),
            _buildAvatarWithRipples(),
            const SizedBox(height: 24),
            _buildPatientInfo(),
            const SizedBox(height: 20),
            _buildComplaintCard(),
            const Spacer(),
            _buildRingingLabel(),
            const SizedBox(height: 28),
            _buildActionButtons(),
            const SizedBox(height: 16),
            _buildActionLabels(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final pct = _countdown / 30;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Consultation type chip
        _TypeChip(type: _consultationType),
        // Countdown ring
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
                style: AppTextStyles.labelMedium.copyWith(
                    fontWeight: FontWeight.w700, color: Colors.white),
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
          // Three expanding ripple rings
          _RippleRing(controller: _ripple1, delay: 0.0),
          _RippleRing(controller: _ripple2, delay: 0.33),
          _RippleRing(controller: _ripple3, delay: 0.66),
          // Pulsing avatar with patient initials
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.55),
                    blurRadius: 30,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: _patientPhotoUrl.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        _patientPhotoUrl,
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Center(child: _buildAvatarFallback()),
                      ),
                    )
                  : Center(child: _buildAvatarFallback()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarFallback() {
    return _patientName.isNotEmpty
        ? Text(
            _patientName
                .trim()
                .split(' ')
                .take(2)
                .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
                .join(),
            style: AppTextStyles.display.copyWith(
              fontSize: 38,
              color: Colors.white,
              height: 1,
            ),
          )
        : const Icon(Icons.person_rounded, color: Colors.white, size: 58);
  }

  Widget _buildPatientInfo() {
    return Column(
      children: [
        Text(
          'Incoming Consultation',
          style: AppTextStyles.caption.copyWith(
              fontSize: 12, color: Colors.white54, letterSpacing: 1.2),
        ),
        const SizedBox(height: 8),
        Text(
          _patientName,
          textAlign: TextAlign.center,
          style: AppTextStyles.display.copyWith(
              fontSize: 28, color: Colors.white, letterSpacing: -0.3),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_rounded, color: Colors.white38, size: 14),
            const SizedBox(width: 4),
            Text(
              '$_consultationType Call',
              style: AppTextStyles.caption.copyWith(
                  fontSize: 12, color: Colors.white38),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildComplaintCard() {
    if (_chiefComplaint.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha:0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha:0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.medical_information_rounded,
                color: Colors.white70, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chief Complaint',
                  style: AppTextStyles.caption.copyWith(
                      fontSize: 10, color: Colors.white38, letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  _chiefComplaint,
                  style: AppTextStyles.labelMedium.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha:0.87)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRingingLabel() {
    return AnimatedBuilder(
      animation: _ripple1,
      builder: (_, __) {
        final opacity =
            (math.sin(_ripple1.value * math.pi * 2) * 0.4 + 0.6).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.ring_volume_rounded, color: Colors.white54, size: 13),
              const SizedBox(width: 6),
              Text(
                'Ringing...',
                style: AppTextStyles.caption.copyWith(
                    fontSize: 12, color: Colors.white54, letterSpacing: 1.0),
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
        _CallButton(
          icon: Icons.call_end_rounded,
          color: const Color(0xFFE53935),
          glowColor: const Color(0xFFE53935),
          size: 68,
          onTap: _declineCall,
        ),
        const SizedBox(width: 52),
        // Accept — larger, with countdown ring around it
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: CircularProgressIndicator(
                value: _countdown / 30,
                strokeWidth: 3.5,
                backgroundColor: Colors.white12,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
              ),
            ),
            _CallButton(
              icon: Icons.call_rounded,
              color: const Color(0xFF00C853),
              glowColor: const Color(0xFF00C853),
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
                  fontFamily: 'Inter', fontSize: 11, color: Colors.white38)),
        ),
        SizedBox(width: 52),
        SizedBox(
          width: 96,
          child: Text('Accept',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  color: Colors.white60,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ── Reusable widgets ─────────────────────────────────────────────────────────

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color glowColor;
  final double size;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.color,
    required this.glowColor,
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
              color: glowColor.withValues(alpha:0.45),
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

/// Expanding ripple ring animation.
class _RippleRing extends StatelessWidget {
  final AnimationController controller;
  final double delay;

  const _RippleRing({required this.controller, required this.delay});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        // Offset the progress by delay so rings are staggered
        final progress = ((controller.value + delay) % 1.0);
        final size = 110.0 + (90.0 * progress);
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

/// Consultation type badge (Video / Audio / Chat).
class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  IconData get _icon => type.toLowerCase().contains('audio')
      ? Icons.headset_mic_rounded
      : type.toLowerCase().contains('chat')
          ? Icons.chat_bubble_outline_rounded
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
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// Three bouncing dots shown while waiting for a consultation.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final phase = (_ctrl.value - i * 0.15).clamp(0.0, 1.0);
            final scale = 0.6 + 0.4 * math.sin(phase * math.pi * 2).abs();
            return Transform.scale(
              scale: scale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.white30,
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
