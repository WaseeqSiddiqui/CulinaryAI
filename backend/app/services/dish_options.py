"""Check a requested dish independently of pantry-only recommendations."""

import re

from app.models.dish_options import DishOptionsRequest, DishOptionsResponse
from app.models.recipe_discovery import DiscoveredRecipe
from app.services.live_recipe_discovery import TheMealDBClient, RecipeProviderUnavailable, public_link, raw_ingredients
from app.services.recipe_inventory import canonical_name, check_ingredients


class DishOptionsService:
    def __init__(self, provider: TheMealDBClient, fallback=None):
        self.provider = provider
        self.fallback = fallback

    def check(self, request: DishOptionsRequest) -> DishOptionsResponse:
        # Empty inventories still need a real ingredient list, not an early exit.
        words = canonical_name(request.dish).split()
        if not words:
            return self._not_found(request)
        try:
            records = self.provider.search_name(request.dish)
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
        source_recipe = None
        if not matching:
            source_recipe = self.fallback.lookup(request.dish) if self.fallback else None
            if not source_recipe:
                return self._not_found(request)
        record = min(matching, key=lambda r: (canonical_name(r["strMeal"]) != " ".join(words), len(r["strMeal"]))) if matching else None
        pantry = [item for item in request.pantry_items if item.quantity > 0 and (
            item.expiry_date is None or item.expiry_date >= request.reference_date)]
        checks = check_ingredients(source_recipe['ingredients'] if source_recipe else raw_ingredients(record), pantry)
        missing = any(item.status in ("missing", "insufficient") for item in checks)
        uncertain = any(item.status == "check_quantity" for item in checks)
        status = "missing" if missing else "check_quantities" if uncertain else "ready"
        image = public_link(record.get("strMealThumb")) or "" if record else ""
        if image and not image.startswith("https://www.themealdb.com/"):
            image = ""
        recipe = DiscoveredRecipe(
            recipe_id=f"mealdb_{record['idMeal']}" if record else 'web_recipe',
            name=record["strMeal"][:180] if record else source_recipe['name'],
            cuisine=str(record.get("strArea") or "")[:80] if record else '',
            category=str(record.get("strCategory") or "")[:80] if record else '',
            source='TheMealDB' if record else 'Recipe website', image_url=image,
            source_url=f"https://www.themealdb.com/meal.php?c={record['idMeal']}" if record else source_recipe['source_url'],
            ingredients=checks, pantry_match_percent=round(100 * sum(c.status == "available" for c in checks) / len(checks)),
            can_cook_now=status == "ready",
        )
        return DishOptionsResponse(dish=request.dish, status=status, recipe=recipe, message={
            "missing": "Some ingredients are missing or below the recipe's required amount.",
            "check_quantities": "Check the ingredient amounts or units before cooking.",
            "ready": "Your pantry covers the listed ingredient quantities for this recipe.",
        }[status])

    @staticmethod
    def _not_found(request):
        return DishOptionsResponse(dish=request.dish, status="recipe_not_found", message=
            "I couldn't find a matching source recipe to verify its ingredients. Try a simpler dish name, or look for restaurant menus.")
