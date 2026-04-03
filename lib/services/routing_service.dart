// Aanchal — Routing Service
//
// Uses the public OSRM demo server for route calculation.
// Supports driving, walking, and cycling profiles.
// Returns decoded GeoJSON polylines plus estimated duration.
// Includes step-by-step navigation instructions from OSRM.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../core/logger.dart';
import 'navigation_state.dart';

const _tag = 'RoutingService';

/// Travel mode → OSRM profile string.
enum TravelMode {
  driving('car', 'driving', icon: '🚗'),
  walking('foot', 'walking', icon: '🚶'),
  cycling('bike', 'cycling', icon: '🚲');

  final String label;
  final String osrmProfile;
  final String emoji;
  const TravelMode(this.label, this.osrmProfile, {required String icon})
    : emoji = icon;

  /// Human-readable name shown in UI.
  String get displayName {
    switch (this) {
      case TravelMode.driving:
        return 'Car';
      case TravelMode.walking:
        return 'Walk';
      case TravelMode.cycling:
        return 'Bike';
    }
  }
}

/// A single route alternative returned by OSRM.
class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final TravelMode mode;
  final bool isSafe;
  final List<NavigationStep> steps; // Turn-by-turn instructions

  RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.mode,
    this.isSafe = true,
    this.steps = const [],
  });

  RouteResult copyWith({bool? isSafe, List<NavigationStep>? steps}) =>
      RouteResult(
        points: points,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        mode: mode,
        isSafe: isSafe ?? this.isSafe,
        steps: steps ?? this.steps,
      );

  /// Human-friendly duration string.
  String get durationText {
    final mins = (durationSeconds / 60).ceil();
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}h ${m}m';
  }

  /// Human-friendly distance string.
  String get distanceText {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }
}

class RoutingService {
  static const _baseUrl = 'https://router.project-osrm.org';

  /// Fetch route alternatives for a given [mode].
  ///
  /// Optionally pass [waypoints] to force the route through intermediate
  /// points (used for detour routing around danger zones).
  ///
  /// Returns routes with full turn-by-turn [NavigationStep]s.
  static Future<List<RouteResult>> getRoutes({
    required LatLng origin,
    required LatLng destination,
    required TravelMode mode,
    List<LatLng>? waypoints,
  }) async {
    // OSRM public demo only has driving profile;
    // for walk/bike we use driving profile and adjust durations.
    const profile = 'driving';
    // Disable alternatives when using waypoints (multi-stop).
    final wantAlternatives = waypoints == null || waypoints.isEmpty;

    // Build coordinate string: origin ; [waypoints...] ; destination
    final coords = StringBuffer()
      ..write('${origin.longitude},${origin.latitude}');
    if (waypoints != null) {
      for (final wp in waypoints) {
        coords.write(';${wp.longitude},${wp.latitude}');
      }
    }
    coords.write(';${destination.longitude},${destination.latitude}');

    final url = Uri.parse(
      '$_baseUrl/route/v1/$profile/$coords'
      '?alternatives=$wantAlternatives&geometries=geojson&overview=full'
      '&steps=true',
    );

    logInfo(_tag, 'Requesting route: $url');

    try {
      final response = await http
          .get(url, headers: {'User-Agent': 'Aanchal-SafetyApp/1.0'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        logError(_tag, 'OSRM returned ${response.statusCode}');
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['code'] != 'Ok') {
        logError(_tag, 'OSRM error: ${json['code']}');
        return [];
      }

      final routes = json['routes'] as List<dynamic>;
      final results = <RouteResult>[];

      for (final route in routes) {
        final geometry = route['geometry'] as Map<String, dynamic>;
        final coordsList = geometry['coordinates'] as List<dynamic>;
        final points = coordsList.map<LatLng>((c) {
          final pair = c as List<dynamic>;
          return LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          );
        }).toList();

        var distance = (route['distance'] as num).toDouble();
        var duration = (route['duration'] as num).toDouble();

        // Adjust durations for non-driving modes using average speeds.
        if (mode == TravelMode.walking) {
          duration = distance / (5000 / 3600); // ~5 km/h
        } else if (mode == TravelMode.cycling) {
          duration = distance / (15000 / 3600); // ~15 km/h
        }

        // ── Parse turn-by-turn steps from OSRM response ─────────────
        final steps = <NavigationStep>[];
        final legs = route['legs'] as List<dynamic>? ?? [];
        for (final leg in legs) {
          final legSteps = leg['steps'] as List<dynamic>? ?? [];
          for (final step in legSteps) {
            final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
            final loc = maneuver['location'] as List<dynamic>? ?? [0, 0];
            final mType = maneuver['type'] as String? ?? '';
            final mModifier = maneuver['modifier'] as String? ?? '';
            final name = step['name'] as String? ?? '';
            final sDist = (step['distance'] as num?)?.toDouble() ?? 0;
            var sDur = (step['duration'] as num?)?.toDouble() ?? 0;

            // Adjust step duration for non-driving modes
            if (mode == TravelMode.walking) {
              sDur = sDist / (5000 / 3600);
            } else if (mode == TravelMode.cycling) {
              sDur = sDist / (15000 / 3600);
            }

            // Build human-readable instruction
            final instruction = _buildInstruction(mType, mModifier, name);

            steps.add(
              NavigationStep(
                location: LatLng(
                  (loc[1] as num).toDouble(),
                  (loc[0] as num).toDouble(),
                ),
                instruction: instruction,
                maneuverType: mType,
                maneuverModifier: mModifier,
                distanceMeters: sDist,
                durationSeconds: sDur,
                roadName: name,
              ),
            );
          }
        }

        results.add(
          RouteResult(
            points: points,
            distanceMeters: distance,
            durationSeconds: duration,
            mode: mode,
            steps: steps,
          ),
        );
      }

      logInfo(
        _tag,
        'Got ${results.length} route(s) for ${mode.displayName}'
        ' with ${results.isNotEmpty ? results.first.steps.length : 0} steps',
      );
      return results;
    } catch (e) {
      logError(_tag, 'Route fetch failed', e);
      return [];
    }
  }

  /// Build a human-readable turn instruction from OSRM maneuver data.
  static String _buildInstruction(String type, String modifier, String road) {
    final roadPart = road.isNotEmpty ? ' onto $road' : '';

    switch (type) {
      case 'depart':
        return 'Head$roadPart';
      case 'arrive':
        return 'You have arrived at your destination';
      case 'turn':
        return 'Turn ${_modifierText(modifier)}$roadPart';
      case 'new name':
        return 'Continue$roadPart';
      case 'merge':
        return 'Merge ${_modifierText(modifier)}$roadPart';
      case 'on ramp':
        return 'Take the ramp ${_modifierText(modifier)}$roadPart';
      case 'off ramp':
        return 'Take the exit$roadPart';
      case 'fork':
        return 'Keep ${_modifierText(modifier)}$roadPart';
      case 'end of road':
        return 'Turn ${_modifierText(modifier)}$roadPart';
      case 'continue':
        return 'Continue ${_modifierText(modifier)}$roadPart';
      case 'roundabout':
      case 'rotary':
        return 'Enter roundabout and exit$roadPart';
      case 'roundabout turn':
        return 'At roundabout, turn ${_modifierText(modifier)}$roadPart';
      case 'notification':
        return road.isNotEmpty ? road : 'Continue';
      default:
        return modifier.isNotEmpty
            ? '${_modifierText(modifier).capitalize()}$roadPart'
            : 'Continue$roadPart';
    }
  }

  static String _modifierText(String modifier) {
    switch (modifier) {
      case 'uturn':
        return 'U-turn';
      case 'sharp right':
        return 'sharp right';
      case 'right':
        return 'right';
      case 'slight right':
        return 'slight right';
      case 'straight':
        return 'straight';
      case 'slight left':
        return 'slight left';
      case 'left':
        return 'left';
      case 'sharp left':
        return 'sharp left';
      default:
        return modifier;
    }
  }
}

extension _StringCap on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
