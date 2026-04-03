// ignore_for_file: deprecated_member_use, unused_element

// Aanchal — Map Screen
//
// Production-ready OpenStreetMap view (flutter_map) with:
//   • Hardcoded base layers  → danger-zone polygon, police station, pink booth
//   • Dynamic overlays       → Firestore `danger_zones` & `static_places`
//   • Live patrol markers    → Firebase Realtime Database `live_patrols` node
//   • Live patrol route line → Firebase Realtime Database `live_patrols/…/route`
//   • User live location     → Geolocator with blue dot marker
//   • Destination search     → Nominatim (OpenStreetMap) geocoding
//   • Smart routing          → OSRM free routing with safety analysis
//   • Route selection UI     → Bottom sheet with mode, time, safe/unsafe
//   • Shared location intake → Receive destinations from Google/Apple Maps share
//   • Long-press destination → Drop pin, reverse geocode, set destination
//   • Turn-by-turn navigation → Live instructions, progress bar, notifications
//
// Static base data is always visible.  Firestore streams add extra data on top.
// The RTDB stream drives real-time patrol car movement along the route.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;

import '../../core/app_config.dart';
import '../../core/logger.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../services/navigation_service.dart';
import '../../services/navigation_state.dart';
import '../../services/routing_service.dart';
import '../../services/safety_routing_service.dart';
import '../../services/shared_location_parser.dart';

const _tag = 'MapScreen';

// ═══════════════════════════════════════════════════════════════════════════
// MapScreen
// ═══════════════════════════════════════════════════════════════════════════

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final Map<String, LatLng> _previousPatrolPositions = <String, LatLng>{};
  final Map<String, double> _patrolBearings = <String, double>{};

  // ── Map centre (SRM / Kattankulathur area) ────────────────────────────
  static const _initialPosition = LatLng(12.824864, 80.046118);

  // ── User location ─────────────────────────────────────────────────────
  LatLng? _currentPosition;
  bool _locationLoading = true;

  // ── Search state ──────────────────────────────────────────────────────
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<GeocodingResult> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;

  // ── Routing state ─────────────────────────────────────────────────────
  LatLng? _destination;
  String? _destinationName;
  TravelMode _selectedMode = TravelMode.driving;
  List<RouteResult> _routeResults = [];
  int _selectedRouteIndex = 0;
  bool _routeLoading = false;
  bool _showRouteSheet = false;
  List<DangerZone> _dangerZonesCache = [];
  bool _firestoreOverlaysEnabled = true;
  bool _overlayPermissionWarningShown = false;

  // ── Long-press pin state ──────────────────────────────────────────────
  LatLng? _longPressPin;
  String? _longPressPinName;
  bool _longPressLoading = false;

  // ── Navigation state ──────────────────────────────────────────────────
  bool _isNavigating = false;
  NavigationState _navState = const NavigationState();
  StreamSubscription<NavigationState>? _navSub;

  // ── Sharing intent subscription ───────────────────────────────────────
  StreamSubscription<dynamic>? _sharingSub;

  // ── Firestore references ──────────────────────────────────────────────
  final _dangerZonesRef = FirebaseFirestore.instance.collection('danger_zones');
  final _staticPlacesRef = FirebaseFirestore.instance.collection(
    'static_places',
  );

  // ── Realtime Database references ──────────────────────────────────────
  final _livePatrolsRef = FirebaseDatabase.instance.ref('live_patrols');

  // ══════════════════════════════════════════════════════════════════════
  // Hardcoded base data (always visible, regardless of Firestore content)
  // ══════════════════════════════════════════════════════════════════════

  /// Default danger-zone polygon (red overlay) near the new centre.
  static const _defaultDangerZone = [
    LatLng(12.8210, 80.0410),
    LatLng(12.8210, 80.0450),
    LatLng(12.8180, 80.0450),
    LatLng(12.8180, 80.0410),
  ];

  /// Built-in safe-place markers near 12.824864, 80.046118.
  late final List<Marker> _defaultSafeMarkers = [
    Marker(
      point: const LatLng(12.8255, 80.0455),
      width: 80,
      height: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/map/policestation.png', width: 48, height: 48),
          const Text(
            'Police Station',
            style: TextStyle(
              fontSize: 9,
              color: Colors.white,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(blurRadius: 2)],
            ),
          ),
        ],
      ),
    ),
    const Marker(
      point: LatLng(12.8235, 80.0480),
      width: 90,
      height: 62,
      child: _PoiPin(
        icon: Icons.shield,
        label: 'Pink Booth',
        color: Colors.pink,
      ),
    ),
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    logInfo(_tag, 'MapScreen initialised (OSM + Firebase streams)');
    _initUserLocation();
    _initFirestoreOverlayAccess();
    _initSharingIntent();
    _initNavigationListener();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _sharingSub?.cancel();
    _navSub?.cancel();
    super.dispose();
  }

  // ── Sharing intent init ───────────────────────────────────────────────

  void _initSharingIntent() {
    // Disabled temporarily for Android build compatibility with Kotlin 2.3.
    // Can be re-enabled after migrating to a sharing plugin compatible with
    // current AGP/Kotlin toolchain.
    _sharingSub = null;
  }

  Future<void> _handleSharedText(String text) async {
    final result = await SharedLocationParser.parse(
      text,
      userLocation: _currentPosition,
    );
    if (result != null && mounted) {
      setState(() {
        _destination = result.location;
        _destinationName = result.name;
        _searchController.text = result.name;
        _showSearchResults = false;
        _showRouteSheet = false;
        _routeResults = [];
      });
      _mapController.move(result.location, 14);
      await _fetchRoutes();
    }
  }

  // ── Navigation listener init ──────────────────────────────────────────

  void _initNavigationListener() {
    _navSub = NavigationService.instance.stateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _navState = state;
        if (state.hasArrived) {
          _isNavigating = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 You have arrived at your destination!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        // Auto-pan map to follow user during navigation
        if (state.isNavigating && state.userLocation != null) {
          _currentPosition = state.userLocation;
          _mapController.move(state.userLocation!, _mapController.camera.zoom);
        }
      });
    });
  }

  // ── Location init ─────────────────────────────────────────────────────

  Future<void> _initUserLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _locationLoading = false;
      if (pos != null) {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _mapController.move(_currentPosition!, 15);
      }
    });
  }

  Future<void> _loadDangerZones() async {
    if (!_firestoreOverlaysEnabled) {
      _dangerZonesCache = [];
      return;
    }

    _dangerZonesCache = await SafetyRoutingService.fetchDangerZones();
  }

  Future<void> _initFirestoreOverlayAccess() async {
    try {
      await Future.wait([
        _dangerZonesRef.limit(1).get(),
        _staticPlacesRef.limit(1).get(),
      ]);
      if (!mounted) return;
      setState(() => _firestoreOverlaysEnabled = true);
      await _loadDangerZones();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      if (e.code == 'permission-denied') {
        setState(() => _firestoreOverlaysEnabled = false);
        if (!_overlayPermissionWarningShown) {
          _overlayPermissionWarningShown = true;
          logWarn(
            _tag,
            'Firestore map overlays disabled (permission denied). '
            'Deploy updated firestore.rules to enable danger_zones/static_places.',
          );
        }
        return;
      }

      setState(() => _firestoreOverlaysEnabled = false);
      logWarn(_tag, 'Firestore overlay probe failed: ${e.code} ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _firestoreOverlaysEnabled = false);
      logWarn(_tag, 'Firestore overlay probe failed: $e');
    }
  }

  void _handleOverlayStreamError(Object? error, String collectionName) {
    final text = '$error'.toLowerCase();
    if (text.contains('permission-denied')) {
      if (!_overlayPermissionWarningShown) {
        _overlayPermissionWarningShown = true;
        logWarn(
          _tag,
          'Firestore stream denied for $collectionName; overlays disabled for this session.',
        );
      }

      if (_firestoreOverlaysEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _firestoreOverlaysEnabled = false);
        });
      }
      return;
    }

    logWarn(_tag, '$collectionName stream error: $error');
  }

  // ── Search helpers ────────────────────────────────────────────────────

  Timer? _debounce;

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isSearching = true);
    final results = await GeocodingService.search(
      query,
      near: _currentPosition ?? _initialPosition,
    );
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
      _showSearchResults = results.isNotEmpty;
    });
  }

  Future<void> _selectDestination(GeocodingResult result) async {
    _searchFocusNode.unfocus();
    setState(() {
      _destination = result.location;
      _destinationName = result.shortName;
      _searchController.text = result.shortName;
      _showSearchResults = false;
      _showRouteSheet = false;
      _routeResults = [];
    });
    _mapController.move(result.location, 14);
    await _fetchRoutes();
  }

  // ── Routing helpers ───────────────────────────────────────────────────

  Future<void> _fetchRoutes() async {
    final origin = _currentPosition ?? _initialPosition;
    final dest = _destination;
    if (dest == null) return;

    setState(() => _routeLoading = true);

    // Use the enhanced routing that guarantees at least 1 safe route.
    final evaluated = await SafetyRoutingService.fetchRoutesWithSafeAlternative(
      origin: origin,
      destination: dest,
      mode: _selectedMode,
      firestoreZones: _dangerZonesCache,
      extraPolygons: [_defaultDangerZone],
    );

    if (!mounted) return;

    setState(() {
      _routeResults = evaluated;
      _selectedRouteIndex = 0;
      _routeLoading = false;
      _showRouteSheet = evaluated.isNotEmpty;
    });

    // Fit map to show the full route.
    if (evaluated.isNotEmpty) {
      _fitMapToRoute(evaluated.first.points);
    }
  }

  void _fitMapToRoute(List<LatLng> points) {
    if (points.isEmpty) return;
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
        padding: const EdgeInsets.all(60),
      ),
    );
  }

  void _clearRoute() {
    if (_isNavigating) {
      NavigationService.instance.stopNavigation();
      _isNavigating = false;
    }
    setState(() {
      _destination = null;
      _destinationName = null;
      _routeResults = [];
      _showRouteSheet = false;
      _searchController.clear();
      _longPressPin = null;
      _longPressPinName = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safe Map'),
        actions: [
          if (_destination != null)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear route',
              onPressed: _clearRoute,
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialPosition,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onTap: (_, __) {
                // Dismiss search results on map tap.
                if (_showSearchResults) {
                  setState(() => _showSearchResults = false);
                }
                _searchFocusNode.unfocus();
                // Clear long-press pin if tapping elsewhere
                if (_longPressPin != null && _destination == null) {
                  setState(() {
                    _longPressPin = null;
                    _longPressPinName = null;
                  });
                }
              },
              onLongPress: (tapPos, latLng) => _handleLongPress(latLng),
            ),
            children: [
              // ── OSM tile layer ────────────────────────────────────
              TileLayer(
                urlTemplate: AppConfig.mapTileUrlTemplate,
                subdomains: AppConfig.mapTileSubdomains,
                userAgentPackageName: 'my.aanchal',
              ),

              // ── Hardcoded danger-zone polygon ─────────────────────
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _defaultDangerZone,
                    color: Colors.red.withValues(alpha: 0.25),
                    borderColor: Colors.red,
                    borderStrokeWidth: 2,
                    label: 'Red Zone',
                    labelStyle: const TextStyle(
                      color: Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              // ── Extra danger-zones from Firestore ─────────────────
              _buildFirestoreDangerZonesLayer(),

              // ── Patrol route polyline from RTDB ───────────────────
              _buildPatrolRouteLayer(),

              // ── Navigated route polylines ──────────────────────────
              _buildNavigationRouteLayer(),

              // ── Hardcoded safe-place markers ───────────────────────
              MarkerLayer(markers: _defaultSafeMarkers),

              // ── Extra static places from Firestore ────────────────
              _buildFirestoreStaticPlacesLayer(),

              // ── Live patrol markers (Realtime DB stream) ──────────
              _buildLivePatrolsLayer(),

              // ── User location marker ──────────────────────────────
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

              // ── Destination marker ────────────────────────────────
              if (_destination != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _destination!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.deepOrange,
                        size: 40,
                      ),
                    ),
                  ],
                ),

              // ── Long-press pin marker ─────────────────────────────
              if (_longPressPin != null && _destination == null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _longPressPin!,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.push_pin,
                        color: Colors.purple,
                        size: 40,
                      ),
                    ),
                  ],
                ),

              // ── OSM attribution ───────────────────────────────────
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    AppConfig.mapTileAttribution,
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),

          // ── Navigation banner (during turn-by-turn) ───────────────
          if (_isNavigating) _buildNavigationBanner(),

          // ── Long-press info sheet ───────────────────────────────────
          if (_longPressPin != null && _destination == null)
            _buildLongPressSheet(),

          // ── Search bar overlay ──────────────────────────────────────
          if (!_isNavigating)
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Column(
                children: [
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchChanged,
                      onSubmitted: (q) => _performSearch(q),
                      decoration: InputDecoration(
                        hintText: 'Search destination…',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchResults = [];
                                    _showSearchResults = false;
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  // ── Search results dropdown ─────────────────────────
                  if (_showSearchResults) _buildSearchResultsList(),
                  if (_isSearching)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),

          // ── Loading indicator for location ──────────────────────────
          if (_locationLoading)
            const Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Chip(
                  avatar: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  label: Text('Getting your location…'),
                ),
              ),
            ),

          // ── Route selection bottom sheet ─────────────────────────────
          if (_showRouteSheet && !_isNavigating) _buildRouteBottomSheet(),

          // ── Route loading indicator ─────────────────────────────────
          if (_routeLoading)
            const Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Chip(
                  avatar: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  label: Text('Finding safest routes…'),
                ),
              ),
            ),
        ],
      ),

      // ── Re-centre FAB ──────────────────────────────────────────────
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isNavigating)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FloatingActionButton.small(
                heroTag: 'stop_nav',
                tooltip: 'Stop navigation',
                backgroundColor: Colors.red,
                onPressed: _stopNavigation,
                child: const Icon(Icons.stop, color: Colors.white),
              ),
            ),
          FloatingActionButton.small(
            heroTag: 'map_recenter',
            tooltip: 'Re-centre to my location',
            onPressed: () {
              final target = _currentPosition ?? _initialPosition;
              _mapController.move(target, 15);
            },
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // Search results dropdown
  // ═════════════════════════════════════════════════════════════════════

  Widget _buildSearchResultsList() {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _searchResults.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final result = _searchResults[index];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.place, color: Colors.deepOrange),
              title: Text(
                result.shortName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                result.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () => _selectDestination(result),
            );
          },
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // Route bottom sheet
  // ═════════════════════════════════════════════════════════════════════

  Widget _buildRouteBottomSheet() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Handle bar ──────────────────────────────────────────
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // ── Destination header ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.flag, color: Colors.deepOrange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _destinationName ?? 'Destination',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _clearRoute,
                    ),
                  ],
                ),
              ),

              // ── Travel mode tabs ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: TravelMode.values.map((mode) {
                    final isActive = mode == _selectedMode;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Text(mode.displayName),
                          avatar: Text(
                            mode.emoji,
                            style: const TextStyle(fontSize: 14),
                          ),
                          selected: isActive,
                          onSelected: (_) {
                            setState(() => _selectedMode = mode);
                            _fetchRoutes();
                          },
                          selectedColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          padding: EdgeInsets.zero,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 8),

              // ── Route alternatives list ─────────────────────────────
              if (_routeResults.isEmpty && !_routeLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No routes found. Try a different destination.'),
                ),

              ..._routeResults.asMap().entries.map((entry) {
                final idx = entry.key;
                final route = entry.value;
                final isSelected = idx == _selectedRouteIndex;
                final isFastest =
                    idx == 0 ||
                    route.durationSeconds ==
                        _routeResults
                            .map((r) => r.durationSeconds)
                            .reduce(math.min);

                return InkWell(
                  onTap: () {
                    setState(() => _selectedRouteIndex = idx);
                    _fitMapToRoute(route.points);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 3,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (route.isSafe
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.red.withValues(alpha: 0.1))
                          : null,
                      border: Border.all(
                        color: isSelected
                            ? (route.isSafe ? Colors.green : Colors.red)
                            : Colors.grey.withValues(alpha: 0.3),
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        // Safety icon
                        Icon(
                          route.isSafe
                              ? Icons.verified_user
                              : Icons.warning_amber_rounded,
                          color: route.isSafe ? Colors.green : Colors.red,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        // Time & distance
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    route.durationText,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: route.isSafe
                                          ? Colors.green[700]
                                          : Colors.red[700],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    route.distanceText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (route.isSafe)
                                    _buildTag('Safe Route', Colors.green)
                                  else
                                    _buildTag('⚠ Passes Red Zone', Colors.red),
                                  if (isFastest) ...[
                                    const SizedBox(width: 6),
                                    _buildTag('Fastest', Colors.blue),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Selection radio
                        Radio<int>(
                          value: idx,
                          groupValue: _selectedRouteIndex,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedRouteIndex = val);
                              _fitMapToRoute(route.points);
                            }
                          },
                          activeColor: route.isSafe ? Colors.green : Colors.red,
                        ),
                      ],
                    ),
                  ),
                );
              }),

              // ── Start navigation button ─────────────────────────────
              if (_routeResults.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        final selected = _routeResults[_selectedRouteIndex];
                        if (!selected.isSafe) {
                          // Warn user before confirming unsafe route.
                          _showUnsafeRouteDialog(selected);
                        } else {
                          _confirmRoute(selected);
                        }
                      },
                      icon: const Icon(Icons.navigation),
                      label: Text(
                        _routeResults[_selectedRouteIndex].isSafe
                            ? 'Start Safe Route'
                            : 'Start Route (Unsafe)',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            _routeResults[_selectedRouteIndex].isSafe
                            ? Colors.green
                            : Colors.orange,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  void _showUnsafeRouteDialog(RouteResult route) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.red,
          size: 40,
        ),
        title: const Text('Unsafe Route'),
        content: const Text(
          'This route passes through a Red Zone (danger area). '
          'It may be faster but is not recommended for safety.\n\n'
          'Are you sure you want to take this route?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Choose Safer Route'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmRoute(route);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Proceed Anyway'),
          ),
        ],
      ),
    );
  }

  void _confirmRoute(RouteResult route) {
    // Start turn-by-turn navigation
    setState(() {
      _isNavigating = true;
      _showRouteSheet = false;
    });
    NavigationService.instance.startNavigation(route);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Navigation started — ${route.durationText} via ${route.mode.displayName} '
          '(${route.distanceText})',
        ),
        backgroundColor: route.isSafe ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _stopNavigation() {
    NavigationService.instance.stopNavigation();
    setState(() => _isNavigating = false);
  }

  // ── Long-press handler ────────────────────────────────────────────────

  Future<void> _handleLongPress(LatLng latLng) async {
    logInfo(_tag, 'Long press at ${latLng.latitude}, ${latLng.longitude}');

    setState(() {
      _longPressPin = latLng;
      _longPressPinName = null;
      _longPressLoading = true;
    });

    // Reverse geocode the location
    final name = await GeocodingService.reverseGeocode(latLng);
    if (!mounted) return;

    setState(() {
      _longPressPinName =
          name ??
          '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
      _longPressLoading = false;
    });
  }

  void _setLongPressAsDestination() {
    if (_longPressPin == null) return;
    final pin = _longPressPin!;
    final name = _longPressPinName ?? 'Dropped Pin';

    setState(() {
      _destination = pin;
      _destinationName = name;
      _searchController.text = name;
      _longPressPin = null;
      _longPressPinName = null;
      _showSearchResults = false;
      _showRouteSheet = false;
      _routeResults = [];
    });
    _mapController.move(pin, 14);
    _fetchRoutes();
  }

  // ═════════════════════════════════════════════════════════════════════
  // Navigation banner widget (shown during turn-by-turn)
  // ═════════════════════════════════════════════════════════════════════

  Widget _buildNavigationBanner() {
    final step = _navState.currentStep;
    final nextStep = _navState.nextStep;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Main instruction card ───────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[700],
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Direction icon
                      Icon(
                        _getManeuverIcon(
                          step?.maneuverType ?? '',
                          step?.maneuverModifier ?? '',
                        ),
                        color: Colors.white,
                        size: 36,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Distance to next turn
                            Text(
                              _navState.nextTurnDistanceText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            // Turn instruction
                            Text(
                              step?.instruction ?? 'Navigating…',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // ── Next maneuver preview ───────────────────────────
                  if (nextStep != null) ...[
                    const Divider(color: Colors.white30, height: 16),
                    Row(
                      children: [
                        Icon(
                          _getManeuverIcon(
                            nextStep.maneuverType,
                            nextStep.maneuverModifier,
                          ),
                          color: Colors.white70,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Then: ${nextStep.instruction}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // ── Progress bar ────────────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _navState.remainingDistanceText,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        _navState.remainingTimeText,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _navState.completedFraction,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.green[600]!,
                      ),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getManeuverIcon(String type, String modifier) {
    if (type == 'arrive') return Icons.flag;
    if (type == 'depart') return Icons.navigation;

    switch (modifier) {
      case 'left':
        return Icons.turn_left;
      case 'sharp left':
        return Icons.turn_sharp_left;
      case 'slight left':
        return Icons.turn_slight_left;
      case 'right':
        return Icons.turn_right;
      case 'sharp right':
        return Icons.turn_sharp_right;
      case 'slight right':
        return Icons.turn_slight_right;
      case 'uturn':
        return Icons.u_turn_left;
      case 'straight':
      default:
        return Icons.straight;
    }
  }

  // ═════════════════════════════════════════════════════════════════════
  // Long-press bottom sheet
  // ═════════════════════════════════════════════════════════════════════

  Widget _buildLongPressSheet() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Pin icon + name
                Row(
                  children: [
                    const Icon(Icons.push_pin, color: Colors.purple, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_longPressLoading)
                            const Text(
                              'Looking up address…',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.grey,
                              ),
                            )
                          else
                            Text(
                              _longPressPinName ?? 'Dropped Pin',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 2),
                          Text(
                            '${_longPressPin!.latitude.toStringAsFixed(5)}, ${_longPressPin!.longitude.toStringAsFixed(5)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() {
                        _longPressPin = null;
                        _longPressPinName = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Set as destination button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _longPressLoading
                        ? null
                        : _setLongPressAsDestination,
                    icon: const Icon(Icons.directions),
                    label: const Text('Set as Destination'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // Navigation route polylines layer
  // ═════════════════════════════════════════════════════════════════════

  Widget _buildNavigationRouteLayer() {
    if (_routeResults.isEmpty) return const SizedBox.shrink();

    final polylines = <Polyline>[];

    // Draw non-selected routes first (grey, thinner).
    for (var i = 0; i < _routeResults.length; i++) {
      if (i == _selectedRouteIndex) continue;
      final route = _routeResults[i];
      polylines.add(
        Polyline(
          points: route.points,
          strokeWidth: 4.0,
          color: Colors.grey.withValues(alpha: 0.45),
        ),
      );
    }

    // Draw the selected route on top (thicker, coloured by safety).
    if (_selectedRouteIndex < _routeResults.length) {
      final selected = _routeResults[_selectedRouteIndex];
      polylines.add(
        Polyline(
          points: selected.points,
          strokeWidth: 6.0,
          color: selected.isSafe
              ? Colors.green.withValues(alpha: 0.85)
              : Colors.red.withValues(alpha: 0.85),
        ),
      );
    }

    return PolylineLayer(polylines: polylines);
  }

  // ═════════════════════════════════════════════════════════════════════
  // Existing layer builders (unchanged logic)
  // ═════════════════════════════════════════════════════════════════════

  // ── Firestore: Extra Danger Zones ─────────────────────────────────────
  Widget _buildFirestoreDangerZonesLayer() {
    if (!_firestoreOverlaysEnabled) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _dangerZonesRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _handleOverlayStreamError(snapshot.error, 'danger_zones');
          return const SizedBox.shrink();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final polygons = <Polygon>[];
        for (final doc in snapshot.data!.docs) {
          try {
            final data = doc.data()! as Map<String, dynamic>;
            final rawPoints = data['points'] as List<dynamic>? ?? [];
            final points = rawPoints.map<LatLng>((p) {
              final m = p as Map<String, dynamic>;
              return LatLng(
                (m['lat'] as num).toDouble(),
                (m['lng'] as num).toDouble(),
              );
            }).toList();

            if (points.length >= 3) {
              polygons.add(
                Polygon(
                  points: points,
                  color: Colors.red.withValues(alpha: 0.25),
                  borderColor: Colors.red,
                  borderStrokeWidth: 2,
                  label: data['name'] as String? ?? '',
                  labelStyle: const TextStyle(
                    color: Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }
          } catch (e) {
            logInfo(_tag, 'Skipping malformed danger_zone doc ${doc.id}: $e');
          }
        }

        logInfo(_tag, 'Firestore danger zones: ${polygons.length}');
        return PolygonLayer(polygons: polygons);
      },
    );
  }

  // ── Firestore: Extra Static Places ────────────────────────────────────
  Widget _buildFirestoreStaticPlacesLayer() {
    if (!_firestoreOverlaysEnabled) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _staticPlacesRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _handleOverlayStreamError(snapshot.error, 'static_places');
          return const SizedBox.shrink();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final markers = <Marker>[];
        for (final doc in snapshot.data!.docs) {
          try {
            final data = doc.data()! as Map<String, dynamic>;
            final lat = (data['lat'] as num).toDouble();
            final lng = (data['lng'] as num).toDouble();
            final name = data['name'] as String? ?? '';
            final type = data['type'] as String? ?? '';

            final Color color;
            final IconData icon;
            switch (type) {
              case 'station':
                color = Colors.blue;
                icon = Icons.shield;
              case 'pink_booth':
                color = Colors.pink;
                icon = Icons.shield;
              default:
                color = Colors.teal;
                icon = Icons.location_on;
            }

            markers.add(
              Marker(
                point: LatLng(lat, lng),
                width: 90,
                height: 62,
                child: _PoiPin(icon: icon, label: name, color: color),
              ),
            );
          } catch (e) {
            logInfo(_tag, 'Skipping malformed static_places doc ${doc.id}: $e');
          }
        }

        logInfo(_tag, 'Firestore static places: ${markers.length}');
        return MarkerLayer(markers: markers);
      },
    );
  }

  // ── RTDB: Patrol Route Polyline ───────────────────────────────────────
  /// Reads the `route` array pushed by the simulator under each patrol node
  /// and draws a blue polyline on the map so the user can see the road path.
  Widget _buildPatrolRouteLayer() {
    return StreamBuilder<DatabaseEvent>(
      stream: _livePatrolsRef.onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const SizedBox.shrink();
        }

        final rawData = snapshot.data!.snapshot.value;
        if (rawData is! Map) return const SizedBox.shrink();

        final polylines = <Polyline>[];

        for (final entry in rawData.entries) {
          if (entry.value is! Map) continue;
          final patrol = entry.value as Map;
          final rawRoute = patrol['route'];
          if (rawRoute is! List || rawRoute.isEmpty) continue;

          try {
            final points = rawRoute
                .map<LatLng>((pt) {
                  if (pt is Map) {
                    return LatLng(
                      (pt['lat'] as num).toDouble(),
                      (pt['lng'] as num).toDouble(),
                    );
                  }
                  return const LatLng(0, 0);
                })
                .where((ll) => ll.latitude != 0 || ll.longitude != 0)
                .toList();

            if (points.length >= 2) {
              polylines.add(
                Polyline(
                  points: points,
                  strokeWidth: 4.0,
                  color: Colors.blue.withValues(alpha: 0.70),
                ),
              );
            }
          } catch (e) {
            logInfo(_tag, 'Error parsing patrol route: $e');
          }
        }

        return PolylineLayer(polylines: polylines);
      },
    );
  }

  // ── RTDB: Live Patrol Markers ─────────────────────────────────────────
  Widget _buildLivePatrolsLayer() {
    return StreamBuilder<DatabaseEvent>(
      stream: _livePatrolsRef.onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          logInfo(_tag, 'live_patrols stream error: ${snapshot.error}');
          return const SizedBox.shrink();
        }

        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const SizedBox.shrink();
        }

        final markers = <Marker>[];
        final rawData = snapshot.data!.snapshot.value;

        if (rawData is! Map) return const SizedBox.shrink();

        for (final entry in rawData.entries) {
          try {
            if (entry.value is! Map) continue;
            final patrol = entry.value as Map;
            final patrolId = entry.key.toString();
            final lat = (patrol['lat'] as num).toDouble();
            final lng = (patrol['lng'] as num).toDouble();
            final status = patrol['status']?.toString() ?? 'unknown';

            if (status != 'active') continue;

            final currentPosition = LatLng(lat, lng);
            final previousPosition = _previousPatrolPositions[patrolId];
            var bearing = _patrolBearings[patrolId] ?? 0.0;

            if (previousPosition != null &&
                _isSignificantMovement(previousPosition, currentPosition)) {
              bearing = _bearing(previousPosition, currentPosition);
              _patrolBearings[patrolId] = bearing;
            }
            _previousPatrolPositions[patrolId] = currentPosition;

            markers.add(
              Marker(
                point: currentPosition,
                width: 32,
                height: 32,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Transform.rotate(
                        angle: bearing - (math.pi / 2),
                        child: Image.asset(
                          'assets/map/policecar.png',
                          width: 32,
                          height: 32,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 30,
                      left: -28,
                      right: -28,
                      child: Center(
                        child: Text(
                          _formatPatrolLabel(patrolId),
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(blurRadius: 2)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          } catch (e) {
            logInfo(_tag, 'Skipping malformed patrol ${entry.key}: $e');
          }
        }

        return MarkerLayer(markers: markers);
      },
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // Helpers
  // ═════════════════════════════════════════════════════════════════════

  static String _formatPatrolLabel(String key) {
    return key
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static bool _isSignificantMovement(LatLng from, LatLng to) {
    return (from.latitude - to.latitude).abs() > 0.000001 ||
        (from.longitude - to.longitude).abs() > 0.000001;
  }

  static double _bearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * (math.pi / 180.0);
    final lat2 = to.latitude * (math.pi / 180.0);
    final dLon = (to.longitude - from.longitude) * (math.pi / 180.0);
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return math.atan2(y, x);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper widgets
// ═══════════════════════════════════════════════════════════════════════════

/// Generic safe-place POI pin with configurable [color].
class _PoiPin extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _PoiPin({
    required this.icon,
    required this.label,
    this.color = Colors.teal,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: Colors.white,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(blurRadius: 2)],
          ),
        ),
      ],
    );
  }
}
