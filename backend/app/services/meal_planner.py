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
)

from .recipe_repository import RetrievedRecipe, VerifiedRecipeRepository


class MealPlannerService:
    def __init__(self, repository: VerifiedRecipeRepository) -> None:
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
        candidates.sort(
            key=lambda candidate: self._combined_score(candidate, pantry_names),
            reverse=True,
        )
        meals = [
            self._to_plan_recipe(candidate, pantry_names, request.servings)
            for candidate in candidates[: request.meal_count]
        ]
        return GeneratePlanResponse(
            meals=meals,
            pantry_item_count=len(request.pantry_items),
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
            steps=[CookingStep(**step) for step in recipe["steps"]],
        )

    def _to_plan_recipe(
        self,
        candidate: RetrievedRecipe,
        pantry_names: list[str],
        servings: int,
    ) -> MealPlanRecipe:
        recipe = candidate.recipe
        ingredient_names = [
            ingredient["name"] for ingredient in recipe["ingredients_required"]
        ]
        available = [
            ingredient
            for ingredient in ingredient_names
            if self._has_ingredient(ingredient, pantry_names)
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
            steps=[CookingStep(**step) for step in recipe["steps"]],
            source=recipe["source"],
        )

    def _combined_score(
        self,
        candidate: RetrievedRecipe,
        pantry_names: list[str],
    ) -> float:
        ingredients = candidate.recipe["ingredients_required"]
        pantry_match = sum(
            self._has_ingredient(ingredient["name"], pantry_names)
            for ingredient in ingredients
        ) / len(ingredients)
        normalized_retrieval = max(0.0, candidate.score)
        return pantry_match * 0.8 + normalized_retrieval * 0.2

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
        return all(preference in tags for preference in request.dietary_preferences)

    @staticmethod
    def _normalize(value: str) -> set[str]:
        tokens = re.findall(r"[a-z0-9]+", value.lower())
        return {token[:-1] if token.endswith("s") else token for token in tokens}

    @classmethod
    def _has_ingredient(cls, required: str, pantry_names: list[str]) -> bool:
        required_tokens = cls._normalize(required)
        return any(required_tokens & cls._normalize(name) for name in pantry_names)

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
