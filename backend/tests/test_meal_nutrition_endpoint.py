import io
from unittest.mock import patch

from fastapi.testclient import TestClient
from PIL import Image

from app.main import app, vision_service
from app.models.vision_schemas import MealNutritionEstimate


def _image() -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", (80, 80), color="orange").save(buffer, format="JPEG")
    return buffer.getvalue()


def test_meal_scan_returns_structured_nutrition() -> None:
    estimate = MealNutritionEstimate(
        dish_name="Chicken rice",
        portion_description="one plate",
        calories=540,
        protein_grams=38,
        carbohydrate_grams=62,
        fat_grams=14,
        fiber_grams=4,
        confidence=0.82,
        assumptions=["medium serving"],
    )
    with patch.object(vision_service, "analyze_meal", return_value=estimate):
        response = TestClient(app).post(
            "/analyze-meal",
            files={"file": ("meal.jpg", _image(), "image/jpeg")},
            data={"user_id": "test-user"},
        )

    assert response.status_code == 200
    assert response.json()["dish_name"] == "Chicken rice"
    assert response.json()["protein_grams"] == 38
