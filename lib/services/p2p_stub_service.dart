// Aanchal — P2P Stub Service
//
// Mock implementation of peer-to-peer SOS broadcast.
// Will be replaced with real Nearby Connections via platform channel.

import 'dart:async';
import '../core/logger.dart';

const _tag = 'P2PStubService';

class P2PStubService {
  bool _isDiscovering = false;
  int _mockPeerCount = 0;

  bool get isDiscovering => _isDiscovering;
  int get peerCount => _mockPeerCount;

  /// Start mock discovery.
  Future<void> startDiscovery() async {
    logInfo(_tag, 'Starting mock discovery...');
    _isDiscovering = true;
    // Simulate finding peers after 2 seconds
    await Future.delayed(const Duration(seconds: 2));
    _mockPeerCount = 3;
    logInfo(_tag, 'Mock discovery complete: $_mockPeerCount peers found');
  }

  /// Stop discovery.
  void stopDiscovery() {
    _isDiscovering = false;
    _mockPeerCount = 0;
    logInfo(_tag, 'Discovery stopped');
  }

  /// Broadcast SOS payload (stub — console log only).
  Future<Map<String, dynamic>> broadcastSOS(
    Map<String, dynamic> payload,
  ) async {
    logInfo(_tag, 'Broadcasting SOS (mock): $payload');
    await Future.delayed(const Duration(milliseconds: 300));
    return {'sent': true, 'peers': _mockPeerCount, 'mock': true};
  }
}
