// Aanchal — WhatsApp Service
//
// Opens WhatsApp with a pre-filled emergency message containing GPS coordinates.

import 'package:url_launcher/url_launcher.dart';
import '../core/logger.dart';

const _tag = 'WhatsAppService';

class WhatsAppService {
  /// Send an emergency message via WhatsApp deep link.
  static Future<void> sendEmergency({
    required double lat,
    required double lng,
    String? phone,
  }) async {
    final message = Uri.encodeComponent(
      'EMERGENCY — I need help!\n'
      'My location: https://maps.google.com/?q=$lat,$lng\n'
      'Sent from Aanchal Safety App',
    );

    final uri = phone != null
        ? Uri.parse('https://wa.me/$phone?text=$message')
        : Uri.parse('https://wa.me/?text=$message');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        logInfo(_tag, 'WhatsApp launched');
      } else {
        logWarn(_tag, 'WhatsApp not available');
      }
    } catch (e) {
      logError(_tag, 'Failed to launch WhatsApp', e);
    }
  }
}
