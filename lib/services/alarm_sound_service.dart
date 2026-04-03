import 'dart:async';

import 'package:flutter/services.dart';

import '../core/logger.dart';

const _tag = 'AlarmSoundService';
const _channel = MethodChannel('com.aanchal/alarm');

/// Plays a loud looping alarm sound and (best-effort) forces system volume up.
///
/// Android implementation lives in `MainActivity.kt`.
class AlarmSoundService {
  AlarmSoundService._();

  static bool _isRunning = false;

  static bool get isRunning => _isRunning;

  /// Starts looping the given asset.
  ///
  /// Asset should be bundled in Flutter assets (e.g. `assets/sounds/sound.mp3`).
  static Future<void> start({
    String asset = 'assets/sounds/sound.mp3',
    Duration rampDuration = const Duration(seconds: 3),
    bool enforceMaxVolume = true,
  }) async {
    if (_isRunning) return;

    try {
      await _channel.invokeMethod<void>('start', <String, Object?>{
        'asset': asset,
        'rampMs': rampDuration.inMilliseconds,
        'enforceMax': enforceMaxVolume,
        'stream': 'alarm',
      });
      _isRunning = true;
    } on PlatformException catch (e) {
      logError(_tag, 'start failed: ${e.code} ${e.message}');
    } catch (e) {
      logError(_tag, 'start failed: $e');
    }
  }

  static Future<void> stop({bool restorePreviousVolume = true}) async {
    if (!_isRunning) return;

    try {
      await _channel.invokeMethod<void>('stop', <String, Object?>{
        'restoreVolume': restorePreviousVolume,
      });
    } on PlatformException catch (e) {
      logError(_tag, 'stop failed: ${e.code} ${e.message}');
    } catch (e) {
      logError(_tag, 'stop failed: $e');
    } finally {
      _isRunning = false;
    }
  }
}
