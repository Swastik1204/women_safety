// Aanchal — Watch Connectivity Service
//
// Listens for messages from the paired Apple Watch (via WatchConnectivity).
// When the Watch sends an "SOS" action, this service triggers SOSService.activate()
// and optionally navigates the UI to the SOS screen.
// Also syncs the current user's profile to the Watch so it displays
// the connected user's name and shares the same user ID.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import '../core/logger.dart';
import 'sos_service.dart';
import 'auth_service.dart';

const _tag = 'WatchConnectivityService';

class WatchConnectivityService {
  WatchConnectivityService._();
  static final WatchConnectivityService instance = WatchConnectivityService._();

  final _watch = WatchConnectivity();

  StreamSubscription<Map<String, dynamic>>? _messageSub;
  bool _initialised = false;
  bool _watchApiAvailable = false;

  /// The currently synced user profile (sent to the watch).
  UserProfile? _currentUser;

  /// Callback that the UI layer can set to react to a watch-triggered SOS.
  void Function()? onSOSTriggeredFromWatch;

  /// Start listening for incoming watch messages.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    try {
      final supported = await _watch.isSupported;
      if (!supported) {
        _watchApiAvailable = false;
        logWarn(_tag, 'WatchConnectivity not supported on this device');
        return;
      }

      _watchApiAvailable = true;
      logInfo(_tag, 'WatchConnectivity initialised — listening for messages');

      _messageSub = _watch.messageStream.listen(
        _handleMessage,
        onError: (e) {
          if (_isApiUnavailableError(e)) {
            _watchApiAvailable = false;
            logWarn(_tag, 'Watch API unavailable; disabling watch bridge');
            return;
          }
          logWarn(_tag, 'Watch message stream error: $e');
        },
      );
    } catch (e) {
      _watchApiAvailable = false;
      logWarn(_tag, 'WatchConnectivity init failed: $e');
    }
  }

  /// Send the current user's profile to the Watch app so it knows who is
  /// logged in on the iPhone. Call this after login and whenever the
  /// profile changes.
  Future<void> syncUserToWatch(UserProfile profile) async {
    _currentUser = profile;
    if (!_initialised) {
      await init();
    }
    if (!_watchApiAvailable) return;

    final payload = {
      'action': 'USER_SYNC',
      'uid': profile.uid,
      'name': '${profile.firstName} ${profile.lastName}',
      'email': profile.email,
      'aanchalNumber': profile.aanchalNumber,
    };

    try {
      // applicationContext persists — watch gets it even when not running.
      await _watch.updateApplicationContext(payload);
      logInfo(
        _tag,
        'Synced user to watch: ${profile.firstName} (${profile.uid})',
      );
    } catch (e) {
      if (_isApiUnavailableError(e)) {
        _watchApiAvailable = false;
        logWarn(_tag, 'Watch API unavailable on this device; sync disabled');
        return;
      }
      logWarn(_tag, 'Context sync failed, trying message: $e');
      await _sendToWatch(payload);
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    logInfo(_tag, 'Received watch message: $message');

    final action = message['action'];
    if (action == 'SOS') {
      final watchUid = message['uid'] as String?;
      logInfo(_tag, 'SOS from watch (uid: $watchUid)');

      // Verify the watch user matches the phone user.
      final phoneUid =
          _currentUser?.uid ?? FirebaseAuth.instance.currentUser?.uid;

      if (phoneUid != null && watchUid != null && watchUid != phoneUid) {
        logWarn(_tag, 'UID mismatch — watch=$watchUid, phone=$phoneUid');
        unawaited(_sendToWatch({'status': 'SOS_FAILED', 'error': 'User mismatch'}));
        return;
      }
      unawaited(_triggerSOS());
    } else if (action == 'CANCEL_SOS') {
      logInfo(_tag, 'SOS cancelled from Apple Watch');
      SOSService.instance.deactivate();
      unawaited(_sendToWatch({'status': 'SOS_DEACTIVATED'}));
    } else if (action == 'REQUEST_USER') {
      logInfo(_tag, 'Watch requested user profile');
      if (_currentUser != null) {
        unawaited(syncUserToWatch(_currentUser!));
      } else {
        unawaited(_sendToWatch({'status': 'NO_USER', 'error': 'Not signed in'}));
      }
    }
  }

  Future<void> _triggerSOS() async {
    try {
      final userName =
          _currentUser?.firstName ??
          FirebaseAuth.instance.currentUser?.displayName ??
          'User';
      await SOSService.instance.triggerSOS(userName: userName);
      onSOSTriggeredFromWatch?.call();
      await _sendToWatch({'status': 'SOS_ACTIVATED'});
    } catch (e) {
      logError(_tag, 'Failed to activate SOS from watch: $e');
      await _sendToWatch({'status': 'SOS_FAILED', 'error': e.toString()});
    }
  }

  Future<void> _sendToWatch(Map<String, dynamic> message) async {
    if (!_watchApiAvailable) return;
    try {
      await _watch.sendMessage(message);
      logInfo(_tag, 'Sent to watch: $message');
    } catch (e) {
      if (_isApiUnavailableError(e)) {
        _watchApiAvailable = false;
        logWarn(_tag, 'Watch API unavailable; outgoing watch messages disabled');
        return;
      }
      logWarn(_tag, 'Failed to send message to watch: $e');
    }
  }

  bool _isApiUnavailableError(Object error) {
    final text = error.toString();
    return text.contains('API_UNAVAILABLE') ||
        text.contains('Wearable.API is not available') ||
        text.contains('statusCode=API_UNAVAILABLE');
  }

  void dispose() {
    _messageSub?.cancel();
    _messageSub = null;
    _initialised = false;
    _watchApiAvailable = false;
    _currentUser = null;
  }
}
