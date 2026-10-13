# CulinaryAI

A Flutter cooking assistant with pantry tracking, receipt OCR, AI-assisted
recipe discovery, guided cooking, household sharing, and smart restocking.

## Run the integrated app

Week 2 connects Chef Chat to the FastAPI verified-recipe planner. Start both
services from separate terminals:

```powershell
cd backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

```powershell
flutter run --dart-define=CULINARY_API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` reaches the host machine from the Android emulator. For a physical
device, replace it with the development machine's LAN address. Deployed builds
should use an HTTPS endpoint. If the backend is unavailable, Chef Chat clearly
labels the issue and continues with its offline recommendation engine.

## Demo kitchen

Run `flutter pub get` followed by `flutter run`, then choose **Explore the Demo
Kitchen**. This path is offline-safe and opens a pre-populated pantry so the
main product flow can be presented without creating an account or configuring
demo credentials.

Suggested demo flow:

1. Review pantry health and recipe inspiration on Home.
2. Open My Pantry to search, filter, add, and adjust ingredients.
3. Ask Chef Chat for a meal using available ingredients.
4. Scan a receipt from the camera or gallery and review detected items.
5. Open Restock to act on low-stock items.

## Project services

- Flutter app: run `flutter pub get`, then `flutter run`.
- Person C backend: see [backend/README.md](backend/README.md) for setup, API
  examples, and tests.

## Project documentation

- [Detailed progress and future roadmap](docs/CulinaryAI_Project_Progress_and_Roadmap.docx)

## Verification

```powershell
flutter analyze
flutter test
cd backend
.\.venv\Scripts\python.exe -m pytest -q
```
