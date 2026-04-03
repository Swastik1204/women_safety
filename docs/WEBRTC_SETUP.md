# Aanchal — WebRTC In-App Call Setup

> Last updated: February 2026  
> Status: **Functional (STUN-only; TURN not yet configured)**

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [How Signaling Works](#2-how-signaling-works)
3. [File Map](#3-file-map)
4. [Deploy the Render Backend](#4-deploy-the-render-backend)
5. [Firestore Security Rules](#5-firestore-security-rules)
6. [Testing Calls Between Two Phones](#6-testing-calls-between-two-phones)
7. [Known Limitations](#7-known-limitations)
8. [Roadmap](#8-roadmap)

---

## 1. Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Aanchal P2P Call                             │
│                                                                      │
│   Phone A (Caller)            Render Server           Phone B (Callee)│
│   ───────────────             ─────────────           ────────────── │
│   WebRTCCallService  ←──WS──▶ FastAPI /ws/{id} ←──WS──▶ WebRTCCallService│
│                                   │                                  │
│                          Relays offers / answers                     │
│                          ICE candidates                              │
│                                                                      │
│   After signaling completes, audio flows DIRECTLY between phones     │
│   via UDP (STUN-discovered public IP).  The server is NOT in the     │
│   media path.                                                        │
└──────────────────────────────────────────────────────────────────────┘
```

**Components:**

| Layer | Technology | Location |
|-------|-----------|---------|
| Signaling server | FastAPI + WebSocket | `backend/main.py` → Render |
| Client signaling | `dart:io WebSocket` | `lib/services/webrtc_call_service.dart` |
| P2P audio | `flutter_webrtc` (libwebrtc) | Same service |
| ICE / NAT traversal | Google STUN `stun.l.google.com:19302` | Configured in service |
| User registry | Firebase Firestore `users/` | `lib/services/auth_service.dart` |

---

## 2. How Signaling Works

Signaling is the out-of-band exchange of session metadata before audio can flow. Aanchal uses a WebSocket relay on Render.

### Message Envelope

Every message sent over the WebSocket has this shape:

```json
{
  "type":       "offer | answer | ice | hang_up | error",
  "from":       "<sender-uid>",          // stamped by server, cannot be spoofed
  "to":         "<target-uid>",
  "sdp":        "<sdp-string>",          // offer / answer
  "sdpType":    "offer | answer",        // offer / answer
  "candidate":  { "candidate": "...", "sdpMid": "...", "sdpMLineIndex": 0 },
  "callerName": "<display-name>"         // offer only
}
```

### Call Lifecycle

```
Caller                     Server                    Callee
  │                           │                         │
  │──── connect /ws/{A} ─────▶│                         │
  │                           │◀─── connect /ws/{B} ────│
  │                           │                         │
  │  getUserMedia (mic)        │                         │
  │  createOffer()            │                         │
  │──── {type:"offer", to:B} ▶│──── forward to B ──────▶│
  │                           │                         │  setRemoteDesc
  │                           │                         │  createAnswer()
  │◀─── {type:"answer"} ──────│◀─── {type:"answer"} ────│
  │  setRemoteDesc            │                         │
  │                           │                         │
  │←── ICE candidates ────────│────── ICE candidates ───▶│
  │                  (both directions, interleaved)      │
  │                           │                         │
  │══════════════ Direct UDP audio stream ══════════════│
  │                           │                         │
  │──── {type:"hang_up"} ────▶│──── forward to B ──────▶│
  │  close PC                 │                         │  close PC
```

### WebSocket Reconnect

The service automatically reconnects to the signaling server after a 5-second delay if the connection drops. The user stays logged in to Firebase unaffected.

---

## 3. File Map

```
lib/
├── services/
│   ├── webrtc_call_service.dart   # Core WebRTC + WS signaling singleton
│   └── auth_service.dart          # UserProfile model, Firestore profile sync
│
├── features/
│   ├── call/
│   │   └── call_screen.dart       # Full-screen call UI (incoming + outgoing)
│   ├── community/
│   │   └── user_discovery_screen.dart  # List users; tap to call
│   └── home/
│       └── home_screen.dart       # "Test In-App Call" banner -> UserDiscovery
│
└── core/
    └── app_config.dart            # wsBaseUrl / wsEndpoint(userId)

backend/
└── main.py                        # FastAPI WebSocket signaling relay

firestore.rules                    # Firestore security rules (deploy separately)
```

---

## 4. Deploy the Render Backend

### Prerequisites

- A free [Render](https://render.com) account
- The `backend/` folder pushed to your Git repo

### Steps

1. **Create a new Web Service** on Render → connect your GitHub repo.

2. **Configure the service:**

   | Setting | Value |
   |---------|-------|
   | Root Directory | `backend` |
   | Build Command | `pip install -r requirements.txt` |
   | Start Command | `uvicorn main:app --host 0.0.0.0 --port $PORT` |
   | Instance Type | Free (or Starter for always-on) |

3. **Environment variables:** none required for basic signaling.

4. **After deploy**, your service URL will be:
   ```
   https://aanchal-backend.onrender.com
   ```

5. **Update `lib/core/app_config.dart`** if the URL changes:
   ```dart
   static const String wsBaseUrl = 'wss://YOUR-SERVICE.onrender.com';
   ```

6. **Verify the backend:**
   ```
   GET https://aanchal-backend.onrender.com/health
   ```
   Expected response:
   ```json
   { "status": "ok", "connected_users": 0, "timestamp": "2026-02-22T..." }
   ```

### Keep-Alive (Free Tier)

Render free services spin down after 15 minutes of inactivity. Add a UptimeRobot monitor pinging `/health` every 5 minutes to keep it warm, or upgrade to a paid plan.

---

## 5. Firestore Security Rules

The rules file is at `firestore.rules` in the project root.

### Deploy

```bash
# Install Firebase CLI if needed
npm install -g firebase-tools

firebase login
firebase deploy --only firestore:rules
```

### Current Dev Rules Summary

| Collection | Read | Write |
|-----------|------|-------|
| `users/{userId}` | Any authenticated user | Owner only (`auth.uid == userId`) |
| Everything else | ❌ Denied | ❌ Denied |

### Online Presence

The `online` field in each user's Firestore document is set/unset by the app at login/logout. Enable Firestore offline persistence to prevent stale `online: true` entries on crash.

---

## 6. Testing Calls Between Two Phones

### Setup

1. Install the Aanchal app on **two physical Android phones** (WebRTC does not work on the iOS simulator or the Android emulator for real audio).
2. Both phones must be on the same Wi-Fi **or** have cellular data (STUN handles most NAT scenarios).

### Test Flow

**Phone A (Caller):**
1. Launch Aanchal → Log in (or register) as **User A**.
2. Tap **"Test In-App Call"** banner on the Home screen.
3. Wait for Phone B to appear in the user list (needs to be online).
4. Tap the **Call** button next to User B's name.

**Phone B (Callee):**
1. Launch Aanchal → Log in as **User B** (on the same screen or navigate to any screen — the incoming call overlay will appear automatically).
2. Accept the incoming call on the full-screen dialog.

**Expected result:** Both phones should hear each other's microphone audio within 2–5 seconds of accepting.

### Verifying Signaling

Watch the Render service logs (Render dashboard → Logs tab):

```
INFO:     [+] uid_A connected  (total: 1)
INFO:     [+] uid_B connected  (total: 2)
INFO:     [offer] uid_A ──▶ uid_B
INFO:     [answer] uid_B ──▶ uid_A
INFO:     [ice] uid_A ──▶ uid_B
INFO:     [ice] uid_B ──▶ uid_A
```

### Mute / End Call

- **Mute** button toggles the local microphone track.
- **End call** button sends a `hang_up` message and tears down the `RTCPeerConnection` on both sides.

---

## 7. Known Limitations

| Limitation | Impact | Fix |
|-----------|--------|-----|
| **No TURN server** | Calls fail when both devices are behind symmetric NAT (corporate/campus Wi-Fi, some mobile carriers). Works reliably on home Wi-Fi + cellular. | Add a TURN server (Twilio TURN, Metered TURN, or self-hosted coturn). |
| **Render free tier sleeps** | First WS connection after 15 min idle takes ~10–30 s to wake up. | UptimeRobot ping or upgrade to Render Starter ($7/mo). |
| **Audio only** | No video (by design — Aanchal is a safety calling app). | N/A |
| **No call recording / logging** | Calls are fully ephemeral. | Add a Firestore `calls/` subcollection with server timestamps if audit logs are needed. |
| **No end-to-end encryption of signaling** | SDP is sent in plaintext over WSS (TLS in transit, but the server can read it). The media stream itself is DTLS-SRTP encrypted by WebRTC spec. | For extra privacy, encrypt the SDP payload before sending to the relay. |
| **Single concurrent call** | `WebRTCCallService` is a singleton — only one active `RTCPeerConnection` at a time. | Extend service to a map of active connections keyed by callId. |
| **iOS not tested** | flutter_webrtc supports iOS; `NSMicrophoneUsageDescription` needs to be added to `ios/Runner/Info.plist`. | Add the plist key and test. |

---

## 8. Roadmap

- [ ] **TURN server integration** for reliable calling across all network types
- [ ] **Incoming call notification** (push notification when app is backgrounded)
- [ ] **iOS microphone permission** (`NSMicrophoneUsageDescription` in Info.plist)
- [ ] **Call history** stored in Firestore `calls/` collection
- [ ] **Online presence via Firestore onDisconnect** for accurate status
- [ ] **Group call** (replace 1:1 RTCPeerConnection with an SFU or mesh)
- [ ] **End-to-end encrypted signaling**
