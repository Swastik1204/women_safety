// Aanchal — SOS Alert Screen
//
// Shown on the RECEIVING device when an emergency SOS is received.
// Full-screen red alert with maps link, call police, and TTS.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/sos_service.dart';

class SOSAlertScreen extends StatefulWidget {
  final String fromName;
  final double lat;
  final double lng;
  final String mapsLink;
  final String? sessionId;

  const SOSAlertScreen({
    super.key,
    required this.fromName,
    required this.lat,
    required this.lng,
    required this.mapsLink,
    this.sessionId,
  });

  @override
  State<SOSAlertScreen> createState() => _SOSAlertScreenState();
}

class _SOSAlertScreenState extends State<SOSAlertScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<Color?> _bgAnimation;
  String _placeName = '';

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _bgAnimation = ColorTween(
      begin: const Color(0xFF6B0000),
      end: const Color(0xFFCC0000),
    ).animate(_pulseController);

    _fetchPlaceName();

    // Play TTS alert immediately when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SOSService().speakSOSAlert(
        fromName: widget.fromName,
        mapsLink: widget.mapsLink,
      );
    });
  }

  Future<void> _fetchPlaceName() async {
    if (!widget.lat.isFinite || !widget.lng.isFinite) return;

    try {
      final url = 'https://nominatim.openstreetmap.org/reverse'
          '?format=json'
          '&lat=${widget.lat}'
          '&lon=${widget.lng}';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Aanchal Safety App'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        final place = address?['suburb'] ??
            address?['neighbourhood'] ??
            address?['city_district'] ??
            address?['city'] ??
            data['display_name']?.toString().split(',').first ??
            '';

        if (mounted && place.toString().trim().isNotEmpty) {
          setState(() => _placeName = place.toString().trim());
        }
      }
    } catch (_) {
      // Silently fail — coordinates are shown as fallback.
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bgAnimation,
      builder: (_, __) => Scaffold(
        backgroundColor: _bgAnimation.value,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 96,
                ),
                const SizedBox(height: 24),
                const Text(
                  '\u{1F198} EMERGENCY SOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '${widget.fromName} needs help!',
                  style: const TextStyle(color: Colors.white, fontSize: 22),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Lat: ${widget.lat.toStringAsFixed(5)}\n'
                  'Lng: ${widget.lng.toStringAsFixed(5)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                if (_placeName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Near: $_placeName',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red[900],
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => launchUrl(Uri.parse(widget.mapsLink)),
                  icon: const Icon(Icons.map),
                  label: const Text(
                    'Open Location in Maps',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[900],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => launchUrl(Uri.parse('tel:100')),
                  icon: const Icon(Icons.local_police),
                  label: const Text(
                    'Call Police (100)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(
                      ClipboardData(text: widget.mapsLink),
                    );
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text('Location copied to clipboard'),
                        backgroundColor: Colors.green.shade800,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 20),
                  label: const Text('Copy Location Link'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade800,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Dismiss',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
