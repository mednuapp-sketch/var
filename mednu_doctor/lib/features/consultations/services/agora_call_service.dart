import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

const kAgoraAppId = 'b0143ffdfef74f399a420c7cd73c9e8b';

enum _QualityTier { high, medium, low, audioOnly }

class AgoraCallService {
  RtcEngine? _engine;
  bool isJoined = false;
  int? remoteUid;

  // Starts at high, not medium — the adaptive logic below only ever steps
  // this down in response to actual measured network quality, so starting
  // conservative just made every call blurrier than the network required.
  _QualityTier _currentTier = _QualityTier.high;
  bool _isAudioOnlyMode = false;
  bool _userVideoMuted = false;

  final void Function(int uid) onRemoteJoined;
  final void Function() onRemoteLeft;

  /// Optional: fires whenever network quality changes so the UI can update
  /// the signal indicator and switch to audio-only mode on the doctor side.
  final void Function(int qualityIndex, bool audioOnly)? onNetworkQualityChanged;

  /// Fires on connection state transitions so the UI can show a banner when
  /// reconnecting after a network drop.
  final void Function(ConnectionStateType state)? onConnectionStateChanged;

  /// Fires on any Agora engine error so the UI can display a meaningful message
  /// instead of leaving the user with a silent black screen.
  final void Function(ErrorCodeType code, String message)? onAgoraError;

  AgoraCallService({
    required this.onRemoteJoined,
    required this.onRemoteLeft,
    this.onNetworkQualityChanged,
    this.onConnectionStateChanged,
    this.onAgoraError,
  });

  bool get isInitialized => _engine != null;
  RtcEngine get engine => _engine!;
  bool get isAudioOnlyMode => _isAudioOnlyMode;

  Future<void> initialize() async {
    await [Permission.camera, Permission.microphone].request();
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(const RtcEngineContext(appId: kAgoraAppId));

    await _configureAudio();
    await _engine!.enableVideo();
    await _applyVideoConfig(_QualityTier.high);

    // Dual-stream: let the remote peer request high or low quality as needed
    await _engine!.enableDualStreamMode(enabled: true);

    await _engine!.startPreview();

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        debugPrint('[Agora Doctor] Joined: ${connection.channelId}');
      },
      onError: (err, msg) {
        debugPrint('[Agora Doctor] Error $err: $msg');
        onAgoraError?.call(err, msg);
      },
      onUserJoined: (_, uid, __) {
        remoteUid = uid;
        // Always subscribe to the patient's highest quality stream
        _engine!.setRemoteVideoStreamType(
          uid: uid,
          streamType: VideoStreamType.videoStreamHigh,
        );
        onRemoteJoined(uid);
      },
      onUserOffline: (_, uid, __) {
        remoteUid = null;
        onRemoteLeft();
      },
      onNetworkQuality: (connection, remoteUid, txQuality, rxQuality) {
        if (remoteUid != 0) return;
        _handleNetworkQuality(txQuality, rxQuality);
      },
      // ── Reconnection handling ──────────────────────────────────────────
      onConnectionStateChanged: (connection, state, reason) {
        onConnectionStateChanged?.call(state);
        if (state == ConnectionStateType.connectionStateConnected &&
            isJoined &&
            remoteUid != null) {
          _engine?.setRemoteVideoStreamType(
            uid: remoteUid!,
            streamType: VideoStreamType.videoStreamHigh,
          );
        }
      },
      onTokenPrivilegeWillExpire: (connection, token) async {
        final channelId = connection.channelId;
        if (channelId == null || _engine == null) return;
        try {
          final newToken = await _fetchToken(channelId);
          await _engine!.renewToken(newToken);
        } catch (e) {
          debugPrint('[Agora Doctor] Token renewal failed: $e');
        }
      },
    ));
  }

  // ── Audio: speech-optimised + chatroom echo cancellation ─────────────────
  Future<void> _configureAudio() async {
    await _engine!.setAudioProfile(
      profile: AudioProfileType.audioProfileSpeechStandard,
    );
    await _engine!.setAudioScenario(
      AudioScenarioType.audioScenarioChatroom,
    );
  }

  // ── Adaptive quality ─────────────────────────────────────────────────────
  void _handleNetworkQuality(QualityType txQuality, QualityType rxQuality) {
    final worstIndex =
        txQuality.index > rxQuality.index ? txQuality.index : rxQuality.index;

    final _QualityTier targetTier;
    if (worstIndex <= QualityType.qualityGood.index) {
      targetTier = _QualityTier.high;
    } else if (worstIndex <= QualityType.qualityPoor.index) {
      targetTier = _QualityTier.medium;
    } else if (worstIndex <= QualityType.qualityBad.index) {
      targetTier = _QualityTier.low;
    } else {
      targetTier = _QualityTier.audioOnly;
    }

    if (targetTier == _currentTier) return;
    _currentTier = targetTier;

    if (targetTier == _QualityTier.audioOnly) {
      _enterAudioFirstMode();
    } else {
      if (_isAudioOnlyMode) _exitAudioFirstMode();
      _applyVideoConfig(targetTier);
    }

    onNetworkQualityChanged?.call(worstIndex, _isAudioOnlyMode);
  }

  Future<void> _applyVideoConfig(_QualityTier tier) async {
    final VideoEncoderConfiguration cfg;
    switch (tier) {
      case _QualityTier.high:
        cfg = const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 1280, height: 720),
          frameRate: 30,
          bitrate: 1800,
          orientationMode: OrientationMode.orientationModeAdaptive,
          degradationPreference: DegradationPreference.maintainFramerate,
        );
      case _QualityTier.medium:
        cfg = const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 640, height: 480),
          frameRate: 24,
          bitrate: 1000,
          orientationMode: OrientationMode.orientationModeAdaptive,
          degradationPreference: DegradationPreference.maintainFramerate,
        );
      case _QualityTier.low:
        cfg = const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 320, height: 240),
          frameRate: 15,
          bitrate: 400,
          orientationMode: OrientationMode.orientationModeAdaptive,
          degradationPreference: DegradationPreference.maintainQuality,
        );
      case _QualityTier.audioOnly:
        return;
    }
    await _engine?.setVideoEncoderConfiguration(cfg);
  }

  void _enterAudioFirstMode() {
    _isAudioOnlyMode = true;
    _engine?.muteLocalVideoStream(true);
  }

  void _exitAudioFirstMode() {
    _isAudioOnlyMode = false;
    if (!_userVideoMuted) {
      _engine?.muteLocalVideoStream(false);
    }
  }

  /// Calls the `generateAgoraToken` Cloud Function, which also authorizes
  /// the request server-side (only the doctor/patient on this consultation
  /// may obtain a token for its channel).
  Future<String> _fetchToken(String channelId) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('generateAgoraToken')
        .call({'channelName': channelId});
    return result.data['token'] as String;
  }

  Future<void> joinChannel(String channelId) async {
    if (isJoined || _engine == null) return;
    final token = await _fetchToken(channelId);
    if (isJoined || _engine == null) return;
    isJoined = true;
    await _engine!.joinChannel(
      token: token,
      channelId: channelId,
      uid: 0,
      options: const ChannelMediaOptions(
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  Future<void> muteLocalAudio(bool muted) async {
    await _engine?.muteLocalAudioStream(muted);
  }

  Future<void> muteLocalVideo(bool muted) async {
    _userVideoMuted = muted;
    await _engine?.enableLocalVideo(!muted);
    await _engine?.muteLocalVideoStream(muted);
  }

  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }

  Future<void> setSpeakerphone(bool on) async {
    await _engine?.setEnableSpeakerphone(on);
  }

  Future<void> dispose() async {
    await _engine?.leaveChannel();
    await _engine?.release();
    _engine = null;
    isJoined = false;
    _isAudioOnlyMode = false;
    _userVideoMuted = false;
    _currentTier = _QualityTier.high;
  }
}
