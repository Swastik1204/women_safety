import 'dart:convert';
import 'dart:io';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/logger.dart';

const _tag = 'EvidenceService';

class EvidenceService {
  EvidenceService._();
  static final EvidenceService instance = EvidenceService._();

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();

  bool _isRecording = false;
  String? _backendSessionId;
  String? _audioFilePath;
  File? _timelineFile;

  bool get isRecording => _isRecording;
  String? get audioFilePath => _audioFilePath;

  Future<void> startEvidenceCapture({
    required String sessionId,
    bool includeVideo = false,
  }) async {
    if (_isRecording) return;

    final baseDir = await getApplicationDocumentsDirectory();
    final evidenceDir = Directory('${baseDir.path}/evidence/$sessionId');
    await evidenceDir.create(recursive: true);

    _audioFilePath = '${evidenceDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.aac';
    _timelineFile = File('${evidenceDir.path}/timeline.jsonl');

    await _appendTimeline('evidence_started', {
      'localSessionId': sessionId,
      'includeVideo': includeVideo,
      'timestamp': DateTime.now().toIso8601String(),
    });

    final micPermission = await Permission.microphone.request();
    if (!micPermission.isGranted) {
      logWarn(_tag, 'Microphone permission denied; skipping audio recording');
      await _appendTimeline('audio_start_skipped_permission_denied', {
        'permissionStatus': micPermission.toString(),
      });
      return;
    }

    try {
      await _recorder.openRecorder();
      await _recorder.startRecorder(
        toFile: _audioFilePath,
        codec: Codec.aacADTS,
      );
      _isRecording = true;
      logInfo(_tag, 'Audio recording started');
    } catch (e) {
      logError(_tag, 'Failed to start audio recording: $e');
      await _appendTimeline('audio_start_failed', {'error': '$e'});
    }

    if (includeVideo) {
      // Optional video mode can be layered later without breaking current SOS flow.
      await _appendTimeline('video_not_enabled_in_current_build', {});
    }
  }

  Future<void> attachBackendSession(String sessionId) async {
    _backendSessionId = sessionId;
    await _appendTimeline('backend_session_attached', {
      'sessionId': sessionId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> stopEvidenceCapture() async {
    if (!_isRecording) return;

    try {
      await _recorder.stopRecorder();
      await _recorder.closeRecorder();
      await _appendTimeline('evidence_stopped', {
        'backendSessionId': _backendSessionId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      logInfo(_tag, 'Audio recording stopped');
    } catch (e) {
      logError(_tag, 'Failed to stop audio recording: $e');
    } finally {
      _isRecording = false;
      _backendSessionId = null;
    }
  }

  Future<void> _appendTimeline(String event, Map<String, dynamic> data) async {
    final file = _timelineFile;
    if (file == null) return;

    final payload = {
      'event': event,
      ...data,
    };

    try {
      await file.writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      logWarn(_tag, 'Timeline write failed: $e');
    }
  }
}
