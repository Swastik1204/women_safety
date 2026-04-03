// Aanchal — Navigation State
//
// Data models for the turn-by-turn navigation engine.
// Used by NavigationService and consumed by the MapScreen UI.

import 'package:latlong2/latlong.dart';
import 'routing_service.dart';

/// A single step/maneuver in a route.
class NavigationStep {
  final LatLng location; // Where the maneuver happens
  final String instruction; // Human-readable text
  final String maneuverType; // OSRM maneuver type: turn, new name, etc.
  final String maneuverModifier; // left, right, straight, slight left, etc.
  final double distanceMeters; // Distance of this step
  final double durationSeconds; // Duration of this step
  final String roadName; // Name of the road

  const NavigationStep({
    required this.location,
    required this.instruction,
    required this.maneuverType,
    required this.maneuverModifier,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.roadName,
  });

  /// Human-friendly distance for this step.
  String get distanceText {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }
}

/// Current navigation state emitted by NavigationService.
enum NavigationStatus { idle, navigating, arrived, rerouting }

class NavigationState {
  final NavigationStatus status;
  final RouteResult? route;
  final List<NavigationStep> steps;
  final int currentStepIndex;
  final LatLng? userLocation;
  final double distanceToNextStepMeters;
  final double totalRemainingMeters;
  final double totalRemainingSeconds;
  final double completedFraction; // 0.0 → 1.0

  const NavigationState({
    this.status = NavigationStatus.idle,
    this.route,
    this.steps = const [],
    this.currentStepIndex = 0,
    this.userLocation,
    this.distanceToNextStepMeters = 0,
    this.totalRemainingMeters = 0,
    this.totalRemainingSeconds = 0,
    this.completedFraction = 0,
  });

  NavigationStep? get currentStep =>
      currentStepIndex < steps.length ? steps[currentStepIndex] : null;

  NavigationStep? get nextStep =>
      currentStepIndex + 1 < steps.length ? steps[currentStepIndex + 1] : null;

  bool get isNavigating => status == NavigationStatus.navigating;
  bool get hasArrived => status == NavigationStatus.arrived;

  NavigationState copyWith({
    NavigationStatus? status,
    RouteResult? route,
    List<NavigationStep>? steps,
    int? currentStepIndex,
    LatLng? userLocation,
    double? distanceToNextStepMeters,
    double? totalRemainingMeters,
    double? totalRemainingSeconds,
    double? completedFraction,
  }) {
    return NavigationState(
      status: status ?? this.status,
      route: route ?? this.route,
      steps: steps ?? this.steps,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      userLocation: userLocation ?? this.userLocation,
      distanceToNextStepMeters:
          distanceToNextStepMeters ?? this.distanceToNextStepMeters,
      totalRemainingMeters: totalRemainingMeters ?? this.totalRemainingMeters,
      totalRemainingSeconds:
          totalRemainingSeconds ?? this.totalRemainingSeconds,
      completedFraction: completedFraction ?? this.completedFraction,
    );
  }

  /// Remaining time as human-readable text.
  String get remainingTimeText {
    final mins = (totalRemainingSeconds / 60).ceil();
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}h ${m}m';
  }

  /// Remaining distance as human-readable text.
  String get remainingDistanceText {
    if (totalRemainingMeters < 1000) {
      return '${totalRemainingMeters.round()} m';
    }
    return '${(totalRemainingMeters / 1000).toStringAsFixed(1)} km';
  }

  /// Distance to next turn as human-readable text.
  String get nextTurnDistanceText {
    if (distanceToNextStepMeters < 1000) {
      return '${distanceToNextStepMeters.round()} m';
    }
    return '${(distanceToNextStepMeters / 1000).toStringAsFixed(1)} km';
  }
}
