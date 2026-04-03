// Aanchal — Call Screen
//
// Full call UI with server-authoritative state display.
// States: Ringing, Connecting, In Call, Reconnecting, Call Ended.
// Features: mute, speaker, duration timer, wakelock.
//
// This screen only READS state from CallStateManager and WebRTCEngine.
// All mutations go through the server (via CallStateManager actions).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/auth_service.dart';
import '../services/call_history_service.dart';
import '../core/logger.dart';
import 'models.dart';
import 'call_state_manager.dart';
import 'call_notification.dart';
import 'webrtc_engine.dart';

const _tag = 'CallScreen';

class CallScreen extends StatefulWidget {
  final UserProfile currentUser;
  final String peerId;
  final String peerName;
  final bool isOutgoing;

  /// If non-null, this is an incoming call that was already created on server.
  final CallData? incomingCallData;

  const CallScreen({
    super.key,
    required this.currentUser,
    required this.peerId,
    required this.peerName,
    required this.isOutgoing,
    this.incomingCallData,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _engine = WebRTCEngine();
  final _csm = CallStateManager.instance;

  CallState _state = CallState.idle;
  String _statusText = '';
  String? _callId;
  bool _iceConnected = false;

  // Duration timer.
  Timer? _durationTimer;
  int _durationSeconds = 0;

  // State subscription.
  StreamSubscription<CallData?>? _callSub;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _setupListeners();

    if (widget.isOutgoing) {
      _initiateCall();
    } else if (widget.incomingCallData != null) {
      _callId = widget.incomingCallData!.callId;
      _state = widget.incomingCallData!.state;
      _updateStatus();
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _callSub?.cancel();
    _engine.closeConnection();
    WakelockPlus.disable();
    super.dispose();
  }

  // ── Setup ──────────────────────────────────────────────────────────

  void _setupListeners() {
    // Listen to call state changes from server.
    _callSub = _csm.callStream.listen((callData) {
      if (callData == null) {
        // Call cleared.
        if (mounted && _state != CallState.ended) {
          setState(() {
            _state = CallState.ended;
            _statusText = 'Call Ended';
          });
          _onCallEnded();
        }
        return;
      }

      // Only process if this is our call.
      if (_callId != null && callData.callId != _callId) return;

      final oldState = _state;
      _callId = callData.callId;

      setState(() {
        _state = callData.state;
        _updateStatus();
      });

      // State transition actions.
      if (callData.state == CallState.connecting &&
          oldState != CallState.connecting) {
        _onCallAccepted(callData);
      } else if (callData.state == CallState.inCall &&
          oldState != CallState.inCall) {
        _onCallConnected();
      } else if (callData.state == CallState.ended &&
          oldState != CallState.ended) {
        _onCallEnded();
      }
    });

    // WebRTC engine callbacks.
    _engine.onIceConnected = () {
      if (_callId != null && !_iceConnected) {
        _iceConnected = true;
        _csm.reportIceConnected(_callId!);
        logInfo(_tag, 'ICE connected — reported to server');
      }
    };

    _engine.onIceFailed = () {
      logError(_tag, 'ICE failed permanently');
      if (_callId != null) {
        _csm.endCall(_callId!, reason: 'ice_failed');
      }
    };

    _engine.onIceDisconnected = () {
      if (mounted) {
        setState(() => _statusText = 'Reconnecting...');
      }
    };

    _engine.onIceStateChanged = (state) {
      if (!mounted) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        setState(() => _updateStatus());
      }
    };
  }

  // ── Call Flow ──────────────────────────────────────────────────────

  void _initiateCall() {
    _statusText = 'Calling...';
    final sent = _csm.initiateCall(
      widget.peerId,
      callerName: widget.currentUser.firstName,
      calleeName: widget.peerName,
    );
    if (!sent) {
      setState(() {
        _state = CallState.ended;
        _statusText = 'Failed to connect';
      });
      _scheduleClose();
    }
  }

  void _acceptCall() {
    if (_callId == null) return;
    _csm.acceptCall(_callId!);
    // Dismiss notification.
    CallNotificationService.instance.dismissNotification(_callId!);
  }

  void _rejectCall() {
    if (_callId == null) return;
    _csm.rejectCall(_callId!);
    CallNotificationService.instance.dismissNotification(_callId!);
  }

  void _hangUp() {
    if (_callId == null) {
      Navigator.of(context).pop();
      return;
    }
    _csm.endCall(_callId!);
  }

  // ── State Transition Handlers ──────────────────────────────────────

  Future<void> _onCallAccepted(CallData callData) async {
    logInfo(_tag, 'Call accepted — starting WebRTC');
    CallNotificationService.instance.dismissNotification(callData.callId);

    final localIsCaller = callData.isCaller(widget.currentUser.uid);

    await _engine.createConnection(
      callId: callData.callId,
      peerId: callData.peerId(widget.currentUser.uid),
      isCaller: localIsCaller,
    );

    if (localIsCaller) {
      await _engine.createAndSendOffer();
    }

    // Save call history.
    _saveCallHistory(callData, 'connecting');
  }

  void _onCallConnected() {
    logInfo(_tag, 'Call connected — starting timer');
    _startDurationTimer();
    _saveCallHistoryUpdate('in_call');
  }

  void _onCallEnded() {
    _durationTimer?.cancel();
    _engine.closeConnection();
    _saveCallHistoryUpdate('ended');
    if (_callId != null) {
      CallNotificationService.instance.reportCallEnded(_callId!);
    }
    _scheduleClose();
  }

  void _scheduleClose() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  // ── Duration Timer ─────────────────────────────────────────────────

  void _startDurationTimer() {
    _durationSeconds = 0;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _durationSeconds++);
    });
  }

  String _formatDuration() {
    final m = (_durationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_durationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Status Text ────────────────────────────────────────────────────

  void _updateStatus() {
    switch (_state) {
      case CallState.idle:
        _statusText = 'Initializing...';
      case CallState.ringing:
        _statusText = widget.isOutgoing ? 'Ringing...' : 'Incoming Call';
      case CallState.connecting:
        _statusText = 'Connecting...';
      case CallState.inCall:
        _statusText = _formatDuration();
      case CallState.reconnecting:
        _statusText = 'Reconnecting...';
      case CallState.ended:
        _statusText = 'Call Ended';
    }
  }

  // ── Call History ────────────────────────────────────────────────────

  void _saveCallHistory(CallData call, String status) {
    CallHistoryService.upsert(call.callId, {
      'callerId': call.callerId,
      'calleeId': call.calleeId,
      'callerName': call.callerName,
      'calleeName': widget.peerName,
      'status': status,
      'startedAt': DateTime.now().toIso8601String(),
    });
  }

  void _saveCallHistoryUpdate(String status) {
    if (_callId == null) return;
    final data = <String, dynamic>{'status': status};
    if (status == 'ended') {
      data['duration'] = _durationSeconds;
      data['endedAt'] = DateTime.now().toIso8601String();
    }
    CallHistoryService.upsert(_callId!, data);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),

            // ── Peer Info ──
            _buildAvatar(scheme),
            const SizedBox(height: 20),
            Text(
              widget.peerName,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _state == CallState.inCall ? _formatDuration() : _statusText,
              style: TextStyle(fontSize: 16, color: _statusColor),
            ),

            const Spacer(),

            // ── Controls ──
            if (_state == CallState.ringing && !widget.isOutgoing)
              _buildIncomingControls(scheme)
            else if (_state == CallState.ended)
              _buildEndedInfo()
            else
              _buildInCallControls(scheme),

            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(ColorScheme scheme) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.3),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Center(
        child: Text(
          widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Color get _statusColor {
    switch (_state) {
      case CallState.ringing:
        return Colors.amber;
      case CallState.connecting:
        return Colors.orange;
      case CallState.inCall:
        return Colors.greenAccent;
      case CallState.reconnecting:
        return Colors.amberAccent;
      case CallState.ended:
        return Colors.redAccent;
      default:
        return Colors.white70;
    }
  }

  Widget _buildIncomingControls(ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Reject
        _CircleButton(
          icon: Icons.call_end,
          color: Colors.red,
          label: 'Decline',
          onTap: _rejectCall,
          size: 72,
        ),
        // Accept
        _CircleButton(
          icon: Icons.call,
          color: Colors.green,
          label: 'Accept',
          onTap: _acceptCall,
          size: 72,
        ),
      ],
    );
  }

  Widget _buildInCallControls(ColorScheme scheme) {
    return Column(
      children: [
        // Mute + Speaker row.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CircleButton(
              icon: _engine.isMuted ? Icons.mic_off : Icons.mic,
              color: _engine.isMuted ? Colors.red : Colors.white24,
              label: _engine.isMuted ? 'Unmute' : 'Mute',
              onTap: () {
                _engine.toggleMute();
                setState(() {});
              },
            ),
            const SizedBox(width: 40),
            _CircleButton(
              icon: _engine.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
              color: _engine.isSpeakerOn ? Colors.blueAccent : Colors.white24,
              label: 'Speaker',
              onTap: () {
                _engine.toggleSpeaker();
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 40),
        // Hang up.
        _CircleButton(
          icon: Icons.call_end,
          color: Colors.red,
          label: _state == CallState.ringing ? 'Cancel' : 'End Call',
          onTap: _hangUp,
          size: 72,
        ),
      ],
    );
  }

  Widget _buildEndedInfo() {
    final endMsg = _csm.currentCall?.endReason ?? '';
    String displayReason;
    switch (endMsg) {
      case 'ring_timeout':
        displayReason = 'No answer';
      case 'rejected':
        displayReason = 'Call declined';
      case 'peer_disconnected':
        displayReason = 'Peer disconnected';
      case 'ice_failed':
        displayReason = 'Connection failed';
      case 'connect_timeout':
        displayReason = 'Connection timed out';
      default:
        displayReason = 'Call ended';
    }

    return Column(
      children: [
        const Icon(Icons.call_end, size: 48, color: Colors.redAccent),
        const SizedBox(height: 12),
        Text(
          displayReason,
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        if (_durationSeconds > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Duration: ${_formatDuration()}',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ],
    );
  }
}

// ─── Reusable Circle Button ──────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final double size;

  const _CircleButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
