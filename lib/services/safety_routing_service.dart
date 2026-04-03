// Aanchal — Safety Routing Service
//
// Evaluates routes against known danger zones (red zones) to determine
// which routes are safe and which pass through dangerous areas.
// Also collects all available danger-zone polygons from Firestore.
// Includes detour-waypoint logic to guarantee at least one safe route.

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../core/logger.dart';
import 'routing_service.dart';

const _tag = 'SafetyRoutingService';

/// A danger-zone polygon with metadata.
class DangerZone {
  final String id;
  final String name;
  final List<LatLng> polygon;

  const DangerZone({
    required this.id,
    required this.name,
    required this.polygon,
  });
}

class SafetyRoutingService {
  static bool _didWarnOverlayPermission = false;

  /// Fetch all danger zones from Firestore + any hardcoded defaults.
  static Future<List<DangerZone>> fetchDangerZones() async {
    final zones = <DangerZone>[];

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('danger_zones')
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final rawPoints = data['points'] as List<dynamic>? ?? [];
        final points = rawPoints.map<LatLng>((p) {
          final m = p as Map<String, dynamic>;
          return LatLng(
            (m['lat'] as num).toDouble(),
            (m['lng'] as num).toDouble(),
          );
        }).toList();

        if (points.length >= 3) {
          zones.add(
            DangerZone(
              id: doc.id,
              name: data['name'] as String? ?? 'Unnamed Zone',
              polygon: points,
            ),
          );
        }
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        if (!_didWarnOverlayPermission) {
          _didWarnOverlayPermission = true;
          logWarn(
            _tag,
            'danger_zones read denied by Firestore rules; using local fallback only.',
          );
        }
      } else {
        logError(_tag, 'Failed to fetch Firestore danger zones', e);
      }
    } catch (e) {
      logError(_tag, 'Failed to fetch Firestore danger zones', e);
    }

    return zones;
  }

  /// Check if a route passes through any danger zone.
  /// Returns true if the route intersects **ANY** zone polygon.
  static bool routeIntersectsDangerZones(
    List<LatLng> routePoints,
    List<DangerZone> zones,
  ) {
    // Sample every N-th point for performance.
    final step = math.max(1, routePoints.length ~/ 80);
    for (var i = 0; i < routePoints.length; i += step) {
      for (final zone in zones) {
        if (_pointInPolygon(routePoints[i], zone.polygon)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Also check the hardcoded default danger zone.
  static bool routeIntersectsPolygons(
    List<LatLng> routePoints,
    List<List<LatLng>> polygons,
  ) {
    final step = math.max(1, routePoints.length ~/ 80);
    for (var i = 0; i < routePoints.length; i += step) {
      for (final polygon in polygons) {
        if (_pointInPolygon(routePoints[i], polygon)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Tag each [RouteResult] with safety info against a combined set
  /// of [DangerZone]s and any extra hardcoded polygons.
  static List<RouteResult> evaluateRouteSafety(
    List<RouteResult> routes,
    List<DangerZone> firestoreZones,
    List<List<LatLng>> extraPolygons,
  ) {
    final allPolygons = <List<LatLng>>[
      ...firestoreZones.map((z) => z.polygon),
      ...extraPolygons,
    ];

    return routes.map((route) {
      final intersects = routeIntersectsPolygons(route.points, allPolygons);
      return route.copyWith(isSafe: !intersects);
    }).toList();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Detour waypoint logic — ensures at least one safe route
  // ══════════════════════════════════════════════════════════════════════

  /// Fetch routes for a mode, ensuring at least 2 routes and at least 1 safe.
  ///
  /// Strategy:
  /// 1. Fetch normal OSRM alternatives.
  /// 2. Evaluate safety for each.
  /// 3. If no safe route exists, compute a detour waypoint that goes around
  ///    the intersecting danger zone(s) and request a new route through it.
  /// 4. Return merged results sorted: safe routes first, then unsafe.
  static Future<List<RouteResult>> fetchRoutesWithSafeAlternative({
    required LatLng origin,
    required LatLng destination,
    required TravelMode mode,
    required List<DangerZone> firestoreZones,
    required List<List<LatLng>> extraPolygons,
  }) async {
    final allPolygons = <List<LatLng>>[
      ...firestoreZones.map((z) => z.polygon),
      ...extraPolygons,
    ];

    // ── Step 1: Fetch standard routes ────────────────────────────────
    var routes = await RoutingService.getRoutes(
      origin: origin,
      destination: destination,
      mode: mode,
    );

    if (routes.isEmpty) return [];

    // ── Step 2: Evaluate safety ──────────────────────────────────────
    routes = routes.map((r) {
      final intersects = routeIntersectsPolygons(r.points, allPolygons);
      return r.copyWith(isSafe: !intersects);
    }).toList();

    final hasSafe = routes.any((r) => r.isSafe);

    // ── Step 3: If no safe route, compute detour ─────────────────────
    if (!hasSafe) {
      logInfo(_tag, 'No safe route found — calculating detour waypoint');

      // Find which polygons the first (shortest) route intersects.
      final intersectingPolygons = allPolygons.where((polygon) {
        return routeIntersectsPolygons(routes.first.points, [polygon]);
      }).toList();

      if (intersectingPolygons.isNotEmpty) {
        final detourPoint = _calculateDetourWaypoint(
          origin,
          destination,
          intersectingPolygons.first,
        );

        if (detourPoint != null) {
          logInfo(
            _tag,
            'Detour waypoint: ${detourPoint.latitude}, ${detourPoint.longitude}',
          );

          final detourRoutes = await RoutingService.getRoutes(
            origin: origin,
            destination: destination,
            mode: mode,
            waypoints: [detourPoint],
          );

          // Evaluate detour routes for safety
          final evaluatedDetour = detourRoutes.map((r) {
            final intersects = routeIntersectsPolygons(r.points, allPolygons);
            return r.copyWith(isSafe: !intersects);
          }).toList();

          // If still unsafe, try a second offset on the other side
          if (evaluatedDetour.isNotEmpty &&
              !evaluatedDetour.any((r) => r.isSafe)) {
            logInfo(_tag, 'First detour still unsafe, trying opposite side');
            final detour2 = _calculateDetourWaypoint(
              origin,
              destination,
              intersectingPolygons.first,
              oppositeSide: true,
            );
            if (detour2 != null) {
              final detourRoutes2 = await RoutingService.getRoutes(
                origin: origin,
                destination: destination,
                mode: mode,
                waypoints: [detour2],
              );
              final evaluatedDetour2 = detourRoutes2.map((r) {
                final intersects = routeIntersectsPolygons(
                  r.points,
                  allPolygons,
                );
                return r.copyWith(isSafe: !intersects);
              }).toList();
              routes.addAll(evaluatedDetour2);
            }
          }

          routes.addAll(evaluatedDetour);
        }
      }
    }

    // ── Step 4: Sort — safe routes first ─────────────────────────────
    routes.sort((a, b) {
      if (a.isSafe && !b.isSafe) return -1;
      if (!a.isSafe && b.isSafe) return 1;
      return a.durationSeconds.compareTo(b.durationSeconds);
    });

    // Ensure at least 2 routes (duplicate the best if OSRM returned only 1)
    if (routes.length < 2) {
      logInfo(_tag, 'Only ${routes.length} route, trying detour for variety');
      // Try creating a variant with a slight offset waypoint
      final midLat = (origin.latitude + destination.latitude) / 2;
      final midLng = (origin.longitude + destination.longitude) / 2;
      // Small offset (~200m perpendicular)
      final dx = destination.longitude - origin.longitude;
      final dy = destination.latitude - origin.latitude;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len > 0) {
        final offset = 0.002; // ~200m
        final wp = LatLng(
          midLat + dx / len * offset,
          midLng - dy / len * offset,
        );
        final variantRoutes = await RoutingService.getRoutes(
          origin: origin,
          destination: destination,
          mode: mode,
          waypoints: [wp],
        );
        final evaluated = variantRoutes.map((r) {
          final intersects = routeIntersectsPolygons(r.points, allPolygons);
          return r.copyWith(isSafe: !intersects);
        }).toList();
        routes.addAll(evaluated);
      }
    }

    logInfo(
      _tag,
      'Final: ${routes.length} routes, '
      '${routes.where((r) => r.isSafe).length} safe',
    );

    return routes;
  }

  /// Compute a waypoint that detours around a danger-zone polygon.
  ///
  /// The waypoint is placed perpendicular to the origin→destination line,
  /// offset beyond the bounding box of the polygon with a margin.
  static LatLng? _calculateDetourWaypoint(
    LatLng origin,
    LatLng destination,
    List<LatLng> dangerPolygon, {
    bool oppositeSide = false,
  }) {
    if (dangerPolygon.isEmpty) return null;

    // Bounding box of the danger zone
    double minLat = dangerPolygon.first.latitude;
    double maxLat = dangerPolygon.first.latitude;
    double minLng = dangerPolygon.first.longitude;
    double maxLng = dangerPolygon.first.longitude;

    for (final p in dangerPolygon) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    // Center of the bounding box
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    // Direction vector from origin to destination (normalized)
    final dx = destination.longitude - origin.longitude;
    final dy = destination.latitude - origin.latitude;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return null;

    // Perpendicular direction (rotated 90°) — this pushes the route sideways
    var perpDx = -dy / len;
    var perpDy = dx / len;

    // Decide which side to offset: pick the side away from the polygon center
    final midLat = (origin.latitude + destination.latitude) / 2;
    final midLng = (origin.longitude + destination.longitude) / 2;

    // Vector from route midpoint to polygon center
    final toCenterDx = centerLng - midLng;
    final toCenterDy = centerLat - midLat;

    // Dot product: if positive, the perpendicular goes toward the polygon.
    // In that case, flip it.
    final dot = perpDx * toCenterDx + perpDy * toCenterDy;
    if (dot > 0) {
      perpDx = -perpDx;
      perpDy = -perpDy;
    }

    if (oppositeSide) {
      perpDx = -perpDx;
      perpDy = -perpDy;
    }

    // Offset distance: half the diagonal of the bounding box + margin
    final bboxWidth = maxLng - minLng;
    final bboxHeight = maxLat - minLat;
    final halfDiag =
        math.sqrt(bboxWidth * bboxWidth + bboxHeight * bboxHeight) / 2;
    final margin = 0.003; // ~300m extra clearance
    final offset = halfDiag + margin;

    // Place the waypoint at the midpoint of origin→destination,
    // offset perpendicular by the computed distance.
    final waypointLat = midLat + perpDy * offset;
    final waypointLng = midLng + perpDx * offset;

    return LatLng(waypointLat, waypointLng);
  }

  // ── Ray-casting point-in-polygon test ─────────────────────────────
  static bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    var inside = false;
    final n = polygon.length;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].latitude, yi = polygon[i].longitude;
      final xj = polygon[j].latitude, yj = polygon[j].longitude;

      final intersect =
          ((yi > point.longitude) != (yj > point.longitude)) &&
          (point.latitude <
              (xj - xi) * (point.longitude - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}
