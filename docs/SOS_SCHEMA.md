# Aanchal SOS Firestore Schema (Refactored)

## 1) users/{uid}
Fields:
- uid: string
- name: string
- email: string
- aanchalNumber: string
- role: "user" | "contact" | "admin"
- online: boolean
- lastSeen: timestamp
- lastSeenAt: timestamp
- phone: string (optional, normalized)
- fcmToken: string (optional)

Subcollection:
- emergency_contacts/{contactId}
  - id: string
  - name: string
  - phone: string (normalized)
  - relationship: string
  - createdAt: string
  - addedAt: timestamp

## 2) sos_events/{eventId}
Purpose:
- Receiver wake/alert trigger stream

Fields:
- eventId: string (UUID)
- sessionId: string (UUID)
- fromUserId: string
- fromName: string
- lat: string
- lng: string
- mapsLink: string
- targetUserIds: string[]
- createdAt: timestamp
- expiresAt: timestamp

## 3) sos_sessions/{sessionId}
Purpose:
- Active SOS lifecycle + live tracking + evidence access control

Fields:
- userId: string
- fromName: string
- startTime: timestamp
- active: boolean
- contacts: string[]
- mapsLink: string
- lat: string
- lng: string
- lastLocationAt: timestamp (optional)
- endedAt: timestamp (optional)

Evidence access fields:
- evidenceAccessCodeHash: string (sha256(code + salt))
- codeExpiry: timestamp
- codeUsed: boolean
- codeUsedAt: timestamp (optional)

Subcollection:
- locations/{timestampId}
  - lat: string
  - lng: string
  - timestamp: timestamp

## Notes
- Client never writes directly to sos_events/sos_sessions.
- Backend is source of truth for session creation, location updates, and code verification.
- Receivers subscribe to sos_sessions/{sessionId}/locations for map updates every ~10 seconds.
