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

## Free / Plus allowances and Google Play subscriptions

The app exposes plan details from Profile and Request a dish. Free includes
20 Chef requests and 3 photo scans per UTC calendar month. Plus is displayed as
PKR 999/month with 500 Chef requests and 50 photo scans. The app displays Google's
actual localized monthly price when the product is available. Checkout stays
disabled until `GOOGLE_PLAY_BILLING_ENABLED=true` is configured after store setup.
No endpoint lets a client grant itself Plus or submit an unverified payment.

Chef requests include chat, detailed cooking guidance, shopping normalization
and AI product matching. All four photo endpoints share one pool. Manual pantry
tracking and source-based recipe/restaurant searches do not spend these credits.

The backend verifies Firebase ID tokens, reads server-owned entitlements, and
reserves credits with Firestore transactions before model calls. Normal request
errors and unassessable photo checks refund the reservation. Refund finalization
is idempotent. Pending reservations retained after a worker crash or database
outage must be reconciled by an operator; do not delete usage documents to reset
an account. Usage survives restarts and is shared across backend instances.

Before deploying the new quota-enforced API:

1. Configure Firebase server credentials on Render, using a service-account
   secret file and `GOOGLE_APPLICATION_CREDENTIALS` pointing to its path, or the
   server-only `FIREBASE_SERVICE_ACCOUNT_JSON` environment variable. Use the
   `culinaryai-518b3` project and permissions for Auth verification and Firestore.
   Do not copy a service-account file into Flutter or commit it to Git.
2. Set `FIREBASE_PROJECT_ID=culinaryai-518b3` and `USAGE_LIMITS_ENABLED=true`.
   Firestore billing collections are backend-only in `firestore.rules`.
3. Release the updated Flutter client, which sends Firebase Bearer tokens,
   together with the updated API. Older clients that send only `X-User-Id`
   cannot call quota-enforced AI endpoints. Without Firebase credentials the API
   fails closed; it does not silently provide unlimited usage.
   Startup checks Auth access and performs a refunded Firestore reservation for
   the `culinary-subscription-readiness-v1` service identity. An invalid
   setup prevents the new worker from accepting traffic; no real user's credits
   are used by this check.
4. Verify `/subscription/me` with a signed-in account and check free/expired Plus
   limits before public release. `USAGE_LIMITS_ENABLED=false` is a temporary
   local/staging compatibility switch, not production subscription enforcement.

`GET /subscription/plans` is public. `GET /subscription/me` requires Firebase
authentication. User quota exhaustion returns HTTP 429 with
`detail.code=quota_exceeded` and `X-Usage-Limit: exceeded`; provider rate limits
remain retryable provider errors and never trigger an upgrade prompt.

`POST /subscription/google-play/verify` accepts only a purchase token with a
verified Firebase bearer token. The server queries Google's subscriptionsv2 API,
checks the product/base plan and SHA-256 Firebase account binding, writes a
server-owned entitlement transactionally, then acknowledges the purchase. Replays
do not add usage credits or duplicate subscription periods. A purchase token cannot
move between accounts. Replacements supersede linked old tokens. Raw purchase
tokens remain in backend-only `billing_play_purchases` documents and never appear
in public status responses or application error messages.

Before every metered request and every `/subscription/me` read, Google Play
entitlements are reverified. Canceled subscriptions keep paid access until expiry;
grace periods retain access; pending, expired, paused, refunded/revoked or on-hold
purchases do not grant Plus. Provider outages fail closed for paid access. Very
old expired tokens returning HTTP 410 fall back to Free rather than blocking the
account permanently. Background notifications are not required by this flow:
renewal/refund changes are applied on the next server access check. No user-facing
code trusts an Android purchase success callback to grant access.

### Play Console setup (required before real payments)

1. The owner creates/verifies their [Play Console account](https://play.google.com/console/signup),
   accepts the agreement and pays Google's registration fee themselves. Create the
   app with package `com.enterprise.culinaryAI`, configure the payments profile,
   and complete the required store privacy/subscription information.
2. Configure a private upload signing key and Play App Signing before uploading a
   release AAB. The repository's existing release build currently uses the debug
   signing key; it is not a production upload-signing setup. Test APKs provided
   locally are not Play Store releases. Billing requires Android API 24+ with the
   selected official Flutter plugin.
3. Under **Monetize with Play → Products → Subscriptions**, create product
   `culinary_plus_monthly`, auto-renewing base plan `monthly`, billing period one
   month, and PKR 999 Pakistan pricing. Set other regional prices and activate the
   base plan. The app deliberately selects the ordinary monthly base plan, not
   introductory offers. Do not rename these IDs without updating client/server.
4. Enable the Google Play Android Developer API in the service account's Cloud
   project. In Play Console Users and permissions, grant the existing backend
   service-account email app-specific access to **View financial data, orders,
   and cancellation survey responses** and **Manage orders and subscriptions**.
   The server uses its existing Firebase/Google service-account credential with
   the Android Publisher scope. No Play API key belongs in Flutter.
5. Deploy backend code and Firestore rules. Set
   `GOOGLE_PLAY_BILLING_ENABLED=true` only for license testing once API permissions
   and the active product are ready. Free usage and restaurant search do not
   require this flag. Checkout remains disabled by default.
6. Upload an appropriately signed AAB to an internal testing track. Add license
   testers, install through the Play test link, and use Google's test payment
   methods. Verify successful/pending/declined checkout, cancel, restore after
   reinstall, renewal, refund/revoke, account switching and server outage retry.
   The app must show the store price and Plus only after server verification.
   Public paid release requires completion of this real store test, which is
   not covered by unit tests or a sideloaded debug APK.

References: [API setup](https://developers.google.com/android-publisher/getting_started),
[subscription lifecycle](https://developer.android.com/google/play/billing/lifecycle/subscriptions),
[purchase verification](https://developer.android.com/google/play/billing/security),
[subscription products](https://support.google.com/googleplay/android-developer/answer/140504).

## API examples

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
