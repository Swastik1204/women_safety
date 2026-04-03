import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';
import 'sos_event_dedupe_service.dart';
import 'sos_service.dart';

// IMPORTANT: Add this rule to Firestore Security Rules:
//
// match /sos_events/{eventId} {
//   allow read: if request.auth != null
//               && request.auth.uid
//                  in resource.data.targetUserIds;
//   allow write: if false;
// }
class SosListenerService {
  static SosListenerService? _instance;
  static SosListenerService get instance =>
      _instance ??= SosListenerService._();
  SosListenerService._();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  final _processed = <String>{};

  /// Call once after user logs in.
  void startListening() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _startFallbackSubscription(uid);

    debugPrint('[SosListener] Listening for SOS events targeting $uid');
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    debugPrint('[SosListener] Stopped');
  }

  void _startFallbackSubscription(String uid) {
    _subscription?.cancel();

    _subscription = FirebaseFirestore.instance
        .collection('sos_events')
        .where('targetUserIds', arrayContains: uid)
        .snapshots()
        .listen(
      (snap) => _processSnapshot(snap, filterExpired: true),
      onError: (e) {
        debugPrint('[SosListener] Fallback stream error: $e');
      },
    );
  }

  void _processSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap, {
    required bool filterExpired,
  }) {
    for (final change in snap.docChanges) {
      if (change.type != DocumentChangeType.added) {
        continue;
      }

      final docId = change.doc.id;
      if (_processed.contains(docId)) continue;

      final data = change.doc.data();
      if (data == null) continue;

      if (filterExpired && _isExpired(data)) {
        continue;
      }

      _processed.add(docId);
      _handleSosEvent(data);
    }
  }

  bool _isExpired(Map<String, dynamic> data) {
    final expiresAt = data['expiresAt'];

    if (expiresAt is Timestamp) {
      return expiresAt.toDate().isBefore(DateTime.now());
    }

    if (expiresAt is DateTime) {
      return expiresAt.isBefore(DateTime.now());
    }

    if (expiresAt is String) {
      final parsed = DateTime.tryParse(expiresAt);
      if (parsed != null) {
        return parsed.isBefore(DateTime.now());
      }
    }

    return false;
  }

  Future<void> _handleSosEvent(Map<String, dynamic> data) async {
    final eventId = data['eventId'] as String? ?? '';
    final shouldHandle = await SosEventDedupeService.markIfNew(eventId);
    if (!shouldHandle) {
      debugPrint('[SosListener] Duplicate SOS ignored (eventId=$eventId)');
      return;
    }

    final fromName = data['fromName'] as String? ?? 'Someone';
    final lat = data['lat'] as String? ?? '';
    final lng = data['lng'] as String? ?? '';
    final mapsLink = data['mapsLink'] as String? ?? '';
    final sessionId = data['sessionId'] as String? ?? '';

    debugPrint('[SosListener] SOS received from $fromName');

    await NotificationService.showSOSAlert({
      'eventId': eventId,
      'sessionId': sessionId,
      'fromName': fromName,
      'lat': lat,
      'lng': lng,
      'mapsLink': mapsLink,
      'type': 'sos_incoming',
    });

    await SOSService.instance.speakEmergencyAlert(
      fromName: fromName,
      lat: lat,
      lng: lng,
      repeatCount: 5,
    );
  }
}
