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

## Groq models

Generative features use Groq by default. Set these server-side values in
`backend/.env` (see `.env.example`), then restart the backend:

```dotenv
AI_PROVIDER=groq
GROQ_API_KEY=your_groq_api_key_here
GROQ_TEXT_MODEL=openai/gpt-oss-120b
GROQ_VISION_MODEL=qwen/qwen3.8-27b
```

One Groq key serves both models. Never put it in Flutter assets or a
`--dart-define`. Existing Gemini credentials are not used in Groq mode.

The app defaults to the hosted Render URL. A local `.env` does not configure
that hosted service: deploy the updated backend and set `GROQ_API_KEY` in the
Render service's environment. The repository's `render.yaml` declares the
provider and both model IDs, with the key supplied separately as a secret.

| Features | Model |
| --- | --- |
| Chef Chat, cooking-step chat, step explanations | `openai/gpt-oss-120b` |
| Shopping query normalization and product matching | `openai/gpt-oss-120b` |
| Receipt parsing, fridge scans, meal-photo estimates, cooking-photo checks | `qwen/qwen3.8-27b` |

Qwen runs in instruction mode and GPT-OSS uses low reasoning effort to limit
latency. Structured operations request strict JSON schemas and retain the
existing server-side quantity, price, stock, product-form and confidence checks.
Failed photo checks return `unable_to_assess`; they never fabricate a successful
assessment. A missing Groq key gives a configuration error, and Chef Chat can
then use its labelled offline fallback. Groq failures do not trigger Gemini calls.

The vision model is currently a preview model. Verify model access in your Groq
account, and compare real receipts/photos before relying on accuracy or response
time. No live latency or accuracy benchmark is implied by the mocked tests.
Model IDs are configurable without changing Flutter.

Primary references: [GPT-OSS 120B](https://console.groq.com/docs/model/openai/gpt-oss-120b),
[Qwen vision](https://console.groq.com/docs/model/qwen/qwen3.8-27b),
[structured outputs](https://console.groq.com/docs/structured-outputs).

For a deliberate rollback, set `AI_PROVIDER=gemini` with `GEMINI_API_KEY` and
`GEMINI_MODEL`, then restart. The Google SDK remains installed for this optional
path and the shared content/schema types. Some internal schema names retain
their historic `Gemini` prefix for compatibility; Groq mode sends their data to
Groq only.

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
