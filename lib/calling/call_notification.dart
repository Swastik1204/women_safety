// Aanchal — Call Notification Service
//
// Handles incoming call notifications via flutter_callkit_incoming.
// Responsibilities:
//   • Show incoming call UI (native full-screen notification)
//   • Handle accept/reject from notification
//   • Custom ringtone support
//   • Background notification handling
//
// FCM integration is prepared but not active until Firebase Cloud Messaging
// is configured in the project. For now, notifications are triggered
// directly from the signaling layer when a call:incoming message arrives.

import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../core/logger.dart';

const _tag = 'CallNotification';

/// Callback types for notification actions.
typedef NotificationAcceptCallback = void Function(String callId);
typedef NotificationRejectCallback = void Function(String callId);

class CallNotificationService {
  CallNotificationService._();
  static final CallNotificationService instance = CallNotificationService._();

  NotificationAcceptCallback? onAccept;
  NotificationRejectCallback? onReject;

  /// Initialize CallKit event listeners. Call once at app startup.
  void init() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      final bodyRaw = event.body;
      final body = bodyRaw is Map ? Map<Object?, Object?>.from(bodyRaw) : null;
      final extraRaw = body?['extra'];
      final extra = extraRaw is Map ? Map<Object?, Object?>.from(extraRaw) : null;
      final callId = _extractCallId(extra) ?? _extractCallId(body);
      logInfo(_tag, 'CallKit event: ${event.event} callId=$callId');

      switch (event.event) {
        case Event.actionCallAccept:
          if (callId != null) onAccept?.call(callId);
        case Event.actionCallDecline:
          if (callId != null) onReject?.call(callId);
        case Event.actionCallEnded:
          if (callId != null) onReject?.call(callId);
        case Event.actionCallTimeout:
          if (callId != null) onReject?.call(callId);
        default:
          break;
      }
    });
    logInfo(_tag, 'CallKit listeners initialized');
  }

  /// Show an incoming call notification.
  Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    String? callerAvatar,
  }) async {
    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      avatar: callerAvatar,
      handle: callerName,
      type: 0, // Audio call
      duration: 30000, // Ring for 30 seconds
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: <String, dynamic>{'callId': callId},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1a1a2e',
        actionColor: '#7c3aed',
        isShowFullLockedScreen: true,
        isShowCallID: false,
      ),
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
    logInfo(_tag, 'Showing incoming call notification: $callerName');
  }

  /// Dismiss the incoming call notification.
  Future<void> dismissNotification(String callId) async {
    await FlutterCallkitIncoming.endCall(callId);
    logInfo(_tag, 'Dismissed notification: $callId');
  }

  /// Dismiss all notifications.
  Future<void> dismissAll() async {
    await FlutterCallkitIncoming.endAllCalls();
  }

  /// Start an outgoing call (shows "Calling..." notification briefly).
  Future<void> showOutgoingCall({
    required String callId,
    required String calleeName,
  }) async {
    await FlutterCallkitIncoming.startCall(
      CallKitParams(
        id: callId,
        nameCaller: calleeName,
        handle: calleeName,
        type: 0,
        extra: <String, dynamic>{'callId': callId},
        android: const AndroidParams(
          isCustomNotification: true,
          backgroundColor: '#1a1a2e',
          actionColor: '#7c3aed',
        ),
      ),
    );
  }

  /// Report that a call has ended (dismiss all related UI).
  Future<void> reportCallEnded(String callId) async {
    await FlutterCallkitIncoming.endCall(callId);
  }

  // ── Helpers ────────────────────────────────────────────────────────

  String? _extractCallId(Map<Object?, Object?>? data) {
    if (data == null) return null;

    final map = Map<String, dynamic>.from(
      data.map((key, value) => MapEntry(key.toString(), value)),
    );

    return map['callId']?.toString();
  }
}
