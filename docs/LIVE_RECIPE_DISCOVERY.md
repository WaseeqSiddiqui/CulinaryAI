# Pantry-based live recipe discovery

Chef Chat now routes recipe questions to `POST /discover-recipes`. This path
does not read `verified_recipes.json`, the Flutter recipe catalog, or a generated
recipe from a language model. General chat uses the separately configured Groq
text model, while this discovery path retrieves actual recipe sources.

The Recipes tab also offers publisher search. Set the backend's
`SPOONACULAR_API_KEY` to use Spoonacular for both pantry discovery and **Request
a dish**. Search results use the publisher's name, recipe URL, ingredients,
servings and available time estimate. Spoonacular search calls are bounded and
require a signed-in user. Without that key, the backend uses the existing
TheMealDB configuration.

Chef Chat shows three quick prompts and requests at most three recipes. Its
country control defaults to the device region (labelled as such), remembers a
manually selected country, and offers **Use current location** on Android.
Country detection uses the existing location permission flow; if it fails,
the user can enter any country. Only the country is sent with chat and recipe
requests, not the GPS coordinates or street address.

Country-specific dish searches and cuisine filters bring familiar meals into
the candidate set. Spoonacular does not list Pakistani as a cuisine filter, so
the backend searches for dish names such as karahi, biryani and masoor dal based
on the pantry. Coverage depends on the upstream catalog.
Explicit cuisine requests override this default. Suitable local matches rank
first, and the response explains when only other cuisines match the pantry.

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
  ingredient names present. Within the preferred cuisine, complete quantity
  matches rank first. Alternatives
  explicitly list shortages and uncertain amounts; a shared spice alone never
  qualifies a recipe.
- Dietary and allergen filters inspect the complete external ingredient list.
  Packaged ingredient labels and certification still need checking. Preferences
  the provider cannot verify are identified in the response.
- No staples are silently assumed. Unknown amounts, ranges, pack weights,
  count-to-weight conversions and cup-to-ml conversions remain uncertain.

The UI compares the source's original listed quantities and opens the
publisher's recipe for instructions. When available, it shows the publisher's
servings and time estimate. In-app guided recipes and the weekly planner use
their own catalog.

An empty pantry returns an inventory message without an external search. No
matching recipes returns an honest empty result. Provider errors produce a
retry message, with no silent local-demo fallback. Partial failures are identified.

## Configuration

1. Use a [Spoonacular plan](https://spoonacular.com/food-api/pricing) suited to
   your expected traffic and approved app use.
2. Add `SPOONACULAR_API_KEY` under **Render → Environment**, then deploy the
   backend. Keep this key server-side.
3. In a signed-in test account, try a pantry search, **Request a dish** and click
   through to the credited publisher before shipping. Test Pakistani coverage
   with dishes your users commonly request.

Spoonacular results are fetched for each search and are not persisted or
cached by the backend. API cost depends on query volume and the provider plan.
See [API documentation](https://spoonacular.com/food-api/docs) and
[provider terms](https://spoonacular.com/food-api/terms).

For legacy TheMealDB mode, `MEALDB_API_KEY=1` is the documented development
key. A public app-store release using TheMealDB needs its paid supporter key.
[TheMealDB API guide](https://www.themealdb.com/api.php)

No Groq or Gemini key is needed for this feature. Live recipe discovery works
independently of the text and vision models.

Legacy TheMealDB ingredient searches are cached for 10 minutes and full recipe records for one
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
