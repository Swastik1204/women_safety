// ignore_for_file: unused_field

// Aanchal — WebRTC Engine
//
// Manages the RTCPeerConnection lifecycle:
//   • Create/close peer connection
//   • ICE candidate buffering (candidates received before remote description)
//   • TURN server configuration (metered.ca + Google STUN)
//   • Offer/answer creation
//   • Audio track management (mute/unmute, speaker)
//   • ICE restart for recovery
//   • Connection health monitoring
//
// This engine does NOT know about call state — it only manages the WebRTC
// peer connection. It receives instructions from CallStateManager/CallScreen.

import 'dart:async';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/logger.dart';
import 'models.dart';
import 'signaling_service.dart';

const _tag = 'WebRTCEngine';

/// ICE server configuration.
final _iceServers = <Map<String, dynamic>>[
  // Google STUN (free, reliable)
  {
    'urls': [
      'stun:stun.l.google.com:19302',
      'stun:stun1.l.google.com:19302',
    ],
  },
  // Open Relay TURN (UDP)
  {
    'urls': 'turn:a.relay.metered.ca:80',
    'username': 'e7b2e816a3f0b1834c075653',
    'credential': '8n+qAMiCoBi8QkXF',
  },
  // Open Relay TURN (TCP — for restrictive firewalls)
  {
    'urls': 'turn:a.relay.metered.ca:80?transport=tcp',
    'username': 'e7b2e816a3f0b1834c075653',
    'credential': '8n+qAMiCoBi8QkXF',
  },
  // Open Relay TURN (TLS on 443 — for very restrictive networks)
  {
    'urls': 'turn:a.relay.metered.ca:443',
    'username': 'e7b2e816a3f0b1834c075653',
    'credential': '8n+qAMiCoBi8QkXF',
  },
  {
    'urls': 'turns:a.relay.metered.ca:443?transport=tcp',
    'username': 'e7b2e816a3f0b1834c075653',
    'credential': '8n+qAMiCoBi8QkXF',
  },
];

final _pcConfig = <String, dynamic>{
  'iceServers': _iceServers,
  'sdpSemantics': 'unified-plan',
  'iceCandidatePoolSize': 2,
};

final _mediaConstraints = <String, dynamic>{
  'audio': true,
  'video': false,
};

/// Peer connection state callbacks.
typedef IceStateCallback = void Function(RTCIceConnectionState state);
typedef PeerConnectionStateCallback = void Function(
    RTCPeerConnectionState state);

class WebRTCEngine {
  // ── State ──────────────────────────────────────────────────────────
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  String? _callId;
  String? _peerId;
  bool _isCaller = false;
  bool _disposed = false;

  /// Buffered ICE candidates (received before remote description is set).
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;

  /// Mute state.
  bool _isMuted = false;
  bool get isMuted => _isMuted;

  /// Speaker state (defaults to speaker on).
  bool _isSpeakerOn = true;
  bool get isSpeakerOn => _isSpeakerOn;

  /// Health monitoring.
  Timer? _healthTimer;
  int _iceRestartCount = 0;
  static const _maxIceRestarts = 3;

  /// Callbacks.
  IceStateCallback? onIceStateChanged;
  PeerConnectionStateCallback? onPeerConnectionStateChanged;
  void Function()? onIceConnected;
  void Function()? onIceFailed;
  void Function()? onIceDisconnected;

  // ── Public API ─────────────────────────────────────────────────────

  /// Create the peer connection and set up listeners.
  /// Call this when the call enters CONNECTING state.
  Future<void> createConnection({
    required String callId,
    required String peerId,
    required bool isCaller,
  }) async {
    _callId = callId;
    _peerId = peerId;
    _isCaller = isCaller;
    _disposed = false;
    _remoteDescriptionSet = false;
    _pendingCandidates.clear();
    _iceRestartCount = 0;
    _reportMetric('pc_create', detail: isCaller ? 'caller' : 'callee');

    logInfo(_tag, 'Creating peer connection (caller=$isCaller)');

    // Create peer connection.
    _pc = await createPeerConnection(_pcConfig);

    // Get local audio stream.
    _localStream = await navigator.mediaDevices.getUserMedia(_mediaConstraints);
    for (final track in _localStream!.getAudioTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    // ICE candidate handler — send to peer via signaling server.
    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_disposed) return;
      logInfo(_tag, 'ICE candidate: ${candidate.candidate?.substring(0, min(60, candidate.candidate?.length ?? 0))}');
      SignalingService.instance.send({
        'type': MsgType.webrtcIce,
        'to': _peerId,
        'callId': _callId,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // ICE connection state (connected/disconnected/failed).
    _pc!.onIceConnectionState = (RTCIceConnectionState state) {
      if (_disposed) return;
      logInfo(_tag, 'ICE connection state: $state');
      _reportMetric('ice_state', iceState: state.name);
      onIceStateChanged?.call(state);

      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _iceRestartCount = 0;
          onIceConnected?.call();
          _startHealthMonitor();
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _handleIceFailed();
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          onIceDisconnected?.call();
          // Wait a bit — might recover.
          Future.delayed(const Duration(seconds: 5), () {
            if (_disposed) return;
            if (_pc?.iceConnectionState ==
                RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
              _handleIceFailed();
            }
          });
        default:
          break;
      }
    };

    // Peer connection state.
    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      if (_disposed) return;
      logInfo(_tag, 'Peer connection state: $state');
      onPeerConnectionStateChanged?.call(state);
    };

    // Listen for incoming signaling messages (WebRTC relay).
    SignalingService.instance.addListener(_onSignalingMessage);

  }

  /// Close the peer connection and release resources.
  Future<void> closeConnection() async {
    _disposed = true;
    _stopHealthMonitor();
    SignalingService.instance.removeListener(_onSignalingMessage);

    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      await _localStream?.dispose();
    } catch (e) {
      logError(_tag, 'Error disposing local stream: $e');
    }

    try {
      await _pc?.close();
    } catch (e) {
      logError(_tag, 'Error closing peer connection: $e');
    }

    _pc = null;
    _localStream = null;
    _pendingCandidates.clear();
    _remoteDescriptionSet = false;
    logInfo(_tag, 'Connection closed');
  }

  /// Toggle mute.
  void toggleMute() {
    _isMuted = !_isMuted;
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
    logInfo(_tag, 'Mute: $_isMuted');
  }

  /// Toggle speaker.
  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    _localStream?.getAudioTracks().forEach((track) {
      track.enableSpeakerphone(_isSpeakerOn);
    });
    logInfo(_tag, 'Speaker: $_isSpeakerOn');
  }

  /// Attempt ICE restart.
  Future<void> restartIce() async {
    if (_pc == null || _disposed) return;
    if (_iceRestartCount >= _maxIceRestarts) {
      logWarn(_tag, 'Max ICE restarts reached — giving up');
      onIceFailed?.call();
      return;
    }
    _iceRestartCount++;
    _reportMetric('reconnect_attempt', detail: 'ice_restart_$_iceRestartCount');
    logInfo(_tag, 'Restarting ICE (attempt $_iceRestartCount)');
    await createAndSendOffer(iceRestart: true);
  }

  Future<void> createAndSendOffer({bool iceRestart = false}) async {
    await _createAndSendOffer(iceRestart: iceRestart);
  }

  // ── SDP Offer/Answer ────────────────────────────────────────────────

  Future<void> _createAndSendOffer({bool iceRestart = false}) async {
    if (_pc == null || _disposed) return;

    final constraints = <String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
      if (iceRestart) 'iceRestart': true,
    };

    try {
      final offer = await _pc!.createOffer(constraints);
      await _pc!.setLocalDescription(offer);
      logInfo(_tag, 'Created offer (iceRestart=$iceRestart)');

      SignalingService.instance.send({
        'type': MsgType.webrtcOffer,
        'to': _peerId,
        'callId': _callId,
        'sdp': offer.sdp,
      });
      _reportMetric('offer_sent', detail: iceRestart ? 'ice_restart' : 'initial');
    } catch (e) {
      logError(_tag, 'Create offer failed: $e');
      _reportMetric('offer_failed', detail: '$e');
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    if (_pc == null || _disposed) return;

    final sdp = payload['sdp'] as String?;
    if (sdp == null) return;

    try {
      await _pc!.setRemoteDescription(
        RTCSessionDescription(sdp, 'offer'),
      );
      _remoteDescriptionSet = true;
      logInfo(_tag, 'Remote offer set');

      // Flush pending candidates.
      await _flushPendingCandidates();

      // Create and send answer.
      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _pc!.setLocalDescription(answer);
      logInfo(_tag, 'Created answer');

      SignalingService.instance.send({
        'type': MsgType.webrtcAnswer,
        'to': _peerId,
        'callId': _callId,
        'sdp': answer.sdp,
      });
      _reportMetric('answer_sent');
    } catch (e) {
      logError(_tag, 'Handle offer failed: $e');
      _reportMetric('offer_handle_failed', detail: '$e');
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    if (_pc == null || _disposed) return;

    final sdp = payload['sdp'] as String?;
    if (sdp == null) return;

    try {
      await _pc!.setRemoteDescription(
        RTCSessionDescription(sdp, 'answer'),
      );
      _remoteDescriptionSet = true;
      logInfo(_tag, 'Remote answer set');

      // Flush pending candidates.
      await _flushPendingCandidates();
    } catch (e) {
      logError(_tag, 'Handle answer failed: $e');
      _reportMetric('answer_handle_failed', detail: '$e');
    }
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> payload) async {
    if (_pc == null || _disposed) return;

    final candidate = payload['candidate'] as String?;
    if (candidate == null || candidate.isEmpty) return;

    final iceCandidate = RTCIceCandidate(
      candidate,
      payload['sdpMid'] as String?,
      payload['sdpMLineIndex'] as int?,
    );

    if (_remoteDescriptionSet) {
      try {
        await _pc!.addCandidate(iceCandidate);
        logInfo(_tag, 'Added ICE candidate');
      } catch (e) {
        logError(_tag, 'Add ICE candidate failed: $e');
        _reportMetric('ice_add_failed', detail: '$e');
      }
    } else {
      // Buffer until remote description is set.
      _pendingCandidates.add(iceCandidate);
      logInfo(_tag,
          'Buffered ICE candidate (${_pendingCandidates.length} pending)');
    }
  }

  Future<void> _flushPendingCandidates() async {
    if (_pc == null || _pendingCandidates.isEmpty) return;
    logInfo(_tag, 'Flushing ${_pendingCandidates.length} buffered candidates');
    final candidates = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final c in candidates) {
      try {
        await _pc!.addCandidate(c);
      } catch (e) {
        logError(_tag, 'Flush candidate failed: $e');
      }
    }
  }

  // ── ICE Failure Handling ────────────────────────────────────────────

  void _handleIceFailed() {
    if (_disposed) return;
    _reportMetric('ice_failed');
    if (_iceRestartCount < _maxIceRestarts) {
      logWarn(_tag, 'ICE failed — attempting restart');
      restartIce();
    } else {
      logError(_tag, 'ICE failed — max restarts exhausted');
      onIceFailed?.call();
    }
  }

  // ── Health Monitor ──────────────────────────────────────────────────

  void _startHealthMonitor() {
    _stopHealthMonitor();
    _healthTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkHealth();
    });
  }

  void _stopHealthMonitor() {
    _healthTimer?.cancel();
    _healthTimer = null;
  }

  Future<void> _checkHealth() async {
    if (_pc == null || _disposed) return;

    try {
      final stats = await _pc!.getStats();
      // Just log connection quality — UI can use ice state callbacks.
      for (final report in stats) {
        if (report.type == 'candidate-pair' &&
            report.values['state'] == 'succeeded') {
          final rtt = report.values['currentRoundTripTime'];
          final packetLoss = report.values['packetsLost'];
          final jitter = report.values['jitter'];
          final transport = _extractTransport(report, stats);
          final candidateRoute = _extractCandidateRoute(report, stats);
          if (rtt != null) {
            logInfo(_tag, 'RTT: ${(rtt * 1000).round()}ms');
            _reportMetric(
              'health_sample',
              networkType: transport,
              rttMs: (rtt as num).toDouble() * 1000,
              packetLoss: packetLoss is num ? packetLoss.toDouble() : null,
              jitterMs: jitter is num ? jitter.toDouble() : null,
              detail: candidateRoute,
            );
          }
        }
      }
    } catch (e) {
      // Stats might not be available on all platforms.
    }
  }

  void _reportMetric(
    String eventType, {
    String networkType = '',
    String iceState = '',
    double? rttMs,
    double? packetLoss,
    double? jitterMs,
    String detail = '',
  }) {
    if (_callId == null || _callId!.isEmpty) return;
    SignalingService.instance.send({
      'type': MsgType.metricsReport,
      'callId': _callId,
      'eventType': eventType,
      if (networkType.isNotEmpty) 'networkType': networkType,
      'iceState': iceState,
      if (rttMs != null) 'rttMs': rttMs,
      if (packetLoss != null) 'packetLoss': packetLoss,
      if (jitterMs != null) 'jitterMs': jitterMs,
      if (detail.isNotEmpty) 'detail': detail,
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
    });
  }

  String _extractTransport(StatsReport pair, List<StatsReport> stats) {
    final protocol = pair.values['protocol'];
    if (protocol is String && protocol.isNotEmpty) {
      return protocol.toLowerCase();
    }

    final byId = <String, StatsReport>{for (final s in stats) s.id: s};
    final localId = pair.values['localCandidateId'];
    final remoteId = pair.values['remoteCandidateId'];
    final local = localId is String ? byId[localId] : null;
    final remote = remoteId is String ? byId[remoteId] : null;

    final localType = local?.values['candidateType'];
    final remoteType = remote?.values['candidateType'];
    if (localType == 'relay' || remoteType == 'relay') {
      return 'relay';
    }
    return 'udp';
  }

  String _extractCandidateRoute(StatsReport pair, List<StatsReport> stats) {
    final byId = <String, StatsReport>{for (final s in stats) s.id: s};
    final localId = pair.values['localCandidateId'];
    final remoteId = pair.values['remoteCandidateId'];
    final local = localId is String ? byId[localId] : null;
    final remote = remoteId is String ? byId[remoteId] : null;

    final localType = (local?.values['candidateType'] as String?) ?? 'unknown';
    final remoteType = (remote?.values['candidateType'] as String?) ?? 'unknown';
    return 'route:$localType->$remoteType';
  }

  // ── Signaling Message Handler ───────────────────────────────────────

  void _onSignalingMessage(SignalingMessage msg) {
    switch (msg.type) {
      case MsgType.webrtcOffer:
        _handleOffer(msg.payload);
      case MsgType.webrtcAnswer:
        _handleAnswer(msg.payload);
      case MsgType.webrtcIce:
        _handleIceCandidate(msg.payload);
      default:
        break; // Not a WebRTC message.
    }
  }
}
