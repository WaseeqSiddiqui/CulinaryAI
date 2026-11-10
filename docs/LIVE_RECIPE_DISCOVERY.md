# Pantry-based live recipe discovery

Chef Chat now routes recipe questions to `POST /discover-recipes`. This path
does not read `verified_recipes.json`, the Flutter recipe catalog, or a generated
recipe from Gemini. General chat and the separate curated recipe library retain
their existing behavior.

The backend calls TheMealDB's live ingredient-filter and name-search tools,
then retrieves full ingredient details for candidate recipes. Ingredient names
in the current pantry determine the searches. Title searches also surface meals
centered on those foods. Every displayed recipe comes from an actual provider
record and links to its recipe page.

## Inventory decisions

- The client sends the current pantry on every request, including quantities,
  units and recorded expiry dates. It does not send an account ID to the recipe
  website. The backend rechecks the inventory even when source data is cached.
- The requested date supports today, tomorrow, day after tomorrow, weekdays,
  `in N days`, and `YYYY-MM-DD`. The client supplies its local reference date.
  An explicit `requested_date` also works for other clients. Items expiring
  before that date and zero stock are excluded.
- Matching normalizes common ingredient aliases and compatible units. Shared
  words alone do not make two foods equivalent: milk powder does not count as
  milk, and coconut oil does not count as olive oil.
- Each ingredient reports `available`, `missing`, `insufficient` or
  `check_quantity`. Stock is reserved while evaluating duplicate ingredient rows,
  so the same eggs cannot be counted twice within one recipe.
- A result needs its main food in stock and at least half of its principal
  ingredient names present. Complete quantity matches rank first. Alternatives
  explicitly list shortages and uncertain amounts; a shared spice alone never
  qualifies a recipe.
- Dietary and allergen filters inspect the complete external ingredient list.
  Packaged ingredient labels and certification still need checking. Preferences
  the provider cannot verify are identified in the response.
- No staples are silently assumed. Unknown amounts, ranges, pack weights,
  count-to-weight conversions and cup-to-ml conversions remain uncertain.

The provider does not supply reliable serving counts, cooking times or nutrition
for these records. The UI says so and compares the original listed quantities.
It opens the actual recipe for cooking instructions instead of inventing a
serving multiplier or importing unsupported values into guided cooking.

An empty pantry returns an inventory message without an external search. No
matching recipes returns an honest empty result. Provider errors produce a
retry message, with no silent local-demo fallback. Partial failures are identified.

## Configuration

The API uses `MEALDB_API_KEY` on the backend. With no setting, it uses TheMealDB's
documented development key `1`. Public app-store distribution requires a
supporter production key under the provider's terms:
https://www.themealdb.com/api.php

No Gemini key is needed for this feature. The configured Gemini key returned
quota exhaustion during verification, so live recipe discovery deliberately
works independently of it.

Ingredient searches are cached for 10 minutes and full recipe records for one
hour, with a bounded 256-entry cache. Network concurrency is limited to four.
The client allows 75 seconds for a cold discovery request. These caches contain
provider data; recipe-to-inventory decisions are never cached.

Deploy the updated backend before shipping the updated client. Older servers
without `/discover-recipes` produce a clear unavailable message. Run the app
against the local backend to exercise the implemented feature immediately:

```powershell
cd backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
# In another terminal at the project root:
flutter run -d chrome --dart-define=CULINARY_API_BASE_URL=http://127.0.0.1:8000
```

Regression coverage lives in `backend/tests/test_live_recipe_discovery.py`,
`test/recipe_discovery_api_test.dart` and
`test/chatbot_backend_integration_test.dart`. It covers actual inventory changes,
shortages, expiry on the requested day, unknown quantities, food forms, dietary
filters, duplicate rows, source attribution, provider outages and phone layout.
