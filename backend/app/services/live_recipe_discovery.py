"""Live recipe tools: ingredient search -> recipe lookup -> inventory checks.

No local recipe catalog or generative model participates in this path.
Only provider responses are cached; pantry decisions are recomputed each time.
"""

from collections import Counter, OrderedDict
from concurrent.futures import ThreadPoolExecutor
from datetime import date
import logging
import os
import re
from threading import Lock
import time
from typing import Any
from urllib.parse import urlparse

import httpx

from app.models.recipe_discovery import (
    DiscoveredRecipe,
    RecipeDiscoveryRequest,
    RecipeDiscoveryResponse,
)
from app.services.recipe_inventory import (
    allowed_by_diet,
    canonical_name,
    check_ingredients,
    plan_date,
)

# Production provider keys live in the URL path. Don't let HTTP debug logging
# turn them into ordinary application logs.
logging.getLogger("httpx").setLevel(logging.WARNING)


class RecipeProviderUnavailable(Exception):
    pass


class TheMealDBClient:
    def __init__(self, client: httpx.Client | None = None, api_key: str | None = None):
        self.api_key = api_key or os.getenv("MEALDB_API_KEY") or "1"
        if not re.fullmatch(r"[A-Za-z0-9_-]+", self.api_key):
            raise ValueError("Invalid recipe provider configuration")
        self.client = client or httpx.Client(
            timeout=httpx.Timeout(8, connect=4),
            limits=httpx.Limits(max_connections=4, max_keepalive_connections=4),
            follow_redirects=False,
        )
        self._cache: OrderedDict[tuple, tuple[float, Any]] = OrderedDict()
        self._lock = Lock()

    def close(self):
        self.client.close()

    def _get(self, endpoint: str, **params) -> list[dict]:
        key = (endpoint, tuple(sorted(params.items())))
        with self._lock:
            cached = self._cache.get(key)
            if cached and cached[0] > time.monotonic():
                self._cache.move_to_end(key)
                return cached[1]
        try:
            response = self.client.get(
                f"https://www.themealdb.com/api/json/v1/{self.api_key}/{endpoint}.php",
                params=params,
            )
            response.raise_for_status()
            if len(response.content) > 3_000_000:
                raise ValueError("Response too large")
            payload = response.json()
            meals = payload.get("meals")
            if meals is not None and not isinstance(meals, list):
                raise ValueError("Malformed provider response")
            result = [meal for meal in (meals or []) if isinstance(meal, dict)]
        except (httpx.HTTPError, ValueError, AttributeError, TypeError):
            raise RecipeProviderUnavailable(
                "The live recipe website is unavailable. Please retry; no demo recipes were substituted."
            ) from None
        ttl = 3600 if endpoint == "lookup" else 600
        with self._lock:
            self._cache[key] = (time.monotonic() + ttl, result)
            self._cache.move_to_end(key)
            while len(self._cache) > 256:
                self._cache.popitem(last=False)
        return result

    def search_ingredient(self, ingredient: str) -> list[dict]:
        # Resolve against the provider's live vocabulary rather than assuming
        # its filters accept our pluralization or local ingredient labels.
        try:
            catalog = self._get("list", i="list")
            labels = [record.get("strIngredient") for record in catalog]
            labels = [label for label in labels if isinstance(label, str) and label.strip()]
            exact = next((label for label in labels if label.lower() == ingredient.lower()), None)
            matched = exact or next((label for label in labels if canonical_name(label) == canonical_name(ingredient)), None)
            if matched:
                ingredient = matched
        except RecipeProviderUnavailable:
            pass
        return self._get("filter", i=ingredient.replace(" ", "_"))

    def ingredient_vocabulary(self) -> list[str]:
        return [record["strIngredient"] for record in self._get("list", i="list") if isinstance(record.get("strIngredient"), str)]

    def search_name(self, name: str) -> list[dict]:
        return self._get("search", s=name)

    def lookup(self, recipe_id: str) -> dict | None:
        if not re.fullmatch(r"\d{1,12}", recipe_id):
            return None
        records = self._get("lookup", i=recipe_id)
        return next((record for record in records if str(record.get("idMeal")) == recipe_id), None)


_BASICS = {"salt", "pepper", "water", "olive oil", "cooking oil", "oil", "sugar", "butter"}
_AROMATICS = {"garlic", "onion", "spring onion", "ginger"}
_SEARCH_NAMES = {
    "egg": "eggs", "onion": "onions", "tomato": "tomatoes",
    "potato": "potatoes", "red lentil": "red lentils", "lentil": "lentils",
    "chickpea": "chickpeas", "bell pepper": "bell pepper", "chicken breast": "chicken breast",
}
_QUESTION_WORDS = {
    "what", "can", "could", "should", "would", "i", "we", "you", "my", "our", "the",
    "a", "an", "make", "cook", "cooking", "recipe", "recipes", "meal", "meals", "food",
    "today", "tonight", "tomorrow", "for", "on", "with", "using", "from", "in", "have",
    "pantry", "inventory", "please", "suggest", "recommend", "give", "show", "me", "some",
    "ideas", "idea", "dinner", "lunch", "breakfast", "how", "to", "do", "of", "and",
    "quick", "easy", "healthy", "vegetarian", "vegan", "day", "after", "next", "this",
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
}


def public_link(value: object) -> str | None:
    if not isinstance(value, str) or len(value) > 2048:
        return None
    try:
        uri = urlparse(value.strip())
        if uri.scheme != "https" or not uri.hostname or uri.username or uri.password or uri.port not in (None, 443):
            return None
        # These links are displayed only, never fetched by this backend.
        host = uri.hostname.lower()
        if "." not in host or host.endswith((".local", ".internal", ".localhost")) or re.fullmatch(r"[\d.]+", host) or ":" in host:
            return None
        return uri.geturl()
    except ValueError:
        return None


def raw_ingredients(record: dict) -> list[tuple[str, str]]:
    result = []
    for index in range(1, 21):
        name = record.get(f"strIngredient{index}")
        if isinstance(name, str) and name.strip():
            measure = record.get(f"strMeasure{index}")
            result.append((name.strip()[:160], measure.strip()[:120] if isinstance(measure, str) else ""))
    return result


class LiveRecipeDiscoveryService:
    def __init__(self, provider: TheMealDBClient | None = None):
        self.provider = provider or TheMealDBClient()

    def discover(self, request: RecipeDiscoveryRequest) -> RecipeDiscoveryResponse:
        day = plan_date(request)
        pantry = [item for item in request.pantry_items if item.quantity > 0 and (item.expiry_date is None or item.expiry_date >= day)]
        excluded = sorted({item.name for item in request.pantry_items if item.quantity > 0 and item.expiry_date is not None and item.expiry_date < day})
        response = RecipeDiscoveryResponse(
            pantry_item_count=len(pantry), planning_date=day, excluded_expired_items=excluded,
            message="Your pantry has no usable ingredients for this date. Add ingredients or update their expiry dates first.",
        )
        if not pantry:
            return response
        # Search principal foods before staples, with expiring foods first.
        ordered = sorted(pantry, key=lambda item: (canonical_name(item.name) in _BASICS, item.expiry_date or date.max, -item.quantity))
        names = list(dict.fromkeys(canonical_name(item.name) for item in ordered if canonical_name(item.name) not in _BASICS))[:6]
        if not names:
            response.message = "I found only basic seasonings or cooking fats. Add a main ingredient so I can find meals you can actually make."
            return response
        queries = [_SEARCH_NAMES.get(name, name) for name in names]
        response.searched_ingredients = queries
        vocabulary_method = getattr(self.provider, "ingredient_vocabulary", None)
        vocabulary = []
        if vocabulary_method:
            try:
                vocabulary = vocabulary_method()
            except RecipeProviderUnavailable:
                pass
        vocabulary += ["egg", "eggs", "rice", "pasta", "chicken", "beef", "tomato", "tomatoes", "potato", "potatoes", "spinach", "milk", "flour", "garlic", "onion", "onions"]
        query_text = request.question.lower()
        requested_foods = {canonical_name(label) for label in vocabulary if re.search(rf"\b{re.escape(label.lower())}\b", query_text)}
        requested_foods = {food for food in requested_foods if not any(food != other and re.search(rf"\b{re.escape(food)}\b", other) for other in requested_foods)}
        excluded_foods = {canonical_name(label) for label in vocabulary if re.search(rf"\b(?:without|no|avoid)\s+{re.escape(label.lower())}\b", query_text)}
        for family in ("nuts", "dairy", "gluten", "shellfish"):
            if re.search(rf"\b(?:without|no|avoid)\s+{family}\b", query_text):
                excluded_foods.add(family)
        requested_foods -= excluded_foods
        effective_request = request.model_copy(update={"avoid_ingredients": [*request.avoid_ingredients, *excluded_foods]})
        tokens = [word for word in re.findall(r"[a-z]+", request.question.lower()) if word not in _QUESTION_WORDS and len(word) > 2]
        searches = [("ingredient", query) for query in queries]
        # Ingredient-filter lists are alphabetical and often favor elaborate
        # dishes. Live title searches also surface meals centered on each food.
        searches += [("name", name) for name in names[:3]]
        if "egg" in names:
            searches.append(("name", "omelette"))
        if "rice" in names:
            searches.append(("name", "fried rice"))
        if {"flour", "egg", "milk"} <= set(names):
            searches.append(("name", "pancake"))
        # A named dish request also gets a live title search. The inventory check
        # still decides whether any retrieved recipe is suitable.
        if tokens:
            searches.append(("name", " ".join(tokens[:4])))
        searches = list(dict.fromkeys(searches))
        votes: Counter = Counter()
        summaries: dict[str, dict] = {}
        complete: dict[str, dict] = {}
        failures = 0

        def search(task):
            try:
                method = self.provider.search_ingredient if task[0] == "ingredient" else self.provider.search_name
                return method(task[1])
            except RecipeProviderUnavailable:
                return None

        with ThreadPoolExecutor(max_workers=4) as pool:
            for records in pool.map(search, searches):
                if records is None:
                    failures += 1
                    continue
                for record in records:
                    recipe_id = str(record.get("idMeal", ""))
                    if re.fullmatch(r"\d{1,12}", recipe_id):
                        votes[recipe_id] += 1
                        summaries[recipe_id] = record
                        if raw_ingredients(record):
                            complete[recipe_id] = record
        if failures == len(searches) or (failures and not summaries):
            raise RecipeProviderUnavailable("The live recipe website could not be reached. Please retry; no demo recipes were substituted.")
        candidates = sorted((key for key in summaries if key not in complete), key=lambda key: (votes[key], sum(word in str(summaries[key].get("strMeal", "")).lower() for word in tokens)), reverse=True)[:18]

        def lookup(recipe_id):
            try:
                return self.provider.lookup(recipe_id)
            except RecipeProviderUnavailable:
                return None

        with ThreadPoolExecutor(max_workers=4) as pool:
            details = list(complete.values())[:40] + list(pool.map(lookup, candidates))
        if candidates and not any(details):
            raise RecipeProviderUnavailable("Recipe search worked, but ingredient details could not be loaded. Please retry.")
        matches = []
        for record in details:
            if not record:
                continue
            raw = raw_ingredients(record)
            if not raw or not isinstance(record.get("strMeal"), str):
                continue
            response.checked_recipe_count += 1
            if not allowed_by_diet(raw, effective_request):
                continue
            if re.search(r"\b(dinner|lunch|supper)\b", query_text) and record.get("strCategory", "").lower() == "dessert":
                continue
            searchable = " ".join([canonical_name(record["strMeal"]), *(canonical_name(name) for name, _ in raw)])
            def mentions(food):
                terms = {food}
                if food == "pasta":
                    terms |= {"spaghetti", "penne", "macaroni", "fusilli", "linguine", "fettuccine", "rigatoni"}
                return any(re.search(rf"\b{re.escape(term)}\b", searchable) for term in terms)
            if requested_foods:
                matches_requested = [mentions(food) for food in requested_foods]
                if not (any(matches_requested) if " or " in query_text else all(matches_requested)):
                    continue
            checks = check_ingredients(raw, pantry)
            main = [item for item in checks if canonical_name(item.name) not in _BASICS]
            present = [item for item in main if item.status != "missing"]
            anchor = next((item for item in main if canonical_name(item.name) not in _AROMATICS), None)
            # A single shared spice never makes a recipe a pantry suggestion.
            # The recipe's primary food must also be present: garlic and butter
            # cannot justify recommending frog legs when there are none in stock.
            if not main or anchor is None or anchor.status == "missing" or len(present) / len(main) < 0.5:
                continue
            available = sum(item.status == "available" for item in checks)
            ready = available == len(checks)
            recipe_id = str(record["idMeal"])
            image = public_link(record.get("strMealThumb"))
            if image and urlparse(image).hostname not in ("www.themealdb.com", "themealdb.com"):
                image = None
            recipe = DiscoveredRecipe(
                recipe_id=f"mealdb_{recipe_id}", name=record["strMeal"][:180],
                cuisine=str(record.get("strArea") or "")[:80], category=str(record.get("strCategory") or "")[:80],
                image_url=image or "", source_url=f"https://www.themealdb.com/meal.php?c={recipe_id}",
                original_source_url=public_link(record.get("strSource")),
                ingredients=checks, pantry_match_percent=round(100 * available / len(checks)), can_cook_now=ready,
            )
            # Prioritize complete recipes, then coverage, missing main foods,
            # query relevance and using items that expire soon.
            urgency = sum(item.expiry_date is not None and (item.expiry_date - day).days <= 3 and any(canonical_name(check.name) == canonical_name(item.name) for check in checks) for item in pantry)
            score = (ready, available / len(checks), len(present) / len(main), sum(word in recipe.name.lower() for word in tokens), urgency)
            matches.append((score, recipe))
        matches.sort(key=lambda item: item[0], reverse=True)
        response.meals = [recipe for _, recipe in matches[:request.meal_count]]
        ready_count = sum(recipe.can_cook_now for recipe in response.meals)
        if response.meals:
            response.message = (
                f"I found {ready_count} recipe{'s' if ready_count != 1 else ''} whose listed ingredients and quantities are covered by your pantry."
                if ready_count else
                "I found recipes close to your pantry, but none has every listed quantity confirmed. Check the missing ingredients and quantities below."
            )
        else:
            response.message = "I searched live recipes, but found no close matches for your usable inventory and dietary restrictions. No unrelated or demo recipes were substituted."
        if day != request.reference_date:
            response.message += f" This uses your current stock, excluding anything expiring before {day.isoformat()}; future purchases and consumption are not predicted."
        if failures or any(detail is None for detail in details):
            response.message += " Some recipe searches or details were unavailable, so these results may be incomplete."
        if "halal" in " ".join(request.dietary_preferences).lower():
            response.source_quantities_note += " Check meat certification and packaged ingredients for halal suitability."
        if request.avoid_ingredients:
            response.source_quantities_note += " Check packaged ingredient labels against your allergies and dietary needs."
        unsupported = [item for item in request.dietary_preferences if item not in {"vegan", "vegetarian", "pescatarian", "halal", "gluten-free", "gluten free", "dairy-free", "dairy free", "balanced", "none", "omnivore"}]
        if unsupported:
            response.source_quantities_note += f" This source does not verify these preferences: {', '.join(unsupported)}."
        return response
