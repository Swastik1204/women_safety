// Aanchal — Feature Flags
//
// Runtime feature toggle system.
// All flags default to their values here and can be toggled via the Debug Overlay.

class FeatureFlags {
  static final Map<String, bool> _flags = {
    'enableSOS': true,
    'enableNearbyP2P': false,
    'enableWebRTCCall': true,
    'enableSafeRoutes': true,
    'enableDemoMode': false,
  };

  static bool isEnabled(String flag) => _flags[flag] ?? false;

  static void set(String flag, bool value) {
    _flags[flag] = value;
  }

  static void toggle(String flag) {
    _flags[flag] = !(_flags[flag] ?? false);
  }

  static Map<String, bool> getAll() => Map.unmodifiable(_flags);
}
