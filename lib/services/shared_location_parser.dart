// Aanchal — Shared Location Parser
//
// Parses text shared from Google Maps, Apple Maps, or other apps
// to extract a destination location. Supports:
//   • Direct coordinates in text (e.g. "12.824,80.046")
//   • Google Maps short links (maps.app.goo.gl/…)
//   • Google Maps full links (google.com/maps/…)
//   • Apple Maps links (maps.apple.com/…)
//   • geo: URIs (geo:12.824,80.046)
//   • Plain text place names (falls back to Nominatim search)

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../core/logger.dart';
import 'geocoding_service.dart';

const _tag = 'SharedLocationParser';

/// Result of parsing a shared location.
class SharedLocationResult {
  final LatLng location;
  final String name;

  const SharedLocationResult({required this.location, required this.name});
}

class SharedLocationParser {
  // ── Regex patterns ────────────────────────────────────────────────────

  /// Matches @lat,lng or @lat,lng,zoom in Google Maps URLs.
  static final _googleAtPattern = RegExp(r'@(-?\d+\.?\d*),(-?\d+\.?\d*)');

  /// Matches ?q=lat,lng or &q=lat,lng.
  static final _queryLatLngPattern = RegExp(
    r'[?&]q=(-?\d+\.?\d*),(-?\d+\.?\d*)',
  );

  /// Matches place/Name/@lat,lng in Google Maps URLs.
  static final _placePattern = RegExp(
    r'place/([^/@]+)/@(-?\d+\.?\d*),(-?\d+\.?\d*)',
  );

  /// Matches ll=lat,lng (Apple Maps).
  static final _appleLLPattern = RegExp(r'll=(-?\d+\.?\d*),(-?\d+\.?\d*)');

  /// Matches geo:lat,lng URI.
  static final _geoUriPattern = RegExp(r'geo:(-?\d+\.?\d*),(-?\d+\.?\d*)');

  /// Matches a bare coordinate pair like "12.824864, 80.046118".
  static final _bareCoordPattern = RegExp(
    r'(-?\d{1,3}\.\d{3,})\s*[,\s]\s*(-?\d{1,3}\.\d{3,})',
  );

  /// Matches any URL in the shared text.
  static final _urlPattern = RegExp(r'https?://\S+');

  /// Known short-link domains that need redirect resolution.
  static final _shortLinkDomains = [
    'maps.app.goo.gl',
    'goo.gl',
    'g.co',
    'maps.google.com',
  ];

  // ══════════════════════════════════════════════════════════════════════
  // Public API
  // ══════════════════════════════════════════════════════════════════════

  /// Parse shared text to extract a location.
  ///
  /// Strategy:
  /// 1. Try to extract coordinates directly from the text (geo: URI, bare coords).
  /// 2. Try to find a URL and extract coordinates from it.
  /// 3. If URL is a short link, resolve it and try again.
  /// 4. Fall back to Nominatim text search using plain text.
  static Future<SharedLocationResult?> parse(
    String sharedText, {
    LatLng? userLocation,
  }) async {
    if (sharedText.trim().isEmpty) return null;

    logInfo(_tag, 'Parsing shared text: "${_truncate(sharedText, 120)}"');

    // ── 1. Try geo: URI ──────────────────────────────────────────────
    final geoMatch = _geoUriPattern.firstMatch(sharedText);
    if (geoMatch != null) {
      final result = _coordsFromMatch(geoMatch, 1, 2);
      if (result != null) {
        final name = await _reverseOrFallback(result, sharedText);
        return SharedLocationResult(location: result, name: name);
      }
    }

    // ── 2. Try bare coordinates ──────────────────────────────────────
    final bareMatch = _bareCoordPattern.firstMatch(sharedText);
    if (bareMatch != null &&
        !_urlPattern.hasMatch(sharedText.substring(0, bareMatch.start + 1))) {
      final result = _coordsFromMatch(bareMatch, 1, 2);
      if (result != null) {
        final name = await _reverseOrFallback(result, sharedText);
        return SharedLocationResult(location: result, name: name);
      }
    }

    // ── 3. Try extracting URL and parsing coordinates from it ────────
    final urlMatch = _urlPattern.firstMatch(sharedText);
    if (urlMatch != null) {
      var url = urlMatch.group(0)!;
      logInfo(_tag, 'Found URL: $url');

      // Try parsing coords from the URL directly.
      var coordResult = _extractCoordsFromUrl(url);
      if (coordResult != null) {
        final name = await _reverseOrFallback(coordResult.location, sharedText);
        return SharedLocationResult(
          location: coordResult.location,
          name: coordResult.name.isNotEmpty ? coordResult.name : name,
        );
      }

      // If it's a short link, resolve the redirect.
      if (_isShortLink(url)) {
        final resolved = await _resolveRedirect(url);
        if (resolved != null && resolved != url) {
          logInfo(_tag, 'Resolved short link to: ${_truncate(resolved, 120)}');
          coordResult = _extractCoordsFromUrl(resolved);
          if (coordResult != null) {
            final name = await _reverseOrFallback(
              coordResult.location,
              sharedText,
            );
            return SharedLocationResult(
              location: coordResult.location,
              name: coordResult.name.isNotEmpty ? coordResult.name : name,
            );
          }
        }
      }
    }

    // ── 4. Fall back to Nominatim text search ────────────────────────
    // Strip URLs and clean up the text for search.
    final cleanText = sharedText.replaceAll(_urlPattern, '').trim();
    if (cleanText.isNotEmpty) {
      logInfo(_tag, 'Falling back to Nominatim search: "$cleanText"');
      final results = await GeocodingService.search(
        cleanText,
        near: userLocation,
        limit: 1,
      );
      if (results.isNotEmpty) {
        return SharedLocationResult(
          location: results.first.location,
          name: results.first.shortName,
        );
      }
    }

    // Also try the full text as-is.
    if (cleanText != sharedText.trim()) {
      final results = await GeocodingService.search(
        sharedText.trim(),
        near: userLocation,
        limit: 1,
      );
      if (results.isNotEmpty) {
        return SharedLocationResult(
          location: results.first.location,
          name: results.first.shortName,
        );
      }
    }

    logWarn(_tag, 'Could not parse any location from shared text');
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Internal helpers
  // ══════════════════════════════════════════════════════════════════════

  /// Extract coordinates from a URL string.
  static SharedLocationResult? _extractCoordsFromUrl(String url) {
    // Google Maps place pattern: /place/Name/@lat,lng
    final placeMatch = _placePattern.firstMatch(url);
    if (placeMatch != null) {
      final name = Uri.decodeComponent(
        placeMatch.group(1)!,
      ).replaceAll('+', ' ');
      final coords = _coordsFromMatch(placeMatch, 2, 3);
      if (coords != null) {
        return SharedLocationResult(location: coords, name: name);
      }
    }

    // Google Maps @lat,lng pattern.
    final atMatch = _googleAtPattern.firstMatch(url);
    if (atMatch != null) {
      final coords = _coordsFromMatch(atMatch, 1, 2);
      if (coords != null) {
        return SharedLocationResult(location: coords, name: '');
      }
    }

    // ?q=lat,lng pattern.
    final qMatch = _queryLatLngPattern.firstMatch(url);
    if (qMatch != null) {
      final coords = _coordsFromMatch(qMatch, 1, 2);
      if (coords != null) {
        return SharedLocationResult(location: coords, name: '');
      }
    }

    // Apple Maps ll=lat,lng pattern.
    final llMatch = _appleLLPattern.firstMatch(url);
    if (llMatch != null) {
      final coords = _coordsFromMatch(llMatch, 1, 2);
      if (coords != null) {
        return SharedLocationResult(location: coords, name: '');
      }
    }

    return null;
  }

  /// Parse lat/lng from regex match groups.
  static LatLng? _coordsFromMatch(
    RegExpMatch match,
    int latGroup,
    int lngGroup,
  ) {
    try {
      final lat = double.parse(match.group(latGroup)!);
      final lng = double.parse(match.group(lngGroup)!);
      if (lat.abs() <= 90 && lng.abs() <= 180) {
        return LatLng(lat, lng);
      }
    } catch (_) {}
    return null;
  }

  /// Check if this URL is a known short-link domain.
  static bool _isShortLink(String url) {
    try {
      final uri = Uri.parse(url);
      return _shortLinkDomains.any((d) => uri.host.contains(d));
    } catch (_) {
      return false;
    }
  }

  /// Follow HTTP redirects to resolve a short URL.
  static Future<String?> _resolveRedirect(String url) async {
    try {
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url))
          ..followRedirects = false;
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 8));

        if (response.isRedirect ||
            response.statusCode == 301 ||
            response.statusCode == 302) {
          final location = response.headers['location'];
          if (location != null) return location;
        }

        // Some servers do JS redirects; check the body for meta refresh.
        final body = await response.stream.bytesToString();
        final metaRefresh = RegExp(r'url=([^"]+)"').firstMatch(body);
        if (metaRefresh != null) return metaRefresh.group(1);

        // If no redirect, the original URL may itself contain coords after loading.
        return url;
      } finally {
        client.close();
      }
    } catch (e) {
      logError(_tag, 'Redirect resolution failed', e);
      return null;
    }
  }

  /// Reverse geocode or fallback to extracting name from text.
  static Future<String> _reverseOrFallback(LatLng location, String text) async {
    final reversed = await GeocodingService.reverseGeocode(location);
    if (reversed != null && reversed.isNotEmpty) {
      // Return a short version.
      final parts = reversed.split(',');
      if (parts.length >= 2) return '${parts[0].trim()}, ${parts[1].trim()}';
      return parts.first.trim();
    }
    // Fallback: use text without URLs.
    final clean = text.replaceAll(_urlPattern, '').trim();
    return clean.isNotEmpty ? clean : 'Shared Location';
  }

  static String _truncate(String s, int maxLen) =>
      s.length <= maxLen ? s : '${s.substring(0, maxLen)}…';
}
