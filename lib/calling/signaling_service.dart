// Aanchal — Signaling Service
//
// ONE persistent WebSocket connection to the signaling server.
// Responsibilities:
//   • Connect/reconnect with exponential backoff
//   • Send messages (WS primary, REST fallback)
//   • Dispatch incoming messages to listeners
//   • Server ping/pong to keep WS alive through Render proxy
//   • Auto request resync after reconnect
//
// This service does NOT interpret call state — it simply relays messages.

// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../core/app_config.dart';
import '../core/logger.dart';
import 'models.dart';

const _tag = 'SignalingService';

typedef MessageCallback = void Function(SignalingMessage message);

class SignalingService {
  SignalingService._();
  static final SignalingService instance = SignalingService._();

  // ── State ──────────────────────────────────────────────────────────
  String? _userId;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;
  bool _connected = false;

  /// Listeners that receive every incoming signaling message.
  final List<MessageCallback> _listeners = [];

  bool get isConnected => _connected;

  // ── Public API ─────────────────────────────────────────────────────

  /// Connect to signaling server for [userId]. Call once after login.
  Future<void> connect(String userId) async {
    _disposed = false;
    _userId = userId;
    _reconnectAttempt = 0;
    await _doConnect();
  }

  /// Disconnect and clean up.
  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close(ws_status.goingAway);
    _channel = null;
    _connected = false;
    _userId = null;
    logInfo(_tag, 'Disconnected');
  }

  /// Add a listener for incoming messages.
  void addListener(MessageCallback cb) => _listeners.add(cb);

  /// Remove a listener.
  void removeListener(MessageCallback cb) => _listeners.remove(cb);

  /// Send a message via WebSocket.
  bool send(Map<String, dynamic> message) {
    if (_channel == null || !_connected) {
      logWarn(_tag, 'Cannot send — WS not connected');
      return false;
    }
    try {
      _channel!.sink.add(jsonEncode(message));
      return true;
    } catch (e) {
      logError(_tag, 'Send error: $e');
      return false;
    }
  }

  /// REST fallback: accept call when WS is down.
  Future<bool> restAcceptCall(String userId, String callId) async {
    return _restCallAction('/api/call/accept', userId, callId);
  }

  /// REST fallback: reject call when WS is down.
  Future<bool> restRejectCall(
    String userId,
    String callId, {
    String reason = 'rejected',
  }) async {
    return _restCallAction('/api/call/reject', userId, callId, reason: reason);
  }

  /// REST fallback: end call when WS is down.
  Future<bool> restEndCall(
    String userId,
    String callId, {
    String reason = 'ended',
  }) async {
    return _restCallAction('/api/call/end', userId, callId, reason: reason);
  }

  /// Request server to send current call state (after reconnect).
  void requestSync() {
    send({'type': MsgType.requestSync});
  }

  // ── WebSocket Connection ───────────────────────────────────────────

  Future<void> _doConnect() async {
    if (_disposed || _userId == null) return;

    // Fast return: Backend removed WebRTC/WebSocket support.
    // Setting connected to false prevents reconnection loops while gracefully shutting down logic.
    _connected = false;
    logInfo(_tag, 'WebSocket connection skipped — disabled on backend.');
    return;
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';

      // Handle server ping internally — don't propagate.
      if (type == MsgType.serverPing) {
        send({'type': 'server:pong'});
        return;
      }

      final message = SignalingMessage.fromJson(json);
      for (final cb in List<MessageCallback>.from(_listeners)) {
        try {
          cb(message);
        } catch (e) {
          logError(_tag, 'Listener error: $e');
        }
      }
    } catch (e) {
      logError(
        _tag,
        'Parse error: $e — raw: ${raw.toString().substring(0, min(120, raw.toString().length))}',
      );
    }
  }

  void _onDisconnected() {
    _connected = false;
    _subscription?.cancel();
    _subscription = null;
    logWarn(_tag, 'Disconnected from server');
    if (!_disposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();

    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s max.
    final delaySec = min(30, pow(2, _reconnectAttempt).toInt());
    _reconnectAttempt++;
    logInfo(_tag, 'Reconnecting in ${delaySec}s...');

    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (!_disposed) _doConnect();
    });
  }

  // ── REST Fallback ──────────────────────────────────────────────────

  Future<bool> _restCallAction(
    String path,
    String userId,
    String callId, {
    String reason = '',
  }) async {
    try {
      final url = Uri.parse('${AppConfig.backendBaseUrl}$path');
      final body = jsonEncode({
        'userId': userId,
        'callId': callId,
        if (reason.isNotEmpty) 'reason': reason,
      });
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(AppConfig.apiTimeout);
      logInfo(_tag, 'REST $path → ${response.statusCode}');
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      logError(_tag, 'REST $path failed: $e');
      return false;
    }
  }
}
