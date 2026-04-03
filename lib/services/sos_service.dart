// Aanchal — SOS Service
//
// Central SOS orchestrator. Activates panic mode, sends SMS to all emergency
// contacts, pushes FCM via the backend, and provides TTS for the receiving side.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../core/app_config.dart';
import '../core/logger.dart';
import 'alarm_sound_service.dart';
import 'auth_service.dart';
import 'evidence_service.dart';
import 'emergency_contacts_service.dart';
import 'location_service.dart';

const _tag = 'SOSService';

class _SosBackendDispatchResult {
  final String? eventId;
  final String? sessionId;

  const _SosBackendDispatchResult({
    this.eventId,
    this.sessionId,
  });
}

class SOSService {
  static final SOSService _instance = SOSService._internal();
  static SOSService get instance => _instance;
  factory SOSService() => _instance;
  SOSService._internal();

  final FlutterTts _tts = FlutterTts();
  static const _smsChannel = MethodChannel('com.aanchal/sms');
  static const _audioChannel = MethodChannel('com.aanchal.app/audio');
  bool _isActive = false;
  String? _activeSessionId;
  Timer? _liveLocationTimer;

  bool get isPanicActive => _isActive;
  String? get activeSessionId => _activeSessionId;

  // Legacy compatibility for incoming navigation shell integration.
  void initListen(String uid) {
    // Listener already resolves current auth user internally.
    // Keeping this method allows phased integration with older call sites.
  }

  void dispose() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
  }

  // ── PUBLIC: called when panic button pressed ──────────────────────
  Future<void> triggerSOS({required String userName}) async {
    if (_isActive) return; // prevent double-trigger
    _isActive = true;

    final smsStatus = await Permission.sms.request();
    if (smsStatus.isDenied || smsStatus.isPermanentlyDenied) {
      logWarn(_tag, 'SMS permission denied — SMS will be skipped');
    }

    logInfo(_tag, 'SOS triggered by $userName');

    // Start loud looping alarm immediately.
    await AlarmSoundService.start();

    // Start local evidence capture immediately when SOS activates.
    final localEvidenceSessionId =
        'local_${DateTime.now().millisecondsSinceEpoch}';
    await EvidenceService.instance.startEvidenceCapture(
      sessionId: localEvidenceSessionId,
      includeVideo: false,
    );

    try {
      // Step 1: Fetch contacts and send immediate SMS without waiting for GPS.
      final contacts = await _getEmergencyContacts();
      await _sendInitialSMSToAll(contacts, userName);

      // Step 2: Fetch location after immediate alert SMS.
      final position = await LocationService.getCurrentPosition() ??
          Position(
            latitude: 0,
            longitude: 0,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );

      // Step 3: Send location SMS + backend dispatch.
      final backendFuture = _sendBackendSOS(position, userName);
      final locationSmsFuture = _sendLocationSMSToAll(contacts, position, userName);

      final backendResult = await backendFuture;
      await locationSmsFuture;

      final sessionId = backendResult?.sessionId;
      if (sessionId != null && sessionId.isNotEmpty) {
        _activeSessionId = sessionId;
        await EvidenceService.instance.attachBackendSession(sessionId);
        _startLiveLocationLoop();
      }

      logInfo(_tag, 'SOS dispatched to ${contacts.length} contacts');
    } catch (e, st) {
      logError(_tag, 'SOS_FAILED: $e');
      logError(_tag, '$st');
    }
    // Note: _isActive stays true and alarm keeps playing until deactivate()
  }

  /// Deactivate panic mode.
  void deactivate() {
    _isActive = false;

    final sessionId = _activeSessionId;
    _activeSessionId = null;
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;

    if (sessionId != null && sessionId.isNotEmpty) {
      unawaited(_stopSosSession(sessionId));
    }

    unawaited(EvidenceService.instance.stopEvidenceCapture());
    logInfo(_tag, 'PANIC_DEACTIVATED');
    unawaited(AlarmSoundService.stop());
  }

  // ── SMS (works on ALL phones, no app needed) ──────────────────────
  Future<void> _sendInitialSMSToAll(
    List<Map<String, dynamic>> contacts,
    String userName,
  ) async {
    final message = 'SOS ALERT\n'
        '$userName needs help.\n'
        'Location fetching...';
    await _sendSMSBatch(
      contacts,
      message,
      phase: 'initial',
    );
  }

  Future<void> _sendLocationSMSToAll(
    List<Map<String, dynamic>> contacts,
    Position position,
    String userName,
  ) async {
    final mapsLink =
        'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    final message = 'SOS LOCATION UPDATE\n'
        '$userName location:\n'
        '$mapsLink';
    await _sendSMSBatch(
      contacts,
      message,
      phase: 'location',
    );
  }

  Future<void> _sendSMSBatch(
    List<Map<String, dynamic>> contacts,
    String message, {
    required String phase,
  }) async {
    if (!await Permission.sms.isGranted) {
      logWarn(_tag, 'SMS permission denied — SMS will be skipped');
      return;
    }

    final phoneContacts = contacts
        .where((c) => c['phone'] != null && (c['phone'] as String).isNotEmpty)
        .toList();
    final phones = phoneContacts
        .map((c) => (c['phone'] as String).trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (phones.isEmpty) {
      logWarn(_tag, 'No phone contacts available for SMS phase=$phase');
      return;
    }

    try {
      await _smsChannel.invokeMethod('sendSmsBatch', {
        'phones': phones,
        'message': message,
      });
      logInfo(_tag, 'SMS($phase) sent to ${phones.length} contact(s)');
      return;
    } on PlatformException catch (_) {
      // Fallback to one-by-one sends for compatibility.
    }

    int sent = 0;
    for (final contact in phoneContacts) {
      try {
        await _smsChannel.invokeMethod('sendSms', {
          'phone': contact['phone'] as String,
          'message': message,
        });
        sent++;
      } on PlatformException catch (e) {
        logError(_tag, 'SMS failed to ${contact['name']}: ${e.message}');
      } catch (e) {
        logError(_tag, 'SMS failed to ${contact['name']}: $e');
      }
    }
    logInfo(_tag, 'SMS($phase) sent to $sent/${phoneContacts.length} contacts');
  }

  // ── Backend dispatch (sos_events + FCM backup) ─────────────────────
  Future<_SosBackendDispatchResult?> _sendBackendSOS(
    Position position,
    String userName,
  ) async {
    final uid = AuthService.currentUser?.uid ?? '';
    final mapsLink =
        'https://maps.google.com/?q=${position.latitude},${position.longitude}';

    try {
      final headers = await _authorizedHeaders();
      final response = await http
          .post(
            Uri.parse(AppConfig.apiSos),
            headers: headers,
            body: jsonEncode({
              'userId': uid,
              'userName': userName,
              'lat': position.latitude.toString(),
              'lng': position.longitude.toString(),
              'mapsLink': mapsLink,
            }),
          )
          .timeout(AppConfig.apiTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        String? sessionId;
        String? eventId;
        try {
          final payload = jsonDecode(response.body) as Map<String, dynamic>;
          sessionId = payload['sessionId']?.toString();
          eventId = payload['eventId']?.toString();
        } catch (_) {
          // Keep compatibility with older backend responses.
        }

        logInfo(_tag, 'SOS request sent to backend');
        return _SosBackendDispatchResult(
          eventId: eventId,
          sessionId: sessionId,
        );
      } else {
        logWarn(_tag, 'SOS backend failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      logError(_tag, 'SOS backend request failed: $e');
    }

    return null;
  }

  void _startLiveLocationLoop() {
    _liveLocationTimer?.cancel();
    final sessionId = _activeSessionId;
    if (sessionId == null || sessionId.isEmpty) return;

    _liveLocationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!_isActive) return;
      final position = await LocationService.getCurrentPosition();
      if (position == null) return;
      await _pushLiveLocation(sessionId, position);
    });

    logInfo(_tag, 'Live tracking started for session=$sessionId');
  }

  Future<void> _pushLiveLocation(String sessionId, Position position) async {
    try {
      final headers = await _authorizedHeaders();
      await http
          .post(
            Uri.parse(AppConfig.apiSosLocation),
            headers: headers,
            body: jsonEncode({
              'sessionId': sessionId,
              'lat': position.latitude.toString(),
              'lng': position.longitude.toString(),
            }),
          )
          .timeout(AppConfig.apiTimeout);
    } catch (e) {
      logWarn(_tag, 'Live location update failed: $e');
    }
  }

  Future<void> _stopSosSession(String sessionId) async {
    try {
      final headers = await _authorizedHeaders();
      await http
          .post(
            Uri.parse(AppConfig.apiSosSessionStop),
            headers: headers,
            body: jsonEncode({'sessionId': sessionId}),
          )
          .timeout(AppConfig.apiTimeout);
    } catch (e) {
      logWarn(_tag, 'SOS session stop failed: $e');
    }
  }

  Future<Map<String, String>> _authorizedHeaders() async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final idToken = await AuthService.currentUser?.getIdToken();
    if (idToken != null && idToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $idToken';
    }
    return headers;
  }

  // ── EMERGENCY CONTACTS ────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _getEmergencyContacts() async {
    final contacts = await EmergencyContactsService.getContacts();
    return contacts.map((c) => c.toJson()).toList();
  }

  Future<void> _forceAlarmAudioStream() async {
    try {
      await _audioChannel.invokeMethod('setAlarmStream');
    } catch (e) {
      logWarn(_tag, 'Could not set alarm stream: $e');
    }
  }

  // ── TTS: called on the RECEIVING side when SOS arrives ────────────
  Future<void> speakSOSAlert({
    required String fromName,
    required String mapsLink,
  }) async {
    await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _forceAlarmAudioStream();
    await _tts.speak(
      '$fromName has triggered an emergency SOS. '
      'Their location has been sent to your phone. '
      'Please check on them immediately or call the police. '
      'This is an automated alert from Aanchal.',
    );
    logInfo(_tag, 'TTS alert played for $fromName');
  }

  Future<void> speakEmergencyAlert({
    required String fromName,
    required String lat,
    required String lng,
    int repeatCount = 5,
  }) async {
    try {
      await _forceAlarmAudioStream();

      await _tts.setLanguage('en-IN');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      final script = 'Save $fromName. '
          'This is an emergency. '
          'Save $fromName.';

      for (int i = 0; i < repeatCount; i++) {
        await _tts.speak(script);
        await Future.delayed(const Duration(seconds: 5));
      }

      debugPrint('[SOS] Emergency alert spoken $repeatCount times');
    } catch (e) {
      debugPrint('[SOS] speakEmergencyAlert failed: $e');
    }
  }
}
