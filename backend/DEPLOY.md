# Aanchal Backend — Render Deployment Guide
#
# This FastAPI backend handles AI Auto-Call requests from the Aanchal app.

## Prerequisites
- A free [Render](https://render.com) account
- Git repository with the `backend/` folder pushed

## Deployment Steps

### 1. Push to GitHub
```bash
git add backend/
git commit -m "Add FastAPI AI auto-call backend"
git push origin main
```

### 2. Create Render Web Service
1. Go to [Render Dashboard](https://dashboard.render.com)
2. Click **"New +"** → **"Web Service"**
3. Connect your GitHub repository
4. Configure:
   - **Name**: `aanchal-backend`
   - **Root Directory**: `backend`
   - **Runtime**: `Python 3`
   - **Build Command**: `pip install -r requirements.txt`
   - **Start Command**: `uvicorn main:app --host 0.0.0.0 --port $PORT`
   - **Instance Type**: `Free`

### 2B. One-Click via Blueprint (Recommended)
If your repo contains `render.yaml` at root, you can deploy directly:
1. Open Render Dashboard
2. Click **New +** → **Blueprint**
3. Select this repository
4. Render auto-detects `render.yaml` and creates `aanchal-backend`

### 3. Deploy
- Click **"Create Web Service"**
- Wait for the build to complete (2-3 minutes)
- Your API will be live at: `https://aanchal-backend.onrender.com`

### 3B. Verify Deployment from Terminal
```bash
curl -i https://aanchal-backend.onrender.com/
curl -i https://aanchal-backend.onrender.com/health
```
Expected status: `200 OK`

### 4. Update Flutter Config
In `lib/core/app_config.dart`, update:
```dart
static const String backendBaseUrl = 'https://aanchal-backend.onrender.com';
```

### 5. Test the Endpoints

**Health Check:**
```bash
curl https://aanchal-backend.onrender.com/health
```

**AI Auto-Call:**
```bash
curl -X POST https://aanchal-backend.onrender.com/ai/auto-call \
  -H "Content-Type: application/json" \
  -d '{
    "caller_number": "+919876543210",
    "callee_number": "+919876543211",
    "persona": "friend",
    "user_name": "User"
  }'
```

**Expected Response:**
```json
{
  "status": "ok",
  "call_id": "call_a1b2c3d4e5f6",
  "message": "Auto-call initiated to +919876543211 as friend",
  "timestamp": "2026-02-21T10:30:00.000000",
  "caller_number": "+919876543210",
  "callee_number": "+919876543211",
  "persona": "friend"
}
```

### 6. API Documentation
Once deployed, interactive API docs are available at:
- Swagger UI: `https://aanchal-backend.onrender.com/docs`
- ReDoc: `https://aanchal-backend.onrender.com/redoc`

## Notes
- Render free tier spins down after 15 minutes of inactivity
- First request after spin-down takes ~30 seconds (cold start)
- The Flutter app handles this with retry logic and timeout configuration
- For production, upgrade to a paid Render plan for always-on

## Keep-Warm via cron-job.org (Recommended for Demo Stability)
To reduce Render cold-start delays on free tier:

1. Create a job at https://cron-job.org
2. URL:
  `https://aanchal-backend.onrender.com/health`
3. Schedule:
  every 5 minutes
4. Method:
  `GET`

The `/health` endpoint is lightweight and does not query Firestore.

## Build Failure Fix (pydantic-core / Rust)
If Render logs show `metadata-generation-failed` for `pydantic-core` on Python 3.14,
pin Python to 3.12:
- `render.yaml` includes `PYTHON_VERSION=3.12.8`
- `backend/runtime.txt` is set to `python-3.12.8`

After pushing these files, trigger **Manual Deploy → Clear build cache & deploy** in Render.
