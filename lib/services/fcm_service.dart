import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../core/logger.dart';
import '../firebase_options.dart';
import '../main.dart' show navigatorKey;
import '../screens/sos_alert_screen.dart';
import '../utils/phone_utils.dart';
import '../widgets/sim_picker_dialog.dart';
import 'notification_service.dart';
import 'sim_service.dart';

const _tag = 'FcmService';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.init();

  final data = Map<String, dynamic>.from(
    message.data.map((k, v) => MapEntry(k.toString(), v)),
  );
  final type = data['type']?.toString() ?? '';

  if (type == 'sos_incoming') {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_sos', jsonEncode(data));
    await NotificationService.showSOSAlert(Map<String, String>.from(message.data));
  }
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  String? _userId;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<RemoteMessage>? _openSub;
  static const _kLastToken = 'fcm_last_token';
  static const _kLastTokenAt = 'fcm_last_token_at';
  static const _kUserPhoneNumber = 'user_phone_number';

  Future<void> registerToken({String reason = 'manual'}) async {
    final uid = _userId;
    if (uid == null || uid.isEmpty) {
      logWarn(_tag, 'FCM token register skipped (reason=$reason): user not set');
      return;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      logWarn(_tag, 'FCM token register skipped (reason=$reason): token missing');
      return;
    }

    await _registerToken(token, reason: reason);
  }

  Future<String?> ensureUserPhone() async {
    return _getUserPhone(allowSimDetection: true);
  }

  Future<void> initForUser(String userId) async {
    _userId = userId;
    await NotificationService.init();

    final messaging = FirebaseMessaging.instance;

    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    logInfo(
      _tag,
      'Notification permission: ${permission.authorizationStatus.name}',
    );
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      logWarn(_tag, 'Notification permission denied; push may not appear');
    }

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _registerToken(token, reason: 'init');
    }

    await _tokenSub?.cancel();
    _tokenSub = messaging.onTokenRefresh.listen((token) async {
      await _registerToken(token, reason: 'refresh');
    });

    await _messageSub?.cancel();
    _messageSub = FirebaseMessaging.onMessage.listen(
      (m) => _handleMessage(m, opened: false),
    );

    await _openSub?.cancel();
    _openSub = FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => _handleMessage(m, opened: true),
    );

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      _handleMessage(initial, opened: true);
    }

    // Check for pending SOS that arrived while app was terminated.
    await _checkPendingSOS();

    logInfo(_tag, 'FCM initialized for user=$userId');
  }

  Future<void> dispose() async {
    await _tokenSub?.cancel();
    await _messageSub?.cancel();
    await _openSub?.cancel();
    _tokenSub = null;
    _messageSub = null;
    _openSub = null;
    _userId = null;
  }

  Future<void> _handleMessage(RemoteMessage message, {bool opened = false}) async {
    final data = Map<String, dynamic>.from(
      message.data.map((k, v) => MapEntry(k.toString(), v)),
    );
    if (data.isEmpty) return;

    final type = data['type']?.toString() ?? '';

    if (type == 'sos_incoming') {
      logInfo(_tag, 'sos_incoming received (opened=$opened)');
      _navigateToSOSAlert(data);
      return;
    }

    logInfo(_tag, 'Unhandled push type: $type');
  }

  /// Navigate to the SOS alert screen using the global navigator key.
  void _navigateToSOSAlert(Map<String, dynamic> data) {
    final lat = double.tryParse(data['lat']?.toString() ?? '0') ?? 0;
    final lng = double.tryParse(data['lng']?.toString() ?? '0') ?? 0;
    final fromName = data['fromName']?.toString() ?? 'Your contact';
    final mapsLink = data['mapsLink']?.toString() ??
        'https://maps.google.com/?q=$lat,$lng';

    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => SOSAlertScreen(
          fromName: fromName,
          lat: lat,
          lng: lng,
          mapsLink: mapsLink,
        ),
      ));
    } else {
      logWarn(_tag, 'No navigator context available for SOS alert');
    }
  }

  /// Check for a pending SOS stored by the background handler.
  Future<void> _checkPendingSOS() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingSos = prefs.getString('pending_sos');
    if (pendingSos != null) {
      await prefs.remove('pending_sos');
      try {
        final data = jsonDecode(pendingSos) as Map<String, dynamic>;
        logInfo(_tag, 'Found pending SOS, navigating');
        // Small delay to ensure navigator is ready
        await Future.delayed(const Duration(milliseconds: 500));
        _navigateToSOSAlert(data);
      } catch (e) {
        logError(_tag, 'Failed to parse pending SOS: $e');
      }
    }
  }

  Future<void> _registerToken(String token, {required String reason}) async {
    final uid = _userId;
    if (uid == null || uid.isEmpty) return;
    final phone = await _getUserPhone(allowSimDetection: false);
    final normalizedPhone = _normalizeForBackend(phone);

    await _persistToken(token);

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _doRegisterToken(
          uid: uid,
          token: token,
          phone: normalizedPhone.isEmpty ? null : normalizedPhone,
          reason: reason,
        ).timeout(const Duration(seconds: 30));
        return;
      } on TimeoutException {
        debugPrint(
          '[FcmService] FCM token register timeout (attempt $attempt/$maxRetries)',
        );
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 5));
        }
      } catch (e) {
        debugPrint('[FcmService] FCM token register error: $e');
        logError(_tag, 'FCM token register error: $e');
        return;
      }
    }

    debugPrint(
      '[FcmService] FCM token register failed after '
      '$maxRetries attempts — will retry on next launch',
    );
  }

  Future<void> _doRegisterToken({
    required String uid,
    required String token,
    required String? phone,
    required String reason,
  }) async {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      logWarn(
        _tag,
        'FCM token register deferred (reason=$reason): missing Firebase ID token',
      );
      return;
    }

    final uri = Uri.parse(AppConfig.apiRegisterDeviceToken);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'userId': uid,
        'token': token,
        'platform': 'android',
        'phone': phone,
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'phone': phone,
          'fcmToken': token,
          'platform': 'android',
        },
        SetOptions(merge: true),
      );

      logInfo(
        _tag,
        'FCM token registered (reason=$reason, status=${response.statusCode})',
      );
    } else {
      logWarn(
        _tag,
        'FCM token register failed (reason=$reason): ${response.statusCode} body=${response.body}',
      );
    }
  }

  Future<String?> _getUserPhone({bool allowSimDetection = true}) async {
    // First try locally stored phone entered by user.
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kUserPhoneNumber);
    if (stored != null && stored.trim().isNotEmpty) {
      final normalized = _normalizeForBackend(stored.trim());
      if (normalized.isNotEmpty) {
        if (normalized != stored.trim()) {
          await prefs.setString(_kUserPhoneNumber, normalized);
        }
        return normalized;
      }
      return stored.trim();
    }

    if (allowSimDetection) {
      final simService = SimService();
      final sims = await simService.detectSims();

      if (sims.isEmpty) {
        debugPrint('[FcmService] No SIMs detected, will prompt for manual entry');
      } else {
        final simsWithNumbers = sims.where((s) => s.hasNumber).toList();

        if (simsWithNumbers.length == 1) {
          final phone = _normalizeForBackend(simsWithNumbers.first.phoneNumber);
          if (phone.isNotEmpty) {
            await prefs.setString(_kUserPhoneNumber, phone);
            debugPrint('[FcmService] SIM auto-detected: $phone');
            return phone;
          }
        }

        if (simsWithNumbers.length > 1) {
          final navigator = navigatorKey.currentState;
          if (navigator == null) return null;

          // ignore: use_build_context_synchronously
          final selected = await navigator.push<String>(
            DialogRoute<String>(
              // ignore: use_build_context_synchronously
              context: navigator.context,
              barrierDismissible: false,
              builder: (_) => SimPickerDialog(sims: sims),
            ),
          );
          if (selected != null && selected.isNotEmpty) {
            final phone = _normalizeForBackend(selected.trim());
            await prefs.setString(_kUserPhoneNumber, phone);
            debugPrint('[FcmService] SIM selected by user: $phone');
            return phone;
          }
          return null;
        }

        debugPrint('[FcmService] SIMs found but no numbers readable');
      }
    }

    // Fallback: Firebase phone number (usually null for email/Google auth).
    final fbPhone = FirebaseAuth.instance.currentUser?.phoneNumber;
    if (fbPhone != null && fbPhone.trim().isNotEmpty) {
      final phone = _normalizeForBackend(fbPhone.trim());
      await prefs.setString(_kUserPhoneNumber, phone);
      return phone;
    }

    return null;
  }

  Future<void> _persistToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastToken, token);
    await prefs.setInt(_kLastTokenAt, DateTime.now().millisecondsSinceEpoch);
  }

  String _normalizeForBackend(String? phone) {
    return PhoneUtils.normalize(phone);
  }
}
