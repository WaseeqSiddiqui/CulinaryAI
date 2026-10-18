# Deploying CulinaryAI Backend

This backend powers the AI features of CulinaryAI:
- Fridge visual reconciliation (`/scan-fridge`)
- Chef chat (`/chef-chat`)
- Receipt parsing (`/parse-receipt`)
- Meal planning & nutrition (`/meal-recommendations`, `/meal-nutrition`)
- Store product matching (`/match-product`)

---

## Option 1: Deploy to Render (Recommended, Free & 2 Minutes)

Render provides free hosting with automatic HTTPS and auto-deploys whenever you push to GitHub.

### Step 1: Sign Up / Log In
1. Go to [render.com](https://render.com) and log in with your **GitHub account**.

### Step 2: Create Web Service
1. Click **New +** -> **Web Service**.
2. Select **Build and deploy from a Git repository**.
3. Choose your repository: `WaseeqSiddiqui/CulinaryAI`.
4. Configure the settings:
   - **Name**: `culinary-ai-backend` (or your choice)
   - **Root Directory**: `backend`
   - **Runtime**: `Python 3`
   - **Build Command**: `pip install -r requirements.txt`
   - **Start Command**: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
   - **Plan**: `Free`

### Step 3: Add Environment Variables
Under the **Environment Variables** section, add:
- `GEMINI_API_KEY`: *(Your Google AI Studio Gemini API key)*
- `GEMINI_MODEL`: `gemini-2.5-flash` (or your preferred model)

### Step 4: Click "Create Web Service"
- In ~1-2 minutes, Render will build and deploy your backend.
- You will receive a permanent HTTPS URL, such as:
  ```
  https://culinary-ai-backend.onrender.com
  ```

---

## Option 2: Deploy to Railway

1. Go to [railway.app](https://railway.app) and sign in with GitHub.
2. Click **New Project** -> **Deploy from GitHub repo**.
3. Select `WaseeqSiddiqui/CulinaryAI`.
4. In Settings:
   - Set **Root Directory** to `/backend`.
5. Under **Variables**:
   - Add `GEMINI_API_KEY`.
   - Add `PORT` (Railway provides this automatically or uses 8000).
6. Under **Settings** -> **Networking**, click **Generate Domain** to get your public HTTPS URL.

---

## Connecting the Flutter App to Your Deployed Server

Once deployed, you can connect your mobile app in either of two ways:

### Method A: In-App (No Rebuild Needed!)
1. Open the CulinaryAI app on your phone.
2. Tap the **Server Settings** icon (gear / server icon in the app bar).
3. Type or paste your deployed URL (e.g., `https://culinary-ai-backend.onrender.com`).
4. Tap **Test Connection** -> Verify it says `Connected successfully (HTTP 200)`.
5. Tap **Save & Use**.

### Method B: Default in Code / Build
Pass `--dart-define` during flutter build/run:
```bash
flutter run --dart-define=CULINARY_API_BASE_URL=https://culinary-ai-backend.onrender.com
```
or update `defaultLocalIp` / `fallbackDefaultUrl` in `lib/services/server_config_service.dart`.
