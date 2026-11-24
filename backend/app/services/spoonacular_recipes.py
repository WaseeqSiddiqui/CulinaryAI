"""Production recipe retrieval through the Spoonacular API."""

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from html import unescape
import math
import os
import re
from urllib.parse import urlsplit

import httpx

from app.services.recipe_inventory import canonical_name


class RecipeProviderUnavailable(Exception):
    pass


@dataclass(frozen=True)
class RecipeSource:
    id: str
    name: str
    ingredients: list[tuple[str, str]]
    publisher: str
    url: str
    image: str = ""
    cuisine: str = ""
    category: str = ""
    servings: int | None = None
    minutes: int | None = None
    original_url: str | None = None
    seasonings: frozenset[str] = frozenset()


def public_link(value: object) -> str | None:
    if not isinstance(value, str) or len(value) > 2048 or "\\" in value or any(ord(char) < 32 for char in value):
        return None
    try:
        uri = urlsplit(value.strip())
        host = uri.hostname or ""
        if uri.scheme != "https" or uri.username is not None or uri.port not in (None, 443):
            return None
        if "." not in host or ":" in host or host.endswith((".local", ".internal", ".localhost")) or re.fullmatch(r"[\d.]+", host):
            return None
        return uri.geturl()
    except ValueError:
        return None


_CUISINES = {
    "african", "asian", "american", "british", "cajun", "caribbean", "chinese",
    "eastern european", "european", "french", "german", "greek", "indian", "irish",
    "italian", "japanese", "jewish", "korean", "latin american", "mediterranean",
    "mexican", "middle eastern", "nordic", "southern", "spanish", "thai", "vietnamese",
}
_PAKISTANI_SEARCHES = {
    "chicken": "chicken karahi", "chicken breast": "chicken karahi",
    "rice": "chicken biryani", "lentil": "dal", "red lentil": "masoor dal",
    "chickpea": "chana masala", "potato": "aloo gobi", "spinach": "aloo palak",
    "egg": "egg curry", "okra": "bhindi masala", "beef": "keema",
}
_DISH_ALIASES = {"daal": "dal", "dhal": "dal", "dahl": "dal", "biriyani": "biryani",
                 "briyani": "biryani", "qeema": "keema", "kadahi": "karahi", "kadhai": "karahi",
                 "pilau": "pulao", "pilaf": "pulao"}


def normalize_dish(value: str) -> str:
    return " ".join(_DISH_ALIASES.get(word, word) for word in canonical_name(value).split())


def _text(value, limit):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", unescape(value))).strip()[:limit] if isinstance(value, str) else ""


def _positive_int(value):
    return value if type(value) is int and value > 0 else None


def _ingredients(rows):
    if not isinstance(rows, list) or not 1 <= len(rows) <= 100:
        return []
    ingredients = []
    for row in rows:
        if not isinstance(row, dict):
            return []
        name = _text(row.get("name"), 160)
        if not name:
            return []
        original = _text(row.get("original"), 300)
        amount, unit = row.get("amount"), _text(row.get("unit"), 48)
        measure = ""
        if type(amount) in (int, float) and math.isfinite(amount) and 0 < amount < 1_000_000:
            # Do not convert ranges, package sizes or vague amounts to a number.
            if not re.search(r"\d\s*[-–]\s*\d|\b(?:to taste|as needed|package|can|handful|pinch)\b|\(\s*\d", original, re.I):
                measure = f"{amount:.8f}".rstrip("0").rstrip(".") + (f" {unit}" if unit else "")
        ingredients.append((name, measure))
    return ingredients


class SpoonacularRecipes:
    def __init__(self, client=None, api_key=None):
        self.client = client or httpx.Client(timeout=httpx.Timeout(8, connect=3), follow_redirects=False)
        self.api_key = api_key

    @property
    def enabled(self):
        key = self.api_key if self.api_key is not None else os.getenv("SPOONACULAR_API_KEY", "")
        return bool(key.strip() and not key.strip().startswith("your_"))

    def _get(self, path, **params):
        key = self.api_key if self.api_key is not None else os.getenv("SPOONACULAR_API_KEY", "")
        try:
            response = self.client.get(
                f"https://api.spoonacular.com/recipes/{path}", params=params,
                headers={"x-api-key": key.strip()},
            )
            if response.status_code in (402, 429):
                raise RecipeProviderUnavailable("The recipe provider is at capacity. Please try again later.")
            response.raise_for_status()
            if len(response.content) > 4_000_000:
                raise ValueError("Oversized recipe response")
            return response.json()
        except (httpx.HTTPError, ValueError, TypeError):
            raise RecipeProviderUnavailable("The recipe provider is unavailable. Please try again.") from None

    def _search(self, **params):
        payload = self._get("complexSearch", number=8, addRecipeInformation="true",
                            instructionsRequired="true", **params)
        if not isinstance(payload, dict) or not isinstance(payload.get("results"), list):
            raise RecipeProviderUnavailable("The recipe provider returned incomplete search results. Please try again.")
        return payload["results"][:8]

    @staticmethod
    def _normalize(row):
        recipe_id = _positive_int(row.get("id"))
        title = _text(row.get("title"), 180)
        raw_url = row.get("sourceUrl")
        if isinstance(raw_url, str) and raw_url.startswith("http://"):
            raw_url = "https://" + raw_url[7:]
        url = public_link(raw_url)
        ingredient_rows = row.get("extendedIngredients")
        raw = _ingredients(ingredient_rows)
        if not (recipe_id and title and url and raw):
            return None
        cuisines = row.get("cuisines")
        categories = row.get("dishTypes")
        return RecipeSource(
            id=f"spoonacular_{recipe_id}", name=title, ingredients=raw,
            publisher=_text(row.get("sourceName") or row.get("creditsText"), 100) or (urlsplit(url).hostname or ""),
            url=url, image=public_link(row.get("image")) or "",
            cuisine=_text(cuisines[0], 80) if isinstance(cuisines, list) and cuisines else "",
            category="Dessert" if isinstance(categories, list) and "dessert" in categories else "",
            servings=_positive_int(row.get("servings")), minutes=_positive_int(row.get("readyInMinutes")),
            seasonings=frozenset(canonical_name(name) for (name, _), ingredient in zip(raw, ingredient_rows)
                                if ingredient.get("aisle") == "Spices and Seasonings"),
        )

    def _details(self, rows):
        unique = {row["id"]: row for row in rows if isinstance(row, dict) and _positive_int(row.get("id"))}
        incomplete = [str(key) for key, row in unique.items() if not row.get("extendedIngredients")]
        if incomplete:
            bulk = self._get("informationBulk", ids=",".join(incomplete), includeNutrition="false")
            if not isinstance(bulk, list):
                raise RecipeProviderUnavailable("The recipe provider returned incomplete ingredient details. Please try again.")
            for row in bulk:
                if isinstance(row, dict) and _positive_int(row.get("id")) and str(row["id"]) in incomplete:
                    unique[row["id"]] = {**unique[row["id"]], **row}
        return [recipe for row in unique.values() if (recipe := self._normalize(row))]

    def named(self, dish):
        normalized = normalize_dish(dish)
        wanted = set(normalized.split())
        if not wanted:
            return []
        return [recipe for recipe in self._details(self._search(query=normalized))
                if wanted <= set(normalize_dish(recipe.name).split())]

    def pantry(self, names, terms, cuisine, request):
        filters = {}
        if request.max_cook_time_minutes:
            filters["maxReadyTime"] = request.max_cook_time_minutes
        if request.avoid_ingredients:
            filters["excludeIngredients"] = ",".join(request.avoid_ingredients[:12])
        diets = {"vegan": "vegan", "vegetarian": "vegetarian", "pescatarian": "pescetarian",
                 "gluten-free": "gluten free", "gluten free": "gluten free"}
        selected = {diets[diet] for diet in request.dietary_preferences if diet in diets}
        if selected:
            filters["diet"] = ",".join(sorted(selected))
        anchor = next((name for name in names if name not in {"onion", "garlic", "ginger", "spring onion"}), names[0])
        if terms:
            searches = [{"query": normalize_dish(" ".join(terms[:6]))}]
        else:
            searches = [{"includeIngredients": anchor}]
        if cuisine.lower() in _CUISINES:
            searches.insert(0, {**searches[0], "cuisine": cuisine.lower()})
        elif cuisine == "Pakistani" and not terms:
            regional = next((_PAKISTANI_SEARCHES[name] for name in names if name in _PAKISTANI_SEARCHES), "")
            if regional:
                searches.insert(0, {"query": regional})
        def run(params):
            try:
                return self._search(**filters, **params)
            except RecipeProviderUnavailable as error:
                return error
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(run, searches))
        failures = [result for result in results if isinstance(result, RecipeProviderUnavailable)]
        if len(failures) == len(results):
            raise failures[0]
        rows = [row for result in results if isinstance(result, list) for row in result]
        return self._details(rows), len(failures)
