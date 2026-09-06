import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_protector/screen_protector.dart';
import 'agora_call_service.dart';
import 'call_ui_widgets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';

/// Call screen for a family member joining via a guest link (see
/// guest_join_screen.dart) — no MedNU account of their own.
///
/// Deliberately a separate screen from [VideoCallScreen] rather than a
/// guest-mode branch on it: this has no ActiveCallService foreground-service
/// integration (that assumes a persistent logged-in account across app
/// restarts — the guest's session is a one-off, scoped Firebase custom
/// token), no notes panel (clinical notes stay with the account holder), and
/// a simple "call ended" screen instead of the rating/prescription flow.
class GuestVideoCallScreen extends StatefulWidget {
  final String appointmentId;
  final String consultationId;
  final String doctorName;
  final String doctorSpecialty;

  const GuestVideoCallScreen({
    super.key,
    required this.appointmentId,
    required this.consultationId,
    required this.doctorName,
    this.doctorSpecialty = '',
  });

  @override
  State<GuestVideoCallScreen> createState() => _GuestVideoCallScreenState();
}

class _GuestVideoCallScreenState extends State<GuestVideoCallScreen>
    with SingleTickerProviderStateMixin {
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;

  /// All remote uids currently in the channel — besides the doctor (uid 1),
  /// the account holder who booked this appointment (uid 2) can also be on
  /// this call at the same time as this guest (see AgoraCallService/
  /// generateAgoraToken).
  Set<int> _remoteUids = {};
  bool get _remoteJoined => _remoteUids.isNotEmpty;
  String? _bookerLabel;
  bool _engineReady = false;
  bool _ending = false;
  bool _isReconnecting = false;
  int _callDuration = 0;

  bool _inLobby = true;
  bool _lobbyLoading = true;
  bool _permissionsBlocked = false;

  int _networkQualityIndex = 0;
  bool _isAudioOnly = false;
  String? _agoraError;

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
    _loadBookerLabel();
    _initLobbyPreview();
  }

  // The account holder who booked this appointment — used to label their
  // video tile if they're also on this call (see `_buildRemoteView`).
  Future<void> _loadBookerLabel() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointmentId)
          .get();
      final name = (snap.data()?['bookedByName'] as String?)?.trim();
      if (mounted && name != null && name.isNotEmpty) {
        setState(() => _bookerLabel = name);
      }
    } catch (_) {}
  }

  Future<void> _enableScreenProtection() async {
    try {
      await ScreenProtector.protectDataLeakageOn();
      await ScreenProtector.protectDataLeakageWithColor(Colors.black);
      await ScreenProtector.preventScreenshotOn();
    } catch (e) {
      debugPrint('[GuestVideoCall] Screen protection error: $e');
    }
  }

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
      debugPrint('[GuestVideoCall] Lobby preview init failed: $e');
      if (!mounted) return;
      setState(() {
        _agoraError = 'Could not start camera preview. Please try again.';
        _lobbyLoading = false;
      });
    }
  }

  Future<void> _joinCall() async {
    setState(() => _inLobby = false);
    _watchConsultation();
  }

  void _watchConsultation() {
    _consultSub = FirebaseFirestore.instance
        .collection('consultations')
        .doc(widget.consultationId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data() ?? {};
      final status = data['status'] as String? ?? '';

      if ((status == 'active' || status == 'ongoing') && !_agora.isJoined) {
        _agora.joinChannel(widget.consultationId);
      }

      if (_ending) return;
      if (status == 'ended' || status == 'cancelled') {
        _doEndCall(fromRemote: true);
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
    _consultSub?.cancel();
    _pulseController.dispose();
    _agora.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    ScreenProtector.preventScreenshotOff();
    ScreenProtector.protectDataLeakageOff();
    ScreenProtector.protectDataLeakageWithColorOff();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_inLobby) return _buildLobby();
    return PopScope(
      canPop: _ending,
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

  // ── Pre-join lobby ─────────────────────────────────────────────────────────

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
            end: Alignment.bottomCenter,
          ),
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
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.videocam_off_rounded, size: 48, color: Colors.white),
          ),
        ),
      );
    }
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _agora.engine,
        canvas: const VideoCanvas(uid: 0, renderMode: RenderModeType.renderModeHidden),
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
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 36),
          ),
          const SizedBox(height: 20),
          const Text(
            'Camera & microphone access needed',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'Allow access so the doctor can see and hear you during the consultation.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white60, height: 1.4),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => openAppSettings(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Open Settings',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              setState(() => _lobbyLoading = true);
              _initLobbyPreview();
            },
            child: const Text('Try again', style: TextStyle(fontFamily: 'Poppins', color: Colors.white60)),
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
            colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            TopButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
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
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.doctorName,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            if (widget.doctorSpecialty.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(widget.doctorSpecialty,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white60)),
            ],
            const SizedBox(height: 6),
            const Text(
              'Ready to join the consultation?',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CallButton(
                  icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  label: _isMuted ? 'Unmute' : 'Mute',
                  isActive: _isMuted,
                  onTap: () {
                    setState(() => _isMuted = !_isMuted);
                    _agora.muteLocalAudio(_isMuted);
                  },
                ),
                const SizedBox(width: 28),
                CallButton(
                  icon: _isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                  label: 'Camera',
                  isActive: _isCameraOff,
                  onTap: () {
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
                onPressed: (_lobbyLoading || _agoraError != null) ? null : _joinCall,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _lobbyLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Join call',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
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
                    BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: 10),
                  ],
                ),
                child: const Icon(Icons.person_rounded, size: 64, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.doctorName,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              widget.doctorSpecialty,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.white60),
            ),
            const SizedBox(height: 16),
            const Text(
              'Waiting for doctor to join...',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white54),
            ),
          ],
        ),
      );
    }
    if (!_engineReady) {
      return const Center(child: CircularProgressIndicator(color: Colors.white54));
    }
    // Whether the account holder who booked this appointment (uid 2) has
    // also joined — the only other remote possible here besides the doctor
    // (uid 1), since "self" (uid 3) is this guest device.
    final hasBooker = _remoteUids.contains(2);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!hasBooker)
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _agora.engine,
              canvas: VideoCanvas(
                uid: _remoteUids.isEmpty ? 0 : _remoteUids.first,
                renderMode: RenderModeType.renderModeHidden,
              ),
              connection: RtcConnection(channelId: widget.consultationId),
            ),
          )
        else
          Column(
            children: [
              Expanded(
                child: _buildLabeledRemoteTile(uid: 1, label: widget.doctorName),
              ),
              Container(height: 2, color: Colors.black),
              Expanded(
                child: _buildLabeledRemoteTile(uid: 2, label: _bookerLabel ?? 'Patient'),
              ),
            ],
          ),
        if (_isAudioOnly)
          Container(
            color: Colors.black54,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 48),
                SizedBox(height: 12),
                Text('Poor network — audio only',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.white70)),
              ],
            ),
          ),
      ],
    );
  }

  // A single tile in the 2-remote (doctor + booking account holder) layout —
  // used only once the booker has actually joined; the ordinary case above
  // (just the doctor) keeps the original full-bleed single view untouched.
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
                  fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
            ),
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
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
        ),
        child: _isCameraOff || _isAudioOnly
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isAudioOnly ? Icons.wifi_off_rounded : Icons.videocam_off_rounded,
                    color: Colors.white60,
                    size: 30,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isAudioOnly ? 'Audio Only' : 'Camera Off',
                    style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'Poppins'),
                  ),
                ],
              )
            : _engineReady
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _agora.engine,
                        canvas: const VideoCanvas(uid: 0, renderMode: RenderModeType.renderModeHidden),
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
            colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
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
                  _remoteJoined ? '$_networkQualityLabel • $_formattedDuration' : 'Connecting...',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11, fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            const Spacer(),
            TopButton(icon: Icons.chat_rounded, onTap: () => _showChat(context)),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 10),
            Text('Reconnecting...',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
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
        decoration: BoxDecoration(color: Colors.red.shade700.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _agoraError ?? '',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white),
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
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            CallButton(
              icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: _isMuted ? 'Unmute' : 'Mute',
              isActive: _isMuted,
              onTap: () {
                setState(() => _isMuted = !_isMuted);
                _agora.muteLocalAudio(_isMuted);
              },
            ),
            CallButton(
              icon: _isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
              label: 'Camera',
              isActive: _isCameraOff,
              onTap: () {
                setState(() => _isCameraOff = !_isCameraOff);
                _agora.muteLocalVideo(_isCameraOff);
              },
            ),
            AnimatedTap(
              heavy: true,
              onTap: () => _confirmEnd(context),
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFE53935).withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 4),
                  ],
                ),
                child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
              ),
            ),
            CallButton(
              icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              label: 'Speaker',
              isActive: !_isSpeakerOn,
              onTap: () {
                setState(() => _isSpeakerOn = !_isSpeakerOn);
                _agora.setSpeakerphone(_isSpeakerOn);
              },
            ),
            CallButton(
              icon: Icons.flip_camera_android_rounded,
              label: 'Flip',
              isActive: false,
              onTap: () => _agora.switchCamera(),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('End Call?', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to end this consultation?', style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _doEndCall();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            child: const Text('End Call'),
          ),
        ],
      ),
    );
  }

  Future<void> _doEndCall({bool fromRemote = false}) async {
    if (_ending) return;
    _ending = true;
    // WhatsApp-style group-call semantics: leaving only ends the consultation
    // for everyone once the LAST participant leaves an empty channel — read
    // before `_agora.dispose()` below clears it. If the doctor or the booking
    // account holder is still connected, this guest just exits locally.
    final isLastToLeave = _agora.remoteUids.isEmpty;
    if (!fromRemote && isLastToLeave && widget.consultationId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('consultations')
            .doc(widget.consultationId)
            .update({'status': 'ended', 'endedAt': FieldValue.serverTimestamp()});
      } catch (e) {
        debugPrint('[GuestVideoCall] End-call status update failed: $e');
      }
    }
    // Mark the linked appointment completed once the visit is actually over
    // for everyone — same "last one out" rule as the account holder's own
    // screen; Firestore rules narrowly allow a guest to set only these two
    // fields on the one appointment their join link is scoped to.
    if ((fromRemote || isLastToLeave) && widget.appointmentId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(widget.appointmentId)
            .update({'status': 'completed', 'completedAt': FieldValue.serverTimestamp()});
      } catch (e) {
        debugPrint('[GuestVideoCall] Appointment complete failed: $e');
      }
    }
    if (mounted) setState(() { _engineReady = false; _remoteUids = {}; });
    await _agora.dispose();
    // The guest's Firebase Auth session is scoped to exactly this
    // appointment and has no meaning anywhere else in the app — drop it so
    // splash/router logic doesn't mistake it for a real logged-in account.
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    _showEndedSheet(context);
  }

  void _showEndedSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
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
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 24),
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 16),
            const Text('Call ended',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Duration: $_formattedDuration',
                style: const TextStyle(fontFamily: 'Poppins', color: Colors.grey)),
            const SizedBox(height: 8),
            const Text('Thank you for using MedNU.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  context.go(AppRoutes.splash);
                },
                child: const Text('Close'),
              ),
            ),
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
      builder: (_) => _GuestConsultationChat(consultationId: widget.consultationId),
    );
  }
}

// ── In-call Chat (guest) ─────────────────────────────────────────────────────

class _GuestConsultationChat extends StatefulWidget {
  final String consultationId;
  const _GuestConsultationChat({required this.consultationId});

  @override
  State<_GuestConsultationChat> createState() => _GuestConsultationChatState();
}

class _GuestConsultationChatState extends State<_GuestConsultationChat> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'guest';
  String get _chatPath => 'consultations/${widget.consultationId}/messages';

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    await FirebaseFirestore.instance.collection(_chatPath).add({
      'text': text,
      'senderId': _uid,
      // Rendered on the doctor's side exactly like the patient's own
      // messages — the guest is standing in for the patient on this call.
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
                    color: AppColors.primary.withValues(alpha: 0.1),
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
                                color: AppColors.primary.withValues(alpha: 0.1),
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
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
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
                                        fontFamily: 'Poppins', fontSize: 13, color: isMe ? Colors.white : Colors.black87, height: 1.4)),
                              ),
                              const SizedBox(height: 3),
                              Text(time, style: const TextStyle(fontFamily: 'Poppins', fontSize: 9, color: Colors.black38)),
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
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))],
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
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
