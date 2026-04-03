import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SosEventDedupeService {
  SosEventDedupeService._();

  static const _kHandledSosEvents = 'handled_sos_events_v1';
  static const int _maxEntries = 400;
  static const Duration _retention = Duration(hours: 24);

  static Future<bool> markIfNew(String? eventId) async {
    final id = (eventId ?? '').trim();
    if (id.isEmpty) return true;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final retentionMs = _retention.inMilliseconds;

    final raw = prefs.getString(_kHandledSosEvents);
    final decoded = <String, int>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
        jsonMap.forEach((k, v) {
          final ts = int.tryParse(v.toString());
          if (ts != null) {
            decoded[k] = ts;
          }
        });
      } catch (_) {
        // If cache is malformed, reset and continue.
      }
    }

    decoded.removeWhere((_, ts) => (now - ts) > retentionMs);

    if (decoded.containsKey(id)) {
      await prefs.setString(_kHandledSosEvents, jsonEncode(decoded));
      return false;
    }

    decoded[id] = now;

    if (decoded.length > _maxEntries) {
      final entries = decoded.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final removeCount = decoded.length - _maxEntries;
      for (int i = 0; i < removeCount; i++) {
        decoded.remove(entries[i].key);
      }
    }

    await prefs.setString(_kHandledSosEvents, jsonEncode(decoded));
    return true;
  }
}
