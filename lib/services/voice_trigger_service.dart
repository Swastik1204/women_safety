// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceTriggerService {
  VoiceTriggerService._();
  static final VoiceTriggerService instance = VoiceTriggerService._();

  static const String _triggerPhrase = 'help me aanchal';

  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  DateTime? _lastTriggerAt;

  bool get isListening => _isListening;

  Future<void> start({required Future<void> Function() onTrigger}) async {
    if (_isListening) return;

    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening') {
          _isListening = false;
        }
      },
      onError: (error) {
        debugPrint('[VoiceTrigger] error: $error');
        _isListening = false;
      },
    );

    if (!available) {
      debugPrint('[VoiceTrigger] Speech recognition unavailable');
      return;
    }

    _isListening = true;
    await _speech.listen(
      onResult: (result) async {
        final text = result.recognizedWords.toLowerCase().trim();
        if (text.isEmpty) return;

        if (text.contains(_triggerPhrase)) {
          final now = DateTime.now();
          if (_lastTriggerAt != null &&
              now.difference(_lastTriggerAt!).inSeconds < 15) {
            return;
          }
          _lastTriggerAt = now;

          debugPrint('[VoiceTrigger] Trigger phrase detected');
          await onTrigger();
        }
      },
      partialResults: true,
      listenMode: ListenMode.dictation,
      cancelOnError: false,
      pauseFor: const Duration(seconds: 3),
      listenFor: const Duration(minutes: 10),
      onDevice: true,
    );
  }

  Future<void> stop() async {
    if (!_isListening) return;
    await _speech.stop();
    _isListening = false;
  }
}
