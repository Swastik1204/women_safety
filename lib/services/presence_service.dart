// Aanchal — Presence Service
//
// Manages live online/offline status with:
//   • Heartbeat: updates `lastSeen` in Firestore every 60 s while foregrounded
//   • AppLifecycle: marks online on resume, offline on pause/detach
//   • Stale check: treats `lastSeen` older than 2 min as effectively offline
//
// Backend keepalive is handled by SignalingService (WS ping every 25s).
//
// Usage:
//   PresenceService.instance.start(uid);   // call after login
//   PresenceService.instance.stop();       // call on logout / dispose

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../core/logger.dart';

const _tag = 'PresenceService';

/// How often to push a heartbeat to Firestore (seconds).
const _heartbeatIntervalSec = 60;

/// Delay before marking offline to absorb transient lifecycle churn
/// (IME/focus changes, brief overlays, fast app switches).
const _offlineDebounce = Duration(seconds: 3);

/// If `lastSeen` is older than this, the user is treated as offline
/// regardless of the `online` field (handles force-kills).
const _staleDuration = Duration(minutes: 2);

class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  String? _uid;
  Timer? _heartbeat;
  Timer? _pendingOffline;
  bool _isOnline = false;
  bool _observerAttached = false;

  // ─── Public API ────────────────────────────────────────────────────

  /// Begin tracking presence for [uid]. Call once after successful login.
  void start(String uid) {
    if (_uid == uid && _observerAttached) {
      _cancelPendingOffline();
      _goOnline();
      return;
    }

    if (_uid != null && _uid != uid) {
      _goOffline();
    }

    _uid = uid;
    _cancelPendingOffline();
    if (!_observerAttached) {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    }
    _goOnline();
    logInfo(_tag, 'Presence started for $uid');
  }

  /// Stop tracking. Call on logout or when the shell is disposed.
  void stop() {
    if (_uid == null && !_observerAttached) return;

    _cancelPendingOffline();
    _goOffline();
    if (_observerAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAttached = false;
    }
    _uid = null;
    logInfo(_tag, 'Presence stopped');
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _cancelPendingOffline();
        _goOnline();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _scheduleOffline();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Transient focus/visibility states can occur without true backgrounding.
        // Avoid flipping presence offline here.
        break;
    }
  }

  // ─── Static Helpers ────────────────────────────────────────────────

  /// Returns `true` if the user should be considered online.
  /// Combines the `online` boolean with a freshness check on `lastSeen`.
  static bool isRecentlyOnline({
    required bool onlineFlag,
    required dynamic lastSeen,
  }) {
    if (!onlineFlag) return false;
    final ts = _asDateTime(lastSeen);
    if (ts == null) return false;

    return DateTime.now().difference(ts) < _staleDuration;
  }

  /// Formats the `lastSeen` timestamp into a human-readable string.
  static String formatLastSeen(dynamic lastSeen) {
    if (lastSeen == null) return 'Never';

    final ts = _asDateTime(lastSeen);
    if (ts == null) return 'Unknown';

    final now = DateTime.now();
    final diff = now.difference(ts);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m min${m > 1 ? 's' : ''} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hour${h > 1 ? 's' : ''} ago';
    }
    final d = diff.inDays;
    if (d == 1) return 'Yesterday';
    if (d < 7) return '$d days ago';
    return '${ts.day}/${ts.month}/${ts.year}';
  }

  /// Handles schema transitions where older docs may still use `lastSeenAt`.
  static dynamic resolveLastSeen(Map<String, dynamic> data) {
    return data['lastSeen'] ?? data['lastSeenAt'];
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  // ─── Internal ──────────────────────────────────────────────────────

  void _goOnline() {
    _cancelPendingOffline();
    if (_uid == null || _isOnline) return;
    _isOnline = true;
    _updateFirestore(true);
    _startHeartbeat();
    logInfo(_tag, 'Status → online');
  }

  void _goOffline() {
    if (_uid == null || !_isOnline) return;
    _isOnline = false;
    _stopHeartbeat();
    _updateFirestore(false);
    logInfo(_tag, 'Status → offline');
  }

  void _scheduleOffline() {
    if (_uid == null || !_isOnline) return;
    _pendingOffline?.cancel();
    _pendingOffline = Timer(_offlineDebounce, _goOffline);
    logDebug(_tag, 'Offline scheduled in ${_offlineDebounce.inSeconds}s');
  }

  void _cancelPendingOffline() {
    _pendingOffline?.cancel();
    _pendingOffline = null;
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeat = Timer.periodic(
      const Duration(seconds: _heartbeatIntervalSec),
      (_) => _updateFirestore(true),
    );
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  // ─── Firestore Update ──────────────────────────────────────────────

  Future<void> _updateFirestore(bool online) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'online': online,
        'lastSeen': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      logError(_tag, 'Firestore presence update failed: $e');
    }
  }
}
