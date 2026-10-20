from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health_reports_the_verified_recipe_index() -> None:
    response = client.get("/health")

    data = response.json()
    assert data["status"] == "ok"
    assert data["indexed_recipes"] >= 6


def test_generate_plan_returns_a_pantry_aware_meal() -> None:
    response = client.post(
        "/generate-plan",
        json={
            "pantry_items": [
                {"name": "eggs", "quantity": 6, "unit": "pcs"},
                {"name": "spinach", "quantity": 150, "unit": "g"},
                {"name": "onion", "quantity": 1, "unit": "pcs"},
            ],
            "servings": 2,
            "meal_count": 1,
            "dietary_preferences": ["vegetarian"],
            "max_cook_time_minutes": 30,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["meals"][0]["recipe_id"] == "rec_frittata"
    assert payload["retrieval_method"] == "verified-recipe-hash-embedding-v1"


def test_unknown_recipe_instructions_return_not_found() -> None:
    response = client.post(
        "/generate-instructions",
        json={"recipe_id": "does-not-exist", "servings": 4},
    )

    assert response.status_code == 404
    assert response.json()["detail"] == "Recipe not found"
