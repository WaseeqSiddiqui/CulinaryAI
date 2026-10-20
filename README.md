# CulinaryAI

A Flutter cooking assistant with pantry tracking, receipt OCR, AI-assisted
recipe discovery, guided cooking, household sharing, and smart restocking.
Now powered by a **LangGraph RAG pipeline** with ChromaDB vector search and
Gemini embeddings for grounded, pantry-aware recipe recommendations.

## RAG Architecture (Chef Chat)

Chef Chat now runs a 4-node LangGraph graph:

```
User Message + Pantry Items
        ↓
   parse_intent        ← intent detection, dietary prefs, cook time
        ↓
  retrieve_recipes     ← ChromaDB semantic search (Gemini embeddings)
        ↓
 filter_by_pantry      ← re-rank by pantry match % + similarity score
        ↓
 generate_response     ← Gemini LLM with retrieved recipe context
```

## Run the integrated app

Start both services from separate terminals:

```powershell
# Terminal 1 — Backend
cd backend
D:\Anaconda\python.exe -m pip install -r requirements.txt   # first time only
D:\Anaconda\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

```powershell
# Terminal 2 — Flutter app
flutter run --dart-define=CULINARY_API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` reaches the host machine from the Android emulator. For a physical
device, replace it with the development machine's LAN address.

## RAG status endpoint

Once the backend is running:
- `http://localhost:8000/rag-status` — indexed recipe count and vector store health
- `http://localhost:8000/docs` — full Swagger UI

## Demo kitchen

Run `flutter pub get` followed by `flutter run`, then choose **Explore the Demo
Kitchen**. This path is offline-safe and opens a pre-populated pantry so the
main product flow can be presented without creating an account.

Suggested demo flow:

1. Review pantry health and recipe inspiration on Home.
2. Open My Pantry to search, filter, add, and adjust ingredients.
3. Ask Chef Chat for a meal using available ingredients (LangGraph RAG active).
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
D:\Anaconda\python.exe -m pytest tests/test_rag.py -v   # RAG tests
D:\Anaconda\python.exe -m pytest -q                      # all tests
```
