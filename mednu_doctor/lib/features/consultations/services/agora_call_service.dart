import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

const kAgoraAppId = 'b0143ffdfef74f399a420c7cd73c9e8b';

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

  // Dual-stream mode (enabled in initialize()) lets each side independently
  // choose the INCOMING resolution it pulls, separate from what it encodes
  // and sends. `_handleNetworkQuality` already adapted the outgoing encode;
  // it never touched this, so a bad network still pulled full 720p from the
  // remote peer even while the local upload degraded. This mirrors
  // `_currentTier` for the receive side.
  VideoStreamType get _currentRemoteStreamType =>
      _currentTier == _QualityTier.low || _currentTier == _QualityTier.audioOnly
          ? VideoStreamType.videoStreamLow
          : VideoStreamType.videoStreamHigh;

  final void Function(int uid) onRemoteJoined;
  final void Function(int uid) onRemoteLeft;

  /// Optional: fires whenever network quality changes so the UI can update
  /// the signal indicator and switch to audio-only mode on the doctor side.
  final void Function(int qualityIndex, bool audioOnly)? onNetworkQualityChanged;

  /// Fires on connection state transitions so the UI can show a banner when
  /// reconnecting after a network drop.
  final void Function(ConnectionStateType state)? onConnectionStateChanged;

  /// Fires when the SDK's own auto-reconnect gives up
  /// (`connectionStateFailed`) — the UI has no other signal that the call is
  /// truly dead rather than still retrying, so this is what drives a
  /// "Call failed — Tap to retry" action instead of leaving a frozen screen.
  final void Function()? onConnectionFailed;

  /// Fires on any Agora engine error so the UI can display a meaningful message
  /// instead of leaving the user with a silent black screen.
  final void Function(ErrorCodeType code, String message)? onAgoraError;

  /// Channel this service last (successfully or attemptedly) joined — kept
  /// so [retryConnection] can rejoin with a fresh token after
  /// `connectionStateFailed` without the caller having to re-supply it.
  String? _lastChannelId;

  AgoraCallService({
    required this.onRemoteJoined,
    required this.onRemoteLeft,
    this.onNetworkQualityChanged,
    this.onConnectionStateChanged,
    this.onConnectionFailed,
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
        remoteUids.add(uid);
        // Subscribe at whatever quality the call is currently running at —
        // a late joiner during an already-degraded call should get the low
        // stream immediately, not the high one this handler used to
        // hardcode regardless of measured network quality.
        _engine!.setRemoteVideoStreamType(
          uid: uid,
          streamType: _currentRemoteStreamType,
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
      // ── Reconnection handling ──────────────────────────────────────────
      onConnectionStateChanged: (connection, state, reason) {
        onConnectionStateChanged?.call(state);
        if (state == ConnectionStateType.connectionStateConnected && isJoined) {
          for (final uid in remoteUids) {
            _engine?.setRemoteVideoStreamType(
              uid: uid,
              streamType: _currentRemoteStreamType,
            );
          }
        }
        // The SDK auto-retries reconnectingâ†’connected on its own; `failed`
        // is what it transitions to once that internal retry gives up
        // (e.g. a genuinely dead network, not just a blip). Nothing else in
        // this service, or any call screen, was watching for this state —
        // a call could die here and just sit frozen with no way back short
        // of the user manually leaving. `onConnectionFailed` gives the UI a
        // hook to show a "Call failed — Tap to retry" action instead.
        if (state == ConnectionStateType.connectionStateFailed) {
          isJoined = false;
          onConnectionFailed?.call();
        }
      },
      onTokenPrivilegeWillExpire: (connection, token) async {
        final channelId = connection.channelId;
        if (channelId == null || _engine == null) return;
        try {
          final newAuth = await _fetchAuth(channelId);
          await _engine!.renewToken(newAuth.token);
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
    final previousTier = _currentTier;
    _currentTier = targetTier;

    if (targetTier == _QualityTier.audioOnly) {
      _enterAudioFirstMode();
    } else {
      if (_isAudioOnlyMode) _exitAudioFirstMode();
      _applyVideoConfig(targetTier);
    }

    // Only re-subscribe when crossing the low/high boundary — stepping
    // between high and medium doesn't need a different incoming stream, and
    // re-issuing an identical setRemoteVideoStreamType call on every minor
    // fluctuation would just be wasted signalling.
    final wasLowBand =
        previousTier == _QualityTier.low || previousTier == _QualityTier.audioOnly;
    final isLowBand =
        targetTier == _QualityTier.low || targetTier == _QualityTier.audioOnly;
    if (wasLowBand != isLowBand) {
      for (final uid in remoteUids) {
        _engine?.setRemoteVideoStreamType(uid: uid, streamType: _currentRemoteStreamType);
      }
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
    _lastChannelId = channelId;
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

  /// Full leave + rejoin with a freshly-minted token, for use after
  /// `onConnectionFailed` — the SDK's own internal retry has already given
  /// up by that point, and the old token may well have expired during
  /// however long the outage lasted, so a plain reconnect isn't enough.
  /// Returns false (instead of throwing) on failure so the UI can show a
  /// "still can't connect" message and let the user try again rather than
  /// crashing the call screen.
  Future<bool> retryConnection() async {
    final channelId = _lastChannelId;
    if (channelId == null || _engine == null) return false;
    try {
      if (isJoined) {
        await _engine!.leaveChannel();
        isJoined = false;
      }
      remoteUids.clear();
      await joinChannel(channelId);
      return true;
    } catch (e) {
      debugPrint('[Agora Doctor] retryConnection failed: $e');
      return false;
    }
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
    remoteUids.clear();
    localUid = null;
    _isAudioOnlyMode = false;
    _userVideoMuted = false;
    _currentTier = _QualityTier.high;
  }
}
