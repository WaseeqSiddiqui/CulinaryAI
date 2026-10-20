"""
Vector Store for CulinaryAI RAG pipeline.

Uses ChromaDB as the local vector database and Gemini text-embedding-004
for generating real semantic embeddings of recipes.

On first startup, all recipes from verified_recipes.json are indexed.
Subsequent startups reuse the persisted ChromaDB collection (fast).
"""
from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

import chromadb
from chromadb.utils import embedding_functions

logger = logging.getLogger(__name__)

# Gemini embedding model — free tier, 768 dimensions
_EMBEDDING_MODEL = "models/text-embedding-004"
_COLLECTION_NAME = "culinaryai_recipes"
# Persist DB inside the backend folder so it survives restarts
_CHROMA_PATH = Path(__file__).resolve().parents[2] / ".chroma_db"
_RECIPES_PATH = Path(__file__).resolve().parents[1] / "data" / "verified_recipes.json"


def _build_document(recipe: dict[str, Any]) -> str:
    """Create a rich text document from a recipe for embedding."""
    ingredient_names = ", ".join(
        i["name"] for i in recipe.get("ingredients_required", [])
    )
    step_text = " ".join(
        s["instruction"] for s in recipe.get("steps", [])
    )
    tags = " ".join(recipe.get("tags", []))
    dietary = " ".join(recipe.get("dietary_tags", []))
    return (
        f"Recipe: {recipe['name']}. "
        f"Cuisine: {recipe.get('cuisine', '')}. "
        f"Tags: {tags}. "
        f"Dietary: {dietary}. "
        f"Ingredients: {ingredient_names}. "
        f"Cooking time: {recipe.get('cook_time_minutes', '?')} minutes. "
        f"Steps: {step_text}"
    )


def _load_recipes() -> list[dict[str, Any]]:
    with _RECIPES_PATH.open("r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("recipes", [])


class RecipeVectorStore:
    """
    ChromaDB-backed vector store for recipe retrieval.

    Uses Google Gemini text-embedding-004 for real semantic embeddings.
    Falls back to ChromaDB's default embedding if no GEMINI_API_KEY is set.
    """

    def __init__(self) -> None:
        self._client = chromadb.PersistentClient(path=str(_CHROMA_PATH))
        self._embedding_fn = self._build_embedding_fn()
        self._collection = self._client.get_or_create_collection(
            name=_COLLECTION_NAME,
            embedding_function=self._embedding_fn,
            metadata={"hnsw:space": "cosine"},
        )
        self._recipes: dict[str, dict[str, Any]] = {}
        self._ensure_indexed()

    def _build_embedding_fn(self):
        """Use Gemini embeddings if API key present, else default."""
        api_key = os.getenv("GEMINI_API_KEY", "")
        if api_key and api_key != "your_gemini_api_key_here":
            try:
                from chromadb.utils.embedding_functions import GoogleGenerativeAiEmbeddingFunction
                logger.info("✅ Using Gemini text-embedding-004 for RAG vector store")
                return GoogleGenerativeAiEmbeddingFunction(
                    api_key=api_key,
                    model_name=_EMBEDDING_MODEL,
                )
            except Exception as exc:
                logger.warning("⚠️  Gemini embedding unavailable (%s). Using default.", exc)
        logger.warning("⚠️  No GEMINI_API_KEY — using ChromaDB default embeddings (lower quality)")
        return embedding_functions.DefaultEmbeddingFunction()

    def _ensure_indexed(self) -> None:
        """Index all recipes if collection is empty or stale."""
        recipes = _load_recipes()
        for recipe in recipes:
            self._recipes[recipe["recipe_id"]] = recipe

        existing_ids = set(self._collection.get()["ids"])
        recipe_ids = {r["recipe_id"] for r in recipes}

        to_add = [r for r in recipes if r["recipe_id"] not in existing_ids]
        to_remove = existing_ids - recipe_ids

        if to_remove:
            self._collection.delete(ids=list(to_remove))
            logger.info("🗑️  Removed %d stale recipes from vector store", len(to_remove))

        if to_add:
            self._collection.add(
                ids=[r["recipe_id"] for r in to_add],
                documents=[_build_document(r) for r in to_add],
                metadatas=[
                    {
                        "name": r["name"],
                        "cuisine": r.get("cuisine", ""),
                        "cook_time_minutes": r.get("cook_time_minutes", 0),
                        "calories_per_serving": r.get("calories_per_serving", 0),
                        "tags": ",".join(r.get("tags", [])),
                        "dietary_tags": ",".join(r.get("dietary_tags", [])),
                    }
                    for r in to_add
                ],
            )
            logger.info("✅ Indexed %d new recipes into ChromaDB vector store", len(to_add))
        else:
            logger.info("✅ Vector store up-to-date (%d recipes)", len(recipes))

    def search(
        self,
        query: str,
        n_results: int = 5,
        dietary_filter: list[str] | None = None,
        max_cook_time: int | None = None,
    ) -> list[dict[str, Any]]:
        """
        Semantic search over recipes using Gemini embeddings.

        Returns list of recipe dicts enriched with a '_similarity_score' field.
        """
        # Retrieve a broader candidate pool to allow robust post-filtering
        candidate_count = min(max(n_results * 4, 12), self._collection.count())
        try:
            results = self._collection.query(
                query_texts=[query],
                n_results=candidate_count,
                include=["documents", "metadatas", "distances"],
            )
        except Exception as exc:
            logger.error("Vector search failed: %s", exc)
            return []

        retrieved: list[dict[str, Any]] = []
        ids = results["ids"][0] if results.get("ids") else []
        distances = results["distances"][0] if results.get("distances") else []

        for recipe_id, distance in zip(ids, distances):
            recipe = self._recipes.get(recipe_id)
            if recipe is None:
                continue
            # Apply dietary filter post-retrieval (exact match on recipe tags)
            if dietary_filter:
                recipe_dietary = {t.lower() for t in recipe.get("dietary_tags", [])}
                if not all(pref.lower() in recipe_dietary for pref in dietary_filter):
                    continue
            # Apply cook time filter post-retrieval
            if max_cook_time and recipe.get("cook_time_minutes", 0) > max_cook_time:
                continue
            # Convert cosine distance to similarity score (0-1)
            similarity = 1.0 - distance
            retrieved.append({**recipe, "_similarity_score": round(similarity, 4)})
            if len(retrieved) >= n_results:
                break

        # If strict cook time filter eliminated all recipes, relax the threshold by 15 mins
        if max_cook_time and not retrieved:
            relaxed_time = max_cook_time + 15
            for recipe_id, distance in zip(ids, distances):
                recipe = self._recipes.get(recipe_id)
                if recipe is None:
                    continue
                if dietary_filter:
                    recipe_dietary = {t.lower() for t in recipe.get("dietary_tags", [])}
                    if not all(pref.lower() in recipe_dietary for pref in dietary_filter):
                        continue
                if recipe.get("cook_time_minutes", 0) <= relaxed_time:
                    similarity = 1.0 - distance
                    retrieved.append({**recipe, "_similarity_score": round(similarity, 4)})
                    if len(retrieved) >= n_results:
                        break

        return retrieved

    def get_recipe(self, recipe_id: str) -> dict[str, Any] | None:
        """Get a single recipe by ID."""
        return self._recipes.get(recipe_id)

    def get_all_recipes(self) -> list[dict[str, Any]]:
        """Return all indexed recipes."""
        return list(self._recipes.values())

    @property
    def recipe_count(self) -> int:
        return len(self._recipes)
