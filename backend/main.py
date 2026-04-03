from __future__ import annotations

import asyncio
import hashlib
from contextlib import contextmanager
import logging
import os
import re
import secrets
import sqlite3
import threading
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, Request, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

# Optional Firebase Admin (for FCM push)
try:
    import firebase_admin as firebase_admin_module
    from firebase_admin import auth as fb_auth
    from firebase_admin import credentials as fb_credentials
    from firebase_admin import firestore as fb_firestore
    from firebase_admin import messaging as fb_messaging
except Exception:
    firebase_admin_module = None
    fb_auth = None
    fb_credentials = None
    fb_firestore = None
    fb_messaging = None


def _is_stale_token_error(err: Exception) -> bool:
    text = str(err).lower()
    indicators = (
        "registration token is not a valid fcm registration token",
        "registration-token-not-registered",
        "requested entity was not found",
        "unregistered",
        "notregistered",
        "invalid registration token",
    )
    return any(i in text for i in indicators)


def normalize_phone(phone: str) -> str:
    """Normalize any Indian phone format to +91XXXXXXXXXX.
    Handles: +919876543210, 919876543210, 9876543210, 09876543210
    """
    if not phone:
        return ""

    cleaned = re.sub(r"[\s\-\(\)]", "", str(phone)).strip()

    # Already correct E.164 with +91
    if cleaned.startswith("+91") and len(cleaned) == 13:
        return cleaned

    # International number that is not Indian — keep as-is
    if cleaned.startswith("+") and not cleaned.startswith("+91"):
        return cleaned

    # 91XXXXXXXXXX without the +
    if cleaned.startswith("91") and len(cleaned) == 12:
        return f"+{cleaned}"

    # Leading 0 (landline style)
    if cleaned.startswith("0") and len(cleaned) == 11:
        cleaned = cleaned[1:]

    # 10-digit Indian mobile starting with 6-9
    if len(cleaned) == 10 and re.match(r"^[6-9]\d{9}$", cleaned):
        return f"+91{cleaned}"

    # Return cleaned as-is if no rule matched
    return cleaned


def _normalize_phone(phone: str) -> str:
    return normalize_phone(phone)


class AuthContext(BaseModel):
    uid: str
    role: str = "user"


bearer_scheme = HTTPBearer(auto_error=False)


def _hash_evidence_code(code: str) -> str:
    return hashlib.sha256(f"{code}:{EVIDENCE_CODE_SALT}".encode("utf-8")).hexdigest()


def _enforce_sos_throttle(uid: str):
    now = time.time()

    with _sos_rate_guard:
        last_trigger_at = _sos_last_trigger_at.get(uid)
        if last_trigger_at is not None:
            elapsed = now - last_trigger_at
            if elapsed < SOS_USER_COOLDOWN_SECONDS:
                remaining = int(SOS_USER_COOLDOWN_SECONDS - elapsed)
                raise HTTPException(
                    status_code=429,
                    detail=f"SOS cooldown active. Try again in {remaining}s",
                )

        history = _sos_request_times.get(uid, [])
        history = [t for t in history if now - t <= SOS_RATE_WINDOW_SECONDS]
        if len(history) >= SOS_RATE_LIMIT:
            raise HTTPException(
                status_code=429,
                detail="Too many SOS requests. Please retry shortly.",
            )

        history.append(now)
        _sos_request_times[uid] = history
        _sos_last_trigger_at[uid] = now


def _require_uid_match(body_user_id: str, auth: AuthContext):
    if body_user_id != auth.uid:
        raise HTTPException(
            status_code=403,
            detail="Authenticated UID does not match request userId",
        )


def _require_role(auth: AuthContext, allowed_roles: set[str]):
    if auth.role not in allowed_roles:
        raise HTTPException(status_code=403, detail="Insufficient role")


async def _resolve_role(uid: str, decoded_token: dict) -> str:
    role = str(decoded_token.get("role", "")).strip().lower()
    if role:
        return role

    db_client = db
    if db_client is not None:
        try:
            user_doc = await asyncio.to_thread(
                lambda: db_client.collection("users").document(uid).get()
            )
            if user_doc.exists:
                user_data = user_doc.to_dict() or {}
                role_val = str(user_data.get("role", "")).strip().lower()
                if role_val:
                    return role_val
        except Exception as exc:
            logger.warning("Role lookup failed for uid=%s err=%s", uid, exc)

    return "user"


async def get_auth_context(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> AuthContext:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="Missing bearer token")

    if fb_auth is None:
        raise HTTPException(status_code=503, detail="Auth verification unavailable")

    try:
        decoded = await asyncio.to_thread(fb_auth.verify_id_token, credentials.credentials)
    except Exception as exc:
        raise HTTPException(status_code=401, detail=f"Invalid auth token: {exc}") from exc

    uid = str(decoded.get("uid", "")).strip()
    if not uid:
        raise HTTPException(status_code=401, detail="Token missing uid")

    role = await _resolve_role(uid, decoded)
    return AuthContext(uid=uid, role=role)


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("aanchal-backend")

app = FastAPI(
    title="Aanchal Backend",
    description="Offline-first SOS backend (FCM + token registry)",
    version="5.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_PATH = os.getenv("AANCHAL_DB_PATH", os.path.join(os.path.dirname(__file__), "aanchal.db"))
db = None

# In-memory abuse controls for SOS trigger. For horizontal scale, move to Redis.
SOS_RATE_LIMIT = int(os.getenv("SOS_RATE_LIMIT", "5"))
SOS_RATE_WINDOW_SECONDS = int(os.getenv("SOS_RATE_WINDOW_SECONDS", "60"))
SOS_USER_COOLDOWN_SECONDS = int(os.getenv("SOS_USER_COOLDOWN_SECONDS", "20"))
EVIDENCE_CODE_TTL_MINUTES = int(os.getenv("EVIDENCE_CODE_TTL_MINUTES", "10"))
EVIDENCE_CODE_SALT = os.getenv("EVIDENCE_CODE_SALT", "aanchal-evidence-salt")

_sos_rate_guard = threading.Lock()
_sos_request_times: dict[str, list[float]] = {}
_sos_last_trigger_at: dict[str, float] = {}


@contextmanager
def get_db():
    conn = sqlite3.connect(DB_PATH)
    try:
        yield conn
    finally:
        conn.close()


class Storage:
    def __init__(self, db_path: str):
        self._conn = sqlite3.connect(db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        self._init_schema()

    def _init_schema(self):
        with self._lock:
            self._conn.execute(
                """
                CREATE TABLE IF NOT EXISTS device_tokens (
                    user_id TEXT PRIMARY KEY,
                    fcm_token TEXT NOT NULL,
                    phone TEXT,
                    platform TEXT NOT NULL DEFAULT 'android',
                    updated_at REAL NOT NULL,
                    last_seen TEXT DEFAULT (datetime('now'))
                )
                """
            )
            cols = {
                row["name"]
                for row in self._conn.execute("PRAGMA table_info(device_tokens)").fetchall()
            }
            if "phone" not in cols:
                self._conn.execute("ALTER TABLE device_tokens ADD COLUMN phone TEXT")
            if "last_seen" not in cols:
                try:
                    self._conn.execute(
                        "ALTER TABLE device_tokens ADD COLUMN "
                        "last_seen TEXT DEFAULT (datetime('now'))"
                    )
                except sqlite3.OperationalError:
                    # Column may already exist in concurrent startup/migrations.
                    pass
            self._conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_device_tokens_phone ON device_tokens(phone)"
            )
            self._conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_device_tokens_fcm_token "
                "ON device_tokens(fcm_token)"
            )
            try:
                self._conn.execute(
                    "CREATE UNIQUE INDEX IF NOT EXISTS idx_device_tokens_fcm_token_unique "
                    "ON device_tokens(fcm_token)"
                )
            except sqlite3.IntegrityError:
                # Deduplicate old rows first, then enforce uniqueness.
                self._conn.execute(
                    """
                    DELETE FROM device_tokens
                    WHERE rowid NOT IN (
                        SELECT MAX(rowid)
                        FROM device_tokens
                        GROUP BY fcm_token
                    )
                    """
                )
                self._conn.execute("DROP INDEX IF EXISTS idx_device_tokens_fcm_token_unique")
                self._conn.execute(
                    "CREATE UNIQUE INDEX IF NOT EXISTS idx_device_tokens_fcm_token_unique "
                    "ON device_tokens(fcm_token)"
                )
            self._conn.commit()

    def upsert_device_token(
        self,
        user_id: str,
        token: str,
        platform: str,
        phone: Optional[str] = None,
    ):
        normalized_phone = _normalize_phone(phone) if phone else None
        with self._lock:
            # Enforce one-token-to-one-user mapping.
            self._conn.execute(
                "DELETE FROM device_tokens "
                "WHERE fcm_token = ? AND user_id != ?",
                (token, user_id),
            )
            self._conn.execute(
                """
                INSERT INTO device_tokens(
                    user_id,
                    fcm_token,
                    phone,
                    platform,
                    updated_at,
                    last_seen
                )
                VALUES (?, ?, ?, ?, ?, datetime('now'))
                ON CONFLICT(user_id) DO UPDATE SET
                    fcm_token=excluded.fcm_token,
                    phone=excluded.phone,
                    platform=excluded.platform,
                    updated_at=excluded.updated_at,
                    last_seen=datetime('now')
                """,
                (user_id, token, normalized_phone, platform, time.time()),
            )
            self._conn.commit()

    def get_db(self):
        return get_db()

    def get_device_token(self, user_id: str) -> Optional[str]:
        with self._lock:
            row = self._conn.execute(
                "SELECT fcm_token FROM device_tokens WHERE user_id = ?",
                (user_id,),
            ).fetchone()
            return str(row["fcm_token"]) if row else None

    def delete_device_token(self, user_id: str):
        with self._lock:
            self._conn.execute(
                "DELETE FROM device_tokens WHERE user_id = ?",
                (user_id,),
            )
            self._conn.commit()

    def get_tokens_by_phones(self, phones: list[str]) -> list[dict[str, str]]:
        normalized = [_normalize_phone(p) for p in phones if p and _normalize_phone(p)]
        if not normalized:
            return []

        placeholders = ",".join(["?"] * len(normalized))
        query = (
            "SELECT user_id, fcm_token, phone "
            "FROM device_tokens "
            f"WHERE phone IN ({placeholders})"
        )

        with self._lock:
            rows = self._conn.execute(query, tuple(normalized)).fetchall()
            return [
                {
                    "userId": str(row["user_id"]),
                    "fcmToken": str(row["fcm_token"]),
                    "phone": str(row["phone"] or ""),
                }
                for row in rows
            ]


storage = Storage(DB_PATH)


def _cleanup_stale_tokens():
    with get_db() as conn:
        conn.execute(
            """
            DELETE FROM device_tokens
            WHERE last_seen < datetime('now', '-90 days')
            """
        )
        conn.commit()
    print("[Startup] Stale token cleanup complete")


def _cleanup_stale_sos_events():
    if db is None:
        return

    try:
        now = datetime.now(timezone.utc)
        old_events = db.collection("sos_events").where("expiresAt", "<", now).get()
        for doc in old_events:
            doc.reference.delete()
        logger.info("[Startup] Cleaned %s stale SOS events", len(old_events))
    except Exception as e:
        logger.warning("[Startup] SOS cleanup failed: %s", e)


@app.on_event("startup")
async def startup_event():
    _cleanup_stale_tokens()
    _cleanup_stale_sos_events()


class PushService:
    def __init__(self):
        self.enabled = False
        self._init_firebase()

    def _init_firebase(self):
        global db

        if firebase_admin_module is None or fb_credentials is None:
            logger.warning("FCM disabled: firebase_admin not installed")
            return
        try:
            if not firebase_admin_module._apps:
                cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "")
                if cred_path and os.path.exists(cred_path):
                    firebase_admin_module.initialize_app(
                        fb_credentials.Certificate(cred_path)
                    )
                else:
                    firebase_admin_module.initialize_app()

            if fb_firestore is not None:
                try:
                    db = fb_firestore.client()
                    logger.info("Firestore client initialized")
                except Exception as exc:
                    db = None
                    logger.warning(f"Firestore disabled: {exc}")

            self.enabled = True
            logger.info("FCM initialized")
        except Exception as exc:
            self.enabled = False
            logger.warning(f"FCM disabled: {exc}")

    def send_data_notification(self, user_id: str, data: dict[str, str]) -> bool:
        if not self.enabled or fb_messaging is None:
            return False

        token = storage.get_device_token(user_id)
        if not token:
            return False

        try:
            message = fb_messaging.Message(
                data=data,
                android=fb_messaging.AndroidConfig(priority="high", ttl=60),
                token=token,
            )
            response_id = fb_messaging.send(message)
            logger.info(
                "FCM sent  user=%s type=%s response_id=%s",
                user_id,
                data.get("type", ""),
                response_id,
            )
            return True
        except Exception as exc:
            logger.warning(
                "FCM send failed  user=%s type=%s err=%s",
                user_id,
                data.get("type", ""),
                exc,
            )
            if _is_stale_token_error(exc):
                storage.delete_device_token(user_id)
                logger.warning("FCM stale token removed for user=%s", user_id)
            return False


push_service = PushService()


class RegisterTokenRequest(BaseModel):
    userId: Optional[str] = None
    token: str
    platform: str = "android"
    phone: Optional[str] = None


class SOSRequest(BaseModel):
    userId: str
    userName: str
    lat: str
    lng: str
    mapsLink: str


class SOSLocationUpdateRequest(BaseModel):
    sessionId: str
    lat: str
    lng: str


class SOSSessionStopRequest(BaseModel):
    sessionId: str


class EvidenceVerifyRequest(BaseModel):
    sessionId: str
    code: str


class HealthResponse(BaseModel):
    status: str = "ok"
    service: str = "aanchal-backend"
    version: str = "5.0.0"
    fcm_enabled: bool = False
    timestamp: str


@app.post("/api/device/register_token")
async def register_device_token(
    req: RegisterTokenRequest,
    auth: AuthContext = Depends(get_auth_context),
):
    if not req.token:
        raise HTTPException(status_code=400, detail="token required")

    if req.userId is not None and req.userId != auth.uid:
        raise HTTPException(
            status_code=403,
            detail="Authenticated UID does not match request userId",
        )

    _require_role(auth, {"user", "admin"})

    normalized_phone = normalize_phone(req.phone or "")

    storage.upsert_device_token(
        auth.uid,
        req.token,
        req.platform,
        phone=normalized_phone,
    )
    return {
        "ok": True,
        "userId": auth.uid,
        "platform": req.platform,
        "phone": normalized_phone or None,
    }


@app.post("/api/sos")
async def trigger_sos(
    body: SOSRequest,
    auth: AuthContext = Depends(get_auth_context),
):
    _require_role(auth, {"user", "admin"})
    _require_uid_match(body.userId, auth)
    _enforce_sos_throttle(auth.uid)

    user_id = auth.uid
    lat = body.lat
    lng = body.lng
    maps_link = body.mapsLink

    event_id = uuid.uuid4().hex
    session_id = uuid.uuid4().hex
    evidence_code = f"{secrets.randbelow(900000) + 100000}"
    now = datetime.now(timezone.utc)
    code_expiry = now + timedelta(minutes=EVIDENCE_CODE_TTL_MINUTES)

    # -- Step 1: Read contacts from Firestore -------------------------------
    contact_phones: list[str] = []
    if db is not None:
        try:
            contacts_ref = (
                db.collection("users")
                .document(user_id)
                .collection("emergency_contacts")
            )
            contacts_snap = await asyncio.to_thread(lambda: list(contacts_ref.stream()))

            for doc in contacts_snap:
                data = doc.to_dict() or {}
                raw_phone = data.get("phone", "")
                if raw_phone:
                    normalized = normalize_phone(raw_phone)
                    if normalized:
                        contact_phones.append(normalized)

            contact_phones = list(dict.fromkeys(contact_phones))
        except Exception as exc:
            logger.warning("Firestore contact read failed for user=%s err=%s", user_id, exc)

    # -- Step 2: Get all registered device tokens --------------------------
    with storage.get_db() as conn:
        all_registered = conn.execute(
            "SELECT user_id, fcm_token, phone FROM device_tokens"
        ).fetchall()

    # -- Step 3: Match by normalized phone ---------------------------------
    matched_tokens: list[str] = []
    targets: list[dict[str, str]] = []

    for row in all_registered:
        db_user_id = row[0]
        db_token = row[1]
        db_phone = normalize_phone(row[2] or "")

        if db_phone and db_phone in contact_phones:
            if db_token not in matched_tokens:
                matched_tokens.append(db_token)
                targets.append(
                    {
                        "userId": str(db_user_id),
                        "fcmToken": str(db_token),
                    }
                )

    # -- Step 4: Fallback — search Firestore users by phone ---------------
    if db is not None:
        for phone in contact_phones:
            try:
                def _get_user_docs(p: str):
                    return list(
                        db.collection("users")  # type: ignore
                        .where("phone", "==", p)
                        .limit(1)
                        .stream()
                    )

                user_docs = await asyncio.to_thread(_get_user_docs, phone)

                for user_doc in user_docs:
                    uid = user_doc.id
                    with storage.get_db() as conn:
                        token_row = conn.execute(
                            "SELECT fcm_token FROM device_tokens "
                            "WHERE user_id = ?",
                            (uid,),
                        ).fetchone()

                    if token_row:
                        token = str(token_row[0])
                        if token not in matched_tokens:
                            matched_tokens.append(token)
                            targets.append(
                                {
                                    "userId": str(uid),
                                    "fcmToken": token,
                                }
                            )
            except Exception as e:
                logger.warning("[SOS] Firestore user lookup failed for a contact: %s", e)

    # Resolve target user IDs from matched tokens.
    target_user_ids: list[str] = []
    if matched_tokens:
        with storage.get_db() as conn:
            for token in matched_tokens:
                row = conn.execute(
                    "SELECT user_id FROM device_tokens WHERE fcm_token = ?",
                    (token,),
                ).fetchone()
                if row and row[0]:
                    target_user_ids.append(str(row[0]))

    target_user_ids = list(dict.fromkeys(target_user_ids))

    # -- Step 5: Write Firestore session + event ---------------------------
    db_client = db
    if db_client is not None and target_user_ids:
        try:
            session_ref = db_client.collection("sos_sessions").document(session_id)
            await asyncio.to_thread(
                lambda: session_ref.set(
                    {
                        "userId": user_id,
                        "fromName": body.userName,
                        "startTime": now,
                        "active": True,
                        "contacts": target_user_ids,
                        "mapsLink": maps_link,
                        "lat": lat,
                        "lng": lng,
                        "evidenceAccessCodeHash": _hash_evidence_code(evidence_code),
                        "codeExpiry": code_expiry,
                        "codeUsed": False,
                    }
                )
            )

            initial_location_ref = session_ref.collection("locations").document(
                str(int(now.timestamp() * 1000))
            )
            await asyncio.to_thread(
                lambda: initial_location_ref.set(
                    {
                        "lat": lat,
                        "lng": lng,
                        "timestamp": now,
                    }
                )
            )

            await asyncio.to_thread(
                lambda: db_client.collection("sos_events").document(event_id).set(
                    {
                        "eventId": event_id,
                        "sessionId": session_id,
                        "fromUserId": user_id,
                        "fromName": body.userName,
                        "lat": lat,
                        "lng": lng,
                        "mapsLink": maps_link,
                        "targetUserIds": target_user_ids,
                        "createdAt": now,
                        "expiresAt": now + timedelta(minutes=10),
                    }
                )
            )

            logger.info(
                "[SOS] Firestore session+event written for %s target(s)",
                len(target_user_ids),
            )
        except Exception as e:
            logger.error("[SOS] Firestore write failed: %s", e)

    # -- Step 6: Send FCM to all matched tokens ----------------------------
    results = {"fcm_sent": [], "fcm_failed": []}

    async def notify_contact(contact: dict):
        token = contact.get("fcmToken")
        if not token:
            return

        if not push_service.enabled or fb_messaging is None:
            results["fcm_failed"].append("FCM not enabled")
            return

        message = fb_messaging.Message(
            data={
                "type": "sos_incoming",
                "eventId": event_id,
                "sessionId": session_id,
                "fromName": body.userName,
                "lat": str(lat),
                "lng": str(lng),
                "mapsLink": maps_link,
                "userId": user_id,
                "evidenceCode": evidence_code,
            },
            android=fb_messaging.AndroidConfig(
                priority="high",
                ttl=60,
            ),
            token=token,
        )

        try:
            await asyncio.to_thread(fb_messaging.send, message)
            results["fcm_sent"].append(contact.get("userId", token))
        except Exception as e:
            results["fcm_failed"].append(str(e))

    if matched_tokens:
        gather_results = await asyncio.gather(
            *[notify_contact(c) for c in targets if isinstance(c, dict)],
            return_exceptions=True,
        )
        for r in gather_results:
            if isinstance(r, Exception):
                results["fcm_failed"].append(str(r))

    notified_count = len(results["fcm_sent"])
    failed_count = len(results["fcm_failed"])

    logger.info(
        "[SOS] userId=%s contacts=%s matched_tokens=%s notified=%s failed=%s",
        user_id,
        len(contact_phones),
        len(matched_tokens),
        notified_count,
        failed_count,
    )
    return {
        "status": "ok",
        "eventId": event_id,
        "sessionId": session_id,
        "notified": notified_count,
        "failed": failed_count,
    }


@app.post("/api/sos/location")
async def update_sos_location(
    body: SOSLocationUpdateRequest,
    auth: AuthContext = Depends(get_auth_context),
):
    _require_role(auth, {"user", "admin"})

    if db is None:
        raise HTTPException(status_code=503, detail="Firestore unavailable")

    session_ref = db.collection("sos_sessions").document(body.sessionId)
    session_doc = await asyncio.to_thread(session_ref.get)
    if not session_doc.exists:
        raise HTTPException(status_code=404, detail="SOS session not found")

    session_data = session_doc.to_dict() or {}
    owner_uid = str(session_data.get("userId", ""))
    if owner_uid != auth.uid:
        raise HTTPException(status_code=403, detail="Cannot update another user's SOS session")

    now = datetime.now(timezone.utc)
    location_ref = session_ref.collection("locations").document(str(int(now.timestamp() * 1000)))
    await asyncio.to_thread(
        lambda: location_ref.set(
            {
                "lat": body.lat,
                "lng": body.lng,
                "timestamp": now,
            }
        )
    )
    await asyncio.to_thread(
        lambda: session_ref.set(
            {
                "active": True,
                "lastLocationAt": now,
            },
            merge=True,
        )
    )

    return {"ok": True, "sessionId": body.sessionId}


@app.post("/api/sos/session/stop")
async def stop_sos_session(
    body: SOSSessionStopRequest,
    auth: AuthContext = Depends(get_auth_context),
):
    _require_role(auth, {"user", "admin"})

    if db is None:
        raise HTTPException(status_code=503, detail="Firestore unavailable")

    session_ref = db.collection("sos_sessions").document(body.sessionId)
    session_doc = await asyncio.to_thread(session_ref.get)
    if not session_doc.exists:
        return {"ok": True, "sessionId": body.sessionId}

    session_data = session_doc.to_dict() or {}
    owner_uid = str(session_data.get("userId", ""))
    if owner_uid != auth.uid and auth.role != "admin":
        raise HTTPException(status_code=403, detail="Cannot stop another user's SOS session")

    now = datetime.now(timezone.utc)
    await asyncio.to_thread(
        lambda: session_ref.set(
            {
                "active": False,
                "endedAt": now,
            },
            merge=True,
        )
    )
    return {"ok": True, "sessionId": body.sessionId}


@app.post("/api/sos/evidence/verify")
async def verify_evidence_access_code(
    body: EvidenceVerifyRequest,
    auth: AuthContext = Depends(get_auth_context),
):
    _require_role(auth, {"user", "contact", "admin"})

    if db is None:
        raise HTTPException(status_code=503, detail="Firestore unavailable")

    session_ref = db.collection("sos_sessions").document(body.sessionId)
    session_doc = await asyncio.to_thread(session_ref.get)
    if not session_doc.exists:
        raise HTTPException(status_code=404, detail="SOS session not found")

    data = session_doc.to_dict() or {}
    owner_uid = str(data.get("userId", ""))
    contacts = [str(x) for x in data.get("contacts", [])]
    if auth.uid not in contacts and auth.uid != owner_uid and auth.role != "admin":
        raise HTTPException(status_code=403, detail="Not allowed for this SOS session")

    if bool(data.get("codeUsed", False)):
        raise HTTPException(status_code=410, detail="Evidence access code already used")

    expiry = data.get("codeExpiry")
    expiry_dt = expiry if isinstance(expiry, datetime) else None
    if expiry_dt is not None and expiry_dt < datetime.now(timezone.utc):
        raise HTTPException(status_code=410, detail="Evidence access code expired")

    expected_hash = str(data.get("evidenceAccessCodeHash", "")).strip()
    if not expected_hash:
        raise HTTPException(status_code=404, detail="Evidence access code not configured")

    provided_hash = _hash_evidence_code(body.code.strip())
    if not secrets.compare_digest(expected_hash, provided_hash):
        raise HTTPException(status_code=401, detail="Invalid evidence access code")

    await asyncio.to_thread(
        lambda: session_ref.set(
            {
                "codeUsed": True,
                "codeUsedAt": datetime.now(timezone.utc),
            },
            merge=True,
        )
    )

    return {
        "ok": True,
        "accessGranted": True,
        "sessionId": body.sessionId,
    }


# TEMPORARY DEBUG ENDPOINT — REMOVE BEFORE PUBLIC LAUNCH.
@app.get("/debug/tokens")
async def debug_tokens(auth: AuthContext = Depends(get_auth_context)):
    """
    TEMPORARY DEBUG ENDPOINT — REMOVE BEFORE PUBLIC LAUNCH.
    Shows token registry status for admin diagnostics.
    Used to diagnose FCM phone-matching issues.
    """
    _require_role(auth, {"admin"})

    with storage.get_db() as conn:
        rows = conn.execute(
            "SELECT user_id, last_seen "
            "FROM device_tokens "
            "ORDER BY last_seen DESC"
        ).fetchall()

    return {
        "count": len(rows),
        "tokens": [
            {
                "userId": r[0],
                "last_seen": r[1],
            }
            for r in rows
        ],
    }


@app.get("/health", response_model=HealthResponse)
async def health_check():
    probe_ts = datetime.now(timezone.utc).isoformat()
    return HealthResponse(
        status="ok",
        fcm_enabled=push_service.enabled,
        timestamp=probe_ts,
    )


@app.get("/")
async def root():
    return {
        "service": "Aanchal Backend",
        "version": "5.0.0",
        "endpoints": {
            "register_token": "POST /api/device/register_token",
            "sos": "POST /api/sos",
            "sos_location": "POST /api/sos/location",
            "sos_session_stop": "POST /api/sos/session/stop",
            "evidence_verify": "POST /api/sos/evidence/verify",
            "health": "/health",
        },
    }


@app.websocket("/ws/{user_id}")
async def legacy_ws(websocket: WebSocket, user_id: str):
    """
    Legacy WebSocket endpoint — silently closes without logging.
    Prevents log spam from old app instances that have stale code.
    WebRTC was removed; this endpoint is a no-op.
    """
    await websocket.close(code=1001)
