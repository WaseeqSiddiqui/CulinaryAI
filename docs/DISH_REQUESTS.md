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
searches Tavily for Foodpanda restaurant menu pages. If no area was entered,
users can add one and choose Find restaurants. Unknown recipe or quantity
results also allow an explicit restaurant search. Ready-to-cook results do not
automatically invoke restaurant search.

Restaurant results must have a real HTTPS Foodpanda restaurant URL and source
text mentioning the requested dish and entered locality. Listings, darkstores,
other cities and unrelated dishes are filtered out. The app shows at most five
matching menu links. It does not claim exact distance, opening hours, live stock,
prices or delivery eligibility. The user opens the menu and completes ordering
on the merchant site; no purchase is submitted by this feature.

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
menu actions, partial failure recovery and stale area responses. Live checks
retrieved a Chicken Biryani recipe with twelve ingredients, three biryani menu
links in Lahore and five pizza menu links for Johar Town Lahore. These checks
did not place an order or share device location.
