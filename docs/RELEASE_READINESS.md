# CulinaryAI release handoff

The redesigned Flutter app includes responsive main and secondary screens,
dark mode, bundled typography, scanner review flows, guided cooking, household
forms, order history and purchase recovery. Backend tests exercise the current
local cooking endpoints. Automated merchant tests use fixtures and never place
a real order.

## Build and run

```powershell
flutter analyze
flutter test
flutter build web --release
cd backend
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

In a second terminal at the project root:

```powershell
flutter run -d chrome --dart-define=CULINARY_API_BASE_URL=http://127.0.0.1:8000
```

Host the contents of `build/web` on an HTTPS static host. For a different API,
build with `--dart-define=CULINARY_API_BASE_URL=https://your-api-host`.
Keep AI credentials in backend environment configuration.

## External release work

- Deploy `/discover-recipes` with the updated backend before releasing the
  live-recipe client. Set `MEALDB_API_KEY` to the provider's production key for
  public app-store distribution. See `LIVE_RECIPE_DISCOVERY.md`.
- On 30 October 2026 the configured Render API's public schema did not expose
  `/step-explanation`, `/cooking-step-chat` or `/validate-cooking-step`. Deploy
  the current backend to enable all three online. Older servers use local step
  guidance and Chef Chat for text; photo checks explain their unavailability.
- Deploy the local `firestore.rules` changes to enable household order writes.
  Order history and recovery remain available on the current device.
- Verify PandaMart login, address, cart selectors, COD and confirmation in a
  signed-in supported native WebView. A real test purchase needs specific items
  and a spending limit. See `PURCHASE_AUTOMATION.md` for acceptance checks.
- Android release configuration still uses the project's debug signing key.
  Configure a private release keystore before Play Store distribution. Native
  device permission and speech-service behavior also require device checks.

No hosted deployment, Firebase rule deployment, store publication or live
purchase is claimed by the local release build.
