"""Check a requested dish independently of pantry-only recommendations."""

import re

from app.models.dish_options import DishOptionsRequest, DishOptionsResponse
from app.models.recipe_discovery import DiscoveredRecipe
from app.services.live_recipe_discovery import TheMealDBClient, RecipeProviderUnavailable, mealdb_recipe, raw_ingredients
from app.services.recipe_inventory import canonical_name, check_ingredients
from app.services.spoonacular_recipes import RecipeSource, SpoonacularRecipes, normalize_dish


class DishOptionsService:
    def __init__(self, provider: TheMealDBClient, fallback=None, production: SpoonacularRecipes | None = None):
        self.provider = provider
        self.fallback = fallback
        self.production = production

    @property
    def production_enabled(self):
        return bool(self.production and self.production.enabled)

    def check(self, request: DishOptionsRequest) -> DishOptionsResponse:
        if self.production_enabled:
            candidates = self.production.named(request.dish)
            if not candidates:
                return self._not_found(request)
            source = min(candidates, key=lambda recipe: (
                normalize_dish(recipe.name) != normalize_dish(request.dish), len(recipe.name),
            ))
        else:
            source = self._legacy_source(request.dish)
        if not source:
            return self._not_found(request)
        pantry = [item for item in request.pantry_items if item.quantity > 0 and (
            item.expiry_date is None or item.expiry_date >= request.reference_date)]
        checks = check_ingredients(source.ingredients, pantry)
        missing = any(item.status in ("missing", "insufficient") for item in checks)
        uncertain = any(item.status == "check_quantity" for item in checks)
        status = "missing" if missing else "check_quantities" if uncertain else "ready"
        recipe = DiscoveredRecipe(
            recipe_id=source.id, name=source.name, cuisine=source.cuisine, category=source.category,
            source=source.publisher, image_url=source.image, source_url=source.url,
            ingredients=checks, pantry_match_percent=round(100 * sum(c.status == "available" for c in checks) / len(checks)),
            can_cook_now=status == "ready", servings=source.servings, cook_time_minutes=source.minutes,
        )
        return DishOptionsResponse(dish=request.dish, status=status, recipe=recipe, message={
            "missing": "Some ingredients are missing or below the recipe's required amount.",
            "check_quantities": "Check the ingredient amounts or units before cooking.",
            "ready": "Your pantry covers the listed ingredient quantities for this recipe.",
        }[status])

    def _legacy_source(self, dish):
        # Empty inventories still need a real ingredient list, not an early exit.
        words = canonical_name(dish).split()
        if not words:
            return None
        try:
            records = self.provider.search_name(dish)
            if not records and len(words) > 1:
                records = self.provider.search_name(words[-1])
        except RecipeProviderUnavailable:
            if self.fallback is None:
                raise
            records = []
        matching = []
        for record in records:
            name = record.get("strMeal")
            recipe_id = str(record.get("idMeal", ""))
            if not isinstance(name, str) or not re.fullmatch(r"\d{1,12}", recipe_id):
                continue
            name_words = canonical_name(name).split()
            if not all(word in name_words for word in words):
                continue
            if not raw_ingredients(record):
                record = self.provider.lookup(recipe_id)
            if not record or not raw_ingredients(record):
                continue
            matching.append(record)
        if matching:
            record = min(matching, key=lambda r: (canonical_name(r["strMeal"]) != " ".join(words), len(r["strMeal"])))
            return mealdb_recipe(record)
        recipe = self.fallback.lookup(dish) if self.fallback else None
        if recipe:
            return RecipeSource("web_recipe", recipe["name"], recipe["ingredients"], "Recipe website", recipe["source_url"])
        return None

    @staticmethod
    def _not_found(request):
        return DishOptionsResponse(dish=request.dish, status="recipe_not_found", message=
            "I couldn't find a matching source recipe to verify its ingredients. Try a simpler dish name, or look for restaurant menus.")
