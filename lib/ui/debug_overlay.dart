// Aanchal — Debug Overlay Widget
//
// Toggleable panel showing feature flags, mock P2P status, and recent logs.

import 'package:flutter/material.dart';
import '../core/feature_flags.dart';
import '../services/p2p_stub_service.dart';

class DebugOverlay extends StatefulWidget {
  final VoidCallback onClose;

  const DebugOverlay({super.key, required this.onClose});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  List<String> _peers = [];
  bool _loadingPeers = false;

  Future<void> _discoverPeers() async {
    setState(() => _loadingPeers = true);
    final svc = P2PStubService();
    await svc.startDiscovery();
    final peers = List.generate(svc.peerCount, (i) => 'MockPeer_${i + 1}');
    setState(() {
      _peers = peers;
      _loadingPeers = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final flags = FeatureFlags.getAll();

    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Debug Panel',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Feature Flags
                      const Text(
                        'Feature Flags',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...flags.entries.map(
                        (e) => SwitchListTile(
                          dense: true,
                          activeTrackColor: Colors.greenAccent,
                          title: Text(
                            e.key,
                            style: const TextStyle(color: Colors.white),
                          ),
                          value: e.value,
                          onChanged: (v) {
                            setState(() => FeatureFlags.set(e.key, v));
                          },
                        ),
                      ),

                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24),

                      // Mock P2P
                      const Text(
                        'P2P Discovery (mock)',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _loadingPeers ? null : _discoverPeers,
                        icon: _loadingPeers
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.search),
                        label: const Text('Discover peers'),
                      ),
                      const SizedBox(height: 8),
                      if (_peers.isNotEmpty)
                        ..._peers.map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(left: 8, bottom: 4),
                            child: Text(
                              '• $p',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),

                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          'Aanchal Debug v0.1.0',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
