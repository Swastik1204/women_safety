// Aanchal — Geocoding Service
//
// Uses Nominatim (free OpenStreetMap geocoding service)
// for forward geocoding (search) and reverse geocoding.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../core/logger.dart';

const _tag = 'GeocodingService';

/// A single geocoding result.
class GeocodingResult {
  final String displayName;
  final LatLng location;
  final String type;

  const GeocodingResult({
    required this.displayName,
    required this.location,
    this.type = '',
  });

  /// Short name: use the first part of the display name.
  String get shortName {
    final parts = displayName.split(',');
    if (parts.length >= 2) return '${parts[0].trim()}, ${parts[1].trim()}';
    return parts.first.trim();
  }
}

class GeocodingService {
  static const _baseUrl = 'https://nominatim.openstreetmap.org';

  /// Search for places matching [query].
  /// Optionally bias results toward [viewBox] (lon1,lat1,lon2,lat2).
  static Future<List<GeocodingResult>> search(
    String query, {
    LatLng? near,
    int limit = 6,
  }) async {
    if (query.trim().isEmpty) return [];

    final params = <String, String>{
      'q': query,
      'format': 'json',
      'limit': '$limit',
      'addressdetails': '1',
    };

    // Bias results to area around user.
    if (near != null) {
      final delta = 0.5; // ~50 km bias window
      params['viewbox'] =
          '${near.longitude - delta},${near.latitude - delta},'
          '${near.longitude + delta},${near.latitude + delta}';
      params['bounded'] = '0'; // prefer, but don't restrict
    }

    final url = Uri.parse('$_baseUrl/search').replace(queryParameters: params);
    logInfo(_tag, 'Searching: $url');

    try {
      final response = await http
          .get(url, headers: {'User-Agent': 'Aanchal-SafetyApp/1.0'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        logError(_tag, 'Nominatim returned ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body) as List<dynamic>;
      return data.map<GeocodingResult>((item) {
        final m = item as Map<String, dynamic>;
        return GeocodingResult(
          displayName: m['display_name'] as String? ?? '',
          location: LatLng(
            double.parse(m['lat'] as String),
            double.parse(m['lon'] as String),
          ),
          type: m['type'] as String? ?? '',
        );
      }).toList();
    } catch (e) {
      logError(_tag, 'Search failed', e);
      return [];
    }
  }

  /// Reverse geocoding: get a place name for a given location.
  static Future<String?> reverseGeocode(LatLng location) async {
    final url = Uri.parse(
      '$_baseUrl/reverse?lat=${location.latitude}'
      '&lon=${location.longitude}&format=json',
    );

    try {
      final response = await http
          .get(url, headers: {'User-Agent': 'Aanchal-SafetyApp/1.0'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['display_name'] as String?;
    } catch (e) {
      logError(_tag, 'Reverse geocoding failed', e);
      return null;
    }
  }
}
