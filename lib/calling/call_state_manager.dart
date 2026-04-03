// Aanchal — Call State Manager
//
// Client-side mirror of the server-authoritative call state.
// This class:
//   • Listens to signaling messages
//   • Maintains current CallData
//   • Provides a stream of state changes for UI consumption
//   • Sends call actions to the server (initiate, accept, reject, end)
//   • NEVER decides call state locally — always waits for server confirmation
//
// Usage:
//   CallStateManager.instance.init(userId, displayName);
//   CallStateManager.instance.callStream.listen((data) { ... });
//   CallStateManager.instance.initiateCall(peerId);

import 'dart:async';

import '../core/logger.dart';
import 'models.dart';
import 'signaling_service.dart';

const _tag = 'CallStateManager';

/// Callback invoked when an incoming call arrives (for showing notification/screen).
typedef IncomingCallCallback = void Function(CallData callData);

class CallStateManager {
  CallStateManager._();
  static final CallStateManager instance = CallStateManager._();

  // ── State ──────────────────────────────────────────────────────────
  String? _userId;
  String _displayName = '';
  CallData? _currentCall;

  /// Stream controller for call state changes.
  final _callController = StreamController<CallData?>.broadcast();

  /// Stream of call state changes. UI subscribes to this.
  Stream<CallData?> get callStream => _callController.stream;

  /// Current call data (null if no active call).
  CallData? get currentCall => _currentCall;

  /// Callback for incoming calls (set by the app to show call screen).
  IncomingCallCallback? onIncomingCall;

  /// Callback for when a call ends.
  void Function(CallData callData)? onCallEnded;

  // ── Lifecycle ──────────────────────────────────────────────────────

  /// Initialize the call state manager. Call after login.
  void init(String userId, {String displayName = ''}) {
    _userId = userId;
    _displayName = displayName;
    SignalingService.instance.addListener(_onSignalingMessage);
    logInfo(_tag, 'Initialized for $userId');
  }

  /// Dispose. Call on logout.
  void dispose() {
    SignalingService.instance.removeListener(_onSignalingMessage);
    _currentCall = null;
    _callController.add(null);
    _userId = null;
    logInfo(_tag, 'Disposed');
  }

  // ── Call Actions (sent to server) ──────────────────────────────────

  /// Initiate a call to [calleeId].
  bool initiateCall(String calleeId, {String callerName = '', String calleeName = ''}) {
    if (_userId == null) return false;
    if (_currentCall != null && _currentCall!.state != CallState.ended) {
      logWarn(_tag, 'Already in a call');
      return false;
    }
    final name = callerName.isNotEmpty ? callerName : _displayName;
    return SignalingService.instance.send({
      'type': MsgType.callInitiate,
      'toUserId': calleeId,
      'callerName': name,
      'calleeName': calleeName,
    });
  }

  /// Ask server to resync current call state (useful after FCM wake-up).
  void requestSync() {
    SignalingService.instance.requestSync();
  }

  /// Accept an incoming call.
  bool acceptCall(String callId) {
    if (_userId == null) return false;
    final sent = SignalingService.instance.send({
      'type': MsgType.callAccept,
      'callId': callId,
    });
    // REST fallback if WS send fails.
    if (!sent) {
      logWarn(_tag, 'WS send failed for accept — trying REST');
      SignalingService.instance.restAcceptCall(_userId!, callId);
    }
    return sent;
  }

  /// Reject an incoming call.
  bool rejectCall(String callId, {String reason = 'rejected'}) {
    if (_userId == null) return false;
    final sent = SignalingService.instance.send({
      'type': MsgType.callReject,
      'callId': callId,
      'reason': reason,
    });
    if (!sent) {
      logWarn(_tag, 'WS send failed for reject — trying REST');
      SignalingService.instance
          .restRejectCall(_userId!, callId, reason: reason);
    }
    return sent;
  }

  /// End an active call. Either party can call this.
  bool endCall(String callId, {String reason = 'ended'}) {
    if (_userId == null) return false;
    final sent = SignalingService.instance.send({
      'type': MsgType.callEnd,
      'callId': callId,
      'reason': reason,
    });
    if (!sent) {
      logWarn(_tag, 'WS send failed for end — trying REST');
      SignalingService.instance.restEndCall(_userId!, callId, reason: reason);
    }
    return sent;
  }

  /// Report to server that ICE connection is established.
  void reportIceConnected(String callId) {
    SignalingService.instance.send({
      'type': MsgType.callIceConnected,
      'callId': callId,
    });
  }

  // ── Signaling Message Handler ──────────────────────────────────────

  void _onSignalingMessage(SignalingMessage msg) {
    switch (msg.type) {
      // ── Outgoing call confirmed ringing ──
      case MsgType.callRinging:
        final call = msg.callData;
        if (call != null) {
          _updateCall(call);
          logInfo(_tag, 'Call ringing: ${call.callId}');
        }

      // ── Incoming call ──
      case MsgType.callIncoming:
        final call = msg.callData;
        if (call != null) {
          _updateCall(call);
          logInfo(_tag, 'Incoming call: ${call.callId} from ${call.callerName}');
          onIncomingCall?.call(call);
        }

      // ── Call accepted → CONNECTING ──
      case MsgType.callAccepted:
        final call = msg.callData;
        if (call != null) {
          _updateCall(call);
          logInfo(_tag, 'Call accepted → CONNECTING: ${call.callId}');
        }

      // ── Call connected → IN_CALL ──
      case MsgType.callConnected:
        final call = msg.callData;
        if (call != null) {
          _updateCall(call);
          logInfo(_tag, 'Call connected → IN_CALL: ${call.callId}');
        }

      // ── Call reconnecting ──
      case MsgType.callReconnecting:
        final call = msg.callData;
        if (call != null) {
          _updateCall(call);
          logInfo(_tag, 'Call reconnecting: ${call.callId}');
          SignalingService.instance.send({
            'type': MsgType.metricsReport,
            'callId': call.callId,
            'eventType': 'reconnect_attempt',
            'detail': 'server_reconnecting_state',
            'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
          });
        }

      // ── Call ended ──
      case MsgType.callEnded:
        final call = msg.callData;
        if (call != null) {
          _updateCall(call);
          logInfo(_tag, 'Call ended: ${call.callId} reason=${call.endReason}');
          onCallEnded?.call(call);
          // Clear current call after a brief delay (let UI show "Call Ended").
          Future.delayed(const Duration(seconds: 2), () {
            if (_currentCall?.callId == call.callId) {
              _currentCall = null;
              _callController.add(null);
            }
          });
        }

      // ── Callee offline (FCM needed) ──
      case MsgType.callCalleeOffline:
        final call = msg.callData;
        if (call != null) {
          _updateCall(call);
          logInfo(_tag, 'Callee offline — FCM push needed');
        }

      // ── Server resync ──
      case MsgType.syncState:
        final call = msg.callData;
        if (call != null) {
          final wasDifferentCall = _currentCall?.callId != call.callId;
          _updateCall(call);
          logInfo(_tag, 'Resync: call ${call.callId} state=${call.state}');

          final isCallee = _userId != null && call.calleeId == _userId;
          if (isCallee && call.state == CallState.ringing && wasDifferentCall) {
            onIncomingCall?.call(call);
          }
        } else {
          // No active call on server.
          if (_currentCall != null) {
            logInfo(_tag, 'Resync: no active call — clearing local state');
            _currentCall = null;
            _callController.add(null);
          }
        }

      // ── Server error ──
      case MsgType.serverError:
        final message = msg.payload['message'] as String? ?? 'Unknown error';
        logError(_tag, 'Server error: $message');

      default:
        break; // WebRTC relay messages handled by WebRTCEngine.
    }
  }

  void _updateCall(CallData call) {
    _currentCall = call;
    _callController.add(call);
  }
}
