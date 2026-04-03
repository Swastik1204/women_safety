// Aanchal — Firebase Sync Service
//
// Background sync of emergency contacts to Firebase Realtime Database.
// Uses WorkManager for periodic background execution (every 12 hours).
//
// Firebase structure:
//   users/{device_id}/emergency_contacts/{contact_id}
//
// Sync direction: Local → Firebase (local is authoritative).
// Retries on failure. Silent background operation.
//
// NOTE: This uses Firebase REST API (no Flutter Firebase SDK required).
//       Works on Spark (free) plan.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../core/logger.dart';
import 'emergency_contacts_service.dart';

const _tag = 'FirebaseSyncService';

/// Key for storing the device ID locally.
const _deviceIdKey = 'aanchal_device_id';

/// Key for storing the last successful sync timestamp.
const _lastSyncKey = 'firebase_last_sync';

class FirebaseSyncService {
  FirebaseSyncService._();

  // ─── Initialisation ─────────────────────────────────────────────────

  /// Initialise the background sync worker.
  /// Call once at app startup (e.g. in `main()`).
  static Future<void> initialise() async {
    logInfo(_tag, 'Firebase sync service initialised');
    // WorkManager registration is handled in main.dart
    // This method ensures the device ID is generated.
    await _getOrCreateDeviceId();
  }

  // ─── Core Sync Logic ───────────────────────────────────────────────

  /// Perform a full sync of local contacts to Firebase.
  /// Returns `true` on success, `false` on failure.
  static Future<bool> syncNow() async {
    logInfo(_tag, 'Starting Firebase sync...');

    try {
      final deviceId = await _getOrCreateDeviceId();
      final contacts = await EmergencyContactsService.getContacts();

      if (contacts.isEmpty) {
        logInfo(_tag, 'No contacts to sync');
        await _recordSyncTime();
        return true;
      }

      // Build the contacts map for Firebase.
      final contactsMap = <String, dynamic>{};
      for (final contact in contacts) {
        contactsMap[contact.id] = contact.toJson();
      }

      // PUT to Firebase REST API (replaces the entire node).
      final url = '${AppConfig.firebaseDbUrl}/users/$deviceId/emergency_contacts.json';
      logDebug(_tag, 'Syncing to: $url');

      final response = await http
          .put(
            Uri.parse(url),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
            body: jsonEncode(contactsMap),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        await _recordSyncTime();
        logInfo(
          _tag,
          'SYNC_SUCCESS: ${contacts.length} contacts synced for device $deviceId',
        );
        return true;
      }

      logWarn(_tag, 'SYNC_FAILED: HTTP ${response.statusCode} — ${response.body}');
      return false;
    } catch (e) {
      logError(_tag, 'SYNC_ERROR', e);
      return false;
    }
  }

  /// The callback executed by WorkManager in the background.
  /// This is the entry point for the periodic background task.
  static Future<bool> backgroundSyncCallback() async {
    logInfo(_tag, 'Background sync triggered by WorkManager');
    return await syncNow();
  }

  // ─── Status ─────────────────────────────────────────────────────────

  /// Get the timestamp of the last successful sync (ISO 8601).
  static Future<String?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSyncKey);
  }

  /// Get the generated device ID.
  static Future<String> getDeviceId() async {
    return await _getOrCreateDeviceId();
  }

  // ─── Internal Helpers ───────────────────────────────────────────────

  /// Get or create a persistent device ID.
  static Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey);

    if (deviceId == null || deviceId.isEmpty) {
      // Generate a simple device-unique ID.
      deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}_'
          '${DateTime.now().hashCode.toRadixString(36)}';
      await prefs.setString(_deviceIdKey, deviceId);
      logInfo(_tag, 'Generated new device ID: $deviceId');
    }

    return deviceId;
  }

  /// Record the current time as the last successful sync.
  static Future<void> _recordSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }
}
