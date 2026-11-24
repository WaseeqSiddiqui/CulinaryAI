from datetime import date

import httpx
import pytest
from fastapi.testclient import TestClient

import app.main as main
from app.models.dish_options import DishOptionsRequest
from app.models.recipe_discovery import RecipeDiscoveryRequest
from app.models.schemas import PantryItemInput
from app.services.dish_options import DishOptionsService
from app.services.live_recipe_discovery import LiveRecipeDiscoveryService
from app.services.spoonacular_recipes import RecipeProviderUnavailable, SpoonacularRecipes


def recipe(recipe_id=12, title="Pakistani Chicken Karahi", source_url="https://publisher.example/chicken-karahi"):
    return {
        "id": recipe_id, "title": title, "sourceUrl": source_url, "sourceName": "Example Publisher",
        "image": "https://publisher.example/karahi.jpg", "servings": 4, "readyInMinutes": 35,
        "extendedIngredients": [
            {"name": "ground cumin", "amount": 1, "unit": "tsp", "aisle": "Spices and Seasonings"},
            {"name": "chicken", "amount": 500, "unit": "g"},
            {"name": "tomatoes", "amount": 2, "unit": ""},
            {"name": "salt", "amount": 1, "unit": "tsp", "original": "salt to taste"},
        ],
    }


def production(handler):
    def handle(request):
        assert request.url.host == "api.spoonacular.com"
        assert request.headers["x-api-key"] == "test-secret"
        assert "apiKey" not in request.url.params
        return handler(request)
    return SpoonacularRecipes(httpx.Client(transport=httpx.MockTransport(handle)), api_key="test-secret")


class NoLegacy:
    def search_name(self, _):
        pytest.fail("Production search must not call the legacy provider")


def test_production_parses_publisher_recipe_and_rechecks_pantry_and_expiry():
    queries = []
    def handle(request):
        queries.append(dict(request.url.params))
        return httpx.Response(200, json={"results": [recipe(), recipe(13, source_url="https://127.0.0.1/a")]})

    service = LiveRecipeDiscoveryService(NoLegacy(), production(handle))
    day = date(2026, 11, 24)
    request = RecipeDiscoveryRequest(country="Pakistan", reference_date=day, pantry_items=[
        PantryItemInput(name="chicken", quantity=0.8, unit="kg", expiry_date=day),
        PantryItemInput(name="tomatoes", quantity=3, unit="pcs"),
    ])
    result = service.discover(request)
    assert result.provider == "Spoonacular"
    assert len(result.meals) == 1
    meal = result.meals[0]
    assert meal.source == "Example Publisher"
    assert meal.source_url == "https://publisher.example/chicken-karahi"
    assert (meal.servings, meal.cook_time_minutes) == (4, 35)
    assert meal.ingredients[1].status == "available"
    assert meal.ingredients[3].quantity is None
    assert not meal.can_cook_now
    assert any(query.get("query") == "chicken karahi" for query in queries)
    assert any(query.get("includeIngredients") == "chicken" for query in queries)
    next_day = request.model_copy(update={"requested_date": date(2026, 11, 25)})
    after_expiry = service.discover(next_day)
    assert after_expiry.meals == []
    assert after_expiry.excluded_expired_items == ["chicken"]


def test_named_recipe_uses_bulk_ingredients_and_rejects_other_dishes():
    def handle(request):
        if request.url.path.endswith("/complexSearch"):
            assert request.url.params["query"] == "chicken karahi"
            return httpx.Response(200, json={"results": [{"id": 12}, {"id": 13}]})
        assert request.url.params["ids"] == "12,13"
        return httpx.Response(200, json=[recipe(), recipe(13, "Lamb Karahi")])

    result = DishOptionsService(NoLegacy(), production=production(handle)).check(
        DishOptionsRequest(dish="chicken kadahi"),
    )
    assert result.recipe.recipe_id == "spoonacular_12"
    assert result.status == "missing"


def test_provider_quota_error_is_safe_and_does_not_fall_back():
    provider = production(lambda _: httpx.Response(402, text="private upstream error"))
    with pytest.raises(RecipeProviderUnavailable, match="at capacity"):
        DishOptionsService(NoLegacy(), production=provider).check(DishOptionsRequest(dish="karahi"))


def test_paid_source_requires_sign_in_before_upstream_calls(monkeypatch):
    def handle(_):
        pytest.fail("Signed-out traffic must not use a paid API call")
    provider = production(handle)
    monkeypatch.setattr(main, "recipe_discovery", LiveRecipeDiscoveryService(NoLegacy(), provider))
    monkeypatch.setattr(main, "dish_options", DishOptionsService(NoLegacy(), production=provider))
    client = TestClient(main.app)
    assert client.post("/discover-recipes", json={}).status_code == 401
    assert client.post("/dish-options", json={"dish": "karahi"}).status_code == 401
