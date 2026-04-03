import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart' show navigatorKey;
import '../screens/sos_alert_screen.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static final AndroidNotificationChannel _sosChannel =
      const AndroidNotificationChannel(
    'aanchal_sos',
    'Aanchal SOS Alerts',
    importance: Importance.max,
    enableVibration: true,
    playSound: true,
  );

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_sosChannel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload == null) return;
        try {
          final data = jsonDecode(response.payload!) as Map<String, dynamic>;
          _navigateToSOS(data);
        } catch (_) {}
      },
    );

    _initialized = true;
  }

  static void _navigateToSOS(Map<String, dynamic> data) {
    final BuildContext? ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final double lat = double.tryParse(data['lat']?.toString() ?? '') ?? 0;
    final double lng = double.tryParse(data['lng']?.toString() ?? '') ?? 0;
    final String fromName = data['fromName']?.toString() ?? 'Someone';
    final String rawMapsLink = data['mapsLink']?.toString() ?? '';
    final String mapsLink = rawMapsLink.isNotEmpty
        ? rawMapsLink
        : 'https://maps.google.com/?q=${data['lat'] ?? '0'},${data['lng'] ?? '0'}';

    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => SOSAlertScreen(
          fromName: fromName,
          lat: lat,
          lng: lng,
          mapsLink: mapsLink,
        ),
      ),
    );
  }

  static Future<void> showSOSAlert(Map<String, String> data) async {
    await init();

    final payloadData = Map<String, String>.from(data);
    payloadData['mapsLink'] = data['mapsLink']?.isNotEmpty == true
        ? data['mapsLink']!
        : 'https://maps.google.com/?q=${data['lat'] ?? '0'},${data['lng'] ?? '0'}';

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'aanchal_sos',
      'Aanchal SOS Alerts',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      ongoing: true,
      autoCancel: false,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
    );

    await _plugin.show(
      911,
      'EMERGENCY ALERT',
      '${data['fromName']} needs help - tap to open',
      const NotificationDetails(android: androidDetails),
      payload: jsonEncode(payloadData),
    );
  }
}
