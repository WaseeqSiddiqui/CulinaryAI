"""
Tests for the RAG pipeline: vector store and LangGraph agent.

Run with:
    cd backend
    .\.venv\Scripts\python.exe -m pytest tests/test_rag.py -v
"""
from __future__ import annotations

import pytest

from app.rag.vector_store import RecipeVectorStore, _build_document
from app.rag.langgraph_agent import (
    ChefAgentState,
    _pantry_names,
    _has_ingredient,
    _pantry_match_percent,
    filter_by_pantry,
    parse_intent,
    should_use_rag,
)


# ─────────────────────────────── Fixtures ───────────────────────────────────

@pytest.fixture(scope="module")
def vector_store():
    """Shared vector store instance for all tests (avoids re-indexing)."""
    return RecipeVectorStore()


SAMPLE_PANTRY = [
    {"name": "Chicken", "quantity": 500, "unit": "g"},
    {"name": "Garlic Cloves", "quantity": 6, "unit": "cloves"},
    {"name": "Tomatoes", "quantity": 4, "unit": "pcs"},
    {"name": "Onion", "quantity": 2, "unit": "pcs"},
    {"name": "Cooking Oil", "quantity": 100, "unit": "ml"},
    {"name": "Basmati Rice", "quantity": 300, "unit": "g"},
]


# ─────────────────────────── Vector Store Tests ──────────────────────────────

class TestVectorStore:
    def test_recipes_indexed(self, vector_store):
        """Vector store should have all recipes from the JSON file."""
        assert vector_store.recipe_count >= 20, "Should have at least 20 recipes"

    def test_search_returns_results(self, vector_store):
        """Basic search should return at least 3 results."""
        results = vector_store.search("chicken rice dinner", n_results=5)
        assert len(results) >= 3
        assert all("recipe_id" in r for r in results)

    def test_search_has_similarity_score(self, vector_store):
        """Each search result must have a _similarity_score field."""
        results = vector_store.search("dal makhani butter")
        assert all("_similarity_score" in r for r in results)
        assert all(0.0 <= r["_similarity_score"] <= 1.0 for r in results)

    def test_desi_recipe_retrieval(self, vector_store):
        """Pakistani recipes should rank high for desi queries."""
        results = vector_store.search("Pakistani desi karahi chicken", n_results=5)
        names = [r["name"] for r in results]
        # At least one desi recipe should appear in top 5
        assert any("Karahi" in n or "Biryani" in n or "Keema" in n for n in names), (
            f"Expected desi recipe in top 5, got: {names}"
        )

    def test_pantry_query_retrieval(self, vector_store):
        """Query with pantry items should return relevant recipes."""
        pantry_str = "chicken, garlic, tomatoes, onion, rice"
        results = vector_store.search(f"dinner with {pantry_str}", n_results=5)
        assert len(results) >= 3

    def test_max_cook_time_filter(self, vector_store):
        """Cook time filter should exclude slow recipes."""
        results = vector_store.search("quick meal", n_results=10, max_cook_time=20)
        for recipe in results:
            assert recipe.get("cook_time_minutes", 0) <= 20, (
                f"{recipe['name']} takes {recipe['cook_time_minutes']} min but filter was 20"
            )

    def test_get_recipe_by_id(self, vector_store):
        """get_recipe should return the correct recipe by ID."""
        recipe = vector_store.get_recipe("rec_chicken_karahi")
        assert recipe is not None
        assert recipe["name"] == "Chicken Karahi"

    def test_get_missing_recipe(self, vector_store):
        """get_recipe should return None for unknown IDs."""
        result = vector_store.get_recipe("rec_nonexistent_xyz")
        assert result is None

    def test_build_document_content(self):
        """_build_document should include name, cuisine, tags, ingredients."""
        recipe = {
            "recipe_id": "test",
            "name": "Test Curry",
            "cuisine": "Pakistani",
            "tags": ["dinner"],
            "dietary_tags": ["halal"],
            "ingredients_required": [{"name": "Chicken", "quantity": 500, "unit": "g"}],
            "cook_time_minutes": 30,
            "steps": [{"step_number": 1, "instruction": "Cook chicken."}],
        }
        doc = _build_document(recipe)
        assert "Test Curry" in doc
        assert "Pakistani" in doc
        assert "Chicken" in doc
        assert "halal" in doc


# ──────────────────────────── Intent Tests ───────────────────────────────────

class TestParseIntent:
    def _make_state(self, message: str) -> ChefAgentState:
        return ChefAgentState(
            user_message=message, pantry_items=[],
            intent="", dietary_preferences=[], max_cook_time=None,
            retrieved_recipes=[], pantry_filtered_recipes=[],
            reply="", retrieval_used=False, recipes_found=0,
        )

    def test_recipe_suggestion_intent(self):
        state = self._make_state("What should I cook today?")
        result = parse_intent(state)
        assert result["intent"] == "recipe_suggestion"

    def test_urdu_recipe_intent(self):
        state = self._make_state("Kya banaun aaj?")
        result = parse_intent(state)
        assert result["intent"] == "recipe_suggestion"

    def test_cooking_help_intent(self):
        state = self._make_state("How to make biryani?")
        result = parse_intent(state)
        assert result["intent"] == "cooking_help"

    def test_quick_intent_sets_time(self):
        state = self._make_state("Quick recipe please!")
        result = parse_intent(state)
        assert result["max_cook_time"] == 25

    def test_vegetarian_dietary(self):
        state = self._make_state("Vegetarian dinner ideas?")
        result = parse_intent(state)
        assert "vegetarian" in result["dietary_preferences"]


# ─────────────────────────── Pantry Helper Tests ─────────────────────────────

class TestPantryHelpers:
    def test_pantry_names(self):
        names = _pantry_names(SAMPLE_PANTRY)
        assert "chicken" in names
        assert "garlic cloves" in names

    def test_has_ingredient_exact(self):
        pantry = ["chicken", "garlic cloves", "tomatoes"]
        assert _has_ingredient("Chicken", pantry) is True

    def test_has_ingredient_partial(self):
        pantry = ["garlic cloves"]
        assert _has_ingredient("Garlic", pantry) is True

    def test_missing_ingredient(self):
        pantry = ["chicken", "rice"]
        assert _has_ingredient("Salmon", pantry) is False

    def test_pantry_match_percent_full(self):
        recipe = {
            "ingredients_required": [
                {"name": "Chicken", "quantity": 500, "unit": "g"},
                {"name": "Garlic Cloves", "quantity": 4, "unit": "cloves"},
                {"name": "Tomatoes", "quantity": 3, "unit": "pcs"},
            ]
        }
        pantry = ["chicken", "garlic cloves", "tomatoes"]
        assert _pantry_match_percent(recipe, pantry) == 100

    def test_pantry_match_percent_partial(self):
        recipe = {
            "ingredients_required": [
                {"name": "Chicken", "quantity": 500, "unit": "g"},
                {"name": "Salmon", "quantity": 300, "unit": "g"},
            ]
        }
        pantry = ["chicken"]
        assert _pantry_match_percent(recipe, pantry) == 50


# ─────────────────────────── Graph Routing Tests ─────────────────────────────

class TestGraphRouting:
    def _make_state(self, retrieved: list) -> ChefAgentState:
        return ChefAgentState(
            user_message="test", pantry_items=[],
            intent="recipe_suggestion", dietary_preferences=[],
            max_cook_time=None, retrieved_recipes=retrieved,
            pantry_filtered_recipes=[], reply="",
            retrieval_used=False, recipes_found=0,
        )

    def test_routes_to_filter_when_recipes_found(self):
        state = self._make_state([{"recipe_id": "rec_1", "name": "Test Recipe"}])
        assert should_use_rag(state) == "filter_by_pantry"

    def test_routes_to_fallback_when_no_recipes(self):
        state = self._make_state([])
        assert should_use_rag(state) == "generate_response"


# ─────────────────────────── Filter Node Tests ───────────────────────────────

class TestFilterByPantry:
    def test_filter_ranks_by_combined_score(self):
        """Recipe with higher pantry match should rank higher."""
        recipes = [
            {
                "recipe_id": "r1",
                "name": "Recipe A (no match)",
                "ingredients_required": [{"name": "Salmon", "quantity": 1, "unit": "g"}],
                "_similarity_score": 0.9,
            },
            {
                "recipe_id": "r2",
                "name": "Recipe B (full match)",
                "ingredients_required": [{"name": "Chicken", "quantity": 1, "unit": "g"}],
                "_similarity_score": 0.5,
            },
        ]
        state = ChefAgentState(
            user_message="dinner", pantry_items=SAMPLE_PANTRY,
            intent="recipe_suggestion", dietary_preferences=[],
            max_cook_time=None, retrieved_recipes=recipes,
            pantry_filtered_recipes=[], reply="",
            retrieval_used=False, recipes_found=0,
        )
        result = filter_by_pantry(state)
        ranked = result["pantry_filtered_recipes"]
        # Recipe B (chicken = pantry match) should rank first despite lower similarity
        assert ranked[0]["recipe_id"] == "r2"

    def test_filter_adds_combined_score(self):
        """All results should have _combined_score and _pantry_match_pct fields."""
        recipes = [
            {
                "recipe_id": "r1",
                "name": "Test",
                "ingredients_required": [],
                "_similarity_score": 0.8,
            }
        ]
        state = ChefAgentState(
            user_message="test", pantry_items=[],
            intent="general", dietary_preferences=[],
            max_cook_time=None, retrieved_recipes=recipes,
            pantry_filtered_recipes=[], reply="",
            retrieval_used=False, recipes_found=0,
        )
        result = filter_by_pantry(state)
        assert "_combined_score" in result["pantry_filtered_recipes"][0]
        assert "_pantry_match_pct" in result["pantry_filtered_recipes"][0]
