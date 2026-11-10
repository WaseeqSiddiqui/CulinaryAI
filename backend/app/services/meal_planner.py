from __future__ import annotations

import re
from typing import Any

from app.models.schemas import (
    CookingStep,
    GeneratePlanRequest,
    GeneratePlanResponse,
    Ingredient,
    InstructionResponse,
    MealPlanRecipe,
    PantryItemInput,
)

from .recipe_repository import RecipeRetriever, RetrievedRecipe


class MealPlannerService:
    def __init__(self, repository: RecipeRetriever) -> None:
        self.repository = repository

    def generate_plan(self, request: GeneratePlanRequest) -> GeneratePlanResponse:
        pantry_names = [item.name for item in request.pantry_items]
        query_parts = (
            [request.question] + pantry_names + request.dietary_preferences
        )
        query = " ".join(query_parts) or "balanced easy meal"
        candidates = self.repository.search(query, limit=len(self.repository.recipes))
        candidates = [
            candidate
            for candidate in candidates
            if self._matches_filters(candidate.recipe, request)
        ]
        if request.pantry_first and pantry_names:
            candidates = [
                candidate
                for candidate in candidates
                if any(
                    self._ingredient_available(ingredient, request.pantry_items)
                    for ingredient in self._scaled_ingredient_dicts(
                        candidate.recipe, request.servings
                    )
                )
            ]
        candidates.sort(
            key=lambda candidate: self._combined_score(
                candidate, request.pantry_items, request
            ),
            reverse=True,
        )
        meals = [
            self._to_plan_recipe(candidate, request.pantry_items, request.servings)
            for candidate in candidates[: request.meal_count]
        ]
        return GeneratePlanResponse(
            meals=meals,
            pantry_item_count=len(request.pantry_items),
            retrieval_method=self.repository.retrieval_method,
            pantry_checked=True,
            requested_servings=request.servings,
            target_calories_per_meal=self._calorie_target(request),
        )

    def instructions(self, recipe_id: str, servings: int) -> InstructionResponse:
        recipe = self.repository.get(recipe_id)
        if recipe is None:
            raise KeyError(recipe_id)
        return InstructionResponse(
            recipe_id=recipe["recipe_id"],
            recipe_name=recipe["name"],
            servings=servings,
            ingredients_required=self._scaled_ingredients(recipe, servings),
            steps=self._steps_with_ingredients(recipe, servings),
        )

    def _to_plan_recipe(
        self,
        candidate: RetrievedRecipe,
        pantry_items: list[PantryItemInput],
        servings: int,
    ) -> MealPlanRecipe:
        recipe = candidate.recipe
        scaled = self._scaled_ingredient_dicts(recipe, servings)
        ingredient_names = [ingredient["name"] for ingredient in scaled]
        available = [
            ingredient["name"]
            for ingredient in scaled
            if self._ingredient_available(ingredient, pantry_items)
        ]
        missing = [
            ingredient for ingredient in ingredient_names if ingredient not in available
        ]
        match = round(100 * len(available) / len(ingredient_names))
        return MealPlanRecipe(
            recipe_id=recipe["recipe_id"],
            name=recipe["name"],
            cuisine=recipe.get("cuisine", "International"),
            cook_time_minutes=recipe["cook_time_minutes"],
            servings=servings,
            pantry_match_percent=match,
            retrieval_score=round(candidate.score, 4),
            ingredients_required=self._scaled_ingredients(recipe, servings),
            available_ingredients=available,
            missing_ingredients=missing,
            steps=self._steps_with_ingredients(recipe, servings),
            source=recipe["source"],
            calories_per_serving=int(recipe.get("calories_per_serving", 0)),
        )

    def _combined_score(
        self,
        candidate: RetrievedRecipe,
        pantry_items: list[PantryItemInput],
        request: GeneratePlanRequest,
    ) -> float:
        ingredients = candidate.recipe["ingredients_required"]
        scaled = self._scaled_ingredient_dicts(
            candidate.recipe, request.servings
        )
        pantry_match = sum(
            self._ingredient_available(ingredient, pantry_items)
            for ingredient in scaled
        ) / len(scaled)
        normalized_retrieval = max(0.0, candidate.score)
        target = self._calorie_target(request)
        recipe_calories = int(candidate.recipe.get("calories_per_serving", 0))
        calorie_score = 0.0
        if target and recipe_calories:
            calorie_score = max(
                0.0, 1.0 - abs(recipe_calories - target) / max(target, 1)
            )
        return pantry_match * 0.7 + normalized_retrieval * 0.15 + calorie_score * 0.15

    @staticmethod
    def _calorie_target(request: GeneratePlanRequest) -> int | None:
        daily = request.target_calories_per_person_per_day
        if daily is None:
            return None
        return round(daily / request.meals_per_day)

    @staticmethod
    def _matches_filters(
        recipe: dict[str, Any], request: GeneratePlanRequest
    ) -> bool:
        if (
            request.max_cook_time_minutes is not None
            and recipe["cook_time_minutes"] > request.max_cook_time_minutes
        ):
            return False
        tags = {tag.lower() for tag in recipe.get("dietary_tags", [])}
        if not all(preference in tags for preference in request.dietary_preferences):
            return False
        ingredient_text = " ".join(
            ingredient["name"].lower()
            for ingredient in recipe.get("ingredients_required", [])
        )
        return not any(
            avoid in ingredient_text for avoid in request.avoid_ingredients
        )

    @staticmethod
    def _normalize(value: str) -> set[str]:
        tokens = re.findall(r"[a-z0-9]+", value.lower())
        return {token[:-1] if token.endswith("s") else token for token in tokens}

    @classmethod
    def _has_ingredient(cls, required: str, pantry_names: list[str]) -> bool:
        required_tokens = cls._normalize(required)
        return any(required_tokens & cls._normalize(name) for name in pantry_names)

    _UNIT_INFO = {
        "g": ("mass", 1.0),
        "kg": ("mass", 1000.0),
        "ml": ("volume", 1.0),
        "l": ("volume", 1000.0),
        "tsp": ("volume", 5.0),
        "tbsp": ("volume", 15.0),
        "cup": ("volume", 240.0),
        "pcs": ("count", 1.0),
        "dozen": ("count", 12.0),
    }
    _DENSITIES = {
        "milk": 1.03,
        "olive oil": 0.91,
        "cooking oil": 0.92,
        "oil": 0.92,
        "mustard sauce": 1.02,
        "soy sauce": 1.16,
        "vinegar": 1.01,
        "heavy cream": 0.99,
    }

    @staticmethod
    def _unit(value: str) -> str:
        normalized = value.strip().lower()
        aliases = {
            "gram": "g", "grams": "g", "kilogram": "kg", "kilograms": "kg",
            "milliliter": "ml", "milliliters": "ml", "millilitre": "ml",
            "millilitres": "ml", "liter": "l", "liters": "l",
            "litre": "l", "litres": "l", "teaspoon": "tsp",
            "teaspoons": "tsp", "tablespoon": "tbsp", "tablespoons": "tbsp",
            "cups": "cup", "pc": "pcs", "piece": "pcs", "pieces": "pcs",
            "clove": "pcs", "cloves": "pcs",
        }
        return aliases.get(normalized, normalized)

    @classmethod
    def _density(cls, ingredient_name: str) -> float | None:
        normalized = ingredient_name.strip().lower()
        return next(
            (
                density
                for name, density in cls._DENSITIES.items()
                if name in normalized or normalized in name
            ),
            None,
        )

    @classmethod
    def _convert(
        cls, quantity: float, from_unit: str, to_unit: str, ingredient_name: str
    ) -> float | None:
        source = cls._UNIT_INFO.get(cls._unit(from_unit))
        target = cls._UNIT_INFO.get(cls._unit(to_unit))
        if source is None or target is None:
            return None
        source_dimension, source_factor = source
        target_dimension, target_factor = target
        base = quantity * source_factor
        if source_dimension == target_dimension:
            return base / target_factor
        if {source_dimension, target_dimension} == {"mass", "volume"}:
            density = cls._density(ingredient_name)
            if density is None:
                return None
            converted = base / density if source_dimension == "mass" else base * density
            return converted / target_factor
        return None

    @classmethod
    def _ingredient_available(
        cls, required: dict[str, Any], pantry_items: list[PantryItemInput]
    ) -> bool:
        available = 0.0
        for item in pantry_items:
            if not cls._has_ingredient(required["name"], [item.name]):
                continue
            converted = cls._convert(
                item.quantity, item.unit, required["unit"], required["name"]
            )
            if converted is not None:
                available += converted
        return available + 1e-6 >= float(required["quantity"])

    @staticmethod
    def _scaled_ingredient_dicts(
        recipe: dict[str, Any], servings: int
    ) -> list[dict[str, Any]]:
        factor = servings / recipe["servings"]
        return [
            {
                "name": ingredient["name"],
                "quantity": round(ingredient["quantity"] * factor, 2),
                "unit": ingredient["unit"],
            }
            for ingredient in recipe["ingredients_required"]
        ]

    @staticmethod
    def _scaled_ingredients(
        recipe: dict[str, Any], servings: int
    ) -> list[Ingredient]:
        factor = servings / recipe["servings"]
        return [
            Ingredient(
                name=ingredient["name"],
                quantity=round(ingredient["quantity"] * factor, 2),
                unit=ingredient["unit"],
            )
            for ingredient in recipe["ingredients_required"]
        ]

    @classmethod
    def _steps_with_ingredients(
        cls, recipe: dict[str, Any], servings: int
    ) -> list[CookingStep]:
        raw_steps = recipe["steps"]
        if not raw_steps:
            return []
        allocations: list[list[dict[str, Any]]] = [[] for _ in raw_steps]
        for ingredient in cls._scaled_ingredient_dicts(recipe, servings):
            required_tokens = cls._normalize(ingredient["name"])
            target = 0
            for index, step in enumerate(raw_steps):
                if required_tokens & cls._normalize(step["instruction"]):
                    target = index
                    break
            allocations[target].append(ingredient)
        return [
            CookingStep(
                **step,
                ingredients_required=[
                    Ingredient(**ingredient) for ingredient in allocations[index]
                ],
            )
            for index, step in enumerate(raw_steps)
        ]
