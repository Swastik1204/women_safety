// Aanchal — Navigation Service
//
// Turn-by-turn navigation engine that:
//   • Listens to Geolocator position stream
//   • Advances through route steps as user moves
//   • Broadcasts NavigationState updates via a stream
//   • Manages a persistent foreground notification with turn instructions
//   • Tracks distance covered and remaining

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:latlong2/latlong.dart';
import '../core/logger.dart';
import 'navigation_state.dart';
import 'routing_service.dart';

const _tag = 'NavigationService';
const _notificationChannelId = 'aanchal_navigation';
const _notificationChannelName = 'Navigation';
const _notificationId = 9001;

/// Threshold in meters to consider "arrived at next maneuver".
const _stepArrivalThresholdMeters = 30.0;

/// Threshold in meters to consider "arrived at destination".
const _destinationArrivalThresholdMeters = 40.0;

class NavigationService {
  NavigationService._();
  static final instance = NavigationService._();

  // ── Notification plugin ────────────────────────────────────────────
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsInitialized = false;

  // ── Position stream ────────────────────────────────────────────────
  StreamSubscription<geo.Position>? _positionSub;

  // ── State ──────────────────────────────────────────────────────────
  NavigationState _state = const NavigationState();
  final _stateController = StreamController<NavigationState>.broadcast();
  Stream<NavigationState> get stateStream => _stateController.stream;
  NavigationState get currentState => _state;

  RouteResult? _activeRoute;
  double _totalRouteMeters = 0;

  // ══════════════════════════════════════════════════════════════════════
  // Public API
  // ══════════════════════════════════════════════════════════════════════

  /// Initialize the notification channel (call once at app startup).
  Future<void> init() async {
    if (_notificationsInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);

    // Create notification channel
    const androidChannel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: 'Turn-by-turn navigation updates',
      importance: Importance.high,
      playSound: false,
      enableVibration: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    _notificationsInitialized = true;
    logInfo(_tag, 'Notification channel initialized');
  }

  /// Start navigation on a selected route.
  Future<void> startNavigation(RouteResult route) async {
    await init();
    await stopNavigation(); // Clean up any previous session

    _activeRoute = route;
    _totalRouteMeters = route.distanceMeters;

    _state = NavigationState(
      status: NavigationStatus.navigating,
      route: route,
      steps: route.steps,
      currentStepIndex: 0,
      totalRemainingMeters: route.distanceMeters,
      totalRemainingSeconds: route.durationSeconds,
      completedFraction: 0,
    );
    _emit(_state);

    // Show initial notification
    _showNotification(
      route.steps.isNotEmpty ? route.steps.first.instruction : 'Navigating…',
      'Total: ${route.distanceText} • ${route.durationText}',
    );

    // Start listening to position updates
    _positionSub =
        geo.Geolocator.getPositionStream(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
            distanceFilter: 5, // update every 5 meters
          ),
        ).listen(
          _onPositionUpdate,
          onError: (e) {
            logError(_tag, 'Position stream error', e);
          },
        );

    logInfo(_tag, 'Navigation started with ${route.steps.length} steps');
  }

  /// Stop navigation and clean up.
  Future<void> stopNavigation() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _activeRoute = null;
    _totalRouteMeters = 0;

    _state = const NavigationState(status: NavigationStatus.idle);
    _emit(_state);

    // Dismiss notification
    await _notifications.cancel(_notificationId);

    logInfo(_tag, 'Navigation stopped');
  }

  /// Dispose everything when the service is no longer needed.
  void dispose() {
    _positionSub?.cancel();
    _stateController.close();
    _notifications.cancel(_notificationId);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Position processing
  // ══════════════════════════════════════════════════════════════════════

  void _onPositionUpdate(geo.Position position) {
    if (_activeRoute == null) return;

    final userLoc = LatLng(position.latitude, position.longitude);
    final steps = _state.steps;
    var stepIndex = _state.currentStepIndex;

    // ── Check if we've arrived at (or passed) the current step ───────
    while (stepIndex < steps.length) {
      final stepLoc = steps[stepIndex].location;
      final dist = _distanceBetween(userLoc, stepLoc);

      if (dist < _stepArrivalThresholdMeters) {
        // Advance to next step
        stepIndex++;
        logInfo(_tag, 'Reached step $stepIndex');
      } else {
        break;
      }
    }

    // ── Check destination arrival ────────────────────────────────────
    final destPoint = _activeRoute!.points.last;
    final distToDest = _distanceBetween(userLoc, destPoint);

    if (distToDest < _destinationArrivalThresholdMeters) {
      _state = _state.copyWith(
        status: NavigationStatus.arrived,
        userLocation: userLoc,
        currentStepIndex: steps.length,
        distanceToNextStepMeters: 0,
        totalRemainingMeters: 0,
        totalRemainingSeconds: 0,
        completedFraction: 1.0,
      );
      _emit(_state);
      _showNotification('You have arrived!', 'Destination reached');
      stopNavigation();
      return;
    }

    // ── Calculate distances ──────────────────────────────────────────
    double distToNext = 0;
    if (stepIndex < steps.length) {
      distToNext = _distanceBetween(userLoc, steps[stepIndex].location);
    }

    // Sum remaining step distances from current step onward
    double remainingMeters = distToNext;
    for (var i = stepIndex + 1; i < steps.length; i++) {
      remainingMeters += steps[i].distanceMeters;
    }

    // Estimate remaining time based on fraction of total route
    final fractionRemaining = _totalRouteMeters > 0
        ? remainingMeters / _totalRouteMeters
        : 0.0;
    final remainingSeconds = _activeRoute!.durationSeconds * fractionRemaining;
    final completedFraction = (1.0 - fractionRemaining).clamp(0.0, 1.0);

    // ── Update state ─────────────────────────────────────────────────
    _state = _state.copyWith(
      userLocation: userLoc,
      currentStepIndex: stepIndex,
      distanceToNextStepMeters: distToNext,
      totalRemainingMeters: remainingMeters,
      totalRemainingSeconds: remainingSeconds,
      completedFraction: completedFraction,
    );
    _emit(_state);

    // ── Update notification ──────────────────────────────────────────
    final currentStep = _state.currentStep;
    if (currentStep != null) {
      _showNotification(
        '${_state.nextTurnDistanceText} — ${currentStep.instruction}',
        '${_state.remainingDistanceText} remaining • ${_state.remainingTimeText}',
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════════════

  void _emit(NavigationState state) {
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  /// Show / update the persistent navigation notification.
  Future<void> _showNotification(String title, String body) async {
    if (!_notificationsInitialized) return;

    const androidDetails = AndroidNotificationDetails(
      _notificationChannelId,
      _notificationChannelName,
      channelDescription: 'Turn-by-turn navigation updates',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      playSound: false,
      enableVibration: false,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.navigation,
    );

    const details = NotificationDetails(android: androidDetails);

    try {
      await _notifications.show(_notificationId, title, body, details);
    } catch (e) {
      logError(_tag, 'Failed to show notification', e);
    }
  }

  /// Haversine distance between two LatLng points in meters.
  static double _distanceBetween(LatLng a, LatLng b) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLon = _toRadians(b.longitude - a.longitude);
    final aLat = _toRadians(a.latitude);
    final bLat = _toRadians(b.latitude);

    final x =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(aLat) *
            math.cos(bLat) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
    return earthRadius * c;
  }

  static double _toRadians(double deg) => deg * math.pi / 180;

  /// Get the direction icon name for a maneuver modifier.
  static String maneuverIcon(String type, String modifier) {
    if (type == 'arrive') return 'flag';
    if (type == 'depart') return 'navigation';

    switch (modifier) {
      case 'left':
      case 'sharp left':
      case 'slight left':
        return 'turn_left';
      case 'right':
      case 'sharp right':
      case 'slight right':
        return 'turn_right';
      case 'uturn':
        return 'u_turn_left';
      case 'straight':
      default:
        return 'straight';
    }
  }
}
