# Aanchal — Women's Safety Companion

> Flutter · Android-only · Offline-first emergency toolkit

---

## What is Aanchal?

Aanchal is a personal safety app built for women in India. It combines one-tap SOS alerts, real-time safe-route mapping, peer-to-peer proximity broadcasting, and AI-powered fake calls into a single, lightweight Android application.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter 3.x (stable) |
| Language | Dart 3.x |
| State | Riverpod |
| Maps | Google Maps Flutter |
| Location | Geolocator |
| Permissions | permission_handler |
| Background | flutter_background_service, workmanager |
| Animation | Lottie |
| Storage | shared_preferences |
| Logging | logger |
| Deep links | url_launcher |
| Native | Kotlin (MethodChannel for Nearby Connections) |

---

## Project Structure

```
lib/
├── main.dart                       # Entry point, MaterialApp + bottom nav
├── core/
│   ├── feature_flags.dart          # Runtime feature toggles
│   └── logger.dart                 # Structured logging helpers
├── services/
│   ├── sos_service.dart            # SOS orchestrator
│   ├── location_service.dart       # Geolocator wrapper
│   ├── whatsapp_service.dart       # WhatsApp deep-link emergency
│   └── p2p_stub_service.dart       # Mock P2P discovery
├── features/
│   ├── home/home_screen.dart       # Dashboard + quick-action grid
│   ├── sos/sos_screen.dart         # Panic mode + persona selector
│   ├── map/map_screen.dart         # Google Maps + danger zones
│   ├── community/community_screen.dart  # Safety feed
│   └── learning/learning_screen.dart    # Helplines + safety tips
└── ui/
    ├── sos_button.dart             # Animated pulsing SOS button
    ├── debug_overlay.dart          # Feature flag panel + mock P2P
    └── fake_call_overlay.dart      # Full-screen fake incoming call

android/
└── app/src/main/kotlin/.../
    └── MainActivity.kt             # Nearby Connections stub channel
```

---

## Getting Started

```bash
# 1  Clone
git clone https://github.com/Swastik1204/Aanchal.git
cd Aanchal

# 2  Install dependencies
flutter pub get

# 3  (Optional) Add your Google Maps API key
#    android/app/src/main/AndroidManifest.xml → replace YOUR_GOOGLE_MAPS_API_KEY_HERE

# 4  Add local runtime secrets (not committed)
#    Copy dart-defines.example.json -> etc/secrets/dart-defines.json
#    and fill TURN + emergency caller number values.

# 5  Run on a connected device or emulator
flutter run --dart-define-from-file=etc/secrets/dart-defines.json
```

**Requirements:** Flutter 3.x stable, Android SDK 34+, JDK 17+.

For full technical documentation (architecture, permissions, native channel, and ADB-over-Wi‑Fi steps), see [README_detailed.md](README_detailed.md).

---

## Screens

| # | Screen | Description |
|---|--------|------------|
| 1 | **Home** | Central dashboard with SOS button and four quick-action cards |
| 2 | **SOS / Panic** | Long-press activation, persona selector, fake call trigger |
| 3 | **Safe Map** | Google Maps with demo danger polygon and POI markers |
| 4 | **Community** | Static safety feed with incident cards |
| 5 | **Safety Hub** | Emergency helplines (181, 100, 108) and safety tips |

---

## Feature Flags

Controlled at runtime via `FeatureFlags` (see `core/feature_flags.dart`):

| Flag | Default | Purpose |
|------|---------|---------|
| `enableSOS` | `true` | Master toggle for SOS system |
| `enableNearbyP2P` | `false` | P2P discovery (stub) |
| `enableAICall` | `true` | AI fake-call feature |
| `enableSafeRoutes` | `true` | Safe route overlays |
| `enableWhatsApp` | `true` | WhatsApp emergency share |
| `enableDemoMode` | `true` | Demo/mock data |

Toggle any flag from the Debug Panel (tap the bug icon on the Home screen).

---

## Native Channel

A Kotlin `MethodChannel` at `com.aanchal/nearby` exposes three stubs:

- `startDiscovery` — placeholder for Google Nearby Connections
- `stopDiscovery` — stop scanning
- `broadcastSOS` — send SOS payload to nearby devices

These are currently no-ops that return success strings. Wire real Nearby Connections API calls inside `MainActivity.kt`.

---

## Permissions

Declared in `AndroidManifest.xml`:

- Internet, Fine/Coarse/Background Location
- Bluetooth Scan/Advertise/Connect, Nearby WiFi Devices
- Post Notifications, Vibrate
- Foreground Service (+ Location type)
- Receive Boot Completed, Wake Lock

---

## Roadmap

- [ ] Firebase Auth + Firestore integration
- [ ] Real Nearby Connections P2P
- [ ] AI voice-call engine (on-device TTS)
- [ ] Background SOS with periodic location push
- [ ] Community reporting with geo-tagged incidents
- [ ] Accessibility audit (TalkBack, high-contrast)

---

## License

Private — all rights reserved.
