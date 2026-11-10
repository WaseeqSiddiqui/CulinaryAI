from datetime import date

from fastapi.testclient import TestClient
import httpx
import pytest

import app.main as main
from app.models.recipe_discovery import RecipeDiscoveryRequest
from app.models.schemas import PantryItemInput
from app.services.live_recipe_discovery import LiveRecipeDiscoveryService, RecipeProviderUnavailable, TheMealDBClient
from app.services.recipe_inventory import canonical_name, check_ingredients, parse_measure, plan_date


def recipe(recipe_id, name, ingredients):
    record = {"idMeal": recipe_id, "strMeal": name, "strArea": "International", "strCategory": "Vegetarian", "strMealThumb": "https://www.themealdb.com/images/test.jpg"}
    for index, (ingredient, measure) in enumerate(ingredients, 1):
        record[f"strIngredient{index}"] = ingredient
        record[f"strMeasure{index}"] = measure
    return record


EGGS = recipe("100", "Egg and onion bowl", [("Eggs", "4"), ("Onions", "1"), ("Olive Oil", "1 tbsp")])
PASTA = recipe("101", "Tomato pasta", [("Pasta", "200g"), ("Tomatoes", "2"), ("Olive Oil", "1 tbsp")])
SALT_ONLY_MATCH = recipe("102", "Chicken dinner", [("Chicken", "500g"), ("Salt", "1 tsp")])


class Provider:
    def __init__(self, records=None):
        self.records = records if records is not None else [EGGS, PASTA, SALT_ONLY_MATCH]
        self.searches = []

    def search_ingredient(self, name):
        self.searches.append(name)
        return [{"idMeal": record["idMeal"], "strMeal": record["strMeal"]} for record in self.records]

    def search_name(self, name):
        return []

    def lookup(self, recipe_id):
        return next((record for record in self.records if record["idMeal"] == recipe_id), None)


def pantry(name, quantity, unit="pcs", expiry=None):
    return PantryItemInput(name=name, quantity=quantity, unit=unit, expiry_date=expiry)


def request(items, **kwargs):
    return RecipeDiscoveryRequest(pantry_items=items, reference_date=date(2026, 10, 30), **kwargs)


def test_results_change_with_real_inventory_and_never_use_a_spice_only_match():
    service = LiveRecipeDiscoveryService(Provider())
    first = service.discover(request([pantry("Eggs", 6), pantry("Onion", 2), pantry("Olive Oil", 30, "ml"), pantry("Salt", 2, "tsp")]))
    assert [meal.name for meal in first.meals] == ["Egg and onion bowl"]
    assert first.meals[0].can_cook_now
    assert first.meals[0].pantry_match_percent == 100
    assert first.meals[0].servings is None
    assert first.meals[0].cook_time_minutes is None
    assert first.meals[0].source_url == "https://www.themealdb.com/meal.php?c=100"
    second = service.discover(request([pantry("Pasta", 0.3, "kg"), pantry("Tomatoes", 4), pantry("Olive Oil", 30, "ml")]))
    assert [meal.name for meal in second.meals] == ["Tomato pasta"]
    assert second.meals[0].can_cook_now


def test_shortages_and_untracked_staples_do_not_claim_cookable():
    response = LiveRecipeDiscoveryService(Provider([EGGS])).discover(request([pantry("Eggs", 2), pantry("Onion", 1)]))
    meal = response.meals[0]
    assert not meal.can_cook_now
    eggs, _, oil = meal.ingredients
    assert eggs.status == "insufficient"
    assert eggs.missing_quantity == 2
    assert oil.status == "missing"


def test_shared_aromatics_do_not_justify_a_missing_main_food():
    frog = recipe("105", "Frog legs with garlic butter", [("Frog Legs", "500g"), ("Garlic", "2 cloves"), ("Butter", "20g")])
    result = LiveRecipeDiscoveryService(Provider([frog])).discover(request([pantry("Garlic", 5), pantry("Butter", 100, "g")]))
    assert result.meals == []


def test_named_recipe_request_does_not_return_an_unrelated_pantry_meal():
    response = LiveRecipeDiscoveryService(Provider([EGGS, PASTA])).discover(request([pantry("Eggs", 6), pantry("Onion", 2), pantry("Olive Oil", 1, "l")], question="Give me a chicken recipe"))
    assert response.meals == []


def test_explicit_without_ingredient_is_respected():
    response = LiveRecipeDiscoveryService(Provider([EGGS])).discover(request([pantry("Eggs", 6), pantry("Onion", 2), pantry("Olive Oil", 1, "l")], question="A recipe without eggs"))
    assert response.meals == []


def test_duplicate_recipe_rows_cannot_spend_the_same_stock_twice():
    checks = check_ingredients([("Eggs", "2"), ("Egg", "2")], [pantry("Eggs", 3)])
    assert [check.status for check in checks] == ["available", "insufficient"]
    assert checks[1].missing_quantity == 1


def test_unknown_measures_and_incompatible_units_need_confirmation():
    checks = check_ingredients([("Salt", "to taste"), ("Milk", "1 cup"), ("Tomato", "500g")], [pantry("Salt", 20, "g"), pantry("Milk", 1, "l"), pantry("Tomatoes", 3)])
    assert all(check.status == "check_quantity" for check in checks)
    assert checks[0].quantity is None


def test_unitless_non_countable_food_is_not_assumed_to_be_pieces():
    checks = check_ingredients([("Salt", "0.5"), ("Rice", "2")], [pantry("Salt", 1), pantry("Rice", 3)])
    assert all(check.status == "check_quantity" for check in checks)
    assert all(check.quantity is None for check in checks)


def test_unknown_extra_stock_is_not_reported_as_a_definite_shortage():
    checks = check_ingredients([("Milk", "500ml")], [pantry("Milk", 100, "ml"), pantry("Milk", 1, "pack")])
    assert checks[0].status == "check_quantity"
    assert checks[0].missing_quantity is None


@pytest.mark.parametrize(("measure", "expected"), [("1 1/2 tbsp", (1.5, "tbsp")), ("½ tsp", (0.5, "tsp")), ("250g", (250, "g")), ("2", (2, "pcs")), ("2x400g", (None, "")), ("1-2 cups", (None, "")), ("a pinch", (None, ""))])
def test_quantity_parser_preserves_uncertainty(measure, expected):
    assert parse_measure(measure) == expected


def test_food_forms_are_not_matched_by_a_shared_word():
    checks = check_ingredients([("Olive Oil", "1 tbsp"), ("Milk", "200ml"), ("Chicken Breast", "200g")], [pantry("Coconut Oil", 1, "l"), pantry("Milk Powder", 1, "kg"), pantry("Chicken Wings", 1, "kg")])
    assert all(check.status == "missing" for check in checks)
    assert canonical_name("Garlic Cloves") == canonical_name("Garlic")


def test_selected_day_excludes_ingredients_that_expire_before_that_day():
    provider = Provider([EGGS])
    response = LiveRecipeDiscoveryService(provider).discover(request([pantry("Eggs", 6, expiry=date(2026, 10, 30)), pantry("Onion", 1), pantry("Olive Oil", 1, "l")], question="What can I cook tomorrow?"))
    assert response.planning_date == date(2026, 10, 31)
    assert response.excluded_expired_items == ["Eggs"]
    assert response.pantry_item_count == 2
    assert response.meals == []
    assert "current stock" in response.message


@pytest.mark.parametrize(("question", "expected"), [("today", date(2026, 10, 30)), ("next Friday", date(2026, 11, 6)), ("Sunday", date(2026, 11, 1)), ("in 3 days", date(2026, 11, 2)), ("on 2026-12-10", date(2026, 12, 10))])
def test_requested_date_resolution(question, expected):
    assert plan_date(request([], question=question)) == expected


def test_empty_or_expired_pantry_does_not_call_the_provider():
    provider = Provider()
    response = LiveRecipeDiscoveryService(provider).discover(request([pantry("Eggs", 0), pantry("Pasta", 200, "g", date(2026, 10, 29))]))
    assert response.meals == []
    assert provider.searches == []


def test_dietary_and_allergen_filters_apply_to_complete_external_ingredients():
    chicken = recipe("103", "Chicken omelette", [("Eggs", "2"), ("Chicken", "100g"), ("Onion", "1")])
    nuts = recipe("104", "Peanut eggs", [("Eggs", "2"), ("Peanut Butter", "1 tbsp")])
    service = LiveRecipeDiscoveryService(Provider([EGGS, chicken, nuts]))
    response = service.discover(request([pantry("Eggs", 6), pantry("Onion", 2), pantry("Olive Oil", 1, "l")], dietary_preferences=["vegetarian"], avoid_ingredients=["nuts"]))
    assert [meal.name for meal in response.meals] == ["Egg and onion bowl"]


def test_provider_is_cached_but_inventory_is_rechecked_on_every_request():
    calls = []
    def transport(req):
        calls.append(req.url.path)
        if "filter.php" in req.url.path:
            return httpx.Response(200, json={"meals": [{"idMeal": "100", "strMeal": "Egg and onion bowl"}]})
        return httpx.Response(200, json={"meals": [EGGS]})
    provider = TheMealDBClient(client=httpx.Client(transport=httpx.MockTransport(transport)))
    service = LiveRecipeDiscoveryService(provider)
    items = [pantry("Eggs", 6), pantry("Onion", 2), pantry("Olive Oil", 1, "l")]
    assert service.discover(request(items)).meals[0].can_cook_now
    count = len(calls)
    items[0].quantity = 1
    assert not service.discover(request(items)).meals[0].can_cook_now
    assert len(calls) == count


def test_provider_outage_returns_503_without_catalog_fallback(monkeypatch):
    class Offline(Provider):
        def search_ingredient(self, name):
            raise RecipeProviderUnavailable("offline")
    monkeypatch.setattr(main, "recipe_discovery", LiveRecipeDiscoveryService(Offline()))
    response = TestClient(main.app).post("/discover-recipes", json={"pantry_items": [{"name": "Eggs", "quantity": 4, "unit": "pcs"}]})
    assert response.status_code == 503
    assert "no demo recipes" in response.json()["detail"]


def test_discovery_endpoint_returns_provider_attribution_and_inventory_checks(monkeypatch):
    monkeypatch.setattr(main, "recipe_discovery", LiveRecipeDiscoveryService(Provider([EGGS])))
    response = TestClient(main.app).post("/discover-recipes", json={"reference_date": "2026-10-30", "question": "What can I cook today?", "pantry_items": [{"name": "Eggs", "quantity": 4, "unit": "pcs"}, {"name": "Onion", "quantity": 1, "unit": "pcs"}, {"name": "Olive Oil", "quantity": 15, "unit": "ml"}]})
    assert response.status_code == 200
    payload = response.json()
    assert payload["retrieval_method"] == "themealdb-live-ingredient-search"
    assert payload["planning_date"] == "2026-10-30"
    assert payload["meals"][0]["can_cook_now"]
    assert payload["meals"][0]["ingredients"][0]["status"] == "available"
