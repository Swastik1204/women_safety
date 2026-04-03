// Aanchal — Location Service
//
// Wraps geolocator for live location tracking.

import 'package:geolocator/geolocator.dart';
import '../core/logger.dart';

const _tag = 'LocationService';

class LocationService {
  /// Request location permission and return current position, or null on failure.
  static Future<Position?> getCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        logWarn(_tag, 'Location services disabled');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          logWarn(_tag, 'Location permission denied');
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        logWarn(_tag, 'Location permission permanently denied');
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      logInfo(_tag, 'Position: ${pos.latitude}, ${pos.longitude}');
      return pos;
    } catch (e) {
      logError(_tag, 'getCurrentPosition failed', e);
      return null;
    }
  }

  /// Haversine distance between two points in meters.
  static double distanceBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }
}
