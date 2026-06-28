import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';
import 'agora_call_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/active_call_service.dart';

/// Patient-side video call screen.
///
/// Watches the Firestore consultation document to detect when the doctor
/// joins (status = 'active') and reacts to all terminal states:
///   ended / declined / missed / cancelled → post-call feedback then pop.
///
/// Reconnection: Agora's [onConnectionStateChanged] fires when the network
/// drops. We show a "Reconnecting…" banner and auto-resume when it recovers.
class VideoCallScreen extends StatefulWidget {
  final String callId;
  final String? doctorName;
  final String? doctorSpecialty;

  const VideoCallScreen({
    super.key,
    required this.callId,
    this.doctorName,
    this.doctorSpecialty,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen>
    with SingleTickerProviderStateMixin {
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _remoteJoined = false;
  bool _engineReady = false;
  bool _ending = false;
  bool _isReconnecting = false;
  int _callDuration = 0;

  int _networkQualityIndex = 0;
  bool _isAudioOnly = false;
  String? _agoraError;

  // Captured from Firestore so post-call screen gets correct doctor info
  String? _doctorId;
  String? _appointmentId;

  final _notesCtrl = TextEditingController();

  late AgoraCallService _agora;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  StreamSubscription<DocumentSnapshot>? _consultSub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _enableScreenProtection();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _agora = AgoraCallService(
      onRemoteJoined: (uid) {
        if (!mounted) return;
        setState(() => _remoteJoined = true);
        _startTimer();
      },
      onRemoteLeft: () {
        if (!mounted) return;
        setState(() => _remoteJoined = false);
      },
      onNetworkQualityChanged: (qualityIndex, audioOnly) {
        if (!mounted) return;
        setState(() {
          _networkQualityIndex = qualityIndex;
          _isAudioOnly = audioOnly;
        });
      },
      onConnectionStateChanged: (state) {
        if (!mounted) return;
        final reconnecting = state == ConnectionStateType.connectionStateReconnecting;
        setState(() => _isReconnecting = reconnecting);
      },
      onAgoraError: (code, msg) {
        if (!mounted) return;
        final label = code.index == 110
            ? 'Video auth failed — token required. Contact support.'
            : 'Video error (${code.index}): $msg';
        setState(() => _agoraError = label);
      },
    );
    _initAgora();
  }

  Future<void> _enableScreenProtection() async {
    try {
      // Android: FLAG_SECURE — blocks both screenshots and screen recordings at OS level
      await ScreenProtector.protectDataLeakageOn();
      // iOS: show a solid black overlay whenever the screen is being captured/recorded
      await ScreenProtector.protectDataLeakageWithColor(Colors.black);
      // Both platforms: prevent screenshots
      await ScreenProtector.preventScreenshotOn();
      // iOS: fire a warning snackbar if a screenshot is still attempted
      ScreenProtector.addListener(
        () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Screenshots are not allowed during consultations'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        },
        (isRecording) {
          debugPrint('[VideoCall] Screen recording detected: $isRecording');
        },
      );
    } catch (e) {
      debugPrint('[VideoCall] Screen protection error: $e');
    }
  }

  Future<void> _initAgora() async {
    await _agora.initialize();
    if (!mounted) return;
    setState(() => _engineReady = true);
    // Start the foreground service + cache the Flutter engine so Android does
    // not kill the process (or the Dart VM) if the user swipes from recents.
    await ActiveCallService.start(
      callId: widget.callId,
      callerName: widget.doctorName ?? 'Doctor',
    );
    // Handle "End Call" tapped in the persistent notification while in background.
    ActiveCallService.setEndCallFromNotificationHandler(() => _doEndCall());
    _watchConsultation();
  }

  void _watchConsultation() {
    _consultSub = FirebaseFirestore.instance
        .collection('consultations')
        .doc(widget.callId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data() ?? {};
      final status = data['status'] as String? ?? '';

      // Eagerly capture doctor ID and appointment ID for post-call use
      if (_doctorId == null) {
        final did = data['doctorId'] as String?;
        if (did != null && did.isNotEmpty) _doctorId = did;
      }
      if (_appointmentId == null) {
        final apptId = data['appointmentId'] as String?;
        if (apptId != null && apptId.isNotEmpty) _appointmentId = apptId;
      }

      // Doctor joined Agora → patient should join too
      if ((status == 'active' || status == 'ongoing') && !_agora.isJoined) {
        _agora.joinChannel(widget.callId);
      }

      // Terminal states
      if (_ending) return;
      switch (status) {
        case 'ended':
          _doEndCall(fromRemote: true);
        case 'declined':
        case 'rejected':
          _doEndCall(fromRemote: true, reason: 'Call was declined by the doctor.');
        case 'missed':
          _doEndCall(fromRemote: true, reason: 'No answer — missed call.');
        case 'cancelled':
          _doEndCall(fromRemote: true, reason: 'Consultation was cancelled.');
        default:
          break;
      }
    });
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _callDuration++);
      return _remoteJoined;
    });
  }

  String get _formattedDuration {
    final m = _callDuration ~/ 60;
    final s = _callDuration % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _networkQualityLabel {
    if (_isAudioOnly) return 'Audio';
    switch (_networkQualityIndex) {
      case 1:
      case 2:
        return 'HD';
      case 3:
        return 'SD';
      case 4:
      case 5:
        return 'LD';
      default:
        return 'HD';
    }
  }

  Color get _networkSignalColor {
    switch (_networkQualityIndex) {
      case 1:
      case 2:
        return const Color(0xFF4CAF50);
      case 3:
        return Colors.orange;
      case 4:
      case 5:
        return Colors.deepOrange;
      case 6:
        return Colors.red;
      default:
        return const Color(0xFF4CAF50);
    }
  }

  @override
  void dispose() {
    // Always detach the notification handler — the widget is gone.
    // We do NOT stop the foreground service here because dispose() is also
    // called when the Activity is destroyed by swipe-from-recents. The service
    // (and the cached Flutter engine) keep Agora alive. The service is stopped
    // only in _doEndCall() when the call is intentionally ended.
    ActiveCallService.clearEndCallFromNotificationHandler();
    _consultSub?.cancel();
    _pulseController.dispose();
    _notesCtrl.dispose();
    _agora.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    ScreenProtector.preventScreenshotOff();
    ScreenProtector.protectDataLeakageOff();
    ScreenProtector.protectDataLeakageWithColorOff();
    ScreenProtector.removeListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // During an active call, back button minimizes the app (like WhatsApp)
      // so the call continues via the foreground service notification.
      // Once _ending is true the call is over and normal back-navigation works.
      canPop: _ending,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_ending) {
          // Move app to background — the foreground service notification
          // stays visible so the user can return to the call at any time.
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _buildRemoteView(),
            _buildLocalPip(),
            _buildTopBar(),
            if (_isReconnecting) _buildReconnectBanner(),
            if (_agoraError != null) _buildAgoraErrorBanner(),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  // ── Remote view / waiting state ───────────────────────────────────────────

  Widget _buildRemoteView() {
    if (!_remoteJoined) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A0533), Color(0xFF0D1B3E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.primary.withValues(alpha:0.4),
                        blurRadius: 30,
                        spreadRadius: 10),
                  ],
                ),
                child: const Icon(Icons.person_rounded,
                    size: 64, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.doctorName ?? 'Doctor',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              widget.doctorSpecialty ?? '',
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, color: Colors.white60),
            ),
            const SizedBox(height: 16),
            const Text(
              'Waiting for doctor to join...',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: Colors.white54),
            ),
          ],
        ),
      );
    }
    if (!_engineReady) {
      return const Center(child: CircularProgressIndicator(color: Colors.white54));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: _agora.engine,
            canvas: VideoCanvas(
              uid: _agora.remoteUid ?? 0,
              renderMode: RenderModeType.renderModeHidden,
            ),
            connection: RtcConnection(channelId: widget.callId),
          ),
        ),
        if (_isAudioOnly)
          Container(
            color: Colors.black54,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 48),
                SizedBox(height: 12),
                Text(
                  'Poor network — audio only',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.white70),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Local PiP ─────────────────────────────────────────────────────────────

  Widget _buildLocalPip() {
    return Positioned(
      top: 60,
      right: 16,
      child: Container(
        width: 100,
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C3E),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: Colors.white.withValues(alpha:0.3), width: 2),
        ),
        child: _isCameraOff || _isAudioOnly
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isAudioOnly
                        ? Icons.wifi_off_rounded
                        : Icons.videocam_off_rounded,
                    color: Colors.white60,
                    size: 30,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isAudioOnly ? 'Audio Only' : 'Camera Off',
                    style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                        fontFamily: 'Poppins'),
                  ),
                ],
              )
            : _engineReady
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _agora.engine,
                        canvas: const VideoCanvas(
                          uid: 0,
                          renderMode: RenderModeType.renderModeHidden,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black.withValues(alpha:0.6), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha:0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(
                  Icons.signal_cellular_alt_rounded,
                  color: _remoteJoined ? _networkSignalColor : Colors.orange,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  _remoteJoined
                      ? '$_networkQualityLabel • $_formattedDuration'
                      : 'Connecting...',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            const Spacer(),
            _TopButton(
                icon: Icons.chat_rounded,
                onTap: () => _showChat(context)),
          ],
        ),
      ),
    );
  }

  // ── Reconnecting banner ───────────────────────────────────────────────────

  Widget _buildReconnectBanner() {
    return Positioned(
      top: 110,
      left: 16,
      right: 16,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha:0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 10),
            Text(
              'Reconnecting...',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // ── Agora error banner ────────────────────────────────────────────────────

  Widget _buildAgoraErrorBanner() {
    return Positioned(
      top: 110,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade700.withValues(alpha:0.92),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _agoraError ?? '',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _agoraError = null),
              child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom controls ───────────────────────────────────────────────────────

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, Colors.black.withValues(alpha:0.8)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.white.withValues(alpha:0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.note_alt_rounded,
                    color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Tap to add consultation notes',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'Poppins')),
                ),
                GestureDetector(
                  onTap: () => _showNotes(context),
                  child: const Text('Add',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CallButton(
                  icon: _isMuted
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  label: _isMuted ? 'Unmute' : 'Mute',
                  isActive: _isMuted,
                  onTap: () {
                    setState(() => _isMuted = !_isMuted);
                    _agora.muteLocalAudio(_isMuted);
                  },
                ),
                _CallButton(
                  icon: _isCameraOff
                      ? Icons.videocam_off_rounded
                      : Icons.videocam_rounded,
                  label: 'Camera',
                  isActive: _isCameraOff,
                  onTap: () {
                    setState(() => _isCameraOff = !_isCameraOff);
                    _agora.muteLocalVideo(_isCameraOff);
                  },
                ),
                _AnimatedTap(
                  heavy: true,
                  onTap: () => _confirmEnd(context),
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color:
                                const Color(0xFFE53935).withValues(alpha:0.5),
                            blurRadius: 20,
                            spreadRadius: 4),
                      ],
                    ),
                    child: const Icon(Icons.call_end_rounded,
                        color: Colors.white, size: 30),
                  ),
                ),
                _CallButton(
                  icon: _isSpeakerOn
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  label: 'Speaker',
                  isActive: !_isSpeakerOn,
                  onTap: () {
                    setState(() => _isSpeakerOn = !_isSpeakerOn);
                    _agora.setSpeakerphone(_isSpeakerOn);
                  },
                ),
                _CallButton(
                  icon: Icons.flip_camera_android_rounded,
                  label: 'Flip',
                  isActive: false,
                  onTap: () => _agora.switchCamera(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _confirmEnd(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('End Call?',
            style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text(
            'Are you sure you want to end this consultation?',
            style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _doEndCall();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935)),
            child: const Text('End Call'),
          ),
        ],
      ),
    );
  }

  Future<void> _doEndCall({
    bool fromRemote = false,
    String? reason,
  }) async {
    if (_ending) return;
    _ending = true;
    // Stop foreground service + release engine cache so the next cold start
    // creates a fresh Flutter engine (no stale call state).
    await ActiveCallService.stop();
    if (!fromRemote && widget.callId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('consultations')
            .doc(widget.callId)
            .update({
          'status': 'ended',
          'endedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[VideoCall] End-call status update failed: $e');
      }
    }
    // Always mark the linked appointment completed — idempotent even if doctor
    // side writes it at the same time.
    if (_appointmentId != null && _appointmentId!.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(_appointmentId!)
            .update({
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[VideoCall] Appointment complete failed: $e');
      }
    }
    if (mounted) setState(() { _engineReady = false; _remoteJoined = false; });
    await _agora.dispose();
    if (!mounted) return;
    _showPostCallSheet(context, reason: reason);
  }

  // ── Post-call feedback sheet ──────────────────────────────────────────────

  void _showPostCallSheet(BuildContext context, {String? reason}) {
    final wasMissedOrDeclined = reason != null;

    void goToFeedback() {
      context.go(AppRoutes.postConsultation, extra: {
        'consultationId': widget.callId,
        'doctorId': _doctorId ?? '',
        'doctorName': widget.doctorName ?? '',
        'doctorSpecialty': widget.doctorSpecialty ?? '',
        'type': 'immediate',
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            if (wasMissedOrDeclined) ...[
              const Icon(Icons.phone_missed_rounded,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(
                reason,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87),
              ),
            ] else ...[
              const Text('How was your consultation?',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Duration: $_formattedDuration',
                  style: const TextStyle(
                      fontFamily: 'Poppins', color: Colors.grey)),
              const SizedBox(height: 6),
              const Text('Tap a feeling or "Rate & Submit" to leave full feedback',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _FeedbackOption('😊', 'Better', AppColors.accent,
                      onTap: () {
                    Navigator.pop(sheetCtx);
                    goToFeedback();
                  }),
                  _FeedbackOption('😐', 'Same', Colors.orange, onTap: () {
                    Navigator.pop(sheetCtx);
                    goToFeedback();
                  }),
                  _FeedbackOption('😔', 'Worse', AppColors.error,
                      onTap: () {
                    Navigator.pop(sheetCtx);
                    goToFeedback();
                  }),
                ],
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  if (!wasMissedOrDeclined) {
                    goToFeedback();
                  } else {
                    context.go(AppRoutes.home);
                  }
                },
                child: Text(
                    wasMissedOrDeclined ? 'Close' : 'Rate & Submit'),
              ),
            ),
            if (!wasMissedOrDeclined) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  context.go(AppRoutes.home);
                },
                child: const Text('Skip for now',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Colors.grey)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Chat sheet ────────────────────────────────────────────────────────────

  void _showChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConsultationChat(callId: widget.callId),
    );
  }

  // ── Notes sheet ───────────────────────────────────────────────────────────

  void _showNotes(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Consultation Notes',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                controller: _notesCtrl,
                maxLines: 5,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Add notes about symptoms, diagnosis...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(sheetCtx);
                    final text = _notesCtrl.text.trim();
                    if (text.isEmpty || widget.callId.isEmpty) return;
                    try {
                      await FirebaseFirestore.instance
                          .collection('consultations')
                          .doc(widget.callId)
                          .update({'patientNotes': text});
                    } catch (_) {}
                  },
                  child: const Text('Save Notes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _FeedbackOption extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _FeedbackOption(this.emoji, this.label, this.color,
      {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha:0.3), width: 2),
            ),
            child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 28))),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

class _AnimatedTap extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool heavy;
  const _AnimatedTap(
      {required this.child, required this.onTap, this.heavy = false});

  @override
  State<_AnimatedTap> createState() => _AnimatedTapState();
}

class _AnimatedTapState extends State<_AnimatedTap>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 75),
      reverseDuration: const Duration(milliseconds: 130),
    );
    _scale = Tween<double>(begin: 1.0, end: widget.heavy ? 0.80 : 0.86)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) {
    widget.heavy
        ? HapticFeedback.mediumImpact()
        : HapticFeedback.lightImpact();
    _ctrl.forward();
  }

  void _up(TapUpDetails _) {
    _ctrl.reverse();
    widget.onTap();
  }

  void _cancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: _down,
        onTapUp: _up,
        onTapCancel: _cancel,
        child: ScaleTransition(scale: _scale, child: widget.child),
      );
}

class _TopButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _AnimatedTap(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha:0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _CallButton(
      {required this.icon,
      required this.label,
      required this.isActive,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _AnimatedTap(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withValues(alpha:0.3)
                  : Colors.white.withValues(alpha:0.15),
              shape: BoxShape.circle,
              border: isActive
                  ? Border.all(color: Colors.white, width: 1.5)
                  : null,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFamily: 'Poppins')),
        ],
      ),
    );
  }
}

// ── In-call Chat ──────────────────────────────────────────────────────────────

class _ConsultationChat extends StatefulWidget {
  final String callId;
  const _ConsultationChat({required this.callId});

  @override
  State<_ConsultationChat> createState() => _ConsultationChatState();
}

class _ConsultationChatState extends State<_ConsultationChat> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'patient';
  String get _chatPath => 'consultations/${widget.callId}/messages';

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    await FirebaseFirestore.instance.collection(_chatPath).add({
      'text': text,
      'senderId': _uid,
      'senderRole': 'patient',
      'timestamp': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle + header
          Container(
            width: 40, height: 4, margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.chat_rounded, color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('In-Call Chat',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.black54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Messages list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(_chatPath)
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, size: 40, color: Colors.black12),
                        SizedBox(height: 10),
                        Text('Start chatting during the call',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.black38)),
                      ],
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == _uid;
                    final text = data['text'] as String? ?? '';
                    final ts = data['timestamp'] as Timestamp?;
                    final time = ts != null
                        ? '${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                        : '';
                    final role = data['senderRole'] as String? ?? 'patient';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isMe) ...[
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha:0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                role == 'doctor' ? Icons.medical_services_rounded : Icons.person_rounded,
                                color: AppColors.primary, size: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Column(
                            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Container(
                                constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.65),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isMe ? AppColors.primary : const Color(0xFFF0F4FF),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                                    bottomRight: Radius.circular(isMe ? 4 : 16),
                                  ),
                                ),
                                child: Text(text,
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        color: isMe ? Colors.white : Colors.black87,
                                        height: 1.4)),
                              ),
                              const SizedBox(height: 3),
                              Text(time,
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 9, color: Colors.black38)),
                            ],
                          ),
                          if (isMe) const SizedBox(width: 8),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 8, offset: const Offset(0, -2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.black38),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                        color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
