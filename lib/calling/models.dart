// Aanchal — Calling Models & Constants
//
// Shared data models and message-type constants for the calling module.
// Mirror of the server-side schema. Client NEVER decides call state —
// it reads state from these models, which are populated by server messages.

import 'dart:convert';

// ─── Call State ──────────────────────────────────────────────────────────────

/// Server-authoritative call states.
enum CallState {
  idle,
  ringing,
  connecting,
  inCall,
  reconnecting,
  ended;

  static CallState fromServer(String value) {
    switch (value) {
      case 'RINGING':
        return CallState.ringing;
      case 'CONNECTING':
        return CallState.connecting;
      case 'IN_CALL':
        return CallState.inCall;
      case 'RECONNECTING':
        return CallState.reconnecting;
      case 'ENDED':
        return CallState.ended;
      default:
        return CallState.idle;
    }
  }
}

// ─── Call Data ───────────────────────────────────────────────────────────────

/// Immutable snapshot of a call as received from the server.
class CallData {
  final String callId;
  final String callerId;
  final String calleeId;
  final String callerName;
  final String calleeName;
  final CallState state;
  final double? createdAt;
  final double? answeredAt;
  final double? endedAt;
  final String endReason;

  const CallData({
    required this.callId,
    required this.callerId,
    required this.calleeId,
    this.callerName = '',
    this.calleeName = '',
    this.state = CallState.idle,
    this.createdAt,
    this.answeredAt,
    this.endedAt,
    this.endReason = '',
  });

  factory CallData.fromJson(Map<String, dynamic> json) {
    return CallData(
      callId: json['callId'] as String? ?? '',
      callerId: json['callerId'] as String? ?? '',
      calleeId: json['calleeId'] as String? ?? '',
      callerName: json['callerName'] as String? ?? '',
      calleeName: json['calleeName'] as String? ?? '',
      state: CallState.fromServer(json['state'] as String? ?? ''),
      createdAt: (json['createdAt'] as num?)?.toDouble(),
      answeredAt: (json['answeredAt'] as num?)?.toDouble(),
      endedAt: (json['endedAt'] as num?)?.toDouble(),
      endReason: json['endReason'] as String? ?? '',
    );
  }

  /// Is the current user the caller?
  bool isCaller(String myUid) => callerId == myUid;

  /// The peer's UID from the current user's perspective.
  String peerId(String myUid) => isCaller(myUid) ? calleeId : callerId;

  /// The peer's display name from the current user's perspective.
  String peerName(String myUid) => isCaller(myUid) ? calleeName : callerName;

  @override
  String toString() =>
      'CallData(callId=$callId, state=$state, caller=$callerId, callee=$calleeId)';
}

// ─── Signaling Message ───────────────────────────────────────────────────────

/// A message sent to/from the signaling server.
class SignalingMessage {
  final String type;
  final Map<String, dynamic> payload;

  const SignalingMessage({required this.type, this.payload = const {}});

  factory SignalingMessage.fromJson(Map<String, dynamic> json) {
    return SignalingMessage(type: json['type'] as String? ?? '', payload: json);
  }

  /// Extract embedded CallData if present.
  CallData? get callData {
    final callJson = payload['call'] as Map<String, dynamic>?;
    return callJson != null ? CallData.fromJson(callJson) : null;
  }

  String toJsonString() => jsonEncode(payload);

  @override
  String toString() => 'SignalingMessage(type=$type)';
}

// ─── Message Type Constants ──────────────────────────────────────────────────

abstract class MsgType {
  // Client → Server
  static const callInitiate = 'call:initiate';
  static const callAccept = 'call:accept';
  static const callReject = 'call:reject';
  static const callEnd = 'call:end';
  static const callIceConnected = 'call:ice_connected';
  static const requestSync = 'server:request_sync';
  static const metricsReport = 'metrics:report';

  // Server → Client
  static const callRinging = 'call:ringing';
  static const callIncoming = 'call:incoming';
  static const callAccepted = 'call:accepted';
  static const callEnded = 'call:ended';
  static const callConnected = 'call:connected';
  static const callReconnecting = 'call:reconnecting';
  static const callCalleeOffline = 'call:callee_offline';
  static const syncState = 'server:sync_state';
  static const serverError = 'server:error';
  static const serverPing = 'server:ping';

  // WebRTC relay
  static const webrtcOffer = 'webrtc:offer';
  static const webrtcAnswer = 'webrtc:answer';
  static const webrtcIce = 'webrtc:ice';
}
