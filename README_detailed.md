# Aanchal (Flutter) — Detailed README

> Android-only Flutter rebuild of the original Aanchal concept.

---

## 1. Project Overview

Aanchal is a women’s safety companion app for Android built in Flutter. The project is structured as a clean, modular foundation with feature stubs and demo-mode behavior that can later be wired to real backends.

Core goals:

- Fast access to SOS / Panic Mode
- Location capture + share (WhatsApp deep link)
- Maps-based “safe map” view with demo danger-zones + POIs
- Community safety feed (mock)
- Safety Hub (helplines + tips)
- Native Android hooks via Kotlin `MethodChannel` for future Nearby Connections

Scope:

- Android only (no iOS)
- Flutter + Dart (Material 3)
- No Firebase wired yet (intentionally stubbed)

---

## 2. Feature Summary (Current Implementation)

### 2.1 Home Dashboard
- Central landing page with large pulsing **SOS** button
- Quick actions: Panic Mode, Safe Map, Community, Safety Hub
- Debug Panel toggle (bug icon)

### 2.2 Panic Mode (SOS Screen)
- Long-press SOS activation
- Deactivate control
- Persona selector for “fake call” (Parent / Dispatcher / Helpline)
- Quick actions row (Fake Call, WhatsApp stub, Alarm stub)

### 2.3 Fake Call Overlay
- Full-screen incoming call simulation
- Accept / Decline, and call timer when answered

### 2.4 Safe Map
- Google Maps view
- Demo danger-zone polygon overlay
- Demo safe POI markers
- `myLocationEnabled` + location button

### 2.5 Community Feed
- Static feed cards with mock safety alerts
- “Report Unsafe Zone” button stub

### 2.6 Safety Hub (Learning)
- Emergency helplines:
  - 181 (Women Helpline)
  - 100 (Police)
  - 108 (Ambulance)
  - NCW sample number
- Safety tips list
- Self-defense resource link (YouTube search)

### 2.7 Debug Panel
- Runtime feature flags toggle UI
- Mock P2P discovery button (simulated peers)

---

## 3. Tech Stack

| Area | Choice |
|------|--------|
| Framework | Flutter 3.x (stable) |
| Language | Dart 3.x |
| State management | Riverpod (foundation ready; not heavily used yet) |
| Maps | `google_maps_flutter` |
| Location | `geolocator` |
| Permissions | `permission_handler` |
| Background | `flutter_background_service`, `workmanager` |
| Storage | `shared_preferences` |
| Deep links | `url_launcher` |
| Logging | `logger` |
| Native | Kotlin (MethodChannel placeholder) |

---

## 4. Architecture & Directory Structure

```
lib/
  main.dart
  core/
    feature_flags.dart
    logger.dart
  services/
    sos_service.dart
    location_service.dart
    whatsapp_service.dart
    p2p_stub_service.dart
  features/
    home/home_screen.dart
    sos/sos_screen.dart
    map/map_screen.dart
    community/community_screen.dart
    learning/learning_screen.dart
  ui/
    app_theme.dart
    sos_button.dart
    debug_overlay.dart
    fake_call_overlay.dart

android/
  app/src/main/AndroidManifest.xml
  app/src/main/kotlin/com/aanchal/aanchal/MainActivity.kt
```

Layering rules (intentional):

- `core/` → feature flags + logging primitives
- `services/` → app capabilities (location, SOS orchestration, sharing, mock P2P)
- `features/` → screens only
- `ui/` → reusable widgets & theme

---

## 5. Setup (Windows)

### 5.1 Install prerequisites
- Flutter stable
- Android Studio + Android SDK
- AVD Emulator (optional)

### 5.2 Install packages

```powershell
cd "D:\My projects\Aanchal"
flutter pub get
```

### 5.3 Google Maps API Key
Edit `android/app/src/main/AndroidManifest.xml` and replace:

- `YOUR_GOOGLE_MAPS_API_KEY_HERE`

with a real key.

---

## 6. Running the App

### 6.1 Run on emulator

```powershell
flutter emulators
flutter emulators --launch Medium_Phone
flutter run
```

### 6.2 Run on a physical device via USB

1. Enable **Developer options**
2. Enable **USB debugging**
3. Plug device into the laptop and accept the RSA prompt

Verify:

```powershell
adb devices -l
flutter devices
```

---

## 7. ADB Over Wi‑Fi (TCP/IP)

You asked specifically for **ADB TCP/IP** so you can deploy wirelessly later on the same network.

### 7.1 One-time prerequisites
- Phone and laptop on the same Wi‑Fi network
- USB debugging enabled
- USB cable connected initially (for the `adb tcpip` switch)

### 7.2 Enable TCP/IP mode + connect

```powershell
# Confirm USB device exists
adb devices -l

# Find phone Wi‑Fi IP (wlan0)
adb shell ip route

# Switch ADB to TCP/IP on port 5555
adb tcpip 5555

# Connect over Wi‑Fi (replace with your IP)
adb connect 10.9.49.221:5555

# Confirm you now see both entries
adb devices -l
```

After that, you can unplug the USB cable and keep using the Wi‑Fi entry.

### 7.3 Reconnect later (same Wi‑Fi)
Your phone’s IP may change after reboot/router reconnect. To reconnect:

```powershell
adb connect <PHONE_WIFI_IP>:5555
adb devices -l
```

### 7.4 Disable TCP/IP mode (back to USB)
To revert (USB cable required):

```powershell
adb usb
```

### 7.5 Android 11+ alternative (Wireless debugging pairing)
If TCP/IP ever fails on newer Android versions, use:

- Developer options → **Wireless debugging** → **Pair device with pairing code**

Then:

```powershell
adb pair <PHONE_IP>:<PAIR_PORT>
adb connect <PHONE_IP>:<CONNECT_PORT>
```

---

## 8. Permissions

Declared in `android/app/src/main/AndroidManifest.xml` (includes):

- Location: fine/coarse/background
- Contacts: read
- Bluetooth scan/advertise/connect
- Nearby Wi‑Fi devices
- Post notifications
- Foreground service (+ location type)
- Boot completed + wake lock

Note: some permissions are future-facing for upcoming P2P/background features.

---

## 9. Native Android Channel (Kotlin)

File: `android/app/src/main/kotlin/com/aanchal/aanchal/MainActivity.kt`

A stub `MethodChannel` is registered:

- Channel: `com.aanchal/nearby`
- Methods:
  - `startDiscovery`
  - `stopDiscovery`
  - `broadcastSOS` (accepts `payload`)

Currently returns stub success strings. This is the intended integration point for Google Nearby Connections.

---

## 10. Quality Checks (Deep Pass)

These were run and passed:

- `flutter doctor -v` (only issue: Visual Studio not installed, which is OK for Android-only)
- `flutter analyze` → no issues
- `flutter test` → passed

Dependency update check:

- `flutter pub outdated` shows some dependencies have newer major versions available (e.g. Riverpod 3.x, Geolocator 14.x, permission_handler 12.x). These were **not** automatically upgraded to avoid breaking changes.

Security scanning:

- The Dart CLI in this environment does not provide `dart pub audit`.
- A `.github/dependabot.yml` was added so GitHub can surface vulnerable dependency updates automatically.

---

## 11. Troubleshooting

### ADB device not showing
- Try another cable/port
- Set USB mode to **File transfer**
- Re-authorize USB debugging

Commands:

```powershell
adb kill-server
adb start-server
adb devices -l
```

### Maps not rendering
- Ensure a valid Google Maps API key is configured
- Ensure Google Play Services are present/updated on the device/emulator

---

## 12. Roadmap (Suggested Next Steps)

- Replace mock P2P with real Nearby Connections via Kotlin channel
- Add real SOS payload format + encryption/signing for relay
- Add contact management (trusted contacts)
- Add background periodic SOS re-broadcast + location updates
- Add community report persistence (Firestore or custom API)
- Improve accessibility (TalkBack, text scale, high contrast)

---

## 13. Quick Start Commands

```powershell
cd "D:\My projects\Aanchal"
flutter pub get
flutter analyze
flutter test
flutter run
```
