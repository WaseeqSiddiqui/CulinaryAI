from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

from .embedding_service import HashEmbeddingService


@dataclass(frozen=True)
class RetrievedRecipe:
    recipe: dict[str, Any]
    score: float


class RecipeRetriever(Protocol):
    """Stable seam for the upcoming vector/RAG recipe repository."""

    @property
    def recipes(self) -> list[dict[str, Any]]: ...

    @property
    def retrieval_method(self) -> str: ...

    def get(self, recipe_id: str) -> dict[str, Any] | None: ...

    def search(self, query: str, limit: int = 5) -> list[RetrievedRecipe]: ...


class VerifiedRecipeRepository:
    def __init__(
        self,
        data_path: Path | None = None,
        embedder: HashEmbeddingService | None = None,
    ) -> None:
        self.data_path = data_path or (
            Path(__file__).resolve().parents[1] / "data" / "verified_recipes.json"
        )
        self.embedder = embedder or HashEmbeddingService()
        self._recipes = self._load()
        self._vectors = {
            recipe["recipe_id"]: self.embedder.embed(self._document_text(recipe))
            for recipe in self._recipes
        }

    @property
    def recipes(self) -> list[dict[str, Any]]:
        return list(self._recipes)

    @property
    def retrieval_method(self) -> str:
        return "verified-recipe-hash-embedding-v1"

    def get(self, recipe_id: str) -> dict[str, Any] | None:
        return next(
            (recipe for recipe in self._recipes if recipe["recipe_id"] == recipe_id),
            None,
        )

    def search(self, query: str, limit: int = 5) -> list[RetrievedRecipe]:
        query_vector = self.embedder.embed(query)
        ranked = [
            RetrievedRecipe(
                recipe=recipe,
                score=self.embedder.similarity(
                    query_vector,
                    self._vectors[recipe["recipe_id"]],
                ),
            )
            for recipe in self._recipes
        ]
        ranked.sort(key=lambda result: result.score, reverse=True)
        return ranked[:limit]

    def _load(self) -> list[dict[str, Any]]:
        with self.data_path.open("r", encoding="utf-8") as file:
            payload = json.load(file)
        recipes = payload.get("recipes", [])
        if not recipes:
            raise ValueError("verified recipe dataset is empty")
        required = {
            "recipe_id",
            "name",
            "ingredients_required",
            "steps",
            "source",
        }
        for recipe in recipes:
            missing = required.difference(recipe)
            if missing:
                raise ValueError(
                    f"recipe {recipe.get('recipe_id', '<unknown>')} misses {missing}"
                )
        return recipes

    @staticmethod
    def _document_text(recipe: dict[str, Any]) -> str:
        ingredients = " ".join(
            ingredient["name"] for ingredient in recipe["ingredients_required"]
        )
        tags = " ".join(recipe.get("tags", []))
        dietary = " ".join(recipe.get("dietary_tags", []))
        return " ".join(
            [recipe["name"], recipe.get("cuisine", ""), ingredients, tags, dietary]
        )
