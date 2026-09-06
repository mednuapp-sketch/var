import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:permission_handler/permission_handler.dart';

// Injected via --dart-define=AGORA_APP_ID=... at build time.
// Restrict this App ID in Agora Console to package com.mednu.mednu.
const kAgoraAppId = String.fromEnvironment(
  'AGORA_APP_ID',
  defaultValue: 'b0143ffdfef74f399a420c7cd73c9e8b',
);

enum _QualityTier { high, medium, low, audioOnly }

class AgoraCallService {
  RtcEngine? _engine;
  bool isJoined = false;

  /// All other participants currently in the channel — a plain int, not a
  /// bool/single-uid slot, so a 3-party call (e.g. patient + a guest family
  /// member + doctor) can track each remote independently: one leaving no
  /// longer clears the others' state, which `onUserOffline` used to do when
  /// it unconditionally nulled a single `remoteUid`.
  final Set<int> remoteUids = {};

  /// This device's own Agora uid, assigned by `generateAgoraToken` from the
  /// caller's verified role (doctor=1, patient=2, guest=3) — fixed per role
  /// so every screen can label tiles deterministically instead of guessing.
  int? localUid;

  // Starts at high, not medium — the adaptive logic below only ever steps
  // this down in response to actual measured network quality, so starting
  // conservative just made every call blurrier than the network required.
  _QualityTier _currentTier = _QualityTier.high;
  bool _isAudioOnlyMode = false;
  bool _userVideoMuted = false;

  final void Function(int uid) onRemoteJoined;
  final void Function(int uid) onRemoteLeft;
  final void Function(int qualityIndex, bool audioOnly)? onNetworkQualityChanged;

  /// Fires whenever Agora's connection state changes so the UI can show
  /// a "Reconnecting…" banner and the call can recover automatically.
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

  /// Requests camera + mic access up front (before the engine is created)
  /// so the pre-join lobby can show a proper permission prompt/denied state
  /// instead of the engine silently starting with no video/audio.
  Future<Map<Permission, PermissionStatus>> requestPermissions() {
    return [Permission.camera, Permission.microphone].request();
  }

  Future<void> initialize() async {
    await [Permission.camera, Permission.microphone].request();
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(const RtcEngineContext(appId: kAgoraAppId));

    await _configureAudio();
    await _engine!.enableVideo();
    await _applyVideoConfig(_QualityTier.high);

    // Dual-stream: high quality for active speaker, low for thumbnail
    await _engine!.enableDualStreamMode(enabled: true);

    await _engine!.startPreview();

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        // ignore: avoid_print
        print('[Agora] Joined: ${connection.channelId}');
      },
      onError: (err, msg) {
        // ignore: avoid_print
        print('[Agora] Error $err: $msg');
        onAgoraError?.call(err, msg);
      },
      onUserJoined: (_, uid, __) {
        remoteUids.add(uid);
        _engine!.setRemoteVideoStreamType(
          uid: uid,
          streamType: VideoStreamType.videoStreamHigh,
        );
        onRemoteJoined(uid);
      },
      onUserOffline: (_, uid, __) {
        remoteUids.remove(uid);
        onRemoteLeft(uid);
      },
      onNetworkQuality: (connection, remoteUid, txQuality, rxQuality) {
        if (remoteUid != 0) return;
        _handleNetworkQuality(txQuality, rxQuality);
      },
      // ── Reconnection lifecycle ─────────────────────────────────────────
      onConnectionStateChanged: (connection, state, reason) {
        onConnectionStateChanged?.call(state);

        if (state == ConnectionStateType.connectionStateConnected &&
            isJoined) {
          // Re-subscribe to remote streams after a reconnect to prevent
          // a frozen video frame on the recovered connection.
          for (final uid in remoteUids) {
            _engine?.setRemoteVideoStreamType(
              uid: uid,
              streamType: VideoStreamType.videoStreamHigh,
            );
          }
        }
      },
      onTokenPrivilegeWillExpire: (connection, token) async {
        final channelId = connection.channelId;
        if (channelId == null || _engine == null) return;
        try {
          final newAuth = await _fetchAuth(channelId);
          await _engine!.renewToken(newAuth.token);
        } catch (e) {
          // ignore: avoid_print
          print('[Agora] Token renewal failed: $e');
        }
      },
    ));
  }

  // ── Audio: speech-optimised profile + chatroom scenario ─────────────────
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
  /// the request server-side (only the doctor/patient/guest on this
  /// consultation may obtain a token for its channel) and assigns this
  /// caller a fixed uid for their verified role (doctor=1, patient=2,
  /// guest=3) so every screen can label tiles deterministically.
  Future<({String token, int uid})> _fetchAuth(String channelId) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('generateAgoraToken')
        .call({'channelName': channelId});
    final data = result.data as Map;
    return (token: data['token'] as String, uid: data['uid'] as int);
  }

  Future<void> joinChannel(String channelId) async {
    if (isJoined || _engine == null) return;
    final auth = await _fetchAuth(channelId);
    if (isJoined || _engine == null) return;
    isJoined = true;
    localUid = auth.uid;
    await _engine!.joinChannel(
      token: auth.token,
      channelId: channelId,
      uid: auth.uid,
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
    // enableLocalVideo(false) physically stops camera capture and turns off
    // the camera LED — muteLocalVideoStream alone only suppresses the outgoing
    // stream but leaves the camera running.
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
    remoteUids.clear();
    localUid = null;
    _isAudioOnlyMode = false;
    _userVideoMuted = false;
    _currentTier = _QualityTier.high;
  }
}
