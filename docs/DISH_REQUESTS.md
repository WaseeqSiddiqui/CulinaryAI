# Requested dishes and restaurant menus

Open Recipes and choose Request a dish, or use Home → All features → Request a
dish. Chef Chat also recognizes explicit requests such as “I want chicken
biryani”, “How do I cook tomato pasta?”, a bare “biryani”, and “mujhe biryani
chahiye”. General pantry and weekly-plan questions retain their existing flow.

Enter a dish and optionally a neighbourhood and city in Pakistan. Check my
pantry compares the recipe's listed ingredient amounts against current stock.
Expired and zero-quantity items do not cover ingredients. Missing and
insufficient quantities are listed separately from unknown or incompatible
units. An empty pantry is checked too. Stock is never changed by this feature.

Named recipes are retrieved from TheMealDB. When a dish is absent there, Tavily
searches a small allowlist of recipe sites. The backend reads actual Recipe
JSON-LD ingredient lists from those sites and validates the requested dish name.
It does not invent ingredients or replace chicken with a lamb recipe. Unsupported
recipes produce an explicit unknown result. Portions are not inferred from the
user's household; users must check the source recipe's portions.

When ingredients are missing and an area is supplied, the app automatically
searches Tavily for restaurant-owned ordering/menu websites. If no area was entered,
users can add one and choose Find restaurants. Unknown recipe or quantity
results also allow an explicit restaurant search. Ready-to-cook results do not
automatically invoke restaurant search.

Restaurant results use HTTPS restaurant websites. Delivery marketplaces,
directories, social pages, private/network URLs, and static menu images are
excluded. Tavily extraction reads candidate sites and finds real ordering/menu
links on those pages, including same-site ordering subdomains. Essential query
parameters such as branch IDs are preserved, while tracking parameters are
removed. No ordering URL is invented by appending a guessed path.

The app labels each action as ordering, a menu, or a website visit according to
the source. Country-wide chains may appear when their menu matches; delivery to
the requested search area still needs confirmation on the restaurant website.
If the source confirms only the dish family, the card explicitly says the exact
dish is unconfirmed. The app shows at most five results, cleans HTML/Markdown
formatting, and skips malformed entries without breaking the entire result list.
It does not claim exact distance, opening hours, live stock, prices or delivery
eligibility. No purchase is submitted by this feature.

A View Plus entry on this page opens the same Free/Plus allowance screen as
Profile. Payment collection is intentionally disabled until a billing provider
is connected. See the backend README for the Firebase quota rollout steps.

## Backend configuration

Set TAVILY_API_KEY in backend/.env for local development and in the hosted
service's environment for production. It is never compiled into Flutter. The
backend sends dish and area search terms to Tavily, not the user's pantry,
account identifiers or device coordinates. No new location permission is needed.

Deploy the backend and rebuild the app. The configured default backend is the
Render service, so a local .env key alone does not enable the hosted app. The
Render blueprint declares TAVILY_API_KEY as a secret requiring server-side input.

Endpoints:

- POST /dish-options accepts dish, pantry_items and reference_date. Its status
  is ready, missing, check_quantities or recipe_not_found.
- POST /nearby-restaurants accepts only dish and area. It returns sourced menu
  links, an empty result, or a retryable 503 when the provider cannot be used.

## Validation

Backend tests cover empty inventory, shortages, expired food, uncertain units,
named-dish identity, structured recipe lookup, redirect restrictions, provider
failures, location/dish filtering and link validation. Flutter tests cover the
ready and missing paths, no restaurant request for ready inventory, small-screen
menu actions, partial failure recovery and stale area responses. Live development
checks use example dishes and cities without placing orders or sharing device
location. Result availability depends on indexed restaurant websites and does
not imply that a venue delivers to the user.
