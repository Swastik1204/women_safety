// Aanchal — App Configuration
//
// Central configuration for the Aanchal app.
// Contains hardcoded values, API endpoints, and feature toggles.

class AppConfig {
  AppConfig._();

  // ─── Map Tiles ─────────────────────────────────────────────────────
  /// Override in builds with:
  /// --dart-define=AANCHAL_MAP_TILE_URL_TEMPLATE=https://your.tiles/{z}/{x}/{y}.png
  static const String mapTileUrlTemplate = String.fromEnvironment(
    'AANCHAL_MAP_TILE_URL_TEMPLATE',
    defaultValue: 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
  );

  static const List<String> mapTileSubdomains = ['a', 'b', 'c'];

  static const String mapTileAttribution = String.fromEnvironment(
    'AANCHAL_MAP_TILE_ATTRIBUTION',
    defaultValue: 'OpenStreetMap contributors',
  );

  // ─── Caller Identity ────────────────────────────────────────────────
  static const String emergencyCallerNumber = '+918918586567';

  // ─── Backend API ────────────────────────────────────────────────────
  /// Base URL for the FastAPI backend deployed on Render (free tier).
  /// Override in debug/dev builds with:
  /// --dart-define=AANCHAL_BACKEND_BASE_URL=http://HOST_IP:8000
  static const String backendBaseUrl = String.fromEnvironment(
    'AANCHAL_BACKEND_BASE_URL',
    defaultValue: 'https://aanchal-backend.onrender.com',
  );

  /// WebSocket base URL for signaling.
  static const String wsBaseUrl = 'wss://aanchal-backend.onrender.com';

  static String wsEndpoint(String userId) => '$wsBaseUrl/ws/$userId';

  // ─── REST Endpoints ─────────────────────────────────────────────────
  static const String apiRegisterDeviceToken =
      '$backendBaseUrl/api/device/register_token';

  /// SOS endpoint — sends FCM push to all emergency contacts.
  static const String apiSos = '$backendBaseUrl/api/sos';
  static const String apiSosLocation = '$backendBaseUrl/api/sos/location';
  static const String apiSosSessionStop = '$backendBaseUrl/api/sos/session/stop';
  static const String apiEvidenceVerify = '$backendBaseUrl/api/sos/evidence/verify';

    // ─── Calling Endpoints ──────────────────────────────────────────────
    static const String apiAcceptCall = '$backendBaseUrl/api/call/accept';
    static const String apiRejectCall = '$backendBaseUrl/api/call/reject';
    static const String apiEndCall = '$backendBaseUrl/api/call/end';
    static String apiTestPush(String userId) => '$backendBaseUrl/api/test_push/$userId';
    static String apiTestCall(String callerId, String calleeId) =>
      '$backendBaseUrl/api/test_call/$callerId/$calleeId';
    static String apiCallHistory(String userId) => '$backendBaseUrl/api/call/history/$userId';
    static String apiMissedCalls(String userId) => '$backendBaseUrl/api/call/missed/$userId';
    static const String apiCallMetrics = '$backendBaseUrl/api/call/metrics';
    static String apiCallMetricsById(String callId) => '$backendBaseUrl/api/call/metrics/$callId';
    static String apiCallMetricsSummaryById(String callId) =>
      '$backendBaseUrl/api/call/metrics_summary/$callId';
    static String apiCallState(String callId) => '$backendBaseUrl/api/call/state/$callId';

  // ─── Timeouts ───────────────────────────────────────────────────────
  /// HTTP request timeout for API calls.
  static const Duration apiTimeout = Duration(seconds: 15);

  /// Retry delay between failed API attempts.
  static const Duration retryDelay = Duration(seconds: 3);

  /// Maximum number of API retry attempts.
  static const int maxRetries = 2;

  // ─── Firebase Sync ──────────────────────────────────────────────────
  /// Firebase Realtime Database base URL (free Spark plan).
  /// Update this after creating your Firebase project.
  static const String firebaseDbUrl =
      'https://aanchal-d17d5-default-rtdb.asia-southeast1.firebasedatabase.app';

  /// Interval for background Firebase sync (in hours).
  static const int firebaseSyncIntervalHours = 12;

  // ─── Default Persona ────────────────────────────────────────────────
  static const String defaultPersona = 'friend';

  // ─── App Meta ───────────────────────────────────────────────────────
  static const String appName = 'Aanchal';
  static const String appVersion = '1.0.0';
}
