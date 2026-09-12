import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_protector/screen_protector.dart';
import '../services/agora_call_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/active_call_service.dart';
import '../../../shared_core/providers/role_providers.dart';

/// Physiotherapist/Counsellor video session — same reliable call mechanics
/// as [DoctorVideoCallScreen] (lobby → join, adaptive quality, reconnect/
/// call-failed banners, background-safe via [ActiveCallService], screen
/// protection) stripped of doctor-only clinical features (prescription
/// writing, patient medical history, in-call chat) that don't apply to a
/// therapy/counselling session.
class ProviderVideoCallScreen extends StatefulWidget {
  final String consultationId;
  final String providerRole; // 'physiotherapist' | 'counsellor'
  final String patientName;

  const ProviderVideoCallScreen({
    super.key,
    required this.consultationId,
    required this.providerRole,
    required this.patientName,
  });

  @override
  State<ProviderVideoCallScreen> createState() => _ProviderVideoCallScreenState();
}

class _ProviderVideoCallScreenState extends State<ProviderVideoCallScreen> {
  Set<int> _remoteUids = {};
  bool get _remoteJoined => _remoteUids.isNotEmpty;
  bool _engineReady = false;
  bool _isReconnecting = false;
  bool _callFailed = false;
  bool _retryingConnection = false;
  int _networkQualityIndex = 0;
  bool _isAudioOnly = false;
  String? _agoraError;

  bool _inLobby = true;
  bool _lobbyLoading = true;
  bool _permissionsBlocked = false;

  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _endCallLock = false;
  int _callDuration = 0;

  late AgoraCallService _agora;
  StreamSubscription? _consultSub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    ProviderScope.containerOf(context, listen: false)
        .read(criticalOperationInProgressProvider.notifier)
        .state = true;
    _enableScreenProtection();
    _agora = AgoraCallService(
      onRemoteJoined: (uid) {
        if (!mounted) return;
        final isFirst = _remoteUids.isEmpty;
        setState(() => _remoteUids = {..._remoteUids, uid});
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
        setState(() {
          _isReconnecting = state == ConnectionStateType.connectionStateReconnecting;
          if (state == ConnectionStateType.connectionStateConnected ||
              state == ConnectionStateType.connectionStateReconnecting ||
              state == ConnectionStateType.connectionStateConnecting) {
            _callFailed = false;
          }
        });
      },
      onConnectionFailed: () {
        if (!mounted) return;
        setState(() {
          _isReconnecting = false;
          _callFailed = true;
        });
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

  Future<void> _initLobbyPreview() async {
    try {
      final statuses = await _agora.requestPermissions().timeout(const Duration(seconds: 15));
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
      debugPrint('[ProviderVideoCall] Lobby preview init failed: $e');
      if (!mounted) return;
      setState(() {
        _agoraError = 'Could not start camera preview. Please try again.';
        _lobbyLoading = false;
      });
    }
  }

  Future<void> _joinCall() async {
    setState(() => _inLobby = false);
    try {
      await ActiveCallService.start(callId: widget.consultationId, callerName: widget.patientName);
      ActiveCallService.setEndCallFromNotificationHandler(() => _doEndCall());
      await _agora.joinChannel(widget.consultationId);
    } catch (e) {
      debugPrint('[ProviderVideoCall] Agora join failed: $e');
      if (!mounted) return;
      setState(() => _agoraError = 'Could not start the video call. Please try again.');
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('consultations')
          .doc(widget.consultationId)
          .update({'status': 'active'});
    } catch (e) {
      debugPrint('[ProviderVideoCall] Active status update failed: $e');
    }
  }

  Future<void> _enableScreenProtection() async {
    try {
      await ScreenProtector.protectDataLeakageOn();
      await ScreenProtector.protectDataLeakageWithColor(Colors.black);
      await ScreenProtector.preventScreenshotOn();
      ScreenProtector.addListener(
        () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Screenshots are not allowed during sessions'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        },
        (isRecording) => debugPrint('[ProviderVideoCall] Screen recording detected: $isRecording'),
      );
    } catch (e) {
      debugPrint('[ProviderVideoCall] Screen protection error: $e');
    }
  }

  void _watchConsultation() {
    _consultSub =
        FirebaseFirestore.instance.collection('consultations').doc(widget.consultationId).snapshots().listen(
      (snap) {
        if (!snap.exists || !mounted) return;
        final status = snap.data()?['status'] as String? ?? '';
        if (status == 'ended' && !_endCallLock) _doEndCall(fromRemote: true);
      },
      onError: (e) => debugPrint('[ProviderVideoCall] Consultation watch error: $e'),
    );
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

  Future<void> _retryConnection() async {
    if (_retryingConnection) return;
    setState(() => _retryingConnection = true);
    final ok = await _agora.retryConnection();
    if (!mounted) return;
    setState(() {
      _retryingConnection = false;
      if (ok) _callFailed = false;
    });
    if (!ok && mounted) {
      setState(() {
        _callFailed = true;
        _agoraError = 'Still unable to connect. Check your network and try again.';
      });
    }
  }

  void _confirmEnd(BuildContext context) {
    if (_endCallLock) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('End Session?', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
        content: const Text('The video session will be ended.', style: TextStyle(fontFamily: 'Inter')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _doEndCall();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            child: const Text('End Session', style: TextStyle(fontFamily: 'Inter')),
          ),
        ],
      ),
    );
  }

  Future<void> _doEndCall({bool fromRemote = false}) async {
    if (_endCallLock) return;
    _endCallLock = true;
    final isLastToLeave = _agora.remoteUids.isEmpty;
    await ActiveCallService.stop();

    final consultRef = FirebaseFirestore.instance.collection('consultations').doc(widget.consultationId);
    if (!fromRemote && isLastToLeave) {
      try {
        await consultRef.update({'status': 'ended', 'endedAt': FieldValue.serverTimestamp()});
      } catch (_) {}
    }

    await _agora.dispose();
    _consultSub?.cancel();
    ActiveCallService.clearEndCallFromNotificationHandler();

    if (!mounted) return;
    ProviderScope.containerOf(context, listen: false)
        .read(criticalOperationInProgressProvider.notifier)
        .state = false;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  @override
  void dispose() {
    ActiveCallService.clearEndCallFromNotificationHandler();
    ProviderScope.containerOf(context, listen: false)
        .read(criticalOperationInProgressProvider.notifier)
        .state = false;
    _consultSub?.cancel();
    ScreenProtector.protectDataLeakageOff();
    ScreenProtector.protectDataLeakageWithColorOff();
    ScreenProtector.removeListener();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_inLobby) return _buildLobby();
    return PopScope(
      canPop: _endCallLock,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_endCallLock) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _buildRemoteView(),
            _buildLocalPip(),
            _buildTopBar(),
            if (_isReconnecting) _buildReconnectBanner(),
            if (_callFailed) _buildCallFailedBanner(),
            if (_agoraError != null) _buildAgoraErrorBanner(),
            _buildBottomControls(context),
          ],
        ),
      ),
    );
  }

  // ── Pre-join lobby ─────────────────────────────────────────────────────────

  Widget _buildLobby() {
    if (_permissionsBlocked) {
      return Scaffold(
        backgroundColor: const Color(0xFF14141C),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'Camera & microphone access needed',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enable camera and microphone permissions in Settings to start the video session.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Inter', color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => openAppSettings(),
                    child: const Text('Open Settings'),
                  ),
                  TextButton(
                    onPressed: () => context.canPop() ? context.pop() : context.go('/dashboard'),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildLobbyPreview(),
          if (_agoraError != null) _buildAgoraErrorBanner(),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.patientName,
                      style: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _engineReady ? _joinCall : null,
                        icon: const Icon(Icons.videocam_rounded),
                        label: Text(_lobbyLoading ? 'Preparing…' : 'Join call'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLobbyPreview() {
    if (_lobbyLoading || !_engineReady) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF1A0533), Color(0xFF0D1B3E)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: const Center(child: CircularProgressIndicator(color: Colors.white54)),
      );
    }
    if (_isCameraOff) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF1A0533), Color(0xFF0D1B3E)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
            child: const Icon(Icons.videocam_off_rounded, size: 48, color: Colors.white),
          ),
        ),
      );
    }
    return AgoraVideoView(controller: VideoViewController(rtcEngine: _agora.engine, canvas: const VideoCanvas(uid: 0)));
  }

  // ── In-call ────────────────────────────────────────────────────────────────

  Widget _buildRemoteView() {
    if (!_remoteJoined) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF1A0533), Color(0xFF0D1B3E)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: 10)],
              ),
              child: const Icon(Icons.person_rounded, size: 64, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(widget.patientName, style: const TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 6),
            const Text('Waiting for patient to join...', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white54)),
          ],
        ),
      );
    }
    if (!_agora.isInitialized) return const SizedBox.expand();
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _agora.engine,
        canvas: VideoCanvas(uid: _remoteUids.first, renderMode: RenderModeType.renderModeHidden),
        connection: RtcConnection(channelId: widget.consultationId),
      ),
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
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
        ),
        child: _isCameraOff
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_off_rounded, color: Colors.white60, size: 30),
                  SizedBox(height: 4),
                  Text('Camera Off', style: TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'Inter')),
                ],
              )
            : _engineReady
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AgoraVideoView(controller: VideoViewController(rtcEngine: _agora.engine, canvas: const VideoCanvas(uid: 0))),
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

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.signal_cellular_alt_rounded, color: _remoteJoined ? _networkSignalColor : Colors.orange, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    _remoteJoined ? '$_networkQualityLabel • $_formattedDuration' : 'Connecting...',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Inter', fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
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
          gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
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
              _isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
              'Camera',
              _isCameraOff,
              () {
                setState(() => _isCameraOff = !_isCameraOff);
                _agora.muteLocalVideo(_isCameraOff);
              },
            ),
            GestureDetector(
              onTap: () => _confirmEnd(context),
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xFFE53935).withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 4)],
                ),
                child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
              ),
            ),
            _CallBtn(
              _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              'Speaker',
              !_isSpeakerOn,
              () {
                setState(() => _isSpeakerOn = !_isSpeakerOn);
                _agora.setSpeakerphone(_isSpeakerOn);
              },
            ),
            _CallBtn(Icons.flip_camera_android_rounded, 'Flip', false, () => _agora.switchCamera()),
          ],
        ),
      ),
    );
  }

  Widget _buildReconnectBanner() {
    return Positioned(
      top: 110,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 10),
            Text('Reconnecting...', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildCallFailedBanner() {
    return Positioned(
      top: 110,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Colors.red.shade700.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Call disconnected — network lost.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white),
              ),
            ),
            GestureDetector(
              onTap: _retryingConnection ? null : _retryConnection,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: _retryingConnection
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                    : Text('Retry', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.red.shade700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgoraErrorBanner() {
    return Positioned(
      top: (_isReconnecting || _callFailed) ? 164 : 110,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Colors.red.shade700.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _agoraError ?? '',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white),
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
}

class _CallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _CallBtn(this.icon, this.label, this.isActive, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isActive ? Colors.white.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: isActive ? Border.all(color: Colors.white, width: 1.5) : null,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Inter')),
          ],
        ),
      );
}
