import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_protector/screen_protector.dart';
import '../services/agora_call_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/active_call_service.dart';
import '../../../features/notifications/services/notification_service.dart';
import '../../../shared_core/providers/role_providers.dart';

class DoctorVideoCallScreen extends StatefulWidget {
  final String consultationId;
  final String patientName;

  const DoctorVideoCallScreen({
    super.key,
    required this.consultationId,
    this.patientName = 'Patient',
  });

  @override
  State<DoctorVideoCallScreen> createState() => _DoctorVideoCallScreenState();
}

class _DoctorVideoCallScreenState extends State<DoctorVideoCallScreen>
    with SingleTickerProviderStateMixin {
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _showNotes = false;

  /// All remote uids currently in the channel — besides the account holder
  /// who booked (uid 2), a family member the appointment was booked for can
  /// also be on this call as a guest (uid 3, see AgoraCallService/
  /// generateAgoraToken).
  Set<int> _remoteUids = {};
  bool get _remoteJoined => _remoteUids.isNotEmpty;
  String? _bookedByName;
  bool _engineReady = false;
  bool _isReconnecting = false;
  int _networkQualityIndex = 0;
  bool _isAudioOnly = false;
  String? _agoraError;

  // Pre-join lobby (Google Meet-style): request camera/mic permission and
  // preview the local camera before actually publishing/joining the channel.
  bool _inLobby = true;
  bool _lobbyLoading = true;
  bool _permissionsBlocked = false;

  /// True once the patient has joined at least once during this session.
  /// Prescription access and post-call routing depend on this flag.
  bool _patientJoinedAtLeastOnce = false;

  /// Guards _doEndCall against concurrent/re-entrant invocations.
  bool _endCallLock = false;

  int _callDuration = 0;

  // Patient info loaded from the consultation document
  String? _patientId;
  String _consultPatientName = 'Patient';
  String? _appointmentId;

  late AgoraCallService _agora;
  final _notesCtrl = TextEditingController();
  StreamSubscription<DocumentSnapshot>? _consultSub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Owns criticalOperationInProgressProvider for the full duration of the
    // call — covers both video and audio-only (the latter is a
    // network-degradation mode of this same screen, see _isAudioOnly).
    // IncomingRequestScreen/DoctorOutgoingCallScreen already set this true
    // before the doctor lands here; re-asserting it is idempotent.
    ProviderScope.containerOf(context, listen: false)
        .read(criticalOperationInProgressProvider.notifier)
        .state = true;
    _enableScreenProtection();
    _agora = AgoraCallService(
      onRemoteJoined: (uid) {
        if (!mounted) return;
        final isFirst = _remoteUids.isEmpty;
        setState(() {
          _remoteUids = {..._remoteUids, uid};
          _patientJoinedAtLeastOnce = true;
        });
        if (isFirst) _startTimer();
      },
      onRemoteLeft: (uid) {
        if (!mounted) return;
        setState(() => _remoteUids = {..._remoteUids}..remove(uid));
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
        setState(() => _isReconnecting =
            state == ConnectionStateType.connectionStateReconnecting);
      },
      onAgoraError: (code, msg) {
        if (!mounted) return;
        final label = code.index == 110
            ? 'Video auth failed — token required. Contact support.'
            : 'Video error (${code.index}): $msg';
        setState(() => _agoraError = label);
      },
    );
    _initLobbyPreview();
    _watchConsultation();
  }

  /// Requests camera/mic permission and starts the local preview for the
  /// pre-join lobby. Does NOT join the Agora channel yet — that only
  /// happens once the doctor taps "Join call" in [_joinCall].
  Future<void> _initLobbyPreview() async {
    try {
      final statuses = await _agora
          .requestPermissions()
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final camGranted = statuses[Permission.camera]?.isGranted ?? false;
      final micGranted = statuses[Permission.microphone]?.isGranted ?? false;

      if (!camGranted && !micGranted) {
        setState(() {
          _permissionsBlocked = true;
          _lobbyLoading = false;
        });
        return;
      }

      await _agora.initialize().timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (!camGranted) {
        _isCameraOff = true;
        await _agora.muteLocalVideo(true);
      }
      if (!micGranted) {
        _isMuted = true;
        await _agora.muteLocalAudio(true);
      }
      if (!mounted) return;
      setState(() {
        _permissionsBlocked = false;
        _engineReady = true;
        _lobbyLoading = false;
      });
    } catch (e) {
      debugPrint('[DoctorVideoCall] Lobby preview init failed: $e');
      if (!mounted) return;
      setState(() {
        _agoraError = 'Could not start camera preview. Please try again.';
        _lobbyLoading = false;
      });
    }
  }

  /// Called when the doctor taps "Join call" in the lobby — actually
  /// connects to the Agora channel and flips the consultation to 'active'
  /// so the patient's listener knows to join too.
  Future<void> _joinCall() async {
    setState(() => _inLobby = false);
    try {
      // Start foreground service + cache the Flutter engine so Android does not
      // kill the process (or Dart VM) if the doctor swipes from recents mid-call.
      await ActiveCallService.start(
        callId: widget.consultationId,
        callerName: widget.patientName,
      );
      ActiveCallService.setEndCallFromNotificationHandler(() => _doEndCall());
      await _agora.joinChannel(widget.consultationId);
    } catch (e) {
      debugPrint('[DoctorVideoCall] Agora join failed: $e');
      if (!mounted) return;
      setState(() => _agoraError = 'Could not start the video call. Please try again.');
      return;
    }
    // Signal the patient app to join by setting status to 'active'.
    // The patient's Firestore listener watches for this exact status change.
    try {
      await FirebaseFirestore.instance
          .collection('consultations')
          .doc(widget.consultationId)
          .update({'status': 'active'});
    } catch (e) {
      debugPrint('[DoctorVideoCall] Active status update failed: $e');
    }
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
          debugPrint('[DoctorVideoCall] Screen recording detected: $isRecording');
        },
      );
    } catch (e) {
      debugPrint('[DoctorVideoCall] Screen protection error: $e');
    }
  }

  void _watchConsultation() {
    _consultSub = FirebaseFirestore.instance
        .collection('consultations')
        .doc(widget.consultationId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data();
      if (data == null) return;

      // Always capture patient info — must happen regardless of _endCallLock
      // so _patientId is ready before _doEndCall navigates.
      if (_patientId == null) {
        final pid = data['patientId'] as String?;
        final pname = data['patientName'] as String? ?? widget.patientName;
        if (pid != null && pid.isNotEmpty) {
          if (mounted) {
            setState(() {
              _patientId = pid;
              _consultPatientName = pname;
            });
          }
        }
      }
      if (_appointmentId == null) {
        final apptId = data['appointmentId'] as String?;
        if (apptId != null && apptId.isNotEmpty) {
          if (mounted) {
            setState(() => _appointmentId = apptId);
          }
          _loadBookedByName(apptId);
        }
      }

      // Only react to remote 'ended' — ignore the echo of our own update
      final status = data['status'] as String? ?? '';
      if (status == 'ended' && !_endCallLock) {
        _doEndCall(fromRemote: true);
      }
    }, onError: (e) {
      debugPrint('[VideoCall] Consultation watch error: $e');
    });
  }

  // The account holder who booked this appointment — distinct from
  // `_consultPatientName` (whoever the appointment is actually FOR, which
  // may be a family member) — used to label their video tile when both
  // they and a guest family member are on this call at once.
  Future<void> _loadBookedByName(String appointmentId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appointmentId)
          .get();
      final name = (snap.data()?['bookedByName'] as String?)?.trim();
      if (mounted && name != null && name.isNotEmpty) {
        setState(() => _bookedByName = name);
      }
    } catch (_) {}
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

  @override
  void dispose() {
    // Detach the notification handler — widget is gone.
    // Do NOT stop the foreground service here: dispose() is also called when
    // the Activity is destroyed by swipe-from-recents. The cached engine +
    // service keep Agora alive. The service is stopped only in _doEndCall().
    ActiveCallService.clearEndCallFromNotificationHandler();
    // The call is over (or this screen is being torn down some other way) —
    // role switching is safe again.
    ProviderScope.containerOf(context, listen: false)
        .read(criticalOperationInProgressProvider.notifier)
        .state = false;
    _consultSub?.cancel();
    _notesCtrl.dispose();
    // Only dispose Agora if _doEndCall hasn't already done it
    if (!_endCallLock) _agora.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    ScreenProtector.preventScreenshotOff();
    ScreenProtector.protectDataLeakageOff();
    ScreenProtector.protectDataLeakageWithColorOff();
    ScreenProtector.removeListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_inLobby) return _buildLobby();
    return PopScope(
      // During an active call, back button minimizes the app (like WhatsApp).
      // Once _endCallLock is true the call is over and normal navigation works.
      canPop: _endCallLock,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_endCallLock) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _buildRemoteView(),
            _buildLocalPip(),
            if (_showNotes) _buildNotesPanel(),
            _buildTopBar(context),
            if (_isReconnecting) _buildReconnectBanner(),
            if (_agoraError != null) _buildAgoraErrorBanner(),
            _buildBottomControls(context),
          ],
        ),
      ),
    );
  }

  // ── Pre-join lobby (Google Meet-style) ────────────────────────────────────

  Widget _buildLobby() {
    if (_permissionsBlocked) {
      return Scaffold(
        backgroundColor: const Color(0xFF14141C),
        body: Stack(
          children: [
            _buildLobbyPermissionBlocked(),
            _buildLobbyTopBar(),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildLobbyPreview(),
          _buildLobbyTopBar(),
          if (_agoraError != null) _buildAgoraErrorBanner(),
          _buildLobbyBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildLobbyPreview() {
    if (_lobbyLoading || !_engineReady) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF1A0533), Color(0xFF0D1B3E)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
      );
    }
    if (_isCameraOff) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF1A0533), Color(0xFF0D1B3E)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter),
        ),
        child: Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient, shape: BoxShape.circle),
            child: const Icon(Icons.videocam_off_rounded,
                size: 48, color: Colors.white),
          ),
        ),
      );
    }
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _agora.engine,
        canvas: const VideoCanvas(
          uid: 0,
          renderMode: RenderModeType.renderModeHidden,
        ),
      ),
    );
  }

  Widget _buildLobbyPermissionBlocked() {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.08),
                shape: BoxShape.circle),
            child: const Icon(Icons.videocam_off_rounded,
                color: Colors.white54, size: 36),
          ),
          const SizedBox(height: 20),
          const Text(
            'Camera & microphone access needed',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'Allow access so the patient can see and hear you during the consultation.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: Colors.white60,
                height: 1.4),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => openAppSettings(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Open Settings',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              setState(() => _lobbyLoading = true);
              _initLobbyPreview();
            },
            child: const Text('Try again',
                style: TextStyle(fontFamily: 'Inter', color: Colors.white60)),
          ),
        ],
      ),
    );
  }

  Widget _buildLobbyTopBar() {
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
              end: Alignment.bottomCenter),
        ),
        child: Row(children: [
          _TopBtn(Icons.arrow_back_rounded,
              () => Navigator.of(context).maybePop(),
              tooltip: 'Back'),
        ]),
      ),
    );
  }

  Widget _buildLobbyBottomPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [Colors.transparent, Colors.black.withValues(alpha:0.85)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.patientName,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
            const SizedBox(height: 6),
            const Text(
              'Ready to join the consultation?',
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CallBtn(
                  _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  _isMuted ? 'Unmute' : 'Mute',
                  _isMuted,
                  () {
                    setState(() => _isMuted = !_isMuted);
                    _agora.muteLocalAudio(_isMuted);
                  },
                ),
                const SizedBox(width: 28),
                _CallBtn(
                  _isCameraOff
                      ? Icons.videocam_off_rounded
                      : Icons.videocam_rounded,
                  'Camera',
                  _isCameraOff,
                  () {
                    setState(() => _isCameraOff = !_isCameraOff);
                    _agora.muteLocalVideo(_isCameraOff);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_lobbyLoading || _agoraError != null)
                    ? null
                    : _joinCall,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha:0.4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _lobbyLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Join call',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteView() {
    if (!_remoteJoined) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF1A0533), Color(0xFF0D1B3E)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha:0.4),
                      blurRadius: 30,
                      spreadRadius: 10)
                ]),
            child: const Icon(Icons.person_rounded,
                size: 64, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(widget.patientName,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Waiting for patient to join...',
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 13, color: Colors.white54)),
        ]),
      );
    }
    if (!_agora.isInitialized) return const SizedBox.expand();
    // Whether a family member the appointment was booked for has also
    // joined as a guest (uid 3) — the only other remote possible here
    // besides the booking account holder (uid 2), since "self" (uid 1) is
    // this doctor's own device.
    final hasGuest = _remoteUids.contains(3);
    if (!hasGuest) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _agora.engine,
          canvas: VideoCanvas(
            uid: _remoteUids.isEmpty ? 0 : _remoteUids.first,
            renderMode: RenderModeType.renderModeHidden,
          ),
          connection: RtcConnection(channelId: widget.consultationId),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: _buildLabeledRemoteTile(uid: 2, label: _bookedByName ?? 'Patient'),
        ),
        Container(height: 2, color: Colors.black),
        Expanded(
          child: _buildLabeledRemoteTile(uid: 3, label: _consultPatientName),
        ),
      ],
    );
  }

  // A single tile in the 2-remote (booking account holder + guest family
  // member) layout — used only once a guest has actually joined; the
  // ordinary single-patient case above keeps the original full-bleed view.
  Widget _buildLabeledRemoteTile({required int uid, required String label}) {
    final joined = _remoteUids.contains(uid);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF1A0533)),
        if (joined)
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _agora.engine,
              canvas: VideoCanvas(uid: uid, renderMode: RenderModeType.renderModeHidden),
              connection: RtcConnection(channelId: widget.consultationId),
            ),
          )
        else
          const Center(child: CircularProgressIndicator(color: Colors.white54)),
        Positioned(
          left: 10,
          bottom: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

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
          border: Border.all(color: Colors.white.withValues(alpha:0.3), width: 2),
        ),
        child: _isCameraOff
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_off_rounded,
                      color: Colors.white60, size: 30),
                  SizedBox(height: 4),
                  Text('Camera Off',
                      style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          fontFamily: 'Inter')),
                ],
              )
            : _engineReady
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _agora.engine,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    ),
                  )
                : const SizedBox(),
      ),
    );
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

  Widget _buildReconnectBanner() {
    return Positioned(
      top: 110,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgoraErrorBanner() {
    return Positioned(
      top: _isReconnecting ? 164 : 110,
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
                    fontFamily: 'Inter',
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

  Widget _buildNotesPanel() {
    return Positioned(
      top: 60,
      left: 16,
      right: 130,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha:0.8),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Consultation Notes',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            maxLines: 4,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'Inter', fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Symptoms, diagnosis...',
              hintStyle:
                  const TextStyle(color: Colors.white38, fontSize: 12),
              fillColor: Colors.white.withValues(alpha:0.1),
              filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
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
              end: Alignment.bottomCenter),
        ),
        child: Row(children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha:0.4),
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.signal_cellular_alt_rounded,
                  color: _remoteJoined ? _networkSignalColor : Colors.orange,
                  size: 14),
              const SizedBox(width: 4),
              Text(
                _remoteJoined
                    ? '$_networkQualityLabel • $_formattedDuration'
                    : 'Connecting...',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600),
              ),
            ]),
          ),
          const Spacer(),
          _TopBtn(Icons.chat_rounded,
              () => _showChat(context),
              tooltip: 'Chat'),
          const SizedBox(width: 8),
          _TopBtn(Icons.note_alt_rounded,
              () => setState(() => _showNotes = !_showNotes),
              tooltip: 'Consultation notes'),
          const SizedBox(width: 8),
          _TopBtn(Icons.medical_information_rounded, () {
            if (_patientId != null && _patientId!.isNotEmpty) {
              context.push(AppRoutes.patientDetail, extra: {
                'patientId': _patientId!,
                'patientName': _consultPatientName,
              });
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Patient details are still loading…'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
              tooltip: 'Patient history',
              enabled: _patientId != null && _patientId!.isNotEmpty),
        ]),
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context) {
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
              end: Alignment.bottomCenter),
        ),
        child: Column(children: [
          // ── Prescription status banner ──────────────────────────────────
          _buildPrescriptionBanner(context),
          const SizedBox(height: 20),
          // ── Call control buttons ────────────────────────────────────────
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _CallBtn(
              _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              _isMuted ? 'Unmuted' : 'Mute',
              _isMuted,
              () {
                setState(() => _isMuted = !_isMuted);
                _agora.muteLocalAudio(_isMuted);
              },
            ),
            _CallBtn(
              _isCameraOff
                  ? Icons.videocam_off_rounded
                  : Icons.videocam_rounded,
              'Camera',
              _isCameraOff,
              () {
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
                          spreadRadius: 4)
                    ]),
                child: const Icon(Icons.call_end_rounded,
                    color: Colors.white, size: 30),
              ),
            ),
            _CallBtn(
              _isSpeakerOn
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              'Speaker',
              !_isSpeakerOn,
              () {
                setState(() => _isSpeakerOn = !_isSpeakerOn);
                _agora.setSpeakerphone(_isSpeakerOn);
              },
            ),
            _CallBtn(
              Icons.flip_camera_android_rounded,
              'Flip',
              false,
              () => _agora.switchCamera(),
            ),
          ]),
        ]),
      ),
    );
  }

  /// Shows either a waiting-for-patient notice or the end-and-prescribe shortcut.
  /// The "End & Prescribe" action goes through _confirmEnd — never bypasses it —
  /// so the call is always properly terminated before reaching the prescription screen.
  Widget _buildPrescriptionBanner(BuildContext context) {
    if (!_patientJoinedAtLeastOnce) {
      // Patient has not joined yet — prescription is locked
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha:0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha:0.3))),
        child: const Row(children: [
          Icon(Icons.lock_clock_rounded, color: Colors.orangeAccent, size: 16),
          SizedBox(width: 8),
          Expanded(
              child: Text(
            'Prescription locked — waiting for patient to join',
            style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 11,
                fontFamily: 'Inter'),
          )),
        ]),
      );
    }

    // Patient has joined at least once — show the shortcut
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.receipt_long_rounded,
            color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        const Expanded(
            child: Text('End call to write prescription',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: 'Inter'))),
        GestureDetector(
          onTap: () => _confirmEnd(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha:0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('End & Prescribe',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  void _showChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DoctorConsultationChat(
        consultationId: widget.consultationId,
        patientName: _consultPatientName,
      ),
    );
  }

  void _confirmEnd(BuildContext context) {
    if (_endCallLock) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('End Consultation?',
            style: TextStyle(
                fontFamily: 'Inter', fontWeight: FontWeight.w700)),
        content: Text(
          _patientJoinedAtLeastOnce
              ? 'The call will be ended and you can write a prescription for this patient.'
              : 'The patient has not joined yet. The consultation will be marked as ended.',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(fontFamily: 'Inter'))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _doEndCall();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935)),
            child: Text(
              _patientJoinedAtLeastOnce ? 'End & Write Prescription' : 'End Call',
              style: const TextStyle(fontFamily: 'Inter'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _doEndCall({bool fromRemote = false}) async {
    // Re-entry guard: prevents double-disposal and double-navigation
    if (_endCallLock) return;
    _endCallLock = true;
    // WhatsApp-style group-call semantics: the doctor leaving only ends the
    // consultation record for everyone once the channel is otherwise empty
    // (no patient/guest still connected) — read before `_agora.dispose()`
    // below clears it. The doctor's own notes/prescription/follow-up
    // workflow below still always runs on the doctor's own departure,
    // regardless of who else remains — only the *shared* Firestore status
    // is gated on being the last one out.
    final isLastToLeave = _agora.remoteUids.isEmpty;
    // Stop foreground service + release engine cache so the next cold start
    // creates a fresh Flutter engine (no stale call state).
    await ActiveCallService.stop();

    final consultRef = FirebaseFirestore.instance
        .collection('consultations')
        .doc(widget.consultationId);

    try {
      if (!fromRemote) {
        // Doctor is actively ending — update Firestore status once nobody
        // else is left on the call; always save notes regardless.
        final updates = <String, dynamic>{
          if (_notesCtrl.text.isNotEmpty) 'doctorNotes': _notesCtrl.text,
        };
        if (isLastToLeave) {
          updates['status'] = 'ended';
          updates['endedAt'] = FieldValue.serverTimestamp();
        }
        if (updates.isNotEmpty) {
          await consultRef.update(updates);
        }
      } else if (_notesCtrl.text.isNotEmpty) {
        // Remote ended (call closed out by someone else) — preserve notes
        await consultRef.update({'doctorNotes': _notesCtrl.text});
      }
    } catch (e) {
      debugPrint('[DoctorVideoCall] End-call Firestore update failed: $e');
      if (mounted && _notesCtrl.text.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Consultation notes could not be saved.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }

    // Mark the linked appointment completed once the visit is actually over
    // for everyone: either another party already closed it out (fromRemote —
    // the Firestore status change is the authoritative signal) or the doctor
    // is the last one leaving. Idempotent even if another party's leave races this.
    if ((fromRemote || isLastToLeave) &&
        _appointmentId != null &&
        _appointmentId!.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(_appointmentId!)
            .update({
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[DoctorVideoCall] Appointment complete failed: $e');
      }
    }

    // Fire-and-forget post-consultation notifications — only if the patient
    // actually joined at some point. Otherwise there was no real
    // consultation (missed/declined/cancelled before connecting), so a
    // "Consultation Complete — how are you feeling?" push would be false.
    if (_patientJoinedAtLeastOnce) {
      _sendPatientFollowups(consultRef);
    }

    // Tear down Agora before navigating to prevent black-screen / engine leaks
    if (mounted) setState(() => _engineReady = false);
    await _agora.dispose();

    if (!mounted) return;

    if (_patientJoinedAtLeastOnce && (_patientId?.isNotEmpty ?? false)) {
      // Go to dashboard first (clears video-call from the stack), then push
      // prescription on top so the back button returns to dashboard and the
      // extra params are not subject to go_router's refreshListenable rebuild.
      context.go(AppRoutes.dashboard);
      final pid        = _patientId!;
      final pname      = _consultPatientName;
      final consultId  = widget.consultationId;
      final apptId     = _appointmentId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.push(AppRoutes.prescription, extra: {
          'patientId':       pid,
          'patientName':     pname,
          'consultationId':  consultId,
          'appointmentId':   apptId,
          'sessionValidated': true,
        });
      });
    } else {
      // Patient never joined, or patient ID unknown — go back to dashboard
      context.go(AppRoutes.dashboard);
    }
  }

  Future<void> _sendPatientFollowups(
      DocumentReference<Map<String, dynamic>> consultRef) async {
    try {
      final snap = await consultRef.get();
      final data = snap.data();
      if (data == null) return;

      final patientId = data['patientId'] as String?;
      if (patientId == null || patientId.isEmpty) return;

      final patientName = data['patientName'] as String? ?? 'Patient';
      final doctorName = data['doctorName'] as String? ?? 'your doctor';
      final doctorSpecialty = data['doctorSpecialty'] as String? ?? 'General';

      await NotificationService.schedulePostConsultationNotifications(
        patientId: patientId,
        patientName: patientName,
        doctorName: doctorName,
        doctorSpecialty: doctorSpecialty,
        consultationId: widget.consultationId,
      );
    } catch (e) {
      debugPrint('[DoctorVideoCall] Post-consultation notification failed: $e');
    }
  }
}

// ── Animated tap wrapper — scale + haptic on every press ─────────────────────
class _AnimatedTap extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool heavy;
  const _AnimatedTap({required this.child, required this.onTap, this.heavy = false});

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

class _TopBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool enabled;
  const _TopBtn(this.icon, this.onTap,
      {required this.tooltip, this.enabled = true});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        child: Tooltip(
          message: tooltip,
          child: _AnimatedTap(
            onTap: onTap,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: enabled ? 0.4 : 0.25),
                  shape: BoxShape.circle),
              child: Icon(icon,
                  color: enabled ? Colors.white : Colors.white38, size: 18),
            ),
          ),
        ),
      );
}

class _CallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _CallBtn(this.icon, this.label, this.isActive, this.onTap);

  @override
  Widget build(BuildContext context) => _AnimatedTap(
        onTap: onTap,
        child: Column(children: [
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
                    : null),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFamily: 'Inter')),
        ]),
      );
}

// ── Doctor In-Call Chat ───────────────────────────────────────────────────────

class _DoctorConsultationChat extends StatefulWidget {
  final String consultationId;
  final String patientName;
  const _DoctorConsultationChat({
    required this.consultationId,
    required this.patientName,
  });

  @override
  State<_DoctorConsultationChat> createState() => _DoctorConsultationChatState();
}

class _DoctorConsultationChatState extends State<_DoctorConsultationChat> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'doctor';
  String get _chatPath => 'consultations/${widget.consultationId}/messages';

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    await FirebaseFirestore.instance.collection(_chatPath).add({
      'text': text,
      'senderId': _uid,
      'senderRole': 'doctor',
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
                Expanded(
                  child: Text('Chat with ${widget.patientName}',
                      style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.black54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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
                            style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.black38)),
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
                    final isMe = data['senderRole'] == 'doctor';
                    final text = data['text'] as String? ?? '';
                    final ts = data['timestamp'] as Timestamp?;
                    final time = ts != null
                        ? '${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                        : '';
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
                                color: AppColors.secondary.withValues(alpha:0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person_rounded, color: AppColors.secondary, size: 14),
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
                                        fontFamily: 'Inter',
                                        fontSize: 13,
                                        color: isMe ? Colors.white : Colors.black87,
                                        height: 1.4)),
                              ),
                              const SizedBox(height: 3),
                              Text(time,
                                  style: const TextStyle(
                                      fontFamily: 'Inter', fontSize: 9, color: Colors.black38)),
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
                      hintText: 'Message patient...',
                      hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.black38),
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
