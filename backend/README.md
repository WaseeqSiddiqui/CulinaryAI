# CulinaryAI FastAPI Backend

This service provides pantry-aware meal planning, verified-recipe retrieval,
and structured cooking instructions without requiring an external AI API key.
Chef Chat calls it for live recommendations and falls back to its local catalog
when the service cannot be reached.

## Run locally

From the repository root:

```powershell
python -m venv backend\.venv
backend\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
cd backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Open `http://127.0.0.1:8000/docs` for the interactive API documentation.

## API

`POST /generate-plan`

```json
{
  "question": "Suggest a quick high-protein dinner",
  "pantry_items": [
    {"name": "chicken breast", "quantity": 500, "unit": "g"},
    {"name": "basmati rice", "quantity": 250, "unit": "g"}
  ],
  "servings": 4,
  "meal_count": 3,
  "dietary_preferences": [],
  "max_cook_time_minutes": 45
}
```

`POST /generate-instructions`

```json
{"recipe_id": "rec_chicken_rice", "servings": 4}
```

The retrieval pipeline embeds the curated records in
`app/data/verified_recipes.json` using deterministic local hash embeddings. This
makes the Week 1 RAG flow reproducible and free to run; a hosted vector database
or LLM can replace the service implementation later without changing the API.

## Test

```powershell
cd backend
.\.venv\Scripts\python.exe -m pytest -q
```
