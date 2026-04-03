import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/logger.dart';

const _tag = 'CallHistoryService';

class CallHistoryService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> upsert(String callId, Map<String, dynamic> data) async {
    if (callId.isEmpty) return;
    await _db.collection('calls').doc(callId).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<List<Map<String, dynamic>>> fetchServerHistory(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final uri = Uri.parse('${AppConfig.apiCallHistory(userId)}?limit=$limit');
      final response = await http.get(uri).timeout(AppConfig.apiTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        logWarn(_tag, 'fetchServerHistory failed: ${response.statusCode}');
        return const [];
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final items = payload['items'] as List<dynamic>? ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    } catch (e) {
      logError(_tag, 'fetchServerHistory error: $e');
      return const [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchServerMissedCalls(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final uri = Uri.parse('${AppConfig.apiMissedCalls(userId)}?limit=$limit');
      final response = await http.get(uri).timeout(AppConfig.apiTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        logWarn(_tag, 'fetchServerMissedCalls failed: ${response.statusCode}');
        return const [];
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final items = payload['items'] as List<dynamic>? ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    } catch (e) {
      logError(_tag, 'fetchServerMissedCalls error: $e');
      return const [];
    }
  }
}
